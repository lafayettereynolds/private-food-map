export type MembershipEntitlementSource =
  | 'app_store_monthly'
  | 'app_store_annual'
  | 'gift_annual'
  | 'gift_lifetime'
  | 'app_store_subscription'
  | 'promotion'
  | 'signup_trial'
  | 'referral_reward'
  | 'app_store_yearly'
  | 'app_store_lifetime'
  | 'admin_grant'
  | 'promo'
  | 'redeem_code'

export interface MembershipEntitlement {
  id: string
  userId: string
  source: MembershipEntitlementSource
  startsAt: string
  startedAt?: string
  grantedAt?: string
  grantedBy?: string | null
  expiresAt: string | null
  isLifetime: boolean
  status: 'active' | 'revoked'
  note: string
  createdAt: string
  updatedAt: string
  revokedAt: string | null
}

export interface EffectiveMembership {
  isPremium: boolean
  source: MembershipEntitlementSource | null
  startsAt: string | null
  expiresAt: string | null
  isLifetime: boolean
  entitlements: MembershipEntitlement[]
}

export interface MembershipSelfResponse {
  entitlement: EffectiveMembership
  isAdmin: boolean
}

export interface MembershipAdminUser {
  id: string
  nickname: string
  email: string | null
  city: string
  entitlement: EffectiveMembership
}
