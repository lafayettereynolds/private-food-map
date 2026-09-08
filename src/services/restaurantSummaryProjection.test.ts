import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { Restaurant } from '../types/domain'
import { buildRestaurantSummaries } from './restaurantSummaryProjection'

describe('owner Restaurant summary membership', () => {
  it('preserves visited restaurants without Visits in every city and build mode', () => {
    const restaurants = ['杭州', '上海市', '东京', 'New York', '广州'].map((city, index) => ({
      ...fixture.restaurants[0], id: `city-${index}`, city, status: 'visited',
    })) as unknown as Restaurant[]
    for (const development of [true, false]) {
      const result = buildRestaurantSummaries(restaurants, [], { development })
      expect(result.map((value) => value.id)).toEqual(restaurants.map((value) => value.id))
      expect(result.map((value) => value.city)).toEqual(restaurants.map((value) => value.city))
      expect(result.every((value) => value.status === 'visited' && value.visitCount === 0)).toBe(true)
    }
  })

  it('does not infer want-to-go membership or fixture status from a city name', () => {
    const restaurants = ['上海', '杭州', 'QA City'].map((city, index) => ({
      ...fixture.restaurants[0], id: `wanted-${index}`, city, status: 'wantToGo',
    })) as unknown as Restaurant[]
    const result = buildRestaurantSummaries(restaurants, [], { development: true })
    expect(result.map((value) => value.city)).toEqual(['上海', '杭州', 'QA City'])
    expect(result.every((value) => value.status === 'wantToGo')).toBe(true)
  })
})
