import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary, Visit, UserProfile } from '../types/domain'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { analyticsComparableWindow, analyticsRepresentativeRatings } from './analyticsEvidenceRules'
import { analyticsCuisineRanking, buildAnalyticsTasteReport } from './analyticsTasteReport'
import { buildAnalyticsPeriodReport } from './analyticsPeriodReport'
import { buildAnalyticsSourceReport } from './analyticsSocialReport'
const now = new Date('2026-09-06T12:00:00Z')
const restaurant = (id: string, tags = ['日料']): RestaurantSummary => ({ ...fixture.restaurants[0] as unknown as RestaurantSummary, id, userId: 'owner', tags, status: 'visited', deletedAt: null })
const visit = (id: string, restaurantId: string, visitedAt: string, rating: Visit['rating'] = 4): Visit => ({ ...fixture.restaurants[0].visits[0] as unknown as Visit, id, restaurantId, userId: 'owner', visitedAt, rating, dishes: [], companions: [], companionIds: [], diningOccasions: [], recommendationSourceType: null, recommendationSourceText: '', recommendationSourceUserId: null, deletedAt: null })

describe('analysis reference evidence rules', () => {
  it('averages each restaurant before comparing cuisines, without repeat-Visit domination', () => {
    const values = [...Array.from({ length: 9 }, (_, i) => visit(`${i}`, 'a', '2026-08-01', 5)), visit('b', 'b', '2026-08-01', 1)]
    expect(analyticsRepresentativeRatings(values).map(item => item.scoreOutOfTen)).toEqual([10, 2])
    expect(analyticsCuisineRanking([restaurant('a'), restaurant('b')], values, now)[0]).toMatchObject({ averageScoreOutOfTen: 6, ratedVisitCount: 10, ratedRestaurantCount: 2, highRatingShare: .5 })
  })
  it('uses exactly two adjacent 90-day windows and rejects repeated-one-store evidence', () => {
    const values = [visit('too-old', 'a', '2026-01-01'), ...Array.from({ length: 10 }, (_, i) => visit(`old${i}`, 'a', '2026-04-01')), ...Array.from({ length: 10 }, (_, i) => visit(`new${i}`, 'a', '2026-08-01'))]
    const result = buildAnalyticsTasteReport([restaurant('a')], values, now).recentComparison
    expect(result).toMatchObject({ currentVisitCount: 10, previousVisitCount: 10, currentRatedRestaurantCount: 1, previousRatedRestaurantCount: 1, available: false, changes: [] })
    expect(Date.parse(result.currentStart) - Date.parse(result.previousStart)).toBe(90 * 86400000)
  })
  it('requires ten different restaurants and thirty days for stronger single-cuisine evidence', () => {
    const restaurants = Array.from({ length: 10 }, (_, i) => restaurant(`r${i}`))
    const values = restaurants.map((item, i) => visit(`${i}`, item.id, '2026-08-01'))
    expect(analyticsCuisineRanking(restaurants, values, now)[0].confidence).toBe('emerging')
    values[0].visitedAt = '2026-06-01'
    expect(analyticsCuisineRanking(restaurants, values, now)[0].confidence).toBe('established')
    expect(analyticsCuisineRanking(restaurants, values.slice(0, 4), now)[0].confidence).toBe('insufficient')
  })
  it('keeps cuisine means factual without comparing two small groups', () => {
    const restaurants = [restaurant('a', ['日料']), restaurant('b', ['中餐'])]
    const values = Array.from({ length: 10 }, (_, i) => visit(`${i}`, i % 2 ? 'a' : 'b', '2026-08-01', i % 2 ? 5 : 2))
    const result = buildAnalyticsTasteReport(restaurants, values, now)
    expect(result.cuisines.map(item => item.averageScoreOutOfTen).sort((a, b) => a! - b!)).toEqual([4, 10])
    expect(result.highlyRated).toEqual([])
    expect(result.headline).not.toContain('更高')
  })
  it('admits 10 Visits / five restaurants for frequency and five restaurant scores for rating changes', () => {
    const restaurants = Array.from({ length: 10 }, (_, i) => restaurant(`r${i}`, [i < 5 ? '日料' : '中餐']))
    const values = Array.from({ length: 10 }, (_, i) => visit(`old${i}`, `r${i % 5}`, '2026-04-01', 3)).concat(Array.from({ length: 10 }, (_, i) => visit(`new${i}`, `r${5 + i % 5}`, '2026-08-01', 4)))
    const result = buildAnalyticsTasteReport(restaurants, values, now).recentComparison
    expect(result).toMatchObject({ frequencyAvailable: true, ratingAvailable: true, scoreDelta: 2 })
    expect(result.changes).toContain('餐厅平均评分提高 2.0 分')
    expect(result.frequencyChanges.find(item => item.label === '中餐')?.delta).toBe(1)
  })
  it('compares a current month only against the matching previous dates, while keeping its full actual total', () => {
    const values = [visit('sep', 'a', '2026-09-01'), visit('aug', 'a', '2026-08-01'), visit('late', 'b', '2026-08-30')]
    const result = buildAnalyticsPeriodReport([restaurant('a'), restaurant('b')], values, 'monthly', 2026, 9, now)
    expect(result.summary.visitCount).toBe(1)
    expect(result.comparison.previousSummary.visitCount).toBe(1)
    expect(result.comparison.statistics?.visitDelta).toBe(0)
    expect(result.periodLabel).toContain('截至 9 月 6 日')
    expect(result.wishlistRedemption).toMatchObject({ availability: 'historyUnavailable', redeemedRestaurantCount: null })
  })
  it('clips a longer current month to the previous month length for comparisons only', () => {
    const march = new Date(2026, 2, 31, 12)
    const bounds = analyticsComparableWindow('monthly', 2026, 3, march)
    expect(bounds.currentEnd).toEqual(new Date(2026, 2, 29))
    expect(bounds.previousEnd).toEqual(new Date(2026, 2, 1))
    const result = buildAnalyticsPeriodReport([restaurant('a')], [visit('late', 'a', '2026-03-30')], 'monthly', 2026, 3, march)
    expect(result.summary.visitCount).toBe(1)
    expect(result.comparison.currentSummary.visitCount).toBe(0)
  })
  it('requires eighty-percent coverage and applies the approved historical CNY policy', () => {
    const values = [0, 1, 2, 3, 4].flatMap(i => [visit(`now${i}`, 'a', '2026-09-01'), visit(`old${i}`, 'a', '2026-08-01')])
    for (const item of values) { item.totalPrice = null; item.myActualSpend = item.id.endsWith('4') ? null : 0; item.paymentMode = null }
    const result = buildAnalyticsPeriodReport([restaurant('a')], values, 'monthly', 2026, 9, now)
    expect(result.comparison.spendCoverageEligible).toBe(true)
    expect(result.comparison.spendAvailability).toBe('available')
    expect(result.comparison.spendCurrency).toBe('CNY')
    expect(result.comparison.statistics?.spendDelta).toBe(0)
    expect(result.summary.spend.total).toBe(0)
    values[0].myActualSpend = null
    expect(buildAnalyticsPeriodReport([restaurant('a')], values, 'monthly', 2026, 9, now).comparison.spendCoverageEligible).toBe(false)
  })
  it('labels incomplete years, excludes future visits and aligns prior-year comparison', () => {
    const values = [visit('now', 'a', '2026-08-01'), visit('future', 'a', '2026-12-01'), visit('previous', 'a', '2025-08-01'), visit('later', 'a', '2025-12-01')]
    const result = buildAnalyticsPeriodReport([restaurant('a')], values, 'annual', 2026, 1, now)
    expect(result.summary.visitCount).toBe(1)
    expect(result.comparison.previousSummary.visitCount).toBe(1)
    expect(result.monthlySnapshots[11].observationState).toBe('future')
    expect(result.periodLabel).toContain('截至')
  })
  it('only includes mature source acquisitions in 90-day repeat denominator', () => {
    const restaurants = ['repeat', 'late', 'pending'].map(id => restaurant(id))
    const visits = [visit('a', 'repeat', '2026-03-01'), visit('ar', 'repeat', '2026-03-20'), visit('b', 'late', '2026-03-01'), visit('br', 'late', '2026-07-01'), visit('c', 'pending', '2026-08-01')]
    const profile: TasteMapProfileDashboardViewModel = { user: { id: 'owner' } as UserProfile, restaurants, visits, followerCount: 0, followingCount: 0, restaurantImages: {} }
    const result = buildAnalyticsSourceReport(profile, { now, sources: [{ id: 's', ownerUserID: 'owner', displayName: '朋友', identifiers: ['s'], updatedAt: '', deletedAt: null, sourceType: 'friend' }], visitSourceLinks: ['a', 'b', 'c'].map(visitID => ({ visitID, sourceID: 's' })) })
    expect(result.sources[0]).toMatchObject({ repeatRestaurantCount: 2, repeatRestaurantRate: .5, repeatObservation: { observedRestaurantCount: 2, pendingRestaurantCount: 1, repeatedRestaurantCount: 1 } })
    const pending = buildAnalyticsSourceReport({ ...profile, restaurants: [restaurants[2]], visits: [visits[4]] }, { now, sources: [{ id: 's', ownerUserID: 'owner', displayName: '朋友', identifiers: ['s'], updatedAt: '', deletedAt: null, sourceType: 'friend' }], visitSourceLinks: [{ visitID: 'c', sourceID: 's' }] })
    expect(pending.sources[0].repeatRestaurantRate).toBeNull()
    expect(pending.sources[0].repeatObservation.observedRestaurantCount).toBe(0)
  })
})
