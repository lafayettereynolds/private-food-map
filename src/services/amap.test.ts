import { describe, expect, it } from 'vitest'
import { normalizeRestaurantKeyword } from './restaurantSearch'

describe('restaurant keyword normalization', () => {
  it('supports common restaurant brand names', () => {
    expect(normalizeRestaurantKeyword('KFC')).toBe('肯德基')
    expect(normalizeRestaurantKeyword('Starbucks')).toBe('星巴克')
    expect(normalizeRestaurantKeyword('麦当劳')).toBe('麦当劳')
  })

  it('does not search empty input', () => {
    expect(normalizeRestaurantKeyword('   ')).toBe('')
  })
})
