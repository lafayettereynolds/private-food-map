import { describe, expect, it } from 'vitest'
import { inferredActualSpend, resolveVisitActualSpend, summarizeVisitSpend } from './visitSpend'

describe('visit spend', () => {
  it('keeps an explicitly recorded personal amount authoritative', () => {
    expect(inferredActualSpend(600, 128.5, 'aa', 3)).toBe(128.5)
  })

  it('recovers deterministic personal spend from the former one-price Hybrid form', () => {
    expect(inferredActualSpend(168, null, null, 1)).toBe(168)
    expect(inferredActualSpend(300, null, 'aa', 3)).toBe(100)
    expect(inferredActualSpend(480, null, 'my_treat', 4)).toBe(480)
    expect(inferredActualSpend(480, null, 'treated', 4)).toBe(0)
  })

  it('does not guess a personal amount for separate or unspecified other payments', () => {
    expect(inferredActualSpend(480, null, 'separate', 4)).toBeNull()
    expect(inferredActualSpend(480, null, 'other', 4)).toBeNull()
  })

  it('excludes deleted and unrecorded visits while retaining a real zero spend', () => {
    const summary = summarizeVisitSpend([
      { deletedAt: null, totalPrice: 300, myActualSpend: 150, paymentMode: 'aa', partySize: 2 },
      { deletedAt: null, totalPrice: null, myActualSpend: null, paymentMode: 'treated', partySize: 2 },
      { deletedAt: null, totalPrice: 200, myActualSpend: null, paymentMode: 'other', partySize: 2 },
      { deletedAt: '2026-09-05T00:00:00Z', totalPrice: 999, myActualSpend: 999, paymentMode: null, partySize: 1 },
    ])
    expect(summary).toEqual({ total: 150, recordedVisitCount: 2, unrecordedVisitCount: 1 })
  })

  it('rejects invalid money rather than contaminating the aggregate', () => {
    expect(resolveVisitActualSpend({ deletedAt: null, totalPrice: Number.NaN, myActualSpend: null, paymentMode: null, partySize: 1 })).toBeNull()
    expect(resolveVisitActualSpend({ deletedAt: null, totalPrice: null, myActualSpend: -1, paymentMode: 'other', partySize: 1 })).toBeNull()
  })

  it('normalizes legacy empty payment modes and rejects unknown runtime values without producing NaN', () => {
    const legacyEmpty = { deletedAt: null, totalPrice: 168, myActualSpend: null, paymentMode: '', partySize: 1 } as unknown as Parameters<typeof resolveVisitActualSpend>[0]
    const unknown = { deletedAt: null, totalPrice: 999, myActualSpend: null, paymentMode: 'legacy_unknown', partySize: 1 } as unknown as Parameters<typeof resolveVisitActualSpend>[0]
    expect(resolveVisitActualSpend(legacyEmpty)).toBe(168)
    expect(resolveVisitActualSpend(unknown)).toBeNull()
    expect(summarizeVisitSpend([legacyEmpty, unknown])).toEqual({ total: 168, recordedVisitCount: 1, unrecordedVisitCount: 1 })
  })
})
