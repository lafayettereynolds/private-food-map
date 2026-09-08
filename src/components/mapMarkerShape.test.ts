import { describe, expect, it } from 'vitest'
import { MAP_MARKER_CHEST, MAP_MARKER_CHEST_MASK, TREASURE_CHEST_CANDIDATE_ENABLED, mapMarkerShape } from './mapMarkerShape'
import browserMap from './MapView.tsx?raw'

describe('Paused Restaurant marker treasure chest candidate', () => {
  it('keeps formal wanted/recommended and visited silhouettes circular by default', () => {
    expect(TREASURE_CHEST_CANDIDATE_ENABLED).toBe(false)
    expect(mapMarkerShape('wantToGo')).toBe('circle')
    expect(mapMarkerShape('visited', true)).toBe('circle')
    expect(mapMarkerShape('visited')).toBe('circle')
  })

  it('retains an explicit isolated candidate without changing visited Restaurants', () => {
    expect(mapMarkerShape('wantToGo', false, true)).toBe('treasureChest')
    expect(mapMarkerShape('visited', true, true)).toBe('treasureChest')
    expect(mapMarkerShape('visited', false, true)).toBe('circle')
  })

  it('retains the exact supplied PNG with one bounded photograph window and original clasp', () => {
    expect(MAP_MARKER_CHEST.source).toBe('/map-markers/treasure-chest.png')
    expect(MAP_MARKER_CHEST.size).toBe(62)
    expect(MAP_MARKER_CHEST.photoWindow).toEqual({ x: 8, y: 32, width: 46, height: 24 })
    expect(MAP_MARKER_CHEST.clasp).toEqual({ x: 25, y: 29, width: 12, height: 14 })
    const mask = decodeURIComponent(MAP_MARKER_CHEST_MASK)
    expect(mask).toContain('<rect x="8" y="32" width="46" height="24" fill="black"/>')
    expect(mask).toContain('<rect x="25" y="29" width="12" height="14" fill="white"/>')
    expect(mask).not.toContain('<image')
  })

  it('keeps the shell outside asynchronously replaced image content on every Browser renderer', () => {
    const source = browserMap
    expect(source).toContain('marker.append(createTreasureChestDecoration())')
    expect(source).toContain("if (marker.dataset.markerShape === 'treasureChest')")
    expect(source).toContain('layer.append(createTreasureChestDecoration())')
    expect(source.match(/<TreasureChestDecoration \/>/g)).toHaveLength(2)
    expect(source).toContain("image.addEventListener('load', () => visual.replaceChildren(image)")
    expect(source).toContain("anchor: 'center', offset: new AMap.Pixel(0, 0)")
    expect(source).not.toContain('MAP_MARKER_CHEST_PATHS')
    expect(source).toContain('src={MAP_MARKER_CHEST.source}')
    expect(source).not.toContain('if (unvisited) marker.append(createTreasureChestDecoration())')
    expect(source).not.toContain('{unvisited ? <TreasureChestDecoration />')
  })
})
