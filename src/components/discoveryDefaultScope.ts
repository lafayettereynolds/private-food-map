import type { TasteMapDiscoveryCityPageRequest } from '../platform/TasteMapPlatform'
import { normalizeDiscoveryFilters, DISCOVERY_FILTER_TAXONOMY } from '../contracts/discoveryFilters'
import { normalizeDiscoverySessionPreferences } from '../contracts/discoverySessionPreferences'

/** Default For You shares Map's authoritative snapshot. An explicit query must
 * never filter that bounded snapshot and pretend it searched a whole city. */
export function usesCanonicalForYou(defaultCity: boolean, query: TasteMapDiscoveryCityPageRequest): boolean {
  if (!defaultCity || query.mode !== 'for_you' || (query.sort ?? 'recommended') !== 'recommended') return false
  const filters = normalizeDiscoveryFilters(query.filters, DISCOVERY_FILTER_TAXONOMY)
  if (filters.viewerStates.some(state => state !== 'none')) return false
  return JSON.stringify({ ...filters, viewerStates: [] }) === JSON.stringify(normalizeDiscoveryFilters())
    && JSON.stringify(normalizeDiscoverySessionPreferences(query.preferences)) === JSON.stringify(normalizeDiscoverySessionPreferences())
}
