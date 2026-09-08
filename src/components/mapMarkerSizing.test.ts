import { describe, expect, it } from 'vitest'
import browserMap from './MapView.tsx?raw'
import nativePresentation from '../../ios/TasteMap/TasteMap/Features/Map/RestaurantMapPresentation.swift?raw'
import nativeRenderer from '../../ios/TasteMap/TasteMap/Features/Map/ClusteredRestaurantMapView.swift?raw'
import { MAP_MARKER_FAR_SCALE, mapMarkerZoomDimensions } from './mapMarkerSizing'

const baseline = { diameter: 32, selectedDiameter: 36, unvisitedIncrease: 4 }

describe('far-distance Restaurant marker sizing', () => {
  it('preserves every city and approved regional-overview size through 2.4 degrees', () => {
    for (const span of [0.001, 0.02, 0.8, 1.5, 2.4]) {
      expect(mapMarkerZoomDimensions(span, baseline)).toEqual({ ...baseline, glyphSize: 16 })
    }
  })

  it('shrinks continuously as regional views become national and worldwide, and reverses exactly', () => {
    const spans = [2.4, 2.40001, 4, 8, 15, 30, 50, 80]
    const dimensions = spans.map((span) => mapMarkerZoomDimensions(span, baseline))
    for (let i = 1; i < dimensions.length; i++) {
      expect(dimensions[i].diameter).toBeLessThan(dimensions[i - 1].diameter)
      expect(dimensions[i].selectedDiameter).toBeLessThan(dimensions[i - 1].selectedDiameter)
    }
    expect(dimensions[0].diameter - dimensions[1].diameter).toBeLessThan(0.001)
    expect(dimensions[dimensions.length - 1]).toEqual({ diameter: 14, selectedDiameter: 15, unvisitedIncrease: 1, glyphSize: 6 })
    expect([...spans].reverse().map((span) => mapMarkerZoomDimensions(span, baseline)).reverse()).toEqual(dimensions)
    expect(mapMarkerZoomDimensions(180, baseline)).toEqual(dimensions[dimensions.length - 1])
    // Logarithmic midpoint makes the visible change proportional to zoom steps.
    const midpoint = Math.sqrt(MAP_MARKER_FAR_SCALE.startLatitudeDelta * MAP_MARKER_FAR_SCALE.fullLatitudeDelta)
    expect(mapMarkerZoomDimensions(midpoint, baseline).diameter).toBeCloseTo(23)
  })

  it('keeps pending destinations emphasized without forcing a city-sized circle at world scale', () => {
    for (const span of [0.01, 2.4, 8, 30, 80]) {
      const sizes = mapMarkerZoomDimensions(span, baseline)
      expect(sizes.unvisitedIncrease).toBeGreaterThanOrEqual(1)
      expect(sizes.unvisitedIncrease).toBeLessThanOrEqual(4)
      expect(sizes.selectedDiameter + sizes.unvisitedIncrease).toBeLessThanOrEqual(40)
    }
    for (const invalid of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, -1, 0]) {
      expect(mapMarkerZoomDimensions(invalid, baseline)).toEqual({ ...baseline, glyphSize: 16 })
    }
  })

  it('changes centered contents only, while anchor and grouping geometry remain independent', () => {
    expect(browserMap).toContain('mapMarkerZoomDimensions(latitudeDelta, {')
    expect(browserMap).toContain("record.anchor.style.setProperty('--map-marker-size', `${dimensions.diameter}px`)")
    expect(browserMap).toContain('markerRegionalGroupingDistance(latitudeDelta, markerDiameter)')
    expect(browserMap).not.toContain('markerRegionalGroupingDistance(latitudeDelta, dimensions.diameter)')
    expect(browserMap).toContain("anchor: 'center', offset: new AMap.Pixel(0, 0)")
    expect(nativePresentation).toContain('(cityDiameter * 1.14 + 7).rounded(.up)')
    expect(nativeRenderer).toContain('x: (bounds.width - outerDiameter) / 2, y: (bounds.height - outerDiameter) / 2')
    expect(nativeRenderer).toContain('let fallbackInset = borderWidth + 3 * (1 - densityStyle.farZoomProgress)')
  })
})
