import type { ProfileAvatarPresetContract } from './profileContract'
import type { RestaurantPlaceProvider } from '../types/restaurantIdentity'
import { RECOMMENDATION_EVIDENCE_POLICY } from './recommendationEvidencePolicy'

export const DISCOVERY_API_VERSION = 1 as const
export const DISCOVERY_DEFAULT_LIMIT = 20
export const DISCOVERY_MAX_LIMIT = 50
export const DISCOVERY_SIMILAR_TASTE_MINIMUM_SHARED_RESTAURANTS = RECOMMENDATION_EVIDENCE_POLICY.forming.minimumSharedRestaurants
export const DISCOVERY_TREND_WINDOWS = [7, 30] as const
/** User-facing Discovery qualification is defined on the 10-point scale. */
export const DISCOVERY_MINIMUM_QUALIFIED_SCORE_OUT_OF_TEN = 7.5
/** Legacy Visit.rating storage remains 5-point for API compatibility only. */
export const DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE =
  DISCOVERY_MINIMUM_QUALIFIED_SCORE_OUT_OF_TEN / 2

export type DiscoveryModeV1 = 'for_you' | 'similar_taste' | 'trending'
export type DiscoveryViewerRestaurantStateV1 = 'none' | 'want_to_go' | 'visited'
export type DiscoveryCacheScopeV1 = 'public' | 'friends'
export type DiscoveryConfidenceV1 = 'insufficient' | 'low' | 'medium' | 'high'
export type DiscoveryReasonCodeV1 =
  | 'COLD_START_TRENDING'
  | 'TASTE_TAG_MATCH'
  | 'HIGH_CUISINE_MATCH'
  | 'REPEAT_VISIT_PATTERN'
  | 'PRICE_RANGE_MATCH'
  | 'SHORT_TERM_DIVERSITY'
  | 'SOURCE_VISIT_RATING'
  | 'SIMILAR_USERS'
  | 'FRIEND_HIGH_RATING'
  | 'FOLLOWING_HIGH_RATING'
  | 'COMMUNITY_QUALITY'
  | 'TRENDING_UNIQUE_USERS'
  | 'RECENT_WANT_TO_GO'
  | 'INITIAL_HISTORY_MATCH'
  | 'WANT_TO_GO_MATCH'

export interface DiscoveryPlaceIdentityV1 {
  provider: RestaurantPlaceProvider
  externalId: string
  isPrimary: boolean
}

export interface DiscoveryPhotoProjectionV1 {
  photoKind?: string
  photoId: string
  variant: 'thumbnail'
  sourceType?: 'currentOwnerPhoto' | 'activityAuthorPhoto' | 'publicUGC'
  restaurantId?: string
  visitId?: string | null
  ownerUserId?: string
  visibility?: 'private' | 'friends' | 'public'
  createdAt?: string
  exportAllowed?: boolean
}

export interface DiscoveryRestaurantProjectionV1 {
  globalKey: string
  placeIdentities: DiscoveryPlaceIdentityV1[]
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags: string[]
  pricePerPerson: number | null
  merchantImageUrl: string | null
  markerEmoji: string
  photo: DiscoveryPhotoProjectionV1 | null
}

export interface DiscoveryPublicUserProjectionV1 {
  userId: string
  displayName: string
  bio: string | null
  city: string | null
  avatarPhotoId: string | null
  avatarPresetId: ProfileAvatarPresetContract
  friendshipId: string | null
  friendshipState: 'none' | 'outgoing_request' | 'incoming_request' | 'friends'
  isFollowing: boolean
}

/**
 * The concrete public/friends-visible visit that caused this placement.
 * This is intentionally separate from restaurant-level rating aggregates:
 * cards tell the story of one real activity, while aggregate ratings belong
 * to the restaurant detail context.
 */
export interface DiscoveryActivityProjectionV1 {
  visitId: string
  visitedAt: string
  rating: number | null
  /** Complete eligible album for this Visit, never photos from another Visit. */
  photos?: DiscoveryPhotoProjectionV1[]
}

export interface DiscoveryRatingProjectionV1 {
  value: number | null
  sampleCount: number
}

export interface DiscoveryRatingsV1 {
  mine: DiscoveryRatingProjectionV1
  community: DiscoveryRatingProjectionV1
  friends: DiscoveryRatingProjectionV1
  similarTaste: DiscoveryRatingProjectionV1
}

export interface DiscoveryReasonV1 {
  code: DiscoveryReasonCodeV1
  text: string
  evidence?: import('../services/recommendationHistoryReasons').RecommendationReasonEvidence
}

export interface DiscoveryTrendContextV1 {
  windowDays: 7 | 30
  uniqueVisitorCount: number
  wantToGoCount: number
}

export interface DiscoverySimilarityContextV1 {
  percent: number
  sharedRestaurantCount: number
  evidenceState?: import('./recommendationEvidencePolicy').TasteEvidenceState
  weightedSimilarity?: number
  userMeanOutOfTen?: number
}

export interface DiscoveryCardV1 {
  id: string
  mode: DiscoveryModeV1
  restaurant: DiscoveryRestaurantProjectionV1
  viewerState: DiscoveryViewerRestaurantStateV1
  ratings: DiscoveryRatingsV1
  reasons: DiscoveryReasonV1[]
  sourceUser: DiscoveryPublicUserProjectionV1 | null
  activity: DiscoveryActivityProjectionV1 | null
  similarity: DiscoverySimilarityContextV1 | null
  tasteEvidence?: {
    evidenceState: import('./recommendationEvidencePolicy').TasteEvidenceState
    sharedRestaurantCount: number
    supporterCount: number
    aggregation: 'equal_user_mean'
    latestVisibleVisitAt: string
    records: Array<{ user: DiscoveryPublicUserProjectionV1; visitId: string; visitedAt: string; rating: number | null }>
  }
  trend: DiscoveryTrendContextV1 | null
  cacheScope: DiscoveryCacheScopeV1
  rank: number
  score: number
  /** History-derived matching index, never a calibrated probability. */
  personalTastePercent?: number | null
  predictedLiking?: import('./predictedLiking').PredictedLiking | null
  calibratedLikeProbability?: import('./recommendationSignal').CalibratedLikeProbability | null
}

export interface DiscoveryPageV1 {
  filterCapabilities?: import('./discoveryFilters').DiscoveryFilterCapabilities
  filterTaxonomy?: import('./discoveryFilters').DiscoveryFilterTaxonomy
  appliedQuery?: import('./discoveryFilters').DiscoveryAppliedQuery
  apiVersion: typeof DISCOVERY_API_VERSION
  mode: DiscoveryModeV1
  city: string
  personalizationConfidence: DiscoveryConfidenceV1
  generatedAt: string
  items: DiscoveryCardV1[]
  nextCursor: string | null
  evidenceAvailability?: {
    personalRatedRestaurantCount: number
    personalScoreStandardDeviationOutOfTen: number
    personalEvidence: 'insufficient' | 'eligible'
    localDirectRestaurantCount: number
  }
}
