import type { MembershipTier } from '../types/domain'

export type MembershipFeature =
  | 'dish_photos'
  | 'custom_avatar'
  | 'full_taste_profile'
  | 'companion_analysis'
  | 'recommendation_source_analysis'
  | 'similar_taste'
  | 'deep_recommendation'
  | 'advanced_recommendation_filters'
  | 'monthly_review'
  | 'annual_review'
  | 'spending_insights'
  | 'companion_recommendation'

const PREMIUM_FEATURES = new Set<MembershipFeature>([
  'dish_photos',
  'custom_avatar',
  'full_taste_profile',
  'companion_analysis',
  'recommendation_source_analysis',
  'similar_taste',
  'deep_recommendation',
  'advanced_recommendation_filters',
  'monthly_review',
  'annual_review',
  'spending_insights',
  'companion_recommendation',
])

export function canUseFeature(membershipTier: MembershipTier, feature: MembershipFeature) {
  return !PREMIUM_FEATURES.has(feature) || membershipTier === 'member'
}

export function visitPhotoLimit(membershipTier: MembershipTier) {
  return membershipTier === 'member' ? 20 : 2
}
