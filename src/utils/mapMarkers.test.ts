import { describe, expect, it } from 'vitest'
import { isUnvisitedMapMarker } from './mapMarkers'

describe('pending map marker emphasis', () => {
  it('enlarges wanted and recommended destinations using the same semantic state', () => {
    expect(isUnvisitedMapMarker('wantToGo')).toBe(true)
    expect(isUnvisitedMapMarker('visited', true)).toBe(true)
    expect(isUnvisitedMapMarker('wantToGo', true)).toBe(true)
  })

  it('leaves visited markers at their existing size', () => {
    expect(isUnvisitedMapMarker('visited')).toBe(false)
  })
})
