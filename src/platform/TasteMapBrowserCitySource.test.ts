import { describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary, UserProfile } from '../types/domain'
import type { TasteMapMapBrowseRequest, TasteMapProfileDashboardViewModel } from './TasteMapPlatform'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'

const owner = fixture.profile.user.id
const seed = fixture.restaurants[0] as unknown as RestaurantSummary
function restaurant(id: string, city: string, status: RestaurantSummary['status'] = 'visited'): RestaurantSummary {
  return { ...seed, id, city, userId: owner, status, visits: [], deletedAt: null }
}
function profile(restaurants: RestaurantSummary[]): TasteMapProfileDashboardViewModel {
  return { user: fixture.profile.user as unknown as UserProfile, restaurants, visits: [],
    followerCount: 0, followingCount: 0, restaurantImages: {} }
}
function request(overrides: Partial<TasteMapMapBrowseRequest> = {}): TasteMapMapBrowseRequest {
  return { requestID: 'city-source-test', scope: 'visited', filters: {}, sort: 'recent', search: '', limit: 300, ...overrides }
}

describe('Browser city sources and accepted snapshots', () => {
  it('uses the selected owner/status before viewport, city, search and score filters', async () => {
    const values = [restaurant('shanghai', '上海市'), restaurant('alias', '上海'), restaurant('hangzhou', '杭州'),
      restaurant('wanted', '东京', 'wantToGo'), { ...restaurant('foreign', '广州'), userId: 'other-owner' },
      { ...restaurant('deleted', '北京'), deletedAt: '2026-09-06T00:00:00Z' }]
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile(values) })
    const visited = await adapter.map.viewport(request())
    expect(new Set(visited.options.cities)).toEqual(new Set(['上海', '杭州']))
    expect(visited.items.map((value) => value.id).sort()).toEqual(['alias', 'hangzhou', 'shanghai'])
    const alias = await adapter.map.viewport(request({ filters: { city: ' 上海 ' } }))
    expect(alias.items.map((value) => value.id).sort()).toEqual(['alias', 'shanghai'])
    expect(alias.options.cities).toEqual(visited.options.cities)
    const empty = await adapter.map.viewport(request({ search: '不存在的餐厅', filters: { city: '上海市', minimumScoreOutOfTen: 10 },
      bounds: { north: 1, south: 0, west: 0, east: 1 } }))
    expect(empty.items).toEqual([])
    expect(empty.options.cities).toEqual(visited.options.cities)
    expect((await adapter.map.viewport(request({ scope: 'wantToGo' }))).options.cities).toEqual(['东京'])
    expect((await adapter.map.viewport(request({ scope: 'recommended' }))).options.cities).toEqual([])
    expect(values[0].city).toBe('上海市')
  })

  it('accepts add/edit/status/delete snapshots without querying again during map panning', async () => {
    const dataSource = { profile: vi.fn(async () => profile([restaurant('first', '上海')])) }
    const adapter = new TasteMapBrowserAdapter(dataSource)
    expect((await adapter.map.viewport(request())).options.cities).toEqual(['上海'])
    adapter.acceptProfileSnapshot(profile([restaurant('first', '上海'), restaurant('added', '杭州市')]))
    expect(new Set((await adapter.map.viewport(request())).options.cities)).toEqual(new Set(['上海', '杭州']))
    adapter.acceptProfileSnapshot(profile([restaurant('first', '温州市'), restaurant('added', '杭州', 'wantToGo')]))
    expect((await adapter.map.viewport(request())).options.cities).toEqual(['温州'])
    expect((await adapter.map.viewport(request({ scope: 'wantToGo' }))).options.cities).toEqual(['杭州'])
    adapter.acceptProfileSnapshot(profile([restaurant('added', '杭州', 'wantToGo')]))
    for (let index = 0; index < 8; index += 1) {
      const result = await adapter.map.viewport(request({ bounds: { north: 32 + index, south: 28, west: 119, east: 122 } }))
      expect(result.options.cities).toEqual([])
    }
    expect(dataSource.profile).toHaveBeenCalledTimes(1)
  })

  it('refreshes explicit profile reads and reuses their snapshot for viewport calls', async () => {
    const dataSource = { profile: vi.fn().mockResolvedValueOnce(profile([restaurant('old', '上海')]))
      .mockResolvedValueOnce(profile([restaurant('new', '东京')])) }
    const adapter = new TasteMapBrowserAdapter(dataSource)
    await adapter.profile.getCurrent()
    expect((await adapter.map.viewport(request())).options.cities).toEqual(['上海'])
    await adapter.profile.getCurrent()
    expect((await adapter.map.viewport(request())).options.cities).toEqual(['东京'])
    expect(dataSource.profile).toHaveBeenCalledTimes(2)
  })

  it('does not let a pending old read replace a newer accepted owner snapshot', async () => {
    let resolveOld!: (value: TasteMapProfileDashboardViewModel) => void
    const adapter = new TasteMapBrowserAdapter({ profile: () => new Promise((resolve) => { resolveOld = resolve }) })
    const pending = adapter.profile.getCurrent()
    await vi.waitFor(() => expect(resolveOld).toBeTypeOf('function'))
    adapter.acceptProfileSnapshot(profile([restaurant('new', '温州')]))
    resolveOld(profile([restaurant('old', '上海')]))
    await pending
    expect((await adapter.map.viewport(request())).options.cities).toEqual(['温州'])
  })
})
