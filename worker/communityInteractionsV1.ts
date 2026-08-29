import type {
  CommunityCommentMutationV1,
  CommunityCommentPageV1,
  CommunityCommentV1,
  CommunityEngagementSummaryV1,
  CommunityLikeMutationV1,
  PublicContentUserV1,
} from '../src/contracts/communityContract'
import type { ProfileAvatarPresetContract } from '../src/contracts/profileContract'
import { consumePublicAPIQuota } from './publicAPIRateLimit'

const API_VERSION = 1
const DEFAULT_LIMIT = 20
const MAX_LIMIT = 50
const MAX_COMMENT_LENGTH = 280

interface VisitAccessRow {
  id: string
  user_id: string
  visibility: 'private' | 'friends' | 'public'
  profile_visibility: 'private' | 'friends' | 'public'
}

interface CommentRow {
  id: string
  content_type: 'visit'
  content_id: string
  user_id: string
  body: string
  created_at: string
  updated_at: string
  deleted_at: string | null
  server_version: number
  display_name: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract
}

interface RelationshipRow {
  id: string
  requester_id: string
  addressee_id: string
  status: string
  deleted_at: string | null
}

export class CommunityInteractionV1Error extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

export async function handleCommunityInteractionsV1(
  request: Request,
  database: D1Database,
  viewerId: string,
): Promise<CommunityLikeMutationV1 | CommunityCommentPageV1 | CommunityCommentMutationV1> {
  const url = new URL(request.url)
  const likeMatch = url.pathname.match(/^\/api\/v1\/community\/content\/visit\/([^/]+)\/like$/)
  if (likeMatch && (request.method === 'PUT' || request.method === 'DELETE')) {
    await consumePublicAPIQuota(database, viewerId, 'community-like-mutation', 120)
    return mutateLike(database, viewerId, decodedID(likeMatch[1]), request.method === 'PUT')
  }
  const commentsMatch = url.pathname.match(/^\/api\/v1\/community\/content\/visit\/([^/]+)\/comments$/)
  if (commentsMatch && request.method === 'GET') {
    await consumePublicAPIQuota(database, viewerId, 'community-comment-read', 180)
    return readComments(database, viewerId, decodedID(commentsMatch[1]), url)
  }
  if (commentsMatch && request.method === 'POST') {
    await consumePublicAPIQuota(database, viewerId, 'community-comment-create', 20)
    return createComment(database, viewerId, decodedID(commentsMatch[1]), request)
  }
  const deleteMatch = url.pathname.match(/^\/api\/v1\/community\/comments\/([^/]+)$/)
  if (deleteMatch && request.method === 'DELETE') {
    await consumePublicAPIQuota(database, viewerId, 'community-comment-delete', 60)
    return deleteComment(database, viewerId, decodedID(deleteMatch[1]))
  }
  throw new CommunityInteractionV1Error('Community interaction endpoint was not found.', 404)
}

export async function engagementForVisits(
  database: D1Database,
  viewerId: string,
  visitIDs: string[],
): Promise<Map<string, CommunityEngagementSummaryV1>> {
  const uniqueIDs = unique(visitIDs)
  if (!uniqueIDs.length) return new Map()
  const marks = placeholders(uniqueIDs)
  const [likes, comments] = await database.batch([
    database.prepare(`SELECT content_id, COUNT(*) AS count,
        MAX(CASE WHEN user_id = ? THEN 1 ELSE 0 END) AS liked_by_viewer
      FROM content_likes
      WHERE content_type = 'visit' AND deleted_at IS NULL AND content_id IN (${marks})
      GROUP BY content_id`).bind(viewerId, ...uniqueIDs),
    database.prepare(`SELECT content_id, COUNT(*) AS count FROM content_comments
      WHERE content_type = 'visit' AND deleted_at IS NULL AND content_id IN (${marks})
      GROUP BY content_id`).bind(...uniqueIDs),
  ])
  const result = new Map<string, CommunityEngagementSummaryV1>()
  for (const id of uniqueIDs) result.set(id, { likedByViewer: false, likeCount: 0, commentCount: 0 })
  for (const row of likes.results as Array<{ content_id: string; count: number; liked_by_viewer: number }>) {
    result.set(row.content_id, {
      likedByViewer: Number(row.liked_by_viewer) === 1,
      likeCount: Number(row.count),
      commentCount: result.get(row.content_id)?.commentCount ?? 0,
    })
  }
  for (const row of comments.results as Array<{ content_id: string; count: number }>) {
    const current = result.get(row.content_id) ?? { likedByViewer: false, likeCount: 0, commentCount: 0 }
    result.set(row.content_id, { ...current, commentCount: Number(row.count) })
  }
  return result
}

async function mutateLike(
  database: D1Database,
  viewerId: string,
  visitID: string,
  liked: boolean,
): Promise<CommunityLikeMutationV1> {
  await requireReadableVisit(database, viewerId, visitID)
  const id = `like:visit:${visitID}:${viewerId}`
  const existing = await database.prepare(`SELECT deleted_at, server_version FROM content_likes
    WHERE id = ? AND user_id = ? LIMIT 1`).bind(id, viewerId)
    .first<{ deleted_at: string | null; server_version: number }>()
  const duplicate = liked ? existing?.deleted_at === null : !existing || existing.deleted_at !== null
  if (!duplicate) {
    const now = new Date().toISOString()
    if (existing) {
      await database.prepare(`UPDATE content_likes SET deleted_at = ?, updated_at = ?,
        server_version = server_version + 1 WHERE id = ? AND user_id = ?`)
        .bind(liked ? null : now, now, id, viewerId).run()
    } else {
      await database.prepare(`INSERT INTO content_likes (
        id, content_type, content_id, user_id, created_at, updated_at, deleted_at, server_version
      ) VALUES (?, 'visit', ?, ?, ?, ?, NULL, 1)`)
        .bind(id, visitID, viewerId, now, now).run()
    }
  }
  const summary = (await engagementForVisits(database, viewerId, [visitID])).get(visitID)!
  return { apiVersion: API_VERSION, ...summary, duplicate }
}

async function readComments(
  database: D1Database,
  viewerId: string,
  visitID: string,
  url: URL,
): Promise<CommunityCommentPageV1> {
  await requireReadableVisit(database, viewerId, visitID)
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const rows = await database.prepare(`SELECT c.*, p.display_name, p.bio, p.city,
      p.avatar_photo_id, p.avatar_preset_id
    FROM content_comments c
    JOIN user_profiles p ON p.user_id = c.user_id AND p.deleted_at IS NULL
    WHERE c.content_type = 'visit' AND c.content_id = ? AND c.deleted_at IS NULL
      AND (c.created_at < ? OR (c.created_at = ? AND c.id > ?))
    ORDER BY c.created_at DESC, c.id ASC LIMIT ?`)
    .bind(visitID, cursor.createdAt, cursor.createdAt, cursor.id, limit + 1).all<CommentRow>()
  const visible = rows.results.slice(0, limit)
  const items = await commentContracts(database, viewerId, visible)
  return {
    apiVersion: API_VERSION,
    items,
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.created_at, visible.at(-1)!.id)
      : null,
  }
}

async function createComment(
  database: D1Database,
  viewerId: string,
  visitID: string,
  request: Request,
): Promise<CommunityCommentMutationV1> {
  await requireReadableVisit(database, viewerId, visitID)
  const body = await objectBody(request)
  const text = typeof body.body === 'string' ? body.body.trim() : ''
  if (!text || [...text].length > MAX_COMMENT_LENGTH) {
    throw new CommunityInteractionV1Error('评论需为 1 到 280 个字符。', 400)
  }
  const now = new Date().toISOString()
  const id = crypto.randomUUID()
  await database.prepare(`INSERT INTO content_comments (
    id, content_type, content_id, user_id, body, created_at, updated_at, deleted_at, server_version
  ) VALUES (?, 'visit', ?, ?, ?, ?, ?, NULL, 1)`)
    .bind(id, visitID, viewerId, text, now, now).run()
  const row = await commentByID(database, id)
  const [comment] = await commentContracts(database, viewerId, row ? [row] : [])
  if (!comment) throw new CommunityInteractionV1Error('评论没有保存成功。', 500)
  const summary = (await engagementForVisits(database, viewerId, [visitID])).get(visitID)!
  return { apiVersion: API_VERSION, comment, likeCount: summary.likeCount, commentCount: summary.commentCount }
}

async function deleteComment(
  database: D1Database,
  viewerId: string,
  commentID: string,
): Promise<CommunityCommentMutationV1> {
  const existing = await commentByID(database, commentID)
  if (!existing || existing.user_id !== viewerId) {
    throw new CommunityInteractionV1Error('没有找到可删除的评论。', 404)
  }
  if (!existing.deleted_at) {
    const now = new Date().toISOString()
    await database.prepare(`UPDATE content_comments SET deleted_at = ?, updated_at = ?,
      server_version = server_version + 1 WHERE id = ? AND user_id = ?`)
      .bind(now, now, commentID, viewerId).run()
  }
  const row = await commentByID(database, commentID)
  const [comment] = await commentContracts(database, viewerId, row ? [row] : [])
  if (!comment) throw new CommunityInteractionV1Error('评论删除状态无法读取。', 500)
  const summary = (await engagementForVisits(database, viewerId, [existing.content_id])).get(existing.content_id)!
  return { apiVersion: API_VERSION, comment, likeCount: summary.likeCount, commentCount: summary.commentCount }
}

async function requireReadableVisit(database: D1Database, viewerId: string, visitID: string) {
  const row = await database.prepare(`SELECT v.id, v.user_id, v.visibility,
      p.visibility AS profile_visibility
    FROM visits v JOIN user_profiles p ON p.user_id = v.user_id AND p.deleted_at IS NULL
    JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
    WHERE v.id = ? AND v.deleted_at IS NULL LIMIT 1`).bind(visitID).first<VisitAccessRow>()
  if (!row || row.visibility === 'private') {
    throw new CommunityInteractionV1Error('没有找到可互动的公开内容。', 404)
  }
  const owner = row.user_id === viewerId
  const friend = owner || Boolean(await database.prepare(`SELECT id FROM friendships
    WHERE status = 'accepted' AND deleted_at IS NULL AND (
      (requester_id = ? AND addressee_id = ?) OR
      (requester_id = ? AND addressee_id = ?)
    ) LIMIT 1`).bind(viewerId, row.user_id, row.user_id, viewerId).first())
  const permitted = owner || (row.visibility === 'public' && row.profile_visibility === 'public') ||
    (friend && row.profile_visibility !== 'private')
  if (!permitted) throw new CommunityInteractionV1Error('没有找到可互动的公开内容。', 404)
  return row
}

async function commentByID(database: D1Database, id: string) {
  return database.prepare(`SELECT c.*, p.display_name, p.bio, p.city,
      p.avatar_photo_id, p.avatar_preset_id
    FROM content_comments c JOIN user_profiles p ON p.user_id = c.user_id
    WHERE c.id = ? LIMIT 1`).bind(id).first<CommentRow>()
}

async function commentContracts(database: D1Database, viewerId: string, rows: CommentRow[]) {
  if (!rows.length) return []
  const userIDs = unique(rows.map((row) => row.user_id))
  const [friendships, follows] = await database.batch([
    database.prepare(`SELECT id, requester_id, addressee_id, status, deleted_at FROM friendships
      WHERE requester_id = ? OR addressee_id = ?`).bind(viewerId, viewerId),
    database.prepare(`SELECT followed_user_id FROM follows
      WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
  ])
  const friendshipByUser = new Map((friendships.results as unknown as RelationshipRow[])
    .filter((row) => userIDs.includes(row.requester_id === viewerId ? row.addressee_id : row.requester_id))
    .map((row) => [row.requester_id === viewerId ? row.addressee_id : row.requester_id, row]))
  const followed = new Set((follows.results as Array<{ followed_user_id: string }>).map((row) => row.followed_user_id))
  return rows.map((row): CommunityCommentV1 => ({
    apiVersion: API_VERSION,
    id: row.id,
    contentType: row.content_type,
    contentId: row.content_id,
    body: row.body,
    author: userContract(row, friendshipByUser.get(row.user_id), followed.has(row.user_id), viewerId),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    serverVersion: Number(row.server_version),
  }))
}

function userContract(
  row: CommentRow,
  friendship: RelationshipRow | undefined,
  following: boolean,
  viewerId: string,
): PublicContentUserV1 {
  let state: PublicContentUserV1['friendshipState'] = 'none'
  if (friendship && !friendship.deleted_at) {
    if (friendship.status === 'accepted') state = 'friends'
    else if (friendship.status === 'pending') {
      state = friendship.requester_id === viewerId ? 'outgoing_request' : 'incoming_request'
    }
  }
  return {
    userId: row.user_id,
    displayName: row.display_name,
    bio: row.bio.trim() || null,
    city: row.city.trim() || null,
    avatarPhotoId: row.avatar_photo_id,
    avatarPresetId: row.avatar_preset_id ?? 'polar-bear',
    friendshipId: friendship?.id ?? null,
    friendshipState: state,
    isFollowing: following,
  }
}

async function objectBody(request: Request) {
  const value = await request.json().catch(() => null)
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new CommunityInteractionV1Error('Community interaction body is invalid.', 400)
  }
  return value as Record<string, unknown>
}

function decodedID(value: string) {
  const decoded = decodeURIComponent(value).trim()
  if (!decoded || decoded.length > 200) throw new CommunityInteractionV1Error('Community content identifier is invalid.', 400)
  return decoded
}

function pageLimit(url: URL) {
  const value = Number(url.searchParams.get('limit') ?? DEFAULT_LIMIT)
  return Number.isInteger(value) ? Math.min(MAX_LIMIT, Math.max(1, value)) : DEFAULT_LIMIT
}

function encodeCursor(createdAt: string, id: string) {
  return btoa(JSON.stringify({ createdAt, id })).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function decodeCursor(value: string | null) {
  if (!value) return { createdAt: '9999-12-31T23:59:59.999Z', id: '' }
  try {
    const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=')
    const decoded = JSON.parse(atob(padded)) as { createdAt?: unknown; id?: unknown }
    if (typeof decoded.createdAt !== 'string' || !Number.isFinite(Date.parse(decoded.createdAt)) || typeof decoded.id !== 'string') throw new Error()
    return { createdAt: decoded.createdAt, id: decoded.id }
  } catch { throw new CommunityInteractionV1Error('评论游标无效。', 400) }
}

function placeholders(values: unknown[]) { return values.map(() => '?').join(',') }
function unique(values: string[]) { return [...new Set(values)] }
