import { describe, expect, it } from 'vitest'
import { annualSavingsPercent, type MembershipStorePlan } from './membershipStore'

function plan(period: MembershipStorePlan['period'], price: number, currencyCode = 'CNY'): MembershipStorePlan {
  return { id: period, displayName: period, description: '', displayPrice: `¥${price}`, period, price, currencyCode }
}

describe('annualSavingsPercent', () => {
  it('calculates annual savings only from numeric StoreKit prices in the same currency', () => {
    expect(annualSavingsPercent(plan('monthly', 10), plan('yearly', 100))).toBe(17)
  })

  it('does not invent savings when StoreKit has no comparable numeric price', () => {
    expect(annualSavingsPercent(undefined, plan('yearly', 100))).toBeNull()
    expect(annualSavingsPercent(plan('monthly', 10, 'CNY'), plan('yearly', 100, 'USD'))).toBeNull()
    expect(annualSavingsPercent(plan('monthly', 10), plan('yearly', 120))).toBeNull()
  })
})
