import { describe, expect, it } from 'vitest'
import { HYBRID_ROUTE_REGISTRY, parseTasteMapDeepLink, routeFromLocation, routeHash } from './HybridRouteRegistry'

describe('HybridRouteRegistry', () => {
  it('marks My Map, Profile and Restaurant Detail as HYBRID_INTEGRATED', () => {
    expect(HYBRID_ROUTE_REGISTRY.map).toBe('HYBRID_INTEGRATED')
    expect(HYBRID_ROUTE_REGISTRY.profile).toBe('HYBRID_INTEGRATED')
    expect(HYBRID_ROUTE_REGISTRY.restaurant).toBe('HYBRID_INTEGRATED')
    expect(Object.entries(HYBRID_ROUTE_REGISTRY).filter(([, status]) => status === 'HYBRID_INTEGRATED')).toHaveLength(3)
  })

  it('round-trips ready routes and keeps unknown paths at Profile', () => {
    const detail = { surface: 'restaurant' as const, id: 'restaurant id' }
    expect(routeFromLocation({ hash: routeHash(detail) } as Location)).toEqual(detail)
    expect(routeFromLocation({ hash: '#/unknown' } as Location)).toEqual({ surface: 'profile' })
  })

  it('allowlists app and universal deep-link shapes', () => {
    expect(parseTasteMapDeepLink('tastemap://restaurant/r1')).toEqual({ surface: 'restaurant', id: 'r1' })
    expect(parseTasteMapDeepLink('https://example.test/profile/tm_1')).toEqual({ surface: 'profile', id: 'tm_1' })
    expect(parseTasteMapDeepLink('https://example.test/admin/token')).toBeNull()
  })
})
