import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { AnalyticsSection } from './analyticsReportTypes'
import { buildAnalyticsTasteReport } from './analyticsTasteReport'
import { buildAnalyticsPeriodReport } from './analyticsPeriodReport'
import { buildAnalyticsCompanionReport, buildAnalyticsSourceReport } from './analyticsSocialReport'

const owner = 'copy-owner'
const now = new Date('2026-09-06T12:00:00Z')
const restaurants = Array.from({ length: 10 }, (_, index): RestaurantSummary => ({
  ...fixture.restaurants[0] as unknown as RestaurantSummary,
  id: `r${index}`, userId: owner, name: `餐厅${index}`, city: '杭州', status: 'visited',
  tags: ['日料'], deletedAt: null, updatedAt: '2026-09-01',
}))
const visits = restaurants.map((restaurant, index): Visit => ({
  ...fixture.restaurants[0].visits[0] as unknown as Visit,
  id: `v${index}`, userId: owner, restaurantId: restaurant.id, visitedAt: `2026-08-${String(index + 1).padStart(2, '0')}T12:00:00Z`,
  rating: index < 5 ? 4.5 : 2, valueRating: null, environmentRating: null, serviceRating: null,
  companionIds: ['pal'], companions: [], recommendationSourceType: 'friend', recommendationSourceText: index < 5 ? 'a' : 'b',
  recommendationSourceUserId: null, dishes: [], photos: [], photoIds: [], note: '',
  diningOccasions: [], diningMode: 'dine_in', totalPrice: null, myActualSpend: null, paymentMode: null, partySize: null,
  deletedAt: null, updatedAt: '2026-09-01',
}))
const directory = (id: string) => ({ id, displayName: id, ownerUserID: owner, identifiers: [id], updatedAt: '2026-09-01', deletedAt: null })
const profile = (items = visits): TasteMapProfileDashboardViewModel => ({
  user: { ...fixture.profile.user as unknown as UserProfile, id: owner, city: '杭州' },
  restaurants, visits: items, followerCount: 0, followingCount: 0, restaurantImages: {},
})
const sourceOptions = { now, sources: [directory('a'), directory('b')].map(item => ({ ...item, sourceType: 'friend' as const })),
  visitSourceLinks: visits.map((visit, index) => ({ visitID: visit.id, sourceID: index < 5 ? 'a' : 'b' })) }

/** Description is retained as structured report metadata but is no longer
 * printed by the product result view. Test the actual result-facing fields. */
function resultCopy(report: { headline: string; insights: string[]; sections: AnalyticsSection[] }) {
  return [report.headline, ...report.insights, ...report.sections.flatMap(section => [
    section.title, section.emptyMessage ?? '',
    ...(section.rows ?? []).flatMap(row => [row.label, row.detail ?? '', row.value ?? '']),
    ...(section.metrics ?? []).flatMap(metric => [metric.label, metric.value, metric.note ?? '']),
  ])].join('\n')
}

describe('analytics result copy, without implementation explanations', () => {
  it('keeps the five reports about actual meals instead of code or calculation machinery', () => {
    const reports = [
      buildAnalyticsTasteReport(restaurants, visits, now),
      buildAnalyticsCompanionReport(profile(), { now, companions: [directory('pal')] }),
      buildAnalyticsSourceReport(profile(), sourceOptions),
      buildAnalyticsPeriodReport(restaurants, visits, 'monthly', 2026, 8),
      buildAnalyticsPeriodReport(restaurants, visits, 'annual', 2026, 8),
    ]
    for (const report of reports) {
      expect(resultCopy(report)).not.toMatch(/历史 Web|稳定 ID|稳定身份|按 Visit|分母|阈值|无法唯一解析|正式来源目录|覆盖不足|样本修正|归因|共同到访证据|来源餐厅证据/)
    }
  })

  it('preserves all actual counts, rating results, privacy flags and ranking thresholds', () => {
    const taste = buildAnalyticsTasteReport(restaurants, visits, now)
    expect(taste.summary).toMatchObject({ visitCount: 10, restaurantCount: 10, averageScoreOutOfTen: 6.5 })
    expect(taste.sections.find(item => item.id === 'personal-spend')?.privacy).toBe('spend')
    const companion = buildAnalyticsCompanionReport(profile(), { now, companions: [directory('pal')] })
    expect(companion.companions[0]).toMatchObject({ sharedVisitCount: 10, restaurantCount: 10, ratedVisitCount: 10, ratingAverage: 6.5 })
    expect(companion.companions[0].sections.find(item => item.id === 'companion-evidence')?.title).toBe('一起吃过的日子')
    expect(companion.companions[0].sections.find(item => item.id === 'companion-evidence')?.privacy).toBe('companion')
    const source = buildAnalyticsSourceReport(profile(), sourceOptions)
    expect(source).toMatchObject({ bestSourceID: 'a', worstSourceID: 'b', overallSourceRating: 6.5, baselineRestaurantCount: 10 })
    expect(source.conclusions.find(item => item.id === 'worst')?.explanation).toContain('5 家体验不如平时')
    const insufficient = buildAnalyticsSourceReport(profile(visits.slice(0, 4)), sourceOptions)
    expect(insufficient.bestSourceID).toBeNull()
    expect(insufficient.worstSourceID).toBeNull()
    expect(insufficient.sources.find(item => item.id === 'a')?.ratedRestaurantCount).toBe(4)
  })

  it('keeps missing data distinct from accumulated records without fabricated trends', () => {
    const unavailable = buildAnalyticsCompanionReport(profile())
    expect(unavailable.identityAvailability).toBe('unavailable')
    expect(unavailable.insights[0]).toContain('暂未读到，请稍后重试')
    expect(buildAnalyticsSourceReport(profile()).insights[0]).toContain('暂未读到，请稍后重试')
    const one = buildAnalyticsTasteReport(restaurants, visits.slice(0, 1), now)
    expect(one.sections.find(item => item.id === 'recent-history')?.emptyMessage).toBe('近期和过去的记录还在积累。')
    const annual = buildAnalyticsPeriodReport(restaurants, [], 'annual', 2026, 8)
    expect(annual.sections.find(item => item.id === 'annual-half-comparison')?.emptyMessage).toBe('上下半年的记录还在积累。')
    expect(annual.halfYearComparison?.changes).toEqual([])
  })
})
