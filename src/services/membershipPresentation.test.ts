import { describe, expect, it } from 'vitest'
import type { EffectiveMembership, MembershipEntitlementSource } from '../types/membership'
import { membershipStatusPresentation } from './membershipPresentation'

function entitlement(source: MembershipEntitlementSource, options: Partial<EffectiveMembership> = {}): EffectiveMembership {
  return {
    isPremium: true,
    source,
    startsAt: '2026-08-01T00:00:00.000Z',
    expiresAt: '2026-09-01T00:00:00.000Z',
    isLifetime: false,
    entitlements: [],
    ...options,
  }
}

describe('membershipStatusPresentation', () => {
  it('shows Reward dates without Apple renewal or subscription management',()=>{
    expect(membershipStatusPresentation(entitlement('referral_reward'),'free')).toMatchObject({
      planLabel:'邀请奖励 · 有效期至 2026年09月01日',sourceLabel:'Taste Map 邀请奖励',dateLabel:'有效期至',canManageAppStoreSubscription:false,
    })
  })
  it.each([
    ['app_store_monthly', '月度会员'],
    ['app_store_yearly', '年度会员'],
  ] as const)('allows subscription management for %s', (source, planLabel) => {
    const result = membershipStatusPresentation(entitlement(source), 'free')
    expect(result).toMatchObject({ isPremium: true, planLabel, sourceLabel: 'App Store 订阅', dateLabel: '下次续订', canManageAppStoreSubscription: true })
  })

  it('does not show renewal or subscription management for lifetime purchases', () => {
    const result = membershipStatusPresentation(entitlement('app_store_lifetime', { expiresAt: null, isLifetime: true }), 'free')
    expect(result).toMatchObject({ planLabel: '永久会员', sourceLabel: 'App Store 永久购买', dateLabel: null, dateValue: null, canManageAppStoreSubscription: false })
  })

  it.each([
    ['admin_grant', 'Premium 赠送资格', '管理员赠送'],
    ['promo', 'Premium 活动资格', '活动赠送'],
    ['redeem_code', 'Premium 兑换资格', '兑换码'],
  ] as const)('presents %s without App Store management', (source, planLabel, sourceLabel) => {
    const result = membershipStatusPresentation(entitlement(source), 'free')
    expect(result).toMatchObject({ planLabel, sourceLabel, dateLabel: '有效期至', canManageAppStoreSubscription: false })
  })

  it('never unlocks Premium from a cached profile tier without authority', () => {
    expect(membershipStatusPresentation(null, 'member').isPremium).toBe(false)
    expect(membershipStatusPresentation(null, 'free').isPremium).toBe(false)
  })

  it('renders exact Gift copy without subscription management', () => {
    expect(membershipStatusPresentation(entitlement('gift_annual'), 'free')).toMatchObject({planLabel:'赠送会员 · 有效期至 2026年09月01日',canManageAppStoreSubscription:false})
    expect(membershipStatusPresentation(entitlement('gift_lifetime', {expiresAt:null,isLifetime:true}), 'free')).toMatchObject({planLabel:'永久会员 · 由 Taste Map 赠送',canManageAppStoreSubscription:false})
    expect(membershipStatusPresentation(entitlement('app_store_annual'), 'free').canManageAppStoreSubscription).toBe(true)
  })

  it('lets an authoritative expired entitlement override a stale member tier', () => {
    const result = membershipStatusPresentation({ ...entitlement('promo'), isPremium: false }, 'member')
    expect(result.isPremium).toBe(false)
  })
})
