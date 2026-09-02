import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = (name: string) => readFileSync(new URL(name, import.meta.url), 'utf8')

describe('Phase 2B Hybrid Map product contract', () => {
  it('keeps one centered title switch and the exact three canonical scopes', () => {
    const page = source('../../src/components/MyMapBrowsePage.tsx')
    expect(page).toContain('HYBRID_MAP_PRIMARY_SCOPES.map')
    expect(page).toContain("切换到我的列表")
    expect(page).toContain("切换到我的地图")
    expect(page).not.toContain('适合你')
    expect(page).not.toMatch(/segmented/i)
  })

  it('renders independent markers at their real coordinates without cluster or default separation', () => {
    const map = source('../../src/components/MapView.tsx')
    const mapService = source('../../src/services/amap.ts')
    expect(map).toContain('position: [restaurant.longitude, restaurant.latitude]')
    expect(`${map}\n${mapService}`).not.toMatch(/MarkerCluster|createClusterData|spiderfy|collision dispersion/i)
    expect(map).not.toMatch(/coordinateOffset|adjustedCoordinate|spreadCoordinate/i)
  })

  it('keeps Map mounted while Hybrid Restaurant Detail owns the visible route', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    expect(shell).toContain('mapWasActivated ? <MyMapBrowsePage')
    expect(shell).toContain("active={route.surface === 'map'}")
    expect(shell).toContain("navigate({ surface: 'restaurant', id: restaurantID })")
  })
})
