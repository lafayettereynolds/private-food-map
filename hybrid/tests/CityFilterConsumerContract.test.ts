import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')

describe('City source global consumer contract', () => {
  it('applies recommendation cities only on the recommendation scope', () => {
    const page = source('../../src/components/MyMapBrowsePage.tsx')
    expect(page).toContain("options: canonicalRecommendations && scope === 'recommended'")
    expect(page).toContain('? recommendationMapOptions(response.options, canonicalRecommendations)')
  })

  it('accepts owner live-query snapshots before child map requests without emitting a refresh loop', () => {
    const app = source('../../src/App.tsx')
    const adapter = source('../../src/platform/TasteMapBrowserAdapter.ts')
    expect(app).toContain('useLayoutEffect(() => {\n    if (!currentUser || !restaurants || !visits) return\n    browserPlatform.acceptProfileSnapshot')
    expect(app).toContain("activeList === 'recommended'\n      ? recommendations")
    expect(adapter).toContain("profile = { getCurrent: () => this.loadProfile(true) }")
    const acceptance = adapter.slice(adapter.indexOf('  acceptProfileSnapshot('), adapter.indexOf('\n  restaurant ='))
    expect(acceptance).not.toContain('data.changed')
    expect(acceptance).not.toContain('this.dataSource.profile')
    expect(source('../../src/services/restaurantSummaryProjection.ts')).not.toContain("restaurant.city.includes('杭州')")
  })

  it('routes Native rollback controls and sheets through selected-scope options and shared matching', () => {
    const home = source('../../ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift')
    const filters = source('../../ios/TasteMap/TasteMap/Features/Map/PersonalRestaurantFilters.swift')
    const bridge = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridBridgeService.swift')
    expect(home.match(/options: snapshot\.filterOptions\(for: selectedSegment\)/g)).toHaveLength(2)
    expect(filters).toContain('RestaurantCityFilterIdentity.matches(item.restaurant.city, city)')
    expect(bridge).toContain('RestaurantCityFilterIdentity.options(citySource.map(\\.city))')
    expect(bridge).toContain('RestaurantCityFilterIdentity.matches(item.city, city)')
    const runtime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    const invalidation = runtime.slice(runtime.indexOf('func localDataDidChange('))
    expect(invalidation.slice(0, 1300)).toContain('invalidateBridgeReadCaches()')
  })
})
