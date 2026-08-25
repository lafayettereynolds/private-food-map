import { CLOUD_SYNC_ENABLED } from '../config/appEnvironment'
import type { MembershipAdminUser, MembershipSelfResponse } from '../types/membership'

async function membershipFetch<Result>(input: string, init: RequestInit = {}): Promise<Result> {
  const response = await fetch(input, {
    ...init,
    headers: { 'content-type': 'application/json', ...init.headers },
  })
  const payload = await response.json().catch(() => ({})) as Result & { error?: string }
  if (!response.ok) throw new Error(payload.error || '会员服务暂时不可用。')
  return payload
}

export const MembershipService = {
  async getEntitlement(): Promise<MembershipSelfResponse> {
    if (!CLOUD_SYNC_ENABLED) {
      return {
        entitlement: { isPremium: false, source: null, startsAt: null, expiresAt: null, isLifetime: false, entitlements: [] },
        isAdmin: false,
      }
    }
    return membershipFetch('/api/membership')
  },

  async searchUsers(query = ''): Promise<MembershipAdminUser[]> {
    const result = await membershipFetch<{ users: MembershipAdminUser[] }>(`/api/admin/memberships?q=${encodeURIComponent(query.trim())}`)
    return result.users
  },

  grant(userId: string, duration: '1m' | '3m' | '6m' | '1y' | 'lifetime' | 'custom', expiresAt: string | null, note: string) {
    return membershipFetch('/api/admin/memberships', {
      method: 'POST',
      body: JSON.stringify({ action: 'grant', userId, duration, expiresAt, note }),
    })
  },

  update(entitlementId: string, expiresAt: string | null, isLifetime: boolean, note: string) {
    return membershipFetch('/api/admin/memberships', {
      method: 'POST',
      body: JSON.stringify({ action: 'update', entitlementId, expiresAt, isLifetime, note }),
    })
  },

  revoke(entitlementId: string, reason: string) {
    return membershipFetch('/api/admin/memberships', {
      method: 'POST',
      body: JSON.stringify({ action: 'revoke', entitlementId, reason }),
    })
  },
}
