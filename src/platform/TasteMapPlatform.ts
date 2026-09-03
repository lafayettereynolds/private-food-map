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
  'acquisition.search',
  'acquisition.nearby',
  'acquisition.shared',
  'acquisition.manual',
  'acquisition.select',
  'map.viewport',
  'content.snapshot',
  'community.setLike',
  'community.comments',
  'community.addComment',
  'restaurant.setWantToGo',
  'visit.contract',
  'visit.save',
  'visit.delete',
  'sync.status',
  'sync.run',
  'haptics.selection',
  'share.open',
  'location.current',
  'photo.pick',
  'photo.capture',
  'photo.discard',
  'photo.retry',
  'premium.status',
  'premium.products',
  'premium.purchase',
  'premium.restore',
  'premium.manage',
  'permissions.status',
  'permissions.openSettings',
  'backup.openExport',
  'backup.openImport',
  'account.openDelete',
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
  | 'restaurantAcquisition'
  | 'mapBrowse'
  | 'contentRead'
  | 'communityInteraction'
  | 'restaurantViewerState'
  | 'visitContract'
  | 'sync'
  | 'haptics'
  | 'share'
  | 'location'
  | 'photoPicker'
  | 'premium'
  | 'permissions'
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
  noiseLevel: Visit['noiseLevel']
  diningDuration: Visit['diningDuration']
  portionLevel: Visit['portionLevel']
  transportConvenience: Visit['transportConvenience']
  specialNotes: string
  companions: string[]
  companionIds: string[]
  recommendationSourceType: Visit['recommendationSourceType']
  recommendationSourceUserId: string | null
  recommendationSourceText: string
  sharedMealId: string | null
  partySize: number | null
  note: string
  dishes: TasteMapVisitWriteDishDTO[]
  photos: TasteMapImageDescriptor[]
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
  /** Adapter-owned viewer state. Public records must never infer this from IDs. */
  viewerState: 'none' | 'want_to_go' | 'visited'
  /** Owner-scoped Native decision. JavaScript must not infer edit rights from user IDs. */
  editableVisitIDs: string[]
  /** Native/Browser adapter capability decision for the current viewer. */
  capabilities: TasteMapRestaurantCapabilitiesDTO
}

export interface TasteMapRestaurantCapabilitiesDTO {
  canEditRestaurant: boolean
  canDeleteRestaurant: boolean
  canRecordVisit: boolean
  canAddToWantToGo: boolean
  canAddToList: boolean
  canAddToRoulette: boolean
  canShare: boolean
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
  viewerState: 'none' | 'want_to_go' | 'visited'
  editableVisitIDs: string[]
  capabilities: TasteMapRestaurantCapabilitiesDTO
}

export interface TasteMapRestaurantListRequest {
  ids?: string[]
  status?: 'visited' | 'wantToGo'
  limit?: number
}

export type TasteMapMapScope = 'visited' | 'wantToGo' | 'recommended'
export type TasteMapMapSort = 'recent' | 'rating' | 'visits' | 'distance'

export interface TasteMapMapBounds {
  north: number
  south: number
  east: number
  west: number
}

export interface TasteMapMapFilters {
  city?: string
  minimumScoreOutOfTen?: number
  maximumSpend?: number
  minimumVisitCount?: number
  companion?: string
  cuisine?: string
  recommendationSource?: string
}

export interface TasteMapMapBrowseRequest {
  requestID: string
  scope: TasteMapMapScope
  bounds?: TasteMapMapBounds
  filters: TasteMapMapFilters
  sort: TasteMapMapSort
  search: string
  limit?: number
  currentLocation?: { latitude: number; longitude: number }
}

export interface TasteMapMapBrowseOptions {
  cities: string[]
  companions: string[]
  cuisines: string[]
  recommendationSources: string[]
}

export interface TasteMapMapBrowseResponse {
  requestID: string
  items: TasteMapRestaurantDTO[]
  totalCount: number
  options: TasteMapMapBrowseOptions
}

export interface TasteMapHybridListRestaurantDTO {
  id: string
  name: string
  address: string
  city: string
  position: number
  note: string
  image: TasteMapImageDescriptor
}

export interface TasteMapHybridPersonDTO {
  id: string
  name: string
  city: string | null
  avatarPhotoID: string | null
  avatarPresetID: UserProfile['avatarPresetId']
  isFollowing: boolean
}

export interface TasteMapHybridContentRestaurantDTO {
  id: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags: string[]
  referencePrice: number | null
  image: TasteMapImageDescriptor
}

export interface TasteMapHybridDiscoveryItemDTO {
  id: string
  mode: 'for_you' | 'similar_taste' | 'trending'
  restaurant: TasteMapHybridContentRestaurantDTO
  viewerState: 'none' | 'want_to_go' | 'visited'
  sourceUser: TasteMapHybridPersonDTO | null
  activityRating: number | null
  activityVisitedAt: string | null
  interaction: TasteMapHybridActivityInteractionDTO | null
  likedByViewer: boolean
  likeCount: number
  commentCount: number
  communityRating: {
    valueOutOfFive: number | null
    sampleCount: number
  }
  reason: string
  similarityPercent: number | null
  sharedRestaurantCount: number | null
  uniqueVisitorCount: number | null
  wantToGoCount: number | null
  rank: number
}

export interface TasteMapHybridActivityItemDTO {
  id: string
  kind: 'visit' | 'want_to_go'
  eventAt: string
  user: TasteMapHybridPersonDTO
  restaurant: TasteMapHybridContentRestaurantDTO
  visitID: string | null
  interaction: TasteMapHybridActivityInteractionDTO | null
  visitRating: number | null
  note: string | null
  viewerState: 'none' | 'want_to_go' | 'visited'
  likedByViewer: boolean
  likeCount: number
  commentCount: number
}

/** Explicit identity chain for an interaction. A recommendation without a
 * concrete Visit never receives a fabricated social target. */
export interface TasteMapHybridActivityInteractionDTO {
  activityID: string | null
  visitID: string
  authorID: string
  restaurantID: string
}

export interface TasteMapCommunityEngagementDTO {
  likedByViewer: boolean
  likeCount: number
  commentCount: number
}

export interface TasteMapCommunityCommentDTO {
  id: string
  visitID: string
  body: string
  author: TasteMapHybridPersonDTO
  createdAt: string
}

export interface TasteMapCommunityCommentPageDTO {
  items: TasteMapCommunityCommentDTO[]
  nextCursor: string | null
}

export interface TasteMapCommunityCommentMutationDTO extends TasteMapCommunityEngagementDTO {
  comment: TasteMapCommunityCommentDTO
}

export interface TasteMapRestaurantViewerStateMutationDTO {
  restaurantID: string
  viewerState: 'none' | 'want_to_go' | 'visited'
  updatedAt: string
}

export interface TasteMapHybridListDTO {
  id: string
  title: string
  description: string
  visibility: 'private' | 'friends' | 'public'
  isRanked: boolean
  isOwnedByViewer: boolean
  ownerName: string
  restaurantCount: number
  restaurants: TasteMapHybridListRestaurantDTO[]
  updatedAt: string
}

export interface TasteMapHybridContentSnapshotDTO {
  generatedAt: string
  discovery: {
    forYou: TasteMapHybridDiscoveryItemDTO[]
    similarTaste: TasteMapHybridDiscoveryItemDTO[]
    trending: TasteMapHybridDiscoveryItemDTO[]
  }
  community: {
    following: TasteMapHybridActivityItemDTO[]
    latest: TasteMapHybridActivityItemDTO[]
  }
  lists: TasteMapHybridListDTO[]
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
  pendingPhotoCount?: number
  failedPhotoCount?: number
  conflictCount?: number
  lastSuccessfulSyncAt: string | null
  errorCode: string | null
}

export interface TasteMapLocationDTO {
  latitude: number
  longitude: number
  timestamp: string
  horizontalAccuracy: number
  accuracyMode: 'full' | 'reduced'
  authorizationStatus: 'allowed' | 'denied' | 'notDetermined' | 'restricted'
}

export interface TasteMapAcquisitionCandidateDTO {
  id: string
  name: string
  address: string
  city: string
  district: string
  latitude: number
  longitude: number
  distanceMeters: number | null
  phone: string | null
  openingHours: string | null
  image: TasteMapImageDescriptor
  duplicateKind: 'none' | 'exactProvider' | 'probableCrossProvider'
  existingRestaurantID: string | null
}

export interface TasteMapAcquisitionResultsDTO {
  candidates: TasteMapAcquisitionCandidateDTO[]
  location: TasteMapLocationDTO | null
  message: string | null
  sharedImportFingerprint: string | null
}

export interface TasteMapManualRestaurantDraftDTO {
  name: string
  city: string
  address: string
  latitude?: number | null
  longitude?: number | null
}

export interface TasteMapAcquisitionSelectionDTO {
  restaurantID: string
  duplicateKind: TasteMapAcquisitionCandidateDTO['duplicateKind']
  existingRestaurantID: string | null
}

export interface TasteMapPhotoPickItemDTO {
  photoID: string
  preview: Extract<TasteMapImageDescriptor, { kind: 'nativeResource' }>
}

export interface TasteMapPhotoPickResult { photos: TasteMapPhotoPickItemDTO[] }

export interface TasteMapPendingPhotoAttachmentDTO {
  photoID: string
  dishDraftID: string | null
}

export interface TasteMapVisitWriteDishDTO {
  id: string
  name: string
  taste: string
  rating: number | null
  price: number | null
  photoID: string | null
}

export interface TasteMapVisitWriteDraftDTO {
  visitedAt: string
  rating: number | null
  visibility: Visit['visibility']
  diningMode: Visit['diningMode']
  totalPrice: number | null
  myActualSpend: number | null
  paymentMode: Visit['paymentMode']
  partySize: number
  queueDuration: Visit['queueDuration']
  diningOccasions: Visit['diningOccasions']
  diningOccasionText: string
  valueRating: number | null
  environmentRating: number | null
  serviceRating: number | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: Visit['noiseLevel']
  diningDuration: Visit['diningDuration']
  portionLevel: Visit['portionLevel']
  transportConvenience: Visit['transportConvenience']
  specialNotes: string
  recommendationSourceType: Visit['recommendationSourceType']
  recommendationSourceUserID: string | null
  recommendationSourceText: string
  sharedParticipantUserIDs: string[]
  companions: string[]
  dishes: TasteMapVisitWriteDishDTO[]
  pendingPhotos?: TasteMapPendingPhotoAttachmentDTO[]
  note: string
}

export interface TasteMapVisitWriteRequest {
  restaurantID: string
  visitID: string | null
  draft: TasteMapVisitWriteDraftDTO
}

export interface TasteMapVisitMutationResultDTO {
  restaurantID: string
  visitID: string
  updatedAt: string
  photoWarning?: string | null
}

export interface TasteMapPremiumStatusDTO {
  state: 'free' | 'premium' | 'unavailable'
  expiresAt: string | null
}

export interface TasteMapPremiumProductDTO {
  id: string
  displayName: string
  valueDescription: string
  displayPrice: string
  period: 'monthly' | 'annual' | 'lifetime'
  billingPeriodDescription: string
}

export interface TasteMapPremiumActionResultDTO {
  outcome: 'completed' | 'pending' | 'cancelled' | 'opened'
  status: TasteMapPremiumStatusDTO
}

export interface TasteMapPermissionsStatusDTO {
  location: 'allowed' | 'limited' | 'denied' | 'restricted' | 'notDetermined'
  camera: 'allowed' | 'denied' | 'restricted' | 'notDetermined'
  photoAddOnly: 'allowed' | 'limited' | 'denied' | 'restricted' | 'notDetermined'
  canOpenSystemSettings: boolean
}

export interface TasteMapSharePayload {
  title?: string
  text?: string
  url?: string
  nativeResourceURL?: string
  /** Transient generated share artwork only. Native rejects non-image and oversized payloads. */
  imageDataURL?: string
}

/** Native-only capabilities. Hybrid pages are intentionally impossible to
 * pass to openNative at the TypeScript boundary. */
export interface TasteMapNativeRouteRequest {
  route:
    | 'acquisitionNative' | 'listManage' | 'premiumStore' | 'settingsNative' | 'socialNative'
    | 'dataBackup' | 'permissions' | 'storage' | 'accountDelete'
    | 'profileEdit' | 'restaurantEdit' | 'restaurantDelete' | 'restaurantAddToList'
  identifier?: string
}

export type TasteMapHybridRoute =
  | { surface: 'profile'; identifier?: string }
  | { surface: 'restaurant'; identifier: string }
  | { surface: 'map' | 'discovery' | 'add' | 'visit' | 'visitEdit' | 'lists' | 'publicList' | 'activity' | 'roulette' | 'analytics' | 'premium' | 'settings'; identifier?: string }
  | { surface: 'acquisitionNative' | 'listManage' | 'premiumStore' | 'settingsNative' | 'socialNative' | 'dataBackup' | 'permissions' | 'storage' | 'accountDelete'; identifier?: string }
  | { surface: 'profileEdit'; identifier?: string }
  | { surface: 'restaurantEdit' | 'restaurantDelete' | 'restaurantAddToList' | 'restaurantWantToGo'; identifier: string }

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
  | { version: 1; sequence: number; name: 'location.changed'; payload: TasteMapLocationDTO }

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
    setWantToGo(restaurantID: string, wanted: boolean): Promise<TasteMapRestaurantViewerStateMutationDTO>
  }
  acquisition: {
    search(query: string, city: string): Promise<TasteMapAcquisitionResultsDTO>
    nearby(): Promise<TasteMapAcquisitionResultsDTO>
    shared(): Promise<TasteMapAcquisitionResultsDTO>
    manual(draft: TasteMapManualRestaurantDraftDTO): Promise<TasteMapAcquisitionResultsDTO>
    select(candidateID: string, confirmProbableMatch?: boolean): Promise<TasteMapAcquisitionSelectionDTO>
  }
  map: { viewport(request: TasteMapMapBrowseRequest): Promise<TasteMapMapBrowseResponse> }
  content: { snapshot(): Promise<TasteMapHybridContentSnapshotDTO> }
  community: {
    setLike(target: TasteMapHybridActivityInteractionDTO, liked: boolean): Promise<TasteMapCommunityEngagementDTO>
    comments(target: TasteMapHybridActivityInteractionDTO): Promise<TasteMapCommunityCommentPageDTO>
    addComment(target: TasteMapHybridActivityInteractionDTO, body: string): Promise<TasteMapCommunityCommentMutationDTO>
  }
  visit: {
    contract(): Promise<{ version: 1; writeUIReady: true }>
    save(request: TasteMapVisitWriteRequest): Promise<TasteMapVisitMutationResultDTO>
    delete(visitID: string): Promise<TasteMapVisitMutationResultDTO>
  }
  sync: {
    status(): Promise<TasteMapSyncStatusDTO>
    run(): Promise<TasteMapSyncStatusDTO>
  }
  haptics: { selection(): Promise<void> }
  share: { open(payload: TasteMapSharePayload): Promise<void> }
  location: { current(): Promise<TasteMapLocationDTO> }
  photo: {
    pick(selectionLimit: number): Promise<TasteMapPhotoPickResult>
    capture(): Promise<TasteMapPhotoPickResult>
    discard(photoID: string): Promise<void>
    retry(photoID: string): Promise<void>
  }
  premium: {
    status(): Promise<TasteMapPremiumStatusDTO>
    products(): Promise<TasteMapPremiumProductDTO[]>
    purchase(productID: string): Promise<TasteMapPremiumActionResultDTO>
    restore(): Promise<TasteMapPremiumActionResultDTO>
    manage(): Promise<TasteMapPremiumActionResultDTO>
  }
  permissions: {
    status(): Promise<TasteMapPermissionsStatusDTO>
    openSystemSettings(): Promise<void>
  }
  backup: {
    openExport(): Promise<void>
    openImport(): Promise<void>
  }
  account: { openDelete(): Promise<void> }
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
