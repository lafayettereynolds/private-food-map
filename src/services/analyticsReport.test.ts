import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import type { TasteMapProfileDashboardDTO, TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { projectBridgeProfile } from '../platform/TasteMapBridgeProjection'
import { buildAnalyticsReport } from './analyticsReport'
import { analyticsDataset } from './analyticsReportData'
import { analyticsCuisineRanking, buildAnalyticsTasteReport } from './analyticsTasteReport'
import { buildAnalyticsPeriodReport } from './analyticsPeriodReport'
import { analyticsReportHome, analyticsDetailTopics } from './analyticsReportHome'

const now = new Date('2026-09-06T12:00:00')
const restaurants = [restaurant('r1', '常去小馆', '杭州市', ['中餐']), restaurant('r2', '一次高分', '杭州', ['日料']), restaurant('r3', '咖啡店', '上海', ['咖啡'])]

describe('shared report entry point', () => {
  it('separates most recorded cuisine from higher-rated cuisine without substituting frequency for liking', () => {
    const input = profile([...Array.from({ length: 10 }, (_, i) => visit('a' + i, `chinese${i % 5}`, undefined, 3)), ...Array.from({ length: 5 }, (_, i) => visit('b' + i, `japanese${i}`, undefined, 4.5))])
    input.restaurants = Array.from({ length: 5 }, (_, i) => restaurant(`chinese${i}`, `中餐${i}`, '杭州', ['中餐'])).concat(Array.from({ length: 5 }, (_, i) => restaurant(`japanese${i}`, `日料${i}`, '杭州', ['日料'])))
    const report = buildAnalyticsReport(input, { mode: 'taste', now })
    const home = analyticsReportHome(report)
    expect(home.frequent[0].label).toBe('中餐')
    expect(home.highlyRated[0].label).toBe('日料')
    expect(home.headline).toContain('却给日料更高')
    expect(home.habits.length).toBeLessThanOrEqual(4)
    const topics = analyticsDetailTopics(report.sections)
    expect(topics.flatMap(topic => topic.sections.map(section => section.id)).sort()).toEqual(report.sections.map(section => section.id).sort())
  })
  it('keeps solo/together conflicts out of both groups and retains original records', () => {
    const conflict = { ...visit('conflict', 'r1', undefined, 4), companions: ['小林'], companionIds: ['c'], diningOccasions: ['solo' as const] }
    const input = profile([conflict, { ...visit('solo', 'r1', undefined, 3), diningOccasions: ['solo'] }, { ...visit('with', 'r1', undefined, 5), companions: ['小林'] }])
    const report = buildAnalyticsReport(input, { mode: 'taste', now })
    expect(report.taste?.companionImpact).toMatchObject({ withCount: 1, soloCount: 1, withAverage: 10, soloAverage: 6 })
    expect(report.taste?.snapshot.companions.find(item => item.label === '场景冲突待确认')?.value).toBe(33)
    expect(report.summary.visitCount).toBe(3)
    expect(input.visits[0]).toEqual(conflict)
  })
  it('monthly repeat counts are Visits, not repeated Restaurant counts', () => {
    const input = profile([visit('old', 'r1', '2026-08-01'), visit('repeat1', 'r1'), visit('repeat2', 'r1'), visit('new1', 'r2'), visit('repeat3', 'r2')])
    const report = buildAnalyticsReport(input, { mode: 'monthly', year: 2026, month: 9, now })
    expect(analyticsReportHome(report).facts).toEqual([{ label: '用餐记录', value: '4' }, { label: '不同餐厅', value: '2' }, { label: '首次记录餐厅', value: '1' }, { label: '回访次数', value: '3' }])
  })
  it('annual cover reports actual month coverage, and empty reports invent no facts', () => {
    const report = buildAnalyticsReport(profile([visit('first', 'r1', '2026-02-01'), visit('last', 'r1', '2026-08-01')]), { mode: 'annual', year: 2026, now })
    expect(analyticsReportHome(report).subtitle).toContain('记录覆盖 2 个月（2—8 月）')
    expect(analyticsReportHome(report).facts.map(item => item.label)).toEqual(['用餐记录', '不同餐厅', '城市', '首次记录餐厅'])
    expect(analyticsReportHome(buildAnalyticsReport(profile([]), { mode: 'monthly', now })).facts).toEqual([])
  })
  it('keeps date-only meals in totals but excludes them from both data and poster time percentages', () => {
    const report = buildAnalyticsReport(profile([visit('date-only', 'r1', '2026-09-01'), visit('lunch', 'r2', '2026-09-02T12:00:00')]), { mode: 'taste', now })
    expect(report.summary.visitCount).toBe(2)
    expect(report.taste?.snapshot.diningTimes.find(item => item.label === '午餐')?.value).toBe(100)
    expect(report.taste?.snapshot.diningTimes.find(item => item.label === '夜宵')?.value).toBe(0)
    const section = report.sections.find(item => item.id === 'dining-times')!
    expect(section.description).toBe(report.taste?.snapshot.diningTimeNote)
    expect(section.description).toContain('1/2')
    expect(section.rows?.find(item => item.label === '午餐')?.value).toBe('1 次 · 100%')
    const untimed = buildAnalyticsReport(profile([visit('date-only', 'r1', '2026-09-01')]), { mode: 'taste', now })
    expect(untimed.taste?.snapshot.diningTimes).toEqual([])
    expect(untimed.sections.find(item => item.id === 'dining-times')?.rows).toEqual([])
  })
  it.each(['taste', 'companion', 'source', 'monthly', 'annual'] as const)('shows an honestly empty %s report after known deletions, not a data-load failure', mode => {
    const live = visit('deleted', 'r1')
    const tombstone = { ...live, deletedAt: '2026-09-02', updatedAt: '2026-09-02' }
    const report = buildAnalyticsReport(profile([live, tombstone]), { mode, now })
    expect(report.dataState).toBe('empty')
    expect(report.summary).toMatchObject({ visitCount: 0, ratedVisitCount: 0, averageScoreOutOfTen: null })
    expect(report.dataNote).not.toContain('缺少可核验归属')
  })
  it('invalidates a poster snapshot when corrected fields change without legacy updatedAt being bumped', () => {
    const input = profile([visit('actual', 'r1', undefined, 4)])
    const first = buildAnalyticsReport(input, { mode: 'taste', now })
    input.visits[0].rating = 5
    const score = buildAnalyticsReport(input, { mode: 'taste', now })
    expect(score.id).not.toBe(first.id)
    expect(score.summary.averageScoreOutOfTen).toBe(10)
    input.visits[0].photos = ['data:image/png;base64,REAL']
    const photo = buildAnalyticsReport(input, { mode: 'taste', now })
    expect(photo.id).not.toBe(score.id)
  })
  it('uses the same snapshot clock to exclude future visits from monthly and all-time facts', () => {
    const input = profile([visit('actual', 'r1', '2026-09-05T12:00:00'), visit('future', 'r2', '2026-09-28T12:00:00')])
    const monthly = buildAnalyticsReport(input, { mode: 'monthly', now })
    expect(monthly.summary.visitCount).toBe(1)
    expect(monthly.period?.visits.map((item) => item.id)).toEqual(['actual'])
    expect(monthly.excludedVisitCount).toBe(1)
    expect(buildAnalyticsReport(input, { mode: 'taste', now }).summary.visitCount).toBe(1)
    expect(input.visits).toHaveLength(2)
  })
  it('carries actual Native bridge owner identity into the same non-empty report', () => {
    const dto: TasteMapProfileDashboardDTO = {
      user: { id: 'tm-native-owner', nickname: '真实所有者', bio: '', city: '杭州', avatarPhotoId: null, avatarPresetId: 'polar-bear', membershipTier: 'free', mapSharingEnabled: false, mapVisibility: 'private', createdAt: '', updatedAt: '' },
      restaurants: [{ ...restaurants[0], phone: null, openingHours: null, referencePrice: 50, image: { kind: 'foodDiningFallback', stableSeed: 'r1', accessibilityLabel: '餐厅' }, visits: [{ ...visit('native', 'r1', undefined, 4), dishes: [], photos: [] }] }],
      followerCount: 0, followingCount: 0,
      analyticsIdentity: { ownerUserID: 'tm-native-owner', recordOwnerID: 'tm-native-owner', companions: [], sources: [], visitSourceLinks: [{ visitID: 'native', sourceID: null }] },
    }
    const projected = projectBridgeProfile(dto)
    expect(projected.visits[0].userId).toBe('owner')
    const result = buildAnalyticsReport(projected, { mode: 'taste', now })
    expect(result.scope.ownerID).toBe('tm-native-owner')
    expect(result.summary).toMatchObject({ visitCount: 1, restaurantCount: 1, averageScoreOutOfTen: 8 })
    expect(result.taste?.snapshot.visitCount).toBe(result.summary.visitCount)
    expect(result.dataState).toBe('ready')
    expect(result.sections).toBeDefined()
  })
  it('does not call unproven legacy owner records a first-use empty account', () => {
    const input = profile([visit('a', 'r1')]); input.user.id = 'tm-different-owner'
    const result = buildAnalyticsReport(input, { mode: 'taste', now })
    expect(result.dataState).toBe('unavailable')
    expect(result.headline).not.toContain('第一')
    expect(result.dataNote).toContain('不是从未记录过')
  })
  it('preserves current-month name and changes only a selected historical month', () => {
    expect(buildAnalyticsReport(profile([]), { mode: 'monthly', now }).title).toBe('本月回顾')
    expect(buildAnalyticsReport(profile([]), { mode: 'monthly', now, year: 2025, month: 8 }).title).toBe('月度回顾')
  })
  it('scopes selection and directory changes into report identity without reusing an old poster key', () => {
    const input = profile([visit('a', 'r1')])
    input.analyticsIdentity = { ownerUserID: 'owner', recordOwnerID: 'owner', companions: [{ id: 'c1', ownerUserID: 'owner', displayName: '旧名', identifiers: ['c1'], updatedAt: '2026-09-01', deletedAt: null }], sources: [], visitSourceLinks: [] }
    const one = buildAnalyticsReport(input, { mode: 'companion', now, companionID: 'c1' })
    const two = buildAnalyticsReport(input, { mode: 'companion', now, companionID: 'c2' })
    expect(one.id).not.toBe(two.id)
    input.analyticsIdentity.companions![0].displayName = '新名'
    expect(buildAnalyticsReport(input, { mode: 'companion', now, companionID: 'c1' }).id).not.toBe(one.id)
  })
  it('passes only selected period visits into stable companion reports while retaining real history', () => {
    const input = profile([{ ...visit('old', 'r1', '2026-08-01T12:00:00'), companionIds: ['c'] }, { ...visit('current', 'r1'), companionIds: ['c'] }])
    input.analyticsIdentity = { ownerUserID: 'owner', recordOwnerID: 'owner', companions: [{ id: 'c', ownerUserID: 'owner', displayName: '饭搭子', identifiers: ['c'], updatedAt: '', deletedAt: null }], sources: [], visitSourceLinks: [] }
    const report = buildAnalyticsReport(input, { mode: 'monthly', now, year: 2026, month: 9 })
    expect(report.summary.visitCount).toBe(1)
    expect(report.companion?.summary.visitCount).toBe(1)
    expect(report.sections.some((section) => section.id.startsWith('period-companion-'))).toBe(true)
    expect(report.period?.review.newRestaurantCount).toBe(0)
  })
})

describe('device time-zone period evidence', () => {
  beforeAll(() => vi.stubEnv('TZ', 'Asia/Shanghai'))
  afterAll(() => vi.unstubAllEnvs())
  it('places 08-31 16:30 UTC in September and labels the same Visit September 1', () => {
    const input = profile([visit('boundary', 'r1', '2026-08-31T16:30:00Z', 4)])
    const report = buildAnalyticsReport(input, { mode: 'monthly', now: new Date('2026-09-06T12:00:00Z'), year: 2026, month: 9 })
    expect(report.summary.visitCount).toBe(1)
    expect(report.scope.timeZone).toBe('Asia/Shanghai')
    expect(report.sections.find((section) => section.id === 'period-key-restaurants')?.rows?.[0].value).toBe('2026-09-01')
    expect(report.sections.find((section) => section.id === 'period-memories')?.rows?.[0].value).toBe('2026-09-01')
    expect(buildAnalyticsReport(input, { mode: 'monthly', now: new Date('2026-09-06T12:00:00Z'), year: 2026, month: 8 }).summary.visitCount).toBe(0)
  })
})

describe('owner-scoped analytics dataset', () => {
  it('orders record revisions by instant, not offset text, and gives equal-time tombstones priority', () => {
    const live = { ...visit('same', 'r1'), updatedAt: '2026-09-01T09:00:00+08:00' }
    const deleted = { ...live, updatedAt: '2026-09-01T02:00:00Z', deletedAt: '2026-09-01T02:00:00Z' }
    expect(analyticsDataset(profile([live, deleted])).visits).toEqual([])
    expect(analyticsDataset(profile([deleted, live])).visits).toEqual([])
    const tie = { ...deleted, updatedAt: '2026-09-01T01:00:00Z' }
    expect(analyticsDataset(profile([tie, live])).visits).toEqual([])
  })
  it('normalizes invalid dish scores independently without removing valid unscored dining evidence', () => {
    const input = profile([{ ...visit('dish', 'r1'), dishes: [0, 6, 4].map((rating, index) => ({ id: String(index), name: `菜${index}`, taste: '', rating: rating as Visit['rating'], price: null, imageData: null, photoId: null })) }])
    const report = buildAnalyticsReport(input, { mode: 'taste', now })
    expect(report.taste?.dishes.map(item => item.scoreOutOfTen).sort()).toEqual([8, null, null])
    expect(report.summary).toMatchObject({ visitCount: 1, ratedVisitCount: 0 })
  })
  it('excludes other owners, deleted/orphan/invalid visits and unvisited restaurant counters', () => {
    const input = profile([visit('good', 'r1'), { ...visit('other', 'r1'), userId: 'other' }, { ...visit('deleted', 'r1'), deletedAt: '2026-09-02' }, visit('orphan', 'missing'), { ...visit('invalid', 'r1'), visitedAt: 'not a date' }])
    const result = analyticsDataset(input)
    expect(result.visits.map((item) => item.id)).toEqual(['good'])
    expect(result.excludedVisitCount).toBe(4)
    const report = buildAnalyticsTasteReport(result.restaurants, result.visits, now)
    expect(report.summary.restaurantCount).toBe(1)
    expect(report.topRestaurants[0].count).toBe(1)
  })
  it('requires a matching adapter owner proof for presentation sentinels', () => {
    const input = profile([visit('good', 'r1')])
    input.user = { ...input.user, id: 'tm-real-owner' }
    expect(analyticsDataset(input).visits).toEqual([])
    input.analyticsIdentity = { ownerUserID: 'different-owner', recordOwnerID: 'owner', companions: null, sources: null, visitSourceLinks: null }
    expect(analyticsDataset(input).visits).toEqual([])
    input.analyticsIdentity.ownerUserID = 'tm-real-owner'
    const accepted = analyticsDataset(input)
    expect(accepted.visits[0].userId).toBe('tm-real-owner')
    expect(accepted.restaurants[0].userId).toBe('tm-real-owner')
    expect(input.visits[0].userId).toBe('owner')
  })
  it('deduplicates before tombstone filtering and never resurrects stale rows', () => {
    const older = visit('duplicate', 'r1')
    const newer = { ...older, updatedAt: '2026-09-04', deletedAt: '2026-09-04' }
    expect(analyticsDataset(profile([older, newer])).visits).toEqual([])
    expect(analyticsDataset(profile([newer, older])).visits).toEqual([])
    expect(analyticsDataset(profile([older, { ...older, deletedAt: '2026-09-04' }])).visits).toEqual([])
    const input = profile([older])
    input.restaurants.push({ ...restaurants[0], deletedAt: '2026-09-05', updatedAt: '2026-09-05' })
    expect(analyticsDataset(input).visits).toEqual([])
  })
})

describe('fused Taste Profile report', () => {
  it('keeps frequency and highest score distinct and counts only real period visits', () => {
    const report = buildAnalyticsTasteReport(restaurants, [visit('a', 'r1', undefined, 3), visit('b', 'r1', undefined, 3), visit('c', 'r2', undefined, 5)], now)
    expect(report.topRestaurants.map((item) => item.restaurantID)).toEqual(['r1', 'r2'])
    expect(report.topRestaurants[0]).toMatchObject({ count: 2, scoreOutOfTen: 6 })
    expect(report.repeat).toMatchObject({ repeatedRestaurantCount: 1, visitedRestaurantCount: 2, rate: 0.5 })
    expect(report.summary.cityCount).toBe(1)
  })
  it('uses Native cuisine reliability/recency without fabricating unrated scores', () => {
    const report = analyticsCuisineRanking(restaurants, [visit('a', 'r1'), visit('b', 'r1'), visit('c', 'r2', undefined, 5)], now)
    const unrated = report.find((item) => item.label === '中餐')!
    expect(unrated.averageScoreOutOfTen).toBeNull()
    expect(unrated.ratedVisitCount).toBe(0)
    expect(unrated.visitCount).toBe(2)
    expect(unrated.score).toBeCloseTo(Math.log2(3) * 1.15 + 0.75 + 0.2 + 0.45)
    expect(report.find((item) => item.label === '日料')!.score).toBeCloseTo((10 * 0.48 + 3) / 3 + 1.15 + 0.2 + 0.45)
  })
  it('deduplicates tags per visit and excludes environment or occasion tags', () => {
    const report = analyticsCuisineRanking([{ ...restaurants[0], tags: ['中餐', '中餐', '约会', '环境舒适'] }], [visit('a', 'r1')], now)
    expect(report).toHaveLength(1)
    expect(report[0]).toMatchObject({ label: '中餐', visitCount: 1, share: 1 })
  })
  it('calculates category shares from actual money, not meal counts', () => {
    const visits = [visit('meal', 'r1', undefined, null, 1000), ...Array.from({ length: 10 }, (_, index) => visit(`coffee-${index}`, 'r3', undefined, null, 10))]
    const report = buildAnalyticsTasteReport(restaurants, visits, now)
    expect(report.summary.spend.total).toBe(1100)
    expect(report.spendCategories.find((item) => item.label === '正餐')).toMatchObject({ amount: 1000, count: 1 })
    expect(report.spendCategories.find((item) => item.label === '正餐')!.share).toBeCloseTo(10 / 11)
    expect(report.snapshot.spendCategories.find((item) => item.label === '正餐')!.value).toBeCloseTo(1000 / 11)
  })
  it('separates current reference price from AA, hosting and being treated amounts', () => {
    const visits = (['aa', 'my_treat', 'treated'] as const).map((paymentMode) => ({ ...visit(paymentMode, 'r1'), totalPrice: 200, partySize: 4, paymentMode, pricePerPerson: 999 }))
    const report = buildAnalyticsTasteReport(restaurants, visits, now)
    expect(report.summary.spend.total).toBe(250)
    expect(report.summary.spend.recordedVisitCount).toBe(3)
    expect(report.referenceDistribution.find((item) => item.minimum === 50)?.count).toBe(3)
    expect(report.referenceDistribution.find((item) => item.minimum === 800)?.count).toBe(0)
  })
  it('allows separate payment as a personal reference without inventing a table total', () => {
    const report = buildAnalyticsTasteReport(restaurants, [{ ...visit('separate', 'r1', undefined, null, 80), totalPrice: null, paymentMode: 'separate', partySize: 6 }], now)
    expect(report.summary.spend.total).toBe(80)
    expect(report.referenceDistribution.find((item) => item.minimum === 50)?.count).toBe(1)
  })
  it('distinguishes no amount from a legitimate zero payment and avoids fake category shares', () => {
    const empty = buildAnalyticsTasteReport(restaurants, [visit('unknown', 'r1')], now)
    expect(empty.summary.spend).toMatchObject({ total: 0, recordedVisitCount: 0, display: 'hidden', median: null })
    expect(empty.snapshot.spendCategories).toEqual([])
    const zero = buildAnalyticsTasteReport(restaurants, [{ ...visit('guest', 'r1'), paymentMode: 'treated' }], now)
    expect(zero.summary.spend).toMatchObject({ total: 0, recordedVisitCount: 1, display: 'total', median: 0 })
    expect(zero.snapshot.spendCategories).toEqual([])
  })
  it('does not substitute cuisine for unrecorded dish tastes or make low-sample stable claims', () => {
    const report = buildAnalyticsTasteReport(restaurants, [visit('a', 'r1')], now)
    expect(report.snapshot.preferences).toEqual([])
    expect(report.headline).toBe('口味档案正在形成')
    expect(report.recentComparison.available).toBe(false)
    expect(report.sections.find((item) => item.id === 'recent-history')?.confidence).toBe('insufficient')
  })
  it('preserves all historical dimensions and explicit sample/price provenance', () => {
    const report = buildAnalyticsTasteReport(restaurants, [], now)
    expect(report.sections.map((item) => item.id)).toEqual(['cuisines', 'dish-tastes', 'dishes', 'top-restaurants', 'personal-spend', 'personal-spend-distribution', 'reference-price', 'repeat', 'high-traits', 'pitfalls', 'hidden-preferences', 'scenes', 'ratings', 'companion-context', 'source-context', 'recent-history', 'dining-times', 'cities', 'restaurant-roles'])
    expect(report.summary.averageScoreOutOfTen).toBeNull()
    expect(report.headline).toBe('从第一条真实到访开始')
    expect(report.sections.find((item) => item.id === 'reference-price')?.privacy).toBe('spend')
  })
})

describe('fused monthly / annual reports', () => {
  it('accepts a selected historical month, uses half-open bounds and never leaks all-time scores', () => {
    const visits = [visit('before', 'r1', '2026-07-31T23:59:59', 5), visit('a', 'r1', '2026-08-01T00:00:00', 2), visit('b', 'r1', '2026-08-31T23:59:59', 3), visit('after', 'r2', '2026-09-01T00:00:00', 5)]
    const report = buildAnalyticsPeriodReport(restaurants, visits, 'monthly', 2026, 8)
    expect(report.summary).toMatchObject({ visitCount: 2, restaurantCount: 1, averageScoreOutOfTen: 5 })
    expect(report.topRestaurants[0]).toMatchObject({ restaurantID: 'r1', count: 2, scoreOutOfTen: 5 })
    expect(report.review).toMatchObject({ newRestaurantCount: 0, revisitCount: 1 })
    expect(report.periodLabel).toBe('2026 年 8 月')
  })
  it('crosses a year boundary for previous-month comparison and retains full-period statistics', () => {
    const visits = [visit('a', 'r1', '2025-12-05T12:00:00', 4, 20), visit('b', 'r2', '2025-12-06T12:00:00', 4, 30), visit('c', 'r1', '2026-01-01T12:00:00', 4, 50), visit('d', 'r3', '2026-01-02T12:00:00', 4, 60), visit('e', 'r3', '2026-01-03T12:00:00', 4, 70)]
    const report = buildAnalyticsPeriodReport(restaurants, visits, 'monthly', 2026, 1)
    expect(report.previousLabel).toBe('2025 年 12 月')
    expect(report.review.comparison).toEqual({ visitDelta: 1, restaurantDelta: 0, spendDelta: 130 })
    expect(report.comparison.spendAvailability).toBe('available')
    expect(report.comparison.spendCurrency).toBe('CNY')
    expect(report.review.newRestaurantCount).toBe(1)
  })
  it('requires sufficient coverage before comparing spend and keeps nil distinct from zero', () => {
    const visits = [visit('a', 'r1', '2026-07-05T12:00:00', 4, 20), visit('b', 'r2', '2026-07-06T12:00:00', 4), visit('c', 'r1', '2026-08-01T12:00:00', 4, 50), visit('d', 'r3', '2026-08-02T12:00:00', 4, 60)]
    expect(buildAnalyticsPeriodReport(restaurants, visits, 'monthly', 2026, 8).review.comparison?.spendDelta).toBeNull()
  })
  it('does not fabricate trend, memories or representatives for an empty selected period', () => {
    const report = buildAnalyticsPeriodReport(restaurants, [visit('outside', 'r1', '2025-08-01T12:00:00', 5)], 'monthly', 2026, 8)
    expect(report.summary.visitCount).toBe(0)
    expect(report.topRestaurants).toEqual([])
    expect(report.review.favorite).toBeNull()
    expect(report.review.comparison).toBeNull()
    expect(report.review.tasteChanges).toEqual([])
  })
  it('preserves twelve months and uses actual new/repeat counts per month', () => {
    const visits = [visit('old', 'r1', '2025-12-01T12:00:00'), visit('january', 'r1', '2026-01-05T12:00:00'), visit('august', 'r2', '2026-08-01T12:00:00')]
    const report = buildAnalyticsPeriodReport(restaurants, visits, 'annual', 2026, 1)
    expect(report.monthlySnapshots).toHaveLength(12)
    expect(report.monthlySnapshots[0]).toMatchObject({ visitCount: 1, newRestaurantCount: 0, repeatRestaurantCount: 1 })
    expect(report.monthlySnapshots[1]).toMatchObject({ visitCount: 0, dominantCuisine: null, representative: null })
    expect(report.monthlySnapshots[7]).toMatchObject({ visitCount: 1, newRestaurantCount: 1 })
    expect(report.journeyGranularity).toBe('insufficient')
    expect(report.halfYearComparison?.available).toBe(false)
  })
  it('uses Native yearly journey sample gates and separate half-year evidence', () => {
    const visits = [1, 3, 7, 9].flatMap((month) => Array.from({ length: 3 }, (_, index) => visit(`${month}-${index}`, index % 2 ? 'r1' : month < 7 ? 'r2' : 'r3', `2026-${String(month).padStart(2, '0')}-0${index + 1}T12:00:00`)))
    const report = buildAnalyticsPeriodReport(restaurants, visits, 'annual', 2026, 1)
    expect(report.journeyGranularity).toBe('monthly')
    expect(report.journey).toHaveLength(4)
    expect(report.halfYearComparison?.available).toBe(false) // Six Visits / two Restaurants do not support a frequency comparison.
    expect(report.halfYearComparison?.changes).toEqual([])
  })
  it('retains concrete new restaurants and sample-gated rating/spend month highlights', () => {
    const visits = [visit('old', 'r1', '2025-08-01T12:00:00', 5), visit('j1', 'r1', '2026-01-01T12:00:00', 4, 100), visit('j2', 'r2', '2026-01-02T12:00:00', 4, 200), visit('s1', 'r3', '2026-09-01T12:00:00', 5)]
    const report = buildAnalyticsPeriodReport(restaurants, visits, 'annual', 2026, 1)
    expect(report.newRestaurants.map((item) => item.restaurantID).sort()).toEqual(['r2', 'r3'])
    expect(report.monthlyHighlights.find((item) => item.id === 'rating')?.value).toBe('1 月 · 8.0 / 10')
    expect(report.monthlyHighlights.find((item) => item.id === 'spend')).toMatchObject({ value: '1 月 · ¥300', privacy: 'spend' })
  })
  it('keeps legacy name/type winner claims out of the fused period report', () => {
    const report = buildAnalyticsPeriodReport(restaurants, [{ ...visit('a', 'r1'), companions: ['同名'], recommendationSourceType: 'friend', recommendationSourceText: '同名' }], 'monthly', 2026, 9)
    expect(report.review.companionInsight).toBeNull()
    expect(report.review.sourceInsight).toBeNull()
    expect(report.review.companions).toEqual([])
    expect(report.review.recommendationSources).toEqual([])
  })
  it('rejects invalid selection rather than silently rolling the report into another year', () => {
    expect(() => buildAnalyticsPeriodReport(restaurants, [], 'monthly', 2026, 13)).toThrow('分析周期无效')
  })
})

function restaurant(id: string, name: string, city: string, tags: string[]): RestaurantSummary {
  return { id, userId: 'owner', amapPoiId: id, name, address: `${city}测试地址`, city, latitude: 30, longitude: 120, status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags, longTermNote: '', pricePerPerson: null, phone: null, openingHours: null, markerType: 'image', markerImageData: null, markerPhotoId: null, merchantImageUrl: null, markerEmoji: '', createdAt: '2025-01-01', updatedAt: '2026-09-01', deletedAt: null, visitCount: 999, averageRating: 5, scoreOutOfTen: 10, latestVisitDate: null, latestVisit: null, visits: [], averagePricePerPerson: null, averageQueueMinutes: null }
}
function visit(id: string, restaurantId: string, visitedAt = '2026-09-01T12:00:00', rating: Visit['rating'] = null, myActualSpend: number | null = null): Visit {
  return { id, userId: 'owner', restaurantId, visitedAt, rating, visibility: 'private', diningMode: 'dine_in', totalPrice: null, myActualSpend, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null, diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [], dishes: [], note: '', photos: [], photoIds: [], createdAt: visitedAt, updatedAt: '2026-09-01', deletedAt: null }
}
function profile(visits: Visit[]): TasteMapProfileDashboardViewModel {
  return { user: { id: 'owner', nickname: '分析用户', city: '' } as UserProfile, restaurants: [...restaurants], visits, followerCount: 0, followingCount: 0, restaurantImages: {} }
}
