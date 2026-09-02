export type HybridRouteStatus =
  | 'NATIVE_PRIMARY'
  | 'HYBRID_POC'
  | 'HYBRID_READY'
  | 'HYBRID_INTEGRATED'
  | 'HYBRID_PRIMARY'
  | 'NATIVE_ROLLBACK'
  | 'RETIRED_AFTER_MIGRATION'

export const HYBRID_ROUTE_REGISTRY = {
  map: 'HYBRID_INTEGRATED',
  discovery: 'HYBRID_INTEGRATED',
  add: 'HYBRID_INTEGRATED',
  restaurant: 'HYBRID_INTEGRATED',
  profile: 'HYBRID_INTEGRATED',
  visit: 'HYBRID_INTEGRATED',
  visitEdit: 'HYBRID_INTEGRATED',
  lists: 'HYBRID_INTEGRATED',
  roulette: 'HYBRID_INTEGRATED',
  analytics: 'HYBRID_INTEGRATED',
  premium: 'HYBRID_INTEGRATED',
  settings: 'HYBRID_INTEGRATED',
  publicList: 'HYBRID_INTEGRATED',
  activity: 'HYBRID_INTEGRATED',
} as const satisfies Record<string, HybridRouteStatus>

export type HybridSurface = keyof typeof HYBRID_ROUTE_REGISTRY

export type HybridRoute =
  | { surface: 'profile'; id?: string }
  | { surface: 'restaurant'; id: string }
  | { surface: Exclude<HybridSurface, 'profile' | 'restaurant'>; id?: string }

const hybridPath = /^#\/(?:hybrid\/)?([^/?#]+)(?:\/([^/?#]+))?/

export function routeFromLocation(location: Pick<Location, 'hash'>): HybridRoute {
  const match = location.hash.match(hybridPath)
  if (!match) return { surface: 'profile' }
  const surface = match[1] as HybridSurface
  if (!(surface in HYBRID_ROUTE_REGISTRY)) return { surface: 'profile' }
  if (surface === 'restaurant') {
    return match[2]
      ? { surface, id: decodeURIComponent(match[2]) }
      : { surface: 'profile' }
  }
  if (surface === 'profile') return { surface, id: match[2] ? decodeURIComponent(match[2]) : undefined }
  return { surface, id: match[2] ? decodeURIComponent(match[2]) : undefined }
}

/**
 * Browser and Capacitor deep links are authoritative. The Debug fixture route is
 * only a fallback for an otherwise empty launch and must never mask an explicit
 * URL/deep-link route during refresh.
 */
export function routeFromStartupLocation(
  location: Pick<Location, 'hash'>,
  debugFallbackHash?: string,
): HybridRoute {
  return routeFromLocation({ hash: location.hash || debugFallbackHash || '' } as Location)
}

export function routeHash(route: HybridRoute) {
  if (route.surface === 'restaurant') return `#/restaurant/${encodeURIComponent(route.id)}`
  if (route.surface === 'profile') return route.id ? `#/profile/${encodeURIComponent(route.id)}` : '#/profile'
  return route.id
    ? `#/${route.surface}/${encodeURIComponent(route.id)}`
    : `#/${route.surface}`
}

export function surfaceStatus(surface: HybridSurface) {
  return HYBRID_ROUTE_REGISTRY[surface]
}

export interface TasteMapDeepLinkRoute {
  surface: 'restaurant' | 'profile' | 'list' | 'activity'
  id: string
}

export function isHybridOwnedRoute(route: HybridRoute) {
  return route.surface !== 'profile' || !route.id
}

/** Parses only the allowlisted local/deep-link contract; it never navigates. */
export function parseTasteMapDeepLink(rawValue: string): TasteMapDeepLinkRoute | null {
  let url: URL
  try { url = new URL(rawValue) } catch { return null }
  const parts = url.pathname.split('/').filter(Boolean)
  const schemeSurface = url.protocol === 'tastemap:' ? url.hostname : parts[0]
  const schemeID = url.protocol === 'tastemap:' ? parts[0] : parts[1]
  if (!schemeID || !['restaurant', 'profile', 'list', 'activity'].includes(schemeSurface)) return null
  return { surface: schemeSurface as TasteMapDeepLinkRoute['surface'], id: decodeURIComponent(schemeID) }
}
