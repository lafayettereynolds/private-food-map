import { describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import { debugRestaurantSocialStats, TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { expandRichMapRestaurants } from './TasteMapBrowserDebugFixture'
import { hasNativeTasteMapRuntime, TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import { projectBridgeProfile } from './TasteMapBridgeProjection'
import { summarizeVisitSpend } from '../services/visitSpend'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { CURRENT_USER_ID } from '../db/social'
import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  TasteMapPlatformError,
  type TasteMapBridgeRequestEnvelope,
  type TasteMapBridgeResponseEnvelope,
  type TasteMapCapabilityRegistry,
  type TasteMapHybridEvent,
  type TasteMapMapBrowseRequest,
  type TasteMapProfileDashboardDTO,
  type TasteMapProfileDashboardViewModel,
  type TasteMapVisitWriteRequest,
} from './TasteMapPlatform'

const capabilities: TasteMapCapabilityRegistry = {
  appleSignIn: false, logout: false, profileRead: true, restaurantRead: true, restaurantAcquisition: true, mapBrowse: true,
  contentRead: true,
  communityInteraction: true,
  restaurantViewerState: true,
  visitContract: true, sync: false, haptics: true, share: false,
  location: false, photoPicker: false, premium: false, permissions: false, nativeNavigation: false,
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

describe('Native payment/restaurant identity projection', () => {
  it('projects the saved profile avatar through Native resources without losing its ID', () => {
    const result = projectBridgeProfile({ ...bridgeProfile, user: { ...bridgeProfile.user, avatarPhotoId: 'avatar/新版 1' } })
    expect(result.user.avatarImageData).toBe('tastemap-resource://photo/avatar%2F%E6%96%B0%E7%89%88%201/display')
    expect(result.user.avatarPhotoId).toBe('avatar/新版 1')
    expect(projectBridgeProfile({ ...bridgeProfile, user: { ...bridgeProfile.user, avatarPhotoId: null } }).user.avatarImageData).toBeNull()
  })
  it('joins local/remote IDs to their actual parent and recovers omitted optional keys', () => {
    const parent = bridgeProfile.restaurants[0]
    const visit = { ...parent.visits[0], restaurantId: 'different-local-uuid', totalPrice: 17, partySize: 1 }
    delete (visit as Partial<typeof visit>).paymentMode
    delete (visit as Partial<typeof visit>).myActualSpend
    const result = projectBridgeProfile({ ...bridgeProfile, restaurants: [{ ...parent, id: 'REMOTE-ID', city: '', address: '中国浙江省杭州市滨江区江南大道', visits: [visit] }] })
    expect(result.visits[0].restaurantId).toBe(result.restaurants[0].id)
    expect(result.visits[0].paymentMode).toBeNull()
    expect(result.restaurants[0].city).toBe('杭州市')
    expect(summarizeVisitSpend(result.visits).total).toBe(17)
  })
})

describe('TasteMapBrowserAdapter', () => {
  it('keeps the deterministic Hybrid Rich Demo at the real 90/25/275 performance scale', () => {
    const restaurants = expandRichMapRestaurants(fixture.restaurants as unknown as RestaurantSummary[])
    expect(restaurants.filter((value) => value.status === 'visited')).toHaveLength(90)
    expect(restaurants.filter((value) => value.status === 'wantToGo')).toHaveLength(25)
    expect(restaurants.flatMap((value) => value.visits)).toHaveLength(275)
  })

  it('gives the Rich Demo enough distinct social samples to prove every rating reference', () => {
    const stats = debugRestaurantSocialStats(browserProfile.restaurants[0])
    expect(stats.overallUserCount).toBeGreaterThanOrEqual(10)
    expect(stats.friendUserCount).toBeGreaterThanOrEqual(5)
    expect(stats.similarTasteUserCount).toBeGreaterThanOrEqual(5)
    expect(new Set([stats.overallUserRating, stats.friendAverageRating, stats.similarTasteAverageRating]).size).toBeGreaterThan(1)
  })

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

  it.each(['free', 'unavailable'] as const)('rejects premium Map filters when authoritative entitlement is %s', async (state) => {
    const source = { profile: vi.fn(async () => browserProfile) }
    const adapter = new TasteMapBrowserAdapter(source)
    vi.spyOn(adapter.premium, 'status').mockResolvedValue({ state, expiresAt: null })
    for (const filters of [{ companion: '小陈' }, { recommendationSource: '小陈推荐' }, { recommendationSourceType: 'friend' }] as const) {
      await expect(adapter.map.viewport({ requestID: 'restricted', scope: 'visited', filters,
        sort: 'rating', search: '', limit: 300 })).rejects.toMatchObject({ code: 'premium_filters_required' })
    }
    expect(source.profile).not.toHaveBeenCalled()
  })

  it('uses the same owner-scoped viewport contract for Browser Map and List', async () => {
    const adapter = new TasteMapBrowserAdapter({ profile: async () => browserProfile })
    vi.spyOn(adapter.premium, 'status').mockResolvedValue({ state: 'premium', expiresAt: null })
    const request: TasteMapMapBrowseRequest = {
      requestID: 'viewport-1', scope: 'visited', filters: {}, sort: 'rating', search: '', limit: 300,
    }
    const visited = await adapter.map.viewport(request)
    expect(visited.requestID).toBe(request.requestID)
    expect(visited.items.length).toBeGreaterThan(0)
    expect(visited.items.every((item) => item.status === 'visited')).toBe(true)
    expect(visited.items.every((item) => item.id && Number.isFinite(item.latitude) && Number.isFinite(item.longitude))).toBe(true)
    expect(visited.items.every((item) => !('resourceURL' in item.image) || !item.image.resourceURL.startsWith('file://'))).toBe(true)
    expect(visited.scopeCounts).toEqual({ visited: 3, wantToGo: 2, recommended: 0 })

    const filtered = await adapter.map.viewport({
      ...request, requestID: 'viewport-2', filters: { city: visited.items[0].city, minimumVisitCount: 1 },
    })
    expect(filtered.items.every((item) => item.city === visited.items[0].city && item.visitCount >= 1)).toBe(true)
    expect(filtered.scopeCounts).toEqual(visited.scopeCounts)

    const completeFilters = await adapter.map.viewport({
      ...request,
      requestID: 'viewport-complete-filters',
      currentLocation: { latitude: 30.2553, longitude: 120.1637 },
      filters: {
        city: '杭州', scoreBands: [5], minimumVisitCount: 2, diningMode: 'dine_in',
        queueDuration: 'under15', diningOccasions: ['date'], recommendationSourceType: 'friend',
        recommendationSource: '小陈推荐', companion: '小陈', cuisine: '杭帮菜',
        priceRange: 'over200', visitPeriod: 'sixMonths', distanceKilometers: 1,
      },
    })
    expect(completeFilters.items.map((item) => item.name)).toEqual(['湖滨二十八号 · 江南味道'])

    const noVisitFacetMatch = await adapter.map.viewport({
      ...request, requestID: 'viewport-no-facet-match', filters: { diningMode: 'takeout', queueDuration: 'under15' },
    })
    expect(noVisitFacetMatch.items).toEqual([])

    const recommended = await adapter.map.viewport({ ...request, requestID: 'viewport-3', scope: 'recommended' })
    expect(recommended.items).toEqual([])
    expect(recommended.totalCount).toBe(0)
    expect(recommended.scopeCounts).toEqual({ visited: 3, wantToGo: 2, recommended: 0 })
  })

  it('applies every minimum score inclusively, excludes unrated records and restores them on clear', async () => {
    const scores = [null, 1, 2, 3, 4, 5, 6, 7, 7.5, 8, 9, 10]
    const restaurants = scores.map((score, index) => ({
      ...browserProfile.restaurants[0], id: `rating-filter-${index}`, status: 'visited' as const,
      scoreOutOfTen: score, averageRating: score == null ? null : score / 2,
    }))
    const adapter = new TasteMapBrowserAdapter({ profile: async () => ({ ...browserProfile, restaurants }) })
    const request: TasteMapMapBrowseRequest = {
      requestID: 'complete-rating-options', scope: 'visited', filters: {}, sort: 'rating', search: '', limit: 300,
    }
    for (let minimum = 1; minimum <= 10; minimum += 1) {
      const response = await adapter.map.viewport({ ...request, filters: { minimumScoreOutOfTen: minimum } })
      expect(response.items.map((item) => item.scoreOutOfTen)).toEqual(scores.filter((score) => score != null && score >= minimum).reverse())
      expect(response.scopeCounts.visited).toBe(scores.length)
    }
    expect((await adapter.map.viewport(request)).items).toHaveLength(scores.length)
  })

  it('reuses the Browser canonical Restaurant image plan for an existing acquisition match', async () => {
    const existing = {
      ...browserProfile.restaurants[0],
      amapPoiId: 'manual-验收餐厅-杭州-西湖边',
      markerImageData: 'blob:https://example.test/owner-marker',
      markerPhotoId: 'owner-marker-photo',
      merchantImageUrl: 'https://images.example.test/existing-merchant.jpg',
    }
    const existingImage = {
      kind: 'ownerPhoto' as const,
      resourceURL: 'blob:https://example.test/owner-visit',
      photoID: 'owner-visit-photo',
      restaurantID: existing.id,
      visitID: existing.visits[0]?.id ?? null,
      sourceOwnerID: existing.userId,
      visibility: 'private' as const,
      exportAllowed: true,
      attributionRequired: false,
      accessibilityLabel: '已有用户到访照片',
    }
    const profile = {
      ...browserProfile,
      restaurants: [existing],
      restaurantImages: { [existing.id]: existingImage },
    }
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
    const cacheCandidate = Reflect.get(adapter, 'cacheBrowserCandidate') as (
      value: import('../types/domain').PoiSearchResult,
      distance: number | null,
      sourceProfile: TasteMapProfileDashboardViewModel,
    ) => import('./TasteMapPlatform').TasteMapAcquisitionCandidateDTO
    const candidate = cacheCandidate.call(adapter, {
      amapPoiId: existing.amapPoiId,
      name: '验收餐厅',
      address: '西湖边',
      city: '杭州',
      district: '西湖区',
      latitude: 30.25,
      longitude: 120.16,
      categoryHints: ['餐厅'],
      merchantImageUrl: null,
    }, null, profile)

    expect(candidate.existingRestaurantID).toBe(existing.id)
    expect(candidate.duplicateKind).toBe('exactProvider')
    expect(candidate.imageResolution.sources.map((source) => source.kind)).toEqual(['ownerPhoto'])
    expect(candidate.imageResolution.fallback.kind).toBe('foodCategoryVisual')
    expect((await adapter.acquisition.select(candidate.id)).restaurantID).toBe(existing.id)
  })

  it('does not use a persisted Provider image as an automatic avatar', async () => {
    const restaurant = {
      ...browserProfile.restaurants[0],
      markerType: 'image' as const,
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: 'https://images.example.test/merchant-only.jpg',
      visits: [],
      latestVisit: null,
    }
    const adapter = new TasteMapBrowserAdapter({
      profile: async () => ({ ...browserProfile, restaurants: [restaurant], restaurantImages: {} }),
    })

    expect((await adapter.restaurant.get(restaurant.id)).image).toMatchObject({
      kind: 'foodCategoryVisual',
    })
  })
})

describe('TasteMapNativeAdapter', () => {
  function nativeTarget(options: { bridgeVersion?: number; failMethod?: string } = {}) {
    let eventListener: ((event: { sequence: number; name: 'auth.changed'; payload: { state: 'signedOut' } } | Extract<TasteMapHybridEvent, { name: 'map.restaurant.groupSelected' }>) => void) | undefined
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
          scopeCounts: { visited: 3, wantToGo: 2, recommended: 0 },
          options: { cities: ['杭州'], companions: [], cuisines: [], recommendationSources: [] },
        }
      }
      else if (request.method === 'map.surface.update') {
        const payload = request.payload as import('./TasteMapPlatform').TasteMapNativeMapSurfaceUpdateRequest
        result = { requestID: payload.requestID, surface: 'mapkit', persistent: true }
      }
      else if (request.method === 'restaurant.get') {
        const id = (request.payload as { id: string }).id
        const restaurant = fixture.restaurants.find((item) => item.id === id)!
        result = {
          restaurant: bridgeProfile.restaurants.find((item) => item.id === id)!,
          socialStats: {
            overallUserRating: 8.8, overallUserCount: 36,
            friendAverageRating: 9.2, friendUserCount: 8,
            similarTasteAverageRating: 9, similarTasteUserCount: 12,
            repeatVisitRate: 42, repeatVisitorCount: 9, uniqueVisitorCount: 36,
          },
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
      } else if (request.method === 'visit.contract') {
        result = { version: 1, writeUIReady: true }
      } else if (request.method === 'visit.save') {
        const payload = request.payload as TasteMapVisitWriteRequest
        result = { restaurantID: payload.restaurantID, visitID: payload.visitID ?? 'visit-created-1', updatedAt: '2026-09-03T00:00:00.000Z' }
      } else if (request.method === 'visit.delete') {
        result = { restaurantID: fixture.restaurants[0].id, visitID: (request.payload as { visitID: string }).visitID, updatedAt: '2026-09-03T00:00:00.000Z' }
      } else if (request.method === 'community.setLike') {
        result = { likedByViewer: (request.payload as { liked: boolean }).liked, likeCount: 13, commentCount: 2 }
      } else if (request.method === 'community.safety') {
        result = { ownerID: 'other', canReport: true, canBlock: true, canDelete: false }
      } else if (request.method === 'community.report' || request.method === 'community.block' || request.method === 'community.deleteComment') {
        result = { acknowledged: true }
      } else if (request.method === 'community.comments') {
        result = { items: [], nextCursor: null }
      } else if (request.method === 'community.addComment') {
        const payload = request.payload as { target: { visitID: string }; body: string }
        result = {
          likedByViewer: true, likeCount: 13, commentCount: 3,
          comment: { id: 'comment-1', visitID: payload.target.visitID, body: payload.body, author: { id: 'viewer', name: '我', city: '杭州', avatarPhotoID: null, avatarPresetID: 'otter', isFollowing: false }, createdAt: '2026-09-03T00:00:00.000Z' },
        }
      } else if (request.method === 'restaurant.setWantToGo') {
        const payload = request.payload as { restaurantID: string; wanted: boolean }
        result = { restaurantID: payload.restaurantID, viewerState: payload.wanted ? 'want_to_go' : 'none', updatedAt: '2026-09-03T00:00:00.000Z' }
      } else if (request.method === 'restaurant.setAvatar') {
        const payload = request.payload as { restaurantID: string; kind: 'photo' | 'emoji'; emoji?: string }
        result = { restaurantID: payload.restaurantID, markerType: payload.kind === 'photo' ? 'image' : 'emoji', markerEmoji: payload.emoji ?? '🍽️', updatedAt: '2026-09-03T00:00:00.000Z' }
      } else if (request.method === 'photo.pick' || request.method === 'photo.capture') {
        result = { photos: [{
          photoID: 'pending-photo-1',
          preview: { kind: 'nativeResource', resourceURL: 'tastemap-resource://photo-draft/pending-photo-1/thumbnail', photoID: 'pending-photo-1', accessibilityLabel: '待保存的到访照片' },
        }] }
      } else if (request.method === 'acquisition.search' || request.method === 'acquisition.nearby' || request.method === 'acquisition.shared' || request.method === 'acquisition.manual') {
        result = {
          candidates: [{
            id: 'candidate-1', name: '湖滨候选餐厅', address: '平海路 1 号', city: '杭州', district: '上城区',
            latitude: 30.25, longitude: 120.16, distanceMeters: request.method === 'acquisition.nearby' ? 42 : null,
            phone: null, openingHours: null,
            image: { kind: 'providerMerchant', resourceURL: 'https://images.example.test/candidate.jpg', accessibilityLabel: '湖滨候选餐厅餐厅图片' },
            imageResolution: {
              sources: [{ kind: 'providerMerchant', resourceURL: 'https://images.example.test/candidate.jpg', accessibilityLabel: '湖滨候选餐厅餐厅图片' }],
              fallback: { kind: 'foodDiningFallback', stableSeed: 'candidate-1', accessibilityLabel: '湖滨候选餐厅餐厅图片占位' },
            },
            duplicateKind: 'none', existingRestaurantID: null,
          }],
          location: request.method === 'acquisition.nearby'
            ? { latitude: 30.25, longitude: 120.16, timestamp: '2026-09-03T00:00:00.000Z', horizontalAccuracy: 8, accuracyMode: 'full', authorizationStatus: 'allowed' }
            : null,
          detectedCity: request.method === 'acquisition.nearby' ? '杭州市' : null,
          message: null,
          sharedImportFingerprint: request.method === 'acquisition.shared' ? 'share-fingerprint' : null,
        }
      } else if (request.method === 'acquisition.select') {
        result = { restaurantID: 'amap:candidate-1', duplicateKind: 'none', existingRestaurantID: null }
      } else if (request.method === 'premium.status') {
        result = { state: 'free', expiresAt: null }
      } else if (request.method === 'premium.trialEligibility') {
        result = { eligible: true, trialDays: 7 }
      } else if (request.method === 'premium.claimTrial') {
        result = { expiresAt: '2026-09-15T00:00:00Z', status: { state: 'premium', source: 'signup_trial', expiresAt: '2026-09-15T00:00:00Z' } }
      } else if (request.method === 'premium.products') {
        result = [{ id: 'store-product', displayName: '年度会员', valueDescription: '正式商品', displayPrice: '¥88.00', period: 'annual', billingPeriodDescription: '每年续订' }]
      } else if (request.method === 'premium.purchase' || request.method === 'premium.restore') {
        result = { outcome: 'completed', status: { state: 'premium', expiresAt: null } }
      } else if (request.method === 'premium.manage') {
        result = { outcome: 'opened', status: { state: 'premium', expiresAt: null } }
      } else if (request.method === 'sync.status' || request.method === 'sync.run') {
        result = { state: 'idle', pendingMutationCount: 2, pendingPhotoCount: 1, failedPhotoCount: 0, conflictCount: 0, lastSuccessfulSyncAt: null, errorCode: null }
      } else if (request.method === 'permissions.status') {
        result = { location: 'denied', camera: 'notDetermined', photoAddOnly: 'allowed', canOpenSystemSettings: true }
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
    expect(detail.socialStats).toEqual(expect.objectContaining({
      overallUserRating: 8.8,
      friendAverageRating: 9.2,
      similarTasteAverageRating: 9,
    }))
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

  it('keeps private directory edits and picked image bytes behind the typed Native boundary', async () => {
    const { invoke,target }=nativeTarget()
    const adapter=new TasteMapNativeAdapter(target as never)
    const photoID=await adapter.directory.pickAvatar()
    expect(photoID).toBe('pending-photo-1')
    await adapter.directory.dashboard()
    await adapter.directory.searchUsers('Alice')
    await adapter.directory.mutate({kind:'companion',id:'companion-a',action:'avatar',photoID})
    await adapter.directory.respond('request-a','accept')
    const requests=invoke.mock.calls.map(([call])=>call.request)
    expect(requests.map(request=>request.method)).toEqual(expect.arrayContaining(['photo.pick','directory.dashboard','directory.searchUsers','directory.mutate','directory.respond']))
    expect(requests.find(request=>request.method==='directory.mutate')?.payload).toEqual({kind:'companion',id:'companion-a',action:'avatar',photoID:'pending-photo-1'})
    expect(JSON.stringify(requests)).not.toMatch(/base64|file:\/\/|avatarData/)
  })

  it('passes a single versioned viewport request and preserves its request ID', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const response = await adapter.map.viewport({ requestID: 'latest-viewport', scope: 'visited', filters: {}, sort: 'recent', search: '' })
    expect(response.requestID).toBe('latest-viewport')
    expect(response.items.every((item) => item.status === 'visited')).toBe(true)
    expect(invoke.mock.calls.some((call) => call[0].request.method === 'map.viewport')).toBe(true)
  })

  it('updates the persistent Native MapKit surface through a typed presentation-only request', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const response = await adapter.map.updateNativeSurface({
      requestID: 'mapkit-surface-1', visible: true, viewportWidth: 402, viewportHeight: 874,
      frame: { x: 0, y: 168, width: 402, height: 646 }, reactControlExclusions: [],
      scope: 'visited', filters: {}, sort: 'recent', search: '', cameraFitKey: 'initial',
      selectedRestaurantID: null, userAvatarPresetID: 'otter', userAvatarPhotoID: null,
      tasteDataProgress: { displayCount: 7, target: 10, message: '再评分 3 家，推荐和分析会更准确' },
      markers: [],
    })
    expect(response).toEqual({ requestID: 'mapkit-surface-1', surface: 'mapkit', persistent: true })
    const request = invoke.mock.calls.find((call) => call[0].request.method === 'map.surface.update')?.[0].request
    expect(request?.payload).not.toHaveProperty('token')
    expect(request?.payload).not.toHaveProperty('credential')
    expect(request?.payload).toMatchObject({
      tasteDataProgress: { displayCount: 7, target: 10, message: '再评分 3 家，推荐和分析会更准确' },
    })
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
    const groupEvent: Extract<TasteMapHybridEvent, { name: 'map.restaurant.groupSelected' }> = { version: 1, sequence: 2, name: 'map.restaurant.groupSelected', payload: { restaurantIDs: fixture.restaurants.slice(0, 3).map((restaurant) => restaurant.id) } }
    native.emit(groupEvent)
    expect(listener).toHaveBeenLastCalledWith(groupEvent)
    await subscription.remove()
    expect(native.addListener).toHaveBeenCalledWith('event', expect.any(Function))
    expect(native.remove).toHaveBeenCalledOnce()
  })

  it('uses typed Visit save/delete envelopes without embedding owner identity in JavaScript', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const request: TasteMapVisitWriteRequest = {
      restaurantID: fixture.restaurants[0].id,
      visitID: 'visit-owned-1',
      draft: {
        visitedAt: '2026-09-03T00:00:00.000Z', rating: 4.5, visibility: 'private', diningMode: 'dine_in',
        totalPrice: 300, myActualSpend: 150, paymentMode: 'aa', partySize: 2, queueDuration: 'under15',
        diningOccasions: ['friends'], diningOccasionText: '', valueRating: 4.5, environmentRating: 4,
        serviceRating: 4, valueTags: ['值得'], environmentTags: ['安静'], serviceTags: ['周到'],
        noiseLevel: 'quiet', diningDuration: 'under120', portionLevel: 'normal',
        transportConvenience: 'convenient', specialNotes: '', recommendationSourceType: 'friend',
        recommendationSourceUserID: null, recommendationSourceText: '朋友', sharedParticipantUserIDs: [],
        companions: ['小王'], dishes: [{ id: 'dish-1', name: '招牌菜', taste: '鲜', rating: 4.5, price: 88, photoID: null }],
        note: '会再来',
      },
    }
    expect(await adapter.visit.contract()).toEqual({ version: 1, writeUIReady: true })
    expect((await adapter.visit.save(request)).visitID).toBe('visit-owned-1')
    expect((await adapter.visit.delete('visit-owned-1')).visitID).toBe('visit-owned-1')
    expect(invoke).toHaveBeenCalledWith(expect.objectContaining({
      request: expect.objectContaining({
        method: 'visit.save',
        payload: request,
      }),
    }))
    expect(JSON.stringify(invoke.mock.calls)).not.toMatch(/ownerUserID|accessToken|refreshToken|bearer/i)
    invoke.mockClear()
    await adapter.visit.save({ ...request, browserPhotoMaterial: {
      photos: ['data:image/png;base64,browser-only-material'], photoIds: [null], dishPhotos: [],
    } })
    expect(JSON.stringify(invoke.mock.calls)).not.toMatch(/browserPhotoMaterial|browser-only-material|data:image/)
  })

  it('routes Activity identity and viewer-state mutations through dedicated typed methods', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const interaction = {
      activityID: 'activity-1', visitID: 'visit-1', authorID: 'author-1', restaurantID: 'restaurant-1',
    }
    expect(await adapter.community.setLike(interaction, true)).toEqual({ likedByViewer: true, likeCount: 13, commentCount: 2 })
    expect(await adapter.community.comments(interaction)).toEqual({ items: [], nextCursor: null })
    expect((await adapter.community.addComment(interaction, '真不错')).comment).toMatchObject({ visitID: 'visit-1', body: '真不错' })
    const safetyTarget = { type: 'visit' as const, id: 'visit-1' }
    expect(await adapter.community.safety(safetyTarget)).toEqual({ ownerID: 'other', canReport: true, canBlock: true, canDelete: false })
    expect(await adapter.community.report(safetyTarget, 'spam', '', '00000000-0000-4000-8000-000000000001')).toEqual({ acknowledged: true })
    expect(await adapter.community.block(safetyTarget)).toEqual({ acknowledged: true })
    expect(await adapter.community.deleteComment({ type: 'comment', id: 'comment-1' })).toEqual({ acknowledged: true })
    expect((await adapter.restaurant.setWantToGo('restaurant-1', true)).viewerState).toBe('want_to_go')
    expect((await adapter.restaurant.setAvatar('restaurant-1', { kind: 'emoji', emoji: '🍣' })).markerEmoji).toBe('🍣')
    const requests = invoke.mock.calls.map((call) => call[0].request)
    expect(requests).toEqual(expect.arrayContaining([
      expect.objectContaining({ method: 'community.setLike', payload: { target: interaction, liked: true } }),
      expect.objectContaining({ method: 'community.comments', payload: { target: interaction } }),
      expect.objectContaining({ method: 'community.addComment', payload: { target: interaction, body: '真不错' } }),
      expect.objectContaining({ method: 'community.safety', payload: { target: safetyTarget } }),
      expect.objectContaining({ method: 'community.report', payload: { target: safetyTarget, reason: 'spam', details: '', requestID: '00000000-0000-4000-8000-000000000001' } }),
      expect.objectContaining({ method: 'community.block', payload: { target: safetyTarget } }),
      expect.objectContaining({ method: 'community.deleteComment', payload: { target: { type: 'comment', id: 'comment-1' } } }),
      expect.objectContaining({ method: 'restaurant.setWantToGo', payload: { restaurantID: 'restaurant-1', wanted: true } }),
      expect.objectContaining({ method: 'restaurant.setAvatar', payload: { restaurantID: 'restaurant-1', kind: 'emoji', emoji: '🍣' } }),
    ]))
    expect(JSON.stringify(requests)).not.toMatch(/ownerUserID|accessToken|refreshToken|authorization|bearer/i)
  })

  it('uses opaque Native photo descriptors without paths or image bytes', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const picked = await adapter.photo.pick(3)
    const captured = await adapter.photo.capture()
    expect(picked.photos).toEqual([expect.objectContaining({
      photoID: 'pending-photo-1',
      preview: expect.objectContaining({ kind: 'nativeResource' }),
    })])
    expect(captured.photos).toEqual([expect.objectContaining({ photoID: 'pending-photo-1' })])
    await adapter.photo.discard('pending-photo-1')
    await adapter.photo.retry('existing-photo-1')
    expect(invoke).toHaveBeenCalledWith(expect.objectContaining({
      request: expect.objectContaining({ method: 'photo.pick', payload: { selectionLimit: 3 } }),
    }))
    expect(invoke).toHaveBeenCalledWith(expect.objectContaining({
      request: expect.objectContaining({ method: 'photo.capture', payload: {} }),
    }))
    const serialized = JSON.stringify(invoke.mock.calls)
    expect(serialized).not.toMatch(/file:\/\/|\/Users\/|base64|imageData|ownerUserID|bearer/i)
  })

  it('uses typed Restaurant acquisition envelopes and never passes an owner or credential', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    const search = await adapter.acquisition.search('湖滨', '杭州')
    await adapter.acquisition.search('湖滨', '杭州', { cursor: 'opaque-next-page' })
    expect(invoke).toHaveBeenCalledWith(expect.objectContaining({
      request: expect.objectContaining({ method: 'acquisition.search', payload: { query: '湖滨', city: '杭州', cursor: 'opaque-next-page' } }),
    }))
    expect(search.candidates[0].name).toBe('湖滨候选餐厅')
    expect(JSON.stringify(search.candidates[0].imageResolution)).not.toMatch(/file:\/\/|\/Users\/|base64|imageData|credential/i)
    const nearby = await adapter.acquisition.nearby()
    expect(nearby.candidates[0].distanceMeters).toBe(42)
    expect(nearby.detectedCity).toBe('杭州市')
    expect((await adapter.acquisition.shared()).sharedImportFingerprint).toBe('share-fingerprint')
    expect((await adapter.acquisition.manual({ name: '手动餐厅', city: '杭州', address: '西湖边' })).candidates).toHaveLength(1)
    expect((await adapter.acquisition.select('candidate-1', true)).restaurantID).toBe('amap:candidate-1')
    expect(invoke).toHaveBeenCalledWith(expect.objectContaining({
      request: expect.objectContaining({ method: 'acquisition.select', payload: { candidateID: 'candidate-1', confirmProbableMatch: true } }),
    }))
    expect(JSON.stringify(invoke.mock.calls)).not.toMatch(/ownerUserID|accessToken|refreshToken|authorization|bearer|keychain/i)
  })

  it('claims a server trial over distinct bridge methods with no purchase or client authority payload', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    expect(await adapter.premium.trialEligibility()).toEqual({ eligible: true, trialDays: 7 })
    expect((await adapter.premium.claimTrial()).status).toMatchObject({ state: 'premium', source: 'signup_trial' })
    const calls = JSON.stringify(invoke.mock.calls)
    expect(calls).not.toMatch(/premium.purchase|productID|userId|eligible|expiresAt|transaction|trial_claimed_at/)
  })

  it('routes StoreKit, sync, permissions, backup and account actions through typed v1 methods', async () => {
    const { invoke, target } = nativeTarget()
    const adapter = new TasteMapNativeAdapter(target as never)
    expect((await adapter.premium.products())[0]).toMatchObject({ id: 'store-product', displayPrice: '¥88.00' })
    expect((await adapter.premium.purchase('store-product')).status.state).toBe('premium')
    expect((await adapter.premium.restore()).outcome).toBe('completed')
    expect((await adapter.premium.manage()).outcome).toBe('opened')
    expect((await adapter.sync.status()).pendingPhotoCount).toBe(1)
    expect((await adapter.sync.run()).pendingMutationCount).toBe(2)
    expect(await adapter.permissions.status()).toMatchObject({ location: 'denied', camera: 'notDetermined', canOpenSystemSettings: true })
    await adapter.permissions.openSystemSettings()
    await adapter.backup.openExport()
    await adapter.backup.openImport()
    await adapter.account.openDelete()
    const methods = invoke.mock.calls.map((call) => call[0].request.method)
    for (const method of ['premium.products', 'premium.purchase', 'premium.restore', 'premium.manage', 'sync.status', 'sync.run', 'permissions.status', 'permissions.openSettings', 'backup.openExport', 'backup.openImport', 'account.openDelete']) {
      expect(methods).toContain(method)
    }
    expect(JSON.stringify(invoke.mock.calls)).not.toMatch(/ownerUserID|accessToken|refreshToken|authorization|bearer|keychain/i)
  })
})
