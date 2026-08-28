export const MEMBERSHIP_API_VERSION = 1 as const

export type MembershipEntitlementSourceV1 =
  | 'app_store_monthly'
  | 'app_store_yearly'
  | 'app_store_lifetime'
  | 'admin_grant'
  | 'promo'
  | 'redeem_code'
  | 'development'

export type MembershipEntitlementKindV1 =
  | 'monthly_subscription'
  | 'annual_subscription'
  | 'lifetime'
  | 'fixed_term'
  | 'unspecified'

export interface EffectiveMembershipProjection {
  isPremium: boolean
  source: Exclude<MembershipEntitlementSourceV1, 'development'> | null
  startsAt: string | null
  expiresAt: string | null
  isLifetime: boolean
  entitlements: Array<{
    source: Exclude<MembershipEntitlementSourceV1, 'development'>
    status: 'active' | 'revoked'
    updatedAt: string
  }>
}

export interface MembershipSelfResponseV1 {
  apiVersion: typeof MEMBERSHIP_API_VERSION
  userId: string
  entitlement: {
    state: 'free' | 'active'
    isPremium: boolean
    source: MembershipEntitlementSourceV1 | null
    kind: MembershipEntitlementKindV1
    startsAt: string | null
    expiresAt: string | null
    isLifetime: boolean
    updatedAt: string | null
  }
  verifiedAt: string
}

export function membershipSelfResponseV1(
  userId: string,
  effective: EffectiveMembershipProjection,
  developmentTestIdentity = false,
  now = new Date(),
): MembershipSelfResponseV1 {
  const source: MembershipEntitlementSourceV1 | null = effective.isPremium
    ? developmentTestIdentity ? 'development' : effective.source
    : null
  const updatedAt = effective.entitlements
    .filter((item) => item.status === 'active')
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))[0]?.updatedAt ?? null
  return {
    apiVersion: MEMBERSHIP_API_VERSION,
    userId,
    entitlement: {
      state: effective.isPremium ? 'active' : 'free',
      isPremium: effective.isPremium,
      source,
      kind: effective.isPremium ? entitlementKind(source, effective.isLifetime) : 'unspecified',
      startsAt: effective.isPremium ? effective.startsAt : null,
      expiresAt: effective.isPremium ? effective.expiresAt : null,
      isLifetime: effective.isPremium && effective.isLifetime,
      updatedAt,
    },
    verifiedAt: now.toISOString(),
  }
}

function entitlementKind(
  source: MembershipEntitlementSourceV1 | null,
  isLifetime: boolean,
): MembershipEntitlementKindV1 {
  if (isLifetime || source === 'app_store_lifetime' || source === 'development') return 'lifetime'
  if (source === 'app_store_monthly') return 'monthly_subscription'
  if (source === 'app_store_yearly') return 'annual_subscription'
  if (source === 'admin_grant' || source === 'promo' || source === 'redeem_code') return 'fixed_term'
  return 'unspecified'
}
