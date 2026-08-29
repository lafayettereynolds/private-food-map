import type { PublicContentRestaurantV1 } from './communityContract'
import type { SocialUserResultV1, SocialUserSummaryV1 } from './socialContract'

export const SOCIAL_COLLABORATION_API_VERSION = 1 as const

export type CompanionLinkStatusV1 = 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'unlinked'
export type CompanionLinkScopeV1 = 'incoming' | 'outgoing' | 'active'
export type CompanionLinkActionV1 = 'accept' | 'reject' | 'cancel' | 'unlink'

export interface SocialSuggestionV1 {
  user: SocialUserResultV1
  reasons: string[]
}

export interface SocialSuggestionPageV1 {
  apiVersion: typeof SOCIAL_COLLABORATION_API_VERSION
  items: SocialSuggestionV1[]
  nextCursor: string | null
}

export interface CompanionLinkRequestV1 {
  apiVersion: typeof SOCIAL_COLLABORATION_API_VERSION
  id: string
  companionId: string
  companionDisplayName: string
  requesterUserId: string
  targetUserId: string
  status: CompanionLinkStatusV1
  otherUser: SocialUserSummaryV1
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  serverVersion: number
}

export interface CompanionLinkPageV1 {
  apiVersion: typeof SOCIAL_COLLABORATION_API_VERSION
  scope: CompanionLinkScopeV1
  items: CompanionLinkRequestV1[]
  nextCursor: string | null
}

export type SharedMealStatusV1 = 'pending' | 'accepted' | 'declined' | 'revoked'
export type SharedMealScopeV1 = 'incoming' | 'sent' | 'accepted'
export type SharedMealParticipantActionV1 = 'accept' | 'decline' | 'attach'

export interface SharedMealInvitationV1 {
  apiVersion: typeof SOCIAL_COLLABORATION_API_VERSION
  mealId: string
  participantId: string
  sourceVisitId: string
  inviter: SocialUserSummaryV1
  participant: SocialUserSummaryV1
  participantUserId: string
  restaurant: PublicContentRestaurantV1
  occurredAt: string
  visibility: 'private' | 'friends' | 'public'
  status: SharedMealStatusV1
  visitId: string | null
  createdAt: string
  updatedAt: string
  revokedAt: string | null
  serverVersion: number
}

export interface SharedMealPageV1 {
  apiVersion: typeof SOCIAL_COLLABORATION_API_VERSION
  scope: SharedMealScopeV1
  items: SharedMealInvitationV1[]
  nextCursor: string | null
}

export interface SharedMealInviteResponseV1 {
  apiVersion: typeof SOCIAL_COLLABORATION_API_VERSION
  mealId: string
  duplicate: boolean
  invitations: SharedMealInvitationV1[]
}
