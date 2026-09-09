import { describe, expect, it } from 'vitest'
import { predictLiking } from './predictedLiking'
import { normalizeDiscoveryFilters, discoveryFiltersFingerprint, discoveryFilterCapabilityIssues } from './discoveryFilters'
const target = { id: 'target', tags: ['日料'], city: '杭州', price: null }
describe('independent personal recommendation dimensions', () => {
  it('estimates historical rating, not similarity or public popularity', () => {
    const history = [{ ...target, id: 'past', scoreOutOfTen: 4, visitCount: 2, ratedVisitCount: 2 }]
    expect(predictLiking(target, history)).toEqual({ scoreOutOfTen: 4, ratedRestaurantCount: 1,
      ratedVisitCount: 2, matchedRestaurantCount: 1, method: 'owner_history_weighted_rating_v1' })
    expect(predictLiking(target, [{ ...history[0], scoreOutOfTen: 9 }]).scoreOutOfTen).toBe(9)
  })
  it('does not use the target or missing/invalid ratings as evidence', () => {
    expect(predictLiking(target, [{ ...target, scoreOutOfTen: 10 }, { ...target, id: 'unrated' },
      { ...target, id: 'invalid', scoreOutOfTen: NaN }]).scoreOutOfTen).toBeNull()
  })
  it('binds separate score and percent filters to the query fingerprint', () => {
    const filters = normalizeDiscoveryFilters({ minimumPredictedLikingOutOfTen: 8, minimumTasteMatchPercent: 90 })
    expect(filters.minimumPredictedLikingOutOfTen).toBe(8)
    expect(filters.minimumTasteMatchPercent).toBe(90)
    expect(discoveryFilterCapabilityIssues(filters)).toHaveLength(2)
    expect(discoveryFiltersFingerprint(filters)).not.toBe(discoveryFiltersFingerprint({ minimumPredictedLikingOutOfTen: 9, minimumTasteMatchPercent: 90 }))
    expect(discoveryFiltersFingerprint({ minimumTasteMatchPercent: null })).toBe(discoveryFiltersFingerprint())
    for (const filters of [{ minimumPredictedLikingOutOfTen: 11 }, { minimumTasteMatchPercent: 101 }, { minimumPredictedLikingOutOfTen: '8' }]) {
      expect(() => normalizeDiscoveryFilters(filters)).toThrow()
    }
  })
})
