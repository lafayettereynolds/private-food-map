import { describe, expect, it } from 'vitest'
import { MapMarkerViewportScale, mapMarkerZoomDimensions } from './mapMarkerSizing'
import { markerRegionalGroupingDistance, markerRegionalGroups } from './mapMarkerPriority'

describe('map marker scale across pan and metadata updates', () => {
  const baseline = { diameter: 32, selectedDiameter: 36, unvisitedIncrease: 4 }

  it('keeps grouping and size when a north/south pan changes Mercator latitude bounds at the same zoom', () => {
    const scale = new MapMarkerViewportScale()
    const restaurants = [
      { id: 'front', scoreOutOfTen: 9, visitCount: 1 },
      { id: 'other', scoreOutOfTen: 8, visitCount: 1 },
    ]
    const points = new Map([['front', { x: 0, y: 0 }], ['other', { x: 30, y: 0 }]])
    const initial = scale.resolve(7, 390, 780, 2.4)
    const firstGroups = markerRegionalGroups(restaurants, points, markerRegionalGroupingDistance(initial, baseline.diameter))
    expect(firstGroups).toHaveLength(1)
    // Old per-render latitude bounds would split this group after a metadata
    // update at the panned location, despite unchanged projected separation.
    expect(markerRegionalGroups(restaurants, points, markerRegionalGroupingDistance(1.2, baseline.diameter))).toHaveLength(2)
    for (const latitudeDelta of [2.078, 1.2, 2.078, 2.4]) {
      const resolved = scale.resolve(7, 390, 780, latitudeDelta)
      expect(resolved).toBe(initial)
      expect(markerRegionalGroups(restaurants, points, markerRegionalGroupingDistance(resolved, baseline.diameter))).toEqual(firstGroups)
    }
    const far = scale.resolve(4, 390, 780, 30)
    expect(mapMarkerZoomDimensions(scale.resolve(4, 390, 780, 15), baseline)).toEqual(mapMarkerZoomDimensions(far, baseline))
  })

  it('applies actual zoom and viewport changes and restores approved sizes after zooming back', () => {
    const scale = new MapMarkerViewportScale()
    expect(scale.resolve(7, 390, 780, 2.4)).toBe(2.4)
    expect(scale.resolve(6.5, 390, 780, 3.4)).toBe(3.4)
    expect(scale.resolve(3, 390, 780, 80)).toBe(80)
    expect(scale.resolve(7, 390, 780, 2.4)).toBe(2.4)
    expect(mapMarkerZoomDimensions(scale.resolve(7, 390, 780, 2.1), baseline).diameter).toBe(32)
    expect(scale.resolve(7, 780, 390, 1.2)).toBe(1.2)
  })
})
