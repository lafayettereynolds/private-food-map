import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { buildAnalyticsReport } from './analyticsReport'
import { analyticsReportOwnerPosterData, analyticsReportShareData, analyticsReportShareText } from './analyticsReportShare'
import { renderAnalysisPosterSvg } from './analysisPosterRenderer'
import { analyticsResultHighlights } from './analyticsReportHighlights'

function profile(): TasteMapProfileDashboardViewModel {
  const owner = fixture.profile.user.id
  const restaurants = fixture.restaurants.map(item => ({ ...item, userId: owner })) as unknown as RestaurantSummary[]
  const visits = restaurants.flatMap(item => item.visits).map((item, index) => ({ ...item, userId: owner, visitedAt: `2026-09-0${index + 1}T12:00:00`, myActualSpend: 137, note: '绝不分享的私人笔记', companions: ['秘密同行姓名'], companionIds: ['c1'] })) as Visit[]
  return { user: fixture.profile.user as unknown as UserProfile, restaurants, visits, restaurantImages: {}, followingCount: 0, followerCount: 0,
    analyticsIdentity: { ownerUserID: owner, recordOwnerID: owner, companions: [{ id: 'c1', ownerUserID: owner, displayName: '秘密同行姓名', identifiers: ['c1'], updatedAt: '', deletedAt: null }], sources: [], visitSourceLinks: visits.map(item => ({ visitID: item.id, sourceID: null })) } }
}
const now = new Date('2026-09-06T12:00:00')
describe('analytics shared report privacy and evidence', () => {
  it('keeps a complete owner preview separate from the default safe export without modifying the report', () => {
    const input = profile(); const report = buildAnalyticsReport(input, { mode: 'taste', now })
    const before = structuredClone(report)
    const owner = analyticsReportOwnerPosterData(report, input)
    const shared = analyticsReportShareData(report, input)
    expect(owner.tasteProfile).toEqual(report.taste?.snapshot)
    const editorial = renderAnalysisPosterSvg({ data: owner, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(editorial).toContain('viewBox="0 0 1080 1620"')
    for (const title of ['数据总览', '口味偏好', '消费分布', '人均消费区间', '城市足迹 TOP 5', '用餐时间偏好']) expect(editorial).toContain(title)
    expect(editorial).not.toContain('viewBox="0 0 1080 1920"')
    expect(owner.tasteProfile?.spend).toBe(report.summary.spend.total)
    expect(owner.tasteProfile?.priceRanges.length).toBeGreaterThan(0)
    expect(shared.tasteProfile?.spend).toBeNull()
    expect(shared.tasteProfile?.priceRanges).toEqual([])
    expect(shared.tasteProfile?.companions).toEqual([])
    expect(shared.privacy.spendIncluded).toBe(false)
    expect(report).toEqual(before)
  })
  it.each(['taste', 'companion', 'source', 'monthly', 'annual'] as const)('projects %s poster findings from the data report priority, never from an independent insight list', mode => {
    const input = profile()
    input.analyticsIdentity!.sources = [{ id: 'source', displayName: '实际来源', ownerUserID: input.user.id, identifiers: ['source'], updatedAt: '', deletedAt: null, sourceType: 'blogger' }]
    input.analyticsIdentity!.visitSourceLinks = input.visits.map(visit => ({ visitID: visit.id, sourceID: 'source' }))
    const report = buildAnalyticsReport(input, { mode, now })
    const priorities = { taste: 'recent-history', companion: 'companion-foods', source: 'source-outcomes', monthly: 'period-taste-change', annual: 'annual-half-comparison' }
    report.sections = [{ id: priorities[mode], title: '同一份真实结果', confidence: 'established', rows: [{ id: 'fact', label: '实际餐厅', value: '3 次', detail: '真实记录说明', count: 3 }] }]
    report.insights = ['不应替代数据页的新说法']
    const highlights = analyticsResultHighlights(mode, report.sections)
    const data = analyticsReportShareData(report, input)
    expect(data.posterFindings?.map(item => item.sectionID)).toEqual(highlights.map(item => item.section.id))
    expect(data.posterFindings?.[0]?.text).toBe('实际餐厅 · 3 次；真实记录说明')
    expect(data.posterFindings).not.toContainEqual(expect.objectContaining({ text: '不应替代数据页的新说法' }))
    report.sections[0].privacy = 'spend'
    expect(analyticsReportShareData(report, input).posterFindings).toEqual([])
  })
  it('shares results without calculation sections or internal descriptions', () => {
    const input = profile(); const report = buildAnalyticsReport(input, { mode: 'taste', now })
    report.sections.unshift({ id: 'source-pitfall-method', title: '计算依据', rows: [{ id: 'internal', label: '内部基线' }] })
    report.sections.push({ id: 'result', title: '常去餐厅', description: '内部计算方法与分母', rows: [{ id: 'r', label: '真实餐厅结果' }] })
    const text = analyticsReportShareText(report, input)
    expect(text).toContain('真实餐厅结果')
    expect(text).not.toMatch(/计算依据|内部基线|内部计算方法/)
  })
  it('uses the report snapshot and its exact scoped restaurant evidence', () => {
    const input = profile(); const report = buildAnalyticsReport(input, { mode: 'taste', now }); const data = analyticsReportShareData(report, input)
    expect(data.tasteProfile?.visitCount).toBe(report.summary.visitCount)
    expect(data.tasteProfile?.averageScoreOutOfTen).toBe(report.summary.averageScoreOutOfTen)
    expect(data.restaurants.map(item => item.restaurantId)).toEqual(report.topRestaurants.map(item => item.restaurantID))
    expect(data.tasteProfile?.cuisines).toEqual(report.taste?.snapshot.cuisines)
    expect(data.tasteProfile?.preferences).toEqual(report.taste?.snapshot.preferences)
  })
  it.each(['taste', 'companion', 'source', 'monthly', 'annual'] as const)('defaults %s data and poster to private-safe projections', mode => {
    const input = profile(); const report = buildAnalyticsReport(input, { mode, now }); const data = analyticsReportShareData(report, input)
    const text = analyticsReportShareText(report, input)
    const svg = renderAnalysisPosterSvg({ data, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    for (const output of [text, svg]) { expect(output).not.toContain('秘密同行姓名'); expect(output).not.toContain('绝不分享的私人笔记'); expect(output).not.toContain('¥137') }
    expect(data.privacy).toEqual({ companionNameIncluded: false, spendIncluded: false, exactLocationIncluded: false })
    expect(data.tasteProfile?.spend ?? null).toBeNull()
  })
  it('retains full safe text instead of a poster-sized list of four observations', () => {
    const input = profile(); const report = buildAnalyticsReport(input, { mode: 'taste', now }); const text = analyticsReportShareText(report, input)
    for (const title of ['评分习惯', '近期与长期口味', '低分体验线索', '同行与独自用餐', '城市足迹', '用餐时段']) expect(text).toContain(title)
  })
  it('keeps anonymous companion evidence without revealing its directory name', () => {
    const input = profile(); const report = buildAnalyticsReport(input, { mode: 'companion', now }); const data = analyticsReportShareData(report, input)
    expect(data.metrics.some(item => item.label === '一起吃次数')).toBe(true)
    expect(analyticsReportShareText(report, input)).toContain('一起吃过的日子')
    expect(JSON.stringify(data)).not.toContain('秘密同行姓名')
  })
  it('prioritizes existing period comparisons over repeated overview counters without bypassing privacy', () => {
    const input = profile()
    input.visits.push(...input.visits.map(visit => ({ ...visit, id: `previous-${visit.id}`, visitedAt: '2026-08-02T12:00:00' })))
    const report = buildAnalyticsReport(input, { mode: 'monthly', now, year: 2026, month: 9 })
    const comparison = report.sections.find(section => section.id === 'period-comparison')!
    expect(comparison.metrics?.length).toBeGreaterThan(0)
    report.sections.unshift({ id: 'period-taste-change', title: '私密变化', privacy: 'spend', rows: [{ id: 'secret', label: '绝不分享的私人变化' }] })
    const data = analyticsReportShareData(report, input)
    expect(data.insights.some(line => line.startsWith(`${comparison.title} · `))).toBe(true)
    expect(data.insights.slice(0, 3).some(line => line.startsWith(`${comparison.title} · `))).toBe(true)
    expect(data.insights).not.toContain(`到访：${report.summary.visitCount} 次`)
    expect(JSON.stringify(data)).not.toContain('绝不分享的私人变化')
  })
  it('does not export owner images when the image capability denies export', () => {
    const input = profile(); const id = input.restaurants[0].id
    input.restaurantImages[id] = { kind: 'ownerPhoto', resourceURL: 'https://private.example/secret-photo.png', accessibilityLabel: '本人照片', photoID: 'p1', sourceOwnerID: input.user.id, restaurantID: id, visitID: null, visibility: 'private', attributionRequired: false, exportAllowed: false }
    const data = analyticsReportShareData(buildAnalyticsReport(input, { mode: 'taste', now }), input)
    expect(JSON.stringify(data)).not.toContain('secret-photo')
  })
  it('does not export third-party public UGC even when a usable URL exists', () => {
    const input = profile(); const id = input.restaurants[0].id
    input.restaurantImages[id] = { kind: 'publicUGC', resourceURL: 'https://private.example/other-photo.png', accessibilityLabel: '他人照片', photoID: 'p2', sourceOwnerID: 'another', restaurantID: id, visitID: null, visibility: 'public', attributionRequired: true, exportAllowed: true }
    const data = analyticsReportShareData(buildAnalyticsReport(input, { mode: 'taste', now }), input)
    expect(JSON.stringify(data)).not.toContain('other-photo')
  })
  it('requires matching owner, restaurant and scoped Visit for separately projected owner images', () => {
    const input = profile(); const id = input.restaurants[0].id
    input.visits.forEach(visit => { visit.photos = []; visit.photoIds = []; visit.dishes = [] })
    const image = { kind: 'ownerPhoto' as const, resourceURL: 'https://private.example/own-photo.png', accessibilityLabel: '照片', photoID: 'p1', sourceOwnerID: 'another', restaurantID: id, visitID: input.visits.find(visit => visit.restaurantId === id)!.id, visibility: 'private' as const, attributionRequired: false, exportAllowed: true }
    input.restaurantImages[id] = image
    const share = () => analyticsReportShareData(buildAnalyticsReport(input, { mode: 'taste', now }), input)
    expect(JSON.stringify(share())).not.toContain('own-photo')
    input.restaurantImages[id] = { ...image, sourceOwnerID: input.user.id }
    expect(JSON.stringify(share())).toContain('own-photo')
    input.restaurantImages[id] = { ...image, sourceOwnerID: input.user.id, restaurantID: 'wrong-store' }
    expect(JSON.stringify(share())).not.toContain('own-photo')
    input.restaurantImages[id] = { ...image, sourceOwnerID: input.user.id, visitID: null }
    expect(JSON.stringify(share())).not.toContain('own-photo')
  })
  it('freezes real Visit/dish photography with the selected period and never exports the avatar or later profile photos', () => {
    const input = profile(); const id = input.restaurants[0].id
    const selected = input.visits.find(visit => visit.restaurantId === id)!
    input.visits = [
      { ...selected, id: 'old', visitedAt: '2026-08-10T12:00:00', photos: ['data:image/png;base64,OLD'], photoIds: ['old-photo'], dishes: [] },
      { ...selected, id: 'current', photos: [], photoIds: [], dishes: [{ id: 'dish', name: '菜', taste: '', rating: null, price: null, imageData: 'data:image/png;base64,DISH', photoId: 'dish-photo' }] },
    ]
    input.restaurantImages[id] = { kind: 'nativeResource', resourceURL: 'https://private.example/CUSTOM_AVATAR', photoID: 'avatar', accessibilityLabel: '头像' }
    const report = buildAnalyticsReport(input, { mode: 'monthly', now, year: 2026, month: 9 })
    const data = analyticsReportShareData(report, input)
    expect(data.restaurants[0].image).toMatchObject({ source: 'data:image/png;base64,DISH', origin: 'visit', photoId: 'dish-photo', tags: input.restaurants[0].tags })
    expect(JSON.stringify(data)).not.toContain('CUSTOM_AVATAR')
    expect(JSON.stringify(data)).not.toContain('OLD')
    input.visits[1].dishes[0].imageData = 'data:image/png;base64,LATER'
    expect(analyticsReportShareData(report, input).restaurants[0].image.source).toBe('data:image/png;base64,DISH')
    input.user = { ...input.user, id: 'other-owner' }
    expect(() => analyticsReportShareData(report, input)).toThrow('账户已变化')
  })
  it('keeps source poster restaurants on the selected source and anonymizes private source names in text and data', () => {
    const input = profile(); const template = input.visits[0]; const base = input.restaurants[0]
    input.restaurants = []; input.visits = []
    for (const sourceID of ['a', 'b']) for (let i = 0; i < 5; i++) {
      const id = `${sourceID}-${i}`
      input.restaurants.push({ ...base, id, name: id })
      input.visits.push({ ...template, id, restaurantId: id, rating: sourceID === 'a' ? 5 : 1, visitedAt: '2026-09-01', photos: [], photoIds: [], dishes: [] })
    }
    input.analyticsIdentity!.sources = ['a', 'b'].map(id => ({ id, displayName: `私密来源${id}`, ownerUserID: input.user.id, identifiers: [id], updatedAt: '', deletedAt: null, sourceType: 'friend' }))
    input.analyticsIdentity!.visitSourceLinks = input.visits.map(visit => ({ visitID: visit.id, sourceID: visit.id[0] }))
    for (const sourceID of ['a', 'b']) {
      const report = buildAnalyticsReport(input, { mode: 'source', sourceID, now })
      const data = analyticsReportShareData(report, input)
      expect(data.restaurants.map(restaurant => restaurant.restaurantId)).toEqual(report.topRestaurants.map(restaurant => restaurant.restaurantID))
      expect(data.restaurants.every(restaurant => restaurant.restaurantId.startsWith(sourceID))).toBe(true)
      expect(data.sourceResults?.best?.average).toBe(10)
      expect(data.sourceResults?.worst?.average).toBe(2)
      expect(JSON.stringify(data)).not.toContain('私密来源')
      expect(analyticsReportShareText(report, input)).not.toContain('私密来源')
    }
  })
})
