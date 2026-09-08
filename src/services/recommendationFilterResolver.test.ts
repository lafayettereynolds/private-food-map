import { describe, expect, it } from 'vitest'
import { resolveRecommendationFilters, sameCity } from './recommendationFilterResolver'

const anchor = { latitude: 30, longitude: 120 }
const candidate = (kilometers: number, score: number) => ({ city: '杭州市', latitude: 30 + kilometers / 111, longitude: 120, scoreOutOfTen: score })

describe('resolveRecommendationFilters', () => {
  it.each([['杭州', '杭州市'], ['上海', '上海市'], ['温州', '温州市'], ['广州', '广州市'], [' New York ', 'new york'], ['Kansas City', 'kansas city'], ['東京都', '東京都'], ['Ｓａｎ　Ｆｒａｎｃｉｓｃｏ', 'san francisco']])('matches complete city names %s / %s without removing name characters', (left, right) => {
    expect(sameCity(left, right)).toBe(true)
    expect(sameCity(right, left)).toBe(true)
  })
  it.each([['杭州', '杭'], ['温州', '温'], ['广州', '广'], ['上海', '杭州'], ['Kansas City', 'Kansas'], ['东京', '东京都'], ['', ''], ['地区', '地']])('keeps different or missing cities distinct: %s / %s', (left, right) => {
    expect(sameCity(left, right)).toBe(false)
  })
  it('uses the same city identity for the actual recommendation filter', () => {
    expect(resolveRecommendationFilters([candidate(1, 8)], { city: '杭州' }, anchor).results).toHaveLength(1)
  })
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
