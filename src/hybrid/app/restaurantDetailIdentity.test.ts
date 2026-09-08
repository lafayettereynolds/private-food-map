import { describe, expect, it } from 'vitest'
import shell from './HybridAppShell.tsx?raw'
import map from '../../components/MyMapBrowsePage.tsx?raw'
import store from '../../../ios/TasteMap/TasteMap/Persistence/LocalTasteMapStore.swift?raw'
import type { TasteMapRestaurantDetailViewModel } from '../../platform/TasteMapPlatform'
import { detailMatchesRoute, restaurantDetailIdentityKey } from './restaurantDetailIdentity'

const detail = { restaurant: { id: 'owned-UUID' } } as TasteMapRestaurantDetailViewModel
describe('Restaurant mutation presentation', () => {
  it('accepts a successful global/provider-key read resolved to an owned Restaurant', () => {
    expect(detailMatchesRoute(detail, 'provider:place', 'provider:place')).toBe(true)
    expect(detailMatchesRoute(detail, 'OWNED-uuid', null)).toBe(true)
  })
  it('never displays a previous request or a missing response on a different route', () => {
    expect(detailMatchesRoute(detail, 'provider:other', 'provider:place')).toBe(false)
    expect(detailMatchesRoute(null, 'provider:place', 'provider:place')).toBe(false)
  })
  it.each(['apple_maps', 'amap', 'other', 'manual'])('never aliases opaque %s IDs solely by letter case', (provider) => {
    const requested = `${provider}:RestaurantAbC`
    const other = `${provider}:Restaurantabc`
    expect(restaurantDetailIdentityKey(requested)).not.toBe(restaurantDetailIdentityKey(other))
    expect(detailMatchesRoute(detail, requested, requested)).toBe(true)
    expect(detailMatchesRoute(detail, other, requested)).toBe(false)
    const cache = new Map([[restaurantDetailIdentityKey(requested), detail]])
    expect(cache.get(restaurantDetailIdentityKey(other))).toBeUndefined()
    expect(cache.get(restaurantDetailIdentityKey(requested))).toBe(detail)
  })
  it('preserves UUID and canonical internal alias normalization after an external save', () => {
    const id = 'ABCDEF12-3456-4789-ABCD-0123456789AB'
    expect(restaurantDetailIdentityKey(id)).toBe(id.toLowerCase())
    expect(restaurantDetailIdentityKey(`provider:${id}`)).toBe(`provider:${id.toLowerCase()}`)
    expect(detailMatchesRoute({ restaurant: { id } } as TasteMapRestaurantDetailViewModel, id.toLowerCase(), null)).toBe(true)
    expect(detailMatchesRoute({ restaurant: { id } } as TasteMapRestaurantDetailViewModel, 'apple_maps:OpaquePlace', 'apple_maps:OpaquePlace')).toBe(true)
  })
  it('uses the same identity policy for every detail cache operation', () => {
    const operations = shell.split('\n').filter((line) => /restaurantDetailCache\.current\.(get|set|delete)\(/.test(line))
    expect(operations.length).toBeGreaterThan(3)
    expect(operations.every((line) => line.includes('restaurantDetailIdentityKey('))).toBe(true)
  })
  it('bounds detail reads and rejects preview fallback on explicit read failure', () => {
    expect(shell).toContain('boundedSnapshotRead(platform.restaurant.get(route.id))')
    expect(shell).toContain('routeError ? null : ownedRestaurantPreview')
  })
  it('leaves a deleted restaurant without backing into its detail or overriding Native completion', () => {
    const deletion = shell.slice(shell.indexOf('onRestaurantDeleted={'), shell.indexOf('onSaved={(restaurantID)'))
    expect(deletion).toContain('deletedRestaurantRoutes.current.add(restaurantDetailIdentityKey(restaurantID))')
    expect(deletion).toContain('restaurantDetailCache.current.clear()')
    expect(deletion).not.toContain('navigateBack()')
    expect(deletion).toContain("platform.kind !== 'native' && routeHash(currentRouteRef.current) === routeHash(route)")
    expect(shell).toContain('deletedRestaurantRoutes.current.has(restaurantDetailIdentityKey(next.id))')
  })
  it('invalidates mounted map snapshots directly on data changes', () => {
    const change = map.slice(map.indexOf("if (event.name === 'data.changed')"), map.indexOf("} else if (event.name === 'location.changed')"))
    expect(change).toContain('snapshotCache.current.clear()')
    expect(change).toContain("requestGate.current.invalidate('data-changed')")
    expect(change).toContain('setItems([])')
    expect(change).toContain("dispatch({ type: 'retry' })")
  })
  it('posts restaurant deletion invalidation only after persistence succeeds', () => {
    const deletion = store.slice(store.indexOf('func delete(_ restaurant:'), store.indexOf('private func enqueue(_ restaurant:'))
    expect(deletion.indexOf('try context.save()')).toBeLessThan(deletion.indexOf('name: .tasteMapLocalDataDidChange'))
    expect(deletion).toContain('userInfo: ["reason": "restaurantDeleted"]')
  })
})
