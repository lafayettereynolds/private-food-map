import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from './index'

const CITY = '杭州'
const now = Date.now()
const iso = (daysAgo = 0, minutesAgo = 0) => new Date(now - daysAgo * 86_400_000 - minutesAgo * 60_000).toISOString()

describe('Discovery API V1 integration', () => {
  let database

  beforeEach(async () => {
    database = makeDatabase()
    for (const [id, name, visibility] of [
      ['tm_a', 'Alice', 'public'], ['tm_b', 'Bob', 'public'], ['tm_c', 'Carol', 'public'],
      ['tm_d', 'Dan', 'public'], ['tm_private', 'Private User', 'private'],
    ]) await seedUser(database, id, name, visibility)

    for (const [index, rating] of [5, 4.5, 4].entries()) {
      await seedVisit(database, { user: 'tm_a', slug: `shared-${index}`, rating, identity: `apple-shared-${index}` })
      await seedVisit(database, { user: 'tm_b', slug: `shared-${index}`, rating: rating - 0.5, identity: `apple-shared-${index}` })
      await seedVisit(database, { user: 'tm_c', slug: `shared-${index}`, rating: 5.5 - rating, identity: `apple-shared-${index}` })
    }
    await seedVisit(database, { user: 'tm_b', slug: 'bob-pick', rating: 5, identity: 'apple-bob-pick', tags: ['日料'] })
    await seedVisit(database, { user: 'tm_c', slug: 'carol-pick', rating: 4.5, identity: 'apple-carol-pick', tags: ['咖啡'] })
    await seedVisit(database, { user: 'tm_private', slug: 'secret-pick', rating: 5, visibility: 'private' })
    await seedVisit(database, { user: 'tm_private', slug: 'hidden-profile-public', rating: 5, visibility: 'public' })
    await seedVisit(database, { user: 'tm_b', slug: 'friend-pick', rating: 5, visibility: 'friends' })
  })

  it('uses real history for For You, excludes visited places, distinguishes ratings, and emits truthful reasons', async () => {
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.apiVersion).toBe(1)
    expect(page.mode).toBe('for_you')
    expect(page.personalizationConfidence).toBe('medium')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('shared-0')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('secret-pick')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('hidden-profile-public')
    expect(page.items[0].ratings).toEqual(expect.objectContaining({
      mine: expect.objectContaining({ value: null }),
      community: expect.objectContaining({ sampleCount: expect.any(Number) }),
      friends: expect.any(Object), similarTaste: expect.any(Object),
    }))
    expect(page.items.flatMap((item) => item.reasons).every((reason) => reason.text && reason.code)).toBe(true)
    expect(JSON.stringify(page)).not.toContain('note')
    expect(JSON.stringify(page)).not.toContain('storageKey')
  })

  it('falls back to explicitly labelled city trending for a new user without claiming personalization', async () => {
    await seedUser(database, 'tm_new', 'New User', 'public')
    const page = await jsonAPI(database, 'tm_new', '/api/v1/discovery/for-you?city=杭州')
    expect(page.personalizationConfidence).toBe('insufficient')
    expect(page.items.length).toBeGreaterThan(0)
    expect(page.items[0].reasons[0]).toMatchObject({ code: 'COLD_START_TRENDING' })
  })

  it('requires three shared restaurants, ranks aligned users stably, and never recommends self', async () => {
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/similar-taste?city=杭州')
    const bob = page.items.find((item) => item.sourceUser?.userId === 'tm_b')
    expect(bob?.similarity.sharedRestaurantCount).toBeGreaterThanOrEqual(3)
    expect(bob?.similarity.percent).toBeGreaterThan(50)
    expect(page.items.every((item) => item.sourceUser?.userId !== 'tm_a')).toBe(true)
    expect(page.items.find((item) => item.sourceUser?.userId === 'tm_c')).toBeUndefined()

    await seedUser(database, 'tm_sparse', 'Sparse', 'public')
    await seedVisit(database, { user: 'tm_sparse', slug: 'shared-0-copy', rating: 5, identity: 'apple-shared-0' })
    const sparsePage = await jsonAPI(database, 'tm_sparse', '/api/v1/discovery/similar-taste?city=杭州')
    expect(sparsePage.items).toEqual([])
  })

  it('keeps nil and tombstoned ratings out of similarity and community aggregation', async () => {
    await seedVisit(database, { user: 'tm_b', slug: 'nil-rating', rating: null })
    await seedVisit(database, { user: 'tm_b', slug: 'deleted-rating', rating: 5, deleted: true })
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('nil-rating')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('deleted-rating')
  })

  it('uses 7/30-day windows, unique users, stable tie breaks, and excludes old/private/tombstoned activity', async () => {
    for (let index = 0; index < 5; index += 1) {
      await seedVisit(database, { user: 'tm_b', slug: `repeat-${index}`, name: 'Repeat Place', identity: 'apple-repeat', rating: 5, minutesAgo: index })
    }
    await seedVisit(database, { user: 'tm_c', slug: 'unique-c', name: 'Unique Place', identity: 'apple-unique', rating: 5 })
    await seedVisit(database, { user: 'tm_d', slug: 'unique-d', name: 'Unique Place', identity: 'apple-unique', rating: 4.5 })
    await seedVisit(database, { user: 'tm_b', slug: 'old-20', rating: 5, daysAgo: 20 })
    await seedVisit(database, { user: 'tm_b', slug: 'old-40', rating: 5, daysAgo: 40 })
    const week = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&window=7')
    const month = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&window=30')
    expect(week.items.find((item) => item.restaurant.name === 'Repeat Place').trend.uniqueVisitorCount).toBe(1)
    expect(week.items.findIndex((item) => item.restaurant.name === 'Unique Place'))
      .toBeLessThan(week.items.findIndex((item) => item.restaurant.name === 'Repeat Place'))
    expect(week.items.map((item) => item.restaurant.name)).not.toContain('old-20')
    expect(month.items.map((item) => item.restaurant.name)).toContain('old-20')
    expect(month.items.map((item) => item.restaurant.name)).not.toContain('old-40')
    expect(week.items.map((item) => item.restaurant.name)).not.toContain('secret-pick')
    expect(week.items.map((item) => item.restaurant.name)).not.toContain('hidden-profile-public')
    const keys = week.items.map((item) => item.restaurant.globalKey)
    expect(keys).toEqual([...new Set(keys)])
  })

  it('supports deterministic opaque cursor pagination without duplicates', async () => {
    for (let index = 0; index < 5; index += 1) {
      await seedVisit(database, { user: index % 2 ? 'tm_b' : 'tm_c', slug: `page-${index}`, rating: 4.5, minutesAgo: index })
    }
    const first = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&limit=2')
    expect(first.items).toHaveLength(2)
    expect(first.nextCursor).toBeTypeOf('string')
    const second = await jsonAPI(database, 'tm_a', `/api/v1/discovery/trending?city=杭州&limit=2&cursor=${encodeURIComponent(first.nextCursor)}`)
    expect(new Set([...first.items, ...second.items].map((item) => item.restaurant.globalKey)).size)
      .toBe(first.items.length + second.items.length)
    expect((await api(database, 'tm_a', '/api/v1/discovery/trending?cursor=invalid&city=杭州')).status).toBe(400)
  })

  it('makes friends-only signals visible only to accepted friends and revokes them immediately on unfriend', async () => {
    let page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('friend-pick')
    await acceptFriendship(database, 'tm_a', 'tm_b')
    page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const friendCard = page.items.find((item) => item.restaurant.name === 'friend-pick')
    expect(friendCard?.cacheScope).toBe('friends')
    expect(friendCard?.sourceUser.userId).toBe('tm_b')
    database.prepare("UPDATE friendships SET status = 'removed', deleted_at = ? WHERE pair_user_a = 'tm_a' AND pair_user_b = 'tm_b'").bind(iso()).run()
    page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('friend-pick')
  })

  it('allowlists PublicProfile and photo projections without leaking private source content', async () => {
    const publicVisit = await seedVisit(database, { user: 'tm_b', slug: 'photo-public', rating: 5 })
    await seedPhoto(database, publicVisit, 'public')
    const privateVisit = await seedVisit(database, { user: 'tm_b', slug: 'photo-private', rating: 5, visibility: 'private' })
    await seedPhoto(database, privateVisit, 'private')
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const card = page.items.find((item) => item.restaurant.name === 'photo-public')
    expect(Object.keys(card.sourceUser).sort()).toEqual([
      'avatarPhotoId', 'avatarPresetId', 'bio', 'city', 'displayName', 'friendshipId',
      'friendshipState', 'isFollowing', 'userId',
    ])
    expect(card.restaurant.photo).toMatchObject({ photoId: `photo-${publicVisit}`, variant: 'thumbnail' })
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('photo-private')
  })

  it('ignores forged userId and keeps users isolated under authenticated actor', async () => {
    const forged = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州&userId=tm_b')
    const normal = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(forged.items).toEqual(normal.items)
    expect((await api(database, '', '/api/v1/discovery/for-you?city=杭州')).status).toBe(401)
  })

  it('uses provider identities to collapse duplicate user-owned Restaurant rows and reports viewer WantToGo/visited state', async () => {
    await seedRestaurant(database, { user: 'tm_a', slug: 'want-local', name: 'Bob Pick Local', identity: 'apple-bob-pick', status: 'wantToGo' })
    await seedVisit(database, { user: 'tm_c', slug: 'bob-pick-copy', name: 'Bob Pick Copy', identity: 'apple-bob-pick', rating: 5 })
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州')
    const matching = page.items.filter((item) => item.restaurant.placeIdentities.some((identity) => identity.externalId === 'apple-bob-pick'))
    expect(matching).toHaveLength(1)
    expect(matching[0].viewerState).toBe('want_to_go')
    expect(page.items.filter((item) => item.restaurant.name.startsWith('shared-')).every((item) => item.viewerState === 'visited')).toBe(true)
  })

  it('treats isolated WantToGo as private, aggregates a cohort, and rate limits authenticated actors', async () => {
    const restaurant = await seedRestaurant(database, { user: 'tm_b', slug: 'wanted', name: 'Wanted Place' })
    database.prepare('INSERT INTO want_to_go (id, user_id, restaurant_id, created_at) VALUES (?, ?, ?, ?)')
      .bind('want-one', 'tm_b', restaurant, iso()).run()
    let page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州')
    expect(page.items.find((item) => item.restaurant.name === 'Wanted Place')).toBeUndefined()
    database.prepare('INSERT INTO want_to_go (id, user_id, restaurant_id, created_at) VALUES (?, ?, ?, ?)')
      .bind('want-two', 'tm_c', restaurant, iso()).run()
    page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州')
    expect(page.items.find((item) => item.restaurant.name === 'Wanted Place')?.trend.wantToGoCount).toBe(2)
    database.prepare("UPDATE discovery_rate_limits SET request_count = 120 WHERE user_id = 'tm_a'").run()
    expect((await api(database, 'tm_a', '/api/v1/discovery/trending?city=杭州')).status).toBe(429)
  })

  it('projects 30 Discovery cards without item-by-item D1 queries', async () => {
    for (let index = 0; index < 30; index += 1) {
      await seedVisit(database, {
        user: index % 2 === 0 ? 'tm_b' : 'tm_c',
        slug: `scale-${String(index).padStart(2, '0')}`,
        identity: `apple-scale-${index}`, rating: 4.5, minutesAgo: 100 + index,
      })
    }
    database.resetStatementCount()
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&limit=30')
    expect(page.items).toHaveLength(30)
    expect(database.statementCount).toBeLessThanOrEqual(20)
  })
})

async function seedUser(database, id, name, visibility) {
  await api(database, id, '/api/v1/sync/pull?schemaVersion=1&cursor=0')
  await database.prepare(`UPDATE user_profiles SET display_name = ?, bio = ?, city = ?, visibility = ? WHERE user_id = ?`)
    .bind(name, `${name} bio`, CITY, visibility, id).run()
}

async function seedRestaurant(database, {
  user, slug, name = slug, identity = `apple-${slug}`, status = 'visited', city = CITY,
}) {
  const id = `restaurant-${user}-${slug}`
  await database.prepare(`INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, tags_json, created_at, updated_at
  ) VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, 'normal', 'emoji', '🍜', '[]', ?, ?)`)
    .bind(id, user, name, `${name}路 1 号`, city, 30.2 + slug.length / 10_000, 120.1 + slug.length / 10_000,
      status, iso(3), iso(1)).run()
  await database.prepare(`INSERT INTO restaurant_place_identities (
    restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
  ) VALUES (?, ?, 'apple_maps', ?, 1, ?, ?)`)
    .bind(id, user, identity, iso(3), iso(1)).run()
  return id
}

async function seedVisit(database, {
  user, slug, name = slug, identity = `apple-${slug}`, rating = 4.5,
  visibility = 'public', tags = [], daysAgo = 0, minutesAgo = 0, deleted = false,
}) {
  const restaurant = await seedRestaurant(database, { user, slug, name, identity })
  const id = `visit-${user}-${slug}`
  await database.prepare(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, party_size, note, created_at,
    updated_at, deleted_at, visibility
  ) VALUES (?, ?, ?, ?, ?, 1, '', ?, ?, ?, ?)`)
    .bind(id, user, restaurant, iso(daysAgo, minutesAgo), rating, iso(daysAgo, minutesAgo),
      iso(daysAgo, minutesAgo), deleted ? iso() : null, visibility).run()
  await database.prepare('UPDATE restaurants SET tags_json = ? WHERE id = ?').bind(JSON.stringify(tags), restaurant).run()
  return id
}

async function seedPhoto(database, visitID, visibility) {
  const visit = database.get('SELECT user_id, restaurant_id FROM visits WHERE id = ?', visitID)
  await database.prepare(`INSERT INTO photos (
    id, user_id, restaurant_id, visit_id, storage_provider, drive_account_id,
    drive_file_id, kind, mime_type, file_size, visibility, sync_status, created_at, updated_at
  ) VALUES (?, ?, ?, ?, 'r2', '', '', 'visit', 'image/jpeg', 512, ?, 'synced', ?, ?)`)
    .bind(`photo-${visitID}`, visit.user_id, visit.restaurant_id, visitID, visibility, iso(), iso()).run()
}

async function acceptFriendship(database, requester, addressee) {
  const pair = [requester, addressee].sort()
  await database.prepare(`INSERT INTO friendships (
    id, requester_id, addressee_id, status, created_at, updated_at, pair_user_a, pair_user_b, server_version
  ) VALUES (?, ?, ?, 'accepted', ?, ?, ?, ?, 1)`)
    .bind(`friend-${requester}-${addressee}`, requester, addressee, iso(), iso(), pair[0], pair[1]).run()
}

async function jsonAPI(database, viewer, path) {
  const response = await api(database, viewer, path)
  const value = await response.json()
  if (!response.ok) throw new Error(`${response.status}: ${value.error}`)
  return value
}

function api(database, viewer, path, method = 'GET', body) {
  return worker.fetch(new Request(`https://development.example.test${path}`, {
    method,
    headers: { ...(viewer ? { 'X-Taste-Map-Test-User': viewer } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
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
    '0025_discovery_v1_indexes.sql', '0026_public_community_v1_indexes.sql',
    '0027_social_hardening.sql', '0028_restaurant_lists_v1.sql',
  ]) sqlite.exec(readFileSync(resolve('migrations', file), 'utf8'))
  return new SQLiteD1Database(sqlite)
}

class SQLiteD1Database {
  constructor(sqlite) { this.sqlite = sqlite; this.statementCount = 0 }
  prepare(sql) { this.statementCount += 1; return new SQLiteD1Statement(this.sqlite, sql) }
  resetStatementCount() { this.statementCount = 0 }
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
    if (/^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)) return { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} }
    return this.runSync()
  }
  runSync() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes) } }
  }
}
