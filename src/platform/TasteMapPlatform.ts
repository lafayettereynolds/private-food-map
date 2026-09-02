import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'

export const TASTE_MAP_NATIVE_BRIDGE_VERSION = 1 as const

export const TASTE_MAP_BRIDGE_METHODS = [
  'runtime.info',
  'auth.sessionStatus',
  'auth.signInWithApple',
  'auth.logout',
  'profile.getCurrent',
  'restaurant.get',
  'restaurant.list',
  'visit.contract',
  'sync.status',
  'sync.run',
  'haptics.selection',
  'share.open',
  'location.current',
  'photo.pick',
  'premium.status',
  'navigation.openNative',
  'navigation.openHybrid',
  'navigation.back',
  'navigation.current',
] as const

export type TasteMapBridgeMethod = typeof TASTE_MAP_BRIDGE_METHODS[number]

export type TasteMapCapability =
  | 'appleSignIn'
  | 'logout'
  | 'profileRead'
  | 'restaurantRead'
  | 'visitContract'
  | 'sync'
  | 'haptics'
  | 'share'
  | 'location'
  | 'photoPicker'
  | 'premium'
  | 'nativeNavigation'
  | 'backup'
  | 'accountDelete'

export type TasteMapCapabilityRegistry = Record<TasteMapCapability, boolean>

export interface TasteMapRuntimeInfo {
  bridgeVersion: typeof TASTE_MAP_NATIVE_BRIDGE_VERSION
  platform: 'browser' | 'ios'
  appVersion: string
  build: string
  dataSource: 'browser-indexeddb' | 'native-swiftdata' | 'native-swiftdata-debug-fixture'
  localBundle: boolean
  offlineCapable: boolean
  supportedCapabilities: TasteMapCapabilityRegistry
}

export type TasteMapImageDescriptor =
  | { kind: 'nativeResource'; resourceURL: string; photoID: string; accessibilityLabel: string }
  | { kind: 'publicOrCached'; resourceURL: string; photoID: string; accessibilityLabel: string }
  | { kind: 'providerMerchant'; resourceURL: string; accessibilityLabel: string }
  | { kind: 'foodDiningFallback'; stableSeed: string; accessibilityLabel: string }

export interface TasteMapUserDTO {
  id: string
  nickname: string
  bio: string
  city: string
  avatarPhotoId: string | null
  avatarPresetId: UserProfile['avatarPresetId']
  membershipTier: UserProfile['membershipTier']
  mapSharingEnabled: boolean
  mapVisibility: UserProfile['mapVisibility']
  createdAt: string
  updatedAt: string
}

export interface TasteMapVisitDTO {
  id: string
  restaurantId: string
  visitedAt: string
  rating: Visit['rating']
  valueRating: Visit['valueRating']
  environmentRating: Visit['environmentRating']
  serviceRating: Visit['serviceRating']
  myActualSpend: number | null
  totalPrice: number | null
  pricePerPerson: number | null
  diningMode: Visit['diningMode']
  visibility: Visit['visibility']
  paymentMode: Visit['paymentMode']
  queueDuration: Visit['queueDuration']
  diningOccasions: Visit['diningOccasions']
  diningOccasionText: string
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  companions: string[]
  companionIds: string[]
  recommendationSourceText: string
  partySize: number | null
  note: string
  createdAt: string
  updatedAt: string
}

export interface TasteMapRestaurantDTO {
  id: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  status: RestaurantSummary['status']
  tags: string[]
  phone: string | null
  openingHours: string | null
  referencePrice: number | null
  visitCount: number
  averageRating: number | null
  scoreOutOfTen: number | null
  latestVisitDate: string | null
  createdAt: string
  updatedAt: string
  visits: TasteMapVisitDTO[]
  image: TasteMapImageDescriptor
}

export interface TasteMapProfileDashboardDTO {
  user: TasteMapUserDTO
  restaurants: TasteMapRestaurantDTO[]
  followerCount: number
  followingCount: number
}

export interface TasteMapRestaurantDetailDTO {
  restaurant: TasteMapRestaurantDTO
}

export interface TasteMapProfileDashboardViewModel {
  user: UserProfile
  restaurants: RestaurantSummary[]
  visits: Visit[]
  followerCount: number
  followingCount: number
  restaurantImages: Record<string, TasteMapImageDescriptor>
}

export interface TasteMapRestaurantDetailViewModel {
  restaurant: RestaurantSummary
  image: TasteMapImageDescriptor
}

export interface TasteMapRestaurantListRequest {
  ids?: string[]
  status?: 'visited' | 'wantToGo'
  limit?: number
}

export interface TasteMapAuthSessionStatus {
  state: 'authenticated' | 'signedOut' | 'restoring'
  userID: string | null
  displayName: string | null
}

export interface TasteMapAuthResult {
  state: 'authenticated' | 'cancelled' | 'unavailable'
  session: TasteMapAuthSessionStatus
}

export interface TasteMapSyncStatusDTO {
  state: 'idle' | 'syncing' | 'offline' | 'error' | 'unavailable'
  pendingMutationCount: number
  lastSuccessfulSyncAt: string | null
  errorCode: string | null
}

export interface TasteMapLocationDTO {
  latitude: number
  longitude: number
  timestamp: string
  horizontalAccuracy: number
  accuracyAuthorization: 'full' | 'reduced'
}

export interface TasteMapPhotoPickResult { photoIDs: string[] }

export interface TasteMapPremiumStatusDTO {
  state: 'free' | 'premium' | 'unavailable'
  expiresAt: string | null
}

export interface TasteMapSharePayload {
  title?: string
  text?: string
  url?: string
  nativeResourceURL?: string
}

export interface TasteMapNativeRouteRequest {
  route: 'map' | 'discovery' | 'add' | 'visit' | 'lists' | 'roulette' | 'analytics' | 'premium' | 'settings'
  identifier?: string
}

export type TasteMapHybridRoute =
  | { surface: 'profile'; identifier?: string }
  | { surface: 'restaurant'; identifier: string }
  | { surface: 'map' | 'discovery' | 'add' | 'visit' | 'lists' | 'publicList' | 'activity' | 'roulette' | 'analytics' | 'premium' | 'settings'; identifier?: string }

export interface TasteMapNavigationStateDTO {
  route: TasteMapHybridRoute
  owner: 'hybrid' | 'native'
  canGoBack: boolean
}

export type TasteMapLifecycleState = 'foreground' | 'background' | 'resume' | 'memoryWarning'

export type TasteMapHybridEvent =
  | { version: 1; sequence: number; name: 'auth.changed'; payload: TasteMapAuthSessionStatus }
  | { version: 1; sequence: number; name: 'navigation.route'; payload: TasteMapNavigationStateDTO }
  | { version: 1; sequence: number; name: 'deepLink.received'; payload: TasteMapNavigationStateDTO }
  | { version: 1; sequence: number; name: 'shareExtension.received'; payload: { fingerprint: string; target: TasteMapNavigationStateDTO } }
  | { version: 1; sequence: number; name: 'app.lifecycle'; payload: { state: TasteMapLifecycleState } }

export interface TasteMapEventSubscription { remove(): Promise<void> }

export interface TasteMapBridgeErrorPayload {
  code: string
  message: string
  recoverable: boolean
  details?: Record<string, string | number | boolean | null>
}

export interface TasteMapBridgeRequestEnvelope<TPayload = Record<string, never>> {
  version: typeof TASTE_MAP_NATIVE_BRIDGE_VERSION
  requestId: string
  method: TasteMapBridgeMethod
  payload: TPayload
}

export interface TasteMapBridgeResponseEnvelope<TResult = unknown> {
  version: typeof TASTE_MAP_NATIVE_BRIDGE_VERSION
  requestId: string
  result?: TResult
  error?: TasteMapBridgeErrorPayload
}

export interface TasteMapPlatform {
  readonly kind: 'browser' | 'native'
  runtime: { info(): Promise<TasteMapRuntimeInfo> }
  auth: {
    sessionStatus(): Promise<TasteMapAuthSessionStatus>
    signInWithApple(): Promise<TasteMapAuthResult>
    logout(): Promise<TasteMapAuthSessionStatus>
  }
  profile: { getCurrent(): Promise<TasteMapProfileDashboardViewModel> }
  restaurant: {
    get(id: string): Promise<TasteMapRestaurantDetailViewModel>
    list(request?: TasteMapRestaurantListRequest): Promise<TasteMapRestaurantDetailViewModel[]>
  }
  visit: { contract(): Promise<{ version: 1; writeUIReady: false }> }
  sync: {
    status(): Promise<TasteMapSyncStatusDTO>
    run(): Promise<TasteMapSyncStatusDTO>
  }
  haptics: { selection(): Promise<void> }
  share: { open(payload: TasteMapSharePayload): Promise<void> }
  location: { current(): Promise<TasteMapLocationDTO> }
  photo: { pick(): Promise<TasteMapPhotoPickResult> }
  premium: { status(): Promise<TasteMapPremiumStatusDTO> }
  navigation: {
    openNative(request: TasteMapNativeRouteRequest): Promise<void>
    openHybrid(route: TasteMapHybridRoute): Promise<TasteMapNavigationStateDTO>
    back(): Promise<TasteMapNavigationStateDTO>
    current(): Promise<TasteMapNavigationStateDTO>
  }
  events: { subscribe(listener: (event: TasteMapHybridEvent) => void): Promise<TasteMapEventSubscription> }
}

export type TasteMapBridgeUIState =
  | 'loading'
  | 'success'
  | 'empty'
  | 'offline'
  | 'recoverableError'
  | 'fatalError'
  | 'authRequired'
  | 'permissionRequired'

export class TasteMapPlatformError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly recoverable = false,
    readonly details?: TasteMapBridgeErrorPayload['details'],
  ) {
    super(message)
    this.name = 'TasteMapPlatformError'
  }

  static fromBridge(error: TasteMapBridgeErrorPayload) {
    return new TasteMapPlatformError(error.message, error.code, error.recoverable, error.details)
  }
}

export function capabilityUnavailable(capability: TasteMapCapability): never {
  throw new TasteMapPlatformError(
    `The ${capability} capability is not available in this runtime.`,
    'capability_unavailable',
    false,
    { capability },
  )
}

export function makeBridgeRequestID() {
  return globalThis.crypto?.randomUUID?.()
    ?? `tm-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}
