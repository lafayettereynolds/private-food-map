import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')

describe('Native and shared Map location delivery contract', () => {
  it('funnels every successful sensor result through delivery-time validation', () => {
    const manager = source('../../ios/TasteMap/TasteMap/Services/LocationPermissionManager.swift')
    const finish = manager.slice(manager.indexOf('private func finish(with result:'))
    expect(finish).toContain('RestaurantLocationFixPolicy.isUsableForDelivery(')
    expect(finish).toContain('continuation.resume(with: deliveredResult)')
    expect(finish).not.toContain('continuation.resume(with: result)')
    const runtime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    const current = runtime.slice(runtime.indexOf('private func currentLocation()'), runtime.indexOf('private var locationAuthorizationStatus'))
    expect(current.indexOf('RestaurantLocationFixPolicy.isUsable(')).toBeLessThan(current.indexOf('emit(.locationChanged'))
    expect(current).toContain('throw RestaurantLocationError.staleOrInaccurate')
  })

  it('refreshes real GPS on resume without changing camera-fit ownership', () => {
    const page = source('../../src/components/MyMapBrowsePage.tsx')
    const start = page.indexOf('const refreshMapLocation =')
    const refresh = page.slice(start, page.indexOf('}, [platform])', start))
    expect(refresh).toContain('platform.location.current()')
    expect(refresh).toContain('locationDeliveryGate.current.accept(location, sequence)')
    expect(refresh).not.toContain("dispatch({ type: 'filters'")
    expect(refresh).not.toContain("dispatch({ type: 'viewport'")
    expect(page).toContain('locationContext.current.foreground = true\n          refreshMapLocation()')
    expect(page).toContain('if (disposed) return')
  })
})
