import type { MembershipTier } from '../types/domain'
import type { EffectiveMembership, MembershipEntitlementSource } from '../types/membership'

export interface MembershipStatusPresentation {
  isPremium: boolean
  planLabel: string
  sourceLabel: string
  dateLabel: string | null
  dateValue: string | null
  canManageAppStoreSubscription: boolean
}

const APP_STORE_SUBSCRIPTIONS = new Set<MembershipEntitlementSource>(['app_store_monthly', 'app_store_yearly'])

export function membershipStatusPresentation(entitlement: EffectiveMembership | null, fallbackTier: MembershipTier): MembershipStatusPresentation {
  const isPremium = entitlement?.isPremium ?? fallbackTier === 'member'
  const source = entitlement?.source ?? null
  const expiresAt = entitlement?.expiresAt ?? null
  const startsAt = entitlement?.startsAt ?? null
  const isLifetime = Boolean(entitlement?.isLifetime || source === 'app_store_lifetime')
  const canManageAppStoreSubscription = Boolean(source && APP_STORE_SUBSCRIPTIONS.has(source))

  return {
    isPremium,
    planLabel: planLabel(source, isLifetime),
    sourceLabel: sourceLabel(source),
    dateLabel: isLifetime ? null : canManageAppStoreSubscription && expiresAt ? '下次续订' : expiresAt ? '有效期至' : startsAt ? '生效时间' : null,
    dateValue: isLifetime ? null : formatDate(expiresAt ?? startsAt),
    canManageAppStoreSubscription,
  }
}

function planLabel(source: MembershipEntitlementSource | null, isLifetime: boolean) {
  if (isLifetime) return '永久会员'
  if (source === 'app_store_monthly') return '月度会员'
  if (source === 'app_store_yearly') return '年度会员'
  if (source === 'admin_grant') return 'Premium 赠送资格'
  if (source === 'promo') return 'Premium 活动资格'
  if (source === 'redeem_code') return 'Premium 兑换资格'
  return 'Taste Map Premium'
}

function sourceLabel(source: MembershipEntitlementSource | null) {
  if (source === 'app_store_monthly' || source === 'app_store_yearly') return 'App Store 订阅'
  if (source === 'app_store_lifetime') return 'App Store 永久购买'
  if (source === 'admin_grant') return '管理员赠送'
  if (source === 'promo') return '活动赠送'
  if (source === 'redeem_code') return '兑换码'
  return 'Taste Map 会员资格'
}

function formatDate(value: string | null) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' }).format(date)
}
