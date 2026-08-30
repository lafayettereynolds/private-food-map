import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from './index'
import { handleAccountDeletionV1 } from './accountDeletionV1'

describe('Release safety V1 integration', () => {
  let database
  let bucket

  beforeEach(async () => {
    database = makeDatabase()
    bucket = new MemoryR2Bucket()
    await seedUser(database, 'tm_a', 'Alice')
    await seedUser(database, 'tm_b', 'Bob')
    await seedVisit(database, 'tm_a', 'a')
    await seedVisit(database, 'tm_b', 'b')
  })

  it('previews current-user data and completes a durable, idempotent D1 plus R2 deletion', async () => {
    const preview = await jsonAPI(database, bucket, 'tm_a', '/api/v1/account-deletion/preview')
    expect(preview).toMatchObject({ userId: 'tm_a', requiresFreshAuthentication: true })
    expect(preview.entityCounts).toMatchObject({ restaurants: 1, visits: 1, photos: 1 })

    const statusToken = `tm_delete_${'a'.repeat(48)}`
    const body = { apiVersion: 1, requestId: crypto.randomUUID(), statusToken, confirmation: 'DELETE', userId: 'tm_b' }
    const completed = await jsonAPI(database, bucket, 'tm_a', '/api/v1/account-deletion/confirm', 'POST', body)
    expect(completed).toMatchObject({ status: 'completed', retryable: false })
    expect(bucket.deleted.sort()).toEqual([
      'users/tm_a/photos/photo-a/display.jpg', 'users/tm_a/photos/photo-a/thumbnail.jpg',
    ])
    expect(database.get("SELECT deleted_at FROM users WHERE id = 'tm_a'").deleted_at).toBeTruthy()
    expect(database.get("SELECT deleted_at FROM users WHERE id = 'tm_b'").deleted_at).toBeNull()
    expect(database.get("SELECT deleted_at FROM visits WHERE id = 'visit-b'").deleted_at).toBeNull()
    expect(database.get("SELECT body FROM content_comments WHERE id = 'comment-b-on-a'").body).toBe('Bob keeps his comment')

    const status = await jsonAPI(database, bucket, '', '/api/v1/account-deletion/status', 'GET', undefined, statusToken)
    expect(status.jobId).toBe(completed.jobId)
    expect((await api(database, bucket, 'tm_a', '/api/v1/sync/pull?schemaVersion=1&cursor=0')).status).toBe(401)

    const replay = await handleAccountDeletionV1(
      new Request('https://development.example.test/api/v1/account-deletion/confirm', {
        method: 'POST', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' },
      }),
      { DB: database, PHOTO_STORAGE: bucket },
      { id: 'tm_a', developmentIdentity: true },
    )
    expect(replay).toEqual(completed)
  })

  it('retains a failed R2 job and resumes it using only its opaque status token', async () => {
    bucket.failuresRemaining = 1
    const statusToken = `tm_delete_${'b'.repeat(48)}`
    const body = { apiVersion: 1, requestId: crypto.randomUUID(), statusToken, confirmation: 'DELETE' }
    const failed = await jsonAPI(database, bucket, 'tm_a', '/api/v1/account-deletion/confirm', 'POST', body)
    expect(failed).toMatchObject({ status: 'failed', retryable: true, errorCode: 'r2_delete_failed' })
    expect(database.get("SELECT deleted_at FROM users WHERE id = 'tm_a'").deleted_at).toBeNull()

    const retried = await jsonAPI(database, bucket, '', '/api/v1/account-deletion/retry', 'POST', {}, statusToken)
    expect(retried).toMatchObject({ status: 'completed', retryable: false, errorCode: null })
    expect(database.get("SELECT deleted_at FROM users WHERE id = 'tm_a'").deleted_at).toBeTruthy()
  })

  it('reports idempotently and blocks content in feed, comments, search, and direct profile reads', async () => {
    const reportBody = {
      apiVersion: 1, requestId: crypto.randomUUID(), contentType: 'visit', contentId: 'visit-b',
      reason: 'spam', details: 'Repeated promotional content', userId: 'tm_b',
    }
    const first = await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/reports', 'POST', reportBody)
    const duplicate = await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/reports', 'POST', reportBody)
    expect(first).toMatchObject({ status: 'pending', duplicate: false })
    expect(duplicate).toMatchObject({ reportId: first.reportId, duplicate: true })
    expect((await api(database, bucket, 'tm_b', '/api/v1/community/reports', 'POST', {
      ...reportBody, requestId: crypto.randomUUID(),
    })).status).toBe(400)

    expect((await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/feed?scope=latest')).items)
      .toHaveLength(1)
    const block = await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/blocks/tm_b', 'PUT')
    expect(block).toMatchObject({ blockedUserId: 'tm_b', blocked: true, duplicate: false })
    expect((await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/feed?scope=latest')).items)
      .toHaveLength(0)
    expect((await api(database, bucket, 'tm_a', '/api/v1/community/users/tm_b/content')).status).toBe(404)
    expect((await api(database, bucket, 'tm_a', '/api/v1/social/users/search?q=Bob')).status).toBe(200)
    expect((await jsonAPI(database, bucket, 'tm_a', '/api/v1/social/users/search?q=Bob')).items).toHaveLength(0)
    expect((await api(database, bucket, 'tm_a', '/api/v1/community/content/visit/visit-b/comments')).status).toBe(404)

    const duplicateBlock = await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/blocks/tm_b', 'PUT')
    expect(duplicateBlock.duplicate).toBe(true)
    await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/blocks/tm_b', 'DELETE')
    expect((await jsonAPI(database, bucket, 'tm_a', '/api/v1/community/feed?scope=latest')).items)
      .toHaveLength(1)
  })
})

async function seedUser(database, id, name) {
  await api(database, new MemoryR2Bucket(), id, '/api/v1/sync/pull?schemaVersion=1&cursor=0')
  await database.prepare("UPDATE user_profiles SET display_name = ?, visibility = 'public' WHERE user_id = ?")
    .bind(name, id).run()
}

async function seedVisit(database, user, slug) {
  const now = new Date().toISOString()
  await database.prepare(`INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, tags_json, created_at, updated_at
  ) VALUES (?, ?, '', ?, 'Road', 'Hangzhou', 30, 120, 'visited', 'normal', 'emoji', '🍜', '[]', ?, ?)`)
    .bind(`restaurant-${slug}`, user, `Restaurant ${slug}`, now, now).run()
  await database.prepare(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, party_size, note, created_at, updated_at, visibility
  ) VALUES (?, ?, ?, ?, 1, '', ?, ?, 'public')`)
    .bind(`visit-${slug}`, user, `restaurant-${slug}`, now, now, now).run()
  await database.prepare(`INSERT INTO photos (
    id, user_id, restaurant_id, visit_id, storage_provider, storage_key, thumbnail_storage_key,
    drive_account_id, drive_file_id, kind, mime_type, file_size, visibility, sync_status,
    sort_order, created_at, updated_at
  ) VALUES (?, ?, ?, ?, 'r2', ?, ?, '', '', 'visit', 'image/jpeg', 10, 'public', 'synced', 0, ?, ?)`)
    .bind(`photo-${slug}`, user, `restaurant-${slug}`, `visit-${slug}`,
      `users/${user}/photos/photo-${slug}/display.jpg`,
      `users/${user}/photos/photo-${slug}/thumbnail.jpg`, now, now).run()
  if (user === 'tm_b') {
    await database.prepare(`INSERT INTO content_comments (
      id, content_type, content_id, user_id, body, created_at, updated_at, server_version
    ) VALUES ('comment-b-on-a', 'visit', 'visit-a', 'tm_b', 'Bob keeps his comment', ?, ?, 1)`)
      .bind(now, now).run()
  }
}

async function jsonAPI(database, bucket, viewer, path, method = 'GET', body, deletionToken) {
  const response = await api(database, bucket, viewer, path, method, body, deletionToken)
  const value = await response.json()
  if (!response.ok) throw new Error(`${response.status}: ${value.error}`)
  return value
}

function api(database, bucket, viewer, path, method = 'GET', body, deletionToken) {
  const headers = new Headers()
  if (viewer) headers.set('X-Taste-Map-Test-User', viewer)
  if (deletionToken) headers.set('X-Taste-Map-Deletion-Token', deletionToken)
  if (body !== undefined) headers.set('Content-Type', 'application/json')
  return worker.fetch(new Request(`https://development.example.test${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  }), {
    DB: database, PHOTO_STORAGE: bucket, ASSETS: { fetch: () => new Response('not used') },
    APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test',
  })
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  for (const file of [
    '0001_initial.sql', '0002_add_google_drive_photos.sql', '0003_social_visit_fields.sql',
    '0004_user_avatar_thumbnail.sql', '0005_visit_tags_and_map_privacy.sql',
    '0006_avatar_presets_and_membership.sql', '0007_multi_dining_occasions.sql',
    '0008_dining_companion_links.sql', '0009_discovery_follows_and_test_markers.sql',
    '0010_membership_entitlements.sql', '0011_photo_storage_metadata.sql',
    '0012_recommendation_events.sql', '0013_restaurant_lists.sql',
    '0014_restaurant_contact_details.sql', '0015_restaurant_place_identities.sql',
    '0016_sync_v1.sql', '0017_native_auth.sql', '0018_visit_core_fields.sql',
    '0019_dish_photo_sync.sql', '0020_visit_dish_associations.sql',
    '0021_companions_recommendation_sources_sync.sql', '0022_user_profiles_sync.sql',
    '0023_social_relationships_v1.sql', '0024_social_legacy_write_compat.sql',
    '0025_discovery_v1_indexes.sql', '0026_public_community_v1_indexes.sql',
    '0027_social_hardening.sql', '0028_restaurant_lists_v1.sql',
    '0029_social_collaboration_and_interactions.sql', '0030_app_store_commerce.sql',
    '0031_public_sharing.sql', '0032_release_safety.sql',
  ]) sqlite.exec(readFileSync(resolve('migrations', file), 'utf8'))
  return new SQLiteD1Database(sqlite)
}

class MemoryR2Bucket {
  constructor() { this.deleted = []; this.failuresRemaining = 0 }
  async delete(key) {
    if (this.failuresRemaining > 0) { this.failuresRemaining -= 1; throw new Error('injected R2 failure') }
    this.deleted.push(key)
  }
}

class SQLiteD1Database {
  constructor(sqlite) { this.sqlite = sqlite }
  prepare(sql) { return new SQLiteD1Statement(this.sqlite, sql) }
  async batch(statements) {
    this.sqlite.exec('BEGIN IMMEDIATE')
    try {
      const results = statements.map((statement) => statement.batchSync())
      this.sqlite.exec('COMMIT')
      return results
    } catch (error) { this.sqlite.exec('ROLLBACK'); throw error }
  }
  get(sql, ...values) { return this.sqlite.prepare(sql).get(...values) }
}

class SQLiteD1Statement {
  constructor(sqlite, sql, values = []) { this.sqlite = sqlite; this.sql = sql; this.values = values }
  bind(...values) { return new SQLiteD1Statement(this.sqlite, this.sql, values) }
  async first() { return this.sqlite.prepare(this.sql).get(...this.values) ?? null }
  async all() { return { results: this.sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} } }
  async run() { return this.runSync() }
  batchSync() {
    if (/^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)) {
      return { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} }
    }
    return this.runSync()
  }
  runSync() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes) } }
  }
}
