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
  type TasteMapHybridContentSnapshotDTO,
  type TasteMapMapBrowseRequest,
  type TasteMapMapBrowseResponse,
  type TasteMapNativeRouteRequest,
  type TasteMapHybridRoute,
  type TasteMapHybridEvent,
  type TasteMapNavigationStateDTO,
  type TasteMapPhotoPickResult,
  type TasteMapPlatform,
  type TasteMapPremiumStatusDTO,
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

  constructor(target: CapacitorWindow = window as CapacitorWindow) {
    const plugin = target.Capacitor?.Plugins?.TasteMapNative
    if (!plugin) throw new TasteMapPlatformError('TasteMapNative.v1 is not registered.', 'native_bridge_unavailable')
    this.plugin = plugin
  }

  runtime = { info: () => this.runtimeInfo() }
  auth = {
    sessionStatus: () => this.call<TasteMapAuthSessionStatus>('auth.sessionStatus'),
    signInWithApple: () => this.call<TasteMapAuthResult>('auth.signInWithApple'),
    logout: () => this.call<TasteMapAuthSessionStatus>('auth.logout'),
  }
  profile = { getCurrent: async (): Promise<TasteMapProfileDashboardViewModel> => projectBridgeProfile(await this.call<TasteMapProfileDashboardDTO>('profile.getCurrent')) }
  restaurant = {
    get: async (id: string): Promise<TasteMapRestaurantDetailViewModel> => projectBridgeRestaurant(await this.call<TasteMapRestaurantDetailDTO>('restaurant.get', { id })),
    list: async (request: TasteMapRestaurantListRequest = {}) => (await this.call<TasteMapRestaurantDetailDTO[]>('restaurant.list', request)).map(projectBridgeRestaurant),
  }
  map = { viewport: (request: TasteMapMapBrowseRequest) => this.call<TasteMapMapBrowseResponse>('map.viewport', request) }
  content = { snapshot: () => this.call<TasteMapHybridContentSnapshotDTO>('content.snapshot') }
  visit = {
    contract: () => this.call<{ version: 1; writeUIReady: true }>('visit.contract'),
    save: (request: TasteMapVisitWriteRequest) => this.call<TasteMapVisitMutationResultDTO>('visit.save', request),
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
    discard: async (photoID: string) => { await this.call<Record<string, never>>('photo.discard', { photoID }) },
    retry: async (photoID: string) => { await this.call<Record<string, never>>('photo.retry', { photoID }) },
  }
  premium = { status: () => this.call<TasteMapPremiumStatusDTO>('premium.status') }
  navigation = {
    openNative: async (request: TasteMapNativeRouteRequest) => { await this.call<Record<string, never>>('navigation.openNative', request) },
    openHybrid: (route: TasteMapHybridRoute) => this.call<TasteMapNavigationStateDTO>('navigation.openHybrid', route),
    back: () => this.call<TasteMapNavigationStateDTO>('navigation.back'),
    current: () => this.call<TasteMapNavigationStateDTO>('navigation.current'),
  }
  events = {
    subscribe: async (listener: (event: TasteMapHybridEvent) => void) => {
      guardEventAPI(this.plugin)
      return this.plugin.addListener!('event', listener)
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

  private async call<TResult>(method: TasteMapBridgeMethod, payload: unknown = {}, verifyRuntime = true): Promise<TResult> {
    if (verifyRuntime && method !== 'runtime.info') await this.runtimeInfo()
    const requestId = makeBridgeRequestID()
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
