import { describe, expect, it } from 'vitest'
import { markerLayerPriority } from './mapMarkerPriority'

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
})
