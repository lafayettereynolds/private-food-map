import { createHash } from 'node:crypto'
import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from './index'
import { applyAllMigrations } from './testSupport/migrations.js'

const now = Date.now()
const iso = (minutesAgo = 0) => new Date(now - minutesAgo * 60_000).toISOString()

describe('Public Profile content and Community Feed V1 integration', () => {
  let database

  beforeEach(async () => {
    database = makeDatabase()
    for (const [id, name, visibility] of [
      ['tm_a', 'Alice', 'public'], ['tm_b', 'Bob', 'public'],
      ['tm_c', 'Carol', 'friends'], ['tm_private', 'Private', 'private'],
    ]) await seedUser(database, id, name, visibility)

    await seedVisit(database, { user: 'tm_b', slug: 'public-new', visibility: 'public', minutesAgo: 1, note: 'A truthful public note' })
    await seedVisit(database, { user: 'tm_b', slug: 'friends-middle', visibility: 'friends', minutesAgo: 2 })
    await seedVisit(database, { user: 'tm_b', slug: 'private-old', visibility: 'private', minutesAgo: 3 })
    await seedVisit(database, { user: 'tm_private', slug: 'hidden-profile', visibility: 'public', minutesAgo: 4 })
    await seedRestaurant(database, { user: 'tm_b', slug: 'wanted', status: 'wantToGo', minutesAgo: 5 })
  })

  it('returns a strict public allowlist, viewer-dependent statistics, and public WantToGo content', async () => {
    const page = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=visits')
    expect(page).toMatchObject({ apiVersion: 1, targetUserId: 'tm_b', section: 'visits' })
    expect(page.items.map((item) => item.restaurant.name)).toEqual(['public-new'])
    expect(page.statistics).toEqual({
      visibleRestaurantCount: 1, visibleVisitCount: 1, visibleWantToGoCount: 1,
    })
    expect(Object.keys(page.items[0].visit).sort()).toEqual([
      'id', 'note', 'ownerUserId', 'photos', 'rating', 'restaurantGlobalKey',
      'updatedAt', 'visibility', 'visitedAt',
    ])
    const serialized = JSON.stringify(page)
    for (const forbidden of ['actualSpend', 'partySize', 'companion', 'recommendationSource',
      'storageKey', 'refreshToken', 'appleSub', 'userId":"tm_a']) {
      expect(serialized).not.toContain(forbidden)
    }

    const wants = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=want_to_go')
    expect(wants.items).toHaveLength(1)
    expect(wants.items[0]).toMatchObject({ kind: 'want_to_go', visit: null, cacheScope: 'public' })
  })

  it('counts only records visible to the current viewer and never reveals total private activity', async () => {
    for (let index = 0; index < 4; index += 1) {
      await seedVisit(database, { user: 'tm_b', slug: `public-stat-${index}`, visibility: 'public', minutesAgo: 30 + index })
    }
    for (let index = 0; index < 2; index += 1) {
      await seedVisit(database, { user: 'tm_b', slug: `friend-stat-${index}`, visibility: 'friends', minutesAgo: 40 + index })
    }
    for (let index = 0; index < 11; index += 1) {
      await seedVisit(database, { user: 'tm_b', slug: `private-stat-${index}`, visibility: 'private', minutesAgo: 50 + index })
    }
    const stranger = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=visits&limit=50')
    expect(stranger.statistics.visibleVisitCount).toBe(5)
    await acceptFriendship(database, 'tm_a', 'tm_b')
    const friend = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=visits&limit=50')
    expect(friend.statistics.visibleVisitCount).toBe(8)
    expect(friend.statistics.visibleVisitCount).not.toBe(20)
  })

  it('enforces public, friends and private profile/Visit visibility and revokes access immediately', async () => {
    expect((await api(database, 'tm_a', '/api/v1/community/users/tm_private/content')).status).toBe(404)
    expect((await api(database, 'tm_a', '/api/v1/community/users/tm_c/content')).status).toBe(404)

    await acceptFriendship(database, 'tm_a', 'tm_b')
    let page = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=visits')
    expect(page.items.map((item) => item.restaurant.name)).toEqual(['public-new', 'friends-middle'])
    expect(page.items.find((item) => item.restaurant.name === 'friends-middle').cacheScope).toBe('friends')
    expect(page.statistics.visibleVisitCount).toBe(2)

    await acceptFriendship(database, 'tm_a', 'tm_c')
    expect((await api(database, 'tm_a', '/api/v1/community/users/tm_c/content')).status).toBe(200)

    database.prepare("UPDATE friendships SET status = 'removed', deleted_at = ? WHERE pair_user_a = 'tm_a' AND pair_user_b = 'tm_b'").bind(iso()).run()
    page = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=visits')
    expect(page.items.map((item) => item.restaurant.name)).toEqual(['public-new'])
  })

  it('builds latest/following feeds from real Visits, preserves event order on edit, and paginates without duplicates', async () => {
    for (let index = 0; index < 5; index += 1) {
      await seedVisit(database, { user: index % 2 === 0 ? 'tm_b' : 'tm_c', slug: `page-${index}`, minutesAgo: 10 + index })
    }
    await seedVisit(database, { user: 'tm_b', slug: 'page-extra-a', minutesAgo: 20 })
    await seedVisit(database, { user: 'tm_b', slug: 'page-extra-b', minutesAgo: 21 })
    const first = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest&limit=2')
    expect(first.items).toHaveLength(2)
    expect(first.nextCursor).toBeTypeOf('string')
    const second = await jsonAPI(database, 'tm_a', `/api/v1/community/feed?scope=latest&limit=2&cursor=${encodeURIComponent(first.nextCursor)}`)
    expect(new Set([...first.items, ...second.items].map((item) => item.id)).size)
      .toBe(first.items.length + second.items.length)
    expect((await api(database, 'tm_a', '/api/v1/community/feed?scope=latest&cursor=invalid')).status).toBe(400)

    const visitID = first.items[0].visit.id
    const originalEventAt = first.items[0].eventAt
    database.prepare('UPDATE visits SET note = ?, updated_at = ? WHERE id = ?')
      .bind('edited without becoming newly visited', iso(-60), visitID).run()
    const edited = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest&limit=50')
    const item = edited.items.find((candidate) => candidate.visit?.id === visitID)
    expect(item.eventAt).toBe(originalEventAt)
    expect(item.visit.note).toBe('edited without becoming newly visited')
  })

  it('keeps follow distinct from friendship: following grants discovery of public content but not friends-only content', async () => {
    await follow(database, 'tm_a', 'tm_b')
    let page = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=following')
    expect(page.items.map((item) => item.restaurant.name)).toContain('public-new')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('friends-middle')

    await acceptFriendship(database, 'tm_a', 'tm_b')
    page = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=following')
    expect(page.items.map((item) => item.restaurant.name)).toContain('friends-middle')
    expect(page.items.find((item) => item.restaurant.name === 'friends-middle').cacheScope).toBe('friends')
  })

  it('removes tombstoned content and never exposes a private-profile Visit in latest', async () => {
    let page = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest')
    expect(page.items.map((item) => item.restaurant.name)).toContain('public-new')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('hidden-profile')
    database.prepare("UPDATE visits SET deleted_at = ?, server_version = server_version + 1 WHERE id = 'visit-tm_b-public-new'")
      .bind(iso()).run()
    page = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('public-new')
  })

  it('does not treat a stable public Restaurant hash as authorization', async () => {
    const identity = 'restaurant:public-new|杭州|public-new路1号'
    const publicID = createHash('sha256').update(`taste-map-public:${identity}`).digest('hex').slice(0, 24)
    expect((await api(database, 'tm_a', `/api/public/restaurants/${publicID}`)).status).toBe(200)
    database.prepare("UPDATE user_profiles SET visibility = 'private' WHERE user_id = 'tm_b'").run()
    expect((await api(database, 'tm_a', `/api/public/restaurants/${publicID}`)).status).toBe(404)
  })

  it('returns only authorized photo identifiers, never R2 keys, and no private Visit photos', async () => {
    await seedPhoto(database, 'visit-tm_b-public-new', 'public')
    await seedPhoto(database, 'visit-tm_b-private-old', 'private')
    const page = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/content?section=visits')
    expect(page.items[0].visit.photos).toEqual([
      expect.objectContaining({
        photoId: 'photo-visit-tm_b-public-new',
        variant: 'thumbnail',
        sourceType: 'activityAuthorPhoto',
        ownerUserId: 'tm_b',
        visibility: 'public',
        exportAllowed: false,
      }),
    ])
    expect(JSON.stringify(page)).not.toContain('storage_key')
    expect(JSON.stringify(page)).not.toContain('users/tm_b/photos')
  })

  it('uses authenticated identity, ignores a forged userId, and rejects unauthenticated access', async () => {
    const normal = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest')
    const forged = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest&userId=tm_b')
    expect(forged.items).toEqual(normal.items)
    expect((await api(database, '', '/api/v1/community/feed?scope=latest')).status).toBe(401)
    expect((await api(database, 'tm_a', '/api/v1/community/feed', 'POST')).status).toBe(405)
  })

  it('hydrates 30 Community cards with a bounded number of D1 statements', async () => {
    for (let index = 0; index < 30; index += 1) {
      await seedVisit(database, {
        user: 'tm_b', slug: `scale-${String(index).padStart(2, '0')}`,
        visibility: 'public', minutesAgo: 100 + index,
      })
    }
    database.resetStatementCount()
    const page = await jsonAPI(database, 'tm_a', '/api/v1/community/feed?scope=latest&limit=30')
    expect(page.items).toHaveLength(30)
    // Engagement hydration adds two bounded aggregate statements regardless
    // of card count; the feed still avoids per-item queries.
    expect(database.statementCount).toBeLessThanOrEqual(14)
  })
})

async function seedUser(database, id, name, visibility) {
  await api(database, id, '/api/v1/sync/pull?schemaVersion=1&cursor=0')
  await database.prepare('UPDATE user_profiles SET display_name = ?, bio = ?, city = ?, visibility = ? WHERE user_id = ?')
    .bind(name, `${name} bio`, '杭州', visibility, id).run()
}

async function seedRestaurant(database, { user, slug, status = 'visited', minutesAgo = 0 }) {
  const id = `restaurant-${user}-${slug}`
  await database.prepare(`INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, tags_json, created_at, updated_at
  ) VALUES (?, ?, '', ?, ?, '杭州', 30.25, 120.16, ?, 'normal', 'emoji', '🍜', '["面"]', ?, ?)`)
    .bind(id, user, slug, `${slug}路 1 号`, status, iso(minutesAgo), iso(minutesAgo)).run()
  await database.prepare(`INSERT INTO restaurant_place_identities (
    restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
  ) VALUES (?, ?, 'apple_maps', ?, 1, ?, ?)`)
    .bind(id, user, `apple-${slug}`, iso(minutesAgo), iso(minutesAgo)).run()
  return id
}

async function seedVisit(database, {
  user, slug, visibility = 'public', minutesAgo = 0, note = '', rating = 4.5,
}) {
  const restaurant = await seedRestaurant(database, { user, slug, minutesAgo })
  await database.prepare(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, party_size, note, created_at,
    updated_at, visibility
  ) VALUES (?, ?, ?, ?, ?, 2, ?, ?, ?, ?)`)
    .bind(`visit-${user}-${slug}`, user, restaurant, iso(minutesAgo), rating, note,
      iso(minutesAgo), iso(minutesAgo), visibility).run()
}

async function seedPhoto(database, visitID, visibility) {
  const visit = database.get('SELECT user_id, restaurant_id FROM visits WHERE id = ?', visitID)
  await database.prepare(`INSERT INTO photos (
    id, user_id, restaurant_id, visit_id, storage_provider, storage_key,
    thumbnail_storage_key, drive_account_id, drive_file_id, kind, mime_type,
    file_size, visibility, sync_status, sort_order, created_at, updated_at
  ) VALUES (?, ?, ?, ?, 'r2', ?, ?, '', '', 'visit', 'image/jpeg', 512, ?, 'synced', 0, ?, ?)`)
    .bind(`photo-${visitID}`, visit.user_id, visit.restaurant_id, visitID,
      `users/${visit.user_id}/photos/photo-${visitID}/display.jpg`,
      `users/${visit.user_id}/photos/photo-${visitID}/thumbnail.jpg`, visibility, iso(), iso()).run()
}

async function acceptFriendship(database, requester, addressee) {
  const pair = [requester, addressee].sort()
  await database.prepare(`INSERT OR REPLACE INTO friendships (
    id, requester_id, addressee_id, status, created_at, updated_at,
    pair_user_a, pair_user_b, server_version, deleted_at
  ) VALUES (?, ?, ?, 'accepted', ?, ?, ?, ?, 1, NULL)`)
    .bind(`friend-${pair.join('-')}`, requester, addressee, iso(), iso(), pair[0], pair[1]).run()
}

async function follow(database, follower, followed) {
  await database.prepare(`INSERT INTO follows (
    id, follower_id, followed_user_id, created_at, updated_at, deleted_at, server_version
  ) VALUES (?, ?, ?, ?, ?, NULL, 1)`)
    .bind(`follow-${follower}-${followed}`, follower, followed, iso(), iso()).run()
}

async function jsonAPI(database, viewer, path) {
  const response = await api(database, viewer, path)
  const body = await response.json()
  if (!response.ok) throw new Error(`${response.status}: ${body.error}`)
  return body
}

function api(database, viewer, path, method = 'GET') {
  return worker.fetch(new Request(`https://development.example.test${path}`, {
    method, headers: viewer ? { 'X-Taste-Map-Test-User': viewer } : {},
  }), {
    DB: database, ASSETS: { fetch: () => new Response('not used') },
    APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test',
  })
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  applyAllMigrations(sqlite)
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
