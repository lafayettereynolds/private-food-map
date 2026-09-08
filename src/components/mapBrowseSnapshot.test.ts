import { afterEach, describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import {
  LatestMapRequestGate,
  LatestMapViewportCommitScheduler,
  MapBrowseSnapshotCache,
  mapBrowseDataVersion,
  mapBrowseSnapshotKey,
  type MapBrowsePresentationSnapshot,
} from './mapBrowseSnapshot'

const restaurants = fixture.restaurants as unknown as RestaurantSummary[]
const options = { cities: ['杭州'], companions: [], cuisines: [], recommendationSources: [] }

function snapshot(scope: 'visited' | 'wantToGo' | 'recommended'): MapBrowsePresentationSnapshot {
  return {
    scope,
    items: restaurants,
    images: {},
    options,
    scopeCounts: { visited: 3, wantToGo: 2, recommended: 1 },
    capturedAt: Date.now(),
  }
}

describe('MapBrowse snapshot and request performance contract', () => {
  it('invalidates same-timestamp accepted city/status/identity/delete changes without depending on row order', () => {
    const initial = restaurants.map((item) => ({ ...item }))
    const version = mapBrowseDataVersion(initial)
    expect(mapBrowseDataVersion([...initial].reverse())).toBe(version)
    for (const change of [{ city: '温州' }, { status: 'wantToGo' as const }, { id: 'replacement' }, { deletedAt: '2026-09-06' }]) {
      expect(mapBrowseDataVersion(initial.map((item, index) => index === 0 ? { ...item, ...change } : item))).not.toBe(version)
    }
  })

  afterEach(() => vi.useRealTimers())

  it('invalidates edited avatars even when another restaurant owns the latest timestamp', () => {
    const initial = restaurants.map((item, index) => ({ ...item, updatedAt: index === 0 ? '2026-09-01' : '2026-10-01' }))
    const version = mapBrowseDataVersion(initial)
    for (const change of [
      { markerType: 'emoji' as const, markerEmoji: '🐸' },
      { markerType: 'image' as const, markerPhotoId: 'new-owner-photo' },
      { updatedAt: '2026-09-06' },
    ]) {
      expect(mapBrowseDataVersion(initial.map((item, index) => index === 0 ? { ...item, ...change } : item))).not.toBe(version)
    }
  })

  it('keys each owner/scope/query independently', () => {
    const base = {
      ownerUserID: 'tm_owner', dataVersion: '5:2:v1', mode: 'map' as const,
      filters: { city: '杭州' }, sort: 'rating' as const, search: '', currentLocation: null,
    }
    const visited = mapBrowseSnapshotKey({ ...base, scope: 'visited' })
    const wanted = mapBrowseSnapshotKey({ ...base, scope: 'wantToGo' })
    expect(visited).not.toBe(wanted)
  })

  it('does not key Restaurant data by viewport, so a pan cannot replace marker identities', () => {
    const key = mapBrowseSnapshotKey({
      ownerUserID: 'tm_owner', dataVersion: '5:2:v1', mode: 'map', scope: 'visited',
      filters: {}, sort: 'recent', search: '', currentLocation: null,
    })
    expect(key).not.toContain('bounds')
    expect(key).not.toContain('viewport')
  })

  it('keeps full-sheet conditions in cache identity rather than replaying a different scope query', () => {
    const input = { ownerUserID: 'owner', dataVersion: 'v1', mode: 'map' as const,
      scope: 'visited' as const, filters: {}, sort: 'recent' as const, search: '', currentLocation: null }
    const base = mapBrowseSnapshotKey(input)
    for (const filters of [{ scoreBands: [3] as const }, { diningMode: 'solo' }, { queueDuration: 'unrecorded' },
      { diningOccasions: ['breakfast'] }, { visitPeriod: 'year' }, { distanceKilometers: 3 },
      { priceRange: 'under100' }, { recommendationSourceType: 'friend' }]) {
      expect(mapBrowseSnapshotKey({ ...input, filters: filters as Parameters<typeof mapBrowseSnapshotKey>[0]['filters'] })).not.toBe(base)
    }
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

  it('coalesces rapid viewport changes into one settled data refresh', () => {
    vi.useFakeTimers()
    const scheduler = new LatestMapViewportCommitScheduler(160)
    const commits: number[] = []
    const viewport = (zoom: number) => ({
      zoom,
      center: { latitude: 30.27, longitude: 120.15 },
      bounds: { north: 30.3, east: 120.2, south: 30.2, west: 120.1 },
    })

    scheduler.schedule(viewport(13), (value) => commits.push(value.zoom))
    scheduler.schedule(viewport(14), (value) => commits.push(value.zoom))
    scheduler.schedule(viewport(15), (value) => commits.push(value.zoom))
    vi.advanceTimersByTime(159)
    expect(commits).toEqual([])
    vi.advanceTimersByTime(1)
    expect(commits).toEqual([15])
  })
})
