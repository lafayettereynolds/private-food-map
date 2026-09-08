import type {
  AccountDeletionConfirmRequestV1,
  AccountDeletionJobV1,
  AccountDeletionPreviewV1,
  AccountDeletionStatusV1,
} from '../src/contracts/releaseSafetyV1'
import { RELEASE_SAFETY_API_VERSION } from '../src/contracts/releaseSafetyV1'

import { PRIVACY_RETENTION } from './privacyRetentionPolicy'

const FRESH_AUTH_WINDOW_MS = 10 * 60 * 1000

export interface AccountDeletionEnvironmentV1 {
  DB: D1Database
  PHOTO_STORAGE?: R2Bucket
}

export interface AccountDeletionViewerV1 {
  id: string
  authenticatedAt?: string
  developmentIdentity?: boolean
}

interface JobRow {
  id: string
  user_id: string
  request_id: string
  request_fingerprint: string
  status_token_hash: string
  status: AccountDeletionStatusV1
  requested_at: string
  updated_at: string
  completed_at: string | null
  retry_count: number
  last_error_code: string | null
}

interface CountRow { count: number }
interface StorageKeyRow { storage_key: string }

export class AccountDeletionV1Error extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message)
    this.name = 'AccountDeletionV1Error'
  }
}

export async function handleAccountDeletionV1(
  request: Request,
  environment: AccountDeletionEnvironmentV1,
  viewer: AccountDeletionViewerV1 | null,
  now = new Date(),
): Promise<AccountDeletionPreviewV1 | AccountDeletionJobV1> {
  const path = new URL(request.url).pathname
  if (path === '/api/v1/account-deletion/status' && request.method === 'GET') {
    return statusFromToken(request, environment.DB)
  }
  if (path === '/api/v1/account-deletion/retry' && request.method === 'POST') {
    const job = await jobFromToken(request, environment.DB)
    if (!job || job.status !== 'failed') throw requestError('删除任务当前不可重试。', 409, 'job_not_retryable')
    return processJob(environment, job, now)
  }
  if (!viewer) throw requestError('需要登录后才能删除账户。', 401, 'authentication_required')
  if (path === '/api/v1/account-deletion/preview' && request.method === 'GET') {
    return deletionPreview(environment.DB, viewer.id)
  }
  if (path === '/api/v1/account-deletion/confirm' && request.method === 'POST') {
    requireFreshAuthentication(viewer, now)
    const payload = await readConfirmRequest(request)
    return confirmDeletion(environment, viewer.id, payload, now)
  }
  throw requestError('Account deletion endpoint was not found.', 404, 'route_not_found')
}

async function deletionPreview(database: D1Database, userID: string): Promise<AccountDeletionPreviewV1> {
  const definitions = [
    ['restaurants', 'SELECT COUNT(*) AS count FROM restaurants WHERE user_id = ? AND deleted_at IS NULL'],
    ['visits', 'SELECT COUNT(*) AS count FROM visits WHERE user_id = ? AND deleted_at IS NULL'],
    ['dishes', 'SELECT COUNT(*) AS count FROM dishes WHERE user_id = ? AND deleted_at IS NULL'],
    ['photos', 'SELECT COUNT(*) AS count FROM photos WHERE user_id = ? AND deleted_at IS NULL'],
    ['lists', 'SELECT COUNT(*) AS count FROM restaurant_lists WHERE user_id = ? AND deleted_at IS NULL'],
    ['comments', 'SELECT COUNT(*) AS count FROM content_comments WHERE user_id = ? AND deleted_at IS NULL'],
  ] as const
  const results = await database.batch(definitions.map(([, sql]) => database.prepare(sql).bind(userID)))
  const entityCounts = Object.fromEntries(definitions.map(([name], index) => [
    name, Number((results[index].results?.[0] as unknown as CountRow | undefined)?.count ?? 0),
  ]))
  const pending = await database.prepare(`SELECT COUNT(*) AS count FROM sync_mutation_receipts_v6
    WHERE user_id = ? AND status <> 'applied'`).bind(userID).first<CountRow>()
  const objects = await database.prepare(`SELECT COUNT(*) AS count FROM photos
    WHERE user_id = ? AND deleted_at IS NULL AND (
      COALESCE(storage_key, '') <> '' OR COALESCE(thumbnail_storage_key, '') <> ''
    )`).bind(userID).first<CountRow>()
  return {
    apiVersion: RELEASE_SAFETY_API_VERSION,
    userId: userID,
    requiresFreshAuthentication: true,
    pendingMutationCount: Number(pending?.count ?? 0),
    entityCounts,
    photoObjectCount: Number(objects?.count ?? 0),
  }
}

async function confirmDeletion(
  environment: AccountDeletionEnvironmentV1,
  userID: string,
  payload: AccountDeletionConfirmRequestV1,
  now: Date,
): Promise<AccountDeletionJobV1> {
  const fingerprint = await sha256(JSON.stringify({
    apiVersion: payload.apiVersion, requestId: payload.requestId, confirmation: payload.confirmation,
  }))
  const tokenHash = await sha256(payload.statusToken)
  let job = await environment.DB.prepare(`SELECT * FROM account_deletion_jobs
    WHERE user_id = ? AND request_id = ? LIMIT 1`).bind(userID, payload.requestId).first<JobRow>()
  if (job) {
    if (job.request_fingerprint !== fingerprint || job.status_token_hash !== tokenHash) {
      throw requestError('重复删除请求的内容不一致。', 409, 'idempotency_conflict')
    }
    if (job.status === 'failed') return processJob(environment, job, now)
    return contract(job)
  }

  const jobID = `delete_${crypto.randomUUID()}`
  const timestamp = now.toISOString()
  await environment.DB.prepare(`INSERT OR IGNORE INTO account_deletion_jobs (
    id, user_id, request_id, request_fingerprint, status_token_hash, status,
    requested_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, 'confirmed', ?, ?)`).bind(
    jobID, userID, payload.requestId, fingerprint, tokenHash, timestamp, timestamp,
  ).run()
  job = await environment.DB.prepare('SELECT * FROM account_deletion_jobs WHERE user_id=? AND request_id=?')
    .bind(userID,payload.requestId).first<JobRow>()
  if (!job) throw requestError('删除任务没有创建成功。', 500, 'job_creation_failed')
  if (job.request_fingerprint !== fingerprint || job.status_token_hash !== tokenHash) throw requestError('重复删除请求的内容不一致。',409,'idempotency_conflict')
  if (job.id !== jobID) return contract(job)
  return processJob(environment, job, now)
}

async function processJob(
  environment: AccountDeletionEnvironmentV1,
  job: JobRow,
  now: Date,
): Promise<AccountDeletionJobV1> {
  const lease = crypto.randomUUID()
  const claim = await environment.DB.prepare(`UPDATE account_deletion_jobs SET cleanup_lease=?,cleanup_lease_until=?
    WHERE id=? AND status<>'completed' AND (cleanup_lease_until IS NULL OR cleanup_lease_until<=?)`)
    .bind(lease,new Date(now.getTime()+PRIVACY_RETENTION.leaseSeconds*1000).toISOString(),job.id,now.toISOString()).run()
  if (!claim.meta.changes) {
    const current = await environment.DB.prepare('SELECT * FROM account_deletion_jobs WHERE id=?').bind(job.id).first<JobRow>()
    if (!current) throw requestError('删除任务不存在。',404,'job_missing')
    return contract(current)
  }
  try {
    if (job.status === 'confirmed' || job.status === 'failed' || job.status === 'deleting_data') {
      await deleteD1Data(environment.DB, job, now)
    }
    await cleanAccountObjects(environment, job, now)
    await finishDeletion(environment.DB, job, now)
  } catch (error) {
    const code = error instanceof AccountDeletionV1Error ? error.code : 'deletion_failed'
    await environment.DB.prepare(`UPDATE account_deletion_jobs SET status = 'failed',
      retry_count = retry_count + 1, updated_at = ?, last_error_code = ? WHERE id = ?`)
      .bind(now.toISOString(), code, job.id).run()
  } finally {
    await environment.DB.prepare('UPDATE account_deletion_jobs SET cleanup_lease=NULL,cleanup_lease_until=NULL WHERE id=? AND cleanup_lease=?').bind(job.id,lease).run()
  }
  const current = await environment.DB.prepare('SELECT * FROM account_deletion_jobs WHERE id = ?')
    .bind(job.id).first<JobRow>()
  if (!current) throw requestError('删除任务无法读取。', 500, 'job_missing')
  return contract(current)
}

export async function resumeAccountDeletions(environment: AccountDeletionEnvironmentV1, now = new Date()) {
  const jobs = await environment.DB.prepare(`SELECT * FROM account_deletion_jobs WHERE status IN
    ('confirmed','deleting_data','deleting_objects','failed') ORDER BY updated_at LIMIT ?`)
    .bind(PRIVACY_RETENTION.jobBatch).all<JobRow>()
  for (const job of jobs.results) await processJob(environment, job, now)
}

/** Owner-prefix listing also catches uploads whose metadata commit failed. No bucket-wide scan. */
async function cleanAccountObjects(environment: AccountDeletionEnvironmentV1, job: JobRow, now: Date) {
  if (!/^[A-Za-z0-9_-]+$/.test(job.user_id)) throw requestError('Invalid object owner.', 409, 'invalid_object_owner')
  const prefix = `users/${job.user_id}/photos/`
  const bucket = environment.PHOTO_STORAGE
  if (!bucket) throw requestError('照片存储暂不可用。', 503, 'photo_storage_unavailable')
  await environment.DB.prepare("UPDATE account_deletion_jobs SET status='deleting_objects', updated_at=? WHERE id=?")
    .bind(now.toISOString(), job.id).run()
  let pages = 0
  for (;;) {
    if (++pages > PRIVACY_RETENTION.maxObjectPages) throw requestError('Cleanup continuation required.', 503, 'cleanup_continuation')
    const batch = await environment.DB.prepare(`SELECT storage_key FROM account_deletion_objects
      WHERE job_id=? AND status<>'deleted' ORDER BY storage_key LIMIT ?`)
      .bind(job.id, PRIVACY_RETENTION.objectBatch).all<StorageKeyRow>()
    if (!batch.results.length) break
    const keys = batch.results.map(row => row.storage_key)
    if (keys.some(key => !key.startsWith(prefix))) throw requestError('Object owner mismatch.', 409, 'object_owner_mismatch')
    try { await bucket.delete(keys) }
    catch { throw requestError('照片删除暂未完成，可以安全重试。', 503, 'r2_delete_failed') }
    // Delete is idempotent; if acknowledgement fails the same keys are safe to retry.
    await environment.DB.prepare(`UPDATE account_deletion_objects SET status='deleted', updated_at=?, last_error_code=NULL
      WHERE job_id=? AND storage_key IN (${keys.map(() => '?').join(',')})`).bind(now.toISOString(), job.id, ...keys).run()
  }
  let cursor: string | undefined
  do {
    if (++pages > PRIVACY_RETENTION.maxObjectPages) throw requestError('Cleanup continuation required.', 503, 'cleanup_continuation')
    const page = await bucket.list({ prefix, cursor, limit: PRIVACY_RETENTION.objectBatch })
    const keys = page.objects.map(object => object.key)
    if (keys.some(key => !key.startsWith(prefix))) throw requestError('Object owner mismatch.', 409, 'object_owner_mismatch')
    try { if (keys.length) await bucket.delete(keys) }
    catch { throw requestError('照片删除暂未完成，可以安全重试。', 503, 'r2_delete_failed') }
    if (page.truncated && (!page.cursor || page.cursor === cursor)) throw requestError('Invalid R2 continuation.', 503, 'invalid_r2_cursor')
    cursor = page.truncated ? page.cursor : undefined
  } while (cursor)
  // A short page is not proof of completion. Fresh prefix listing must be empty.
  const proof = await bucket.list({ prefix, limit: 1 })
  const pending = await environment.DB.prepare("SELECT COUNT(*) AS count FROM account_deletion_objects WHERE job_id=? AND status<>'deleted'")
    .bind(job.id).first<CountRow>()
  if (proof.objects.length || proof.truncated || pending?.count) throw requestError('照片删除尚未完成。', 503, 'objects_remaining')
}

async function deleteD1Data(database: D1Database, job: JobRow, now: Date) {
  const timestamp = now.toISOString()
  const userID = job.user_id
  await database.prepare(`UPDATE account_deletion_jobs SET status = 'deleting_data',
    confirmed_at = COALESCE(confirmed_at, ?), updated_at = ?, last_error_code = NULL WHERE id = ?`)
    .bind(timestamp, timestamp, job.id).run()

  await database.batch([
    database.prepare("UPDATE users SET deleted_at=COALESCE(deleted_at,?), updated_at=? WHERE id=?").bind(timestamp, timestamp, userID),
    database.prepare("UPDATE user_profiles SET visibility='private',deleted_at=COALESCE(deleted_at,?),updated_at=? WHERE user_id=?").bind(timestamp,timestamp,userID),
    database.prepare("UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at,?), revoke_reason='account_deleted', updated_at=? WHERE user_id=?").bind(timestamp, timestamp, userID),
  ])
  await database.prepare(`INSERT OR IGNORE INTO account_deletion_objects(job_id,storage_key,status,updated_at)
    SELECT ?,storage_key,'pending',? FROM photos WHERE user_id=? AND COALESCE(storage_key,'')<>''
    UNION SELECT ?,thumbnail_storage_key,'pending',? FROM photos WHERE user_id=? AND COALESCE(thumbnail_storage_key,'')<>''`)
    .bind(job.id,timestamp,userID,job.id,timestamp,userID).run()

  const statements = [
    database.prepare('DELETE FROM recommendation_preference_events WHERE user_id = ?').bind(userID),
    database.prepare(`UPDATE public_share_links SET revoked_at = COALESCE(revoked_at, ?), updated_at = ? WHERE owner_user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE content_likes SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE content_comments SET body = '[deleted]', deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE friendships SET status = 'removed', deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE requester_id = ? OR addressee_id = ?`).bind(timestamp, timestamp, userID, userID),
    database.prepare(`UPDATE follows SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE follower_id = ? OR followed_user_id = ?`).bind(timestamp, timestamp, userID, userID),
    database.prepare(`UPDATE companion_link_requests SET status = 'removed', deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE requester_user_id = ? OR target_user_id = ?`).bind(timestamp, timestamp, userID, userID),
    database.prepare(`UPDATE dining_companions SET linked_user_id = NULL, updated_at = ? WHERE linked_user_id = ? AND owner_user_id <> ?`).bind(timestamp, userID, userID),
    database.prepare(`UPDATE recommendation_sources SET linked_user_id = NULL, updated_at = ? WHERE linked_user_id = ? AND user_id <> ?`).bind(timestamp, userID, userID),
    database.prepare(`UPDATE shared_meal_participants SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ? OR shared_meal_id IN (SELECT id FROM shared_meals WHERE created_by_user_id = ?)`).bind(timestamp, timestamp, userID, userID),
    database.prepare(`UPDATE shared_meals SET deleted_at = COALESCE(deleted_at, ?), revoked_at = COALESCE(revoked_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE created_by_user_id = ?`).bind(timestamp, timestamp, timestamp, userID),
    database.prepare(`UPDATE user_blocks SET deleted_at = COALESCE(deleted_at, ?), updated_at = ? WHERE blocker_user_id = ? OR blocked_user_id = ?`).bind(timestamp, timestamp, userID, userID),
    database.prepare(`UPDATE restaurant_list_items SET deleted_at = COALESCE(deleted_at, ?), updated_at = ? WHERE list_id IN (SELECT id FROM restaurant_lists WHERE user_id = ?)`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE restaurant_lists SET deleted_at = COALESCE(deleted_at, ?), updated_at = ? WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE want_to_go SET deleted_at = COALESCE(deleted_at, ?) WHERE user_id = ?`).bind(timestamp, userID),
    database.prepare(`UPDATE visit_dishes SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE dishes SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE photos SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE visits SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE restaurants SET deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE dining_companions SET display_name = 'Deleted user', linked_user_id = NULL, deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE owner_user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE recommendation_sources SET display_name = 'Deleted source', normalized_name = 'Deleted source', linked_user_id = NULL, deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE user_profiles SET display_name = 'Deleted user', bio = '', city = '', avatar_photo_id = NULL, visibility = 'private', deleted_at = COALESCE(deleted_at, ?), updated_at = ?, server_version = server_version + CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END WHERE user_id = ?`).bind(timestamp, timestamp, userID),
  ]
  await database.batch(statements)
}

async function finishDeletion(database: D1Database, job: JobRow, now: Date) {
  const timestamp = now.toISOString()
  const userID = job.user_id
  const identities = await database.prepare('SELECT id FROM auth_identities WHERE user_id = ?')
    .bind(userID).all<{ id: string }>()
  const statements = [
    ...identities.results.map((identity) => database.prepare('DELETE FROM auth_identity_token_uses WHERE identity_id = ?').bind(identity.id)),
    database.prepare('DELETE FROM auth_identities WHERE user_id = ?').bind(userID),
    database.prepare(`UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, ?),
      revoke_reason = COALESCE(revoke_reason, 'account_deleted'), updated_at = ? WHERE user_id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE users SET auth_subject = NULL, email = NULL, nickname = 'Deleted user',
      bio = '', city = '', avatar_photo_id = NULL, avatar_image_data = NULL, deleted_at = COALESCE(deleted_at, ?), updated_at = ?
      WHERE id = ?`).bind(timestamp, timestamp, userID),
    database.prepare(`UPDATE account_deletion_jobs SET status = 'completed', completed_at = ?,
      updated_at = ?, last_error_code = NULL WHERE id = ?`).bind(timestamp, timestamp, job.id),
  ]
  await database.batch(statements)
}

async function statusFromToken(request: Request, database: D1Database) {
  const job = await jobFromToken(request, database)
  if (!job) throw requestError('删除任务不存在。', 404, 'job_not_found')
  return contract(job)
}

async function jobFromToken(request: Request, database: D1Database) {
  const token = request.headers.get('X-Taste-Map-Deletion-Token')?.trim()
  if (!token || !/^tm_delete_[A-Za-z0-9_-]{32,}$/.test(token)) {
    throw requestError('删除任务凭据无效。', 401, 'invalid_status_token')
  }
  return database.prepare('SELECT * FROM account_deletion_jobs WHERE status_token_hash = ? LIMIT 1')
    .bind(await sha256(token)).first<JobRow>()
}

function requireFreshAuthentication(viewer: AccountDeletionViewerV1, now: Date) {
  if (viewer.developmentIdentity) return
  const authenticatedAt = viewer.authenticatedAt ? Date.parse(viewer.authenticatedAt) : NaN
  if (!Number.isFinite(authenticatedAt) || now.getTime() - authenticatedAt > FRESH_AUTH_WINDOW_MS) {
    throw requestError('删除账户前需要重新使用 Apple 登录验证。', 401, 'fresh_authentication_required')
  }
}

async function readConfirmRequest(request: Request): Promise<AccountDeletionConfirmRequestV1> {
  const payload = await request.json().catch(() => null) as Partial<AccountDeletionConfirmRequestV1> | null
  if (!payload || payload.apiVersion !== RELEASE_SAFETY_API_VERSION || payload.confirmation !== 'DELETE' ||
      typeof payload.requestId !== 'string' || !/^[0-9a-f-]{36}$/i.test(payload.requestId) ||
      typeof payload.statusToken !== 'string' || !/^tm_delete_[A-Za-z0-9_-]{32,}$/.test(payload.statusToken)) {
    throw requestError('删除确认请求无效。', 400, 'invalid_confirmation')
  }
  return payload as AccountDeletionConfirmRequestV1
}

function contract(row: JobRow): AccountDeletionJobV1 {
  return {
    apiVersion: RELEASE_SAFETY_API_VERSION,
    jobId: row.id,
    status: row.status,
    requestedAt: row.requested_at,
    updatedAt: row.updated_at,
    completedAt: row.completed_at,
    retryable: row.status === 'failed',
    errorCode: row.last_error_code,
  }
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function requestError(message: string, status: number, code: string) {
  return new AccountDeletionV1Error(message, status, code)
}
