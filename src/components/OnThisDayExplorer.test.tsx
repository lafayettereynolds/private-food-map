import { renderToStaticMarkup } from 'react-dom/server'
import { afterEach, describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { OnThisDayExplorer } from './OnThisDayExplorer'

const state = vi.hoisted(() => ({ page: 'D03' }))
vi.mock('./AnalysisReadingUI', async importOriginal => ({
  ...await importOriginal<typeof import('./AnalysisReadingUI')>(),
  useAnalysisReading: () => ({ route: { page: state.page }, go: vi.fn(), setRoute: vi.fn(), back: vi.fn(), root: { current: null } }),
}))
const user = fixture.profile.user as unknown as UserProfile
const restaurants = [{ ...fixture.restaurants[0], id: 'r', userId: user.id, name: '回忆测试餐厅', deletedAt: null }] as unknown as RestaurantSummary[]
function render(dates: string[]) {
  const visits = dates.map((visitedAt, index) => ({ ...fixture.restaurants[0].visits[0], id: `v${index}`, userId: user.id, restaurantId: 'r', visitedAt, rating: null, deletedAt: null, photos: [], photoIds: [], dishes: [], companions: [], note: '' })) as Visit[]
  return renderToStaticMarkup(<OnThisDayExplorer user={user} restaurants={restaurants} visits={visits} onClose={() => {}} onOpenRestaurant={() => {}} />)
}
afterEach(() => { vi.useRealTimers(); state.page = 'D03' })
describe('On This Day year destination', () => {
  it('renders distinct newest-first year groups, retains every unrated meal, and has no self-link', () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date(2026, 8, 8, 12))
    const html = render(['2024-09-08', '2025-09-08T12:00:00', '2025-09-08T19:00:00', '2026-09-08', '2025-09-07'])
    expect(html).toContain('data-explore-page="D03"')
    expect(html).toContain('2025 年 · 2 条记录')
    expect(html).toContain('2024 年 · 1 条记录')
    expect(html.indexOf('2025 年 ·')).toBeLessThan(html.indexOf('2024 年 ·'))
    expect(html.match(/<strong>回忆测试餐厅<\/strong>/g)).toHaveLength(3)
    expect(html).not.toContain('<strong>不同年份的这一天</strong>')
    expect(html).not.toContain('2026 年 ·')
    expect(html).toContain('同日记录清单')
    expect(html).toContain('返回上一页')
  })
  it('keeps the single-year destination meaningful for the reported one-meal case', () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date(2026, 8, 8, 12))
    const html = render(['2025-09-08'])
    expect(html).toContain('2025 年 · 1 条记录')
    expect(html).not.toContain('<strong>不同年份的这一天</strong>')
  })
  it('renders an honest empty year destination when its records are no longer available', () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date(2026, 8, 8, 12))
    expect(render([])).toContain('往年的这一天还没有记录。')
  })
})
