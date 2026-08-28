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
  photoId: string
  variant: 'thumbnail'
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
  apiVersion: typeof COMMUNITY_API_VERSION
  scope: CommunityFeedScopeV1
  generatedAt: string
  items: PublicContentItemV1[]
  nextCursor: string | null
}
