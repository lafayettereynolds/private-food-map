import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import {
  LatestMapRequestGate,
  MapBrowseSnapshotCache,
  mapBrowseCameraFitKey,
  mapBrowseSnapshotKey,
  type MapBrowsePresentationSnapshot,
} from './mapBrowseSnapshot'

const restaurants = fixture.restaurants as unknown as RestaurantSummary[]
const options = { cities: ['杭州'], companions: [], cuisines: [], recommendationSources: [] }

function snapshot(scope: 'visited' | 'wantToGo' | 'recommended'): MapBrowsePresentationSnapshot {
  return { scope, items: restaurants, images: {}, options, capturedAt: Date.now() }
}

describe('MapBrowse snapshot and request performance contract', () => {
  it('keys each owner/scope/query while excluding scope from the camera-fit identity', () => {
    const base = {
      ownerUserID: 'tm_owner', dataVersion: '5:2:v1', mode: 'map' as const,
      filters: { city: '杭州' }, sort: 'rating' as const, search: '', viewport: {
        zoom: 14, center: { latitude: 30.27, longitude: 120.15 },
        bounds: { north: 30.3, east: 120.2, south: 30.2, west: 120.1 },
      }, currentLocation: null,
    }
    const visited = mapBrowseSnapshotKey({ ...base, scope: 'visited' })
    const wanted = mapBrowseSnapshotKey({ ...base, scope: 'wantToGo' })
    expect(visited).not.toBe(wanted)
    expect(mapBrowseCameraFitKey(base.filters, base.search)).toBe(mapBrowseCameraFitKey(base.filters, base.search))
    expect(mapBrowseCameraFitKey(base.filters, base.search)).not.toContain('visited')
  })

  it('reuses unchanged snapshots without unbounded memory growth', () => {
    const cache = new MapBrowseSnapshotCache(3)
    cache.set('visited', snapshot('visited'))
    cache.set('wanted', snapshot('wantToGo'))
    cache.set('recommended', snapshot('recommended'))
    expect(cache.get('visited')?.scope).toBe('visited')
    cache.set('next-query', snapshot('visited'))
    expect(cache.size).toBe(3)
    expect(cache.get('wanted')).toBeUndefined()
  })

  it('rejects stale and mismatched Native responses after a rapid scope switch', () => {
    const gate = new LatestMapRequestGate()
    gate.activate('visited-request')
    gate.activate('recommended-request')
    expect(gate.accepts('visited-request')).toBe(false)
    expect(gate.accepts('recommended-request', 'visited-request')).toBe(false)
    expect(gate.accepts('recommended-request')).toBe(true)
    gate.invalidate()
    expect(gate.accepts('recommended-request')).toBe(false)
  })
})
