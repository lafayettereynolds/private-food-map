import { describe, expect, it } from 'vitest'
import runtime from '../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift?raw'
import service from '../../ios/TasteMap/TasteMap/Services/RestaurantSearchService.swift?raw'
import worldwideService from '../../ios/TasteMap/TasteMap/Services/WorldwideRestaurantSearchService.swift?raw'
import page from '../hybrid/app/HybridAddRestaurantPage.tsx?raw'
import privateScheme from '../../ios/TasteMap/TasteMap.xcodeproj/xcshareddata/xcschemes/Taste Map Private.xcscheme?raw'
import defaultScheme from '../../ios/TasteMap/TasteMap.xcodeproj/xcshareddata/xcschemes/TasteMap.xcscheme?raw'
import qaScheme from '../../ios/TasteMap/TasteMap.xcodeproj/xcshareddata/xcschemes/TasteMap QA.xcscheme?raw'

describe('Restaurant acquisition search/location boundary', () => {
  it('only treats relevant worldwide results as a hit before suppressing an independent provider fallback', () => {
    const worldwide = worldwideService.slice(worldwideService.indexOf('struct WorldwideRestaurantSearchService'))
    expect(worldwide).not.toContain('if !values.isEmpty { return values }')
    expect(worldwide).not.toContain('if !scoped.isEmpty { return scoped }')
    expect(worldwide.match(/if !matches.isEmpty \{ return matches \}/g)).toHaveLength(2)
    expect(worldwide).toContain('RestaurantSearchRelevancePolicy.rankedMatches')
    expect(worldwide).not.toContain('Da Andrea')
  })

  it('preserves actual MapKit neighbourhood evidence before falling back to city context on iOS 26', () => {
    const district = service.slice(service.indexOf('private func mapItemDistrict'), service.indexOf('private func legacyAddress'))
    expect(district.indexOf('mapItem.placemark.subLocality')).toBeLessThan(district.indexOf('if #available(iOS 26.0, *)'))
    expect(district.indexOf('mapItem.placemark.subAdministrativeArea')).toBeLessThan(district.indexOf('if #available(iOS 26.0, *)'))
  })
  it('allows Xcode location simulation only in the isolated QA launch scheme', () => {
    for (const scheme of [privateScheme, defaultScheme]) {
      expect(scheme).toContain('allowLocationSimulation = "NO"')
      expect(scheme).not.toContain('LocationScenarioReference')
      expect(scheme).not.toContain('TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST')
    }
    expect(qaScheme).toContain('allowLocationSimulation = "YES"')
    expect(qaScheme).toContain('buildConfiguration = "DebugQA"')
  })

  it('uses fresh accepted native GPS only in the matching city and retains it in an owner-scoped continuation', () => {
    expect(runtime).toContain('scope: RestaurantSearchScope(city: city, center: center)')
    expect(runtime).toContain('normalizedCity($0) == normalizedCity(city)')
    expect(runtime).toContain('$0.value.owner == owner')
    expect(runtime).toContain('page.query == query, page.city == city')
    expect(runtime).toContain('acquisitionSearchPages.removeValue(forKey: cursor)')
    expect(runtime).toContain('acquisitionSearchGeneration == generation')
    expect(runtime).toContain('currentOwner == owner')
    expect(runtime).toContain('candidates: Array(page.candidates.dropFirst(20)), location: page.location')
    expect(runtime).toContain('expiresAt: Date().addingTimeInterval(300)')
    const searchFunction = runtime.slice(runtime.indexOf('private func searchRestaurants'), runtime.indexOf('private func searchPage'))
    expect(searchFunction).toContain('await RestaurantSearchLocationPolicy.location')
    expect(searchFunction).toContain('self.freshLocationFix(method: .acquisitionSearch).location')
  })

  it('pairs deterministic acquisition GPS only with the explicit synthetic provider and rejects reduced accuracy', () => {
    const locationFunction = runtime.slice(runtime.indexOf('private func obtainFreshLocationFix'), runtime.indexOf('private func pickPhotos'))
    expect(locationFunction).toContain('usesRestaurantAcquisitionFixture')
    expect(locationFunction).not.toContain('usesVisualQA')
    expect(locationFunction).toContain('accuracyAuthorization == .fullAccuracy')
    expect(locationFunction).toContain('location_precise_required')
  })

  it('supplements already populated results and resolves genuine provider completions', () => {
    expect(service.indexOf('let variants = RestaurantSearchRelevancePolicy.queryVariants(query)')).toBeLessThan(service.indexOf('if values.isEmpty'))
    expect(service).toContain('MKLocalSearchCompleter()')
    expect(service).toContain('completions.prefix(3)')
    expect(service).toContain('radiusMeters: min(500, radiusMeters)')
    expect(service).toMatch(/async let localRestaurants = nearbyCandidates\([\s\S]*?requiresRegion: true/)
    expect(service).toContain('outcomes += await [localPoints, localRestaurants]')
  })

  it('invalidates in-flight search and continuation on edits and exposes a real load-more control', () => {
    expect(page).toContain('requestID !== searchRequestRef.current')
    expect(page).toContain('onQueryChange={(value) => { invalidateSearch(); setQuery(value) }}')
    expect(page).toMatch(/onCityChange=[\s\S]*?invalidateSearch\(\)/)
    expect(page).toContain('searchResult?.nextCursor')
    expect(page).toContain('继续加载餐厅')
    expect(page).toContain("?.code === 'location_precise_required'")
  })
})
