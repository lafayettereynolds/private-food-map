export type MembershipPlanPeriod = 'monthly' | 'yearly'

export interface MembershipStorePlan {
  id: string
  displayName: string
  description: string
  displayPrice: string
  period: MembershipPlanPeriod
  price?: number
  currencyCode?: string
}

export interface MembershipPurchaseResult {
  success: boolean
  transactionId?: string
}

interface NativeMembershipStoreBridge {
  loadPlans(): Promise<MembershipStorePlan[]>
  purchase(productId: string): Promise<MembershipPurchaseResult>
  restorePurchases(): Promise<MembershipPurchaseResult>
  manageSubscriptions?(): Promise<void>
}

declare global {
  interface Window {
    TasteMapMembershipStore?: NativeMembershipStoreBridge
  }
}

export class MembershipStoreUnavailableError extends Error {
  constructor() {
    super('暂时无法获取订阅信息。请在 iPhone App 中查看价格或恢复购买。')
    this.name = 'MembershipStoreUnavailableError'
  }
}

function bridge() {
  if (typeof window === 'undefined' || !window.TasteMapMembershipStore) throw new MembershipStoreUnavailableError()
  return window.TasteMapMembershipStore
}

export const MembershipStore = {
  async loadPlans() {
    const plans = await bridge().loadPlans()
    return plans.filter((plan) => plan.period === 'monthly' || plan.period === 'yearly')
  },
  async purchase(productId: string) { return bridge().purchase(productId) },
  async restorePurchases() { return bridge().restorePurchases() },
  async manageSubscriptions() {
    const nativeBridge = bridge()
    if (!nativeBridge.manageSubscriptions) throw new MembershipStoreUnavailableError()
    return nativeBridge.manageSubscriptions()
  },
}

export function annualSavingsPercent(monthly?: MembershipStorePlan, yearly?: MembershipStorePlan) {
  if (!monthly?.price || !yearly?.price || !monthly.currencyCode || monthly.currencyCode !== yearly.currencyCode) return null
  const fullYear = monthly.price * 12
  if (yearly.price >= fullYear) return null
  return Math.round((1 - yearly.price / fullYear) * 100)
}
