import { describe, expect, it } from 'vitest'
import { HYBRID_ROUTE_REGISTRY, parseTasteMapDeepLink, routeFromLocation, routeFromStartupLocation, routeHash } from './HybridRouteRegistry'

describe('HybridRouteRegistry', () => {
  it('marks Batch 1 surfaces and the Batch 2 Visit editor as HYBRID_PRIMARY', () => {
    const migrated = ['map', 'profile', 'restaurant', 'discovery', 'activity', 'add', 'lists', 'publicList', 'roulette', 'analytics', 'premium', 'settings'] as const
    migrated.forEach((surface) => expect(HYBRID_ROUTE_REGISTRY[surface]).toBe('HYBRID_PRIMARY'))
    expect(HYBRID_ROUTE_REGISTRY.visit).toBe('HYBRID_PRIMARY')
    expect(HYBRID_ROUTE_REGISTRY.visitEdit).toBe('HYBRID_PRIMARY')
  })

  it('round-trips ready routes and keeps empty or invalid paths at Map', () => {
    const detail = { surface: 'restaurant' as const, id: 'restaurant id' }
    expect(routeFromLocation({ hash: routeHash(detail) } as Location)).toEqual(detail)
    for (const hash of ['', '#/', '#/unknown', '#/restaurant']) {
      expect(routeFromLocation({ hash } as Location)).toEqual({ surface: 'map' })
    }
    expect(routeFromStartupLocation({ hash: '' })).toEqual({ surface: 'map' })
  })

  it('keeps an explicit Browser or Capacitor route authoritative over the Debug fallback', () => {
    expect(routeFromStartupLocation({ hash: '#/discovery' } as Location, '#/map')).toEqual({ surface: 'discovery' })
    expect(routeFromStartupLocation({ hash: '#/add' } as Location, '#/map')).toEqual({ surface: 'add' })
    expect(routeFromStartupLocation({ hash: '' } as Location, '#/map')).toEqual({ surface: 'map' })
    expect(routeFromStartupLocation({ hash: '' }, '#/profile')).toEqual({ surface: 'profile' })
    expect(routeFromStartupLocation({ hash: '#/profile' }, '#/map')).toEqual({ surface: 'profile' })
    expect(routeFromStartupLocation({ hash: '#/restaurant/r1' }, '#/map')).toEqual({ surface: 'restaurant', id: 'r1' })
  })

  it('allowlists app and universal deep-link shapes', () => {
    expect(parseTasteMapDeepLink('tastemap://restaurant/r1')).toEqual({ surface: 'restaurant', id: 'r1' })
    expect(parseTasteMapDeepLink('https://example.test/profile/tm_1')).toEqual({ surface: 'profile', id: 'tm_1' })
    expect(parseTasteMapDeepLink('https://example.test/admin/token')).toBeNull()
  })
})
