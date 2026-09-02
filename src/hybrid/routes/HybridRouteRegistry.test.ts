import { describe, expect, it } from 'vitest'
import { HYBRID_ROUTE_REGISTRY, parseTasteMapDeepLink, routeFromLocation, routeFromStartupLocation, routeHash } from './HybridRouteRegistry'

describe('HybridRouteRegistry', () => {
  it('marks Batch 1 surfaces and the Batch 2 Visit editor as HYBRID_INTEGRATED', () => {
    const migrated = ['map', 'profile', 'restaurant', 'discovery', 'activity', 'add', 'lists', 'publicList', 'roulette', 'analytics', 'premium', 'settings'] as const
    migrated.forEach((surface) => expect(HYBRID_ROUTE_REGISTRY[surface]).toBe('HYBRID_INTEGRATED'))
    expect(HYBRID_ROUTE_REGISTRY.visit).toBe('HYBRID_INTEGRATED')
    expect(HYBRID_ROUTE_REGISTRY.visitEdit).toBe('HYBRID_INTEGRATED')
  })

  it('round-trips ready routes and keeps unknown paths at Profile', () => {
    const detail = { surface: 'restaurant' as const, id: 'restaurant id' }
    expect(routeFromLocation({ hash: routeHash(detail) } as Location)).toEqual(detail)
    expect(routeFromLocation({ hash: '#/unknown' } as Location)).toEqual({ surface: 'profile' })
  })

  it('keeps an explicit Browser or Capacitor route authoritative over the Debug fallback', () => {
    expect(routeFromStartupLocation({ hash: '#/discovery' } as Location, '#/map')).toEqual({ surface: 'discovery' })
    expect(routeFromStartupLocation({ hash: '#/add' } as Location, '#/map')).toEqual({ surface: 'add' })
    expect(routeFromStartupLocation({ hash: '' } as Location, '#/map')).toEqual({ surface: 'map' })
  })

  it('allowlists app and universal deep-link shapes', () => {
    expect(parseTasteMapDeepLink('tastemap://restaurant/r1')).toEqual({ surface: 'restaurant', id: 'r1' })
    expect(parseTasteMapDeepLink('https://example.test/profile/tm_1')).toEqual({ surface: 'profile', id: 'tm_1' })
    expect(parseTasteMapDeepLink('https://example.test/admin/token')).toBeNull()
  })
})
