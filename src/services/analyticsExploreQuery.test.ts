import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { RestaurantSummary, Visit } from '../types/domain'
import { analyticsFilterVisits, analyticsMealTime, analyticsQueryRecords } from './analyticsExploreQuery'
import { buildAnalyticsReport } from './analyticsReport'

function data() {
  const owner = fixture.profile.user.id
  const restaurants = fixture.restaurants.slice(0, 2).map((item, index) => ({ ...item, id: `r${index}`, userId: owner, tags: [index ? '西餐' : '日料'], city: index ? '上海' : '杭州', deletedAt: null })) as unknown as RestaurantSummary[]
  const base = fixture.restaurants[0].visits[0]
  const visits = [
    { ...base, id: 'a', restaurantId: 'r0', visitedAt: '2026-08-01', rating: null, visibility: 'private', pricePerPerson: null, totalPrice: null, partySize: null, myActualSpend: null },
    { ...base, id: 'b', restaurantId: 'r0', visitedAt: '2026-08-02T12:00:00', rating: 4.5, visibility: 'public', totalPrice: 200, partySize: 2, paymentMode: 'aa', myActualSpend: 100 },
    { ...base, id: 'c', restaurantId: 'r1', visitedAt: '2026-02-01T19:00:00', rating: 3, visibility: 'friends', totalPrice: 300, partySize: 1, myActualSpend: 300 },
  ].map(item => ({ ...item, userId: owner, deletedAt: null, dishes: [], companions: [], companionIds: [] })) as Visit[]
  return { ...fixture.profile, user: { ...fixture.profile.user, id: owner }, restaurants, visits, restaurantImages: {} } as unknown as TasteMapProfileDashboardViewModel
}
describe('F01–F24 real record queries', () => {
  it('does not turn date-only records into night meals or unrated records into zero', () => {
    const { restaurants, visits } = data()
    expect(analyticsMealTime(visits[0])).toBeNull()
    expect(analyticsQueryRecords(restaurants, visits, { label: '夜宵', time: '夜宵' })).toEqual([])
    expect(analyticsQueryRecords(restaurants, visits, { label: '低分', score: { minimum: 0, maximum: 7 } }).map(item => item.id)).toEqual(['c'])
  })
  it('intersects cuisine/time/price on the same Visit and preserves input', () => {
    const { restaurants, visits } = data(), original = JSON.stringify(visits)
    expect(analyticsQueryRecords(restaurants, visits, { label: '午餐日料', cuisine: '日料', time: '午餐', price: { minimum: 100, maximum: 200 } }).map(item => item.id)).toEqual(['b'])
    expect(analyticsQueryRecords(restaurants, visits, { label: '晚餐日料', cuisine: '日料', time: '晚餐' })).toEqual([])
    expect(JSON.stringify(visits)).toBe(original)
  })
  it('uses half-open price buckets and exact upstream IDs', () => {
    const { restaurants, visits } = data()
    expect(analyticsQueryRecords(restaurants, visits, { label: '<100', price: { minimum: 0, maximum: 100 } })).toEqual([])
    expect(analyticsQueryRecords(restaurants, visits, { label: 'empty source', visitIDs: [] })).toEqual([])
    expect(analyticsQueryRecords(restaurants, visits, { label: 'source', visitIDs: ['b'] }).map(item => item.id)).toEqual(['b'])
  })
  it('filters report and export from the same scope but excludes nonpublic records before share calculation', () => {
    const profile = data(), now = new Date('2026-09-07T12:00:00')
    const owner = buildAnalyticsReport(profile, { mode: 'taste', now })
    const safe = buildAnalyticsReport(profile, { mode: 'taste', now, excludePrivate: true })
    expect(owner.summary.visitCount).toBe(3)
    expect(safe.summary.visitCount).toBe(1)
    expect(safe.recordEvidence.map(item => item.id)).toEqual(['b'])
    expect(safe.taste?.frequent.map(item => item.label)).toEqual(['日料'])
    expect(owner.id).not.toBe(safe.id)
    expect(analyticsFilterVisits(profile.restaurants, profile.visits, { days: 90, city: '杭州市' }, now).map(item => item.id)).toEqual(['a', 'b'])
  })
})
