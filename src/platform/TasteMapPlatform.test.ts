import { afterEach, describe, expect, it, vi } from 'vitest'
import fixture from '../../public/hybrid-poc/dataset.json'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { hasNativeTasteMapRuntime, TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import { TASTE_MAP_NATIVE_BRIDGE_VERSION, TasteMapPlatformError } from './TasteMapPlatform'

afterEach(() => vi.unstubAllGlobals())

describe('TasteMapBrowserAdapter', () => {
  it('uses the deterministic fixture without a backend dependency', async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify(fixture), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    const adapter = new TasteMapBrowserAdapter()
    const profile = await adapter.profile.getCurrent()
    const restaurant = await adapter.restaurant.get('11111111-1111-4111-8111-111111111111')

    expect(profile.followingCount).toBe(76)
    expect(profile.followerCount).toBe(128)
    expect(profile.restaurants).toHaveLength(5)
    expect(profile.visits).toHaveLength(2)
    expect(restaurant.name).toBe('湖滨二十八号 · 江南味道')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('reports a typed missing Restaurant error', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify(fixture), { status: 200 })))
    await expect(new TasteMapBrowserAdapter().restaurant.get('missing')).rejects.toMatchObject({
      code: 'restaurant_not_found',
    })
  })
})

describe('TasteMapNativeAdapter', () => {
  function nativeTarget(bridgeVersion: number = TASTE_MAP_NATIVE_BRIDGE_VERSION) {
    const plugin = {
      runtimeInfo: vi.fn(async () => ({
        bridgeVersion,
        platform: 'ios' as const,
        dataSource: 'native-swiftdata-in-memory' as const,
        localBundle: true,
        offlineCapable: true,
      })),
      profileGetCurrent: vi.fn(async () => ({
        user: fixture.profile.user,
        restaurants: fixture.restaurants,
        visits: fixture.restaurants.flatMap((restaurant) => restaurant.visits),
        followerCount: fixture.profile.followerCount,
        followingCount: fixture.profile.followingCount,
      })),
      restaurantGet: vi.fn(async ({ id }: { id: string }) => fixture.restaurants.find((item) => item.id === id)!),
      hapticsSelection: vi.fn(async () => ({})),
      authSessionStatus: vi.fn(async () => ({ state: 'authenticated' as const, provider: 'local-poc' as const, userID: 'tm_capacitor_poc' })),
      authSignInWithApple: vi.fn(async () => ({ state: 'unavailable' as const, reason: 'No credential requested.' })),
    }
    const target = {
      Capacitor: {
        Plugins: { TasteMapNative: plugin },
        getPlatform: () => 'ios',
        isNativePlatform: () => true,
      },
    }
    return { plugin, target }
  }

  it('forwards the v1 profile, restaurant, haptic and auth boundaries', async () => {
    const { plugin, target } = nativeTarget()
    expect(hasNativeTasteMapRuntime(target as never)).toBe(true)

    const adapter = new TasteMapNativeAdapter(target as never)
    expect((await adapter.runtime.info()).localBundle).toBe(true)
    expect((await adapter.profile.getCurrent()).followingCount).toBe(76)
    expect((await adapter.restaurant.get(fixture.restaurants[0].id)).id).toBe(fixture.restaurants[0].id)
    await adapter.haptics.selection()
    expect(plugin.hapticsSelection).toHaveBeenCalledOnce()
    expect(await adapter.auth.sessionStatus()).toEqual({
      state: 'authenticated', provider: 'local-poc', userID: 'tm_capacitor_poc',
    })
    expect(await adapter.auth.signInWithApple()).toEqual({
      state: 'unavailable', reason: 'No credential requested.',
    })
  })

  it('rejects an incompatible native bridge before consuming data', async () => {
    const { target } = nativeTarget(2)
    await expect(new TasteMapNativeAdapter(target as never).runtime.info()).rejects.toMatchObject({
      name: 'TasteMapPlatformError',
      code: 'bridge_version_mismatch',
    } satisfies Partial<TasteMapPlatformError>)
  })
})
