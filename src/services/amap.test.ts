import { describe, expect, it } from 'vitest'
import fixture from '../../contracts/fixtures/nearby-location.v1.json'
import { distanceMeters } from './geoDistance'
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

describe('nearby fixed-coordinate contract', () => {
  it('uses the shared GPS origin and sorts the 40m restaurant first', () => {
    const origin = { latitude: fixture.latitude, longitude: fixture.longitude }
    const sorted = fixture.candidates
      .map((candidate) => ({ ...candidate, distance: distanceMeters(origin, candidate) }))
      .sort((left, right) => left.distance - right.distance)

    expect(sorted.map((candidate) => candidate.name)).toEqual([
      'fixture-40m',
      'fixture-420m',
      'fixture-2km',
    ])
    expect(sorted[0].distance).toBeGreaterThan(39)
    expect(sorted[0].distance).toBeLessThan(41)
    expect(sorted[1].distance).toBeGreaterThan(419)
  })
})
