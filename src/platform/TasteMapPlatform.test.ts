import { describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { hasNativeTasteMapRuntime, TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { CURRENT_USER_ID } from '../db/social'
import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  TasteMapPlatformError,
  type TasteMapBridgeRequestEnvelope,
  type TasteMapBridgeResponseEnvelope,
  type TasteMapCapabilityRegistry,
  type TasteMapMapBrowseRequest,
  type TasteMapProfileDashboardDTO,
  type TasteMapProfileDashboardViewModel,
} from './TasteMapPlatform'

const capabilities: TasteMapCapabilityRegistry = {
  appleSignIn: false, logout: false, profileRead: true, restaurantRead: true, mapBrowse: true,
  contentRead: true,
  visitContract: true, sync: false, haptics: true, share: false,
  location: false, photoPicker: false, premium: false, nativeNavigation: false,
  backup: false, accountDelete: false,
}

const browserProfile: TasteMapProfileDashboardViewModel = {
  user: fixture.profile.user as unknown as UserProfile,
  restaurants: fixture.restaurants as unknown as RestaurantSummary[],
  visits: fixture.restaurants.flatMap((restaurant) => restaurant.visits) as unknown as Visit[],
  followerCount: fixture.profile.followerCount,
  followingCount: fixture.profile.followingCount,
  restaurantImages: Object.fromEntries(fixture.restaurants.map((restaurant) => [restaurant.id,
    restaurant.merchantImageUrl
      ? { kind: 'providerMerchant' as const, resourceURL: restaurant.merchantImageUrl, accessibilityLabel: restaurant.name }
      : { kind: 'foodDiningFallback' as const, stableSeed: restaurant.id, accessibilityLabel: restaurant.name },
  ])),
}

const bridgeProfile: TasteMapProfileDashboardDTO = {
  user: {
    id: fixture.profile.user.id,
    nickname: fixture.profile.user.nickname,
    bio: fixture.profile.user.bio,
    city: fixture.profile.user.city,
    avatarPhotoId: fixture.profile.user.avatarPhotoId,
    avatarPresetId: fixture.profile.user.avatarPresetId as TasteMapProfileDashboardDTO['user']['avatarPresetId'],
    membershipTier: fixture.profile.user.membershipTier as TasteMapProfileDashboardDTO['user']['membershipTier'],
    mapSharingEnabled: fixture.profile.user.mapSharingEnabled,
    mapVisibility: fixture.profile.user.mapVisibility as TasteMapProfileDashboardDTO['user']['mapVisibility'],
    createdAt: fixture.profile.user.createdAt,
    updatedAt: fixture.profile.user.updatedAt,
  },
  restaurants: fixture.restaurants.map((restaurant) => ({
    id: restaurant.id,
    name: restaurant.name,
    address: restaurant.address,
    city: restaurant.city,
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    status: restaurant.status as TasteMapProfileDashboardDTO['restaurants'][number]['status'],
    tags: restaurant.tags,
    phone: restaurant.phone,
    openingHours: restaurant.openingHours,
    referencePrice: restaurant.averagePricePerPerson,
    visitCount: restaurant.visitCount,
    averageRating: restaurant.averageRating,
    scoreOutOfTen: restaurant.scoreOutOfTen,
    latestVisitDate: restaurant.latestVisitDate,
    createdAt: restaurant.createdAt,
    updatedAt: restaurant.updatedAt,
    visits: restaurant.visits.map((visit) => ({
      id: visit.id,
      restaurantId: visit.restaurantId,
      visitedAt: visit.visitedAt,
      rating: visit.rating,
      valueRating: visit.valueRating,
      environmentRating: visit.environmentRating,
      serviceRating: visit.serviceRating,
      myActualSpend: visit.myActualSpend,
      totalPrice: visit.totalPrice,
      pricePerPerson: visit.pricePerPerson,
      diningMode: visit.diningMode,
      visibility: visit.visibility,
      paymentMode: visit.paymentMode,
      queueDuration: visit.queueDuration,
      diningOccasions: visit.diningOccasions,
      diningOccasionText: visit.diningOccasionText,
      valueTags: visit.valueTags,
      environmentTags: visit.environmentTags,
      serviceTags: visit.serviceTags,
      companions: visit.companions,
      companionIds: visit.companionIds,
      recommendationSourceText: visit.recommendationSourceText,
      partySize: visit.partySize,
      note: visit.note,
      createdAt: visit.createdAt,
      updatedAt: visit.updatedAt,
    })),
    image: browserProfile.restaurantImages[restaurant.id],
  } as TasteMapProfileDashboardDTO['restaurants'][number])),
  followerCount: fixture.profile.followerCount,
  followingCount: fixture.profile.followingCount,
}

describe('TasteMapBrowserAdapter', () => {
  it('uses an injected Browser data source without a backend dependency', async () => {
    const dataSource = { profile: vi.fn(async () => browserProfile) }
    const adapter = new TasteMapBrowserAdapter(dataSource)
    expect((await adapter.runtime.info()).dataSource).toBe('browser-indexeddb')
    expect((await adapter.profile.getCurrent()).followingCount).toBe(76)
    expect((await adapter.restaurant.get('11111111-1111-4111-8111-111111111111')).restaurant.name).toBe('湖滨二十八号 · 江南味道')
    expect(dataSource.profile).toHaveBeenCalledTimes(1)
  })

  it('reports a typed missing Restaurant error', async () => {
    const adapter = new TasteMapBrowserAdapter({ profile: async () => browserProfile })
    await expect(adapter.restaurant.get('missing')).rejects.toMatchObject({ code: 'restaurant_not_found' })
  })

  it('uses the same owner-scoped viewport contract for Browser Map and List', async () => {
    const adapter = new TasteMapBrowserAdapter({ profile: async () => browserProfile })
    const request: TasteMapMapBrowseRequest = {
      requestID: 'viewport-1', scope: 'visited', filters: {}, sort: 'rating', search: '', limit: 300,
    }
    const visited = await adapter.map.viewport(request)
    expect(visited.requestID).toBe(request.requestID)
    expect(visited.items.length).toBeGreaterThan(0)
    expect(visited.items.every((item) => item.status === 'visited')).toBe(true)
    expect(visited.items.every((item) => item.id && Number.isFinite(item.latitude) && Number.isFinite(item.longitude))).toBe(true)
    expect(visited.items.every((item) => !('resourceURL' in item.image) || !item.image.resourceURL.startsWith('file://'))).toBe(true)

    const filtered = await adapter.map.viewport({
      ...request, requestID: 'viewport-2', filters: { city: visited.items[0].city, minimumVisitCount: 1 },
    })
    expect(filtered.items.every((item) => item.city === visited.items[0].city && item.visitCount >= 1)).toBe(true)

    const recommended = await adapter.map.viewport({ ...request, requestID: 'viewport-3', scope: 'recommended' })
    expect(recommended.items).toEqual([])
    expect(recommended.totalCount).toBe(0)
  })
})

describe('TasteMapNativeAdapter', () => {
  function nativeTarget(options: { bridgeVersion?: number; failMethod?: string } = {}) {
    let eventListener: ((event: { sequence: number; name: 'auth.changed'; payload: { state: 'signedOut' } }) => void) | undefined
    const remove = vi.fn(async () => undefined)
    const addListener = vi.fn(async (_eventName: 'event', listener: typeof eventListener) => {
      eventListener = listener
      return { remove }
    })
    const invoke = vi.fn(async ({ request }: { request: TasteMapBridgeRequestEnvelope<unknown> }) => {
      const version = options.bridgeVersion ?? TASTE_MAP_NATIVE_BRIDGE_VERSION
      let result: unknown
      if (options.failMethod === request.method) {
        return { version, requestId: request.requestId, error: { code: 'capability_unavailable', message: 'Unavailable.', recoverable: false } } as TasteMapBridgeResponseEnvelope
      }
      if (request.method === 'runtime.info') result = {
        bridgeVersion: version, platform: 'ios', appVersion: '1.0', build: '1',
        dataSource: 'native-swiftdata-debug-fixture', localBundle: true, offlineCapable: true,
        supportedCapabilities: capabilities,
      }
      else if (request.method === 'profile.getCurrent') result = bridgeProfile
      else if (request.method === 'map.viewport') {
        const payload = request.payload as TasteMapMapBrowseRequest
        result = {
          requestID: payload.requestID,
          items: bridgeProfile.restaurants.filter((item) => item.status === (payload.scope === 'visited' ? 'visited' : 'wantToGo')),
          totalCount: bridgeProfile.restaurants.length,
          options: { cities: ['杭州'], companions: [], cuisines: [], recommendationSources: [] },
        }
      }
      else if (request.method === 'restaurant.get') {
        const id = (request.payload as { id: string }).id
        const restaurant = fixture.restaurants.find((item) => item.id === id)!
        result = {
          restaurant: bridgeProfile.restaurants.find((item) => item.id === id)!,
          viewerState: restaurant.status === 'visited' ? 'visited' : 'want_to_go',
          editableVisitIDs: restaurant.visits.map((visit) => visit.id),
          capabilities: {
            canEditRestaurant: true,
            canDeleteRestaurant: true,
            canRecordVisit: true,
            canAddToWantToGo: true,
            canAddToList: true,
            canAddToRoulette: true,
            canShare: true,
          },
        }
      } else if (request.method === 'auth.sessionStatus') {
        result = { state: 'authenticated', userID: fixture.profile.user.id, displayName: fixture.profile.user.nickname }
      } else if (request.method === 'navigation.openHybrid') {
        result = { route: request.payload, owner: 'hybrid', canGoBack: true }
      } else if (request.method === 'navigation.back' || request.method === 'navigation.current') {
        result = { route: { surface: 'profile' }, owner: 'hybrid', canGoBack: false }
      } else result = {}
      return { version, requestId: request.requestId, result } as TasteMapBridgeResponseEnvelope
    })
    const target = { Capacitor: { Plugins: { TasteMapNative: { invoke, addListener } }, getPlatform: () => 'ios', isNativePlatform: () => true } }
    return { addListener, emit: (event: Parameters<NonNullable<typeof eventListener>>[0]) => eventListener?.(event), invoke, remove, target }
  }

  it('uses one typed v1 envelope for runtime, profile, Restaurant and haptics', async () => {
    const { invoke, target } = nativeTarget()
    expect(hasNativeTasteMapRuntime(target as never)).toBe(true)
    const adapter = new TasteMapNativeAdapter(target as never)
    expect((await adapter.runtime.info()).localBundle).toBe(true)
    const profile = await adapter.profile.getCurrent()
    expect(profile.followingCount).toBe(76)
    expect(profile.restaurants[0].userId).toBe(CURRENT_USER_ID)
    expect(profile.restaurants[0].visits[0].userId).toBe(CURRENT_USER_ID)
    const detail = await adapter.restaurant.get(fixture.restaurants[0].id)
    expect(detail.restaurant.id).toBe(fixture.restaurants[0].id)
    expect(detail.restaurant.userId).toBe(CURRENT_USER_ID)
    expect(detail.editableVisitIDs).toEqual(fixture.restaurants[0].visits.map((visit) => visit.id))
    expect(detail.capabilities).toEqual(expect.objectContaining({
      canEditRestaurant: true,
      canDeleteRestaurant: true,
      canRecordVisit: true,
    }))
    await adapter.haptics.selection()
    expect(invoke).toHaveBeenCalledTimes(4)
    for (const call of invoke.mock.calls) {
      const request = call[0].request
      expect(request.version).toBe(TASTE_MAP_NATIVE_BRIDGE_VERSION)
      expect(request.requestId).toMatch(/^tm-|^[0-9a-f-]{36}$/)
      expect(request.method).toContain('.')
    }
  })

  it('passes a single versioned viewport request and preserves its request ID', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const response = await adapter.map.viewport({ requestID: 'latest-viewport', scope: 'visited', filters: {}, sort: 'recent', search: '' })
    expect(response.requestID).toBe('latest-viewport')
    expect(response.items.every((item) => item.status === 'visited')).toBe(true)
    expect(invoke.mock.calls.some((call) => call[0].request.method === 'map.viewport')).toBe(true)
  })

  it('rejects incompatible envelopes and structured native errors', async () => {
    await expect(new TasteMapNativeAdapter(nativeTarget({ bridgeVersion: 2 }).target as never).runtime.info()).rejects.toMatchObject({
      name: 'TasteMapPlatformError', code: 'bridge_version_mismatch',
    } satisfies Partial<TasteMapPlatformError>)
    const adapter = new TasteMapNativeAdapter(nativeTarget({ failMethod: 'sync.run' }).target as never)
    await expect(adapter.sync.run()).rejects.toMatchObject({
      name: 'TasteMapPlatformError', code: 'capability_unavailable', recoverable: false,
    } satisfies Partial<TasteMapPlatformError>)
  })

  it('keeps navigation and versioned native events typed without exposing auth credentials', async () => {
    const native = nativeTarget()
    const adapter = new TasteMapNativeAdapter(native.target as never)
    const session = await adapter.auth.sessionStatus()
    expect(JSON.stringify(session)).not.toMatch(/accessToken|refreshToken|authorization|bearer/i)

    const opened = await adapter.navigation.openHybrid({ surface: 'restaurant', identifier: fixture.restaurants[0].id })
    expect(opened).toMatchObject({ owner: 'hybrid', route: { surface: 'restaurant' }, canGoBack: true })
    expect((await adapter.navigation.back()).route.surface).toBe('profile')

    const listener = vi.fn()
    const subscription = await adapter.events.subscribe(listener)
    native.emit({ sequence: 1, name: 'auth.changed', payload: { state: 'signedOut' } })
    expect(listener).toHaveBeenCalledWith({ sequence: 1, name: 'auth.changed', payload: { state: 'signedOut' } })
    await subscription.remove()
    expect(native.addListener).toHaveBeenCalledWith('event', expect.any(Function))
    expect(native.remove).toHaveBeenCalledOnce()
  })

  it('routes Visit edits through the typed Native handoff without embedding ownership decisions in JavaScript', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    await adapter.navigation.openNative({ route: 'visitEdit', identifier: 'visit-owned-1' })
    expect(invoke).toHaveBeenCalledWith(expect.objectContaining({
      request: expect.objectContaining({
        method: 'navigation.openNative',
        payload: { route: 'visitEdit', identifier: 'visit-owned-1' },
      }),
    }))
  })
})
