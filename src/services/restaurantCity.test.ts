import { describe, expect, it } from 'vitest'
import { restaurantCityComparisonKey, restaurantCityFilterOptions } from './restaurantCity'

describe('Restaurant city filter identity', () => {
  it('deduplicates display aliases without mutating source values', () => {
    const values = ['上海市', ' 上海 ', '杭州市', '杭州', '温州市', '温州', '广州市', '', '  ']
    const before = [...values]
    expect(new Set(restaurantCityFilterOptions(values))).toEqual(new Set(['上海', '杭州', '温州', '广州']))
    expect(values).toEqual(before)
  })

  it('preserves genuine Chinese and overseas city names', () => {
    expect(restaurantCityComparisonKey('杭州')).toBe('杭州')
    expect(restaurantCityComparisonKey('温州')).toBe('温州')
    expect(restaurantCityComparisonKey('东京都')).not.toBe(restaurantCityComparisonKey('东京'))
    expect(restaurantCityFilterOptions(['Ｋａｎｓａｓ　Ｃｉｔｙ', 'Kansas City', 'New  York', 'NEW YORK']))
      .toEqual(['Kansas City', 'NEW YORK'])
    expect(restaurantCityComparisonKey('Kansas City')).not.toBe(restaurantCityComparisonKey('Kansas'))
  })

  it('has stable labels and ordering regardless of incoming snapshot order', () => {
    const values = ['上海市', '上海', 'new york', 'New York', '杭州']
    expect(restaurantCityFilterOptions(values)).toEqual(restaurantCityFilterOptions([...values].reverse()))
  })
})
