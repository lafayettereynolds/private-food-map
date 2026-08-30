import { readFileSync, readdirSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import { createPublicShareV1, PublicSharingV1Error, readPublicShareV1 } from './publicSharingV1'

const at = '2026-08-30T00:00:00.000Z'
let database

beforeEach(() => {
  database = makeDatabase()
  seedUser('tm_share_a', '公开用户 A', 'public')
  seedUser('tm_share_b', '公开用户 B', 'public')
  seedRestaurantVisit('tm_share_a', 'restaurant-apple-only', 'visit-public', 'public')
})

describe('Task 09 public sharing', () => {
  it('issues a stable opaque Restaurant URL without exposing internal identities', async () => {
    const first = await create('tm_share_a', 'restaurant', 'restaurant-apple-only')
    const retry = await create('tm_share_a', 'restaurant', 'restaurant-apple-only')
    const publicValue = await read(first.shareId)
    const serialized = JSON.stringify(publicValue)

    expect(first).toMatchObject({ apiVersion: 1, entityType: 'restaurant' })
    expect(first.shareId).toHaveLength(32)
    expect(first.url).toBe(`https://share.development.test/share/${first.shareId}`)
    expect(retry.shareId).toBe(first.shareId)
    expect(first.url).not.toContain('restaurant-apple-only')
    expect(serialized).toContain('Apple-only 餐厅')
    for (const forbidden of ['tm_share_a', 'restaurant-apple-only', 'visit-public', 'apple-place-id', 'amapPoiId']) {
      expect(serialized).not.toContain(forbidden)
    }
  })

  it('dynamically revokes Restaurant access after privacy, deletion, or profile changes', async () => {
    const share = await create('tm_share_a', 'restaurant', 'restaurant-apple-only')
    database.get("UPDATE visits SET visibility = 'private' WHERE id = 'visit-public'")
    await expect(read(share.shareId)).rejects.toMatchObject({ status: 404 })
    database.get("UPDATE visits SET visibility = 'public' WHERE id = 'visit-public'")
    database.get("UPDATE user_profiles SET visibility = 'private' WHERE user_id = 'tm_share_a'")
    await expect(read(share.shareId)).rejects.toMatchObject({ status: 404 })
    database.get("UPDATE user_profiles SET visibility = 'public' WHERE user_id = 'tm_share_a'")
    database.get("UPDATE restaurants SET deleted_at = ? WHERE id = 'restaurant-apple-only'", at)
    await expect(read(share.shareId)).rejects.toMatchObject({ status: 404 })
  })

  it('publishes an allowlisted Profile projection and stops when the profile becomes private', async () => {
    const share = await create('tm_share_a', 'profile', 'tm_share_a')
    const value = await read(share.shareId)
    const serialized = JSON.stringify(value)
    expect(value.entity).toMatchObject({ displayName: '公开用户 A', statistics: { restaurantCount: 1, visitCount: 1 } })
    for (const forbidden of ['tm_share_a', 'serverVersion', 'apple_sub', 'email', 'auth']) {
      expect(serialized).not.toContain(forbidden)
    }
    database.get("UPDATE user_profiles SET visibility = 'friends' WHERE user_id = 'tm_share_a'")
    await expect(read(share.shareId)).rejects.toMatchObject({ status: 404 })
  })

  it('publishes only a public List and strips owner, global identity, and business record IDs', async () => {
    seedList('tm_share_a', 'list-public', 'public')
    const share = await create('tm_share_a', 'list', 'list-public')
    const value = await read(share.shareId)
    const serialized = JSON.stringify(value)
    expect(value.entity).toMatchObject({ title: '杭州清单', ownerDisplayName: '公开用户 A', restaurantCount: 1 })
    expect(value.entity.restaurants[0]).toMatchObject({ name: 'Apple-only 餐厅', note: '值得回去' })
    for (const forbidden of ['tm_share_a', 'list-public', 'list-item-public', 'apple_maps:', 'restaurant-apple-only']) {
      expect(serialized).not.toContain(forbidden)
    }
    database.get("UPDATE restaurant_lists SET visibility = 'private' WHERE id = 'list-public'")
    await expect(read(share.shareId)).rejects.toMatchObject({ status: 404 })
  })

  it('prevents a verified user from issuing links for another owner via forged entity IDs', async () => {
    await expect(create('tm_share_b', 'restaurant', 'restaurant-apple-only'))
      .rejects.toBeInstanceOf(PublicSharingV1Error)
    await expect(create('tm_share_b', 'profile', 'tm_share_a'))
      .rejects.toMatchObject({ status: 404 })
    expect(database.get('SELECT COUNT(*) AS value FROM public_share_links').value).toBe(0)
  })

  it('rejects private content and malformed public IDs without creating a share row', async () => {
    seedList('tm_share_a', 'list-private', 'private')
    await expect(create('tm_share_a', 'list', 'list-private')).rejects.toMatchObject({ status: 404 })
    await expect(read('restaurant-apple-only')).rejects.toMatchObject({ status: 404 })
    expect(database.get('SELECT COUNT(*) AS value FROM public_share_links').value).toBe(0)
  })
})

function create(owner, entityType, entityId) {
  return createPublicShareV1(new Request('https://api.development.test/api/v1/public-shares', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ entityType, entityId }),
  }), database, owner, { PUBLIC_SHARE_ORIGIN: 'https://share.development.test' })
}

function read(shareID) {
  return readPublicShareV1(new Request(`https://api.development.test/api/public/shares/${shareID}`, {
    headers: { 'CF-Connecting-IP': '203.0.113.42' },
  }), database, shareID)
}

function seedUser(id, name, visibility) {
  database.get(`INSERT INTO users (id, nickname, created_at, updated_at, is_test_user)
    VALUES (?, ?, ?, ?, 1)`, id, name, at, at)
  database.get(`INSERT INTO user_profiles (
    user_id, display_name, bio, city, avatar_preset_id, visibility,
    created_at, updated_at, server_version, last_mutation_id
  ) VALUES (?, ?, '公开简介', '杭州', 'polar-bear', ?, ?, ?, 1, ?)`,
  id, name, visibility, at, at, `seed:profile:${id}`)
}

function seedRestaurantVisit(user, restaurantID, visitID, visibility) {
  database.get(`INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, tags_json, created_at, updated_at,
    deleted_at, server_version
  ) VALUES (?, ?, '', 'Apple-only 餐厅', '西湖路 1 号', '杭州', 30.25, 120.16,
    'visited', 'normal', 'emoji', '🍣', '["日料"]', ?, ?, NULL, 1)`, restaurantID, user, at, at)
  database.get(`INSERT INTO restaurant_place_identities (
    restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
  ) VALUES (?, ?, 'apple_maps', 'apple-place-id', 1, ?, ?)`, restaurantID, user, at, at)
  database.get(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, party_size, note,
    created_at, updated_at, visibility, deleted_at, server_version
  ) VALUES (?, ?, ?, ?, 4.5, 2, '私人备注不能泄露', ?, ?, ?, NULL, 1)`,
  visitID, user, restaurantID, at, at, at, visibility)
}

function seedList(user, listID, visibility) {
  database.get(`INSERT INTO restaurant_lists (
    id, user_id, title, description, visibility, is_ranked, cover_mode,
    created_at, updated_at, server_version, last_mutation_id, active_item_count
  ) VALUES (?, ?, '杭州清单', '公开说明', ?, 1, 'automatic', ?, ?, 1, ?, 1)`,
  listID, user, visibility, at, at, `seed:list:${listID}`)
  database.get(`INSERT INTO restaurant_list_items (
    id, list_id, restaurant_id, position, note, created_at, updated_at,
    user_id, restaurant_global_key, restaurant_snapshot_json, server_version, last_mutation_id
  ) VALUES ('list-item-public', ?, 'restaurant-apple-only', 0, '值得回去', ?, ?, ?,
    'apple_maps:apple-place-id', NULL, 1, 'seed:list-item')`, listID, at, at, user)
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  for (const file of readdirSync(resolve('migrations')).filter((value) => /^\d{4}.*\.sql$/.test(value)).sort()) {
    sqlite.exec(readFileSync(resolve('migrations', file), 'utf8'))
  }
  return new SQLiteD1Database(sqlite)
}

class SQLiteD1Database {
  constructor(sqlite) { this.sqlite = sqlite }
  prepare(sql) { return new SQLiteD1Statement(this.sqlite, sql) }
  get(sql, ...values) {
    const statement = this.sqlite.prepare(sql)
    return /^\s*(SELECT|PRAGMA|WITH)\b/i.test(sql) ? statement.get(...values) : statement.run(...values)
  }
  async batch(statements) {
    this.sqlite.exec('BEGIN IMMEDIATE')
    try { const values = statements.map((statement) => statement.batchSync()); this.sqlite.exec('COMMIT'); return values }
    catch (error) { this.sqlite.exec('ROLLBACK'); throw error }
  }
}

class SQLiteD1Statement {
  constructor(sqlite, sql, values = []) { this.sqlite = sqlite; this.sql = sql; this.values = values }
  bind(...values) { return new SQLiteD1Statement(this.sqlite, this.sql, values) }
  async first() { return this.sqlite.prepare(this.sql).get(...this.values) ?? null }
  async all() { return { results: this.sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} } }
  async run() { return this.runSync() }
  batchSync() { return /^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)
    ? { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} }
    : this.runSync() }
  runSync() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } }
  }
}
