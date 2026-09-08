import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from './index'
import { DISCOVERY_AGGREGATE_CAPACITY } from './discoveryVisitAggregates'
import { handleDiscoveryV1 } from './discoveryV1'
import { applyAllMigrations } from './testSupport/migrations.js'

const CITY = '杭州'
const now = Date.now()
const iso = (daysAgo = 0, minutesAgo = 0) => new Date(now - daysAgo * 86_400_000 - minutesAgo * 60_000).toISOString()

describe('Discovery API V1 integration', () => {
  let database

  it('reads owner feedback before pagination and rejects stale continuation after a new vote', async () => {
    const path = '/api/v1/discovery/for-you?city=杭州&limit=1'
    const before = await jsonAPI(database, 'tm_a', path)
    expect(before.items).toHaveLength(1)
    const id = before.items[0].restaurant.globalKey
    const event = { eventID:'dismiss-test',aliases:[id],source:'explicit_dismissal',occurredAt:iso(),intent:null }
    await database.prepare('INSERT INTO recommendation_preference_events (user_id,event_id,payload_json,received_at) VALUES (?,?,?,?)').bind('tm_a',event.eventID,JSON.stringify(event),iso()).run()
    const after = await jsonAPI(database,'tm_a',path)
    expect(after.items.every(item=>item.restaurant.globalKey!==id)).toBe(true)
    if (before.nextCursor) await expect(jsonAPI(database,'tm_a',path+'&cursor='+encodeURIComponent(before.nextCursor))).rejects.toThrow('400')
    await database.prepare('DELETE FROM recommendation_preference_events WHERE user_id=?').bind('tm_a').run()
    await database.prepare('INSERT INTO recommendation_preference_events (user_id,event_id,payload_json,received_at) VALUES (?,?,?,?)').bind('tm_b',event.eventID,JSON.stringify(event),iso()).run()
    expect((await jsonAPI(database,'tm_a',path)).items[0].restaurant.globalKey).toBe(id)
  })

  beforeEach(async () => {
    database = makeDatabase()
    for (const [id, name, visibility] of [
      ['tm_a', 'Alice', 'public'], ['tm_b', 'Bob', 'public'], ['tm_c', 'Carol', 'public'],
      ['tm_d', 'Dan', 'public'], ['tm_private', 'Private User', 'private'],
    ]) await seedUser(database, id, name, visibility)

    for (const [index, rating] of [5, 4.5, 4, 3.5, 3].entries()) {
      await seedVisit(database, { user: 'tm_a', slug: `shared-${index}`, rating, identity: `apple-shared-${index}`, tags: ['日料'] })
      await seedVisit(database, { user: 'tm_b', slug: `shared-${index}`, rating: rating - 0.5, identity: `apple-shared-${index}`, tags: ['日料'] })
      await seedVisit(database, { user: 'tm_c', slug: `shared-${index}`, rating: 5.5 - rating, identity: `apple-shared-${index}`, tags: ['日料'] })
    }
    await seedVisit(database, { user: 'tm_b', slug: 'bob-pick', rating: 5, identity: 'apple-bob-pick', tags: ['日料'] })
    await seedVisit(database, { user: 'tm_c', slug: 'carol-pick', rating: 4.5, identity: 'apple-carol-pick', tags: ['咖啡'] })
    await seedVisit(database, { user: 'tm_private', slug: 'secret-pick', rating: 5, visibility: 'private' })
    await seedVisit(database, { user: 'tm_private', slug: 'hidden-profile-public', rating: 5, visibility: 'public' })
    await seedVisit(database, { user: 'tm_b', slug: 'friend-pick', rating: 5, visibility: 'friends', tags: ['日料'] })
  })

  it.each(['for-you', 'similar-taste'])('preserves %s default unvisited and respects explicit visited/all without lowering evidence gates', async (mode) => {
    const base = `/api/v1/discovery/${mode}?city=杭州&limit=50`
    const implicit = await jsonAPI(database, 'tm_a', base)
    expect(implicit.items.some(item => item.viewerState === 'visited')).toBe(false)
    const partial = await jsonAPI(database, 'tm_a', `${base}&filters=${encodeURIComponent(JSON.stringify({ cuisines: ['日料'] }))}`)
    expect(partial.items.some(item => item.viewerState === 'visited')).toBe(false)
    const visited = await jsonAPI(database, 'tm_a', `${base}&filters=${encodeURIComponent(JSON.stringify({ viewerStates: ['visited'] }))}`)
    expect(visited.items.length).toBeGreaterThan(0)
    expect(visited.items.every(item => item.viewerState === 'visited' && item.reasons.length > 0)).toBe(true)
    const all = await jsonAPI(database, 'tm_a', `${base}&filters=${encodeURIComponent(JSON.stringify({ viewerStates: [] }))}`)
    expect(all.items.some(item => item.viewerState === 'visited')).toBe(true)
    expect(all.items.some(item => item.viewerState === 'none')).toBe(true)
    const none = await jsonAPI(database, 'tm_a', `${base}&filters=${encodeURIComponent(JSON.stringify({ viewerStates: ['none'] }))}`)
    expect(none.items.every(item => item.viewerState === 'none')).toBe(true)
  })

  it.each(['for-you', 'similar-taste', 'trending'])('hard filters merged candidates before %s qualification and pagination', async (mode) => {
    const filters = encodeURIComponent(JSON.stringify({ cuisines: ['日料'], minimumPublicScoreOutOfTen: 9, minimumPublicRatingUsers: 1, viewerStates: ['none'] }))
    const page = await jsonAPI(database, 'tm_a', `/api/v1/discovery/${mode}?city=杭州&limit=1&filters=${filters}`)
    expect(page.items).toHaveLength(1)
    expect(page.items[0].restaurant.name).toBe('bob-pick')
    expect(page.appliedQuery.filters.minimumPublicRatingUsers).toBe(1)
    expect(page.filterCapabilities.price.currencies).toEqual(['CNY'])
    expect(page.nextCursor).toBeNull()
  })

  it('counts distinct public reviewers across provider aliases, not repeated records or hidden accounts', async () => {
    await seedVisit(database, { user: 'tm_c', slug: 'bob-alias', rating: 5, identity: 'apple-bob-pick', tags: ['日料'] })
    const filters = encodeURIComponent(JSON.stringify({ minimumPublicRatingUsers: 2, minimumPublicScoreOutOfTen: 9, viewerStates: ['none'] }))
    let page = await jsonAPI(database, 'tm_a', `/api/v1/discovery/trending?city=杭州&filters=${filters}`)
    expect(page.items).toHaveLength(1)
    await database.prepare("UPDATE user_profiles SET visibility = 'private' WHERE user_id = 'tm_c'").run()
    page = await jsonAPI(database, 'tm_a', `/api/v1/discovery/trending?city=杭州&filters=${filters}`)
    expect(page.items).toEqual([])
  })

  it('uses an eligible photo after 1800 unrelated photos and rechecks deletion instead of library/avatar stand-ins', async () => {
    for (let index = 0; index < 1801; index++) await seedPhoto(database, 'visit-tm_b-shared-0', 'public', `unrelated-${index}`, 0)
    await seedPhoto(database, 'visit-tm_b-bob-pick', 'public', 'target-photo', 99)
    const filters = encodeURIComponent(JSON.stringify({ cuisines: ['日料'], viewerStates: ['none'], requireActualPhoto: true }))
    const path = `/api/v1/discovery/for-you?city=杭州&filters=${filters}`
    const page = await jsonAPI(database, 'tm_a', path)
    expect(page.items.map(item => item.restaurant.name)).toEqual(['bob-pick'])
    expect(page.items[0].restaurant.photo.photoId).toBe('target-photo')
    await database.prepare('UPDATE photos SET deleted_at = ? WHERE id = ?').bind(iso(), 'target-photo').run()
    expect((await jsonAPI(database, 'tm_a', path)).items).toEqual([])
  })

  it('removes actioned content from public filter statistics and discovery eligibility', async () => {
    await database.prepare(`INSERT INTO content_reports (id, reporter_user_id, content_type, content_id, reason, request_id, request_fingerprint, status, created_at, updated_at)
      VALUES ('moderated', 'tm_a', 'visit', 'visit-tm_b-bob-pick', 'spam', 'report-1', 'fingerprint', 'actioned', ?, ?)`).bind(iso(), iso()).run()
    const filters = encodeURIComponent(JSON.stringify({ cuisines: ['日料'], minimumPublicScoreOutOfTen: 9, viewerStates: ['none'] }))
    for (const mode of ['for-you', 'similar-taste', 'trending']) {
      expect((await jsonAPI(database, 'tm_a', `/api/v1/discovery/${mode}?city=杭州&filters=${filters}`)).items).toEqual([])
    }
  })

  it('does not satisfy actual-photo filtering while binary upload is incomplete or points to a different owner', async () => {
    await seedPhoto(database, 'visit-tm_b-bob-pick', 'public', 'not-ready')
    const filters = encodeURIComponent(JSON.stringify({ viewerStates: ['none'], requireActualPhoto: true }))
    const path = `/api/v1/discovery/for-you?city=杭州&filters=${filters}`
    for (const update of ["sync_status = 'pending'", "sync_status = 'synced', storage_key = NULL", "storage_key = 'users/tm_a/photos/not-ready/display.jpg'"]) {
      await database.prepare(`UPDATE photos SET ${update} WHERE id = 'not-ready'`).run()
      expect((await jsonAPI(database, 'tm_a', path)).items).toEqual([])
    }
  })

  it('can use a legitimate dish photo on a provider alias without inventing a Visit for it', async () => {
    const photoVisit = await seedVisit(database, { user: 'tm_d', slug: 'dish-only-alias', identity: 'apple-bob-pick' })
    await seedPhoto(database, photoVisit, 'public', 'dish-only-photo')
    await database.prepare("UPDATE photos SET visit_id = NULL, kind = 'dish' WHERE id = 'dish-only-photo'").run()
    await database.prepare('DELETE FROM visits WHERE id = ?').bind(photoVisit).run()
    const filters = encodeURIComponent(JSON.stringify({ requireActualPhoto: true, viewerStates: ['none'] }))
    const page = await jsonAPI(database, 'tm_a', `/api/v1/discovery/for-you?city=杭州&filters=${filters}`)
    expect(page.items).toHaveLength(1)
    expect(page.items[0].restaurant.photo.photoId).toBe('dish-only-photo')
    expect(page.items[0].ratings.community.sampleCount).toBe(1)
  })

  it('applies exploration limits to every server page without dropping deferred candidates', async () => {
    for (let index = 0; index < 11; index++) await seedVisit(database, { user: 'tm_b', slug: `new-taste-${index}`, rating: 4.5, tags: ['川菜'] })
    const filters = encodeURIComponent(JSON.stringify({ cuisines: ['川菜'] }))
    for (const [exploration, cap] of [['balanced', 4], ['adventurous', 8], ['familiar', 0]]) {
      const preferences = encodeURIComponent(JSON.stringify({ exploration }))
      const path = `/api/v1/discovery/for-you?city=杭州&limit=10&filters=${filters}&preferences=${preferences}`
      let page = await jsonAPI(database, 'tm_a', path)
      const ids = []
      do {
        expect(page.items.length).toBeLessThanOrEqual(cap)
        expect(page.items.every(item => item.reasons[0].code === 'SHORT_TERM_DIVERSITY')).toBe(true)
        ids.push(...page.items.map(item => item.restaurant.globalKey))
        if (!page.nextCursor) break
        page = await jsonAPI(database, 'tm_a', `${path}&cursor=${encodeURIComponent(page.nextCursor)}`)
      } while (ids.length < 20)
      expect(ids.length).toBe(cap ? 11 : 0)
      expect(new Set(ids).size).toBe(ids.length)
    }
  })

  it('sorts the full qualified set before pagination and binds filters, size and preferences to continuation', async () => {
    const first = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州&sort=public_rating&limit=1')
    expect(first.items[0].restaurant.name).toBe('bob-pick')
    expect(first.nextCursor).toBeTypeOf('string')
    const cursor = encodeURIComponent(first.nextCursor)
    for (const changed of ['&sort=taste', '&sort=public_rating&filters=%7B%22requireActualPhoto%22:true%7D', '&sort=public_rating&preferences=%7B%22exploration%22:%22familiar%22%7D']) {
      expect((await api(database, 'tm_a', `/api/v1/discovery/for-you?city=杭州&limit=1${changed}&cursor=${cursor}`)).status).toBe(400)
    }
    const second = await jsonAPI(database, 'tm_a', `/api/v1/discovery/for-you?city=杭州&sort=public_rating&limit=1&cursor=${cursor}`)
    expect(second.items[0].restaurant.name).toBe('carol-pick')
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
    expect(page.items.filter((item) => item.sourceUser).every((item) =>
      typeof item.activity?.visitId === 'string' &&
      typeof item.activity?.visitedAt === 'string' &&
      Object.hasOwn(item.activity, 'rating'),
    )).toBe(true)
    expect(page.items.flatMap((item) => item.reasons).every((reason) => reason.text && reason.code)).toBe(true)
    expect(page.items[0].reasons[0]).toMatchObject({ code: 'HIGH_CUISINE_MATCH', text: '你过去 5 家日料相关餐厅的平均评分为 8.0/10' })
    expect(page.items[0].reasons).toHaveLength(1)
    expect(page.items[0].personalTastePercent).toBeGreaterThanOrEqual(0)
    expect(page.items[0].personalTastePercent).toBeLessThanOrEqual(100)
    expect(page.items.flatMap((item) => item.reasons).map((reason) => reason.code)).not.toEqual(
      expect.arrayContaining(['FRIEND_HIGH_RATING', 'FOLLOWING_HIGH_RATING', 'SIMILAR_USERS']),
    )
    expect(page.items.every((item) => item.sourceUser === null && item.activity === null)).toBe(true)
    expect(JSON.stringify(page)).not.toContain('note')
    expect(JSON.stringify(page)).not.toContain('storageKey')
  })

  it('uses only the authenticated owner cross-city want intent for no-rating cold start', async () => {
    await seedUser(database, 'tm_new', 'New User', 'public')
    const wanted = await seedRestaurant(database, { user: 'tm_new', slug: 'wanted-away', city: '上海', status: 'wantToGo' })
    await database.prepare('UPDATE restaurants SET tags_json = ? WHERE id = ?').bind('["日料"]', wanted).run()
    const page = await jsonAPI(database, 'tm_new', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.length).toBeGreaterThan(0)
    expect(page.items.every(item => item.restaurant.city === '杭州' && item.personalTastePercent === null && item.reasons[0].code === 'WANT_TO_GO_MATCH')).toBe(true)
    const evidence = page.items[0].reasons[0].evidence
    expect(evidence.participants[0]).toMatchObject({ restaurantRecordIDs: [wanted], visitIDs: [], fields: { ratingCount: 0, meanOutOfTen: null } })
    await database.prepare('UPDATE restaurants SET deleted_at = ? WHERE id = ?').bind(iso(), wanted).run()
    expect((await jsonAPI(database, 'tm_new', '/api/v1/discovery/for-you?city=杭州')).items).toEqual([])
  })

  it('emits owner-only participating record IDs and no other-user private history in reasons', async () => {
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const participants = page.items.flatMap(item => item.reasons.flatMap(reason => reason.evidence?.participants ?? []))
    expect(participants.length).toBeGreaterThan(0)
    expect(participants.every(source => source.restaurantRecordIDs.every(id => id.startsWith('restaurant-tm_a-')) && source.visitIDs.every(id => id.startsWith('visit-tm_a-')))).toBe(true)
    expect(page.items.every(item => item.reasons.length <= 3 && new Set(item.reasons.map(reason => reason.code)).size === item.reasons.length)).toBe(true)
  })

  it('returns an honest empty For You feed for a new user instead of filling it with city trends', async () => {
    await seedUser(database, 'tm_new', 'New User', 'public')
    const page = await jsonAPI(database, 'tm_new', '/api/v1/discovery/for-you?city=杭州')
    expect(page.personalizationConfidence).toBe('insufficient')
    expect(page.items).toEqual([])
    const trends = await jsonAPI(database, 'tm_new', '/api/v1/discovery/trending?city=杭州')
    expect(trends.items.length).toBeGreaterThan(0)
  })

  it('labels sparse real positive records as preliminary without padding them with trends', async () => {
    await database.prepare("UPDATE visits SET deleted_at = ? WHERE user_id = 'tm_a' AND restaurant_id IN ('restaurant-tm_a-shared-3', 'restaurant-tm_a-shared-4')").bind(iso()).run()
    const page = await handleDiscoveryV1(new Request('https://example.test/api/v1/discovery/for-you?city=杭州'), database, 'tm_a', { isPremium: true })
    expect(page.items.map(item => item.restaurant.name)).toEqual(['bob-pick'])
    expect(page.items[0]).toMatchObject({ personalTastePercent: null, reasons: [{ code: 'INITIAL_HISTORY_MATCH' }] })
    expect(page.personalizationConfidence).toBe('low')
    expect(page.nextCursor).toBeNull()
  })

  it('counts aliases once and does not pad Premium explanations with unproven repetition', async () => {
    // A second owner Visit through an alias is one revisited place, not a fourth Restaurant.
    await seedVisit(database, { user: 'tm_a', slug: 'shared-alias', identity: 'apple-shared-0', rating: 3, tags: ['日料'], visibility: 'private' })
    await seedVisit(database, { user: 'tm_a', slug: 'deleted-evidence', rating: 5, tags: ['日料'], deleted: true })
    const premium = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const item = premium.items.find((card) => card.restaurant.name === 'bob-pick')
    expect(item.reasons).toHaveLength(1)
    expect(item.reasons[0]).toMatchObject({ code: 'HIGH_CUISINE_MATCH', text: '你过去 5 家日料相关餐厅的平均评分为 7.6/10' })
    const free = await handleDiscoveryV1(new Request('https://example.test/api/v1/discovery/for-you?city=杭州'), database, 'tm_a', { isPremium: false })
    expect(free.items.every((card) => card.reasons.length === 1 && card.similarity === null)).toBe(true)
    expect(free.items.map((card) => card.restaurant.globalKey)).toEqual(premium.items.map((card) => card.restaurant.globalKey))
    await expect(handleDiscoveryV1(new Request('https://example.test/api/v1/discovery/similar-taste?city=杭州'), database, 'tm_a', { isPremium: false })).rejects.toMatchObject({ status: 403, code: 'membership_required' })
  })

  it('uses approved legacy CNY for reliable bills while retaining price evidence thresholds', async () => {
    await database.prepare("UPDATE restaurants SET price_per_person = 100 WHERE user_id = 'tm_a' OR id = 'restaurant-tm_b-bob-pick'").run()
    const before = (await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')).items.find((card) => card.restaurant.name === 'bob-pick')
    expect(before.reasons.map(reason => reason.code)).not.toContain('PRICE_RANGE_MATCH')
    await database.prepare("UPDATE visits SET rating = 4.5, total_price = 200, party_size_optional = 2 WHERE user_id = 'tm_a' OR id = 'visit-tm_b-bob-pick'").run()
    const item = (await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')).items.find((card) => card.restaurant.name === 'bob-pick')
    expect(item.reasons.map(reason => reason.code)).toContain('PRICE_RANGE_MATCH')
    await database.prepare("UPDATE visits SET party_size_optional = NULL WHERE id = 'visit-tm_a-shared-0'").run()
    const insufficient = (await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')).items.find((card) => card.restaurant.name === 'bob-pick')
    expect(insufficient.reasons.map((reason) => reason.code)).not.toContain('PRICE_RANGE_MATCH')
  })

  it('treats a provider city suffix as the same discovery city', async () => {
    const requested = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州市')
    expect(requested.city).toBe('杭州')
    expect(requested.items.length).toBeGreaterThan(0)

    await database.prepare("UPDATE user_profiles SET city = '杭州市' WHERE user_id = 'tm_a'").run()
    const profiled = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you')
    expect(profiled.city).toBe('杭州')
    expect(profiled.items.length).toBeGreaterThan(0)
  })

  it('requires two actual cross-date repeat restaurants, merging aliases without counting them as new places', async () => {
    await seedVisit(database, { user: 'tm_a', slug: 'repeat-0', identity: 'apple-shared-0', rating: 4.5, tags: ['日料'], daysAgo: 5, visibility: 'private' })
    let page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.find(card => card.restaurant.name === 'bob-pick').reasons.map(reason => reason.code)).not.toContain('REPEAT_VISIT_PATTERN')
    await seedVisit(database, { user: 'tm_a', slug: 'repeat-1', identity: 'apple-shared-1', rating: 4.5, tags: ['日料'], daysAgo: 7, visibility: 'private' })
    page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.find(card => card.restaurant.name === 'bob-pick').reasons).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: 'REPEAT_VISIT_PATTERN', evidence: expect.objectContaining({ sampleCount: 2 }) }),
      expect.objectContaining({ code: 'HIGH_CUISINE_MATCH', evidence: expect.objectContaining({ sampleCount: 5 }) }),
    ]))
  })

  it('requires five shared restaurants, preserves forming evidence without precise percent, and never recommends self', async () => {
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/similar-taste?city=杭州')
    const bob = page.items.find((item) => item.sourceUser?.userId === 'tm_b')
    expect(bob.tasteEvidence).toMatchObject({ sharedRestaurantCount: 5, evidenceState: 'forming', supporterCount: 1 })
    expect(bob.similarity).toBeNull()
    expect(bob.reasons).toHaveLength(2)
    expect(bob.reasons[0].text).toBe('与你共同评过5家餐厅，双方对高低分的判断较接近。')
    expect(bob.reasons[1]).toEqual({ code: 'SOURCE_VISIT_RATING', text: `Bob给过${bob.activity.rating * 2}分。` })
    expect(bob.ratings.similarTaste).toEqual({ value: null, sampleCount: 1 })
    expect(page.items.every((item) => item.sourceUser?.userId !== 'tm_a')).toBe(true)
    expect(page.items.find((item) => item.sourceUser?.userId === 'tm_c')).toBeUndefined()

    await seedUser(database, 'tm_sparse', 'Sparse', 'public')
    await seedVisit(database, { user: 'tm_sparse', slug: 'shared-0-copy', rating: 5, identity: 'apple-shared-0' })
    const sparsePage = await jsonAPI(database, 'tm_sparse', '/api/v1/discovery/similar-taste?city=杭州')
    expect(sparsePage.items).toEqual([])
  })

  it('returns every genuine photo of the selected similar-taste Visit without borrowing another Visit or system attribution', async () => {
    const visitID = 'visit-tm_b-bob-pick'
    for (let index = 0; index < 12; index += 1) await seedPhoto(database, visitID, 'public', `album-${index}`, index)
    await seedPhoto(database, visitID, 'private', 'private', 0)
    await seedPhoto(database, visitID, 'public', 'deleted', 0)
    await database.prepare("UPDATE photos SET deleted_at = ? WHERE id = 'deleted'").bind(iso()).run()
    await seedPhoto(database, 'visit-tm_b-shared-0', 'public', 'unrelated-visit', 0)
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/similar-taste?city=杭州')
    const item = page.items.find((value) => value.activity?.visitId === visitID)
    expect(item.activity.photos.map((photo) => photo.photoId)).toEqual(Array.from({ length: 12 }, (_, index) => `album-${index}`))
    expect(item.activity.photos.every((photo) => photo.visitId === visitID && photo.ownerUserId === 'tm_b' &&
      photo.sourceType === 'activityAuthorPhoto' && photo.exportAllowed === false)).toBe(true)
    expect(JSON.stringify(item.activity.photos)).not.toMatch(/storage_key|storageKey|drive_file_id/)
    for (const path of ['for-you', 'trending']) {
      const system = await jsonAPI(database, 'tm_a', `/api/v1/discovery/${path}?city=杭州`)
      expect(system.items.every((value) => value.activity === null && value.sourceUser === null)).toBe(true)
    }
  })

  it('includes friends photos on a public Visit only for a real friend and narrows cache scope', async () => {
    const visitID = 'visit-tm_b-bob-pick'
    await acceptFriendship(database, 'tm_a', 'tm_b')
    await seedPhoto(database, visitID, 'public', 'friend-public')
    await seedPhoto(database, visitID, 'friends', 'friend-only', 1)
    await seedPhoto(database, visitID, 'private', 'still-private', 2)
    const request = () => jsonAPI(database, 'tm_a', '/api/v1/discovery/similar-taste?city=杭州')
    const friend = (await request()).items.find((value) => value.activity?.visitId === visitID)
    expect(friend.activity.photos.map((photo) => photo.photoId)).toEqual(['friend-public', 'friend-only'])
    expect(friend.cacheScope).toBe('friends')
    await database.prepare("UPDATE friendships SET status = 'removed'").run()
    const stranger = (await request()).items.find((value) => value.activity?.visitId === visitID)
    expect(stranger.activity.photos.map((photo) => photo.photoId)).toEqual(['friend-public'])
    expect(stranger.cacheScope).toBe('public')
    await database.prepare("UPDATE friendships SET status = 'accepted'").run()
    await database.prepare("UPDATE user_profiles SET visibility = 'private' WHERE user_id = 'tm_b'").run()
    expect((await request()).items.some((value) => value.sourceUser?.userId === 'tm_b')).toBe(false)
  })

  it('keeps nil and tombstoned ratings out of similarity and community aggregation', async () => {
    await seedVisit(database, { user: 'tm_b', slug: 'nil-rating', rating: null })
    await seedVisit(database, { user: 'tm_b', slug: 'below-qualified-rating', rating: 3.5, tags: ['日料'] })
    await seedVisit(database, { user: 'tm_b', slug: 'qualified-boundary-rating', rating: 3.75, tags: ['日料'] })
    await seedVisit(database, { user: 'tm_b', slug: 'deleted-rating', rating: 5, deleted: true })
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('nil-rating')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('below-qualified-rating')
    expect(page.items.map((item) => item.restaurant.name)).toContain('qualified-boundary-rating')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('deleted-rating')
    const trending = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&window=7')
    const nilActivity = trending.items.find((item) => item.restaurant.name === 'nil-rating')
    const lowActivity = trending.items.find((item) => item.restaurant.name === 'below-qualified-rating')
    expect(nilActivity?.activity).toBeNull()
    expect(nilActivity?.sourceUser).toBeNull()
    expect(lowActivity?.trend.uniqueVisitorCount).toBe(1)
  })

  it('never exposes explicit test Restaurants through a normal discovery request', async () => {
    await seedVisit(database, { user: 'tm_b', slug: 'fixture-only', rating: 5, tags: ['日料'] })
    await database.prepare("UPDATE restaurants SET is_test_data = 1 WHERE id = 'restaurant-tm_b-fixture-only'").run()

    const forYou = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const trending = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&window=7')
    expect(forYou.items.map((item) => item.restaurant.name)).not.toContain('fixture-only')
    expect(trending.items.map((item) => item.restaurant.name)).not.toContain('fixture-only')
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

  it('binds continuation to the authenticated viewer, mode, resolved city and normalized window', async () => {
    const first = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&limit=1')
    expect(first.nextCursor).toBeTypeOf('string')
    const cursor = encodeURIComponent(first.nextCursor)
    for (const [viewer, path] of [
      ['tm_b', '/api/v1/discovery/trending?city=杭州'],
      ['tm_a', '/api/v1/discovery/for-you?city=杭州'],
      ['tm_a', '/api/v1/discovery/similar-taste?city=杭州'],
      ['tm_a', '/api/v1/discovery/trending?city=上海'],
      ['tm_a', '/api/v1/discovery/trending?city=杭州&window=30'],
    ]) {
      const response = await api(database, viewer, `${path}&cursor=${cursor}`)
      expect(response.status).toBe(400)
      await expect(response.json()).resolves.toMatchObject({ error: expect.stringContaining('does not match') })
    }
    // Page size now binds the deterministic exploration page partition. A
    // changed size must refresh instead of skipping or duplicating candidates.
    expect((await api(database, 'tm_a', `/api/v1/discovery/trending?city=杭州&limit=3&cursor=${cursor}`)).status).toBe(400)
    const second = await jsonAPI(database, 'tm_a', `/api/v1/discovery/trending?city=%20杭州市%20&window=7&limit=1&cursor=${cursor}`)
    expect(second.generatedAt).toBe(first.generatedAt)
    expect(second.items[0].rank).toBe(2)
    expect(second.items.map(item => item.restaurant.globalKey)).not.toContain(first.items[0].restaurant.globalKey)
  })

  it('binds implicit city resolution and rejects a changed profile city, including an empty result scope', async () => {
    const first = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending?limit=1')
    expect(first.city).toBe('杭州')
    expect(first.nextCursor).toBeTypeOf('string')
    const cursor = encodeURIComponent(first.nextCursor)
    const explicit = await jsonAPI(database, 'tm_a', `/api/v1/discovery/trending?city=杭州市&limit=1&cursor=${cursor}`)
    expect(explicit.generatedAt).toBe(first.generatedAt)
    await database.prepare("UPDATE user_profiles SET city = '上海' WHERE user_id = 'tm_a'").run()
    const changed = await api(database, 'tm_a', `/api/v1/discovery/trending?cursor=${cursor}`)
    expect(changed.status).toBe(400)
    // Current visibility remains authoritative even though ranking time freezes.
    await database.prepare("UPDATE user_profiles SET city = '' WHERE user_id = 'tm_a'").run()
    await database.prepare("UPDATE visits SET deleted_at = ? WHERE user_id = 'tm_a'").bind(iso()).run()
    expect((await api(database, 'tm_a', `/api/v1/discovery/trending?cursor=${cursor}`)).status).toBe(400)
    const fresh = await jsonAPI(database, 'tm_a', '/api/v1/discovery/trending')
    expect(fresh.items).toEqual([])
  })

  it('rejects legacy unscoped, malformed and unknown-version cursors with a refreshable 400', async () => {
    const base64 = value => Buffer.from(JSON.stringify(value), 'utf8').toString('base64url')
    const current = [2, 30, 'apple:example', now, 'tm_a', 'trending', '杭州', 7]
    for (const cursor of [
      base64([30, 'apple:example', now]), base64([1, ...current.slice(1)]), base64([3, ...current.slice(1)]),
      base64({ score: 30, key: 'apple:example', snapshot: now }),
      base64([2, null, ...current.slice(2)]), base64([2, 30, '', ...current.slice(3)]),
      base64([2, 30, 'apple:example', -1, ...current.slice(4)]),
      base64([2, 30, 'apple:example', 1e100, ...current.slice(4)]),
      base64([...current.slice(0, 7), 8]), base64([...current, 'extra']), '', 'a'.repeat(4097),
    ]) {
      const response = await api(database, 'tm_a', `/api/v1/discovery/trending?city=杭州&cursor=${encodeURIComponent(cursor)}`)
      expect(response.status).toBe(400)
      await expect(response.json()).resolves.toMatchObject({ error: expect.stringContaining('invalid or outdated') })
    }
    // An omitted cursor remains a normal first-page request.
    expect((await api(database, 'tm_a', '/api/v1/discovery/trending?city=杭州&limit=1')).status).toBe(200)
  })

  it('makes friends-only signals visible only to accepted friends and revokes them immediately on unfriend', async () => {
    let page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('friend-pick')
    await acceptFriendship(database, 'tm_a', 'tm_b')
    page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const friendCard = page.items.find((item) => item.restaurant.name === 'friend-pick')
    expect(friendCard?.cacheScope).toBe('friends')
    expect(friendCard?.sourceUser).toBeNull()
    expect(friendCard?.activity).toBeNull()
    database.prepare("UPDATE friendships SET status = 'removed', deleted_at = ? WHERE pair_user_a = 'tm_a' AND pair_user_b = 'tm_b'").bind(iso()).run()
    page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('friend-pick')
  })

  it('allowlists PublicProfile and photo projections without leaking private source content', async () => {
    const publicVisit = await seedVisit(database, { user: 'tm_b', slug: 'photo-public', rating: 5, tags: ['日料'] })
    await seedPhoto(database, publicVisit, 'public')
    const privateVisit = await seedVisit(database, { user: 'tm_b', slug: 'photo-private', rating: 5, visibility: 'private', tags: ['日料'] })
    await seedPhoto(database, privateVisit, 'private')
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const card = page.items.find((item) => item.restaurant.name === 'photo-public')
    expect(card.sourceUser).toBeNull()
    expect(card.activity).toBeNull()
    expect(card.restaurant.photo).toMatchObject({
      photoId: `photo-${publicVisit}`,
      variant: 'thumbnail',
      sourceType: 'publicUGC',
      ownerUserId: 'tm_b',
      visibility: 'public',
      exportAllowed: false,
    })
    expect(page.items.map((item) => item.restaurant.name)).not.toContain('photo-private')

    database.prepare(`UPDATE photos SET visibility = 'private' WHERE id = ?`).bind(`photo-${publicVisit}`).run()
    const downgraded = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(downgraded.items.find((item) => item.restaurant.name === 'photo-public')?.restaurant.photo).toBeNull()

    database.prepare(`UPDATE photos SET visibility = 'public', deleted_at = ? WHERE id = ?`)
      .bind(iso(), `photo-${publicVisit}`).run()
    const deleted = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(deleted.items.find((item) => item.restaurant.name === 'photo-public')?.restaurant.photo).toBeNull()
  })

  it('never promotes another user private photo from a public Visit into system recommendations', async () => {
    const visit = await seedVisit(database, { user: 'tm_b', slug: 'public-visit-private-photo', rating: 5, tags: ['日料'] })
    await seedPhoto(database, visit, 'private')
    const page = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const card = page.items.find((item) => item.restaurant.name === 'public-visit-private-photo')
    expect(card).toBeDefined()
    expect(card.restaurant.photo).toBeNull()
  })

  it('ignores forged userId and keeps users isolated under authenticated actor', async () => {
    const forged = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州&userId=tm_b')
    const normal = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    expect(forged.items).toEqual(normal.items)
    expect((await api(database, '', '/api/v1/discovery/for-you?city=杭州')).status).toBe(401)
  })

  it('enforces Similar Taste on the server while keeping basic discovery available to Free users', async () => {
    const similar = await api(database, 'free-tester', '/api/v1/discovery/similar-taste?city=杭州')
    expect(similar.status).toBe(403)
    await expect(similar.json()).resolves.toMatchObject({ error: expect.stringContaining('Premium'), code: 'membership_required' })

    const unauthenticated = await api(database, '', '/api/v1/discovery/similar-taste?city=杭州')
    expect(unauthenticated.status).toBe(401)
    expect((await unauthenticated.json()).code).not.toBe('membership_required')

    const basic = await api(database, 'free-tester', '/api/v1/discovery/for-you?city=杭州')
    expect(basic.status).toBe(200)
    await expect(basic.json()).resolves.toMatchObject({ apiVersion: 1, mode: 'for_you' })
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

  it('returns structured 503 rather than a partial success through worker.fetch when complete cohorts exceed capacity', async () => {
    for (let index = 0; index <= DISCOVERY_AGGREGATE_CAPACITY; index++) {
      await seedVisit(database, {
        user: 'tm_b', slug: `capacity-${index}`, identity: `apple-capacity-${index}`,
        rating: 5, tags: ['日料'], minutesAgo: index,
      })
    }
    for (const mode of ['for-you', 'similar-taste', 'trending']) {
      const response = await api(database, 'tm_a', `/api/v1/discovery/${mode}?city=杭州&limit=1`)
      expect(response.status).toBe(503)
      const body = await response.json()
      expect(body).toEqual({
        code: 'DISCOVERY_AGGREGATE_CAPACITY',
        error: '当前城市的发现数据超出完整统计容量，请稍后重试。未返回不完整榜单。',
      })
      expect(body).not.toHaveProperty('items')
      expect(body).not.toHaveProperty('nextCursor')
    }
  })

  it('preserves weighted user means, qualified activity identity and both trend windows across repeated Visits', async () => {
    const bobHigh = await seedVisit(database, {
      user: 'tm_b', slug: 'aggregate-bob', name: 'Aggregate Place', identity: 'aggregate-place',
      rating: 5, tags: ['日料'], daysAgo: 10,
    })
    const restaurantID = database.get('SELECT restaurant_id FROM visits WHERE id = ?', bobHigh).restaurant_id
    for (const [id, rating, daysAgo, visibility] of [
      ['aggregate-bob-low', 1, 2, 'public'],
      ['aggregate-bob-unrated', null, 1, 'public'],
      ['aggregate-bob-friend', 4, 2, 'friends'],
    ]) {
      await database.prepare('INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,visibility,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)')
        .bind(id, 'tm_b', restaurantID, iso(daysAgo), rating, visibility, iso(daysAgo), iso(daysAgo)).run()
    }
    await seedVisit(database, { user: 'tm_b', slug: 'aggregate-alias', name: 'Aggregate Place',
      identity: 'aggregate-place', rating: 3.5, tags: ['日料'], daysAgo: 3 })
    await seedVisit(database, { user: 'tm_c', slug: 'aggregate-carol', name: 'Aggregate Place',
      identity: 'aggregate-place', rating: 4.5, tags: ['日料'], daysAgo: 1 })
    await acceptFriendship(database, 'tm_a', 'tm_b')

    const forYou = await jsonAPI(database, 'tm_a', '/api/v1/discovery/for-you?city=杭州')
    const recommendation = forYou.items.find(item => item.restaurant.name === 'Aggregate Place')
    // Public cohort: Bob's (5+1+3.5)/3 and Carol's 4.5 have equal user weight.
    expect(recommendation.ratings.community).toEqual({ value: 3.83, sampleCount: 2 })
    expect(recommendation.ratings.friends).toEqual({ value: 3.38, sampleCount: 1 })
    // Carol's latest public high rating is the For You quality source; the
    // separate Similar Taste source below is Bob's real friends-only Visit.
    expect(recommendation.cacheScope).toBe('public')

    const similar = await jsonAPI(database, 'tm_a', '/api/v1/discovery/similar-taste?city=杭州')
    const activity = similar.items.find(item => item.restaurant.name === 'Aggregate Place')
    expect(activity.sourceUser.userId).toBe('tm_b')
    expect(activity.activity).toEqual({ visitId: 'aggregate-bob-friend', visitedAt: iso(2), rating: 4, photos: [] })
    expect(activity.ratings.similarTaste).toEqual({ value: null, sampleCount: 1 })
    expect(activity.cacheScope).toBe('friends')

    for (const days of [7, 30]) {
      const page = await jsonAPI(database, 'tm_a', `/api/v1/discovery/trending?city=杭州&window=${days}`)
      const item = page.items.find(item => item.restaurant.name === 'Aggregate Place')
      expect(item.trend).toEqual({ windowDays: days, uniqueVisitorCount: 2, wantToGoCount: 0 })
      // Bob's 10-day-old public high rating counts only in the 30-day window;
      // his recent friends-only high rating must not count for public trends.
      const age = (Date.parse(page.generatedAt) - Date.parse(iso(1))) / 86_400_000
      const recency = Math.max(0, 1 - age / 120)
      const expected = 2 * (days === 7 ? 12 : 7) + (days === 7 ? 1 : 2) * 3 + recency * 2
      expect(item.score).toBe(Math.round(expected * 100) / 100)
    }
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

async function seedPhoto(database, visitID, visibility, photoID = `photo-${visitID}`, sortOrder = 0) {
  const visit = database.get('SELECT user_id, restaurant_id FROM visits WHERE id = ?', visitID)
  await database.prepare(`INSERT INTO photos (
    id, user_id, restaurant_id, visit_id, storage_key, thumbnail_storage_key, storage_provider, drive_account_id,
    drive_file_id, kind, mime_type, file_size, visibility, sync_status, created_at, updated_at, sort_order
  ) VALUES (?, ?, ?, ?, ?, ?, 'r2', '', '', 'visit', 'image/jpeg', 512, ?, 'synced', ?, ?, ?)`)
    .bind(photoID, visit.user_id, visit.restaurant_id, visitID,
      `users/${visit.user_id}/photos/${photoID}/display.jpg`, `users/${visit.user_id}/photos/${photoID}/thumbnail.jpg`,
      visibility, iso(), iso(), sortOrder).run()
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
    if (/^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)) return { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} }
    return this.runSync()
  }
  runSync() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes) } }
  }
}
