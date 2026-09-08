import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { buildAnalyticsReport } from './analyticsReport'
import { analyticsMemoryShareData } from './analyticsMemoryShare'
function profile(): TasteMapProfileDashboardViewModel {
  const owner = fixture.profile.user.id
  const restaurants = Array.from({ length: 12 }, (_, index) => ({ ...fixture.restaurants[0], userId: owner, id: `r${index}`, name: `餐厅${index}`, deletedAt: null, tags: ['日料'] }))
  const visits = restaurants.map((restaurant, index) => ({ ...fixture.restaurants[0].visits[0], id: `v${index}`, userId: owner, restaurantId: restaurant.id, visitedAt: '2026-08-01T12:00:00', rating: index < 6 ? 4.5 : 2.5, visibility: index === 0 ? 'private' : 'public', photos: [], photoIds: [], dishes: [], note: '不应导出的私人笔记', deletedAt: null }))
  return { ...fixture.profile, restaurants, visits, restaurantImages: {}, analyticsIdentity: { ownerUserID: owner, recordOwnerID: owner, companions: [], sources: ['good', 'bad'].map(id => ({ id, identifiers: [id], ownerUserID: owner, displayName: id === 'good' ? '具名正向创作者' : '具名负向创作者', sourceType: 'other', deletedAt: null, updatedAt: '2026-08-01' })), visitSourceLinks: visits.map((visit, index) => ({ visitID: visit.id, sourceID: index < 6 ? 'good' : 'bad' })) } } as unknown as TasteMapProfileDashboardViewModel
}
describe('V2 public memory projections', () => {
  it('recalculates period totals from public records and keeps private notes out', () => {
    const owner = profile(), now = new Date('2026-09-07T12:00:00')
    const full = buildAnalyticsReport(owner, { mode: 'monthly', year: 2026, month: 8, now })
    const safe = buildAnalyticsReport(owner, { mode: 'monthly', year: 2026, month: 8, now, excludePrivate: true })
    expect(full.summary.visitCount).toBe(12); expect(safe.summary.visitCount).toBe(11)
    const data = analyticsMemoryShareData(safe, owner)
    expect(data.metrics.find(item => item.label === '用餐记录')?.value).toBe('11')
    expect(JSON.stringify(data)).not.toMatch(/不应导出的私人笔记|具名负向创作者|具名正向创作者/)
    expect(data.editorial?.audience).toBe('share')
    expect(data.editorial?.sections.find(item => item.id === 'negative')?.rows).toEqual([])
  })
  it('keeps a qualified negative ranking in private analysis but never exports it or named sources', () => {
    const owner = profile(), now = new Date('2026-09-07T12:00:00')
    const report = buildAnalyticsReport(owner, { mode: 'source', now, excludePrivate: true })
    expect(report.source?.worstSourceID).toBe('bad')
    expect(report.source?.baselineRestaurantCount).toBe(11)
    const data = analyticsMemoryShareData(report, owner)
    expect(data.sourceResults).toBeUndefined()
    expect(JSON.stringify(data)).not.toMatch(/具名负向创作者|具名正向创作者|不应导出的私人笔记/)
    expect(data.restaurants.every(item => Number(item.score) >= 8)).toBe(true)
  })
})
