import { describe, expect, it } from 'vitest'
import { membershipSelfResponseV1 } from './membershipV1'

const NOW = new Date('2026-08-29T00:00:00.000Z')

describe('Membership self contract V1', () => {
  it('projects a Development entitlement without pretending it is an App Store purchase', () => {
    const response = membershipSelfResponseV1('premium-tester', {
      isPremium: true,
      source: 'admin_grant',
      startsAt: '2026-01-01T00:00:00.000Z',
      expiresAt: null,
      isLifetime: true,
      entitlements: [{
        source: 'admin_grant', status: 'active', updatedAt: '2026-08-28T12:00:00.000Z',
      }],
    }, true, NOW)

    expect(response).toEqual({
      apiVersion: 1,
      userId: 'premium-tester',
      entitlement: {
        state: 'active', isPremium: true, source: 'development', kind: 'lifetime',
        startsAt: '2026-01-01T00:00:00.000Z', expiresAt: null, isLifetime: true,
        updatedAt: '2026-08-28T12:00:00.000Z',
      },
      verifiedAt: NOW.toISOString(),
    })
    expect(JSON.stringify(response)).not.toContain('admin_grant')
    expect(JSON.stringify(response)).not.toContain('transaction')
    expect(JSON.stringify(response)).not.toContain('note')
  })

  it('returns an explicit Free projection without product or purchase internals', () => {
    const response = membershipSelfResponseV1('tm_free', {
      isPremium: false,
      source: null,
      startsAt: null,
      expiresAt: null,
      isLifetime: false,
      entitlements: [],
    }, false, NOW)

    expect(response.entitlement).toEqual({
      state: 'free', isPremium: false, source: null, kind: 'unspecified',
      startsAt: null, expiresAt: null, isLifetime: false, updatedAt: null,
    })
    expect(Object.keys(response).sort()).toEqual(['apiVersion', 'entitlement', 'userId', 'verifiedAt'])
  })

  it('keeps monthly, annual, lifetime and fixed-term sources neutral', () => {
    const cases = [
      ['app_store_monthly', 'monthly_subscription', false],
      ['app_store_yearly', 'annual_subscription', false],
      ['app_store_lifetime', 'lifetime', true],
      ['promo', 'fixed_term', false],
    ] as const
    for (const [source, kind, isLifetime] of cases) {
      const response = membershipSelfResponseV1('tm_member', {
        isPremium: true, source,
        startsAt: '2026-08-01T00:00:00.000Z',
        expiresAt: isLifetime ? null : '2026-09-01T00:00:00.000Z',
        isLifetime,
        entitlements: [{ source, status: 'active', updatedAt: NOW.toISOString() }],
      }, false, NOW)
      expect(response.entitlement.kind).toBe(kind)
      expect(response.entitlement.source).toBe(source)
    }
  })
})
