import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { TasteMapAnalyticsDirectoryEntryDTO, TasteMapAnalyticsSourceEntryDTO, TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { buildAnalyticsCompanionReport, buildAnalyticsSourceReport } from './analyticsSocialReport'
import { buildAnalyticsReport } from './analyticsReport'
import { analyticsReportHome } from './analyticsReportHome'

const owner = 'tm_analytics_owner'
const now = new Date('2026-09-06T12:00:00Z')
function restaurant(id: string, changes: Partial<RestaurantSummary> = {}): RestaurantSummary {
  return { ...fixture.restaurants[0] as unknown as RestaurantSummary, id, userId: owner, name: id, city: '杭州',
    status: 'visited', preferenceLevel: 'normal', tags: ['日料'], deletedAt: null, updatedAt: '2026-09-01', ...changes }
}
function visit(id: string, restaurantId: string, changes: Partial<Visit> = {}): Visit {
  return { ...fixture.restaurants[0].visits[0] as unknown as Visit, id, userId: owner, restaurantId, visitedAt: '2026-08-01T12:00:00Z',
    companions: [], companionIds: [], recommendationSourceType: null, recommendationSourceText: '', recommendationSourceUserId: null,
    rating: null, valueRating: null, environmentRating: null, serviceRating: null, note: '', dishes: [], photos: [], photoIds: [],
    diningOccasions: [], diningMode: 'dine_in', totalPrice: null, myActualSpend: null, paymentMode: null, partySize: null,
    deletedAt: null, updatedAt: '2026-09-01', ...changes }
}
function companion(id: string, displayName = id, changes: Partial<TasteMapAnalyticsDirectoryEntryDTO> = {}): TasteMapAnalyticsDirectoryEntryDTO {
  return { id, displayName, ownerUserID: owner, identifiers: [id], updatedAt: '2026-09-01', deletedAt: null, ...changes }
}
function source(id: string, displayName = id): TasteMapAnalyticsSourceEntryDTO {
  return { ...companion(id, displayName), sourceType: 'friend' }
}
function profile(restaurants: RestaurantSummary[], visits: Visit[]): TasteMapProfileDashboardViewModel {
  return { user: { ...fixture.profile.user as unknown as UserProfile, id: owner, city: '杭州' }, restaurants, visits, followerCount: 0, followingCount: 0, restaurantImages: {} }
}
function sourceInput(countA: number, countB: number) {
  const restaurants: RestaurantSummary[] = []; const visits: Visit[] = []; const links: { visitID: string; sourceID: string }[] = []
  for (const [id, count, rating] of [['a', countA, 4.5], ['b', countB, 2]] as const) for (let index = 0; index < count; index++) {
    const restaurantID = `${id}-${index}`; restaurants.push(restaurant(restaurantID)); visits.push(visit(restaurantID, restaurantID, { rating, recommendationSourceText: id })); links.push({ visitID: restaurantID, sourceID: id })
  }
  return { profile: profile(restaurants, visits), options: { sources: [source('a'), source('b')], visitSourceLinks: links, now } }
}

describe('stable companion report', () => {
  it('does not turn a single high score into a source champion', () => {
    const one = sourceInput(1, 5)
    const home = analyticsReportHome(buildAnalyticsReport(one.profile, { ...one.options, mode: 'source' }))
    expect(home.sourceLeaders).toEqual([])
    expect(home.headline).toContain('先不选出冠军')
    const enough = sourceInput(6, 5)
    const qualified = analyticsReportHome(buildAnalyticsReport(enough.profile, { ...enough.options, mode: 'source' }))
    expect(qualified.sourceLeaders.map(item => item.id)).toEqual(['a'])
    expect(qualified.sourceLeaders[0]).toMatchObject({ highRatingCount: 6, ratedRestaurantCount: 6 })
  })
  it('excludes contradictory solo/companion records and distinguishes repeat Visits from Restaurants', () => {
    const data = profile([restaurant('r')], [visit('old', 'r', { visitedAt: '2026-07-01' }), visit('a', 'r', { companionIds: ['c'] }), visit('b', 'r', { companionIds: ['c'] }), visit('conflict', 'r', { companionIds: ['c'], diningOccasions: ['solo'] })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('c')], now })
    expect(result.unresolvedVisitCount).toBe(1)
    expect(result.companions[0]).toMatchObject({ sharedVisitCount: 2, firstTogetherRestaurantCount: 0, repeatVisitCount: 1 })
    expect(result.visitIDs).not.toContain('conflict')
  })
  it('compares directory revision instants so an offset-formatted stale name cannot revive a deleted companion', () => {
    const data = profile([restaurant('r')], [visit('v', 'r', { companionIds: ['a'] })])
    const stale = companion('a', '旧名字', { updatedAt: '2026-09-01T09:00:00+08:00' })
    const tombstone = companion('a', '已删除', { updatedAt: '2026-09-01T02:00:00Z', deletedAt: '2026-09-01T02:00:00Z' })
    expect(buildAnalyticsCompanionReport(data, { companions: [tombstone, stale], now }).companions).toEqual([])
    expect(buildAnalyticsCompanionReport(data, { companions: [stale, tombstone], now }).companions).toEqual([])
  })
  it('distinguishes missing directories from a known empty directory without deriving names', () => {
    const data = profile([restaurant('r')], [visit('v', 'r', { companions: ['小王'] })])
    expect(buildAnalyticsCompanionReport(data).identityAvailability).toBe('unavailable')
    expect(buildAnalyticsCompanionReport(data).companions).toEqual([])
    expect(buildAnalyticsCompanionReport(profile([], []), { companions: [] }).identityAvailability).toBe('available')
  })
  it('does not merge same names, resolve unknown formal IDs by name, or use linked user IDs', () => {
    const data = profile([restaurant('r')], [visit('a', 'r', { companions: ['小王'] }), visit('b', 'r', { companionIds: ['one', 'one'], companions: ['小王'] }),
      visit('c', 'r', { companionIds: ['missing'], companions: ['唯一名'] })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('one', '小王'), companion('two', '小王'), companion('three', '唯一名')] })
    expect(result.companions.map(item => [item.id, item.sharedVisitCount])).toEqual([['one', 1], ['three', 0], ['two', 0]])
    expect(result.unresolvedVisitCount).toBe(2)
  })
  it('keeps renamed stable IDs, local/remote aliases, and each explicitly selected companion', () => {
    const data = profile([restaurant('r')], [visit('v', 'r', { companionIds: ['REMOTE-A', 'b'], companions: ['旧名'] }), visit('legacy', 'r', { companions: ['  唯一名  '] })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a', '新名字', { identifiers: ['remote-a'] }), companion('b', '唯一名')] })
    expect(result.companions.map(item => [item.id, item.sharedVisitCount])).toEqual([['b', 2], ['a', 1]])
    expect(result.summary.visitCount).toBe(2) // One shared meal is not two dashboard visits.
    expect(result.companions[1].displayName).toBe('新名字')
  })
  it('filters foreign/orphan/deleted records and latest directory tombstones without resurrection', () => {
    const data = profile([restaurant('r'), restaurant('foreign', { userId: 'tm_other' })], [visit('good', 'r', { companionIds: ['a'] }),
      visit('foreign', 'r', { companionIds: ['a'], userId: 'tm_other' }), visit('orphan', 'missing', { companionIds: ['a'] }), visit('bad', 'foreign', { companionIds: ['a'] })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a'), companion('a', 'deleted', { deletedAt: '2026-09-02', updatedAt: '2026-09-02' }), companion('foreign', 'foreign', { ownerUserID: 'tm_other' })] })
    expect(result.companions).toEqual([])
    expect(result.unresolvedVisitCount).toBe(1)
    expect(result.summary.visitCount).toBe(0)
  })
  it.each([[2, 2, 'insufficient'], [3, 1, 'insufficient'], [3, 2, 'emerging'], [6, 2, 'emerging'], [8, 3, 'emerging'], [8, 4, 'established']] as const)('uses %i visits and %i restaurants for %s evidence', (count, restaurantCount, expected) => {
    const data = profile(Array.from({ length: restaurantCount }, (_, i) => restaurant(`r${i}`)), Array.from({ length: count }, (_, i) => visit(`${i}`, `r${i % restaurantCount}`, { companionIds: ['a'] })))
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a')], now })
    expect(result.companions[0].confidence).toBe(expected)
    if (count === 2) expect(result.companions[0].keywords).toEqual([])
  })
  it('uses distinct shared restaurants for repeat rate, valid own ratings and scoped spend median', () => {
    const data = profile([restaurant('r'), restaurant('s')], [visit('1', 'r', { companionIds: ['a'], rating: 4, myActualSpend: 0 }),
      visit('2', 'r', { companionIds: ['a'], rating: 5, myActualSpend: 100 }), visit('3', 'r', { companionIds: ['a'], myActualSpend: 30 }),
      visit('4', 's', { companionIds: ['a'], myActualSpend: 10, note: 'never-export-private-note' })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a')], now, timeZone: 'UTC' })
    const detail = result.companions[0]
    expect(detail.repeatRate).toBe(.5)
    expect(detail.ratingAverage).toBe(9)
    expect(detail.ratedVisitCount).toBe(2)
    expect(detail.ratingDelta).toBeNull() // Baseline needs three actual rated Visits.
    expect(detail.spend.median).toBe(20)
    expect(JSON.stringify(result)).not.toContain('never-export-private-note')
  })
  it('prefers repeated same-Restaurant Dish IDs, not name collisions; excludes scene tags from cuisines', () => {
    const dish = { id: 'dish', name: '拉面', taste: '', rating: null, price: null, imageData: null, photoId: null }
    const data = profile([restaurant('r', { tags: ['日料', '安静', '商场'] }), restaurant('s')], [visit('1', 'r', { companionIds: ['a'], dishes: [dish, dish] }), visit('2', 's', { companionIds: ['a'], dishes: [dish] })])
    expect(buildAnalyticsCompanionReport(data, { companions: [companion('a')] }).companions[0].foods.map(item => item.label)).toEqual(['日料'])
    data.visits.push(visit('3', 'r', { companionIds: ['a'], dishes: [dish] }))
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a')] })
    expect(result.companions[0].foods[0]).toMatchObject({ label: '拉面', count: 2 })
  })
  it('scopes companions to exact period Visit IDs while keeping stable identity and same-city next-meal limits', () => {
    const data = profile([restaurant('r'), restaurant('wanted', { city: '杭州市', status: 'wantToGo' }), restaurant('far', { city: '上海', status: 'wantToGo' }), restaurant('avoid', { preferenceLevel: 'avoid' })],
      [visit('old', 'r', { companionIds: ['a'], visitedAt: '2026-01-01' }), visit('month', 'r', { companionIds: ['a'] })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a')], visitIDs: ['month'], now })
    expect(result.summary.visitCount).toBe(1)
    expect(result.companions[0].recommendations.map(item => item.restaurantID)).toEqual(['wanted'])
  })
  it('switching companion keeps summary and representative restaurants on that exact companion', () => {
    const data = profile([restaurant('r'), restaurant('s')], [visit('a1', 'r', { companionIds: ['a'], rating: 5 }), visit('b1', 's', { companionIds: ['b'], rating: 1 }), visit('b2', 's', { companionIds: ['b'], rating: 1 })])
    const options = { companions: [companion('a'), companion('b')] }
    const a = buildAnalyticsCompanionReport(data, { ...options, selectedCompanionID: 'a' })
    const b = buildAnalyticsCompanionReport(data, { ...options, selectedCompanionID: 'b' })
    expect(a.summary).toMatchObject({ visitCount: 1, averageScoreOutOfTen: 10 })
    expect(b.summary).toMatchObject({ visitCount: 2, averageScoreOutOfTen: 2 })
    expect(a.topRestaurants.map(item => item.id)).toEqual(['r'])
    expect(b.topRestaurants.map(item => item.id)).toEqual(['s'])
    expect(a.sections[0].title).toContain('全部')
    const removed = buildAnalyticsCompanionReport(data, { ...options, selectedCompanionID: 'deleted-id' })
    expect(removed.selectedCompanionID).toBeNull()
    expect(removed.summary.visitCount).toBe(0)
    expect(removed.topRestaurants).toEqual([])
  })
  it('keeps all named companion sections explicitly private and processes a large local history without N+1 reads', () => {
    const restaurants = Array.from({ length: 100 }, (_, index) => restaurant(`r${index}`))
    const companions = Array.from({ length: 200 }, (_, index) => companion(`c${index}`, `私密饭友${index}`))
    const visits = Array.from({ length: 3000 }, (_, index) => visit(`v${index}`, `r${index % 100}`, { companionIds: [`c${index % 200}`], rating: 4 }))
    const started = performance.now()
    const result = buildAnalyticsCompanionReport(profile(restaurants, visits), { companions, now, timeZone: 'UTC' })
    expect(result.companions).toHaveLength(200)
    expect(result.companions.every(item => item.sharedVisitCount === 15)).toBe(true)
    expect(performance.now() - started).toBeLessThan(2000)
    expect(result.sections.filter(section => JSON.stringify(section).includes('私密饭友')).every(section => section.privacy === 'companion')).toBe(true)
    expect(result.sections.find(section => section.id === 'companion-spend')?.privacy).toBe('spend')
  })
  it('uses the one supplied snapshot time and local calendar date rather than a UTC date prefix', () => {
    const localVisit = visit('past', 'r', { companionIds: ['a'], visitedAt: '2026-08-01T23:30:00Z' })
    const data = profile([restaurant('r')], [localVisit, visit('future', 'r', { companionIds: ['a'], visitedAt: '2026-10-01T12:00:00Z' })])
    const result = buildAnalyticsCompanionReport(data, { companions: [companion('a')], now, timeZone: 'Asia/Shanghai' })
    expect(result.summary.visitCount).toBe(1)
    expect(result.sections.find(section => section.id === 'companion-pattern')?.metrics?.find(metric => metric.id === 'latest')?.value).toBe('2026/08/02')
  })
})

describe('formal recommendation source report', () => {
  it('excludes pre-attribution visits from source counts, spend and evidence while retaining them in the personal baseline', () => {
    const data = profile([restaurant('r')], [
      visit('before', 'r', { visitedAt: '2026-01-01', rating: 5, myActualSpend: 900 }),
      visit('acquired', 'r', { visitedAt: '2026-08-01', rating: 2, myActualSpend: 40 }),
      visit('repeat', 'r', { visitedAt: '2026-08-02', rating: 4, myActualSpend: 60 }),
    ])
    const result = buildAnalyticsSourceReport(data, { sources: [source('a')], visitSourceLinks: [{ visitID: 'acquired', sourceID: 'a' }], now })
    expect(result.summary).toMatchObject({ visitCount: 2, averageScoreOutOfTen: 6, spend: { total: 100, median: 50 } })
    expect(result.sources[0].spend).toMatchObject({ total: 100, recordedVisitCount: 2, median: 50 })
    expect(result.topRestaurants[0]).toMatchObject({ count: 2, scoreOutOfTen: 4 })
    expect(result.visitIDs).toEqual(['acquired', 'repeat'])
    expect(result.overallSourceRating).toBe(10)
  })
  it('does not replace missing source entities/associations with a linked social user or platform aggregate', () => {
    const data = profile([restaurant('r')], [visit('v', 'r', { recommendationSourceType: 'xiaohongshu', recommendationSourceUserId: 'linked-not-a-source', recommendationSourceText: '小红书' })])
    const result = buildAnalyticsSourceReport(data)
    expect(result.identityAvailability).toBe('unavailable')
    expect(result.sources).toEqual([])
    expect(result.conclusions).toEqual([])
    expect(JSON.stringify(result)).not.toContain('linked-not-a-source')
    expect(buildAnalyticsSourceReport(profile([], []), { sources: [], visitSourceLinks: [] }).identityAvailability).toBe('available')
  })
  it('allows only unique exact legacy names with an explicitly ID-less association', () => {
    const data = profile([restaurant('r'), restaurant('s')], [visit('v', 'r', { recommendationSourceText: '小红书' }), visit('w', 's', { recommendationSourceText: '小红书 @ABC' })])
    const options = { sources: [source('a', '小红书'), source('b', '小红书'), source('c', '小红书 @ABC')], visitSourceLinks: [{ visitID: 'v', sourceID: null }, { visitID: 'w', sourceID: null }] }
    const result = buildAnalyticsSourceReport(data, options)
    expect(result.sources.find(item => item.id === 'c')?.restaurantCount).toBe(1)
    expect(result.sources.filter(item => item.id !== 'c').map(item => item.restaurantCount)).toEqual([0, 0])
    expect(buildAnalyticsSourceReport(data, { sources: options.sources, visitSourceLinks: [] }).summary.visitCount).toBe(0)
  })
  it('never reassigns an unresolved formal source by its text snapshot', () => {
    const data = profile([restaurant('r')], [visit('v', 'r', { recommendationSourceText: '已有来源' })])
    const result = buildAnalyticsSourceReport(data, { sources: [source('a', '已有来源')], visitSourceLinks: [{ visitID: 'v', sourceID: 'deleted-source' }] })
    expect(result.sources[0].restaurantCount).toBe(0)
    expect(result.unresolvedVisitCount).toBe(1)
  })
  it('excludes conflicting restaurant sources instead of inventing a primary source', () => {
    const data = profile([restaurant('r'), restaurant('s')], [visit('later', 'r', { visitedAt: '2026-08-03', rating: 5 }), visit('first', 'r', { visitedAt: '2026-08-01', rating: 5 }), visit('second', 's', { rating: 1 })])
    const result = buildAnalyticsSourceReport(data, { sources: [source('a'), source('b')], visitSourceLinks: [{ visitID: 'first', sourceID: 'a' }, { visitID: 'later', sourceID: 'b' }, { visitID: 'second', sourceID: 'a' }] })
    expect(result.sources[0]).toMatchObject({ id: 'a', restaurantCount: 1, ratedRestaurantCount: 1, averageScoreOutOfTen: 2, repeatRestaurantCount: 0 })
    expect(result.sources[1].restaurantCount).toBe(0)
    expect(result.ambiguousRestaurantIDs).toEqual(['r'])
  })
  it('uses stable Visit-ID ties and does not reattribute past discoveries when filtering a month', () => {
    const data = profile([restaurant('r'), restaurant('s')], [visit('a-old', 'r', { visitedAt: '2026-07-01', rating: 5 }), visit('z-month', 'r', { visitedAt: '2026-08-01', rating: 1 }), visit('new-month', 's', { rating: 4 })])
    const result = buildAnalyticsSourceReport(data, { sources: [source('a'), source('b')], visitSourceLinks: [{ visitID: 'a-old', sourceID: 'a' }, { visitID: 'z-month', sourceID: 'b' }, { visitID: 'new-month', sourceID: 'b' }], visitIDs: ['z-month', 'new-month'] })
    expect(result.sources.find(item => item.id === 'a')?.restaurantCount).toBe(0)
    expect(result.sources.find(item => item.id === 'b')).toMatchObject({ restaurantCount: 1, averageScoreOutOfTen: 8 })
    expect(result.summary.visitCount).toBe(1)
  })
  it.each([[4, 0], [4, 4], [0, 4]])('does not rank best/worst below five restaurants: %i and %i', (a, b) => {
    const input = sourceInput(a, b); const result = buildAnalyticsSourceReport(input.profile, input.options)
    expect(result.bestSourceID).toBeNull(); expect(result.worstSourceID).toBeNull()
  })
  it('uses a personal first-experience baseline and actual pitfall evidence', () => {
    const input = sourceInput(6, 6); const result = buildAnalyticsSourceReport(input.profile, input.options)
    expect(result.bestSourceID).toBe('a'); expect(result.worstSourceID).toBe('b')
    expect(result.eligibleSourceCount).toBe(2)
    expect(result.conclusions.find(item => item.id === 'worst')?.explanation).toContain('6 家体验不如平时')
    expect(result.overallSourceRating).toBe(6.5)
    expect(result.comparisonTopRestaurants.filter(item => item.detail === '靠谱来源代表').every(item => item.scoreOutOfTen! >= 8)).toBe(true)
    expect(result.comparisonTopRestaurants.filter(item => item.detail === '踩坑餐厅').every(item => item.scoreOutOfTen! <= result.overallSourceRating! - 1)).toBe(true)
    expect(new Set(result.topRestaurants.map(item => item.id)).size).toBe(result.topRestaurants.length)
    expect(JSON.stringify(result.sections)).not.toContain('reliabilityScore')
  })
  it('nil and invalid ratings count as usage but not comparison, while no-source Visits are not errors', () => {
    const input = sourceInput(6, 6)
    input.profile.visits[0].rating = null
    input.profile.visits.push(visit('unattributed', 'a-0'))
    input.options.visitSourceLinks.push({ visitID: 'unattributed', sourceID: '' })
    const result = buildAnalyticsSourceReport(input.profile, input.options)
    expect(result.sources.find(item => item.id === 'a')).toMatchObject({ restaurantCount: 6, ratedRestaurantCount: 5 })
    expect(result.bestSourceID).toBe('a')
    expect(result.unresolvedVisitCount).toBe(0)
  })
  it('recomputes after rename/delete and rejects foreign proof bundles without accepting the owner sentinel broadly', () => {
    const input = sourceInput(6, 6)
    input.profile.analyticsIdentity = { ownerUserID: 'tm_other', recordOwnerID: owner, companions: [], sources: input.options.sources, visitSourceLinks: input.options.visitSourceLinks }
    expect(buildAnalyticsSourceReport(input.profile).identityAvailability).toBe('unavailable')
    input.options.sources[0].displayName = '最新名字'
    expect(buildAnalyticsSourceReport(input.profile, input.options).conclusions.find(item => item.id === 'best')?.label).toBe('最新名字')
    input.options.sources[0].deletedAt = '2026-09-02'
    expect(buildAnalyticsSourceReport(input.profile, input.options).sources.map(item => item.id)).toEqual(['b'])
    expect(buildAnalyticsSourceReport(input.profile, input.options).bestSourceID).toBeNull()
  })
  it('switching source keeps selected summary/top evidence distinct from explicitly labeled all-source comparison', () => {
    const input = sourceInput(6, 7)
    const a = buildAnalyticsSourceReport(input.profile, { ...input.options, selectedSourceID: 'a' })
    const b = buildAnalyticsSourceReport(input.profile, { ...input.options, selectedSourceID: 'b' })
    expect(a.summary).toMatchObject({ visitCount: 6, averageScoreOutOfTen: 9 })
    expect(b.summary).toMatchObject({ visitCount: 7, averageScoreOutOfTen: 4 })
    expect(a.topRestaurants.every(item => item.id.startsWith('a-'))).toBe(true)
    expect(b.topRestaurants.every(item => item.id.startsWith('b-'))).toBe(true)
    expect(a.sections.find(section => section.id === 'source-conclusions')?.title).toContain('全部来源')
    const removed = buildAnalyticsSourceReport(input.profile, { ...input.options, selectedSourceID: 'deleted-source' })
    expect(removed.selectedSourceID).toBeNull()
    expect(removed.summary.visitCount).toBe(0)
    expect(removed.topRestaurants).toEqual([])
  })
  it('keeps source cuisines Restaurant-weighted, personal spend private and unstable three-sample ratings honest', () => {
    const input = sourceInput(3, 0)
    input.profile.visits[0].rating = .5; input.profile.visits[1].rating = 5; input.profile.visits[2].rating = 5
    for (const item of input.profile.visits) item.myActualSpend = 40
    const result = buildAnalyticsSourceReport(input.profile, input.options)
    const selected = result.sources[0]
    expect(selected.cuisines).toEqual([expect.objectContaining({ label: '日料', count: 3 })])
    expect(selected.spend.median).toBe(40)
    expect(selected.ratingStability).toBe('volatile')
    expect(result.sections.find(section => section.id === 'source-spend')?.privacy).toBe('spend')
    expect(result.bestSourceID).toBeNull()
  })
  it('does not let future source Visits create usage or shift the date shown for a real acquisition', () => {
    const data = profile([restaurant('r'), restaurant('future')], [visit('past', 'r', { visitedAt: '2026-08-01T23:30:00Z' }), visit('future', 'future', { visitedAt: '2026-10-01' })])
    const result = buildAnalyticsSourceReport(data, { sources: [source('a')], visitSourceLinks: [{ visitID: 'past', sourceID: 'a' }, { visitID: 'future', sourceID: 'a' }], now, timeZone: 'Asia/Shanghai' })
    expect(result.summary.visitCount).toBe(1)
    expect(result.sources[0].restaurantCount).toBe(1)
    expect(result.sections.find(section => section.id === 'source-outcomes')?.metrics?.find(metric => metric.id === 'latest')?.value).toBe('2026/08/02')
  })
  it('admits five, rejects four, and includes unassociated first Visits in the unrounded baseline', () => {
    const input = sourceInput(5, 4)
    input.profile.restaurants.push(restaurant('own'))
    input.profile.visits.push(visit('own-first', 'own', { rating: 5 }))
    const result = buildAnalyticsSourceReport(input.profile, input.options)
    expect(result.eligibleSourceCount).toBe(1)
    expect(result.baselineRestaurantCount).toBe(10)
    expect(result.overallSourceRating).toBe(7.1)
    expect(result.worstSourceID).toBeNull() // the low source has only four samples
  })
  it('does not let repeat scores change first-experience classification or fill an unrated first Visit', () => {
    const input = sourceInput(5, 5)
    const before = buildAnalyticsSourceReport(input.profile, input.options)
    input.profile.visits.push(visit('repeat', 'b-0', { visitedAt: '2026-09-01', rating: 5 }))
    const after = buildAnalyticsSourceReport(input.profile, input.options)
    expect(after.overallSourceRating).toBe(before.overallSourceRating)
    expect(after.pitfallRanking[0].lowRatingCount).toBe(5)
    expect(after.pitfallRanking[0].restaurants.find(item => item.id === 'b-0')).toMatchObject({ scoreOutOfTen: 4, repeatAverage: 10 })
    input.profile.visits.find(item => item.restaurantId === 'b-0' && item.id !== 'repeat')!.rating = null
    expect(buildAnalyticsSourceReport(input.profile, input.options).worstSourceID).toBeNull()
  })
  it('never awards a pitfall winner with no relative failures, or to self discovery', () => {
    const input = sourceInput(5, 5)
    for (const item of input.profile.visits) item.rating = 2
    expect(buildAnalyticsSourceReport(input.profile, input.options).worstSourceID).toBeNull()
    input.options.sources[1].sourceType = 'self'
    input.profile.visits.filter(item => item.restaurantId.startsWith('a')).forEach(item => { item.rating = 5 })
    expect(buildAnalyticsSourceReport(input.profile, input.options).worstSourceID).toBeNull()
  })
})
