import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { Restaurant, Visit } from '../types/domain'
import { buildRestaurantSummaries } from './restaurantSummaryProjection'
import { selectUniqueProfileRestaurants } from './profileTopStats'

describe('live Visit membership', () => {
  const restaurant = { ...fixture.restaurants[0], userId: 'owner', status: 'visited', deletedAt: null } as unknown as Restaurant
  const visit = { ...fixture.restaurants[0].visits[0], userId: 'owner', restaurantId: restaurant.id, deletedAt: null } as unknown as Visit
  it('keeps one Restaurant through repeated Visits and removes membership after the last deletion', () => {
    const visits = [visit, { ...visit, id: 'second' }]
    const before = buildRestaurantSummaries([restaurant], visits)
    expect(before[0].visitCount).toBe(2)
    expect(selectUniqueProfileRestaurants(before, 'visited')).toHaveLength(1)
    const after = buildRestaurantSummaries([restaurant], visits.map((item) => ({ ...item, deletedAt: '2026-09-07T00:00:00Z' })))
    expect(after).toHaveLength(1) // Detail/List material survives; this is not Restaurant deletion.
    expect(after[0].visitCount).toBe(0)
    expect(selectUniqueProfileRestaurants(after, 'visited')).toHaveLength(0)
    expect(selectUniqueProfileRestaurants(after, 'wantToGo')).toHaveLength(0)
  })
  it('rejects deleted Restaurants and another owner’s Visits', () => {
    expect(buildRestaurantSummaries([{ ...restaurant, deletedAt: '2026-09-07' }], [visit])).toEqual([])
    expect(buildRestaurantSummaries([restaurant], [{ ...visit, userId: 'other' }])[0].visitCount).toBe(0)
  })
})
