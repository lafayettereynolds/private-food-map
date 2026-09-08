import {
  normalizeRecommendationPreferenceEventV1,
  normalizeRecommendationPreferencesPushV1,
  RecommendationPreferenceValidationError,
  RECOMMENDATION_PREFERENCES_MAX_BODY_BYTES,
  RECOMMENDATION_PREFERENCES_MAX_EVENTS,
  type RecommendationPreferencesPullResponseV1,
  type RecommendationPreferencesPushResponseV1,
} from '../src/contracts/recommendationPreferencesV1'

interface EventRow { revision: number; event_id: string; payload_json: string; received_at: string }
const ROOT = '/api/v1/recommendation-preferences/'

export class RecommendationPreferencesV1Error extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message)
    this.name = 'RecommendationPreferencesV1Error'
  }
}
const error = (message: string, status: number, code: string) => new RecommendationPreferencesV1Error(message, status, code)

/** caller passes only the verified current account; body/query cannot select
 * an owner. A missing migration/storage failure is never an empty preference. */
export async function handleRecommendationPreferencesV1(
  request: Request, database: D1Database, ownerID: string, now = new Date(),
): Promise<RecommendationPreferencesPullResponseV1 | RecommendationPreferencesPushResponseV1> {
  if (!ownerID.trim()) throw error('请先登录后同步推荐偏好。', 401, 'authentication_required')
  try {
    await requireActiveAccount(database, ownerID)
    const url = new URL(request.url)
    if (url.pathname === `${ROOT}push` && request.method === 'POST') {
      // Compare-only precondition, never an identity source. Prevent a browser
      // cookie/session switch between pull preflight and an outbox upload.
      if (request.headers.get('X-Taste-Map-Preference-Owner') !== ownerID) throw error('账户已切换，请在当前账户重试。', 409, 'account_changed')
      if ([...url.searchParams.keys()].length) throw error('推荐偏好请求参数无效。', 400, 'invalid_request')
      return await push(request, database, ownerID, now)
    }
    if (url.pathname === `${ROOT}pull` && request.method === 'GET') return await pull(url, database, ownerID)
    throw error('没有找到推荐偏好接口。', 404, 'route_not_found')
  } catch (cause) {
    if (cause instanceof RecommendationPreferencesV1Error) throw cause
    if (cause instanceof RecommendationPreferenceValidationError) throw error(cause.message, 400, 'invalid_request')
    const detail = cause instanceof Error ? cause.message : ''
    if (detail.includes('recommendation_preference_idempotency_conflict')) throw error('同一推荐偏好事件的内容不一致，请保留原事件重试。', 409, 'idempotency_conflict')
    if (detail.includes('recommendation_preference_account_unavailable')) throw error('当前账户无法同步推荐偏好。', 403, 'account_unavailable')
    throw error('推荐偏好同步暂不可用，请稍后重试。', 503, 'preference_storage_unavailable')
  }
}

async function requireActiveAccount(database: D1Database, ownerID: string) {
  const row = await database.prepare(`SELECT id FROM users WHERE id = ? AND deleted_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM account_deletion_jobs WHERE user_id = users.id)`)
    .bind(ownerID).first<{ id: string }>()
  if (!row) throw error('当前账户无法同步推荐偏好。', 403, 'account_unavailable')
}

async function push(request: Request, database: D1Database, ownerID: string, now: Date): Promise<RecommendationPreferencesPushResponseV1> {
  const payload = normalizeRecommendationPreferencesPushV1(await readBoundedJSON(request))
  const receivedAt = now.toISOString()
  // D1 batch is transactional. The insert trigger rejects any mismatched
  // duplicate even in a racing request; the entire batch then rolls back.
  await database.batch(payload.events.map(event => database.prepare(`INSERT OR IGNORE INTO recommendation_preference_events
    (user_id, event_id, payload_json, received_at) VALUES (?, ?, ?, ?)`)
    .bind(ownerID, event.eventID, JSON.stringify(event), receivedAt)))
  // Two binds per statement also respect D1's per-statement parameter ceiling
  // for a full 100-event batch.
  const results = await database.batch<EventRow>(payload.events.map(event => database.prepare(`SELECT revision, event_id, payload_json, received_at
    FROM recommendation_preference_events WHERE user_id = ? AND event_id = ?`).bind(ownerID, event.eventID)))
  const revisions = new Map(results.flatMap(result => result.results).map(row => [row.event_id, row.revision]))
  // A concurrent account deletion must not produce false acknowledgements.
  await requireActiveAccount(database, ownerID)
  if (revisions.size !== payload.events.length) throw error('推荐偏好尚未完整确认，请重试。', 503, 'preference_ack_incomplete')
  return { apiVersion: 1, ownerID, receipts: payload.events.map(event => ({ eventID: event.eventID, revision: revisions.get(event.eventID)! })) }
}

async function pull(url: URL, database: D1Database, ownerID: string): Promise<RecommendationPreferencesPullResponseV1> {
  for (const key of url.searchParams.keys()) {
    if (!['apiVersion', 'cursor', 'limit'].includes(key) || url.searchParams.getAll(key).length !== 1) throw error('推荐偏好查询参数无效。', 400, 'invalid_request')
  }
  if (url.searchParams.get('apiVersion') !== '1') throw error('推荐偏好接口版本无效。', 400, 'invalid_request')
  const rawLimit = url.searchParams.get('limit') ?? '100'
  if (!/^[1-9]\d{0,2}$/.test(rawLimit) || Number(rawLimit) > RECOMMENDATION_PREFERENCES_MAX_EVENTS) throw error('推荐偏好分页大小无效。', 400, 'invalid_request')
  const limit = Number(rawLimit)
  const ownerKey = await sha256(ownerID)
  const after = decodeCursor(url.searchParams.get('cursor'), ownerKey)
  if (after > 0 && !await database.prepare(`SELECT revision FROM recommendation_preference_events
    WHERE user_id = ? AND revision = ?`).bind(ownerID, after).first()) {
    throw error('推荐偏好同步游标已失效。', 400, 'invalid_cursor')
  }
  const page = await database.prepare(`SELECT revision, event_id, payload_json, received_at
    FROM recommendation_preference_events WHERE user_id = ? AND revision > ? ORDER BY revision LIMIT ?`)
    .bind(ownerID, after, limit + 1).all<EventRow>()
  const rows = page.results.slice(0, limit)
  // Recheck after the read: an account deletion may have begun while waiting.
  await requireActiveAccount(database, ownerID)
  const events = rows.map(row => {
    // Stored corruption must be a retryable server failure, not client input
    // rejection and never an empty page that would erase local exclusions.
    try {
      return { ...normalizeRecommendationPreferenceEventV1(JSON.parse(row.payload_json)), revision: row.revision, receivedAt: row.received_at }
    } catch { throw error('推荐偏好记录暂时无法读取，请稍后重试。', 503, 'preference_storage_unavailable') }
  })
  return { apiVersion: 1, ownerID, events, cursor: encodeCursor(ownerKey, rows.at(-1)?.revision ?? after), hasMore: page.results.length > limit }
}

function encodeCursor(ownerKey: string, after: number) {
  return `rp1.${btoa(JSON.stringify([1, ownerKey, after])).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`
}
function decodeCursor(cursor: string | null, ownerKey: string): number {
  if (cursor === null) return 0
  try {
    if (!/^rp1\.[A-Za-z0-9_-]{1,256}$/.test(cursor)) throw new Error()
    const encoded = cursor.slice(4).replace(/-/g, '+').replace(/_/g, '/')
    const value: unknown = JSON.parse(atob(encoded))
    if (!Array.isArray(value) || value.length !== 3 || value[0] !== 1 || value[1] !== ownerKey
      || !Number.isSafeInteger(value[2]) || value[2] < 0 || encodeCursor(ownerKey, value[2]) !== cursor) throw new Error()
    return value[2]
  } catch { throw error('推荐偏好同步游标无效或不属于当前账户。', 400, 'invalid_cursor') }
}
async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('')
}

async function readBoundedJSON(request: Request): Promise<unknown> {
  if (Number(request.headers.get('content-length') ?? 0) > RECOMMENDATION_PREFERENCES_MAX_BODY_BYTES) throw error('推荐偏好请求过大。', 413, 'request_too_large')
  if (!request.body) throw error('推荐偏好请求内容为空。', 400, 'invalid_request')
  const reader = request.body.getReader()
  const chunks: Uint8Array[] = []
  let length = 0
  try {
    for (;;) {
      const result = await reader.read()
      if (result.done) break
      length += result.value.byteLength
      if (length > RECOMMENDATION_PREFERENCES_MAX_BODY_BYTES) {
        await reader.cancel()
        throw error('推荐偏好请求过大。', 413, 'request_too_large')
      }
      chunks.push(result.value)
    }
  } finally { reader.releaseLock() }
  const bytes = new Uint8Array(length)
  let offset = 0
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes)) }
  catch { throw error('推荐偏好请求不是有效的 JSON。', 400, 'invalid_request') }
}
