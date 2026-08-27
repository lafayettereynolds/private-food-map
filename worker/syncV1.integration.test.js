import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import appleFixture from '../contracts/fixtures/restaurant.v1.valid.json'
import legacyFixture from '../contracts/fixtures/restaurant.v0.legacy.json'
import worker from './index'
import {
  handleSyncV1Pull,
  handleSyncV1Push,
  recordUnversionedSyncChanges,
  SyncV1RequestError,
} from './syncV1'

describe('Worker Sync API V1 integration', () => {
  it('allows explicit test identities only in a configured Development deployment', async () => {
    const database = makeDatabase()
    const developmentResponse = await worker.fetch(new Request(
      'https://development.example.test/api/v1/sync/pull?schemaVersion=1&cursor=0',
      { headers: { 'X-Taste-Map-Test-User': 'ios-development-user' } },
    ), {
      DB: database,
      ASSETS: { fetch: () => new Response('not used') },
      APP_ENVIRONMENT: 'development',
      SYNC_AUTH_MODE: 'development-test',
    })
    expect(developmentResponse.status).toBe(200)

    const missingIdentity = await worker.fetch(new Request(
      'https://development.example.test/api/v1/sync/pull?schemaVersion=1&cursor=0',
    ), {
      DB: database,
      ASSETS: { fetch: () => new Response('not used') },
      APP_ENVIRONMENT: 'development',
      SYNC_AUTH_MODE: 'development-test',
    })
    expect(missingIdentity.status).toBe(401)

    const productionMisconfiguration = await worker.fetch(new Request(
      'https://api.example.test/api/v1/sync/pull?schemaVersion=1&cursor=0',
      { headers: { 'X-Taste-Map-Test-User': 'forged-production-user' } },
    ), {
      DB: database,
      ASSETS: { fetch: () => new Response('not used') },
      APP_ENVIRONMENT: 'production',
      SYNC_AUTH_MODE: 'development-test',
    })
    expect(productionMisconfiguration.status).toBe(503)
  })

  it('does not fall back to owner when production sync auth is unconfigured', async () => {
    const response = await worker.fetch(new Request(
      'https://api.example.test/api/v1/sync/pull?schemaVersion=1&cursor=0',
    ), {
      DB: makeDatabase(),
      ASSETS: { fetch: () => new Response('not used') },
    })
    expect(response.status).toBe(503)
    await expect(response.json()).resolves.toMatchObject({ error: expect.stringContaining('not configured') })
  })

  it('keeps the legacy Web /api/sync payload operational', async () => {
    const database = makeDatabase()
    const response = await worker.fetch(new Request('http://localhost/api/sync', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ restaurants: [legacyFixture], visits: [] }),
    }), {
      DB: database,
      ASSETS: { fetch: () => new Response('not used') },
    })
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.restaurants[0]).toMatchObject({
      id: legacyFixture.id,
      amapPoiId: legacyFixture.amapPoiId,
      placeIdentities: [expect.objectContaining({ provider: 'amap', externalId: legacyFixture.amapPoiId })],
    })
    expect(database.get('SELECT server_version FROM restaurants WHERE id = ?', legacyFixture.id).server_version).toBe(1)
  })

  it('syncs an Apple Maps-only Restaurant and related Visit incrementally', async () => {
    const database = makeDatabase()
    const restaurantMutation = mutation('create-restaurant', 'restaurant', appleFixture.id, 0, appleFixture)
    const restaurantResponse = await push(database, 'user-a', restaurantMutation)
    expect(restaurantResponse.acknowledgements[0]).toMatchObject({ status: 'applied', duplicate: false, serverVersion: 1 })

    const visit = visitPayload('visit-1', appleFixture.id, 'user-b')
    await push(database, 'user-a', mutation('create-visit', 'visit', visit.id, 0, visit))

    const firstPull = await pull(database, 'user-a', '0')
    expect(firstPull.restaurants).toHaveLength(1)
    expect(firstPull.restaurants[0].record).not.toHaveProperty('amapPoiId')
    expect(firstPull.restaurants[0].record.placeIdentities[0].provider).toBe('apple_maps')
    expect(firstPull.visits[0].record.restaurantId).toBe(appleFixture.id)
    expect(database.get("SELECT amap_poi_id FROM restaurants WHERE id = ?", appleFixture.id).amap_poi_id).toBe('')

    const secondVisit = visitPayload('visit-2', appleFixture.id, 'user-a')
    await push(database, 'user-a', mutation('create-visit-2', 'visit', secondVisit.id, 0, secondVisit))
    const incremental = await pull(database, 'user-a', firstPull.nextCursor)
    expect(incremental.restaurants.map((item) => item.record.id)).toEqual([appleFixture.id])
    expect(incremental.visits.map((item) => item.record.id)).toEqual(['visit-2'])
  })

  it('round-trips nullable party size, dining mode, and the original visit instant', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('core-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = {
      ...visitPayload('core-v', appleFixture.id, 'forged-user'),
      diningMode: 'takeout', partySize: null, rating: 4.5, myActualSpend: 36.5,
    }
    await push(database, 'user-a', mutation('core-v-create', 'visit', visit.id, 0, visit))

    const first = await pull(database, 'user-a', '0')
    expect(first.visits[0].record).toMatchObject({
      diningMode: 'takeout', partySize: null, visitedAt: visit.visitedAt,
      rating: 4.5, myActualSpend: 36.5,
    })
    expect(database.get('SELECT dining_mode, party_size, party_size_optional FROM visits WHERE id = ?', visit.id))
      .toMatchObject({ dining_mode: 'takeout', party_size: 0, party_size_optional: null })

    const updated = { ...visit, diningMode: 'dine_in', partySize: 3, updatedAt: '2026-08-27T07:30:00.000Z' }
    await push(database, 'user-a', mutation('core-v-update', 'visit', visit.id, 1, updated))
    const second = await pull(database, 'user-a', first.nextCursor)
    expect(second.visits[0]).toMatchObject({
      serverVersion: 2,
      record: { diningMode: 'dine_in', partySize: 3, visitedAt: visit.visitedAt },
    })
  })

  it('keeps a P0 Visit payload compatible with explicit native defaults', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('legacy-v-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const legacy = legacyVisitPayload('legacy-v', appleFixture.id, 'legacy-owner')
    await push(database, 'user-a', mutation('legacy-v-create', 'visit', legacy.id, 0, legacy))

    expect((await pull(database, 'user-a', '0')).visits[0].record)
      .toMatchObject({ diningMode: 'dine_in', partySize: null })
  })

  it('uses mutation receipts when the first response is lost', async () => {
    const database = makeDatabase()
    const request = mutation('response-lost', 'restaurant', appleFixture.id, 0, appleFixture)
    await push(database, 'user-a', request) // Simulate a committed response the client never received.
    const retry = await push(database, 'user-a', request)

    expect(retry.acknowledgements[0]).toMatchObject({ status: 'applied', duplicate: true, serverVersion: 1 })
    expect(database.get('SELECT COUNT(*) AS count FROM restaurants').count).toBe(1)
    expect(database.get("SELECT COUNT(*) AS count FROM sync_change_log_v2 WHERE mutation_id = 'response-lost'").count).toBe(1)
  })

  it('increments server versions for valid Restaurant and Visit updates', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('create-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const updatedRestaurant = { ...appleFixture, name: '更新后的餐厅', updatedAt: '2026-08-27T07:00:00.000Z' }
    const restaurantResponse = await push(database, 'user-a', mutation('update-r', 'restaurant', appleFixture.id, 1, updatedRestaurant))
    const visit = visitPayload('visit-update', appleFixture.id, 'user-a')
    await push(database, 'user-a', mutation('create-v', 'visit', visit.id, 0, visit))
    const updatedVisit = { ...visit, rating: 4.5, note: '更新后的记录', updatedAt: '2026-08-27T07:30:00.000Z' }
    const visitResponse = await push(database, 'user-a', mutation('update-v', 'visit', visit.id, 1, updatedVisit))

    expect(restaurantResponse.acknowledgements[0].serverVersion).toBe(2)
    expect(visitResponse.acknowledgements[0].serverVersion).toBe(2)
    expect(database.get('SELECT name, server_version FROM restaurants WHERE id = ?', appleFixture.id))
      .toMatchObject({ name: '更新后的餐厅', server_version: 2 })
    expect(database.get('SELECT rating, note, server_version FROM visits WHERE id = ?', visit.id))
      .toMatchObject({ rating: 4.5, note: '更新后的记录', server_version: 2 })
  })

  it('publishes a real legacy Web update once without fabricating repeated revisions', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('create-for-web', 'restaurant', appleFixture.id, 0, appleFixture))
    const initial = await pull(database, 'user-a', '0')
    const changedAt = '2026-08-27T09:00:00.000Z'
    await database.prepare('UPDATE restaurants SET name = ?, updated_at = ? WHERE id = ?')
      .bind('Web 更新名称', changedAt, appleFixture.id).run()
    const change = {
      userId: 'user-a', entityType: 'restaurant', entityId: appleFixture.id,
      updatedAt: changedAt, deletedAt: null,
    }
    await recordUnversionedSyncChanges(database, [change])
    await recordUnversionedSyncChanges(database, [change])
    const incremental = await pull(database, 'user-a', initial.nextCursor)

    expect(incremental.restaurants[0]).toMatchObject({ serverVersion: 2, record: { name: 'Web 更新名称' } })
    expect(database.get("SELECT COUNT(*) AS count FROM sync_change_log_v2 WHERE mutation_id LIKE 'legacy:v0:%'").count).toBe(1)
  })

  it('prevents a stale device from resurrecting a server tombstone', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('create', 'restaurant', appleFixture.id, 0, appleFixture))
    await push(database, 'user-a', deletion('delete', 'restaurant', appleFixture.id, 1))
    const stale = { ...appleFixture, name: '旧设备改名', updatedAt: '2026-08-27T08:00:00.000Z' }
    const response = await push(database, 'user-a', mutation('stale-update', 'restaurant', appleFixture.id, 1, stale))
    const changes = await pull(database, 'user-a', '0')

    expect(response.acknowledgements[0]).toMatchObject({ status: 'conflict', conflictReason: 'server_version_mismatch' })
    expect(database.get('SELECT deleted_at FROM restaurants WHERE id = ?', appleFixture.id).deleted_at).not.toBeNull()
    expect(changes.tombstones).toEqual([expect.objectContaining({ entityId: appleFixture.id, serverVersion: 2 })])
  })

  it('hydrates a tombstoned parent Restaurant required by an active Visit', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('parent-create', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('child-visit', appleFixture.id, 'user-a')
    await push(database, 'user-a', mutation('child-create', 'visit', visit.id, 0, visit))
    await push(database, 'user-a', deletion('parent-delete', 'restaurant', appleFixture.id, 1))
    const snapshot = await pull(database, 'user-a', '0')

    expect(snapshot.restaurants).toEqual([
      expect.objectContaining({ record: expect.objectContaining({ id: appleFixture.id, deletedAt: expect.any(String) }) }),
    ])
    expect(snapshot.visits[0].record.restaurantId).toBe(appleFixture.id)
    expect(snapshot.tombstones).toEqual([expect.objectContaining({ entityId: appleFixture.id })])
  })

  it('isolates reads and overrides a forged payload userId', async () => {
    const database = makeDatabase()
    const forged = { ...appleFixture, userId: 'user-b' }
    await push(database, 'user-a', mutation('forged-owner', 'restaurant', appleFixture.id, 0, forged))

    expect(database.get('SELECT user_id FROM restaurants WHERE id = ?', appleFixture.id).user_id).toBe('user-a')
    expect((await pull(database, 'user-b', '0')).restaurants).toEqual([])
    await expect(push(database, 'user-b', mutation('takeover', 'restaurant', appleFixture.id, 1, forged)))
      .rejects.toMatchObject({ status: 403 })
  })

  it('rejects reuse of a mutation ID with different content', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('same-id', 'restaurant', appleFixture.id, 0, appleFixture))
    const changed = { ...appleFixture, name: '不同内容' }
    await expect(push(database, 'user-a', mutation('same-id', 'restaurant', appleFixture.id, 0, changed)))
      .rejects.toBeInstanceOf(SyncV1RequestError)
  })

  it('syncs Dish and provider-neutral Photo metadata with idempotency, isolation, and tombstones', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('p2-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('p2-visit', appleFixture.id, 'forged-user')
    await push(database, 'user-a', mutation('p2-v', 'visit', visit.id, 0, visit))
    const dish = dishPayload('p2-dish', appleFixture.id, visit.id, 'forged-user')
    const dishCreate = mutation('p2-dish-create', 'dish', dish.id, 0, dish)
    await push(database, 'user-a', dishCreate)
    const duplicate = await push(database, 'user-a', dishCreate)
    expect(duplicate.acknowledgements[0]).toMatchObject({ duplicate: true, serverVersion: 1 })

    const photo = photoPayload('p2-photo', appleFixture.id, visit.id, dish.id, 'forged-user')
    await push(database, 'user-a', mutation('p2-photo-create', 'photo', photo.id, 0, photo))
    const first = await pull(database, 'user-a', '0')
    expect(first.dishes).toEqual([expect.objectContaining({ record: expect.objectContaining({ id: dish.id, visitId: visit.id }) })])
    expect(first.photos).toEqual([expect.objectContaining({ record: expect.objectContaining({
      id: photo.id, storageProvider: 'r2', storageKey: 'development/user-a/p2-photo',
    }) })])
    expect(database.get('SELECT user_id FROM dishes WHERE id = ?', dish.id).user_id).toBe('user-a')
    expect(database.get('SELECT user_id FROM photos WHERE id = ?', photo.id).user_id).toBe('user-a')
    expect(JSON.parse(database.get('SELECT dishes_json FROM visits WHERE id = ?', visit.id).dishes_json)[0])
      .toMatchObject({ id: dish.id, photoId: photo.id })
    expect((await pull(database, 'user-b', '0')).dishes).toEqual([])
    expect((await pull(database, 'user-b', '0')).photos).toEqual([])
    await expect(push(database, 'user-b', mutation('p2-dish-takeover', 'dish', dish.id, 1, dish)))
      .rejects.toMatchObject({ status: 403 })

    const updated = { ...dish, taste: '更浓郁', updatedAt: '2026-08-27T09:00:00.000Z' }
    await push(database, 'user-a', mutation('p2-dish-update', 'dish', dish.id, 1, updated))
    const stale = await push(database, 'user-a', mutation('p2-dish-stale', 'dish', dish.id, 1, dish))
    expect(stale.acknowledgements[0]).toMatchObject({ status: 'conflict', serverVersion: 2 })

    await push(database, 'user-a', deletion('p2-photo-delete', 'photo', photo.id, 1))
    await push(database, 'user-a', deletion('p2-dish-delete', 'dish', dish.id, 2))
    const deleted = await pull(database, 'user-a', first.nextCursor)
    expect(deleted.tombstones).toEqual(expect.arrayContaining([
      expect.objectContaining({ entityType: 'photo', entityId: photo.id }),
      expect.objectContaining({ entityType: 'dish', entityId: dish.id }),
    ]))
    expect(JSON.parse(database.get('SELECT dishes_json FROM visits WHERE id = ?', visit.id).dishes_json)).toEqual([])
    expect((await push(database, 'user-a', mutation('p2-dish-resurrect', 'dish', dish.id, 2, dish))).acknowledgements[0])
      .toMatchObject({ status: 'conflict' })
  })
})

function mutation(mutationId, entityType, entityId, baseVersion, payload) {
  return { mutationId, entityType, entityId, operation: 'upsert', baseVersion, clientTimestamp: payload.updatedAt, payload }
}

function deletion(mutationId, entityType, entityId, baseVersion) {
  return { mutationId, entityType, entityId, operation: 'delete', baseVersion, clientTimestamp: '2026-08-27T07:00:00.000Z' }
}

function visitPayload(id, restaurantId, claimedUser) {
  return {
    schemaVersion: 1, id, userId: claimedUser, restaurantId,
    visitedAt: '2026-08-27T06:00:00.000Z', diningMode: 'dine_in', partySize: null,
    rating: null, note: null, myActualSpend: null,
    createdAt: '2026-08-27T06:00:00.000Z', updatedAt: '2026-08-27T06:00:00.000Z', deletedAt: null,
  }
}

function legacyVisitPayload(id, restaurantId, claimedUser) {
  const { diningMode: _, partySize: __, ...legacy } = visitPayload(id, restaurantId, claimedUser)
  return legacy
}

function dishPayload(id, restaurantId, visitId, claimedUser) {
  return {
    schemaVersion: 1, id, userId: claimedUser, restaurantId, visitId,
    name: '寿喜烧', taste: '甜香', rating: 4.5, price: 88, photoId: null,
    sortOrder: 0, createdAt: '2026-08-27T06:10:00.000Z',
    updatedAt: '2026-08-27T06:10:00.000Z', deletedAt: null,
  }
}

function photoPayload(id, restaurantId, visitId, dishId, claimedUser) {
  return {
    schemaVersion: 1, id, userId: claimedUser, restaurantId, visitId, dishId,
    kind: 'dish', storageProvider: 'r2', storageKey: `development/user-a/${id}`,
    providerAccountId: null, thumbnailStorageKey: null, fileName: `${id}.heic`,
    mimeType: 'image/heic', byteSize: 1024, width: 1200, height: 900,
    sortOrder: 0, visibility: 'private', createdAt: '2026-08-27T06:20:00.000Z',
    updatedAt: '2026-08-27T06:20:00.000Z', deletedAt: null,
  }
}

async function push(database, viewerId, ...mutations) {
  const request = new Request('http://localhost/api/v1/sync/push', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations }),
  })
  return handleSyncV1Push(database, viewerId, request)
}

async function pull(database, viewerId, cursor) {
  return handleSyncV1Pull(database, viewerId, new Request(
    `http://localhost/api/v1/sync/pull?schemaVersion=1&cursor=${cursor}&limit=200`,
  ))
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  for (const migration of migrationFiles()) sqlite.exec(readFileSync(resolve('migrations', migration), 'utf8'))
  return new SQLiteD1Database(sqlite)
}

function migrationFiles() {
  return [
    '0001_initial.sql', '0002_add_google_drive_photos.sql', '0003_social_visit_fields.sql',
    '0004_user_avatar_thumbnail.sql', '0005_visit_tags_and_map_privacy.sql',
    '0006_avatar_presets_and_membership.sql', '0007_multi_dining_occasions.sql',
    '0008_dining_companion_links.sql', '0009_discovery_follows_and_test_markers.sql',
    '0010_membership_entitlements.sql', '0011_photo_storage_metadata.sql',
    '0012_recommendation_events.sql', '0013_restaurant_lists.sql',
    '0014_restaurant_contact_details.sql', '0015_restaurant_place_identities.sql',
    '0016_sync_v1.sql', '0017_native_auth.sql', '0018_visit_core_fields.sql',
    '0019_dish_photo_sync.sql',
  ]
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
