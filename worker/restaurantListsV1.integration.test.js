import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import { ensureUserProfile } from './profileV1'
import { handleRestaurantListsV1, RestaurantListsV1RequestError } from './restaurantListsV1'
import { handleSyncV1Pull, handleSyncV1Push, SyncV1RequestError } from './syncV1'
import { applyAllMigrations } from './testSupport/migrations.js'

const at = '2026-08-28T20:00:00.000Z'
let database

beforeEach(async () => {
  database = makeDatabase()
  await seedUser(database, 'tm_list_a', 'Alpha')
  await seedUser(database, 'tm_list_b', 'Beta')
  await seedUser(database, 'tm_list_c', 'Gamma')
})

describe('P4-F Restaurant Lists Sync and public API', () => {
  it('creates offline-style List + Apple Maps-only item, pulls incrementally and is idempotent', async () => {
    const listAck = await pushOne('tm_list_a', mutation('create-list', 'restaurantList', 'list-a', 0,
      listPayload('list-a', 'forged-user', '杭州日料 Top 10', 'private')))
    const itemMutation = mutation('create-item', 'restaurantListItem', 'item-a', 0,
      itemPayload('item-a', 'list-a', 'apple_maps:apple-only-1', 0))
    const first = await pushOne('tm_list_a', itemMutation)
    const retry = await pushOne('tm_list_a', itemMutation)

    expect(listAck).toMatchObject({ status: 'applied', serverVersion: 1 })
    expect(first).toMatchObject({ status: 'applied', duplicate: false })
    expect(retry).toMatchObject({ status: 'applied', duplicate: true, serverVersion: first.serverVersion })
    expect(database.get("SELECT user_id FROM restaurant_lists WHERE id = 'list-a'").user_id).toBe('tm_list_a')
    expect(database.get("SELECT user_id FROM restaurant_list_items WHERE id = 'item-a'").user_id).toBe('tm_list_a')

    const fresh = await pull('tm_list_a', 0)
    expect(fresh.restaurantLists.map((value) => value.record.id)).toContain('list-a')
    expect(fresh.restaurantListItems[0].record).toMatchObject({
      listId: 'list-a', restaurantGlobalKey: 'apple_maps:apple-only-1',
      restaurant: { name: 'Apple-only 餐厅', markerPhotoId: null },
    })
    const rename = await pushOne('tm_list_a', mutation('rename-list', 'restaurantList', 'list-a', 1,
      listPayload('list-a', 'tm_list_b', '杭州日料 Top 12', 'private')))
    const incremental = await pull('tm_list_a', fresh.nextCursor)
    expect(rename.status).toBe('applied')
    expect(incremental.restaurantLists).toHaveLength(1)
    expect(incremental.restaurantLists[0].record.title).toBe('杭州日料 Top 12')
    expect(incremental.restaurantListItems).toEqual([])
  })

  it('prevents duplicate global Restaurant in one list but allows it in another list', async () => {
    await createListAndItem('tm_list_a', 'list-one', 'item-one', 'apple_maps:same-place')
    await pushOne('tm_list_a', mutation('create-list-two', 'restaurantList', 'list-two', 0,
      listPayload('list-two', 'tm_list_a', '第二份榜单', 'private')))

    const duplicate = await pushOne('tm_list_a', mutation('duplicate-place', 'restaurantListItem', 'item-duplicate', 0,
      itemPayload('item-duplicate', 'list-one', 'apple_maps:same-place', 1)))
    const otherList = await pushOne('tm_list_a', mutation('same-place-other-list', 'restaurantListItem', 'item-two', 0,
      itemPayload('item-two', 'list-two', 'apple_maps:same-place', 0)))

    expect(duplicate.status).toBe('conflict')
    expect(duplicate.conflictReason).toContain('duplicate_restaurant')
    expect(otherList.status).toBe('applied')
    expect(database.get(`SELECT COUNT(*) AS value FROM restaurant_list_items
      WHERE restaurant_global_key = 'apple_maps:same-place' AND deleted_at IS NULL`).value).toBe(2)
  })

  it('keeps metadata and item versions independent, preserves deterministic order and rejects stale conflicts', async () => {
    await pushOne('tm_list_a', mutation('list-ranked', 'restaurantList', 'ranked-list', 0,
      { ...listPayload('ranked-list', 'tm_list_a', '我的火锅排名', 'private'), isRanked: true }))
    for (let index = 0; index < 3; index += 1) {
      await pushOne('tm_list_a', mutation(`item-${index}`, 'restaurantListItem', `rank-item-${index}`, 0,
        itemPayload(`rank-item-${index}`, 'ranked-list', `apple_maps:rank-${index}`, index)))
    }
    const rename = await pushOne('tm_list_a', mutation('rename-ranked', 'restaurantList', 'ranked-list', 1,
      { ...listPayload('ranked-list', 'tm_list_a', '新的火锅排名', 'private'), isRanked: true }))
    const reorder = await pushOne('tm_list_a', mutation('reorder-item-2', 'restaurantListItem', 'rank-item-2', 1,
      itemPayload('rank-item-2', 'ranked-list', 'apple_maps:rank-2', 0)))
    const stale = await pushOne('tm_list_a', mutation('stale-item-2', 'restaurantListItem', 'rank-item-2', 1,
      itemPayload('rank-item-2', 'ranked-list', 'apple_maps:rank-2', 2)))

    expect(rename.status).toBe('applied')
    expect(reorder.status).toBe('applied')
    expect(stale).toMatchObject({ status: 'conflict', conflictReason: 'server_version_mismatch' })
    expect(database.get("SELECT title FROM restaurant_lists WHERE id = 'ranked-list'").title).toBe('新的火锅排名')
    expect(database.get("SELECT position FROM restaurant_list_items WHERE id = 'rank-item-2'").position).toBe(0)
  })

  it('enforces owner isolation, ignores forged userId and blocks direct non-owner item edits', async () => {
    await createListAndItem('tm_list_a', 'owned-list', 'owned-item', 'apple_maps:owned')
    await expect(pushOne('tm_list_b', mutation('takeover-list', 'restaurantList', 'owned-list', 1,
      listPayload('owned-list', 'tm_list_b', '偷改榜单', 'public'))))
      .rejects.toMatchObject({ status: 403 })
    await expect(pushOne('tm_list_b', mutation('takeover-item', 'restaurantListItem', 'owned-item', 1,
      itemPayload('owned-item', 'owned-list', 'apple_maps:owned', 9))))
      .rejects.toMatchObject({ status: 403 })
    expect(database.get("SELECT user_id FROM restaurant_lists WHERE id = 'owned-list'").user_id).toBe('tm_list_a')
    expect(database.get("SELECT title FROM restaurant_lists WHERE id = 'owned-list'").title).not.toBe('偷改榜单')
  })

  it('serves public/friends/private lists by server permission and revokes access after visibility change', async () => {
    await createListAndItem('tm_list_a', 'public-list', 'public-item', 'apple_maps:public', 'public')
    await createListAndItem('tm_list_a', 'friends-list', 'friends-item', 'apple_maps:friends', 'friends')
    await createListAndItem('tm_list_a', 'private-list', 'private-item', 'apple_maps:private', 'private')

    let page = await publicRequest('tm_list_b', '/api/v1/lists/users/tm_list_a?limit=20')
    expect(page.items.map((value) => value.id)).toEqual(['public-list'])
    await expect(publicRequest('tm_list_b', '/api/v1/lists/private-list'))
      .rejects.toBeInstanceOf(RestaurantListsV1RequestError)
    await expect(publicRequest('tm_list_b', '/api/v1/lists/friends-list'))
      .rejects.toMatchObject({ status: 404 })

    await database.prepare(`INSERT INTO friendships (
      id, requester_id, addressee_id, status, created_at, updated_at,
      pair_user_a, pair_user_b, deleted_at, server_version
    ) VALUES ('friend-a-b', 'tm_list_a', 'tm_list_b', 'accepted', ?, ?,
      'tm_list_a', 'tm_list_b', NULL, 1)`).bind(at, at).run()
    page = await publicRequest('tm_list_b', '/api/v1/lists/users/tm_list_a?limit=20')
    expect(new Set(page.items.map((value) => value.id))).toEqual(new Set(['public-list', 'friends-list']))
    expect((await publicRequest('tm_list_b', '/api/v1/lists/friends-list')).items[0].note).toBe('公开榜单备注')

    await pushOne('tm_list_a', mutation('public-to-private', 'restaurantList', 'public-list', 1,
      listPayload('public-list', 'forged', 'public-list', 'private')))
    await expect(publicRequest('tm_list_b', '/api/v1/lists/public-list'))
      .rejects.toMatchObject({ status: 404 })
  })

  it('returns allowlisted ordered public DTOs with pagination and no private Visit/user state', async () => {
    await pushOne('tm_list_a', mutation('paged-list', 'restaurantList', 'paged-list', 0,
      { ...listPayload('paged-list', 'tm_list_a', '50 家榜单', 'public'), isRanked: true }))
    for (let index = 0; index < 7; index += 1) {
      await pushOne('tm_list_a', mutation(`paged-${index}`, 'restaurantListItem', `paged-${index}`, 0,
        itemPayload(`paged-${index}`, 'paged-list', `apple_maps:paged-${index}`, index)))
    }
    const first = await publicRequest('tm_list_b', '/api/v1/lists/paged-list?limit=3')
    const second = await publicRequest('tm_list_b', `/api/v1/lists/paged-list?limit=3&cursor=${encodeURIComponent(first.nextCursor)}`)
    const serialized = JSON.stringify(first)

    expect(first.items.map((value) => value.position)).toEqual([0, 1, 2])
    expect(second.items.map((value) => value.position)).toEqual([3, 4, 5])
    expect(first.nextCursor).toBeTruthy()
    expect(second.nextCursor).toBeTruthy()
    for (const forbidden of ['myActualSpend', 'longTermNote', 'authSubject', 'storageKey', 'remoteRecordData', 'Visit']) {
      expect(serialized).not.toContain(forbidden)
    }
    expect(first.list.previewRestaurants).toHaveLength(4)
    expect(first.list.restaurantCount).toBe(7)
  })

  it('soft-deletes list/items, emits tombstones, and prevents stale clients from reviving them', async () => {
    await createListAndItem('tm_list_a', 'delete-list', 'delete-item', 'apple_maps:deleted')
    const before = await pull('tm_list_a', 0)
    const deletion = await pushOne('tm_list_a', {
      mutationId: 'delete-list-mutation', entityType: 'restaurantList', entityId: 'delete-list',
      operation: 'delete', baseVersion: 1, clientTimestamp: at,
    })
    expect(deletion.status).toBe('applied')
    expect(database.get("SELECT deleted_at FROM restaurant_list_items WHERE id = 'delete-item'").deleted_at).not.toBeNull()
    const delta = await pull('tm_list_a', before.nextCursor)
    expect(delta.tombstones).toEqual(expect.arrayContaining([
      expect.objectContaining({ entityType: 'restaurantList', entityId: 'delete-list' }),
      expect.objectContaining({ entityType: 'restaurantListItem', entityId: 'delete-item' }),
    ]))
    await expect(pushOne('tm_list_a', mutation('stale-revive', 'restaurantListItem', 'delete-item', 1,
      itemPayload('delete-item', 'delete-list', 'apple_maps:deleted', 0))))
      .rejects.toMatchObject({ status: 403 })
    await expect(publicRequest('tm_list_a', '/api/v1/lists/delete-list')).rejects.toMatchObject({ status: 404 })
  })

  it('loads 100 list summaries without fetching 5,000 full item payloads', async () => {
    const sql = []
    for (let listIndex = 0; listIndex < 100; listIndex += 1) {
      sql.push(`('perf-list-${listIndex}', 'tm_list_a', 'List ${listIndex}', '', 'public', 0,
        'automatic', NULL, '${at}', '${at}', NULL, 1, 'perf-list-${listIndex}', 50)`)
    }
    await database.prepare(`INSERT INTO restaurant_lists (
      id, user_id, title, description, visibility, is_ranked, cover_mode,
      custom_cover_photo_id, created_at, updated_at, deleted_at,
      server_version, last_mutation_id, active_item_count
    ) VALUES ${sql.join(',')}`).run()
    database.resetStatementCount()
    const page = await publicRequest('tm_list_b', '/api/v1/lists/users/tm_list_a?limit=50')
    expect(page.items).toHaveLength(50)
    expect(page.nextCursor).toBeTruthy()
    expect(database.statementCount).toBeLessThan(10)
    expect(page.items.every((value) => value.previewRestaurants.length === 0)).toBe(true)
  })
})

async function createListAndItem(userID, listID, itemID, globalKey, visibility = 'private') {
  await pushOne(userID, mutation(`create-${listID}`, 'restaurantList', listID, 0,
    listPayload(listID, userID, listID, visibility)))
  return pushOne(userID, mutation(`create-${itemID}`, 'restaurantListItem', itemID, 0,
    itemPayload(itemID, listID, globalKey, 0)))
}

function listPayload(id, userId, title, visibility) {
  return {
    schemaVersion: 1, id, userId, title, description: `${title} 的说明`, visibility,
    isRanked: false, coverMode: 'automatic', customCoverPhotoId: null,
    createdAt: at, updatedAt: at, deletedAt: null,
  }
}

function itemPayload(id, listId, globalKey, position) {
  const [provider, ...external] = globalKey.split(':')
  const externalId = external.join(':')
  const restaurantId = `place-ref:${globalKey}`
  return {
    schemaVersion: 1, id, userId: 'forged-user', listId, restaurantId,
    restaurantGlobalKey: globalKey, position, note: '公开榜单备注',
    restaurant: {
      globalKey, restaurantId,
      placeIdentities: [{ provider, externalId, isPrimary: true }],
      name: globalKey.includes('apple-only') ? 'Apple-only 餐厅' : `餐厅 ${externalId}`,
      address: 'Development Test Address', city: '杭州', latitude: 30.25, longitude: 120.16,
      markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍽️',
    },
    createdAt: at, updatedAt: at, deletedAt: null,
  }
}

function mutation(mutationId, entityType, entityId, baseVersion, payload) {
  return { mutationId, entityType, entityId, operation: 'upsert', baseVersion, clientTimestamp: at, payload }
}

async function pushOne(userID, value) {
  const response = await handleSyncV1Push(database, userID, new Request('https://development.test/api/v1/sync/push', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations: [value] }),
  }))
  return response.acknowledgements[0]
}

function pull(userID, cursor) {
  return handleSyncV1Pull(database, userID, new Request(
    `https://development.test/api/v1/sync/pull?schemaVersion=1&cursor=${cursor}&limit=200`,
  ))
}

function publicRequest(viewerID, path) {
  return handleRestaurantListsV1(new Request(`https://development.test${path}`), database, viewerID)
}

async function seedUser(db, id, name) {
  await db.prepare(`INSERT INTO users (id, nickname, created_at, updated_at, is_test_user)
    VALUES (?, ?, ?, ?, 1)`).bind(id, name, at, at).run()
  await ensureUserProfile(db, id)
  await db.prepare(`UPDATE user_profiles SET display_name = ?, visibility = 'public' WHERE user_id = ?`)
    .bind(name, id).run()
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
    return { success: true, results: [], meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } }
  }
}
