import { describe, expect, it, vi } from 'vitest'
import { renderToStaticMarkup } from 'react-dom/server'
import { createElement } from 'react'
import type { RestaurantSummary, Visit } from '../../types/domain'
import type { TasteMapPlatform, TasteMapRestaurantDetailViewModel } from '../../platform/TasteMapPlatform'
import { boundedVisitEditorRead, loadVisitEditorContext } from './visitEditorContext'
import { HybridVisitEditorPage } from './HybridVisitEditorPage'
vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))

const visit = { id: 'visit-ABC', restaurantId: 'restaurant-ABC', note: '原记录', companions: [] } as unknown as Visit
const restaurant = { id: 'restaurant-ABC', visits: [visit] } as unknown as RestaurantSummary
const detail = { restaurant, editableVisitIDs: [visit.id], capabilities: { canRecordVisit: true } } as TasteMapRestaurantDetailViewModel
function platformFor(value = detail) {
  return { profile: { getCurrent: vi.fn().mockResolvedValue({ restaurants: [restaurant], visits: [visit] }) }, restaurant: { get: vi.fn().mockResolvedValue(value) } } as unknown as TasteMapPlatform
}

describe('Visit edit context recovery', () => {
  it('recovers a cold edit from fresh owner data when the initial profile is stale', async () => {
    const platform = platformFor()
    const value = await loadVisitEditorContext(platform, { visitID: visit.id, restaurants: [], visits: [] })
    expect(platform.profile.getCurrent).toHaveBeenCalledOnce()
    expect(platform.restaurant.get).toHaveBeenCalledWith(restaurant.id)
    expect(value.visit).toBe(visit)
  })
  it('uses the actual Detail entry when its Visit is newer than the dashboard snapshot', async () => {
    const platform = platformFor()
    const value = await loadVisitEditorContext(platform, { visitID: visit.id, restaurants: [], visits: [], sourceDetail: detail })
    expect(platform.profile.getCurrent).not.toHaveBeenCalled()
    expect(value.visit?.note).toBe('原记录')
  })
  it('matches identifier casing without creating a new Visit', async () => {
    expect((await loadVisitEditorContext(platformFor(), { visitID: 'VISIT-abc', restaurants: [restaurant], visits: [visit] })).visit?.id).toBe(visit.id)
  })
  it('fails explicitly when a Visit disappeared instead of opening a create form', async () => {
    const platform = platformFor()
    vi.mocked(platform.profile.getCurrent).mockResolvedValue({ restaurants: [], visits: [] } as never)
    await expect(loadVisitEditorContext(platform, { visitID: 'deleted', restaurants: [], visits: [] })).rejects.toThrow('未找到这次到访')
    expect(platform.restaurant.get).not.toHaveBeenCalled()
  })
  it('checks current Native edit capability, not a client owner comparison', async () => {
    await expect(loadVisitEditorContext(platformFor({ ...detail, editableVisitIDs: [] }), { visitID: visit.id, restaurants: [restaurant], visits: [visit] })).rejects.toThrow('当前账户无法编辑')
  })
  it('does not use a different Visit from the same Restaurant', async () => {
    await expect(loadVisitEditorContext(platformFor({ ...detail, restaurant: { ...restaurant, visits: [] } }), { visitID: visit.id, restaurants: [restaurant], visits: [visit] })).rejects.toThrow('已不可用')
  })
  it('propagates request failures so Retry is meaningful', async () => {
    const platform = platformFor()
    vi.mocked(platform.restaurant.get).mockRejectedValue(new Error('读取失败'))
    await expect(loadVisitEditorContext(platform, { restaurantID: restaurant.id, restaurants: [], visits: [] })).rejects.toThrow('读取失败')
  })
  it('keeps the create flow distinct and enforces its own capability', async () => {
    const value = await loadVisitEditorContext(platformFor(), { restaurantID: restaurant.id, restaurants: [], visits: [] })
    expect(value.visit).toBeNull()
    await expect(loadVisitEditorContext(platformFor({ ...detail, capabilities: { ...detail.capabilities, canRecordVisit: false } }), { restaurantID: restaurant.id, restaurants: [], visits: [] })).rejects.toThrow('无法记录到访')
  })
  it('bounds unresolved reads and ignores a late completion after timeout', async () => {
    vi.useFakeTimers()
    try {
      let finish!: (value: string) => void
      const promise = boundedVisitEditorRead(new Promise<string>((resolve) => { finish = resolve }), 100)
      const assertion = expect(promise).rejects.toThrow('超时')
      await vi.advanceTimersByTimeAsync(101)
      await assertion
      finish('late')
      await Promise.resolve()
      expect(vi.getTimerCount()).toBe(0)
    } finally { vi.useRealTimers() }
  })
  it('renders honest loading with one persistent icon back, never a fatal loading message', () => {
    const html = renderToStaticMarkup(createElement(HybridVisitEditorPage, { platform: platformFor(), visitID: visit.id, restaurants: [], visits: [], onClose: vi.fn(), onSaved: vi.fn(), onRestaurantDeleted: vi.fn() }))
    expect(html).toContain('正在读取到访记录')
    expect(html).not.toContain('无法打开到访记录')
    expect(html.match(/aria-label="返回上一页"/g)).toHaveLength(1)
    expect(html).not.toContain('is-fatal')
  })
})
