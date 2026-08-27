import { describe, expect, it } from 'vitest'
import { canUseFeature, visitPhotoLimit, type MembershipFeature } from './featurePolicy'

const premiumFeatures: MembershipFeature[] = [
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
]

describe('Premium feature policy', () => {
  it('keeps Premium analysis and advanced recommendation features unavailable to free users', () => {
    premiumFeatures.forEach((feature) => expect(canUseFeature('free', feature)).toBe(false))
  })

  it('unlocks the same feature catalog for members', () => {
    premiumFeatures.forEach((feature) => expect(canUseFeature('member', feature)).toBe(true))
  })

  it('uses the agreed per-visit photo limits', () => {
    expect(visitPhotoLimit('free')).toBe(3)
    expect(visitPhotoLimit('member')).toBe(20)
  })
})
