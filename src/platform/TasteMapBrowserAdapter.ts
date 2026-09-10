import { db } from '../db/appDb'
import { browserCommunitySafety } from '../services/communitySafetyApi'
import { browserPrivateDirectory } from '../services/privateDirectoryBrowser'
import { MembershipService } from '../services/membershipService'
import { membershipStatusPresentation } from '../services/membershipPresentation'
import { CURRENT_USER_ID, ensureCurrentUser } from '../db/social'
import { buildRestaurantSummaries } from '../services/restaurantSummaryProjection'
import { restaurantCityComparisonKey, restaurantCityFilterOptions } from '../services/restaurantCity'
import { addVisit, deleteRestaurant, deleteVisit, updateRestaurantBasics, updateVisit, type AddVisitInput } from '../db/restaurants'
import type { RestaurantListCollection, RestaurantListItem } from '../types/domain'
import type { RestaurantSummary } from '../types/domain'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import { restaurantAvatarSelection } from '../services/restaurantAvatarSelection'
import { fetchRestaurantSocialStats } from '../services/restaurantStats'
import type { RestaurantSocialStats } from '../types/restaurantStats'
import { listCoordinate, listRating, validatedListShareURL } from './restaurantListProjection'
import { requestRestaurantListAPI, type PublicListPage } from '../services/restaurantListApi'
import { CLOUD_SYNC_ENABLED } from '../config/appEnvironment'
import { BrowserRecommendationPreferenceSync } from '../services/browserRecommendationPreferenceSync'
import { browserRecommendationPreferenceStore } from '../db/recommendationPreferences'
import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  capabilityUnavailable,
  type TasteMapCapabilityRegistry,
  type TasteMapCommunityCommentDTO,
  type TasteMapCommunityEngagementDTO,
  type TasteMapHybridActivityInteractionDTO,
  type TasteMapHybridEvent,
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
    const [restaurants, visits, follows, companions] = await Promise.all([
      db.restaurants.filter((item) => !item.deletedAt && item.userId === CURRENT_USER_ID).toArray(),
      db.visits.filter((item) => !item.deletedAt && item.userId === CURRENT_USER_ID).toArray(),
      db.follows.toArray(),
      db.diningCompanions.where('ownerUserId').equals(CURRENT_USER_ID).toArray().catch(() => null),
    ])
    const summaries = buildRestaurantSummaries(restaurants, visits)
    return {
      user,
      restaurants: summaries,
      visits,
      followingCount: follows.filter((item) => item.followerId === CURRENT_USER_ID).length,
      followerCount: follows.filter((item) => item.followedUserId === CURRENT_USER_ID).length,
      restaurantImages: Object.fromEntries(summaries.map((restaurant) => [restaurant.id, browserImageDescriptor(restaurant)])),
      analyticsIdentity: {
        ownerUserID: user.id, recordOwnerID: CURRENT_USER_ID,
        companions: companions?.map((item) => ({ id: item.id, ownerUserID: user.id, displayName: item.displayName,
          identifiers: [item.id], updatedAt: item.updatedAt, deletedAt: item.deletedAt })) ?? null,
        // Browser v1 has no formal RecommendationSource directory/Visit source-ID association.
        sources: null, visitSourceLinks: null,
      },
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
  listsRead: true,
  listShare: true,
  discoveryPage: false,
  recommendationPreferences: true,
  communityInteraction: true,
  restaurantViewerState: true,
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
  directory = browserPrivateDirectory()
  referrals = { dashboard: async (): Promise<import('../contracts/referralsV1').ReferralDashboardV1> => {
    if (!referralAvailable()) throw new TasteMapPlatformError('邀请功能暂未开放。','capability_unavailable',false)
    const response = await fetch('/api/v1/referrals', {credentials:'same-origin',cache:'no-store'})
    if (!response.ok) throw new TasteMapPlatformError('请在 iPhone App 登录后查看邀请奖励。','auth_required',true)
    return response.json()
  } }
  readonly kind = 'browser' as const
  private profilePromise: Promise<TasteMapProfileDashboardViewModel> | null = null
  private preferenceOwner: string | null = null
  private eventSequence = 0
  private readonly eventListeners = new Set<(event: TasteMapHybridEvent) => void>()
  private readonly acquisitionCandidates = new Map<string, TasteMapAcquisitionCandidateDTO>()
  private acquisitionGPS: { coordinates: { latitude: number; longitude: number }; city: string; acquiredAt: number } | null = null
  private acquisitionNearbyGeneration = 0
  private acquisitionOwner: string | null = null
  private readonly engagement = new Map<string, TasteMapCommunityEngagementDTO>()
  private readonly commentsByVisit = new Map<string, TasteMapCommunityCommentDTO[]>()
  private listSessionRevision = 0
  private readonly listGenerations = new Map<string, number>()
  private readonly listPages = new Map<string, { owner: string; id: string; cursor: string; updatedAt: string; generation: number; expiresAt: number }>()
  private readonly preferenceSync: BrowserRecommendationPreferenceSync
  private disconnectPreferenceLifecycle: (() => void) | null = null

  constructor(private readonly dataSource: TasteMapBrowserDataSource = new IndexedDBTasteMapDataSource(), preferenceSync?: BrowserRecommendationPreferenceSync) {
    this.preferenceSync = preferenceSync ?? new BrowserRecommendationPreferenceSync(browserRecommendationPreferenceStore, requestRestaurantListAPI, ownerID => {
      if (ownerID !== this.preferenceOwner) return
      const event: TasteMapHybridEvent = { version: 1, sequence: ++this.eventSequence, name: 'data.changed', payload: { reason: 'syncCompleted' } }
      this.eventListeners.forEach(listener => listener(event))
    }, () => CLOUD_SYNC_ENABLED)
  }

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

  profile = { getCurrent: () => this.loadProfile(true) }

  recommendations = {
    preference: async (restaurantID?: string) => {
      const requestOwner = this.acquisitionOwner
      const requestRevision = this.listSessionRevision
      const requestProfile = this.loadProfile()
      const profile = await requestProfile
      const groups = profile.restaurants.map(item => [item.id,
        ...(item.placeIdentities ?? []).map(identity => `${identity.provider}:${identity.externalId}`)])
      const restaurant = profile.restaurants.find((_, index) => groups[index].some(id => id.toLowerCase() === restaurantID?.toLowerCase()))
      // Browser recommendations currently originate from this owner snapshot or
      // the explicitly gated QA fixture. Never accept caller-supplied categories.
      const fixture = restaurantID && !restaurant ? await this.loadDebugFixture() : null
      const candidate = restaurant ?? (fixture?.profile.user.id === profile.user.id ? fixture.content.discovery.forYou.find(item => item.restaurant.id === restaurantID)?.restaurant : undefined)
      if (requestProfile !== this.profilePromise || requestRevision !== this.listSessionRevision || (requestOwner !== null && profile.user.id !== requestOwner)) {
        throw new TasteMapPlatformError('账户已切换，请在当前账户重试。', 'account_changed', true)
      }
      if (restaurantID && !candidate) throw new TasteMapPlatformError('餐厅推荐已失效，请刷新后重试。', 'candidate_not_found', true)
      const aliases = restaurant ? groups[profile.restaurants.indexOf(restaurant)] : restaurantID ? [restaurantID] : []
      if (requestProfile === this.profilePromise) this.preferenceOwner = profile.user.id
      this.preferenceSync.setOwner(profile.user.id)
      return this.preferenceSync.preference(profile.user.id, localStorage, groups,
        restaurantID && candidate ? { aliases, metadata: candidate } : undefined,
        () => requestProfile === this.profilePromise && requestRevision === this.listSessionRevision)
    },
  }

  /** The Browser host already observes owner-scoped IndexedDB data. Accept that
   * snapshot once per data change; viewport/pan reads must not requery the DB. */
  acceptProfileSnapshot(profile: Omit<TasteMapProfileDashboardViewModel, 'restaurantImages'>) {
    const previousOwner = this.acquisitionOwner ?? this.preferenceOwner
    const ownerChanged = previousOwner !== null && previousOwner !== profile.user.id
    if (ownerChanged) {
      ++this.listSessionRevision
      this.listPages.clear()
      ++this.acquisitionNearbyGeneration
      this.acquisitionCandidates.clear()
      this.acquisitionGPS = null
    }
    this.acquisitionOwner = profile.user.id
    if (ownerChanged) this.preferenceSync.setOwner(profile.user.id)
    this.profilePromise = Promise.resolve({
      ...profile,
      restaurantImages: Object.fromEntries(profile.restaurants.map((restaurant) => [restaurant.id, browserImageDescriptor(restaurant)])),
    })
    if (ownerChanged) {
      const event: TasteMapHybridEvent = { version: 1, sequence: ++this.eventSequence, name: 'auth.changed', payload: { state: 'authenticated', userID: profile.user.id, displayName: profile.user.nickname } }
      this.eventListeners.forEach(listener => listener(event))
    }
  }

  restaurant = {
    get: async (id: string) => {
      const profile = await this.loadProfile()
      const restaurant = profile.restaurants.find((item) => item.id === id)
      if (!restaurant) {
        const candidate = this.acquisitionCandidates.get(id)
        if (candidate) return browserCandidateDetail(candidate)
        throw new TasteMapPlatformError(`Restaurant ${id} was not found.`, 'restaurant_not_found')
      }
      const debugFixture = await this.loadDebugFixture()
      const socialStats = debugFixture
        ? debugRestaurantSocialStats(restaurant)
        : restaurant.amapPoiId
          ? await fetchRestaurantSocialStats(restaurant.amapPoiId).catch(() => null)
          : null
      return {
        restaurant,
        image: profile.restaurantImages[id] ?? browserImageDescriptor(restaurant),
        socialStats,
        viewerState: restaurant.status === 'visited' ? 'visited' as const : 'want_to_go' as const,
        editableVisitIDs: restaurant.visits.map((visit) => visit.id),
        deletablePhotoIDs: this.dataSource instanceof IndexedDBTasteMapDataSource && !debugFixture
          ? (await db.photos.filter(photo => photo.userId === CURRENT_USER_ID && photo.restaurantId === id && !photo.deletedAt && photo.localState !== 'delete-pending').toArray()).map(photo => photo.id) : [],
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
    setWantToGo: async (restaurantID: string, wanted: boolean) => {
      const debugFixture = await this.loadDebugFixture()
      if (debugFixture) {
        const current = debugViewerState(restaurantID) ?? debugContentViewerState(debugFixture.content, restaurantID)
        const viewerState = current === 'visited' ? 'visited' as const : wanted ? 'want_to_go' as const : 'none' as const
        writeDebugViewerState(restaurantID, viewerState)
        return { restaurantID, viewerState, updatedAt: new Date().toISOString() }
      }
      const value = await db.restaurants.get(restaurantID)
      if (!value || value.deletedAt) throw new TasteMapPlatformError('这家餐厅不在当前账户中。', 'restaurant_not_found', true)
      if (value.status === 'visited') return { restaurantID, viewerState: 'visited' as const, updatedAt: value.updatedAt }
      if (!wanted) {
        await deleteRestaurant(restaurantID)
        this.profilePromise = null
        return { restaurantID, viewerState: 'none' as const, updatedAt: new Date().toISOString() }
      }
      await updateRestaurantBasics(restaurantID, {
        name: value.name, address: value.address, city: value.city, status: 'wantToGo', tags: value.tags,
        pricePerPerson: value.pricePerPerson, phone: value.phone ?? null, openingHours: value.openingHours ?? null,
        markerType: value.markerType, markerImageData: value.markerImageData, markerPhotoId: value.markerPhotoId,
        markerEmoji: value.markerEmoji, latitude: value.latitude, longitude: value.longitude,
      })
      this.profilePromise = null
      return { restaurantID, viewerState: 'want_to_go' as const, updatedAt: new Date().toISOString() }
    },
    setAvatar: async () => capabilityUnavailable('restaurantRead'),
  }

  acquisition = {
    search: async (query: string, city: string, options: import('./TasteMapPlatform').TasteMapAcquisitionSearchOptions = {}): Promise<TasteMapAcquisitionResultsDTO> => {
      const { mapService, rankRestaurantSearchMatches } = await import('../services/mapService')
      if (!mapService.isConfigured) {
        const fixture = await this.loadDebugFixture()
        if (fixture) {
          const candidates = rankRestaurantSearchMatches(debugAcquisitionPOIs(city || '杭州'), query)
            .map((value) => this.cacheBrowserCandidate(value, null, fixture.profile))
          return { candidates, location: null, message: candidates.length ? null : '没有找到匹配的餐厅。', sharedImportFingerprint: null }
        }
        return { candidates: [], location: null, message: '地图服务尚未配置，仍可手动添加。', sharedImportFingerprint: null }
      }
      const profile = await this.loadProfile()
      const page = Number(options.cursor ?? '1')
      if (!Number.isInteger(page) || page < 1 || page > 20) throw new TasteMapPlatformError('搜索已过期，请重新搜索。', 'invalid_search_cursor')
      const { resolveRestaurantSearchLocation } = await import('../services/restaurantSearchLocation')
      const gps = await resolveRestaurantSearchLocation(this.acquisitionGPS, async () => {
        const coordinates = await mapService.detectCurrentCoordinates()
        const acquiredAt = Date.now()
        const locationContext = await mapService.resolveCoordinatesLocation(coordinates).catch(() => null)
        return { coordinates, city: locationContext?.city ?? '', acquiredAt }
      })
      if (gps) this.acquisitionGPS = gps
      const center = gps && (!city.trim() || city.trim().replace(/市$/, '') === gps.city.replace(/市$/, '')) ? gps.coordinates : undefined
      const batches = await Promise.all([
        mapService.searchRestaurantPois(query, city, { page }),
        center ? mapService.searchRestaurantPois(query, city, { page, center, radiusMeters: 3_000 }).catch(() => []) : [],
      ])
      const values = batches.flat().filter((item, index, all) => all.findIndex((other) => other.amapPoiId === item.amapPoiId) === index)
      const candidates = values.map((value) => this.cacheBrowserCandidate(value, center ? distanceBetween(center, value) : null, profile))
      if (center) candidates.sort((a, b) => (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity))
      return { candidates, location: null, nextCursor: batches.some((batch) => batch.length >= 15) && page < 20 ? String(page + 1) : null, message: candidates.length ? null : '没有找到匹配的餐厅。', sharedImportFingerprint: null }
    },
    nearby: async (): Promise<TasteMapAcquisitionResultsDTO> => {
      const generation = ++this.acquisitionNearbyGeneration
      const { mapService } = await import('../services/mapService')
      if (!mapService.isConfigured) {
        const fixture = await this.loadDebugFixture()
        if (fixture) {
          const candidates = debugAcquisitionPOIs('杭州').map((value, index) =>
            this.cacheBrowserCandidate(value, 180 + index * 260, fixture.profile))
          return { candidates, location: null, detectedCity: '杭州', message: null, sharedImportFingerprint: null }
        }
        return { candidates: [], location: null, message: '地图服务尚未配置，搜索和手动添加仍可使用。', sharedImportFingerprint: null }
      }
      const profile = await this.loadProfile()
      const owner = profile.user.id
      this.acquisitionOwner ??= owner
      const ensureCurrent = async () => {
        const currentProfile = await this.loadProfile()
        if (generation !== this.acquisitionNearbyGeneration || currentProfile.user.id !== owner) {
          throw new TasteMapPlatformError('附近结果已更新，请重新查找。', 'nearby_request_superseded', true)
        }
      }
      await ensureCurrent()
      const coordinates = await mapService.detectCurrentCoordinates()
      await ensureCurrent()
      const acquiredAt = Date.now()
      const [values, locationContext] = await Promise.all([
        mapService.searchNearbyRestaurantPois(coordinates, undefined, { radiusMeters: 3_000 }),
        mapService.resolveCoordinatesLocation(coordinates).catch(() => null),
      ])
      await ensureCurrent()
      this.acquisitionGPS = { coordinates, city: locationContext?.city ?? '', acquiredAt }
      const candidates = values.filter((value, index, all) => all.findIndex((other) => other.amapPoiId === value.amapPoiId) === index)
        .map((value) => this.cacheBrowserCandidate(value, distanceBetween(coordinates, value), profile))
        .filter((value) => (value.distanceMeters ?? Number.POSITIVE_INFINITY) <= 3_000)
        .sort((left, right) => (left.distanceMeters ?? Number.POSITIVE_INFINITY) - (right.distanceMeters ?? Number.POSITIVE_INFINITY))
      return { candidates, location: null, detectedCity: locationContext?.city ?? null, message: candidates.length ? null : '3 公里内没有找到餐厅。', sharedImportFingerprint: null }
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
        categoryHints: [],
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
      if (request.filters.companion || request.filters.recommendationSource || request.filters.recommendationSourceType) {
        if ((await this.premium.status()).state !== 'premium') throw new TasteMapPlatformError('推荐来源和饭搭子筛选需要 Premium。', 'premium_filters_required')
      }
      const debugFixture = await this.loadDebugFixture()
      const profile = debugFixture?.profile ?? await this.loadProfile()
      return projectBrowserMapViewport(profile, request, Boolean(debugFixture))
    },
    updateNativeSurface: async () => capabilityUnavailable('mapBrowse'),
  }

  // The browser's legacy local social mutations are not an authoritative page
  // producer. Fail closed until real page authentication AND interactions exist.
  discovery = {
    cityPage: async (_request: import('./TasteMapPlatform').TasteMapDiscoveryCityPageRequest): Promise<import('./TasteMapPlatform').TasteMapDiscoveryCityPageDTO> => {
      throw new TasteMapPlatformError('当前浏览器尚未连接真实城市发现查询，请使用已更新的 App。', 'capability_unavailable')
    },
    page: async (_request: import('./TasteMapPlatform').TasteMapDiscoveryPageRequest): Promise<import('./TasteMapPlatform').TasteMapDiscoveryPageDTO> => {
      throw new TasteMapPlatformError('Server-scoped Discovery pages are not connected in this browser runtime.', 'capability_unavailable')
    },
  }

  content = {
    snapshot: async (options: import('./TasteMapPlatform').TasteMapContentSnapshotOptions = {}) => {
      const debugFixture = await this.loadDebugFixture()
      if (debugFixture) return applyDebugViewerStates(debugFixture.content)
      const [profile, lists, listItems] = await Promise.all([
        this.loadProfile(options.forceRefresh === true),
        db.restaurantLists.filter((value) => !value.deletedAt && value.userId === CURRENT_USER_ID).toArray(),
        db.restaurantListItems.filter((value) => !value.deletedAt).toArray(),
      ])
      return browserContentSnapshot(profile, lists, listItems)
    },
  }

  lists = {
    get: async (request: import('./TasteMapPlatform').TasteMapListGetRequest): Promise<import('./TasteMapPlatform').TasteMapListPageDTO> => {
      this.validateListID(request.id)
      const profile = await this.loadProfile(true)
      const owner = profile.user.id
      const session = this.listSessionRevision
      const continuation = request.cursor ? this.listPages.get(request.cursor) : undefined
      if (request.cursor) {
        this.listPages.delete(request.cursor)
        if (!continuation || continuation.id !== request.id || continuation.owner !== owner
          || continuation.expiresAt < Date.now() || continuation.generation !== this.listGenerations.get(request.id)) {
          throw new TasteMapPlatformError('食单分页已失效，请重新读取。', 'list_cursor_expired', true)
        }
      } else {
        this.listGenerations.set(request.id, (this.listGenerations.get(request.id) ?? 0) + 1)
        for (const [token, page] of this.listPages) {
          if (page.id === request.id || page.expiresAt < Date.now()) this.listPages.delete(token)
        }
      }
      const generation = this.listGenerations.get(request.id)
      const assertCurrent = async () => {
        if (session !== this.listSessionRevision || (await this.loadProfile()).user.id !== owner
          || this.listGenerations.get(request.id) !== generation) {
          throw new TasteMapPlatformError('账户或食单已变化，请重新读取。', 'list_request_superseded', true)
        }
      }
      const fixture = await this.loadDebugFixture()
      const fixtureList = fixture?.content.lists.find(value => value.id === request.id)
      if (fixtureList && !request.cursor) {
        await assertCurrent()
        return { list: fixtureList, nextCursor: null, generatedAt: fixture!.content.generatedAt }
      }
      const own = await db.restaurantLists.get(request.id)
      if (own?.userId === CURRENT_USER_ID && own.deletedAt) {
        throw new TasteMapPlatformError('这份食单已删除。', 'list_unavailable', true)
      }
      if (own?.userId === CURRENT_USER_ID && !own.deletedAt && !request.cursor) {
        const items = await db.restaurantListItems.where('listId').equals(own.id).filter(value => !value.deletedAt).toArray()
        await assertCurrent()
        return { list: browserContentSnapshot(profile, [own], items).lists[0], nextCursor: null, generatedAt: new Date().toISOString() }
      }
      const query = new URLSearchParams({ limit: '50', ...(continuation ? { cursor: continuation.cursor } : {}) })
      const page = await requestRestaurantListAPI<PublicListPage>(`/api/v1/lists/${encodeURIComponent(request.id)}?${query}`)
      await assertCurrent()
      if (page.apiVersion !== 1 || page.list?.id !== request.id || !Array.isArray(page.items)
        || !Number.isInteger(page.list.restaurantCount) || page.list.restaurantCount < 0) {
        throw new TasteMapPlatformError('食单服务返回的数据无效。', 'invalid_list_response', true)
      }
      if (continuation && continuation.updatedAt !== page.list.updatedAt) {
        throw new TasteMapPlatformError('食单已更新，请重新读取后继续。', 'list_changed', true)
      }
      if (continuation && page.nextCursor === continuation.cursor) {
        throw new TasteMapPlatformError('食单服务返回了重复分页，请重新读取。', 'invalid_list_response', true)
      }
      const nextCursor = page.nextCursor ? crypto.randomUUID() : null
      if (nextCursor) this.listPages.set(nextCursor, {
        owner, id: request.id, cursor: page.nextCursor!, updatedAt: page.list.updatedAt,
        generation: generation!, expiresAt: Date.now() + 300_000,
      })
      return { list: browserPublicListProjection(page, profile), nextCursor, generatedAt: page.generatedAt }
    },
    createShareLink: async (id: string) => {
      this.validateListID(id)
      const owner = (await this.loadProfile()).user.id
      const session = this.listSessionRevision
      const list = await db.restaurantLists.get(id)
      if (!list || list.deletedAt || list.userId !== CURRENT_USER_ID) {
        throw new TasteMapPlatformError('只能为自己的公开食单生成分享链接。', 'list_share_not_owned', true)
      }
      if (list.visibility !== 'public') throw new TasteMapPlatformError('这份食单尚未公开；不会自动修改可见范围。', 'list_share_not_public', true)
      const result = await requestRestaurantListAPI<{ apiVersion: number; entityType: string; url: string }>('/api/v1/public-shares', { entityType: 'list', entityId: id })
      const latest = await db.restaurantLists.get(id)
      if (session !== this.listSessionRevision || (await this.loadProfile()).user.id !== owner
        || !latest || latest.deletedAt || latest.visibility !== 'public' || latest.userId !== CURRENT_USER_ID) {
        throw new TasteMapPlatformError('账户或食单已变化，请重新生成链接。', 'list_share_superseded', true)
      }
      if (result.apiVersion !== 1 || result.entityType !== 'list') throw new TasteMapPlatformError('分享服务返回的数据无效。', 'invalid_list_share', true)
      return { url: validatedListShareURL(result.url) }
    },
  }

  private validateListID(id: string) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw new TasteMapPlatformError('食单标识无效。', 'invalid_list_id')
  }

  community = {
    ...browserCommunitySafety,
    setLike: async (target: TasteMapHybridActivityInteractionDTO, liked: boolean) => {
      const current = await this.engagementFor(target.visitID)
      const next = {
        likedByViewer: liked,
        likeCount: Math.max(0, current.likeCount + (liked === current.likedByViewer ? 0 : liked ? 1 : -1)),
        commentCount: current.commentCount,
      }
      this.engagement.set(target.visitID, next)
      return next
    },
    comments: async (target: TasteMapHybridActivityInteractionDTO) => ({
      items: await this.commentsFor(target.visitID),
      nextCursor: null,
    }),
    addComment: async (target: TasteMapHybridActivityInteractionDTO, body: string) => {
      const trimmed = body.trim()
      if (!trimmed || trimmed.length > 280) throw new TasteMapPlatformError('评论内容无效。', 'invalid_comment', true)
      const profile = await this.loadProfile()
      const comment: TasteMapCommunityCommentDTO = {
        id: crypto.randomUUID(), visitID: target.visitID, body: trimmed,
        author: {
          id: profile.user.id, name: profile.user.nickname, city: profile.user.city,
          avatarPhotoID: profile.user.avatarPhotoId, avatarPresetID: profile.user.avatarPresetId,
          isFollowing: false,
        },
        createdAt: new Date().toISOString(),
      }
      const values = [...await this.commentsFor(target.visitID), comment]
      this.commentsByVisit.set(target.visitID, values)
      const current = await this.engagementFor(target.visitID)
      const next = { ...current, commentCount: current.commentCount + 1 }
      this.engagement.set(target.visitID, next)
      return { ...next, comment }
    },
  }

  visit = {
    contract: async () => ({ version: 1 as const, writeUIReady: true as const }),
    save: async (request: import('./TasteMapPlatform').TasteMapVisitWriteRequest) => {
      const input = browserVisitInput(request.draft)
      const existing = request.visitID ? await db.visits.get(request.visitID) : undefined
      const material = request.browserPhotoMaterial
      input.photos = material?.photos ?? existing?.photos ?? []
      input.photoIds = material?.photoIds ?? existing?.photoIds ?? []
      input.dishes = input.dishes.map((dish) => ({ ...dish,
        imageData: material
          ? material.dishPhotos.find((photo) => photo.id === dish.id)?.imageData ?? null
          : existing?.dishes.find((value) => value.id === dish.id)?.imageData ?? null,
      }))
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
      return { restaurantID: result.restaurantId, visitID: result.visitId, updatedAt: result.updatedAt, deletedRestaurantID: result.deletedRestaurantID }
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
    discard: async (photoID: string) => {
      // Build-time boundary: Drive/Browser credentials must never enter the
      // signed Hybrid bundle. Its native adapter owns persisted photo deletion.
      if (import.meta.env.VITE_HYBRID_SHELL === 'true') throw new Error('iOS 照片删除需要 Native 平台。')
      await (await import('../services/photoSync')).deleteOwnPhoto(photoID)
      this.profilePromise = null
    },
    retry: async () => capabilityUnavailable('photoPicker'),
  }
  premium = {
    trialEligibility: async (): Promise<{ eligible: boolean; trialDays: number }> => {
      const response = await fetch('/api/v1/me/premium-trial-eligibility', { credentials: 'same-origin', cache: 'no-store' })
      if (!response.ok) throw new TasteMapPlatformError('请登录后重试。', 'auth_required')
      return response.json()
    },
    claimTrial: async () => {
      const response = await fetch('/api/v1/me/premium-trial/claim', { method: 'POST', credentials: 'same-origin', cache: 'no-store' })
      const result = await response.json() as { expiresAt: string; error?: string }
      if (!response.ok) throw new Error(result.error ?? '领取暂时无法完成。')
      return { expiresAt: result.expiresAt, status: await this.premium.status() }
    },
    status: async (): Promise<TasteMapPremiumStatusDTO> => {
      const { entitlement } = await MembershipService.getEntitlement()
      const presentation = membershipStatusPresentation(entitlement, 'free')
      return { state: entitlement.isPremium ? 'premium' : 'free', expiresAt: entitlement.expiresAt,
        source: entitlement.source, startedAt: entitlement.startsAt,
        statusText: entitlement.source === 'gift_annual' || entitlement.source === 'gift_lifetime' || entitlement.source === 'referral_reward' || entitlement.source === 'signup_trial' ? presentation.planLabel : null,
        canManageSubscription: entitlement.isPremium && presentation.canManageAppStoreSubscription }
    },
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
  events = { subscribe: async (listener: (event: TasteMapHybridEvent) => void) => {
    this.disconnectPreferenceLifecycle ??= this.preferenceSync.connectLifecycle()
    this.eventListeners.add(listener)
    return { remove: async () => {
      this.eventListeners.delete(listener)
      if (!this.eventListeners.size) { this.disconnectPreferenceLifecycle?.(); this.disconnectPreferenceLifecycle = null }
    } }
  } }

  private loadProfile(refresh = false) {
    if (refresh) this.profilePromise = null
    this.profilePromise ??= this.loadDebugFixture().then((fixture) => fixture?.profile ?? this.dataSource.profile())
    return this.profilePromise
  }

  private async loadDebugFixture() {
    const explicitFixture = typeof window !== 'undefined'
      && new URLSearchParams(window.location.search).get('debugFixture') === 'rich'
    if (import.meta.env.VITE_HYBRID_INTERNAL !== 'true' || !explicitFixture) return null
    const { loadTasteMapBrowserDebugFixture } = await import('./TasteMapBrowserDebugFixture')
    return loadTasteMapBrowserDebugFixture()
  }

  private async engagementFor(visitID: string) {
    const stored = this.engagement.get(visitID)
    if (stored) return stored
    const fixture = await this.loadDebugFixture()
    const values = fixture ? [
      ...fixture.content.discovery.forYou,
      ...fixture.content.discovery.similarTaste,
      ...fixture.content.discovery.trending,
      ...fixture.content.community.following,
      ...fixture.content.community.latest,
    ] : []
    const item = values.find((value) => value.interaction?.visitID === visitID)
    const initial = item ? {
      likedByViewer: item.likedByViewer,
      likeCount: item.likeCount,
      commentCount: item.commentCount,
    } : { likedByViewer: false, likeCount: 0, commentCount: 0 }
    this.engagement.set(visitID, initial)
    return initial
  }

  private async commentsFor(visitID: string) {
    const stored = this.commentsByVisit.get(visitID)
    if (stored) return stored
    const fixture = await this.loadDebugFixture()
    const initial = [...(fixture?.commentsByVisit[visitID] ?? [])]
    this.commentsByVisit.set(visitID, initial)
    return initial
  }

  private cacheBrowserCandidate(
    value: import('../types/domain').PoiSearchResult,
    distanceMeters: number | null = null,
    profile?: TasteMapProfileDashboardViewModel,
  ) {
    const id = `browser-candidate-${value.amapPoiId}`
    const existing = profile?.restaurants.find((restaurant) => restaurant.amapPoiId === value.amapPoiId)
    const existingImage = existing ? profile?.restaurantImages[existing.id] ?? browserImageDescriptor(existing) : null
    const providerImage: TasteMapImageDescriptor | null = value.merchantImageUrl ? {
      kind: 'providerMerchant',
      resourceURL: value.merchantImageUrl,
      accessibilityLabel: `${value.name} 商家图片`,
    } : null
    const sources = [existingImage, providerImage]
      .filter((image): image is TasteMapImageDescriptor => image != null && image.kind !== 'foodDiningFallback' && image.kind !== 'foodCategoryVisual')
      .filter((image, index, values) => values.findIndex((candidate) => descriptorIdentity(candidate) === descriptorIdentity(image)) === index)
    const categoryHints = stableValues([...(existing?.tags ?? []), ...value.categoryHints])
    const fallback = categoryImageDescriptor(value.name, categoryHints, existing?.id ?? id)
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
      websiteUrl: value.websiteUrl ?? null,
      openingHours: value.openingHours ?? null,
      categoryHints,
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
    tags: candidate.categoryHints ?? [],
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
    socialStats: null,
    viewerState: 'none' as const,
    editableVisitIDs: [],
    capabilities: candidateRestaurantCapabilities(),
  }
}

/** Rich Demo proof data only. Production Browser values come from the official stats API. */
export function debugRestaurantSocialStats(restaurant: RestaurantSummary): RestaurantSocialStats {
  const seed = [...restaurant.id].reduce((value, character) => value + character.charCodeAt(0), 0)
  return {
    overallUserRating: 8.3 + (seed % 5) * 0.1,
    overallUserCount: 24 + seed % 17,
    friendAverageRating: 9.1 + (seed % 4) * 0.1,
    friendUserCount: 7 + seed % 6,
    similarTasteAverageRating: 8.8 + (seed % 3) * 0.1,
    similarTasteUserCount: 11 + seed % 8,
    repeatVisitRate: 32 + seed % 29,
    repeatVisitorCount: 6 + seed % 7,
    uniqueVisitorCount: 24 + seed % 17,
  }
}

const debugViewerStateKey = 'tastemap.hybrid.debug.viewer-state.v1'

function readDebugViewerStates(): Record<string, 'none' | 'want_to_go' | 'visited'> {
  if (typeof localStorage === 'undefined') return {}
  try { return JSON.parse(localStorage.getItem(debugViewerStateKey) ?? '{}') as Record<string, 'none' | 'want_to_go' | 'visited'> }
  catch { return {} }
}

function debugViewerState(restaurantID: string) {
  return readDebugViewerStates()[restaurantID]
}

function writeDebugViewerState(restaurantID: string, state: 'none' | 'want_to_go' | 'visited') {
  if (typeof localStorage === 'undefined') return
  localStorage.setItem(debugViewerStateKey, JSON.stringify({ ...readDebugViewerStates(), [restaurantID]: state }))
}

function debugContentViewerState(content: import('./TasteMapPlatform').TasteMapHybridContentSnapshotDTO, restaurantID: string) {
  const items = [
    ...content.discovery.forYou, ...content.discovery.similarTaste, ...content.discovery.trending,
    ...content.community.following, ...content.community.latest,
  ]
  return items.find((item) => item.restaurant.id === restaurantID)?.viewerState ?? 'none'
}

function applyDebugViewerStates(content: import('./TasteMapPlatform').TasteMapHybridContentSnapshotDTO) {
  const states = readDebugViewerStates()
  const copy = structuredClone(content)
  const groups = [
    copy.discovery.forYou, copy.discovery.similarTaste, copy.discovery.trending,
    copy.community.following, copy.community.latest,
  ]
  for (const group of groups) {
    for (const item of group) item.viewerState = states[item.restaurant.id] ?? item.viewerState
  }
  return copy
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
            coordinate: listCoordinate(restaurant?.latitude, restaurant?.longitude),
            rating: restaurant && restaurant.userId === profile.user.id
              ? listRating(restaurant.scoreOutOfTen, 'viewer', restaurant.visits.filter(visit => visit.rating != null && visit.rating > 0 && visit.rating <= 5).length)
              : null,
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

function browserPublicListProjection(page: PublicListPage, profile: TasteMapProfileDashboardViewModel): import('./TasteMapPlatform').TasteMapHybridListDTO {
  return {
    id: page.list.id, title: page.list.title, description: page.list.description,
    visibility: page.list.visibility, isRanked: page.list.isRanked,
    restaurantCount: page.list.restaurantCount, updatedAt: page.list.updatedAt,
    isOwnedByViewer: page.list.owner.userId === profile.user.id,
    ownerName: page.list.owner.displayName,
    restaurants: page.items.map(item => {
      const place = item.restaurant
      const own = profile.restaurants.find(value => value.userId === profile.user.id && value.id.toLowerCase() === place.restaurantId.toLowerCase())
      return {
        id: place.restaurantId, name: place.name, address: place.address, city: place.city,
        position: item.position, note: item.note,
        coordinate: listCoordinate(place.latitude, place.longitude),
        // This API has no public aggregate field; do not borrow a private author score.
        rating: own ? listRating(own.scoreOutOfTen, 'viewer', own.visits.filter(visit => visit.rating != null && visit.rating > 0 && visit.rating <= 5).length) : null,
        image: own ? profile.restaurantImages[own.id] ?? browserImageDescriptor(own)
          : publicListBrowserImage(place),
      }
    }).sort((a, b) => a.position - b.position || a.id.localeCompare(b.id)),
  }
}

function publicListBrowserImage(place: PublicListPage['items'][number]['restaurant']): TasteMapImageDescriptor {
  // Preserve a real API-supplied image; this does not issue provider/photo queries.
  try {
    const url = new URL(place.merchantImageUrl ?? '')
    if (url.protocol === 'https:' && !url.username && !url.password) {
      return { kind: 'providerMerchant', resourceURL: url.href, accessibilityLabel: `${place.name} 餐厅图片` }
    }
  } catch { /* Missing real image uses the canonical deterministic fallback. */ }
  return { kind: 'foodDiningFallback', stableSeed: place.globalKey, accessibilityLabel: `${place.name} 餐饮图示` }
}

function projectBrowserMapViewport(
  profile: TasteMapProfileDashboardViewModel,
  request: TasteMapMapBrowseRequest,
  includeDebugRecommendations = false,
): TasteMapMapBrowseResponse {
  const all = profile.restaurants.filter((item) => !item.deletedAt && item.userId === profile.user.id
    && (item.status !== 'visited' || item.visitCount > 0))
  const normalizedSearch = request.search.trim().toLocaleLowerCase()
  const sourceFor = (scope: TasteMapMapBrowseRequest['scope']) => {
    // Shipping Browser data never invents recommendations. The isolated
    // Hybrid Debug fixture alone exposes a deterministic rich recommendation
    // state for visual/performance QA.
    if (scope !== 'recommended') return all
    if (!includeDebugRecommendations) return []
    return [...all]
      .filter((item) => item.status === 'visited')
      .sort((left, right) => (right.scoreOutOfTen ?? -1) - (left.scoreOutOfTen ?? -1) || left.id.localeCompare(right.id))
      .slice(0, 18)
  }
  const matchesScope = (scope: TasteMapMapBrowseRequest['scope'], includeBounds: boolean) => sourceFor(scope).filter((item) => {
    const requestedStatus = scope === 'wantToGo' ? 'wantToGo' : 'visited'
    if (item.status !== requestedStatus) return false
    if (includeBounds && request.bounds && !coordinateIsInBounds(item, request.bounds)) return false
    if (request.filters.city && restaurantCityComparisonKey(item.city) !== restaurantCityComparisonKey(request.filters.city)) return false
    if (request.filters.minimumScoreOutOfTen && (item.scoreOutOfTen ?? -1) < request.filters.minimumScoreOutOfTen) return false
    if (request.filters.scoreBands?.length) {
      const band = mapScoreBand(item.scoreOutOfTen)
      if (band == null || !request.filters.scoreBands.includes(band)) return false
    }
    if (request.filters.maximumSpend && (item.averagePricePerPerson ?? item.pricePerPerson ?? Number.POSITIVE_INFINITY) > request.filters.maximumSpend) return false
    if (request.filters.cuisine && !item.tags.includes(request.filters.cuisine)) return false
    if (request.filters.distanceKilometers) {
      if (!request.currentLocation || distanceBetween(request.currentLocation, item) > request.filters.distanceKilometers * 1_000) return false
    }
    if (scope !== 'wantToGo') {
      if (request.filters.minimumVisitCount && item.visitCount < request.filters.minimumVisitCount) return false
      if (hasVisitScopedMapFilters(request.filters) && !item.visits.some((visit) => visitMatchesMapFilters(visit, request.filters))) return false
    }
    return !normalizedSearch || [item.name, item.city, item.address, ...item.tags].join('\n').toLocaleLowerCase().includes(normalizedSearch)
  })
  const scopeTotal = (scope: TasteMapMapBrowseRequest['scope']) => {
    const requestedStatus = scope === 'wantToGo' ? 'wantToGo' : 'visited'
    return sourceFor(scope).filter((item) => item.status === requestedStatus).length
  }
  // Options belong to the full selected scope, before city/search/viewport
  // filters. Selecting one city must not hide the other valid cities.
  const citySource = sourceFor(request.scope).filter((item) => item.status === (request.scope === 'wantToGo' ? 'wantToGo' : 'visited'))
  const options = {
    cities: restaurantCityFilterOptions(citySource.map((item) => item.city)),
    companions: stableValues(profile.visits.flatMap((visit) => visit.companions)),
    cuisines: stableValues(all.flatMap((item) => item.tags)),
    recommendationSources: stableValues(profile.visits.map((visit) => visit.recommendationSourceText ?? '')),
  }
  const scopeCounts = {
    visited: scopeTotal('visited'),
    wantToGo: scopeTotal('wantToGo'),
    recommended: scopeTotal('recommended'),
  }
  const matches = matchesScope(request.scope, true)
  const sorted = [...matches].sort((left, right) => compareMapItems(left, right, request))
  const totalCount = sorted.length
  const items = sorted.slice(0, Math.max(0, Math.min(request.limit ?? 300, 500))).map((restaurant) => {
    const image = profile.restaurantImages[restaurant.id] ?? browserImageDescriptor(restaurant)
    return bridgeDTOFromBrowser(restaurant, image)
  })
  return { requestID: request.requestID, items, totalCount, scopeCounts, options }
}

function mapScoreBand(score: number | null): 1 | 2 | 3 | 4 | 5 | null {
  if (score == null || !Number.isFinite(score)) return null
  if (score >= 9) return 5
  if (score >= 7) return 4
  if (score >= 5) return 3
  if (score >= 3) return 2
  return 1
}

function hasVisitScopedMapFilters(filters: TasteMapMapBrowseRequest['filters']) {
  return Boolean(
    filters.diningMode
    || filters.queueDuration
    || filters.diningOccasions?.length
    || filters.recommendationSourceType
    || filters.recommendationSource
    || filters.priceRange
    || filters.visitPeriod
    || filters.companion,
  )
}

function visitMatchesMapFilters(
  visit: RestaurantSummary['visits'][number],
  filters: TasteMapMapBrowseRequest['filters'],
) {
  if (filters.diningMode && visit.diningMode !== filters.diningMode) return false
  if (filters.queueDuration === 'unrecorded' ? visit.queueDuration != null : filters.queueDuration && visit.queueDuration !== filters.queueDuration) return false
  if (filters.diningOccasions?.length && !filters.diningOccasions.some((value) => visit.diningOccasions.includes(value))) return false
  if (filters.recommendationSourceType && visit.recommendationSourceType !== filters.recommendationSourceType) return false
  if (filters.recommendationSource && visit.recommendationSourceText !== filters.recommendationSource) return false
  if (filters.companion && !visit.companions.includes(filters.companion)) return false
  if (filters.priceRange && !priceMatchesMapRange(visit.pricePerPerson, filters.priceRange)) return false
  if (filters.visitPeriod) {
    const months = filters.visitPeriod === 'sixMonths' ? 6 : 12
    const cutoff = new Date()
    cutoff.setMonth(cutoff.getMonth() - months)
    if (new Date(visit.visitedAt) < cutoff) return false
  }
  return true
}

function priceMatchesMapRange(value: number | null, range: NonNullable<TasteMapMapBrowseRequest['filters']['priceRange']>) {
  if (value == null || !Number.isFinite(value)) return false
  if (range === 'under100') return value < 100
  if (range === '100to200') return value >= 100 && value <= 200
  return value > 200
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
  const selected = restaurantAvatarSelection(restaurant)
  if (selected?.source) {
    return {
      kind: 'ownerPhoto',
      resourceURL: selected.source,
      photoID: selected.photoId ?? '',
      restaurantID: restaurant.id,
      visitID: selected.visit?.id ?? null,
      sourceOwnerID: restaurant.userId,
      visibility: selected.visit?.visibility ?? 'private',
      exportAllowed: true,
      attributionRequired: false,
      accessibilityLabel: `${restaurant.name} 的${selected.visit ? '用户实拍' : '自定义头像'}`,
    }
  }
  return categoryImageDescriptor(restaurant.name, restaurant.tags, restaurant.id, restaurant.markerEmoji)
}

function categoryImageDescriptor(name: string, tags: readonly string[], stableSeed: string, preferredEmoji?: string): Extract<TasteMapImageDescriptor, { kind: 'foodCategoryVisual' }> {
  return {
    kind: 'foodCategoryVisual', categoryVisualID: resolveFoodCategoryVisualID({ name, tags }), stableSeed,
    preferredEmoji,
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
    categoryHints: [],
    merchantImageUrl: null, phone: null, openingHours: null,
  }))
}
import { referralAvailable } from '../config/referralAvailability'
