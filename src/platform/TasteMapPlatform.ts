import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import type { RestaurantSocialStats } from '../types/restaurantStats'
import type { FoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'

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
  'map.surface.update',
  'content.snapshot',
  'discovery.page',
  'discovery.cityPage',
  'recommendations.preference',
  'lists.get',
  'lists.createShareLink',
  'community.setLike',
  'community.comments',
  'community.addComment',
  'community.safety', 'community.report', 'community.block', 'community.deleteComment',
  'restaurant.setWantToGo',
  'restaurant.setAvatar',
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
  'premium.trialEligibility',
  'premium.claimTrial',
  'premium.products',
  'premium.purchase',
  'premium.restore',
  'premium.manage',
  'referrals.dashboard',
  'directory.dashboard',
  'directory.mutate',
  'directory.respond',
  'directory.searchUsers',
  'referrals.prepareRegistration',
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

export type TasteMapCapabilityRegistry = Record<TasteMapCapability, boolean> & {
  /** Additive bridge-v1 capability; absent on older hosts means unavailable. */
  discoveryPage?: boolean
  discoveryCityPage?: boolean
  recommendationPreferences?: boolean
  listsRead?: boolean
  listShare?: boolean
  referrals?: boolean
}

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

export type TasteMapUGCVisibility = 'private' | 'friends' | 'public'

export interface TasteMapUGCImageMetadata {
  photoID: string
  restaurantID: string | null
  visitID: string | null
  sourceOwnerID: string
  visibility: TasteMapUGCVisibility
  exportAllowed: boolean
  attributionRequired: boolean
}

export type TasteMapImageDescriptor =
  | ({ kind: 'ownerPhoto'; resourceURL: string; accessibilityLabel: string } & TasteMapUGCImageMetadata)
  | ({ kind: 'activityPhoto'; resourceURL: string; accessibilityLabel: string } & TasteMapUGCImageMetadata)
  | ({ kind: 'publicUGC'; resourceURL: string; accessibilityLabel: string } & TasteMapUGCImageMetadata)
  | { kind: 'foodCategoryVisual'; categoryVisualID: FoodCategoryVisualID; stableSeed: string; preferredEmoji?: string; accessibilityLabel: string; exportAllowed: false }
  | { kind: 'nativeResource'; resourceURL: string; photoID: string; accessibilityLabel: string }
  | { kind: 'publicOrCached'; resourceURL: string; photoID: string; accessibilityLabel: string }
  | { kind: 'providerMerchant'; resourceURL: string; accessibilityLabel: string }
  | { kind: 'foodDiningFallback'; stableSeed: string; accessibilityLabel: string }

export interface TasteMapImageResolutionDTO {
  /** Ordered by the platform's surface-aware Restaurant visual policy. */
  sources: TasteMapImageDescriptor[]
  fallback: Extract<TasteMapImageDescriptor, { kind: 'foodCategoryVisual' | 'foodDiningFallback' }>
}

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
  websiteUrl?: string | null
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
  /** Content photography is independent of the user's custom Restaurant avatar. */
  contentImage?: TasteMapImageDescriptor
  contentImageResolution?: TasteMapImageResolutionDTO
  markerType?: 'image' | 'emoji'
  markerEmoji?: string
}

export type TasteMapRestaurantAvatarUpdateDTO =
  | { kind: 'photo'; photoID: string }
  | { kind: 'emoji'; emoji: string }

export interface TasteMapRestaurantAvatarMutationDTO {
  restaurantID: string
  markerType: 'image' | 'emoji'
  markerEmoji: string
  updatedAt: string
}

export interface TasteMapProfileDashboardDTO {
  user: TasteMapUserDTO
  restaurants: TasteMapRestaurantDTO[]
  followerCount: number
  followingCount: number
  analyticsIdentity?: TasteMapAnalyticsIdentityDTO | null
}

/** Private, owner-scoped directory identities. Linked social-user IDs are not analytics keys. */
export interface TasteMapAnalyticsDirectoryEntryDTO {
  id: string
  ownerUserID: string
  displayName: string
  identifiers: string[]
  updatedAt: string
  deletedAt: string | null
}
export interface TasteMapAnalyticsSourceEntryDTO extends TasteMapAnalyticsDirectoryEntryDTO {
  sourceType: NonNullable<Visit['recommendationSourceType']>
}
export interface TasteMapAnalyticsIdentityDTO {
  ownerUserID: string
  /** Explicit proof for the adapter's already owner-scoped presentation sentinel. */
  recordOwnerID: string
  companions: TasteMapAnalyticsDirectoryEntryDTO[] | null
  sources: TasteMapAnalyticsSourceEntryDTO[] | null
  /** Null means unavailable; sourceID:null is a genuinely ID-less legacy Visit. */
  visitSourceLinks: Array<{ visitID: string; sourceID: string | null }> | null
}

export interface TasteMapRestaurantDetailDTO {
  /** Authoritative current-owner photo deletion capability; absent means denied. */
  deletablePhotoIDs?: string[]
  restaurant: TasteMapRestaurantDTO
  /** Native/Browser-owned aggregate ratings for this exact Restaurant identity. */
  socialStats?: RestaurantSocialStats | null
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
  analyticsIdentity?: TasteMapAnalyticsIdentityDTO | null
}

export interface TasteMapRestaurantDetailViewModel {
  deletablePhotoIDs?: string[]
  restaurant: RestaurantSummary
  image: TasteMapImageDescriptor
  contentImage?: TasteMapImageDescriptor
  contentImageResolution?: TasteMapImageResolutionDTO
  socialStats?: RestaurantSocialStats | null
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
  scoreBands?: Array<1 | 2 | 3 | 4 | 5>
  maximumSpend?: number
  priceRange?: 'under100' | '100to200' | 'over200'
  minimumVisitCount?: number
  diningMode?: Visit['diningMode']
  queueDuration?: NonNullable<Visit['queueDuration']> | 'unrecorded'
  diningOccasions?: Visit['diningOccasions']
  visitPeriod?: 'sixMonths' | 'year'
  distanceKilometers?: 1 | 3 | 5 | 10
  companion?: string
  cuisine?: string
  recommendationSourceType?: NonNullable<Visit['recommendationSourceType']>
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

export type TasteMapMapScopeCounts = Record<TasteMapMapScope, number>

export interface TasteMapMapBrowseResponse {
  requestID: string
  items: TasteMapRestaurantDTO[]
  totalCount: number
  /**
   * Owner-scoped unique Restaurant totals for every primary scope. Viewport,
   * filters and search are deliberately excluded so the scope labels remain a
   * stable description of the user's collection while browsing.
   */
  scopeCounts: TasteMapMapScopeCounts
  options: TasteMapMapBrowseOptions
}

/**
 * Geometry is expressed in WebView CSS viewport points. Native converts it
 * into the persistent CAPBridgeViewController coordinate space. The exclusion
 * rectangles are React-owned controls that must remain visible and tappable
 * above the native MapKit surface.
 */
export interface TasteMapNativeMapSurfaceRect {
  x: number
  y: number
  width: number
  height: number
}

export interface TasteMapNativeMapViewport {
  bounds: TasteMapMapBounds
  center: { latitude: number; longitude: number }
  zoom: number
}

export interface TasteMapNativeMapSurfaceMarkerDTO {
  id: string
  name: string
  latitude: number
  longitude: number
  status: TasteMapMapScope
  recommendationRank: number | null
  visitCount: number
  averageRating: number | null
  fallbackEmoji: string
  image: TasteMapImageDescriptor
}

export interface TasteMapNativeTasteDataProgressDTO {
  displayCount: number
  target: 5 | 10 | 15 | 20
  message: string
}

export interface TasteMapNativeMapSurfaceUpdateRequest {
  requestID: string
  visible: boolean
  viewportWidth: number
  viewportHeight: number
  frame: TasteMapNativeMapSurfaceRect
  reactControlExclusions: TasteMapNativeMapSurfaceRect[]
  scope: TasteMapMapScope
  filters: TasteMapMapFilters
  sort: TasteMapMapSort
  search: string
  cameraFitKey: string
  selectedRestaurantID: string | null
  userAvatarPresetID: UserProfile['avatarPresetId']
  userAvatarPhotoID: string | null
  tasteDataProgress: TasteMapNativeTasteDataProgressDTO | null
  markers: TasteMapNativeMapSurfaceMarkerDTO[]
}

export interface TasteMapNativeMapSurfaceUpdateResponse {
  requestID: string
  surface: 'mapkit'
  persistent: true
}

export interface TasteMapHybridListRestaurantDTO {
  id: string
  name: string
  address: string
  city: string
  position: number
  note: string
  image: TasteMapImageDescriptor
  /** Original stored/provider coordinate; absent is never a city-centre substitute. */
  coordinate?: { latitude: number; longitude: number } | null
  /** Viewer-owned Visit aggregate or explicitly public Restaurant aggregate only. */
  rating?: TasteMapListRatingDTO | null
}

export interface TasteMapListRatingDTO {
  valueOutOfTen: number
  source: 'viewer' | 'public'
  sampleCount: number
}

export interface TasteMapListGetRequest { id: string; cursor?: string | null }
export interface TasteMapListPageDTO {
  list: TasteMapHybridListDTO
  nextCursor: string | null
  generatedAt: string
}
export interface TasteMapListShareLinkDTO { url: string }

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
  contentImage?: TasteMapImageDescriptor
  contentImageResolution?: TasteMapImageResolutionDTO
}

export interface TasteMapHybridDiscoveryReasonDTO {
  code: string
  text: string
  evidence?: import('../contracts/discoveryContract').DiscoveryReasonV1['evidence']
}

export interface TasteMapHybridDiscoveryItemDTO {
  tasteEvidence?: import('../contracts/discoveryContract').DiscoveryCardV1['tasteEvidence']
  id: string
  mode: 'for_you' | 'similar_taste' | 'trending'
  restaurant: TasteMapHybridContentRestaurantDTO
  /** Authorized photos of this exact activity Visit; absent on legacy/system cards. */
  activityImages?: TasteMapImageDescriptor[]
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
  /** History-derived matching index, never a calibrated probability. */
  personalTastePercent?: number | null
  predictedLiking?: import('../contracts/predictedLiking').PredictedLiking | null
  calibratedLikeProbability?: import('../contracts/recommendationSignal').CalibratedLikeProbability | null
  reasons: TasteMapHybridDiscoveryReasonDTO[]
  /** Backward-compatible first reason for older locally staged bundles. */
  reason: string
  similarityPercent: number | null
  sharedRestaurantCount: number | null
  trendWindowDays: number | null
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
  /** Current visible Visit only. Missing/empty keeps the restaurant image fallback. */
  activityImages?: TasteMapImageDescriptor[]
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

export interface TasteMapContentSnapshotOptions { forceRefresh?: boolean }

export type TasteMapDiscoveryMode = 'for_you' | 'similar_taste' | 'trending'

export interface TasteMapDiscoveryPageRequest {
  mode: TasteMapDiscoveryMode
  /** Empty means let the server resolve the city, not a client-side all-city filter. */
  city: string
  windowDays: 7 | 30
  /** Both values must come from the same accepted query snapshot. */
  cursor?: string
  snapshotID?: string
  /** First-page only. Invalidates any pending continuation. */
  forceRefresh?: boolean
  filters?: import('../contracts/discoveryFilters').NormalizedDiscoveryFilters
  sort?: 'recommended' | 'taste' | 'predicted_liking' | 'public_rating' | 'distance' | 'similar_rating' | 'trend'
  preferences?: import('../contracts/discoverySessionPreferences').DiscoverySessionPreferences
}

export interface TasteMapDiscoveryCityPageRequest {
  mode: TasteMapDiscoveryMode | 'following' | 'latest'
  city: string
  windowDays?: 7 | 30
  cursor?: string
  snapshotID?: string
  forceRefresh?: boolean
  filters?: import('../contracts/discoveryFilters').NormalizedDiscoveryFilters
  sort?: 'recommended' | 'taste' | 'predicted_liking' | 'public_rating' | 'distance' | 'similar_rating' | 'trend' | 'latest'
  preferences?: import('../contracts/discoverySessionPreferences').DiscoverySessionPreferences
}

/** Session-only selected-city content. Never replaces the canonical Map recommendation snapshot. */
export interface TasteMapDiscoveryCityPageDTO {
  filterCapabilities?: import('../contracts/discoveryFilters').DiscoveryFilterCapabilities
  filterTaxonomy?: import('../contracts/discoveryFilters').DiscoveryFilterTaxonomy
  appliedQuery?: import('../contracts/discoveryFilters').DiscoveryAppliedQuery
  evidenceAvailability?: import('../contracts/discoveryAvailability').DiscoveryEvidenceAvailability
  dataSource?: 'remote' | 'debug_city_fixture'
  version: 1
  mode: TasteMapDiscoveryCityPageRequest['mode']
  requestedCity: string
  resolvedCity: string
  windowDays: 7 | 30
  snapshotID: string | null
  generatedAt: string | null
  discoveryItems: TasteMapHybridDiscoveryItemDTO[]
  activityItems: TasteMapHybridActivityItemDTO[]
  nextCursor: string | null
  pagination: 'more' | 'complete' | 'unknown'
  refreshStatus: TasteMapDiscoveryRefreshStatusDTO
  engagementState: 'known' | 'unknown'
  /** Social Like/Comment only; authorized Restaurant targets remain independently usable. */
  interactionsAvailable: boolean
}

export interface TasteMapDiscoveryPageDTO {
  filterCapabilities?: import('../contracts/discoveryFilters').DiscoveryFilterCapabilities
  filterTaxonomy?: import('../contracts/discoveryFilters').DiscoveryFilterTaxonomy
  appliedQuery?: import('../contracts/discoveryFilters').DiscoveryAppliedQuery
  evidenceAvailability?: import('../contracts/discoveryAvailability').DiscoveryEvidenceAvailability
  version: 1
  mode: TasteMapDiscoveryMode
  requestedCity: string
  resolvedCity: string
  windowDays: 7 | 30
  snapshotID: string | null
  generatedAt: string | null
  /** Accumulated accepted pages, in server order; not a complete-city total. */
  items: TasteMapHybridDiscoveryItemDTO[]
  nextCursor: string | null
  /** Unknown for unavailable/restricted results; never infer complete from those. */
  pagination: 'more' | 'complete' | 'unknown'
  refreshStatus: TasteMapDiscoveryRefreshStatusDTO
  /** Page-v1 lacks engagement counts. Do not render its legacy zero defaults as real counts. */
  engagementState: 'unknown'
  /** Enable only after the page targets and authoritative engagement read path are wired. */
  interactionsAvailable: false
}

export interface TasteMapDiscoveryRefreshStatusDTO {
  state: 'fresh' | 'cached' | 'unavailable' | 'restricted'
  city: string
  windowDays: number
  sourceGeneratedAt: string | null
  attemptedAt: string
  issue: TasteMapBridgeErrorPayload | null
}

export interface TasteMapHybridContentSnapshotDTO {
  generatedAt: string
  discovery: {
    evidenceAvailability?: Partial<Record<TasteMapDiscoveryMode, import('../contracts/discoveryAvailability').DiscoveryEvidenceAvailability>>
    forYou: TasteMapHybridDiscoveryItemDTO[]
    similarTaste: TasteMapHybridDiscoveryItemDTO[]
    trending: TasteMapHybridDiscoveryItemDTO[]
    /** Missing in older bridge-v1 payloads: freshness is unknown, not fresh. */
    refreshStatus?: Partial<Record<TasteMapDiscoveryMode, TasteMapDiscoveryRefreshStatusDTO>>
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
  /** City reverse-geocoded from this authorized fix, never the Profile city. */
  detectedCity?: string | null
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
  websiteUrl?: string | null
  openingHours: string | null
  /** Provider-supplied categories; optional while older Native bundles remain compatible. */
  categoryHints?: string[]
  /** Kept for Native.v1 compatibility; presentation uses imageResolution. */
  image: TasteMapImageDescriptor
  imageResolution: TasteMapImageResolutionDTO
  duplicateKind: 'none' | 'exactProvider' | 'probableCrossProvider'
  existingRestaurantID: string | null
}

export interface TasteMapAcquisitionResultsDTO {
  /** Nearby returns the complete accepted in-range, distance-ordered snapshot.
   * UI batches only its presentation; expanding never reacquires GPS/search. */
  candidates: TasteMapAcquisitionCandidateDTO[]
  location: TasteMapLocationDTO | null
  /** Reverse-geocoded city for prefilling the editable search scope. */
  detectedCity?: string | null
  message: string | null
  sharedImportFingerprint: string | null
  /** Opaque provider/result snapshot continuation; never a guessed page count. */
  nextCursor?: string | null
}

export interface TasteMapAcquisitionSearchOptions { cursor?: string | null }

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
  /** Browser-local material only. NativeAdapter excludes this field from the bridge. */
  browserPhotoMaterial?: {
    photos: string[]
    photoIds: Array<string | null>
    dishPhotos: Array<{ id: string; imageData: string | null }>
  }
}

export interface TasteMapVisitMutationResultDTO {
  restaurantID: string
  visitID: string
  updatedAt: string
  photoWarning?: string | null
  /** Present only when deleting the final active owner visit also deleted its restaurant. */
  deletedRestaurantID?: string | null
}

export interface TasteMapPremiumStatusDTO {
  state: 'free' | 'premium' | 'unavailable'
  expiresAt: string | null
  source?: string | null
  startedAt?: string | null
  statusText?: string | null
  canManageSubscription?: boolean
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
    | 'accountSettings' | 'dataBackup' | 'dataClear' | 'privacySettings' | 'permissions'
    | 'storage' | 'helpSettings' | 'aboutSettings' | 'accountDelete'
    | 'profileEdit' | 'restaurantEdit' | 'restaurantDelete' | 'restaurantAddToList'
  identifier?: string
}

export type TasteMapHybridRoute =
  | { surface: 'profile'; identifier?: string }
  | { surface: 'restaurant'; identifier: string }
  | { surface: 'map' | 'discovery' | 'add' | 'visit' | 'visitEdit' | 'lists' | 'publicList' | 'activity' | 'roulette' | 'analytics' | 'premium' | 'settings'; identifier?: string }
  | { surface: 'acquisitionNative' | 'listManage' | 'premiumStore' | 'settingsNative' | 'socialNative' | 'accountSettings' | 'dataBackup' | 'dataClear' | 'privacySettings' | 'permissions' | 'storage' | 'helpSettings' | 'aboutSettings' | 'accountDelete'; identifier?: string }
  | { surface: 'profileEdit'; identifier?: string }
  | { surface: 'restaurantEdit' | 'restaurantDelete' | 'restaurantAddToList' | 'restaurantWantToGo'; identifier: string }

export interface TasteMapNavigationStateDTO {
  route: TasteMapHybridRoute
  owner: 'hybrid' | 'native'
  canGoBack: boolean
  /** Present only for a bridge-command acknowledgement, never Native-origin navigation. */
  sourceRequestID?: string
  /** Optional Native-owned completion; old hosts omit it. */
  completedAction?: 'restaurantDelete'
}

/** Adapter-local acknowledgement policy; never included in a Native route payload. */
export interface TasteMapNavigationCommandOptions {
  localTransition?: boolean
}

export interface TasteMapHybridNavigationOpenOptions extends TasteMapNavigationCommandOptions {
  /** Complete the current route instead of retaining it behind the destination. */
  replaceCurrent?: boolean
}

export type TasteMapLifecycleState = 'foreground' | 'background' | 'resume' | 'memoryWarning'

export type TasteMapHybridEvent =
  | { version: 1; sequence: number; name: 'auth.changed'; payload: TasteMapAuthSessionStatus }
  | { version: 1; sequence: number; name: 'navigation.route'; payload: TasteMapNavigationStateDTO }
  | { version: 1; sequence: number; name: 'deepLink.received'; payload: TasteMapNavigationStateDTO }
  | { version: 1; sequence: number; name: 'shareExtension.received'; payload: { fingerprint: string; target: TasteMapNavigationStateDTO } }
  | { version: 1; sequence: number; name: 'app.lifecycle'; payload: { state: TasteMapLifecycleState } }
  | { version: 1; sequence: number; name: 'premium.productsChanged'; payload: Record<string, never> }
  | { version: 1; sequence: number; name: 'location.changed'; payload: TasteMapLocationDTO }
  | { version: 1; sequence: number; name: 'map.viewport.changed'; payload: TasteMapNativeMapViewport }
  | { version: 1; sequence: number; name: 'map.restaurant.selected'; payload: { restaurantID: string | null } }
  | { version: 1; sequence: number; name: 'map.restaurant.groupSelected'; payload: { restaurantIDs: string[] } }
  | { version: 1; sequence: number; name: 'data.changed'; payload: { reason: 'communityUserBlocked' | 'communityCommentDeleted' | 'localDataCleared' | 'restaurantDeleted' | 'backupImported' | 'nativePresentationDismissed' | 'premiumEntitlementChanged' | 'syncCompleted' | 'recommendationPreferenceSynced' | 'localDataChanged' } }

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
  directory?: {
    dashboard():Promise<import('../contracts/privateDirectoryV1').PrivateDirectoryDashboard>
    mutate(input:import('../contracts/privateDirectoryV1').PrivateDirectoryMutation):Promise<unknown>
    respond(id:string,action:'accept'|'reject'|'cancel'|'unlink'):Promise<unknown>
    pickAvatar():Promise<string|null>
    searchUsers(query:string):Promise<Array<{id:string;displayName:string}>>
  }
  referrals?: { dashboard(): Promise<import('../contracts/referralsV1').ReferralDashboardV1>; prepareRegistration?(code:string):Promise<unknown> }
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
    setAvatar(restaurantID: string, update: TasteMapRestaurantAvatarUpdateDTO): Promise<TasteMapRestaurantAvatarMutationDTO>
  }
  acquisition: {
    search(query: string, city: string, options?: TasteMapAcquisitionSearchOptions): Promise<TasteMapAcquisitionResultsDTO>
    nearby(): Promise<TasteMapAcquisitionResultsDTO>
    shared(): Promise<TasteMapAcquisitionResultsDTO>
    manual(draft: TasteMapManualRestaurantDraftDTO): Promise<TasteMapAcquisitionResultsDTO>
    select(candidateID: string, confirmProbableMatch?: boolean): Promise<TasteMapAcquisitionSelectionDTO>
  }
  map: {
    viewport(request: TasteMapMapBrowseRequest): Promise<TasteMapMapBrowseResponse>
    updateNativeSurface(request: TasteMapNativeMapSurfaceUpdateRequest): Promise<TasteMapNativeMapSurfaceUpdateResponse>
  }
  content: { snapshot(options?: TasteMapContentSnapshotOptions): Promise<TasteMapHybridContentSnapshotDTO> }
  /** Optional on legacy bridge-v1 hosts; requires supportedCapabilities.discoveryPage. */
  discovery?: {
    page(request: TasteMapDiscoveryPageRequest): Promise<TasteMapDiscoveryPageDTO>
    cityPage(request: TasteMapDiscoveryCityPageRequest): Promise<TasteMapDiscoveryCityPageDTO>
  }
  /** Owner-scoped, durable exclusions shared by For You and the recommendation map. */
  recommendations?: { preference(restaurantID?: string): Promise<import('../services/recommendationIntent').RecommendationPreferences> }
  /** Optional for older bridge-v1 hosts; absence is an explicit unsupported state. */
  lists?: {
    get(request: TasteMapListGetRequest): Promise<TasteMapListPageDTO>
    createShareLink(id: string): Promise<TasteMapListShareLinkDTO>
  }
  community: {
    setLike(target: TasteMapHybridActivityInteractionDTO, liked: boolean): Promise<TasteMapCommunityEngagementDTO>
    /** Absent on older hosts: fail closed, never simulate moderation success. */
    safety?(target: import('../contracts/releaseSafetyV1').UGCSafetyTarget): Promise<import('../contracts/releaseSafetyV1').UGCSafetyCapabilities>
    report?(target: import('../contracts/releaseSafetyV1').UGCSafetyTarget, reason: import('../contracts/releaseSafetyV1').ModerationReasonV1, details: string, requestID: string): Promise<unknown>
    block?(target: import('../contracts/releaseSafetyV1').UGCSafetyTarget): Promise<unknown>
    deleteComment?(target: import('../contracts/releaseSafetyV1').UGCSafetyTarget): Promise<unknown>
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
    trialEligibility(): Promise<{ eligible: boolean; trialDays: number }>
    claimTrial(): Promise<{ expiresAt: string; status: TasteMapPremiumStatusDTO }>
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
    openHybrid(route: TasteMapHybridRoute, options?: TasteMapHybridNavigationOpenOptions): Promise<TasteMapNavigationStateDTO>
    back(options?: TasteMapNavigationCommandOptions): Promise<TasteMapNavigationStateDTO>
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
