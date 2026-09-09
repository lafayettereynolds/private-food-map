import { DatabaseSync } from 'node:sqlite'
import { describe, expect, it } from 'vitest'
import appleFixture from '../contracts/fixtures/restaurant.v1.valid.json'
import legacyFixture from '../contracts/fixtures/restaurant.v0.legacy.json'
import worker from './index'
import {
  handleSyncV1Pull,
  handleSyncV1Push,
  handleSyncConflictSnapshot,
  recordUnversionedSyncChanges,
  SyncV1RequestError,
} from './syncV1'
import { ensureUserProfile, readPublicProfile } from './profileV1'
import { buildRestaurantSummaries } from '../src/services/restaurantSummaryProjection'
import { applyAllMigrations } from './testSupport/migrations.js'

describe('Worker Sync API V1 integration', () => {
  it('never-uploaded photo delete has an idempotent receipt and a cross-device tombstone', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'user-a')
    const remove = deletion('never-uploaded-delete', 'photo', 'never-uploaded-photo', 0)
    const first = await push(database, 'user-a', remove)
    expect(first.acknowledgements[0]).toMatchObject({ status: 'applied', serverVersion: 1 })
    expect((await push(database, 'user-a', remove)).acknowledgements[0].duplicate).toBe(true)
    const secondClient = await pull(database, 'user-a', '0')
    expect(secondClient.tombstones).toContainEqual(expect.objectContaining({ entityType: 'photo', entityId: 'never-uploaded-photo', serverVersion: 1 }))
    expect((await pull(database, 'user-b', '0')).tombstones).toEqual([])
    expect(database.get('SELECT COUNT(*) AS count FROM photos WHERE id = ?', 'never-uploaded-photo').count).toBe(0)
  })
  it('a deletion fence prevents first metadata creation after a never-synced binary delete', async () => {
    const database = makeDatabase()
    const owner = 'user-a'
    await ensureUser(database, owner)
    await push(database, owner, mutation('fence-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('fence-v', appleFixture.id, owner)
    await push(database, owner, mutation('fence-v', 'visit', visit.id, 0, visit))
    const photo = { ...photoPayload('fence-p', appleFixture.id, visit.id, null, owner), kind: 'visit' }
    await database.prepare('INSERT INTO photo_deletion_fences(user_id,photo_id,deleted_at) VALUES (?,?,?)')
      .bind(owner, photo.id, '2026-09-09').run()
    const result = await push(database, owner, mutation('fence-late-metadata', 'photo', photo.id, 0, photo))
    expect(result.acknowledgements[0].status).toBe('conflict')
    expect(database.get('SELECT COUNT(*) AS count FROM photos WHERE id = ?', photo.id).count).toBe(0)
  })
  it('photo delete reaches an offline second client and stale writes cannot resurrect it', async () => {
    const database = makeDatabase()
    const owner = 'user-a'
    await push(database, owner, mutation('delete-e2e-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('delete-e2e-v', appleFixture.id, owner)
    await push(database, owner, mutation('delete-e2e-v', 'visit', visit.id, 0, visit))
    const photo = { ...photoPayload('delete-e2e-p', appleFixture.id, visit.id, null, owner), kind: 'visit' }
    await push(database, owner, mutation('delete-e2e-p', 'photo', photo.id, 0, photo))
    const deviceB = await pull(database, owner, '0')
    expect(deviceB.photos.some(item => item.record.id === photo.id)).toBe(true)
    const remove = deletion('delete-e2e-remove', 'photo', photo.id, 1)
    expect((await push(database, owner, remove)).acknowledgements[0].status).toBe('applied')
    expect((await push(database, owner, remove)).acknowledgements[0].duplicate).toBe(true)
    const reconnect = await pull(database, owner, deviceB.nextCursor)
    expect(reconnect.tombstones).toContainEqual(expect.objectContaining({ entityType: 'photo', entityId: photo.id }))
    const stale = { ...photo, updatedAt: '2099-01-01T00:00:00.000Z' }
    for (const version of [1, 2]) {
      expect((await push(database, owner, mutation(`delete-e2e-stale-${version}`, 'photo', photo.id, version, stale))).acknowledgements[0].status).toBe('conflict')
    }
    expect((await pull(database, owner, '0')).photos.some(item => item.record.id === photo.id)).toBe(false)
    expect(database.get('SELECT deleted_at FROM photos WHERE id = ?', photo.id).deleted_at).toBeTruthy()
    expect(database.get('SELECT deleted_at FROM visits WHERE id = ?', visit.id).deleted_at).toBeNull()
    expect(JSON.parse(database.get('SELECT photo_ids_json FROM visits WHERE id = ?', visit.id).photo_ids_json)).not.toContain(photo.id)
    await expect(push(database, 'user-b', deletion('delete-e2e-foreign', 'photo', photo.id, 2))).rejects.toMatchObject({ status: 403 })
  })
  it.each(['active', 'foreign', 'visit-deleted', 'dish-deleted', 'restaurant-deleted', 'wrong-parent-owner'])(
    'legacy canonical snapshot enforces parents and does not write: %s', async scenario => {
      const database = makeDatabase()
      await push(database, 'user-a', mutation('canonical-r', 'restaurant', appleFixture.id, 0, appleFixture))
      const visit = visitPayload('canonical-v', appleFixture.id, 'user-a')
      await push(database, 'user-a', mutation('canonical-v', 'visit', visit.id, 0, visit))
      const dish = dishPayload('canonical-d', appleFixture.id, visit.id, 'user-a')
      await push(database, 'user-a', mutation('canonical-d', 'dish', dish.id, 0, dish))
      const canonical = `legacy:${dish.id}:${visit.id}`
      if (scenario.endsWith('-deleted')) {
        const table = { 'visit-deleted': 'visits', 'dish-deleted': 'dishes', 'restaurant-deleted': 'restaurants' }[scenario]
        database.sqlite.prepare(`UPDATE ${table} SET deleted_at='2026-09-09T00:00:00Z'`).run()
      }
      if (scenario === 'wrong-parent-owner') {
        await ensureUser(database, 'user-b')
        database.sqlite.prepare("UPDATE dishes SET user_id='user-b'").run()
      }
      const before = database.get('SELECT total_changes() n').n
      const request = new Request(`https://dev.test/api/v1/sync/conflict-snapshot?entityType=visitDish&entityId=${encodeURIComponent(canonical)}`)
      const action = () => handleSyncConflictSnapshot(database, scenario === 'foreign' ? 'user-b' : 'user-a', request)
      if (scenario === 'active') {
        const result = await action()
        expect(result).toMatchObject({ entityId: canonical, visitDish: { serverVersion: 1, record: { id: canonical, userId: 'user-a', visitId: visit.id, dishId: dish.id } },
          associationParents: { restaurantVersion: 1, visitVersion: 1, dishVersion: 1 } })
        expect(await action()).toEqual(result)
      } else await expect(action()).rejects.toMatchObject({ status: scenario === 'foreign' || scenario === 'wrong-parent-owner' ? 404 : 409 })
      expect(database.get('SELECT total_changes() n').n).toBe(before)
      expect(database.get('SELECT COUNT(*) n FROM visit_dishes').n).toBe(1)
    })

  it('authenticates the conflict-snapshot route and rejects missing or foreign identity', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('route-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('route-v', appleFixture.id, 'user-a')
    await push(database, 'user-a', mutation('route-v', 'visit', visit.id, 0, visit))
    const env = { DB: database, ASSETS: { fetch: () => new Response('not used') },
      APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test' }
    const url = `https://development.example.test/api/v1/sync/conflict-snapshot?entityType=visit&entityId=${visit.id}`
    expect((await worker.fetch(new Request(url), env)).status).toBe(401)
    expect((await worker.fetch(new Request(url, { headers: { 'X-Taste-Map-Test-User': 'user-b' } }), env)).status).toBe(404)
    const result = await worker.fetch(new Request(url, { headers: { 'X-Taste-Map-Test-User': 'user-a' } }), env)
    expect(result.status).toBe(200)
    expect(await result.json()).toMatchObject({ entityType: 'visit', entityId: visit.id, visit: { serverVersion: 1 } })
  })

  it('reads current owner-scoped conflict versions and values without writing a receipt or entity', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('snapshot-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('snapshot-v', appleFixture.id, 'user-a')
    await push(database, 'user-a', mutation('snapshot-v', 'visit', visit.id, 0, visit))
    database.sqlite.prepare(`UPDATE visits SET server_version=7,visibility='public',party_size_optional=2,
      price_per_person=71,my_actual_spend=141 WHERE id=?`).run(visit.id)
    const before = database.get('SELECT total_changes() n').n
    const request = new Request(`https://dev.test/api/v1/sync/conflict-snapshot?entityType=visit&entityId=${visit.id}`)
    expect(await handleSyncConflictSnapshot(database, 'user-a', request)).toMatchObject({
      visit: { serverVersion: 7, record: { userId: 'user-a', visibility: 'public', partySize: 2, pricePerPerson: 71, myActualSpend: 141 } },
      restaurantListItems: [],
    })
    await expect(handleSyncConflictSnapshot(database, 'user-b', request)).rejects.toMatchObject({ status: 404 })
    expect(database.get('SELECT total_changes() n').n).toBe(before)
    database.sqlite.prepare('UPDATE visits SET deleted_at=? WHERE id=?').run('2026-09-09T00:00:00Z',visit.id)
    await expect(handleSyncConflictSnapshot(database, 'user-a', request)).rejects.toMatchObject({ status: 409 })
  })

  it('returns authoritative list membership and ordering without changing the list or its items', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('list-snapshot-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const time = '2026-09-09T00:00:00Z'
    database.sqlite.prepare(`INSERT INTO restaurant_lists(id,user_id,title,description,visibility,is_ranked,created_at,updated_at,server_version)
      VALUES('snapshot-list','user-a','全球十佳','','public',0,?,?,5)`).run(time,time)
    database.sqlite.prepare(`INSERT INTO restaurant_list_items(id,list_id,user_id,restaurant_id,position,note,created_at,updated_at,server_version)
      VALUES('snapshot-item','snapshot-list','user-a',?,2,'',?,?,3)`).run(appleFixture.id,time,time)
    const before = database.get('SELECT total_changes() n').n
    const request = new Request('https://dev.test/api/v1/sync/conflict-snapshot?entityType=restaurantList&entityId=snapshot-list')
    const result = await handleSyncConflictSnapshot(database, 'user-a', request)
    expect(result.restaurantList).toMatchObject({ serverVersion: 5, record: { id: 'snapshot-list',userId: 'user-a',title:'全球十佳',visibility:'public' } })
    expect(result.restaurantListItems).toHaveLength(1)
    expect(result.restaurantListItems[0]).toMatchObject({ serverVersion: 3,record:{id:'snapshot-item',listId:'snapshot-list',userId:'user-a',position:2} })
    expect(database.get('SELECT total_changes() n').n).toBe(before)
    await expect(handleSyncConflictSnapshot(database,'user-b',request)).rejects.toMatchObject({status:404})
  })
  it('preserves raw half-stars and personal 9.1 across push, pull and replay', async () => {
    const database=makeDatabase()
    const restaurant={...appleFixture,userId:'user-a',overallRating:null}
    await push(database,'user-a',mutation('precision-r','restaurant',restaurant.id,0,restaurant))
    const ratings=[4.5,4.5,4.5,4.5,4.5,4.5,4.5,4.5,5]
    const mutations=ratings.map((rating,i)=>{
      const v={...visitPayload(`precision-${i}`,restaurant.id,'user-a'),rating}
      return mutation(`precision-m${i}`,'visit',v.id,0,v)
    })
    await push(database,'user-a',...mutations)
    await push(database,'user-a',...mutations)
    for(let i=0;i<2;i++){
      const result=JSON.parse(JSON.stringify(await pull(database,'user-a','0')))
      expect(result.visits.map(v=>v.record.rating).sort()).toEqual([...ratings].sort())
      expect(buildRestaurantSummaries(result.restaurants.map(x=>x.record),result.visits.map(x=>x.record))[0].scoreOutOfTen).toBe(9.1)
    }
    expect((await pull(database,'user-b','0')).visits).toEqual([])
    expect(database.get('SELECT COUNT(*) AS n FROM visits').n).toBe(9)
  })

  it('rejects new free dish photos even below quota and preserves Premium-era photos', async () => {
    const database=makeDatabase();await ensureUser(database,'user-a')
    await push(database,'user-a',mutation('dish-gate-r','restaurant',appleFixture.id,0,appleFixture))
    const visit=visitPayload('dish-gate-v',appleFixture.id,'user-a')
    await push(database,'user-a',mutation('dish-gate-v','visit',visit.id,0,visit))
    const dish=dishPayload('dish-gate-d',appleFixture.id,visit.id,'user-a')
    await push(database,'user-a',mutation('dish-gate-d','dish',dish.id,0,dish))
    const photo=photoPayload('dish-gate-p',appleFixture.id,visit.id,dish.id,'user-a')
    await expect(pushWithAccess(database,'user-a',{isPremium:false,visitPhotoLimit:2},
      mutation('dish-gate-free','photo',photo.id,0,photo))).rejects.toMatchObject({status:403})
    const saved=await pushWithAccess(database,'user-a',{isPremium:true,visitPhotoLimit:20},
      mutation('dish-gate-paid','photo',photo.id,0,photo))
    expect(saved.acknowledgements[0].status).toBe('applied')
    expect(database.get('SELECT COUNT(*) AS count FROM photos WHERE id = ?',photo.id).count).toBe(1)
  })
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
    expect(developmentResponse.headers.get('Server-Timing')).toContain('hydrate;dur=')
    expect(await database.prepare("SELECT is_test_user FROM users WHERE id = 'ios-development-user'").first())
      .toMatchObject({ is_test_user: 1 })

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

  it('exposes the versioned external-place resolver only to an authenticated viewer and isolates private candidates', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('external-place-a', 'restaurant', appleFixture.id, 0, appleFixture))
    const input = {
      text: 'https://maps.apple.com/?q=%E5%90%88%E5%90%8C%E6%B5%8B%E8%AF%95%E9%A4%90%E5%8E%85&address=%E6%B5%8B%E8%AF%95%E8%B7%AF%201%20%E5%8F%B7&ll=30.2741,120.1551&place-id=apple-place-2B34C5D6',
      currentCity: '杭州',
    }
    const request = (user) => new Request('https://development.example.test/api/v1/external-place/resolve', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(user ? { 'X-Taste-Map-Test-User': user } : {}),
      },
      body: JSON.stringify(input),
    })
    const env = {
      DB: database,
      ASSETS: { fetch: () => new Response('not used') },
      APP_ENVIRONMENT: 'development',
      SYNC_AUTH_MODE: 'development-test',
    }

    const responseA = await worker.fetch(request('user-a'), env)
    expect(responseA.status).toBe(200)
    await expect(responseA.json()).resolves.toMatchObject({
      apiVersion: 1,
      sourceType: 'apple_maps',
      candidates: [expect.objectContaining({
        restaurantId: appleFixture.id,
        placeIdentities: [expect.objectContaining({
          provider: 'apple_maps', externalId: 'apple-place-2B34C5D6',
        })],
      })],
    })

    const responseB = await worker.fetch(request('user-b'), env)
    expect(responseB.status).toBe(200)
    expect((await responseB.json()).candidates).toEqual([])
    expect((await worker.fetch(request(''), env)).status).toBe(401)
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

  it('hydrates a real-sized pull page with bounded batched reads and stays incremental', async () => {
    const database = makeDatabase()
    const records = Array.from({ length: 200 }, (_, index) => {
      const id = `pull-sized-restaurant-${String(index).padStart(3, '0')}`
      return {
        ...appleFixture,
        id,
        userId: 'forged-owner',
        name: `Pull sized restaurant ${index}`,
        placeIdentities: appleFixture.placeIdentities.map((identity) => ({
          ...identity,
          externalId: `pull-sized-apple-${String(index).padStart(3, '0')}`,
        })),
      }
    })
    await push(database, 'pull-sized-user', ...records.slice(0, 100).map((record, index) =>
      mutation(`pull-sized-mutation-${index}`, 'restaurant', record.id, 0, record)))
    await push(database, 'pull-sized-user', ...records.slice(100).map((record, index) =>
      mutation(`pull-sized-mutation-${index + 100}`, 'restaurant', record.id, 0, record)))

    database.resetMetrics()
    const startedAt = performance.now()
    const first = await pull(database, 'pull-sized-user', '0')
    const duration = performance.now() - startedAt

    expect(first.restaurants).toHaveLength(200)
    expect(first.hasMore).toBe(true)
    expect(duration).toBeLessThan(2_000)
    expect(database.batchCalls).toBe(2)
    expect(database.queryExecutions).toBeLessThanOrEqual(10)

    database.resetMetrics()
    const incremental = await pull(database, 'pull-sized-user', first.nextCursor)
    expect(incremental.restaurants).toEqual([])
    expect(incremental.tombstones).toEqual([])
    expect(incremental.hasMore).toBe(false)
    expect(database.batchCalls).toBe(0)
    expect(database.queryExecutions).toBe(1)
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

  it('round-trips partial multidimensional ratings and preserves unrelated Visit columns', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('rating-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = {
      ...visitPayload('rating-v', appleFixture.id, 'forged-user'),
      rating: 4.5, valueRating: 5, environmentRating: null, serviceRating: 3.5,
      recommendationSourceType: 'other', recommendationSourceText: 'legacy-source',
    }
    await database.prepare(`INSERT INTO visits (
      id, user_id, restaurant_id, visited_at, rating, party_size, recommendation_source_text,
      companions_json, dishes_json, note, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(
        visit.id, 'user-a', visit.restaurantId, visit.visitedAt, null, 1, 'legacy-source',
        '[]', '[]', '', visit.createdAt, visit.updatedAt,
      ).run()
    await push(database, 'user-a', mutation('rating-update', 'visit', visit.id, 0, visit))

    const pulled = await pull(database, 'user-a', '0')
    expect(pulled.visits[0].record).toMatchObject({
      rating: 4.5, valueRating: 5, environmentRating: null, serviceRating: 3.5,
    })
    expect(database.get(`SELECT value_rating, environment_rating, service_rating, recommendation_source_text
      FROM visits WHERE id = ?`, visit.id)).toMatchObject({
      value_rating: 5, environment_rating: null, service_rating: 3.5, recommendation_source_text: 'legacy-source',
    })

    const cleared = { ...visit, valueRating: null, updatedAt: '2026-08-27T08:00:00.000Z' }
    await push(database, 'user-a', mutation('rating-clear', 'visit', visit.id, 1, cleared))
    expect((await pull(database, 'user-a', pulled.nextCursor)).visits[0].record)
      .toMatchObject({ valueRating: null, environmentRating: null, serviceRating: 3.5 })
  })

  it('round-trips P2-E dining context, clears nullable fields, and preserves P2-F legacy data', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('p2e-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = {
      ...visitPayload('p2e-v', appleFixture.id, 'forged-user'),
      visibility: 'friends', partySize: 3, totalPrice: 360, myActualSpend: 120,
      paymentMode: 'aa', pricePerPerson: 120, queueDuration: 'none',
      diningOccasions: ['friends', 'other'], diningOccasionText: '工作简餐',
      valueTags: ['合理'], environmentTags: ['舒适'], serviceTags: ['周到'],
      noiseLevel: 'normal', diningDuration: 'under30', portionLevel: 'generous',
      transportConvenience: 'very_convenient', specialNotes: '现场取号',
      rating: 4.5, valueRating: 4, environmentRating: 4.5, serviceRating: 5,
    }
    await push(database, 'user-a', mutation('p2e-create', 'visit', visit.id, 0, visit))
    await database.prepare(`UPDATE visits SET recommendation_source_text = ?, companions_json = ?,
      dishes_json = ?, photo_ids_json = ? WHERE id = ?`).bind(
      '保留到 P2-F', '["小王"]',
      '[{"id":"legacy-web-dish","name":"旧版菜品","taste":"保留原文"}]',
      '["legacy-web-photo"]', visit.id,
    ).run()

    const first = await pull(database, 'user-a', '0')
    expect(first.visits[0].record).toMatchObject({
      visibility: 'friends', totalPrice: 360, myActualSpend: 120, paymentMode: 'aa',
      pricePerPerson: 120, queueDuration: 'none', diningOccasions: ['friends', 'other'],
      diningOccasionText: '工作简餐', valueTags: ['合理'], environmentTags: ['舒适'],
      serviceTags: ['周到'], noiseLevel: 'normal', diningDuration: 'under30',
      portionLevel: 'generous', transportConvenience: 'very_convenient', specialNotes: '现场取号',
    })
    expect(database.get(`SELECT visibility, total_price, payment_mode, queue_duration,
      dining_occasion, dining_occasions_json, noise_level, special_notes
      FROM visits WHERE id = ?`, visit.id)).toMatchObject({
      visibility: 'friends', total_price: 360, payment_mode: 'aa', queue_duration: 'none',
      dining_occasion: 'friends', dining_occasions_json: '["friends","other"]',
      noise_level: 'normal', special_notes: '现场取号',
    })

    const cleared = {
      ...visit, visibility: 'private', totalPrice: null, paymentMode: null,
      pricePerPerson: null, queueDuration: null, diningOccasions: [], diningOccasionText: null,
      valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null,
      diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: null,
      companions: ['小王'], companionIds: [], recommendationSourceType: 'other',
      recommendationSourceText: '保留到 P2-F',
      updatedAt: '2026-08-27T09:00:00.000Z',
    }
    await push(database, 'user-a', mutation('p2e-clear', 'visit', visit.id, 1, cleared))
    const second = await pull(database, 'user-a', first.nextCursor)
    expect(second.visits[0].record).toMatchObject({
      visibility: 'private', totalPrice: null, paymentMode: null, queueDuration: null,
      diningOccasions: [], diningOccasionText: null, valueTags: [], specialNotes: null,
    })
    expect(database.get(`SELECT recommendation_source_text, companions_json, dishes_json, photo_ids_json
      FROM visits WHERE id = ?`, visit.id)).toMatchObject({
      recommendation_source_text: '保留到 P2-F',
      companions_json: '["小王"]',
      dishes_json: '[{"id":"legacy-web-dish","name":"旧版菜品","taste":"保留原文"}]',
      photo_ids_json: '["legacy-web-photo"]',
    })
    expect(database.get(`SELECT COUNT(*) AS count FROM visits
      WHERE id = ? AND visibility = 'public'`, visit.id).count).toBe(0)
    expect((await pull(database, 'user-b', '0')).visits).toEqual([])
  })

  it('keeps a P0 Visit payload compatible with explicit native defaults', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('legacy-v-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const legacy = legacyVisitPayload('legacy-v', appleFixture.id, 'legacy-owner')
    await push(database, 'user-a', mutation('legacy-v-create', 'visit', legacy.id, 0, legacy))

    expect((await pull(database, 'user-a', '0')).visits[0].record)
      .toMatchObject({
        diningMode: 'dine_in', visibility: 'private', partySize: null,
        totalPrice: null, paymentMode: null, queueDuration: null,
        diningOccasions: [], valueTags: [], environmentTags: [], serviceTags: [],
        valueRating: null, environmentRating: null, serviceRating: null,
      })
  })

  it('uses mutation receipts when the first response is lost', async () => {
    const database = makeDatabase()
    const request = mutation('response-lost', 'restaurant', appleFixture.id, 0, appleFixture)
    await push(database, 'user-a', request) // Simulate a committed response the client never received.
    const retry = await push(database, 'user-a', request)

    expect(retry.acknowledgements[0]).toMatchObject({ status: 'applied', duplicate: true, serverVersion: 1 })
    expect(database.get('SELECT COUNT(*) AS count FROM restaurants').count).toBe(1)
    expect(database.get("SELECT COUNT(*) AS count FROM sync_change_log_v6 WHERE mutation_id = 'response-lost'").count).toBe(1)
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
    expect(database.get("SELECT COUNT(*) AS count FROM sync_change_log_v6 WHERE mutation_id LIKE 'legacy:v0:%'").count).toBe(1)
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

  it('enforces the Free 2 / Premium 20 Visit-photo policy and custom-avatar entitlement on the server', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'user-a')
    await ensureUserProfile(database, 'user-a')
    await push(database, 'user-a', mutation('premium-policy-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('premium-policy-v', appleFixture.id, 'forged-user')
    await push(database, 'user-a', mutation('premium-policy-v', 'visit', visit.id, 0, visit))
    const freeAccess = { isPremium: false, visitPhotoLimit: 2 }
    const premiumAccess = { isPremium: true, visitPhotoLimit: 20 }

    for (let index = 0; index < 2; index += 1) {
      const photo = {
        ...photoPayload(`premium-policy-photo-${index}`, appleFixture.id, visit.id, null, 'forged-user'),
        kind: 'visit', sortOrder: index,
      }
      const result = await pushWithAccess(
        database, 'user-a', freeAccess,
        mutation(`premium-policy-photo-${index}`, 'photo', photo.id, 0, photo),
      )
      expect(result.acknowledgements[0].status).toBe('applied')
    }
    const third = {
      ...photoPayload('premium-policy-photo-2', appleFixture.id, visit.id, null, 'forged-user'),
      kind: 'visit', sortOrder: 2,
    }
    await expect(pushWithAccess(
      database, 'user-a', freeAccess,
      mutation('premium-policy-photo-2', 'photo', third.id, 0, third),
    )).rejects.toMatchObject({ status: 403 })
    expect(database.get('SELECT COUNT(*) AS count FROM photos WHERE visit_id = ?', visit.id).count).toBe(2)
    await expect(pushWithAccess(
      database, 'user-a', premiumAccess,
      mutation('premium-policy-photo-2-premium', 'photo', third.id, 0, third),
    )).resolves.toMatchObject({ acknowledgements: [expect.objectContaining({ status: 'applied' })] })

    // Downgraded members retain all historical photos and can edit metadata.
    await expect(pushWithAccess(database, 'user-a', freeAccess,
      mutation('retained-photo-metadata', 'photo', third.id, 1, { ...third, sortOrder: 0 }),
    )).resolves.toMatchObject({ acknowledgements: [expect.objectContaining({ status: 'applied' })] })
    await pushWithAccess(database, 'user-a', freeAccess,
      mutation('retained-visit-note', 'visit', visit.id, 1, { ...visit, note: 'Unrelated edit' }))
    expect(database.get('SELECT COUNT(*) AS count FROM photos WHERE visit_id = ? AND deleted_at IS NULL', visit.id).count).toBe(3)
    const otherVisit = visitPayload('quota-other-visit', appleFixture.id, 'forged-user')
    await push(database, 'user-a', mutation('quota-other-visit', 'visit', otherVisit.id, 0, otherVisit))
    const moving = { ...photoPayload('quota-moving', appleFixture.id, otherVisit.id, null, 'forged-user'), kind: 'visit' }
    await pushWithAccess(database, 'user-a', freeAccess, mutation('quota-moving', 'photo', moving.id, 0, moving))
    await expect(pushWithAccess(database, 'user-a', freeAccess,
      mutation('quota-moving-rebind', 'photo', moving.id, 1, { ...moving, visitId: visit.id }),
    )).rejects.toMatchObject({ status: 403 })
    expect(database.get('SELECT visit_id FROM photos WHERE id = ?', moving.id).visit_id).toBe(otherVisit.id)

    const avatar = {
      ...photoPayload('premium-policy-avatar', null, null, null, 'forged-user'),
      kind: 'avatar', storageKey: 'development/user-a/premium-policy-avatar',
    }
    await pushWithAccess(
      database, 'user-a', freeAccess,
      mutation('premium-policy-avatar', 'photo', avatar.id, 0, avatar),
    )
    const initial = await pull(database, 'user-a', '0')
    const profile = { ...initial.profiles[0].record, avatarPhotoId: avatar.id }
    await expect(pushWithAccess(
      database, 'user-a', freeAccess,
      mutation('premium-policy-avatar-profile-free', 'profile', 'user-a', 1, profile),
    )).rejects.toMatchObject({ status: 403 })
    await expect(pushWithAccess(
      database, 'user-a', premiumAccess,
      mutation('premium-policy-avatar-profile-premium', 'profile', 'user-a', 1, profile),
    )).resolves.toMatchObject({ acknowledgements: [expect.objectContaining({ status: 'applied' })] })
  })

  it('atomically bounds concurrent free photo additions to two', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('quota-race-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const visit = visitPayload('quota-race-v', appleFixture.id, 'forged-user')
    await push(database, 'user-a', mutation('quota-race-v', 'visit', visit.id, 0, visit))
    const outcomes = await Promise.allSettled(Array.from({ length: 4 }, (_, index) => {
      const photo = { ...photoPayload(`quota-race-${index}`, appleFixture.id, visit.id, null, 'forged-user'), kind: 'visit' }
      return pushWithAccess(database, 'user-a', { isPremium: false, visitPhotoLimit: 2 },
        mutation(photo.id, 'photo', photo.id, 0, photo))
    }))
    expect(database.get('SELECT COUNT(*) AS count FROM photos WHERE visit_id = ? AND deleted_at IS NULL', visit.id).count).toBe(2)
    expect(outcomes.filter(outcome => outcome.status === 'fulfilled' && outcome.value.acknowledgements[0].status === 'applied')).toHaveLength(2)
  })

  it('reuses one Restaurant Dish across Visits with idempotent associations and no resurrection', async () => {
    const database = makeDatabase()
    await push(database, 'user-a', mutation('p2c-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const firstVisit = visitPayload('p2c-visit-1', appleFixture.id, 'forged-user')
    const secondVisit = visitPayload('p2c-visit-2', appleFixture.id, 'forged-user')
    await push(database, 'user-a', mutation('p2c-v1', 'visit', firstVisit.id, 0, firstVisit))
    await push(database, 'user-a', mutation('p2c-v2', 'visit', secondVisit.id, 0, secondVisit))

    const dish = dishPayload('p2c-dish', appleFixture.id, firstVisit.id, 'forged-user')
    await push(database, 'user-a', mutation('p2c-dish-create', 'dish', dish.id, 0, dish))
    const origin = visitDishPayload(
      `legacy:${dish.id}:${firstVisit.id}`, appleFixture.id, firstVisit.id, dish.id, 'forged-user',
    )
    const originAcknowledgement = await push(
      database, 'user-a', mutation('p2c-origin-explicit', 'visitDish', origin.id, 0, origin),
    )
    expect(originAcknowledgement.acknowledgements[0]).toMatchObject({
      status: 'applied', duplicate: true, serverVersion: 1,
    })

    const second = visitDishPayload(
      'p2c-association-2', appleFixture.id, secondVisit.id, dish.id, 'forged-user',
    )
    const create = mutation('p2c-association-create', 'visitDish', second.id, 0, second)
    await push(database, 'user-a', create)
    const retry = await push(database, 'user-a', create)
    expect(retry.acknowledgements[0]).toMatchObject({ duplicate: true, serverVersion: 1 })
    expect(database.get('SELECT COUNT(*) AS count FROM dishes WHERE id = ?', dish.id).count).toBe(1)
    expect(database.get('SELECT COUNT(*) AS count FROM visit_dishes WHERE dish_id = ?', dish.id).count).toBe(2)
    expect(JSON.parse(database.get('SELECT dishes_json FROM visits WHERE id = ?', secondVisit.id).dishes_json))
      .toEqual([expect.objectContaining({ id: dish.id, name: '寿喜烧' })])

    const clientB = await pull(database, 'user-a', '0')
    expect(clientB.dishes.map((item) => item.record.id)).toContain(dish.id)
    expect(clientB.visitDishes.map((item) => item.record.id)).toEqual(expect.arrayContaining([origin.id, second.id]))
    expect((await pull(database, 'user-b', '0')).visitDishes).toEqual([])
    await expect(push(database, 'user-b', mutation('p2c-takeover', 'visitDish', second.id, 1, second)))
      .rejects.toMatchObject({ status: 403 })

    const beforeDelete = clientB.nextCursor
    await push(database, 'user-a', deletion('p2c-association-delete', 'visitDish', second.id, 1))
    const deleted = await pull(database, 'user-a', beforeDelete)
    expect(deleted.tombstones).toContainEqual(expect.objectContaining({
      entityType: 'visitDish', entityId: second.id, serverVersion: 2,
    }))
    expect(database.get('SELECT deleted_at FROM dishes WHERE id = ?', dish.id).deleted_at).toBeNull()
    expect(JSON.parse(database.get('SELECT dishes_json FROM visits WHERE id = ?', secondVisit.id).dishes_json)).toEqual([])

    const stale = await push(database, 'user-a', mutation('p2c-stale-revive', 'visitDish', second.id, 1, second))
    expect(stale.acknowledgements[0]).toMatchObject({
      status: 'conflict', serverVersion: 2, conflictReason: 'server_version_mismatch',
    })
  })

  it('syncs private companions and recommendation sources with stable Visit associations', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'user-a')
    await push(database, 'user-a', mutation('p2f-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const companion = companionPayload('companion-wang', 'forged-user', '  小王  ')
    const source = sourcePayload('source-blogger', 'forged-user', '某美食博主', 'blogger')
    const companionCreate = mutation('p2f-companion-create', 'companion', companion.id, 0, companion)
    await push(database, 'user-a', companionCreate)
    expect((await push(database, 'user-a', companionCreate)).acknowledgements[0])
      .toMatchObject({ duplicate: true, serverVersion: 1 })
    await push(database, 'user-a', mutation('p2f-source-create', 'recommendationSource', source.id, 0, source))

    const visit = {
      ...visitPayload('p2f-visit', appleFixture.id, 'forged-user'), partySize: 2,
      companions: ['小王'], companionIds: [companion.id],
      recommendationSourceId: source.id, recommendationSourceType: 'blogger',
      recommendationSourceUserId: null, recommendationSourceText: '某美食博主', sharedMealId: null,
    }
    await push(database, 'user-a', mutation('p2f-visit-create', 'visit', visit.id, 0, visit))
    const first = await pull(database, 'user-a', '0')
    expect(first.companions[0].record).toMatchObject({
      id: companion.id, userId: 'user-a', displayName: '小王', linkedTasteMapUserId: null,
    })
    expect(first.recommendationSources[0].record).toMatchObject({
      id: source.id, userId: 'user-a', displayName: '某美食博主', sourceType: 'blogger',
    })
    expect(first.visits[0].record).toMatchObject({
      companions: ['小王'], companionIds: [companion.id],
      recommendationSourceId: source.id, recommendationSourceText: '某美食博主',
    })
    expect(database.get('SELECT owner_user_id FROM dining_companions WHERE id = ?', companion.id).owner_user_id)
      .toBe('user-a')
    expect((await pull(database, 'user-b', '0')).companions).toEqual([])
    expect((await pull(database, 'user-b', '0')).recommendationSources).toEqual([])

    const renamed = { ...companion, displayName: '王宇', updatedAt: '2026-08-27T09:30:00.000Z' }
    await push(database, 'user-a', mutation('p2f-companion-rename', 'companion', companion.id, 1, renamed))
    const incremental = await pull(database, 'user-a', first.nextCursor)
    expect(incremental.companions[0]).toMatchObject({ serverVersion: 2, record: { displayName: '王宇' } })
    expect(database.get('SELECT companions_json FROM visits WHERE id = ?', visit.id).companions_json)
      .toBe('["小王"]')

    await push(database, 'user-a', deletion('p2f-source-delete', 'recommendationSource', source.id, 1))
    const deleted = await pull(database, 'user-a', incremental.nextCursor)
    expect(deleted.tombstones).toContainEqual(expect.objectContaining({
      entityType: 'recommendationSource', entityId: source.id, serverVersion: 2,
    }))
    expect(database.get('SELECT recommendation_source_text FROM visits WHERE id = ?', visit.id).recommendation_source_text)
      .toBe('某美食博主')
    expect((await push(database, 'user-a', mutation(
      'p2f-source-resurrect', 'recommendationSource', source.id, 1, source,
    ))).acknowledgements[0]).toMatchObject({ status: 'conflict', serverVersion: 2 })
  })

  it('rejects cross-user Visit associations and conservatively deduplicates exact normalized names', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'user-a')
    await ensureUser(database, 'user-b')
    await push(database, 'user-a', mutation('p2f-iso-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const userBCompanion = companionPayload('private-b', 'user-b', 'Alex')
    await push(database, 'user-b', mutation('private-b-create', 'companion', userBCompanion.id, 0, userBCompanion))
    const forgedVisit = {
      ...visitPayload('p2f-forged-visit', appleFixture.id, 'user-b'),
      companions: ['Alex'], companionIds: [userBCompanion.id],
    }
    await expect(push(database, 'user-a', mutation('p2f-forged', 'visit', forgedVisit.id, 0, forgedVisit)))
      .rejects.toMatchObject({ status: 403 })

    const first = companionPayload('alex-upper', 'user-a', ' Alex ')
    await push(database, 'user-a', mutation('alex-first', 'companion', first.id, 0, first))
    const exact = companionPayload('alex-exact', 'user-a', 'Alex', '2026-08-27T07:00:00.000Z')
    expect((await push(database, 'user-a', mutation('alex-exact', 'companion', exact.id, 0, exact))).acknowledgements[0])
      .toMatchObject({ status: 'conflict', conflictReason: `duplicate_name:${first.id}` })
    const lower = companionPayload('alex-lower', 'user-a', 'alex', '2026-08-27T07:10:00.000Z')
    expect((await push(database, 'user-a', mutation('alex-lower', 'companion', lower.id, 0, lower))).acknowledgements[0])
      .toMatchObject({ status: 'applied' })
  })

  it('initializes one Profile, syncs it incrementally, and rejects cross-user takeover', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'user-a')
    await ensureUser(database, 'user-b')
    await ensureUserProfile(database, 'user-a')
    await ensureUserProfile(database, 'user-a')
    await ensureUserProfile(database, 'user-b')
    expect(database.get("SELECT COUNT(*) AS count FROM user_profiles WHERE user_id = 'user-a'").count).toBe(1)

    const initial = await pull(database, 'user-a', '0')
    expect(initial.profiles).toHaveLength(1)
    expect(initial.profiles[0].record).toMatchObject({
      userId: 'user-a', avatarPresetId: 'polar-bear', visibility: 'private',
    })
    const profile = {
      ...initial.profiles[0].record,
      displayName: '小林 🍜', bio: '周末一起吃饭。', city: '杭州',
      avatarPresetId: 'otter', visibility: 'public',
      updatedAt: '2026-08-28T10:00:00.000Z',
    }
    const update = mutation('profile-update', 'profile', 'user-a', 1, profile)
    const firstAck = (await push(database, 'user-a', update)).acknowledgements[0]
    expect(firstAck).toMatchObject({ status: 'applied', duplicate: false, serverVersion: 2 })
    expect((await push(database, 'user-a', update)).acknowledgements[0])
      .toMatchObject({ status: 'applied', duplicate: true, serverVersion: 2 })
    const incremental = await pull(database, 'user-a', initial.nextCursor)
    expect(incremental.profiles[0]).toMatchObject({
      serverVersion: 2,
      record: { displayName: '小林 🍜', bio: '周末一起吃饭。', avatarPresetId: 'otter' },
    })
    expect(database.get("SELECT nickname, email FROM users WHERE id = 'user-a'")).toMatchObject({
      nickname: '小林 🍜', email: null,
    })

    const stale = { ...profile, displayName: '过期修改', updatedAt: '2026-08-28T10:01:00.000Z' }
    expect((await push(database, 'user-a', mutation('profile-stale', 'profile', 'user-a', 1, stale))).acknowledgements[0])
      .toMatchObject({ status: 'conflict', serverVersion: 2 })
    await expect(push(database, 'user-b', mutation('profile-takeover', 'profile', 'user-a', 2, profile)))
      .rejects.toMatchObject({ status: 403 })
    await expect(push(database, 'user-a', deletion('profile-delete', 'profile', 'user-a', 2)))
      .rejects.toMatchObject({ status: 405 })
  })

  it('adopts an offline-first Profile only while its server bootstrap is untouched', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'offline-user')
    await ensureUserProfile(database, 'offline-user')
    const offlineProfile = {
      schemaVersion: 1, userId: 'offline-user', displayName: '离线用户',
      bio: '离线创建，联网后同步。', city: '成都', avatarPhotoId: null,
      avatarPresetId: 'otter', visibility: 'private',
      createdAt: '2026-08-28T09:00:00.000Z', updatedAt: '2026-08-28T09:00:00.000Z',
      deletedAt: null,
    }
    const offlineMutation = mutation(
      'offline-profile-create', 'profile', 'offline-user', 0, offlineProfile,
    )

    expect((await push(database, 'offline-user', offlineMutation)).acknowledgements[0])
      .toMatchObject({ status: 'applied', duplicate: false, serverVersion: 2 })
    expect((await push(database, 'offline-user', offlineMutation)).acknowledgements[0])
      .toMatchObject({ status: 'applied', duplicate: true, serverVersion: 2 })
    expect(database.get("SELECT COUNT(*) AS count FROM user_profiles WHERE user_id = 'offline-user'").count)
      .toBe(1)

    const secondBaseZero = mutation(
      'offline-profile-stale', 'profile', 'offline-user', 0,
      { ...offlineProfile, displayName: '不能覆盖', updatedAt: '2026-08-28T09:05:00.000Z' },
    )
    expect((await push(database, 'offline-user', secondBaseZero)).acknowledgements[0])
      .toMatchObject({ status: 'conflict', serverVersion: 2 })
  })

  it('returns only the Public Profile allowlist and counts only public Visit data', async () => {
    const database = makeDatabase()
    await ensureUser(database, 'user-a')
    await ensureUser(database, 'user-b')
    await ensureUserProfile(database, 'user-a')
    await ensureUserProfile(database, 'user-b')
    const initial = await pull(database, 'user-a', '0')
    const profile = {
      ...initial.profiles[0].record,
      displayName: '公开用户', bio: '公开简介', city: '上海', visibility: 'public',
      updatedAt: '2026-08-28T11:00:00.000Z',
    }
    await push(database, 'user-a', mutation('public-profile', 'profile', 'user-a', 1, profile))
    await push(database, 'user-a', mutation('profile-public-r', 'restaurant', appleFixture.id, 0, appleFixture))
    const publicVisit = { ...visitPayload('profile-public-v', appleFixture.id, 'forged'), visibility: 'public' }
    const privateVisit = { ...visitPayload('profile-private-v', appleFixture.id, 'forged'), visibility: 'private' }
    await push(database, 'user-a', mutation('profile-public-v', 'visit', publicVisit.id, 0, publicVisit))
    await push(database, 'user-a', mutation('profile-private-v', 'visit', privateVisit.id, 0, privateVisit))

    const publicDTO = await readPublicProfile(database, 'user-b', 'user-a')
    expect(publicDTO).toEqual({
      apiVersion: 1, userId: 'user-a', displayName: '公开用户', bio: '公开简介', city: '上海',
      avatarPhotoId: null, avatarPresetId: 'polar-bear', joinedAt: expect.any(String),
      statistics: { publicRestaurantCount: 1, publicVisitCount: 1 },
    })
    const serialized = JSON.stringify(publicDTO)
    for (const privateKey of [
      'email', 'authSubject', 'providerSubject', 'session', 'refreshToken',
      'restaurants', 'visits', 'companions', 'recommendationSources', 'storageKey',
    ]) expect(serialized).not.toContain(privateKey)

    const privateB = { ...initial.profiles[0].record, userId: 'user-b', visibility: 'private' }
    // User B already has an independently bootstrapped Profile; private access stays non-enumerable.
    expect(privateB.visibility).toBe('private')
    await expect(readPublicProfile(database, 'user-a', 'user-b'))
      .rejects.toMatchObject({ status: 404 })
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
    visitedAt: '2026-08-27T06:00:00.000Z', diningMode: 'dine_in', visibility: 'private', partySize: null,
    totalPrice: null, paymentMode: null, pricePerPerson: null, queueDuration: null,
    diningOccasions: [], diningOccasionText: null,
    rating: null, valueRating: null, environmentRating: null, serviceRating: null,
    valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null,
    diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: null,
    companions: [], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId: null,
    note: null, myActualSpend: null,
    createdAt: '2026-08-27T06:00:00.000Z', updatedAt: '2026-08-27T06:00:00.000Z', deletedAt: null,
  }
}

function legacyVisitPayload(id, restaurantId, claimedUser) {
  const {
    diningMode: _, visibility: __, partySize: ___,
    totalPrice: ____, paymentMode: _____, pricePerPerson: ______,
    queueDuration: _______, diningOccasions: ________, diningOccasionText: _________,
    valueRating: __________, environmentRating: ___________, serviceRating: ____________,
    valueTags: _____________, environmentTags: ______________, serviceTags: _______________,
    noiseLevel: ________________, diningDuration: _________________, portionLevel: __________________,
    transportConvenience: ___________________, specialNotes: ____________________,
    companions: _____________________, companionIds: ______________________,
    recommendationSourceId: _______________________,
    recommendationSourceType: ________________________,
    recommendationSourceUserId: _________________________,
    recommendationSourceText: __________________________,
    sharedMealId: ___________________________,
    ...legacy
  } = visitPayload(id, restaurantId, claimedUser)
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

function visitDishPayload(id, restaurantId, visitId, dishId, claimedUser) {
  return {
    schemaVersion: 1, id, userId: claimedUser, restaurantId, visitId, dishId,
    sortOrder: 0, createdAt: '2026-08-27T06:15:00.000Z',
    updatedAt: '2026-08-27T06:15:00.000Z', deletedAt: null,
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

function companionPayload(id, claimedUser, displayName, updatedAt = '2026-08-27T06:05:00.000Z') {
  return {
    schemaVersion: 1, id, userId: claimedUser, displayName,
    linkedTasteMapUserId: null, createdAt: '2026-08-27T06:05:00.000Z',
    updatedAt, deletedAt: null,
  }
}

function sourcePayload(id, claimedUser, displayName, sourceType = 'other') {
  return {
    schemaVersion: 1, id, userId: claimedUser, displayName, sourceType,
    linkedTasteMapUserId: null, createdAt: '2026-08-27T06:06:00.000Z',
    updatedAt: '2026-08-27T06:06:00.000Z', deletedAt: null,
  }
}

async function push(database, viewerId, ...mutations) {
  // Direct-handler fixtures mirror the authenticated user row the real router
  // establishes before allowing Sync API access.
  await ensureUser(database, viewerId)
  const request = new Request('http://localhost/api/v1/sync/push', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations }),
  })
  return handleSyncV1Push(database, viewerId, request)
}

async function pushWithAccess(database, viewerId, access, ...mutations) {
  const request = new Request('http://localhost/api/v1/sync/push', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations }),
  })
  return handleSyncV1Push(database, viewerId, request, access)
}

async function ensureUser(database, id) {
  await database.prepare(`INSERT OR IGNORE INTO users (
    id, auth_provider, nickname, created_at, updated_at
  ) VALUES (?, 'test', ?, ?, ?)`)
    .bind(id, id, '2026-08-27T06:00:00.000Z', '2026-08-27T06:00:00.000Z').run()
}

async function pull(database, viewerId, cursor) {
  return handleSyncV1Pull(database, viewerId, new Request(
    `http://localhost/api/v1/sync/pull?schemaVersion=1&cursor=${cursor}&limit=200`,
  ))
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  applyAllMigrations(sqlite)
  return new SQLiteD1Database(sqlite)
}

class SQLiteD1Database {
  constructor(sqlite) {
    this.sqlite = sqlite
    this.queryExecutions = 0
    this.batchCalls = 0
    this.maxBatchSize = 0
  }
  prepare(sql) {
    return new SQLiteD1Statement(this.sqlite, sql, [], () => { this.queryExecutions += 1 })
  }
  async batch(statements) {
    this.batchCalls += 1
    this.maxBatchSize = Math.max(this.maxBatchSize, statements.length)
    this.queryExecutions += statements.length
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
  resetMetrics() {
    this.queryExecutions = 0
    this.batchCalls = 0
    this.maxBatchSize = 0
  }
}

class SQLiteD1Statement {
  constructor(sqlite, sql, values = [], onExecute = () => {}) {
    this.sqlite = sqlite
    this.sql = sql
    this.values = values
    this.onExecute = onExecute
  }
  bind(...values) { return new SQLiteD1Statement(this.sqlite, this.sql, values, this.onExecute) }
  async first() {
    this.onExecute()
    return this.sqlite.prepare(this.sql).get(...this.values) ?? null
  }
  async all() {
    this.onExecute()
    return { results: this.sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} }
  }
  async run() {
    this.onExecute()
    return this.runSync()
  }
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
