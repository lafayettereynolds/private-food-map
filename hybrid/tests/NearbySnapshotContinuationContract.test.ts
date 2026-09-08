import { describe, expect, it } from 'vitest'
import native from '../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift?raw'
import rollback from '../../ios/TasteMap/TasteMap/Features/Restaurant/RestaurantAcquisitionViewModel.swift?raw'
import rollbackView from '../../ios/TasteMap/TasteMap/Features/Restaurant/AddRestaurantView.swift?raw'
import shared from '../../src/components/TasteMapRestaurantAcquisitionShared.tsx?raw'
import hybrid from '../../src/hybrid/app/HybridAddRestaurantPage.tsx?raw'
import browser from '../../src/components/AddRestaurantModal.tsx?raw'
import app from '../../src/App.tsx?raw'

describe('Nearby snapshot continuation contract', () => {
  it('sends the whole Native accepted snapshot only after owner/generation checks and radius filtering', () => {
    const nearby = native.slice(native.indexOf('private func nearbyRestaurants'), native.indexOf('private func sharedRestaurantCandidates'))
    expect(nearby).toContain('candidates: ordered')
    expect(nearby).not.toContain('ordered.prefix(12)')
    expect(nearby.match(/acquisitionNearbyGeneration == generation/g)).toHaveLength(2)
    expect(nearby.match(/currentOwner == owner/g)).toHaveLength(2)
    expect(nearby).toContain('freshLocationFix(method: .acquisitionNearby)')
    expect(nearby).toContain('<= 3_000')
  })
  it('shares presentation-only continuation across both React entrances without GPS/search callbacks', () => {
    expect(hybrid).toContain('nearbySnapshot={nearbyResult}')
    expect(browser).toContain('nearbySnapshot={nearbyResults}')
    expect(browser).not.toContain('nearby.slice(0, 8)')
    const results = shared.slice(shared.indexOf('export function TasteMapRestaurantAcquisitionResults'))
    expect(results).toContain('继续加载附近餐厅')
    expect(results).toContain('expanded.snapshot === nearbySnapshot')
    expect(results).not.toMatch(/platform\.|mapService\.|fetch\(|detectCurrent|\.nearby\(/)
    expect(hybrid).toContain("event.name === 'auth.changed') invalidateNearby()")
    expect(hybrid).toContain("event.name === 'location.changed'")
    expect(app).toContain("<AddRestaurantModal key={currentUser?.id ?? 'signed-out'}")
  })
  it('retains every Native rollback result and expands without repeating the provider', () => {
    expect(rollback).not.toContain('.prefix(8)')
    expect(rollbackView).not.toContain('nearbyResults.prefix(8)')
    expect(rollbackView).toContain('ForEach(viewModel.visibleNearbyResults)')
    const more = rollback.slice(rollback.indexOf('func loadMoreNearby'), rollback.indexOf('func invalidateNearby'))
    expect(more).toContain('nearbyVisibleCount + 12')
    expect(more).not.toMatch(/searchService|locationProvider|loadNearby\(/)
    expect(rollback).toContain('nearbyGeneration == generation, !Task.isCancelled')
    expect(rollbackView).toContain('.onChange(of: accountScope)')
  })
})
