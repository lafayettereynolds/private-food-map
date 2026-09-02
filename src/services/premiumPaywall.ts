import type { MembershipFeature } from './featurePolicy'

export type PremiumSourceFeatureKey = MembershipFeature
  | 'profile_entry'
  | 'settings_entry'
  | 'visit_photo_limit'
  | 'companion_recommendation'
  | 'spending_insights'

export const PREMIUM_PAYWALL_OPEN_EVENT = 'taste-map:premium-paywall-open'
export const PREMIUM_ANALYTICS_EVENT = 'taste-map:premium-analytics'

export interface PremiumAnalyticsDetail {
  event: 'paywall_viewed' | 'plan_selected' | 'purchase_started' | 'purchase_succeeded' | 'purchase_failed' | 'restore_started' | 'restore_succeeded' | 'restore_failed' | 'manage_started' | 'manage_succeeded' | 'manage_failed'
  sourceFeatureKey: PremiumSourceFeatureKey
  planId?: string
  message?: string
}

export function openPremiumPaywall(sourceFeatureKey: PremiumSourceFeatureKey = 'profile_entry') {
  if (typeof window === 'undefined') return
  window.dispatchEvent(new CustomEvent(PREMIUM_PAYWALL_OPEN_EVENT, { detail: { sourceFeatureKey } }))
}

export function trackPremiumEvent(detail: PremiumAnalyticsDetail) {
  if (typeof window === 'undefined') return
  window.dispatchEvent(new CustomEvent(PREMIUM_ANALYTICS_EVENT, { detail }))
}

export const PREMIUM_SOURCE_COPY: Record<PremiumSourceFeatureKey, string> = {
  profile_entry: '查看完整会员能力与订阅方案。',
  settings_entry: '管理会员状态、订阅方案与恢复购买。',
  custom_avatar: '解锁自定义头像上传，预设头像仍可免费使用。',
  full_taste_profile: '解锁完整口味档案，把长期记录变成清晰的口味画像。',
  companion_analysis: '解锁最佳饭搭子，了解你和谁最常吃、最合拍。',
  recommendation_source_analysis: '解锁谁最会种草，验证谁的推荐真正适合你。',
  similar_taste: '解锁同味之选与同味评分，找到口味真正接近的人。',
  deep_recommendation: '解锁更完整的推荐依据与个性化解释。',
  advanced_recommendation_filters: '解锁推荐来源、适合场景和饭搭子等高级筛选。',
  monthly_review: '解锁完整月度回顾，重新看见这个月的味觉记忆。',
  annual_review: '解锁完整年度回顾与跨城市食味年鉴。',
  visit_photo_limit: '免费版每次到访可上传 3 张，Premium 可上传 20 张。',
  companion_recommendation: '解锁按饭搭子选择餐厅的能力。',
  spending_insights: '解锁消费结构、价格区间与长期趋势分析。',
}
