import { describe, expect, it } from 'vitest'
import { resolveRecommendationFilters } from './recommendationFilterResolver'

const anchor = { latitude: 30, longitude: 120 }
const candidate = (kilometers: number, score: number) => ({ city: '杭州市', latitude: 30 + kilometers / 111, longitude: 120, scoreOutOfTen: score })

describe('resolveRecommendationFilters', () => {
  it('suggests the nearest distance step that restores results', () => {
    const result = resolveRecommendationFilters([candidate(2.2, 8)], { distanceKm: 1 }, anchor)
    expect(result.emptyReason).toBe('DISTANCE_TOO_STRICT')
    expect(result.relaxationSuggestion).toMatchObject({ type: 'distance', to: 3, estimatedResultCount: 1 })
  })

  it('skips distance steps that still have no results', () => {
    const result = resolveRecommendationFilters([candidate(4.2, 8)], { distanceKm: 1 }, anchor)
    expect(result.relaxationSuggestion).toMatchObject({ type: 'distance', to: 5, estimatedResultCount: 1 })
  })

  it('suggests lowering only the rating constraint', () => {
    const result = resolveRecommendationFilters([candidate(.5, 8.4)], { distanceKm: 1, ratingMinimum: 9 }, anchor)
    expect(result.emptyReason).toBe('RATING_TOO_STRICT')
    expect(result.relaxationSuggestion).toMatchObject({ type: 'rating', to: 8, estimatedResultCount: 1 })
  })

  it('does not count sorting or defaults as active filters', () => {
    const result = resolveRecommendationFilters([candidate(.5, 8.4)], {}, anchor)
    expect(result.activeFilters).toEqual([])
    expect(result.results).toHaveLength(1)
  })
})
