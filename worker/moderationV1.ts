import type {
  ContentReportRequestV1,
  ContentReportResponseV1,
  ModerationContentTypeV1,
  ModerationReasonV1,
  UserBlockMutationV1,
} from '../src/contracts/releaseSafetyV1'
import { RELEASE_SAFETY_API_VERSION } from '../src/contracts/releaseSafetyV1'
import { consumePublicAPIQuota } from './publicAPIRateLimit'
import type { UGCSafetyCapabilities } from '../src/contracts/releaseSafetyV1'

const contentTypes = new Set<ModerationContentTypeV1>(['visit', 'comment', 'user'])
const reasons = new Set<ModerationReasonV1>([
  'spam', 'harassment', 'hate', 'sexual', 'violence', 'privacy', 'other',
])

export class ModerationV1Error extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message)
    this.name = 'ModerationV1Error'
  }
}

export async function handleModerationV1(
  request: Request,
  database: D1Database,
  viewerID: string,
): Promise<ContentReportResponseV1 | UserBlockMutationV1 | UGCSafetyCapabilities> {
  const url = new URL(request.url)
  if (url.pathname === '/api/v1/community/safety' && request.method === 'GET') {
    await consumePublicAPIQuota(database, viewerID, 'community-safety-read', 180)
    return safetyCapabilities(database, viewerID, url.searchParams.get('type') ?? '', url.searchParams.get('id') ?? '')
  }
  if (url.pathname === '/api/v1/community/reports' && request.method === 'POST') {
    await consumePublicAPIQuota(database, viewerID, 'community-report-create', 20)
    return createReport(database, viewerID, request)
  }
  const blockMatch = url.pathname.match(/^\/api\/v1\/community\/blocks\/([^/]+)$/)
  if (blockMatch && (request.method === 'PUT' || request.method === 'DELETE')) {
    await consumePublicAPIQuota(database, viewerID, 'community-block-mutation', 60)
    return mutateBlock(database, viewerID, decodedID(blockMatch[1]), request.method === 'PUT')
  }
  throw new ModerationV1Error('Moderation endpoint was not found.', 404, 'route_not_found')
}

export async function usersAreBlocked(database: D1Database, viewerID: string, otherID: string) {
  if (viewerID === otherID) return false
  return Boolean(await database.prepare(`SELECT id FROM user_blocks
    WHERE deleted_at IS NULL AND (
      (blocker_user_id = ? AND blocked_user_id = ?) OR
      (blocker_user_id = ? AND blocked_user_id = ?)
    ) LIMIT 1`).bind(viewerID, otherID, otherID, viewerID).first())
}

async function mutateBlock(
  database: D1Database,
  viewerID: string,
  blockedUserID: string,
  blocked: boolean,
): Promise<UserBlockMutationV1> {
  if (viewerID === blockedUserID) throw requestError('不能屏蔽自己。', 400, 'cannot_block_self')
  const target = await database.prepare(`SELECT id FROM users
    WHERE id = ? AND deleted_at IS NULL LIMIT 1`).bind(blockedUserID).first<{ id: string }>()
  if (!target) throw requestError('没有找到这个用户。', 404, 'user_not_found')
  const existing = await database.prepare(`SELECT id, deleted_at FROM user_blocks
    WHERE blocker_user_id = ? AND blocked_user_id = ? LIMIT 1`)
    .bind(viewerID, blockedUserID).first<{ id: string; deleted_at: string | null }>()
  const duplicate = blocked ? existing?.deleted_at === null : !existing || existing.deleted_at !== null
  if (!duplicate) {
    const now = new Date().toISOString()
    if (existing) {
      await database.prepare(`UPDATE user_blocks SET deleted_at = ?, updated_at = ? WHERE id = ?`)
        .bind(blocked ? null : now, now, existing.id).run()
    } else {
      await database.prepare(`INSERT INTO user_blocks (
        id, blocker_user_id, blocked_user_id, created_at, updated_at, deleted_at
      ) VALUES (?, ?, ?, ?, ?, NULL)`).bind(
        `block_${crypto.randomUUID()}`, viewerID, blockedUserID, now, now,
      ).run()
    }
    if (blocked) {
      const pair = [viewerID, blockedUserID].sort()
      await database.batch([
        database.prepare(`UPDATE follows SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?
          WHERE (follower_id = ? AND followed_user_id = ?) OR (follower_id = ? AND followed_user_id = ?)`)
          .bind(now, now, viewerID, blockedUserID, blockedUserID, viewerID),
        database.prepare(`UPDATE friendships SET status = 'removed', deleted_at = COALESCE(deleted_at, ?),
          updated_at = ? WHERE pair_user_a = ? AND pair_user_b = ?`).bind(now, now, pair[0], pair[1]),
      ])
    }
  }
  return { apiVersion: RELEASE_SAFETY_API_VERSION, blockedUserId: blockedUserID, blocked, duplicate }
}

async function createReport(
  database: D1Database,
  viewerID: string,
  request: Request,
): Promise<ContentReportResponseV1> {
  const body = await request.json().catch(() => null) as Partial<ContentReportRequestV1> | null
  const details = typeof body?.details === 'string' ? body.details.trim() : ''
  if (!body || body.apiVersion !== RELEASE_SAFETY_API_VERSION ||
      typeof body.requestId !== 'string' || !/^[0-9a-f-]{36}$/i.test(body.requestId) ||
      typeof body.contentType !== 'string' || !contentTypes.has(body.contentType as ModerationContentTypeV1) ||
      typeof body.contentId !== 'string' || !body.contentId.trim() || body.contentId.length > 200 ||
      typeof body.reason !== 'string' || !reasons.has(body.reason as ModerationReasonV1) || details.length > 500) {
    throw requestError('举报请求无效。', 400, 'invalid_report')
  }
  await requireReportableContent(database, viewerID, body.contentType as ModerationContentTypeV1, body.contentId)
  const fingerprint = await sha256(JSON.stringify({
    contentType: body.contentType, contentId: body.contentId,
    reason: body.reason, details,
  }))
  const existing = await database.prepare(`SELECT id, request_fingerprint FROM content_reports
    WHERE reporter_user_id = ? AND request_id = ? LIMIT 1`).bind(viewerID, body.requestId)
    .first<{ id: string; request_fingerprint: string }>()
  if (existing) {
    if (existing.request_fingerprint !== fingerprint) {
      throw requestError('重复举报请求的内容不一致。', 409, 'idempotency_conflict')
    }
    return { apiVersion: RELEASE_SAFETY_API_VERSION, reportId: existing.id, status: 'pending', duplicate: true }
  }
  const id = `report_${crypto.randomUUID()}`
  const now = new Date().toISOString()
  await database.prepare(`INSERT INTO content_reports (
    id, reporter_user_id, content_type, content_id, reason, details,
    request_id, request_fingerprint, status, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`).bind(
    id, viewerID, body.contentType, body.contentId, body.reason, details,
    body.requestId, fingerprint, now, now,
  ).run()
  return { apiVersion: RELEASE_SAFETY_API_VERSION, reportId: id, status: 'pending', duplicate: false }
}

async function requireReportableContent(
  database: D1Database,
  viewerID: string,
  type: ModerationContentTypeV1,
  id: string,
) {
  const capabilities = await safetyCapabilities(database, viewerID, type, id)
  if (!capabilities.canReport) throw requestError('不能举报自己的内容。', 400, 'cannot_report_self')
}

/** The same visibility/ownership gate serves both the UI and report writes. */
async function safetyCapabilities(database: D1Database, viewerID: string, type: string, id: string): Promise<UGCSafetyCapabilities> {
  if (!contentTypes.has(type as ModerationContentTypeV1) || !id || id.length > 200) {
    throw requestError('内容标识无效。', 400, 'invalid_content')
  }
  let ownerID: string | null = null
  let visitID: string | null = null
  if (type === 'user') {
    ownerID = (await database.prepare(`SELECT id FROM users WHERE id = ? AND deleted_at IS NULL`)
      .bind(id).first<{ id: string }>())?.id ?? null
  } else if (type === 'visit') {
    ownerID = (await database.prepare(`SELECT v.user_id FROM visits v
      JOIN user_profiles p ON p.user_id = v.user_id AND p.deleted_at IS NULL
      WHERE v.id = ? AND v.deleted_at IS NULL AND v.visibility <> 'private' LIMIT 1`)
      .bind(id).first<{ user_id: string }>())?.user_id ?? null
    visitID = id
  } else {
    const comment = await database.prepare(`SELECT user_id, content_id FROM content_comments
      WHERE id = ? AND content_type = 'visit' AND deleted_at IS NULL LIMIT 1`)
      .bind(id).first<{ user_id: string; content_id: string }>()
    ownerID = comment?.user_id ?? null
    visitID = comment?.content_id ?? null
  }
  if (!ownerID) throw requestError('没有找到可举报的内容。', 404, 'content_not_found')
  if (await usersAreBlocked(database, viewerID, ownerID)) throw requestError('内容不可用。', 404, 'content_not_found')
  if (visitID && !(type === 'comment' && ownerID === viewerID)) {
    const visible = await database.prepare(`SELECT v.id FROM visits v
      JOIN user_profiles p ON p.user_id = v.user_id AND p.deleted_at IS NULL
      JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
      WHERE v.id = ? AND v.deleted_at IS NULL AND v.visibility <> 'private'
      AND (v.user_id = ? OR (v.visibility = 'public' AND p.visibility = 'public') OR
        (p.visibility <> 'private' AND EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
          AND f.deleted_at IS NULL AND ((f.requester_id = ? AND f.addressee_id = v.user_id)
            OR (f.addressee_id = ? AND f.requester_id = v.user_id)))))
      AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE b.deleted_at IS NULL AND
        ((b.blocker_user_id = ? AND b.blocked_user_id = v.user_id) OR
         (b.blocked_user_id = ? AND b.blocker_user_id = v.user_id)))`)
      .bind(visitID, viewerID, viewerID, viewerID, viewerID, viewerID).first()
    if (!visible) throw requestError('内容不可用。', 404, 'content_not_found')
  }
  return { ownerID, canReport: ownerID !== viewerID, canBlock: ownerID !== viewerID, canDelete: type === 'comment' && ownerID === viewerID }
}

function decodedID(value: string) {
  const decoded = decodeURIComponent(value).trim()
  if (!decoded || decoded.length > 200) throw requestError('用户标识无效。', 400, 'invalid_user_id')
  return decoded
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function requestError(message: string, status: number, code: string) {
  return new ModerationV1Error(message, status, code)
}
