import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  TasteMapPlatformError,
  makeBridgeRequestID,
  type TasteMapAuthResult,
  type TasteMapAuthSessionStatus,
  type TasteMapBridgeMethod,
  type TasteMapBridgeRequestEnvelope,
  type TasteMapBridgeResponseEnvelope,
  type TasteMapLocationDTO,
  type TasteMapAcquisitionResultsDTO,
  type TasteMapAcquisitionSelectionDTO,
  type TasteMapManualRestaurantDraftDTO,
  type TasteMapHybridContentSnapshotDTO,
  type TasteMapHybridActivityInteractionDTO,
  type TasteMapCommunityEngagementDTO,
  type TasteMapCommunityCommentPageDTO,
  type TasteMapCommunityCommentMutationDTO,
  type TasteMapRestaurantViewerStateMutationDTO,
  type TasteMapMapBrowseRequest,
  type TasteMapMapBrowseResponse,
  type TasteMapNativeMapSurfaceUpdateRequest,
  type TasteMapNativeMapSurfaceUpdateResponse,
  type TasteMapNativeRouteRequest,
  type TasteMapHybridRoute,
  type TasteMapHybridEvent,
  type TasteMapNavigationStateDTO,
  type TasteMapNavigationCommandOptions,
  type TasteMapHybridNavigationOpenOptions,
  type TasteMapPhotoPickResult,
  type TasteMapPlatform,
  type TasteMapPremiumStatusDTO,
  type TasteMapPremiumProductDTO,
  type TasteMapPremiumActionResultDTO,
  type TasteMapPermissionsStatusDTO,
  type TasteMapProfileDashboardDTO,
  type TasteMapProfileDashboardViewModel,
  type TasteMapRestaurantDetailDTO,
  type TasteMapRestaurantDetailViewModel,
  type TasteMapRestaurantListRequest,
  type TasteMapRuntimeInfo,
  type TasteMapSharePayload,
  type TasteMapSyncStatusDTO,
  type TasteMapVisitMutationResultDTO,
  type TasteMapVisitWriteRequest,
} from './TasteMapPlatform'
import { projectBridgeProfile, projectBridgeRestaurant } from './TasteMapBridgeProjection'

interface TasteMapNativeV1Plugin {
  invoke(options: { request: TasteMapBridgeRequestEnvelope<unknown> }): Promise<TasteMapBridgeResponseEnvelope<unknown>>
  addListener?(eventName: 'event', listener: (event: TasteMapHybridEvent) => void): Promise<{ remove(): Promise<void> }>
}

interface CapacitorWindow extends Window {
  Capacitor?: {
    Plugins?: { TasteMapNative?: TasteMapNativeV1Plugin }
    getPlatform?: () => string
    isNativePlatform?: () => boolean
  }
}

export class TasteMapNativeAdapter implements TasteMapPlatform {
  readonly kind = 'native' as const
  private readonly plugin: TasteMapNativeV1Plugin
  private runtimePromise: Promise<TasteMapRuntimeInfo> | null = null
  private readonly navigationRequestPrefix = `${makeBridgeRequestID()}:navigation:`
  private navigationRequestSequence = 0

  constructor(target: CapacitorWindow = window as CapacitorWindow) {
    const plugin = target.Capacitor?.Plugins?.TasteMapNative
    if (!plugin) throw new TasteMapPlatformError('TasteMapNative.v1 is not registered.', 'native_bridge_unavailable')
    this.plugin = plugin
  }

  runtime = { info: () => this.runtimeInfo() }
  directory = {
    searchUsers: (query:string) => this.call<Array<{id:string;displayName:string}>>('directory.searchUsers',{query}),
    dashboard: () => this.call<import('../contracts/privateDirectoryV1').PrivateDirectoryDashboard>('directory.dashboard'),
    mutate: (input:import('../contracts/privateDirectoryV1').PrivateDirectoryMutation) => this.call('directory.mutate',input),
    respond: (id:string,action:'accept'|'reject'|'cancel'|'unlink') => this.call('directory.respond',{id,action}),
    pickAvatar: async () => (await this.photo.pick(1)).photos[0]?.photoID ?? null,
  }
  referrals = {
    dashboard: () => this.call<import('../contracts/referralsV1').ReferralDashboardV1>('referrals.dashboard'),
    prepareRegistration: (code:string) => this.call('referrals.prepareRegistration',{code}),
  }
  auth = {
    sessionStatus: () => this.call<TasteMapAuthSessionStatus>('auth.sessionStatus'),
    signInWithApple: () => this.call<TasteMapAuthResult>('auth.signInWithApple'),
    logout: () => this.call<TasteMapAuthSessionStatus>('auth.logout'),
  }
  profile = { getCurrent: async (): Promise<TasteMapProfileDashboardViewModel> => projectBridgeProfile(await this.call<TasteMapProfileDashboardDTO>('profile.getCurrent')) }
  restaurant = {
    get: async (id: string): Promise<TasteMapRestaurantDetailViewModel> => projectBridgeRestaurant(await this.call<TasteMapRestaurantDetailDTO>('restaurant.get', { id })),
    list: async (request: TasteMapRestaurantListRequest = {}) => (await this.call<TasteMapRestaurantDetailDTO[]>('restaurant.list', request)).map(projectBridgeRestaurant),
    setWantToGo: (restaurantID: string, wanted: boolean) => this.call<TasteMapRestaurantViewerStateMutationDTO>('restaurant.setWantToGo', { restaurantID, wanted }),
    setAvatar: (restaurantID: string, update: import('./TasteMapPlatform').TasteMapRestaurantAvatarUpdateDTO) => this.call<import('./TasteMapPlatform').TasteMapRestaurantAvatarMutationDTO>('restaurant.setAvatar', { restaurantID, ...update }),
  }
  acquisition = {
    search: (query: string, city: string, options: import('./TasteMapPlatform').TasteMapAcquisitionSearchOptions = {}) => this.call<TasteMapAcquisitionResultsDTO>('acquisition.search', { query, city, ...options }),
    nearby: () => this.call<TasteMapAcquisitionResultsDTO>('acquisition.nearby'),
    shared: () => this.call<TasteMapAcquisitionResultsDTO>('acquisition.shared'),
    manual: (draft: TasteMapManualRestaurantDraftDTO) => this.call<TasteMapAcquisitionResultsDTO>('acquisition.manual', draft),
    select: (candidateID: string, confirmProbableMatch = false) => this.call<TasteMapAcquisitionSelectionDTO>('acquisition.select', { candidateID, confirmProbableMatch }),
  }
  map = {
    viewport: (request: TasteMapMapBrowseRequest) => this.call<TasteMapMapBrowseResponse>('map.viewport', request),
    updateNativeSurface: (request: TasteMapNativeMapSurfaceUpdateRequest) => this.call<TasteMapNativeMapSurfaceUpdateResponse>('map.surface.update', request),
  }
  content = { snapshot: (options: import('./TasteMapPlatform').TasteMapContentSnapshotOptions = {}) =>
    this.call<TasteMapHybridContentSnapshotDTO>('content.snapshot', options) }
  discovery = {
    cityPage: async (request: import('./TasteMapPlatform').TasteMapDiscoveryCityPageRequest) => {
      if ((await this.runtimeInfo()).supportedCapabilities.discoveryCityPage !== true) {
        throw new TasteMapPlatformError('请更新应用后搜索其他城市。', 'capability_unavailable')
      }
      return this.call<import('./TasteMapPlatform').TasteMapDiscoveryCityPageDTO>('discovery.cityPage', request)
    },
    page: async (request: import('./TasteMapPlatform').TasteMapDiscoveryPageRequest) => {
      if ((await this.runtimeInfo()).supportedCapabilities.discoveryPage !== true) {
        throw new TasteMapPlatformError('Server-scoped Discovery pages are unavailable on this host.', 'capability_unavailable')
      }
      return this.call<import('./TasteMapPlatform').TasteMapDiscoveryPageDTO>('discovery.page', request)
    },
  }
  recommendations = {
    preference: async (restaurantID?: string) => {
      if ((await this.runtimeInfo()).supportedCapabilities.recommendationPreferences !== true) {
        throw new TasteMapPlatformError('请更新应用后使用不感兴趣。', 'capability_unavailable')
      }
      return this.call<import('../services/recommendationIntent').RecommendationPreferences>('recommendations.preference', { restaurantID })
    },
  }
  lists = {
    get: (request: import('./TasteMapPlatform').TasteMapListGetRequest) =>
      this.call<import('./TasteMapPlatform').TasteMapListPageDTO>('lists.get', request),
    createShareLink: (id: string) =>
      this.call<import('./TasteMapPlatform').TasteMapListShareLinkDTO>('lists.createShareLink', { id }),
  }
  community = {
    safety: (target: import('../contracts/releaseSafetyV1').UGCSafetyTarget) => this.call<import('../contracts/releaseSafetyV1').UGCSafetyCapabilities>('community.safety', { target }),
    report: (target: import('../contracts/releaseSafetyV1').UGCSafetyTarget, reason: import('../contracts/releaseSafetyV1').ModerationReasonV1, details: string, requestID: string) => this.call('community.report', { target, reason, details, requestID }),
    block: (target: import('../contracts/releaseSafetyV1').UGCSafetyTarget) => this.call('community.block', { target }),
    deleteComment: (target: import('../contracts/releaseSafetyV1').UGCSafetyTarget) => this.call('community.deleteComment', { target }),
    setLike: (target: TasteMapHybridActivityInteractionDTO, liked: boolean) => this.call<TasteMapCommunityEngagementDTO>('community.setLike', { target, liked }),
    comments: (target: TasteMapHybridActivityInteractionDTO) => this.call<TasteMapCommunityCommentPageDTO>('community.comments', { target }),
    addComment: (target: TasteMapHybridActivityInteractionDTO, body: string) => this.call<TasteMapCommunityCommentMutationDTO>('community.addComment', { target, body }),
  }
  visit = {
    contract: () => this.call<{ version: 1; writeUIReady: true }>('visit.contract'),
    save: ({ restaurantID, visitID, draft }: TasteMapVisitWriteRequest) => this.call<TasteMapVisitMutationResultDTO>('visit.save', { restaurantID, visitID, draft }),
    delete: (visitID: string) => this.call<TasteMapVisitMutationResultDTO>('visit.delete', { visitID }),
  }
  sync = {
    status: () => this.call<TasteMapSyncStatusDTO>('sync.status'),
    run: () => this.call<TasteMapSyncStatusDTO>('sync.run'),
  }
  haptics = { selection: async () => { await this.call<Record<string, never>>('haptics.selection') } }
  share = { open: async (payload: TasteMapSharePayload) => { await this.call<Record<string, never>>('share.open', payload) } }
  location = { current: () => this.call<TasteMapLocationDTO>('location.current') }
  photo = {
    pick: (selectionLimit: number) => this.call<TasteMapPhotoPickResult>('photo.pick', { selectionLimit }),
    capture: () => this.call<TasteMapPhotoPickResult>('photo.capture'),
    discard: async (photoID: string) => { await this.call<Record<string, never>>('photo.discard', { photoID }) },
    retry: async (photoID: string) => { await this.call<Record<string, never>>('photo.retry', { photoID }) },
  }
  premium = {
    status: () => this.call<TasteMapPremiumStatusDTO>('premium.status'),
    trialEligibility: () => this.call<{ eligible: boolean; trialDays: number }>('premium.trialEligibility'),
    claimTrial: () => this.call<{ expiresAt: string; status: TasteMapPremiumStatusDTO }>('premium.claimTrial'),
    products: () => this.call<TasteMapPremiumProductDTO[]>('premium.products'),
    purchase: (productID: string) => this.call<TasteMapPremiumActionResultDTO>('premium.purchase', { productID }),
    restore: () => this.call<TasteMapPremiumActionResultDTO>('premium.restore'),
    manage: () => this.call<TasteMapPremiumActionResultDTO>('premium.manage'),
  }
  permissions = {
    status: () => this.call<TasteMapPermissionsStatusDTO>('permissions.status'),
    openSystemSettings: async () => { await this.call<Record<string, never>>('permissions.openSettings') },
  }
  backup = {
    openExport: async () => { await this.call<Record<string, never>>('backup.openExport') },
    openImport: async () => { await this.call<Record<string, never>>('backup.openImport') },
  }
  account = { openDelete: async () => { await this.call<Record<string, never>>('account.openDelete') } }
  navigation = {
    openNative: async (request: TasteMapNativeRouteRequest) => { await this.call<Record<string, never>>('navigation.openNative', request) },
    openHybrid: (route: TasteMapHybridRoute, options?: TasteMapHybridNavigationOpenOptions) => this.call<TasteMapNavigationStateDTO>('navigation.openHybrid', options?.replaceCurrent ? { ...route, replaceCurrent: true } : route, true, options?.localTransition),
    back: (options?: TasteMapNavigationCommandOptions) => this.call<TasteMapNavigationStateDTO>('navigation.back', {}, true, options?.localTransition),
    current: () => this.call<TasteMapNavigationStateDTO>('navigation.current'),
  }
  events = {
    subscribe: async (listener: (event: TasteMapHybridEvent) => void) => {
      guardEventAPI(this.plugin)
      return this.plugin.addListener!('event', event => {
        // These events acknowledge commands whose visible transition is already
        // owned by the shared shell (Back reconciles its explicit response).
        // Identify our own acknowledgements even after their promises settle;
        // no timeout or unbounded set of completed request IDs is needed.
        if (event.name === 'navigation.route'
          && event.payload.sourceRequestID?.startsWith(this.navigationRequestPrefix)) return
        listener(event)
      })
    },
  }

  private runtimeInfo() {
    this.runtimePromise ??= this.call<TasteMapRuntimeInfo>('runtime.info', {}, false).then((info) => {
      if (info.bridgeVersion !== TASTE_MAP_NATIVE_BRIDGE_VERSION) {
        throw new TasteMapPlatformError(`Unsupported bridge version ${info.bridgeVersion}.`, 'bridge_version_mismatch')
      }
      return info
    })
    return this.runtimePromise
  }

  private async call<TResult>(method: TasteMapBridgeMethod, payload: unknown = {}, verifyRuntime = true, localNavigationTransition = false): Promise<TResult> {
    const requestId = localNavigationTransition
      ? `${this.navigationRequestPrefix}${++this.navigationRequestSequence}`
      : makeBridgeRequestID()
    if (verifyRuntime && method !== 'runtime.info') await this.runtimeInfo()
    const request: TasteMapBridgeRequestEnvelope<unknown> = {
      version: TASTE_MAP_NATIVE_BRIDGE_VERSION,
      requestId,
      method,
      payload,
    }
    const response = await this.plugin.invoke({ request })
    if (response.version !== TASTE_MAP_NATIVE_BRIDGE_VERSION) {
      throw new TasteMapPlatformError('The native bridge returned an incompatible envelope.', 'bridge_version_mismatch')
    }
    if (response.requestId !== requestId) {
      throw new TasteMapPlatformError('The native bridge response did not match the request.', 'bridge_request_mismatch')
    }
    if (response.error) throw TasteMapPlatformError.fromBridge(response.error)
    if (!Object.prototype.hasOwnProperty.call(response, 'result')) {
      throw new TasteMapPlatformError('The native bridge response contained no result.', 'bridge_result_missing')
    }
    return response.result as TResult
  }
}

function guardEventAPI(plugin: TasteMapNativeV1Plugin): asserts plugin is TasteMapNativeV1Plugin & Required<Pick<TasteMapNativeV1Plugin, 'addListener'>> {
  if (!plugin.addListener) throw new TasteMapPlatformError('TasteMapNative.v1 event channel is unavailable.', 'native_event_channel_unavailable')
}

export function hasNativeTasteMapRuntime(target: CapacitorWindow = window as CapacitorWindow) {
  return target.Capacitor?.isNativePlatform?.() === true
    && target.Capacitor?.getPlatform?.() === 'ios'
    && Boolean(target.Capacitor?.Plugins?.TasteMapNative)
}
