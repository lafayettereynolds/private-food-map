import { describe, expect, it } from 'vitest'
import { wantedMarkerScale } from './mapMarkers'

describe('wantedMarkerScale', () => {
  it('makes nearby restaurants larger and distant restaurants smaller', () => {
    expect(wantedMarkerScale(0)).toBeCloseTo(1.28)
    expect(wantedMarkerScale(2)).toBeGreaterThan(wantedMarkerScale(10))
    expect(wantedMarkerScale(10)).toBeGreaterThan(wantedMarkerScale(30))
    expect(wantedMarkerScale(30)).toBeCloseTo(0.78)
    expect(wantedMarkerScale(100)).toBeCloseTo(0.78)
  })

  it('falls back to the normal size for invalid distances', () => {
    expect(wantedMarkerScale(Number.NaN)).toBe(1)
    expect(wantedMarkerScale(-1)).toBe(1)
  })
})
