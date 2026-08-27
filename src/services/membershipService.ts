import { SOCIAL_API_ENABLED, localTestHeaders } from '../config/appEnvironment'
import { apiURL } from '../config/apiEnvironment'
import type { MembershipAdminUser, MembershipSelfResponse } from '../types/membership'

export const MEMBERSHIP_CHANGED_EVENT = 'taste-map:membership-changed'

export function notifyMembershipChanged() {
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(MEMBERSHIP_CHANGED_EVENT))
}

async function membershipFetch<Result>(input: string, init: RequestInit = {}): Promise<Result> {
  const response = await fetch(apiURL(input), {
    ...init,
    headers: { 'content-type': 'application/json', ...localTestHeaders(), ...init.headers },
  })
  const payload = await response.json().catch(() => ({})) as Result & { error?: string }
  if (!response.ok) throw new Error(payload.error || '会员服务暂时不可用。')
  return payload
}

export const MembershipService = {
  async getEntitlement(): Promise<MembershipSelfResponse> {
    if (!SOCIAL_API_ENABLED) {
      return {
        entitlement: { isPremium: false, source: null, startsAt: null, expiresAt: null, isLifetime: false, entitlements: [] },
        isAdmin: false,
      }
    }
    return membershipFetch('/api/membership')
  },

  async refresh(): Promise<MembershipSelfResponse> {
    const result = await this.getEntitlement()
    notifyMembershipChanged()
    return result
  },

  async searchUsers(query = ''): Promise<MembershipAdminUser[]> {
    const result = await membershipFetch<{ users: MembershipAdminUser[] }>(`/api/admin/memberships?q=${encodeURIComponent(query.trim())}`)
    return result.users
  },

  async grant(userId: string, duration: '1m' | '3m' | '6m' | '1y' | 'lifetime' | 'custom', expiresAt: string | null, note: string) {
    const result = await membershipFetch('/api/admin/memberships', {
      method: 'POST',
      body: JSON.stringify({ action: 'grant', userId, duration, expiresAt, note }),
    })
    notifyMembershipChanged()
    return result
  },

  async update(entitlementId: string, expiresAt: string | null, isLifetime: boolean, note: string) {
    const result = await membershipFetch('/api/admin/memberships', {
      method: 'POST',
      body: JSON.stringify({ action: 'update', entitlementId, expiresAt, isLifetime, note }),
    })
    notifyMembershipChanged()
    return result
  },

  async revoke(entitlementId: string, reason: string) {
    const result = await membershipFetch('/api/admin/memberships', {
      method: 'POST',
      body: JSON.stringify({ action: 'revoke', entitlementId, reason }),
    })
    notifyMembershipChanged()
    return result
  },
}
