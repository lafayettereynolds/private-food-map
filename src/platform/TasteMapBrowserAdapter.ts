import { db } from '../db/appDb'
import { CURRENT_USER_ID, ensureCurrentUser } from '../db/social'
import { buildRestaurantSummaries } from '../services/restaurantSummaryProjection'
import type { RestaurantSummary } from '../types/domain'
import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  capabilityUnavailable,
  type TasteMapCapabilityRegistry,
  type TasteMapImageDescriptor,
  type TasteMapPlatform,
  type TasteMapPremiumStatusDTO,
  type TasteMapProfileDashboardViewModel,
  type TasteMapRestaurantListRequest,
  type TasteMapRuntimeInfo,
  TasteMapPlatformError,
} from './TasteMapPlatform'

export interface TasteMapBrowserDataSource {
  profile(): Promise<TasteMapProfileDashboardViewModel>
}

class IndexedDBTasteMapDataSource implements TasteMapBrowserDataSource {
  async profile(): Promise<TasteMapProfileDashboardViewModel> {
    const user = await ensureCurrentUser()
    const [restaurants, visits, follows] = await Promise.all([
      db.restaurants.filter((item) => !item.deletedAt && item.userId === CURRENT_USER_ID).toArray(),
      db.visits.filter((item) => !item.deletedAt && item.userId === CURRENT_USER_ID).toArray(),
      db.follows.toArray(),
    ])
    const summaries = buildRestaurantSummaries(restaurants, visits)
    return {
      user,
      restaurants: summaries,
      visits,
      followingCount: follows.filter((item) => item.followerId === CURRENT_USER_ID).length,
      followerCount: follows.filter((item) => item.followedUserId === CURRENT_USER_ID).length,
      restaurantImages: Object.fromEntries(summaries.map((restaurant) => [restaurant.id, browserImageDescriptor(restaurant)])),
    }
  }
}

const browserCapabilities: TasteMapCapabilityRegistry = {
  appleSignIn: false,
  logout: false,
  profileRead: true,
  restaurantRead: true,
  visitContract: true,
  sync: false,
  haptics: false,
  share: typeof navigator !== 'undefined' && typeof navigator.share === 'function',
  location: false,
  photoPicker: false,
  premium: true,
  nativeNavigation: false,
  backup: false,
  accountDelete: false,
}

export class TasteMapBrowserAdapter implements TasteMapPlatform {
  readonly kind = 'browser' as const
  private profilePromise: Promise<TasteMapProfileDashboardViewModel> | null = null

  constructor(private readonly dataSource: TasteMapBrowserDataSource = new IndexedDBTasteMapDataSource()) {}

  runtime = {
    info: async (): Promise<TasteMapRuntimeInfo> => ({
      bridgeVersion: TASTE_MAP_NATIVE_BRIDGE_VERSION,
      platform: 'browser',
      appVersion: 'web',
      build: import.meta.env.MODE,
      dataSource: 'browser-indexeddb',
      localBundle: false,
      offlineCapable: true,
      supportedCapabilities: browserCapabilities,
    }),
  }

  auth = {
    sessionStatus: async () => {
      const profile = await this.loadProfile()
      return { state: 'authenticated' as const, userID: profile.user.id, displayName: profile.user.nickname }
    },
    signInWithApple: async () => capabilityUnavailable('appleSignIn'),
    logout: async () => capabilityUnavailable('logout'),
  }

  profile = { getCurrent: () => this.loadProfile() }

  restaurant = {
    get: async (id: string) => {
      const profile = await this.loadProfile()
      const restaurant = profile.restaurants.find((item) => item.id === id)
      if (!restaurant) throw new TasteMapPlatformError(`Restaurant ${id} was not found.`, 'restaurant_not_found')
      return { restaurant, image: profile.restaurantImages[id] ?? browserImageDescriptor(restaurant) }
    },
    list: async (request: TasteMapRestaurantListRequest = {}) => {
      const profile = await this.loadProfile()
      const ids = request.ids ? new Set(request.ids) : null
      return profile.restaurants
        .filter((item) => (!ids || ids.has(item.id)) && (!request.status || item.status === request.status))
        .slice(0, normalizedLimit(request.limit))
        .map((restaurant) => ({ restaurant, image: profile.restaurantImages[restaurant.id] ?? browserImageDescriptor(restaurant) }))
    },
  }

  visit = { contract: async () => ({ version: 1 as const, writeUIReady: false as const }) }
  sync = {
    status: async () => ({ state: 'unavailable' as const, pendingMutationCount: 0, lastSuccessfulSyncAt: null, errorCode: null }),
    run: async () => capabilityUnavailable('sync'),
  }
  haptics = { selection: async () => undefined }
  share = {
    open: async (payload: { title?: string; text?: string; url?: string }) => {
      if (!navigator.share) capabilityUnavailable('share')
      await navigator.share(payload)
    },
  }
  location = { current: async () => capabilityUnavailable('location') }
  photo = { pick: async () => capabilityUnavailable('photoPicker') }
  premium = {
    status: async (): Promise<TasteMapPremiumStatusDTO> => ({
      state: (await this.loadProfile()).user.membershipTier === 'member' ? 'premium' : 'free',
      expiresAt: null,
    }),
  }
  navigation = {
    openNative: async () => capabilityUnavailable('nativeNavigation'),
    openHybrid: async (route: import('./TasteMapPlatform').TasteMapHybridRoute) => ({ route, owner: 'hybrid' as const, canGoBack: false }),
    back: async () => ({ route: { surface: 'profile' as const }, owner: 'hybrid' as const, canGoBack: false }),
    current: async () => ({ route: { surface: 'profile' as const }, owner: 'hybrid' as const, canGoBack: false }),
  }
  events = { subscribe: async () => ({ remove: async () => undefined }) }

  private loadProfile() {
    this.profilePromise ??= this.dataSource.profile()
    return this.profilePromise
  }
}

function browserImageDescriptor(restaurant: RestaurantSummary): TasteMapImageDescriptor {
  const userPhoto = restaurant.visits.flatMap((visit) => visit.photos.map((resourceURL, index) => ({
    resourceURL,
    photoID: visit.photoIds[index] ?? '',
  }))).find((item) => item.resourceURL)
  if (userPhoto) {
    return {
      kind: 'publicOrCached',
      resourceURL: userPhoto.resourceURL,
      photoID: userPhoto.photoID,
      accessibilityLabel: `${restaurant.name} 的用户实拍`,
    }
  }
  const source = restaurant.markerImageData || restaurant.merchantImageUrl
  if (source) return { kind: 'providerMerchant', resourceURL: source, accessibilityLabel: `${restaurant.name} 餐厅图片` }
  return { kind: 'foodDiningFallback', stableSeed: restaurant.id, accessibilityLabel: `${restaurant.name} 餐饮图示` }
}

function normalizedLimit(value: number | undefined) {
  if (value === undefined) return Number.MAX_SAFE_INTEGER
  return Math.max(0, Math.min(Math.floor(value), 500))
}
