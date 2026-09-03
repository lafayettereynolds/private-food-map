import { describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import { restaurantMarkerReconciliationPlan, restaurantMarkerSignature } from './MapView'
import { markerLayerPriority } from './mapMarkerPriority'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))

const marker = (id: string, scoreOutOfTen: number | null, visitCount: number) => ({ id, scoreOutOfTen, visitCount })

describe('hybrid Restaurant marker ordering', () => {
  it('keeps selected above rating, rating above visit count, and ID as a deterministic tie break', () => {
    const low = marker('restaurant-low', 7.8, 9_999)
    const high = marker('restaurant-high', 7.9, 0)
    expect(markerLayerPriority(high)).toBeGreaterThan(markerLayerPriority(low))
    expect(markerLayerPriority(low, true)).toBeGreaterThan(markerLayerPriority(high))

    const fewerVisits = marker('restaurant-z', 8.8, 4)
    const moreVisits = marker('restaurant-a', 8.8, 5)
    expect(markerLayerPriority(moreVisits)).toBeGreaterThan(markerLayerPriority(fewerVisits))

    expect(markerLayerPriority(marker('restaurant-a', 8.8, 5))).not.toBe(markerLayerPriority(marker('restaurant-b', 8.8, 5)))
    expect(markerLayerPriority(marker('restaurant-a', 8.8, 5))).toBe(markerLayerPriority(marker('restaurant-a', 8.8, 5)))
  })

  it('places a rated Restaurant above nil rating without moving the user marker into this comparator', () => {
    expect(markerLayerPriority(marker('rated', 0, 0))).toBeGreaterThan(markerLayerPriority(marker('nil', null, 9_999)))
  })

  it('diffs stable Restaurant IDs and reuses unchanged marker/image identities', () => {
    const first = fixture.restaurants[0] as unknown as RestaurantSummary
    const second = fixture.restaurants[1] as unknown as RestaurantSummary
    const removed = fixture.restaurants[2] as unknown as RestaurantSummary
    const changed = { ...second, visitCount: second.visitCount + 1 }
    const records = new Map([
      [first.id, { signature: restaurantMarkerSignature(first, null) }],
      [second.id, { signature: restaurantMarkerSignature(second, null) }],
      [removed.id, { signature: restaurantMarkerSignature(removed, null) }],
    ])
    const plan = restaurantMarkerReconciliationPlan(new Set(records.keys()), records, [first, changed], null)
    expect(plan.reused.map((value) => value.id)).toEqual([first.id])
    expect(plan.changed.map((value) => value.id)).toEqual([second.id])
    expect(plan.removed).toEqual([removed.id])
    expect(plan.added).toEqual([])
  })
})
