import { describe, expect, it } from 'vitest'
import { normalizeRecommendationPreferenceEventV1 as event, normalizeRecommendationPreferencesPushV1 as push } from './recommendationPreferencesV1'

const sample = () => ({ eventID: 'event-a', aliases: ['AMAP:A', 'local-a'], source: 'explicit_dismissal', occurredAt: '2026-09-07T08:00:00Z', intent: null })
describe('Recommendation preferences V1 contract', () => {
  it('canonicalizes stable aliases without inferring names, intent or receive time', () => {
    expect(event({ ...sample(), aliases: ['local-a', 'AMAP:A', 'amap:a'] })).toEqual({
      ...sample(), aliases: ['amap:a', 'local-a'], occurredAt: '2026-09-07T08:00:00.000Z',
    })
  })
  it('preserves unknown historical time and exact-only legacy exclusions', () => {
    expect(event({ ...sample(), source: 'legacy_exclusion', occurredAt: null }).intent).toBeNull()
    for (const change of [{ occurredAt: sample().occurredAt }, { intent: { classifierVersion: 1, brandID: 'kfc', context: 'everyday_fast_food' } }]) {
      expect(() => event({ ...sample(), source: 'legacy_exclusion', occurredAt: null, ...change })).toThrow()
    }
    expect(event({ ...sample(), source: 'legacy_intent', occurredAt: null, intent: { classifierVersion: 1, brandID: null, context: 'snack_takeaway' } }).occurredAt).toBeNull()
  })
  it('rejects unsupported classifications and internally contradictory brand/context', () => {
    for (const intent of [undefined, {}, { classifierVersion: 2, brandID: null, context: null },
      { classifierVersion: 1, brandID: 'unknown', context: null }, { classifierVersion: 1, brandID: 'kfc', context: 'snack_takeaway' },
      { classifierVersion: 1, brandID: null, context: '日料' }]) expect(() => event({ ...sample(), intent })).toThrow()
  })
  it('rejects ownership injection, aggregate counters, invalid dates and alias overflow', () => {
    for (const change of [{ userID: 'another' }, { contextCounts: { snack_takeaway: 99 } }, { aliases: [] },
      { aliases: ['Name And Address'] }, { aliases: ['a'.repeat(257)] }, { aliases: Array(33).fill('a') },
      { occurredAt: '2026-02-30T00:00:00Z' }, { occurredAt: null }, { eventID: 'bad id' }]) expect(() => event({ ...sample(), ...change })).toThrow()
  })
  it('requires versioned bounded nonempty batches with unique mutation IDs', () => {
    expect(push({ apiVersion: 1, events: [sample()] }).events).toHaveLength(1)
    for (const body of [{ apiVersion: 2, events: [sample()] }, { apiVersion: 1, events: [] },
      { apiVersion: 1, events: [sample(), sample()] }, { apiVersion: 1, events: [sample()], ownerID: 'other' },
      { apiVersion: 1, events: Array.from({ length: 101 }, (_, i) => ({ ...sample(), eventID: `event-${i}` })) }]) expect(() => push(body)).toThrow()
  })
})
