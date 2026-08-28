import type { ProfileAvatarPresetContract } from './profileContract'

export const SOCIAL_API_VERSION = 1 as const
export const SOCIAL_RELATIONSHIP_STATES = [
  'none', 'outgoing_request', 'incoming_request', 'friends',
] as const

export type SocialRelationshipStateV1 = typeof SOCIAL_RELATIONSHIP_STATES[number]

/** Public search/relationship allowlist. Authentication and private owner fields are absent. */
export interface SocialUserSummaryV1 {
  userId: string
  displayName: string
  bio: string | null
  city: string | null
  avatarPhotoId: string | null
  avatarPresetId: ProfileAvatarPresetContract
}
export interface SocialUserResultV1 {
  profile: SocialUserSummaryV1
  friendshipId: string | null
  friendshipState: SocialRelationshipStateV1
  isFollowing: boolean
}

export interface SocialPageV1<T> {
  apiVersion: typeof SOCIAL_API_VERSION
  items: T[]
  nextCursor: string | null
}

export interface FriendshipV1 {
  apiVersion: typeof SOCIAL_API_VERSION
  id: string
  requesterUserId: string
  addresseeUserId: string
  state: Exclude<SocialRelationshipStateV1, 'none'> | 'rejected' | 'removed'
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  serverVersion: number
}

export interface FollowV1 {
  apiVersion: typeof SOCIAL_API_VERSION
  id: string
  followerUserId: string
  followedUserId: string
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  serverVersion: number
}
