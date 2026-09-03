import { db } from '../db/appDb'
import { CURRENT_USER_ID, ensureCurrentUser } from '../db/social'
import { buildRestaurantSummaries } from '../services/restaurantSummaryProjection'
import { addVisit, deleteVisit, updateVisit, type AddVisitInput } from '../db/restaurants'
import type { RestaurantListCollection, RestaurantListItem } from '../types/domain'
import type { RestaurantSummary } from '../types/domain'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  capabilityUnavailable,
  type TasteMapCapabilityRegistry,
  type TasteMapAcquisitionCandidateDTO,
  type TasteMapAcquisitionResultsDTO,
  type TasteMapImageDescriptor,
  type TasteMapMapBrowseRequest,
  type TasteMapMapBrowseResponse,
  type TasteMapPlatform,
  type TasteMapPremiumStatusDTO,
  type TasteMapProfileDashboardViewModel,
  type TasteMapRestaurantDetailViewModel,
  type TasteMapRestaurantListRequest,
  type TasteMapRuntimeInfo,
  type TasteMapVisitWriteDraftDTO,
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
  restaurantAcquisition: true,
  mapBrowse: true,
  contentRead: true,
  visitContract: true,
  sync: false,
  haptics: false,
  share: typeof navigator !== 'undefined' && typeof navigator.share === 'function',
  location: false,
  photoPicker: false,
  premium: true,
  permissions: false,
  nativeNavigation: false,
  backup: false,
  accountDelete: false,
}

export class TasteMapBrowserAdapter implements TasteMapPlatform {
  readonly kind = 'browser' as const
  private profilePromise: Promise<TasteMapProfileDashboardViewModel> | null = null
  private readonly acquisitionCandidates = new Map<string, TasteMapAcquisitionCandidateDTO>()

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
      if (!restaurant) {
        const candidate = this.acquisitionCandidates.get(id)
        if (candidate) return browserCandidateDetail(candidate)
        throw new TasteMapPlatformError(`Restaurant ${id} was not found.`, 'restaurant_not_found')
      }
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

  acquisition = {
    search: async (query: string, city: string): Promise<TasteMapAcquisitionResultsDTO> => {
      const { mapService } = await import('../services/mapService')
      if (!mapService.isConfigured) {
        const fixture = await this.loadDebugFixture()
        if (fixture) {
          const candidates = debugAcquisitionPOIs(city || '杭州')
            .filter((value) => !query.trim() || `${value.name} ${value.address}`.toLocaleLowerCase('zh-CN').includes(query.trim().toLocaleLowerCase('zh-CN')))
            .map((value) => this.cacheBrowserCandidate(value, null, fixture.profile))
          return { candidates, location: null, message: candidates.length ? null : '没有找到匹配的餐厅。', sharedImportFingerprint: null }
        }
        return { candidates: [], location: null, message: '地图服务尚未配置，仍可手动添加。', sharedImportFingerprint: null }
      }
      const profile = await this.loadProfile()
      const candidates = (await mapService.searchRestaurantPois(query, city)).map((value) => this.cacheBrowserCandidate(value, null, profile))
      return { candidates, location: null, message: candidates.length ? null : '没有找到匹配的餐厅。', sharedImportFingerprint: null }
    },
    nearby: async (): Promise<TasteMapAcquisitionResultsDTO> => {
      const { mapService } = await import('../services/mapService')
      if (!mapService.isConfigured) {
        const fixture = await this.loadDebugFixture()
        if (fixture) {
          const candidates = debugAcquisitionPOIs('杭州').map((value, index) =>
            this.cacheBrowserCandidate(value, 180 + index * 260, fixture.profile))
          return { candidates, location: null, message: null, sharedImportFingerprint: null }
        }
        return { candidates: [], location: null, message: '地图服务尚未配置，搜索和手动添加仍可使用。', sharedImportFingerprint: null }
      }
      const profile = await this.loadProfile()
      const coordinates = await mapService.detectCurrentCoordinates()
      const values = await mapService.searchNearbyRestaurantPois(coordinates, undefined, { radiusMeters: 3_000 })
      const candidates = values.map((value) => this.cacheBrowserCandidate(value, distanceBetween(coordinates, value), profile))
        .filter((value) => (value.distanceMeters ?? Number.POSITIVE_INFINITY) <= 3_000)
        .sort((left, right) => (left.distanceMeters ?? Number.POSITIVE_INFINITY) - (right.distanceMeters ?? Number.POSITIVE_INFINITY))
      return { candidates, location: null, message: candidates.length ? null : '3 公里内没有找到餐厅。', sharedImportFingerprint: null }
    },
    shared: async (): Promise<TasteMapAcquisitionResultsDTO> => ({ candidates: [], location: null, message: '浏览器请使用系统分享或正式网页导入入口。', sharedImportFingerprint: null }),
    manual: async (draft: import('./TasteMapPlatform').TasteMapManualRestaurantDraftDTO): Promise<TasteMapAcquisitionResultsDTO> => {
      const { mapService } = await import('../services/mapService')
      const coordinates = draft.latitude != null && draft.longitude != null
        ? { latitude: draft.latitude, longitude: draft.longitude }
        : await mapService.resolveAddressLocation(draft.address, draft.city)
      const candidate = this.cacheBrowserCandidate({
        amapPoiId: `manual-${crypto.randomUUID()}`,
        name: draft.name,
        city: draft.city,
        address: draft.address,
        district: '',
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        merchantImageUrl: null,
        phone: null,
        openingHours: null,
      }, null, await this.loadProfile())
      return { candidates: [candidate], location: null, message: '请确认餐厅信息。', sharedImportFingerprint: null }
    },
    select: async (candidateID: string, confirmProbableMatch = false) => {
      const candidate = this.acquisitionCandidates.get(candidateID)
      if (!candidate) throw new TasteMapPlatformError('餐厅候选已失效，请重新搜索。', 'candidate_not_found', true)
      if (candidate.duplicateKind === 'probableCrossProvider' && !confirmProbableMatch) throw new TasteMapPlatformError('请先确认可能重复的餐厅。', 'probable_match_confirmation_required', true)
      return { restaurantID: candidate.existingRestaurantID ?? candidateID, duplicateKind: candidate.duplicateKind, existingRestaurantID: candidate.existingRestaurantID }
    },
  }

  map = {
    viewport: async (request: TasteMapMapBrowseRequest): Promise<TasteMapMapBrowseResponse> => {
      const debugFixture = await this.loadDebugFixture()
      const profile = debugFixture?.profile ?? await this.loadProfile()
      return projectBrowserMapViewport(profile, request, Boolean(debugFixture))
    },
    updateNativeSurface: async (_request: import('./TasteMapPlatform').TasteMapNativeMapSurfaceUpdateRequest) => capabilityUnavailable('mapBrowse'),
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

  visit = {
    contract: async () => ({ version: 1 as const, writeUIReady: true as const }),
    save: async (request: import('./TasteMapPlatform').TasteMapVisitWriteRequest) => {
      const input = browserVisitInput(request.draft)
      const visit = request.visitID
        ? await updateVisit(request.visitID, input)
        : await addVisit(request.restaurantID, input)
      if (!visit) throw new TasteMapPlatformError('到访记录没有保存成功。', 'visit_save_failed', true)
      this.profilePromise = null
      return { restaurantID: visit.restaurantId, visitID: visit.id, updatedAt: visit.updatedAt }
    },
    delete: async (visitID: string) => {
      const result = await deleteVisit(visitID)
      this.profilePromise = null
      return { restaurantID: result.restaurantId, visitID: result.visitId, updatedAt: result.updatedAt }
    },
  }
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
  photo = {
    pick: async () => capabilityUnavailable('photoPicker'),
    capture: async () => capabilityUnavailable('photoPicker'),
    discard: async () => capabilityUnavailable('photoPicker'),
    retry: async () => capabilityUnavailable('photoPicker'),
  }
  premium = {
    status: async (): Promise<TasteMapPremiumStatusDTO> => ({
      state: (await this.loadProfile()).user.membershipTier === 'member' ? 'premium' : 'free',
      expiresAt: null,
    }),
    products: async () => [],
    purchase: async () => capabilityUnavailable('premium'),
    restore: async () => capabilityUnavailable('premium'),
    manage: async () => capabilityUnavailable('premium'),
  }
  permissions = {
    status: async () => capabilityUnavailable('permissions'),
    openSystemSettings: async () => capabilityUnavailable('permissions'),
  }
  backup = {
    openExport: async () => capabilityUnavailable('backup'),
    openImport: async () => capabilityUnavailable('backup'),
  }
  account = { openDelete: async () => capabilityUnavailable('accountDelete') }
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

  private cacheBrowserCandidate(
    value: import('../types/domain').PoiSearchResult,
    distanceMeters: number | null = null,
    profile?: TasteMapProfileDashboardViewModel,
  ) {
    const id = `browser-candidate-${value.amapPoiId}`
    const existing = profile?.restaurants.find((restaurant) => restaurant.amapPoiId === value.amapPoiId)
    const existingImage = existing ? profile?.restaurantImages[existing.id] ?? browserImageDescriptor(existing) : null
    const sources = [existingImage]
      .filter((image): image is TasteMapImageDescriptor => image != null && image.kind !== 'foodDiningFallback' && image.kind !== 'foodCategoryVisual')
      .filter((image, index, values) => values.findIndex((candidate) => descriptorIdentity(candidate) === descriptorIdentity(image)) === index)
    const fallback = categoryImageDescriptor(value.name, existing?.tags ?? [], existing?.id ?? id)
    const candidate: TasteMapAcquisitionCandidateDTO = {
      id,
      name: value.name,
      address: value.address,
      city: value.city,
      district: value.district,
      latitude: value.latitude,
      longitude: value.longitude,
      distanceMeters,
      phone: value.phone ?? null,
      openingHours: value.openingHours ?? null,
      image: sources[0] ?? fallback,
      imageResolution: { sources, fallback },
      duplicateKind: existing ? 'exactProvider' : 'none',
      existingRestaurantID: existing?.id ?? null,
    }
    this.acquisitionCandidates.set(id, candidate)
    return candidate
  }
}

function descriptorIdentity(image: TasteMapImageDescriptor) {
  if ('resourceURL' in image) return image.resourceURL
  return `${image.kind}:${image.stableSeed}`
}

function browserCandidateDetail(candidate: TasteMapAcquisitionCandidateDTO): TasteMapRestaurantDetailViewModel {
  const now = new Date().toISOString()
  const restaurant: RestaurantSummary = {
    id: candidate.id,
    userId: CURRENT_USER_ID,
    amapPoiId: candidate.id,
    name: candidate.name,
    address: candidate.address,
    city: candidate.city,
    latitude: candidate.latitude,
    longitude: candidate.longitude,
    status: 'wantToGo',
    preferenceLevel: 'normal',
    overallRating: null,
    foodRating: null,
    environmentRating: null,
    serviceRating: null,
    valueRating: null,
    tags: [],
    longTermNote: '',
    pricePerPerson: null,
    phone: candidate.phone,
    openingHours: candidate.openingHours,
    markerType: candidate.image.kind === 'providerMerchant' ? 'image' : 'emoji',
    markerImageData: null,
    markerPhotoId: null,
    merchantImageUrl: candidate.image.kind === 'providerMerchant' ? candidate.image.resourceURL : null,
    markerEmoji: '',
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    visitCount: 0,
    averageRating: null,
    scoreOutOfTen: null,
    latestVisitDate: null,
    latestVisit: null,
    visits: [],
    averagePricePerPerson: null,
    averageQueueMinutes: null,
  }
  return {
    restaurant,
    image: candidate.image,
    viewerState: 'none' as const,
    editableVisitIDs: [],
    capabilities: candidateRestaurantCapabilities(),
  }
}

function distanceBetween(origin: { latitude: number; longitude: number }, target: { latitude: number; longitude: number }) {
  const radians = (value: number) => value * Math.PI / 180
  const latitudeDelta = radians(target.latitude - origin.latitude)
  const longitudeDelta = radians(target.longitude - origin.longitude)
  const a = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(radians(origin.latitude)) * Math.cos(radians(target.latitude)) * Math.sin(longitudeDelta / 2) ** 2
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

function browserVisitInput(draft: TasteMapVisitWriteDraftDTO): AddVisitInput {
  return {
    visitedAt: draft.visitedAt,
    rating: draft.rating as AddVisitInput['rating'],
    visibility: draft.visibility,
    diningMode: draft.diningMode,
    totalPrice: draft.totalPrice,
    myActualSpend: draft.myActualSpend,
    paymentMode: draft.paymentMode,
    partySize: draft.partySize,
    queueDuration: draft.queueDuration ?? 'none',
    diningOccasions: draft.diningOccasions,
    diningOccasion: draft.diningOccasions[0] ?? null,
    diningOccasionText: draft.diningOccasionText,
    valueRating: draft.valueRating as AddVisitInput['valueRating'],
    environmentRating: draft.environmentRating as AddVisitInput['environmentRating'],
    serviceRating: draft.serviceRating as AddVisitInput['serviceRating'],
    valueTags: draft.valueTags,
    environmentTags: draft.environmentTags,
    serviceTags: draft.serviceTags,
    noiseLevel: draft.noiseLevel,
    diningDuration: draft.diningDuration,
    portionLevel: draft.portionLevel,
    transportConvenience: draft.transportConvenience,
    specialNotes: draft.specialNotes,
    recommendationSourceType: draft.recommendationSourceType,
    recommendationSourceUserId: draft.recommendationSourceUserID,
    recommendationSourceText: draft.recommendationSourceText,
    sharedParticipantUserIds: draft.sharedParticipantUserIDs,
    companions: draft.companions,
    dishes: draft.dishes.map((dish) => ({
      id: dish.id,
      name: dish.name,
      taste: dish.taste,
      rating: dish.rating as import('../types/domain').StarRating | null,
      price: dish.price,
      imageData: null,
      photoId: dish.photoID,
    })),
    note: draft.note,
    photos: [],
    photoIds: [],
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

function candidateRestaurantCapabilities() {
  return {
    canEditRestaurant: false,
    canDeleteRestaurant: false,
    canRecordVisit: true,
    canAddToWantToGo: true,
    canAddToList: true,
    canAddToRoulette: false,
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
  includeDebugRecommendations = false,
): TasteMapMapBrowseResponse {
  const all = profile.restaurants
  const options = {
    cities: stableValues(all.map((item) => item.city)),
    companions: stableValues(profile.visits.flatMap((visit) => visit.companions)),
    cuisines: stableValues(all.flatMap((item) => item.tags)),
    recommendationSources: stableValues(profile.visits.map((visit) => visit.recommendationSourceText ?? '')),
  }
  // Shipping Browser data never invents recommendations. The isolated Hybrid
  // Debug fixture alone exposes a deterministic rich recommendation state for
  // visual/performance QA.
  if (request.scope === 'recommended' && !includeDebugRecommendations) return { requestID: request.requestID, items: [], totalCount: 0, options }
  const normalizedSearch = request.search.trim().toLocaleLowerCase()
  const requestedStatus = request.scope === 'wantToGo' ? 'wantToGo' : 'visited'
  const source = request.scope === 'recommended'
    ? [...all].filter((item) => item.status === 'visited').sort((left, right) => (right.scoreOutOfTen ?? -1) - (left.scoreOutOfTen ?? -1) || left.id.localeCompare(right.id)).slice(0, 18)
    : all
  const matches = source.filter((item) => {
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
      environmentTags: visit.environmentTags, serviceTags: visit.serviceTags,
      noiseLevel: visit.noiseLevel, diningDuration: visit.diningDuration, portionLevel: visit.portionLevel,
      transportConvenience: visit.transportConvenience, specialNotes: visit.specialNotes,
      companions: visit.companions, companionIds: visit.companionIds,
      recommendationSourceType: visit.recommendationSourceType,
      recommendationSourceUserId: visit.recommendationSourceUserId,
      recommendationSourceText: visit.recommendationSourceText ?? '', sharedMealId: visit.sharedMealId,
      partySize: visit.partySize, note: visit.note ?? '',
      dishes: visit.dishes.map((dish) => ({ id: dish.id, name: dish.name, taste: dish.taste, rating: dish.rating, price: dish.price, photoID: dish.photoId })),
      photos: visit.photos.map((resourceURL, index) => ({
        kind: 'publicOrCached' as const,
        resourceURL,
        photoID: visit.photoIds[index] ?? '',
        accessibilityLabel: `${restaurant.name} 的用户实拍`,
      })),
      createdAt: visit.createdAt, updatedAt: visit.updatedAt,
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
    visit,
  }))).find((item) => item.resourceURL)
  if (userPhoto) {
    return {
      kind: 'ownerPhoto',
      resourceURL: userPhoto.resourceURL,
      photoID: userPhoto.photoID,
      restaurantID: restaurant.id,
      visitID: userPhoto.visit.id,
      sourceOwnerID: restaurant.userId,
      visibility: userPhoto.visit.visibility,
      exportAllowed: true,
      attributionRequired: false,
      accessibilityLabel: `${restaurant.name} 的用户实拍`,
    }
  }
  if (restaurant.markerImageData) return {
    kind: 'ownerPhoto', resourceURL: restaurant.markerImageData, photoID: restaurant.markerPhotoId ?? '',
    restaurantID: restaurant.id, visitID: null, sourceOwnerID: restaurant.userId, visibility: 'private',
    exportAllowed: true, attributionRequired: false, accessibilityLabel: `${restaurant.name} 的用户实拍`,
  }
  return categoryImageDescriptor(restaurant.name, restaurant.tags, restaurant.id)
}

function categoryImageDescriptor(name: string, tags: readonly string[], stableSeed: string): Extract<TasteMapImageDescriptor, { kind: 'foodCategoryVisual' }> {
  return {
    kind: 'foodCategoryVisual', categoryVisualID: resolveFoodCategoryVisualID({ name, tags }), stableSeed,
    exportAllowed: false, accessibilityLabel: `${name} 餐饮分类图示`,
  }
}

function normalizedLimit(value: number | undefined) {
  if (value === undefined) return Number.MAX_SAFE_INTEGER
  return Math.max(0, Math.min(Math.floor(value), 500))
}

function debugAcquisitionPOIs(city: string): import('../types/domain').PoiSearchResult[] {
  return [
    ['debug-hotpot', '雨巷火锅', '湖滨路 18 号'],
    ['debug-sushi', '青岚寿司', '延安路 66 号'],
    ['debug-noodles', '云边面馆', '平海路 21 号'],
    ['debug-cafe', '桂雨咖啡', '龙翔桥 8 号'],
    ['debug-western', '湖畔西餐', '东坡路 12 号'],
    ['debug-dessert', '月白甜品', '学士路 9 号'],
  ].map(([amapPoiId, name, address], index) => ({
    amapPoiId, name, address, city, district: '上城区',
    latitude: 30.266 + index * 0.001, longitude: 120.155 + index * 0.001,
    merchantImageUrl: null, phone: null, openingHours: null,
  }))
}
