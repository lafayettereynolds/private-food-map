import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from './index'

const NOW = '2026-08-28T14:00:00.000Z'

describe('Social API V1 integration', () => {
  let database

  beforeEach(async () => {
    database = makeDatabase()
    for (const [id, name, city, visibility] of [
      ['tm_a', 'Alpha 食客', '杭州', 'public'],
      ['tm_b', 'Beta 小林', '上海', 'public'],
      ['tm_c', 'Gamma 阿陈', '杭州', 'public'],
      ['tm_d', 'Delta 用户', '北京', 'public'],
      ['tm_e', 'Echo 用户', '杭州', 'public'],
      ['tm_private', 'Private 隐身', '杭州', 'private'],
    ]) await seedUser(database, id, name, city, visibility)
    database.prepare("UPDATE users SET email = 'apple-secret@icloud.com', auth_subject = 'secret-apple-sub' WHERE id = 'tm_b'").run()
  })

  it('searches only public allowlisted fields with minimum length, pagination, and no enumeration', async () => {
    expect(database.get("SELECT display_name, visibility FROM user_profiles WHERE user_id = 'tm_b'"))
      .toMatchObject({ display_name: 'Beta 小林', visibility: 'public' })
    expect((await api(database, 'tm_a', '/api/v1/social/users/search?q=')).status).toBe(400)
    expect((await api(database, 'tm_a', '/api/v1/social/users/search?q=B')).status).toBe(400)

    const byName = await jsonAPI(database, 'tm_a', '/api/v1/social/users/search?q=eta')
    expect(byName.items.map((item) => item.profile.displayName)).toContain('Beta 小林')
    expect(Object.keys(byName.items[0].profile).sort()).toEqual([
      'avatarPhotoId', 'avatarPresetId', 'bio', 'city', 'displayName', 'userId',
    ])
    expect(JSON.stringify(byName)).not.toContain('apple-secret@icloud.com')
    expect(JSON.stringify(byName)).not.toContain('secret-apple-sub')
    expect((await jsonAPI(database, 'tm_a', '/api/v1/social/users/search?q=apple-secret')).items).toEqual([])
    expect((await jsonAPI(database, 'tm_a', '/api/v1/social/users/search?q=杭州')).items.map((item) => item.profile.userId))
      .not.toContain('tm_private')

    const first = await jsonAPI(database, 'tm_a', '/api/v1/social/users/search?q=用户&limit=1')
    expect(first.items).toHaveLength(1)
    expect(first.nextCursor).toBeTypeOf('string')
    const second = await jsonAPI(database, 'tm_a', `/api/v1/social/users/search?q=用户&limit=1&cursor=${encodeURIComponent(first.nextCursor)}`)
    expect(second.items).toHaveLength(1)
    expect(second.items[0].profile.userId).not.toBe(first.items[0].profile.userId)
  })

  it('enforces the request state machine, duplicate/self protection, cross-request acceptance, and canonical pair', async () => {
    expect((await api(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_a' })).status).toBe(400)
    const first = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_b' })
    const duplicate = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_b' })
    expect(first.friendship.state).toBe('outgoing_request')
    expect(duplicate.duplicate).toBe(true)
    expect(database.get("SELECT COUNT(*) AS value FROM friendships WHERE pair_user_a = 'tm_a' AND pair_user_b = 'tm_b' AND deleted_at IS NULL").value).toBe(1)

    const cross = await jsonAPI(database, 'tm_b', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_a' })
    expect(cross.crossRequestAccepted).toBe(true)
    expect(cross.friendship.state).toBe('friends')
    const aFriends = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships?scope=friends')
    expect(aFriends.items[0]).toMatchObject({ friendshipState: 'friends', profile: { userId: 'tm_b' } })
  })

  it('allows only the addressee to accept/reject, requester to cancel, and participants to remove', async () => {
    const sent = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_b', actorUserId: 'tm_c' })
    const id = encodeURIComponent(sent.friendship.id)
    expect((await api(database, 'tm_c', `/api/v1/social/friendships/${id}`, 'POST', { action: 'accept' })).status).toBe(404)
    expect((await api(database, 'tm_a', `/api/v1/social/friendships/${id}`, 'POST', { action: 'accept' })).status).toBe(409)
    expect((await jsonAPI(database, 'tm_b', `/api/v1/social/friendships/${id}`, 'POST', { action: 'accept' })).friendship.state).toBe('friends')
    expect((await jsonAPI(database, 'tm_a', `/api/v1/social/friendships/${id}`, 'POST', { action: 'remove' })).friendship.state).toBe('removed')

    const rejected = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_c' })
    expect((await jsonAPI(database, 'tm_c', `/api/v1/social/friendships/${encodeURIComponent(rejected.friendship.id)}`, 'POST', { action: 'reject' })).friendship.state).toBe('rejected')
    const cancelled = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_d' })
    expect((await jsonAPI(database, 'tm_a', `/api/v1/social/friendships/${encodeURIComponent(cancelled.friendship.id)}`, 'POST', { action: 'cancel' })).friendship.state).toBe('removed')
  })

  it('keeps Follow one-way, idempotent, removable, and independent from Friendship', async () => {
    expect((await api(database, 'tm_a', '/api/v1/social/follows/tm_a', 'PUT')).status).toBe(400)
    const first = await jsonAPI(database, 'tm_a', '/api/v1/social/follows/tm_b', 'PUT', { actorUserId: 'tm_b' })
    const duplicate = await jsonAPI(database, 'tm_a', '/api/v1/social/follows/tm_b', 'PUT')
    expect(first.follow.followerUserId).toBe('tm_a')
    expect(duplicate.duplicate).toBe(true)
    const context = await jsonAPI(database, 'tm_a', '/api/v1/social/users/tm_b/context')
    expect(context.relationship).toEqual({ friendshipId: null, friendshipState: 'none', isFollowing: true })
    expect((await jsonAPI(database, 'tm_b', '/api/v1/social/follows?scope=followers')).items[0].profile.userId).toBe('tm_a')
    expect((await jsonAPI(database, 'tm_a', '/api/v1/social/follows/tm_b', 'DELETE')).follow.deletedAt).not.toBeNull()
  })

  it('keeps legacy Web Follow reads and writes compatible with V1 tombstones', async () => {
    const legacyAdd = await jsonAPI(database, 'tm_a', '/api/follows', 'POST', { action: 'add', userId: 'tm_b' })
    expect(legacyAdd).toMatchObject({ id: 'follow:owner:tm_b' })
    expect(database.get("SELECT follower_id, followed_user_id, deleted_at FROM follows WHERE id = 'follow:owner:tm_b'"))
      .toMatchObject({ follower_id: 'owner', followed_user_id: 'tm_b', deleted_at: null })
    expect((await jsonAPI(database, 'owner', '/api/v1/social/follows?scope=following')).items)
      .toHaveLength(1)

    await jsonAPI(database, 'owner', '/api/v1/social/follows/tm_b', 'DELETE')
    expect((await jsonAPI(database, 'tm_a', '/api/follows')).follows).toEqual([])

    await jsonAPI(database, 'tm_a', '/api/follows', 'POST', { action: 'add', userId: 'tm_b' })
    expect((await jsonAPI(database, 'owner', '/api/v1/social/follows?scope=following')).items)
      .toHaveLength(1)

    await jsonAPI(database, 'tm_a', '/api/follows', 'POST', { action: 'remove', userId: 'tm_b' })
    expect((await jsonAPI(database, 'owner', '/api/v1/social/follows?scope=following')).items)
      .toEqual([])
  })

  it('gates friends-only Profile statistics immediately when friendship is removed', async () => {
    database.prepare("UPDATE user_profiles SET visibility = 'friends' WHERE user_id = 'tm_b'").run()
    await createVisit(database, 'tm_b', 'friends')
    expect((await api(database, 'tm_a', '/api/v1/social/users/tm_b/context')).status).toBe(404)
    const pending = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_b' })
    expect((await api(database, 'tm_a', '/api/v1/social/users/tm_b/context')).status).toBe(404)
    await jsonAPI(database, 'tm_b', `/api/v1/social/friendships/${encodeURIComponent(pending.friendship.id)}`, 'POST', { action: 'accept' })
    const accepted = await jsonAPI(database, 'tm_a', '/api/v1/social/users/tm_b/context')
    expect(accepted.profile.statistics).toMatchObject({ publicVisitCount: 1, publicRestaurantCount: 1 })
    await jsonAPI(database, 'tm_a', `/api/v1/social/friendships/${encodeURIComponent(pending.friendship.id)}`, 'POST', { action: 'remove' })
    expect((await api(database, 'tm_a', '/api/v1/social/users/tm_b/context')).status).toBe(404)
  })

  it('keeps list state consistent across two clients and uses stable cursors', async () => {
    const sent = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_b' })
    const clientB = await jsonAPI(database, 'tm_b', '/api/v1/social/friendships?scope=incoming&limit=1')
    expect(clientB.items[0]).toMatchObject({ friendshipState: 'incoming_request', profile: { userId: 'tm_a' } })
    await jsonAPI(database, 'tm_b', `/api/v1/social/friendships/${encodeURIComponent(sent.friendship.id)}`, 'POST', { action: 'accept' })
    const secondClientA = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships?scope=friends')
    expect(secondClientA.items[0].friendshipState).toBe('friends')
  })

  it('allows explicit Companion linking only to an accepted friend without deleting history on unfriend', async () => {
    const companion = (linkedTasteMapUserId, displayName = '大学室友') => ({
      schemaVersion: 1, id: 'companion-social-test', userId: 'forged-owner', displayName,
      linkedTasteMapUserId, createdAt: NOW, updatedAt: NOW, deletedAt: null,
    })
    const pushCompanion = (suffix, baseVersion, payload) => api(database, 'tm_a', '/api/v1/sync/push', 'POST', {
      apiVersion: 1, schemaVersion: 1, mutations: [{
        mutationId: suffix, entityType: 'companion', entityId: payload.id,
        operation: 'upsert', baseVersion, clientTimestamp: payload.updatedAt, payload,
      }],
    })
    expect((await pushCompanion('link-before-friend', 0, companion('tm_b'))).status).toBe(403)
    const sent = await jsonAPI(database, 'tm_a', '/api/v1/social/friendships', 'POST', { targetUserId: 'tm_b' })
    await jsonAPI(database, 'tm_b', `/api/v1/social/friendships/${encodeURIComponent(sent.friendship.id)}`, 'POST', { action: 'accept' })
    const linked = await pushCompanion('link-after-friend', 0, companion('tm_b'))
    expect(linked.status).toBe(200)
    expect((await linked.json()).acknowledgements[0].status).toBe('applied')
    await jsonAPI(database, 'tm_a', `/api/v1/social/friendships/${encodeURIComponent(sent.friendship.id)}`, 'POST', { action: 'remove' })
    const renamed = await pushCompanion('rename-after-unfriend', 1, {
      ...companion('tm_b', '老同学'), updatedAt: '2026-08-28T14:01:00.000Z',
    })
    expect(renamed.status).toBe(200)
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id = 'companion-social-test'").linked_user_id).toBe('tm_b')
    expect((await pushCompanion('forge-new-link', 2, {
      ...companion('tm_c', '老同学'), updatedAt: '2026-08-28T14:02:00.000Z',
    })).status).toBe(403)
  })
})

async function seedUser(database, id, name, city, visibility) {
  await api(database, id, '/api/v1/sync/pull?schemaVersion=1&cursor=0')
  await database.prepare(`UPDATE user_profiles SET display_name = ?, bio = ?, city = ?, visibility = ?
    WHERE user_id = ?`).bind(name, `${name} 的公开简介`, city, visibility, id).run()
}

async function createVisit(database, userId, visibility) {
  const restaurantID = `restaurant-${userId}`
  const visitID = `visit-${userId}`
  const restaurant = {
    schemaVersion: 1, id: restaurantID, userId, name: '权限测试餐厅', address: 'Development', city: '杭州',
    latitude: 30.2, longitude: 120.1, status: 'visited', preferenceLevel: 'normal',
    overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
    valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null,
    openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
    markerEmoji: '🍜', placeIdentities: [{ provider: 'apple_maps', externalId: `apple-${userId}`,
      isPrimary: true, createdAt: NOW, updatedAt: NOW }], createdAt: NOW, updatedAt: NOW, deletedAt: null,
  }
  const visit = {
    schemaVersion: 1, id: visitID, userId, restaurantId: restaurantID, visitedAt: NOW,
    diningMode: 'dine_in', visibility, partySize: null, totalPrice: null, paymentMode: null,
    pricePerPerson: null, queueDuration: null, diningOccasions: [], diningOccasionText: null,
    rating: null, valueRating: null, environmentRating: null, serviceRating: null,
    valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null,
    portionLevel: null, transportConvenience: null, specialNotes: null, companions: [], companionIds: [],
    recommendationSourceId: null, recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId: null, note: null, myActualSpend: null,
    createdAt: NOW, updatedAt: NOW, deletedAt: null,
  }
  for (const [entityType, entityId, record] of [['restaurant', restaurantID, restaurant], ['visit', visitID, visit]]) {
    const response = await api(database, userId, '/api/v1/sync/push', 'POST', {
      apiVersion: 1, schemaVersion: 1, mutations: [{ mutationId: `create-${entityId}`,
        entityType, entityId, operation: 'upsert', baseVersion: 0, clientTimestamp: NOW, payload: record }],
    })
    expect(response.status).toBe(200)
  }
}

async function jsonAPI(database, viewer, path, method = 'GET', body) {
  const response = await api(database, viewer, path, method, body)
  const value = await response.json()
  if (!response.ok) throw new Error(`${response.status}: ${value.error}`)
  return value
}

function api(database, viewer, path, method = 'GET', body) {
  return worker.fetch(new Request(`https://development.example.test${path}`, {
    method,
    headers: { 'X-Taste-Map-Test-User': viewer, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), {
    DB: database, ASSETS: { fetch: () => new Response('not used') },
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
    '0025_discovery_v1_indexes.sql',
  ]) sqlite.exec(readFileSync(resolve('migrations', file), 'utf8'))
  return new SQLiteD1Database(sqlite)
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
    } catch (error) {
      this.sqlite.exec('ROLLBACK')
      throw error
    }
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
