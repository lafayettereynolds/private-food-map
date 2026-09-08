import type { ProfileAvatarPresetContract } from './profileContract'
import type { RestaurantPlaceProvider } from '../types/restaurantIdentity'

export const COMMUNITY_API_VERSION = 1 as const
export const COMMUNITY_DEFAULT_LIMIT = 20
export const COMMUNITY_MAX_LIMIT = 50

export type CommunityFeedScopeV1 = 'following' | 'latest'
export type PublicContentSectionV1 = 'visits' | 'want_to_go'
export type PublicContentKindV1 = 'visit' | 'want_to_go'
export type PublicContentCacheScopeV1 = 'public' | 'friends'
export type PublicContentVisibilityV1 = 'public' | 'friends'
export type PublicContentViewerStateV1 = 'none' | 'want_to_go' | 'visited'

export interface PublicContentPlaceIdentityV1 {
  provider: RestaurantPlaceProvider
  externalId: string
  isPrimary: boolean
}

export interface PublicContentPhotoV1 {
  photoKind?: string
  photoId: string
  variant: 'thumbnail'
  sourceType?: 'currentOwnerPhoto' | 'activityAuthorPhoto' | 'publicUGC'
  restaurantId?: string
  visitId?: string | null
  ownerUserId?: string
  visibility?: PublicContentVisibilityV1
  createdAt?: string
  exportAllowed?: boolean
}

/** Explicit allowlist. It is not a User row or an Own Profile contract. */
export interface PublicContentUserV1 {
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

/** Shared Restaurant projection. Browsing it never creates a viewer-owned Restaurant. */
export interface PublicContentRestaurantV1 {
  globalKey: string
  placeIdentities: PublicContentPlaceIdentityV1[]
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags: string[]
  pricePerPerson: number | null
  merchantImageUrl: string | null
  markerEmoji: string
  photo: PublicContentPhotoV1 | null
}

/**
 * Public Visit allowlist. Spend, party size, Companion, RecommendationSource,
 * private context, auth identity and storage metadata intentionally do not exist here.
 */
export interface PublicVisitV1 {
  id: string
  ownerUserId: string
  restaurantGlobalKey: string
  visitedAt: string
  rating: number | null
  note: string | null
  visibility: PublicContentVisibilityV1
  photos: PublicContentPhotoV1[]
  updatedAt: string
}

export interface PublicContentItemV1 {
  id: string
  kind: PublicContentKindV1
  eventAt: string
  updatedAt: string
  user: PublicContentUserV1
  restaurant: PublicContentRestaurantV1
  visit: PublicVisitV1 | null
  viewerState: PublicContentViewerStateV1
  cacheScope: PublicContentCacheScopeV1
  engagement: CommunityEngagementSummaryV1
}

export interface CommunityEngagementSummaryV1 {
  likedByViewer: boolean
  likeCount: number
  commentCount: number
}

export interface CommunityCommentV1 {
  apiVersion: typeof COMMUNITY_API_VERSION
  id: string
  contentType: 'visit'
  contentId: string
  body: string
  author: PublicContentUserV1
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  serverVersion: number
}

export interface CommunityCommentPageV1 {
  apiVersion: typeof COMMUNITY_API_VERSION
  items: CommunityCommentV1[]
  nextCursor: string | null
}

export interface CommunityLikeMutationV1 {
  apiVersion: typeof COMMUNITY_API_VERSION
  likedByViewer: boolean
  likeCount: number
  commentCount: number
  duplicate: boolean
}

export interface CommunityCommentMutationV1 {
  apiVersion: typeof COMMUNITY_API_VERSION
  comment: CommunityCommentV1
  likeCount: number
  commentCount: number
}

export interface PublicProfileTasteSummaryV1 {
  topTags: string[]
  averageRating: number | null
  ratedVisitCount: number
  summary: string | null
}

export interface PublicProfileFootprintV1 {
  city: string
  restaurantCount: number
  visitCount: number
}

export interface PublicProfileOverviewV1 {
  apiVersion: typeof COMMUNITY_API_VERSION
  targetUserId: string
  friendCount: number
  followingCount: number
  followerCount: number
  commonWantToGoCount: number
  commonWantToGo: PublicContentRestaurantV1[]
  representativeRestaurants: PublicContentRestaurantV1[]
  footprints: PublicProfileFootprintV1[]
  tasteSummary: PublicProfileTasteSummaryV1
}

export interface PublicContentStatisticsV1 {
  visibleRestaurantCount: number
  visibleVisitCount: number
  visibleWantToGoCount: number
}

export interface PublicProfileContentPageV1 {
  apiVersion: typeof COMMUNITY_API_VERSION
  targetUserId: string
  section: PublicContentSectionV1
  generatedAt: string
  statistics: PublicContentStatisticsV1
  items: PublicContentItemV1[]
  nextCursor: string | null
}

export interface CommunityFeedPageV1 {
  filterCapabilities?: import('./discoveryFilters').DiscoveryFilterCapabilities
  filterTaxonomy?: import('./discoveryFilters').DiscoveryFilterTaxonomy
  appliedQuery?: import('./discoveryFilters').DiscoveryAppliedQuery
  /** Optional for older servers; present and normalized for city-query support. Empty means all cities. */
  city?: string
  apiVersion: typeof COMMUNITY_API_VERSION
  scope: CommunityFeedScopeV1
  generatedAt: string
  items: PublicContentItemV1[]
  nextCursor: string | null
}
