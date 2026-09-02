import { db } from '../db/appDb'
import { CURRENT_USER_ID, ensureCurrentUser } from '../db/social'
import { buildRestaurantSummaries } from '../services/restaurantSummaryProjection'
import type { RestaurantListCollection, RestaurantListItem } from '../types/domain'
import type { RestaurantSummary } from '../types/domain'
import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  capabilityUnavailable,
  type TasteMapCapabilityRegistry,
  type TasteMapImageDescriptor,
  type TasteMapMapBrowseRequest,
  type TasteMapMapBrowseResponse,
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
  mapBrowse: true,
  contentRead: true,
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
      return {
        restaurant,
        image: profile.restaurantImages[id] ?? browserImageDescriptor(restaurant),
        viewerState: restaurant.status === 'visited' ? 'visited' as const : 'want_to_go' as const,
        editableVisitIDs: restaurant.visits.map((visit) => visit.id),
        capabilities: ownedRestaurantCapabilities(),
      }
    },
    list: async (request: TasteMapRestaurantListRequest = {}) => {
      const profile = await this.loadProfile()
      const ids = request.ids ? new Set(request.ids) : null
      return profile.restaurants
        .filter((item) => (!ids || ids.has(item.id)) && (!request.status || item.status === request.status))
        .slice(0, normalizedLimit(request.limit))
        .map((restaurant) => ({
          restaurant,
          image: profile.restaurantImages[restaurant.id] ?? browserImageDescriptor(restaurant),
          viewerState: restaurant.status === 'visited' ? 'visited' as const : 'want_to_go' as const,
          editableVisitIDs: restaurant.visits.map((visit) => visit.id),
          capabilities: ownedRestaurantCapabilities(),
        }))
    },
  }

  map = {
    viewport: async (request: TasteMapMapBrowseRequest): Promise<TasteMapMapBrowseResponse> => {
      const profile = await this.loadProfile()
      return projectBrowserMapViewport(profile, request)
    },
  }

  content = {
    snapshot: async () => {
      const debugFixture = await this.loadDebugFixture()
      if (debugFixture) return debugFixture.content
      const [profile, lists, listItems] = await Promise.all([
        this.loadProfile(),
        db.restaurantLists.filter((value) => !value.deletedAt && value.userId === CURRENT_USER_ID).toArray(),
        db.restaurantListItems.filter((value) => !value.deletedAt).toArray(),
      ])
      return browserContentSnapshot(profile, lists, listItems)
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
    this.profilePromise ??= this.loadDebugFixture().then((fixture) => fixture?.profile ?? this.dataSource.profile())
    return this.profilePromise
  }

  private async loadDebugFixture() {
    if (import.meta.env.VITE_HYBRID_INTERNAL !== 'true') return null
    const { loadTasteMapBrowserDebugFixture } = await import('./TasteMapBrowserDebugFixture')
    return loadTasteMapBrowserDebugFixture()
  }
}

function ownedRestaurantCapabilities() {
  return {
    canEditRestaurant: true,
    canDeleteRestaurant: true,
    canRecordVisit: true,
    canAddToWantToGo: true,
    canAddToList: true,
    canAddToRoulette: true,
    canShare: true,
  } as const
}

function browserContentSnapshot(
  profile: TasteMapProfileDashboardViewModel,
  lists: RestaurantListCollection[],
  listItems: RestaurantListItem[],
): import('./TasteMapPlatform').TasteMapHybridContentSnapshotDTO {
  const restaurants = new Map(profile.restaurants.map((value) => [value.id, value]))
  return {
    generatedAt: new Date().toISOString(),
    discovery: {
      forYou: [],
      similarTaste: [],
      trending: [],
    },
    community: {
      following: [],
      latest: [],
    },
    lists: lists.map((list) => {
      const items = listItems.filter((value) => value.listId === list.id).sort((a, b) => a.position - b.position)
      return {
        id: list.id,
        title: list.title,
        description: list.description,
        visibility: list.visibility,
        isRanked: list.isRanked,
        isOwnedByViewer: true,
        ownerName: profile.user.nickname,
        restaurantCount: items.length,
        restaurants: items.map((item) => {
          const restaurant = restaurants.get(item.restaurantId)
          return {
            id: item.restaurantId,
            name: restaurant?.name ?? '餐厅',
            address: restaurant?.address ?? '',
            city: restaurant?.city ?? '',
            position: item.position,
            note: item.note,
            image: restaurant
              ? profile.restaurantImages[restaurant.id] ?? browserImageDescriptor(restaurant)
              : { kind: 'foodDiningFallback', stableSeed: item.restaurantId, accessibilityLabel: '餐厅图示' },
          }
        }),
        updatedAt: list.updatedAt,
      }
    }),
  }
}

function projectBrowserMapViewport(
  profile: TasteMapProfileDashboardViewModel,
  request: TasteMapMapBrowseRequest,
): TasteMapMapBrowseResponse {
  const all = profile.restaurants
  const options = {
    cities: stableValues(all.map((item) => item.city)),
    companions: stableValues(profile.visits.flatMap((visit) => visit.companions)),
    cuisines: stableValues(all.flatMap((item) => item.tags)),
    recommendationSources: stableValues(profile.visits.map((visit) => visit.recommendationSourceText ?? '')),
  }
  // Personal Map does not invent recommendation records. Discovery remains the
  // authoritative recommendation source until its formal migration.
  if (request.scope === 'recommended') return { requestID: request.requestID, items: [], totalCount: 0, options }
  const normalizedSearch = request.search.trim().toLocaleLowerCase()
  const requestedStatus = request.scope === 'visited' ? 'visited' : 'wantToGo'
  const matches = all.filter((item) => {
    if (item.status !== requestedStatus) return false
    if (request.bounds && !coordinateIsInBounds(item, request.bounds)) return false
    if (request.filters.city && item.city !== request.filters.city) return false
    if (request.filters.minimumScoreOutOfTen && (item.scoreOutOfTen ?? -1) < request.filters.minimumScoreOutOfTen) return false
    if (request.filters.maximumSpend && (item.averagePricePerPerson ?? item.pricePerPerson ?? Number.POSITIVE_INFINITY) > request.filters.maximumSpend) return false
    if (request.filters.minimumVisitCount && item.visitCount < request.filters.minimumVisitCount) return false
    if (request.filters.cuisine && !item.tags.includes(request.filters.cuisine)) return false
    if (request.filters.companion && !item.visits.some((visit) => visit.companions.includes(request.filters.companion!))) return false
    if (request.filters.recommendationSource && !item.visits.some((visit) => visit.recommendationSourceText === request.filters.recommendationSource)) return false
    return !normalizedSearch || [item.name, item.city, item.address, ...item.tags].join('\n').toLocaleLowerCase().includes(normalizedSearch)
  })
  const sorted = [...matches].sort((left, right) => compareMapItems(left, right, request))
  const totalCount = sorted.length
  const items = sorted.slice(0, Math.max(0, Math.min(request.limit ?? 300, 500))).map((restaurant) => {
    const image = profile.restaurantImages[restaurant.id] ?? browserImageDescriptor(restaurant)
    return bridgeDTOFromBrowser(restaurant, image)
  })
  return { requestID: request.requestID, items, totalCount, options }
}

function bridgeDTOFromBrowser(restaurant: RestaurantSummary, image: TasteMapImageDescriptor) {
  return {
    id: restaurant.id, name: restaurant.name, address: restaurant.address, city: restaurant.city,
    latitude: restaurant.latitude, longitude: restaurant.longitude, status: restaurant.status,
    tags: restaurant.tags, phone: restaurant.phone ?? null, openingHours: restaurant.openingHours ?? null,
    referencePrice: restaurant.averagePricePerPerson ?? restaurant.pricePerPerson,
    visitCount: restaurant.visitCount, averageRating: restaurant.averageRating,
    scoreOutOfTen: restaurant.scoreOutOfTen, latestVisitDate: restaurant.latestVisitDate,
    createdAt: restaurant.createdAt, updatedAt: restaurant.updatedAt, visits: restaurant.visits.map((visit) => ({
      id: visit.id, restaurantId: visit.restaurantId, visitedAt: visit.visitedAt, rating: visit.rating,
      valueRating: visit.valueRating, environmentRating: visit.environmentRating, serviceRating: visit.serviceRating,
      myActualSpend: visit.myActualSpend, totalPrice: visit.totalPrice, pricePerPerson: visit.pricePerPerson,
      diningMode: visit.diningMode, visibility: visit.visibility, paymentMode: visit.paymentMode,
      queueDuration: visit.queueDuration, diningOccasions: visit.diningOccasions,
      diningOccasionText: visit.diningOccasionText ?? '', valueTags: visit.valueTags,
      environmentTags: visit.environmentTags, serviceTags: visit.serviceTags, companions: visit.companions,
      companionIds: visit.companionIds, recommendationSourceText: visit.recommendationSourceText ?? '',
      partySize: visit.partySize, note: visit.note ?? '', createdAt: visit.createdAt, updatedAt: visit.updatedAt,
    })), image,
  }
}

function compareMapItems(left: RestaurantSummary, right: RestaurantSummary, request: TasteMapMapBrowseRequest) {
  if (request.sort === 'rating') return (right.scoreOutOfTen ?? -1) - (left.scoreOutOfTen ?? -1) || left.id.localeCompare(right.id)
  if (request.sort === 'visits') return right.visitCount - left.visitCount || left.id.localeCompare(right.id)
  if (request.sort === 'distance' && request.currentLocation) {
    return squaredDistance(left, request.currentLocation) - squaredDistance(right, request.currentLocation) || left.id.localeCompare(right.id)
  }
  return (right.latestVisitDate ?? right.createdAt).localeCompare(left.latestVisitDate ?? left.createdAt) || left.id.localeCompare(right.id)
}

function squaredDistance(value: { latitude: number; longitude: number }, origin: { latitude: number; longitude: number }) {
  return (value.latitude - origin.latitude) ** 2 + (value.longitude - origin.longitude) ** 2
}

function coordinateIsInBounds(value: { latitude: number; longitude: number }, bounds: import('./TasteMapPlatform').TasteMapMapBounds) {
  const longitudeMatch = bounds.west <= bounds.east
    ? value.longitude >= bounds.west && value.longitude <= bounds.east
    : value.longitude >= bounds.west || value.longitude <= bounds.east
  return value.latitude >= bounds.south && value.latitude <= bounds.north && longitudeMatch
}

function stableValues(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))].sort((left, right) => left.localeCompare(right, 'zh-CN'))
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
