import { beforeEach, describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { PoiSearchResult, UserProfile } from '../types/domain'
import type { TasteMapProfileDashboardViewModel } from './TasteMapPlatform'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'

const provider = vi.hoisted(() => ({
  isConfigured: true,
  detectCurrentCoordinates: vi.fn(),
  searchNearbyRestaurantPois: vi.fn(),
  resolveCoordinatesLocation: vi.fn(),
}))
vi.mock('../services/mapService', () => ({ mapService: provider }))
const profile = (owner = 'test-owner'): TasteMapProfileDashboardViewModel => ({
  user: { ...fixture.profile.user, id: owner } as unknown as UserProfile,
  restaurants: [], visits: [], restaurantImages: {}, followerCount: 0, followingCount: 0,
})
const poi = (index: number, latitude = (index + 1) / 10_000): PoiSearchResult => ({
  amapPoiId: `nearby-test-${index}`, name: `测试候选 ${index}`, address: '测试地址', city: '测试城市', district: '',
  latitude, longitude: 0, categoryHints: [], merchantImageUrl: null, phone: null, openingHours: null,
})
const deferred = <T,>() => { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done }); return { promise, resolve } }

beforeEach(() => {
  vi.clearAllMocks()
  provider.detectCurrentCoordinates.mockResolvedValue({ latitude: 0, longitude: 0 })
  provider.resolveCoordinatesLocation.mockResolvedValue({ city: '测试城市' })
})

describe('complete accepted Nearby snapshots', () => {
  it('returns every obtained in-range candidate, sorted and provider-deduplicated, from one GPS/search', async () => {
    provider.searchNearbyRestaurantPois.mockResolvedValue([...Array.from({ length: 29 }, (_, index) => poi(index)).reverse(), poi(1), poi(99, 0.1)])
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    const result = await adapter.acquisition.nearby()
    expect(result.candidates).toHaveLength(29)
    expect(result.candidates.map((item) => item.name)).toEqual(Array.from({ length: 29 }, (_, index) => `测试候选 ${index}`))
    expect(result.candidates.every((item) => item.distanceMeters !== null && item.distanceMeters <= 3_000)).toBe(true)
    expect(result.nextCursor).toBeUndefined()
    expect(provider.detectCurrentCoordinates).toHaveBeenCalledTimes(1)
    expect(provider.searchNearbyRestaurantPois).toHaveBeenCalledTimes(1)
    expect(provider.searchNearbyRestaurantPois).toHaveBeenCalledWith({ latitude: 0, longitude: 0 }, undefined, { radiusMeters: 3_000 })
  })

  it('does not register an old response after a newer Nearby refresh wins', async () => {
    const old = deferred<PoiSearchResult[]>()
    const current = deferred<PoiSearchResult[]>()
    provider.searchNearbyRestaurantPois.mockReturnValueOnce(old.promise).mockReturnValueOnce(current.promise)
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    const first = adapter.acquisition.nearby().catch((error: { code: string }) => error.code)
    await vi.waitFor(() => expect(provider.searchNearbyRestaurantPois).toHaveBeenCalledTimes(1))
    const second = adapter.acquisition.nearby()
    await vi.waitFor(() => expect(provider.searchNearbyRestaurantPois).toHaveBeenCalledTimes(2))
    current.resolve([poi(2)])
    expect((await second).candidates[0].name).toBe('测试候选 2')
    old.resolve([poi(1)])
    expect(await first).toBe('nearby_request_superseded')
    await expect(adapter.acquisition.select('browser-candidate-nearby-test-1')).rejects.toMatchObject({ code: 'candidate_not_found' })
  })

  it('discards pending results across an accepted owner change without another DB read', async () => {
    const pending = deferred<PoiSearchResult[]>()
    provider.searchNearbyRestaurantPois.mockReturnValueOnce(pending.promise)
    const source = { profile: vi.fn(async () => profile()) }
    const adapter = new TasteMapBrowserAdapter(source)
    const request = adapter.acquisition.nearby().catch((error: { code: string }) => error.code)
    await vi.waitFor(() => expect(provider.searchNearbyRestaurantPois).toHaveBeenCalledTimes(1))
    adapter.acceptProfileSnapshot(profile('new-owner'))
    pending.resolve([poi(1)])
    expect(await request).toBe('nearby_request_superseded')
    expect(source.profile).toHaveBeenCalledTimes(1)
  })

  it('keeps precise-location failures actionable and never starts a provider query', async () => {
    provider.detectCurrentCoordinates.mockRejectedValueOnce(new Error('precise location unavailable'))
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    await expect(adapter.acquisition.nearby()).rejects.toThrow('precise location unavailable')
    expect(provider.searchNearbyRestaurantPois).not.toHaveBeenCalled()
  })
})
