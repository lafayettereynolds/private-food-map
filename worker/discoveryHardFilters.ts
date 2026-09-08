import {
  DISCOVERY_FILTER_TAXONOMY, discoveryFilterCapabilityIssues, discoveryPriceMatchesRange,
  normalizeDiscoveryFilters, type DiscoveryFilterCapabilities, type NormalizedDiscoveryFilters,
} from '../src/contracts/discoveryFilters'
import {
  DEFAULT_DISCOVERY_SESSION_PREFERENCES, normalizeDiscoverySessionPreferences,
} from '../src/contracts/discoverySessionPreferences'
import { LEGACY_AMOUNT_CURRENCY, resolveRecordedMoney } from '../src/contracts/legacyMoney'

export const DISCOVERY_FILTER_CAPABILITIES: DiscoveryFilterCapabilities = {
  cuisines: true, types: true, publicScore: true, publicRatingUsers: true,
  viewerStates: true, actualPhoto: true,
  distanceReferenceSources: ['device_location', 'user_selected_point'],
  price: { bases: ['reference_per_person'], currencies: [LEGACY_AMOUNT_CURRENCY] },
}
export const DISCOVERY_QUERY_SORTS = {
  for_you: ['recommended', 'taste', 'public_rating', 'distance'],
  similar_taste: ['recommended', 'similar_rating', 'distance'],
  trending: ['trend'], latest: ['latest'], following: ['latest'],
} as const
export class DiscoveryQueryError extends Error {
  constructor(message: string, readonly status = 400, readonly code = 'invalid_discovery_filter') { super(message) }
}
export function readDiscoveryQuery(url: URL, mode: keyof typeof DISCOVERY_QUERY_SORTS) {
  const parse = (key: string): unknown => {
    const raw = url.searchParams.get(key)
    if (raw === null) return {}
    if (raw.length > 4096) throw new DiscoveryQueryError(`Invalid ${key}.`)
    try { return JSON.parse(raw) } catch { throw new DiscoveryQueryError(`Invalid ${key}.`) }
  }
  let filters: NormalizedDiscoveryFilters
  let viewerStateFilterExplicit = false
  let preferences: ReturnType<typeof normalizeDiscoverySessionPreferences>
  try {
    const rawFilters = parse('filters')
    filters = normalizeDiscoveryFilters(rawFilters, DISCOVERY_FILTER_TAXONOMY)
    viewerStateFilterExplicit = Object.prototype.hasOwnProperty.call(rawFilters, 'viewerStates')
    preferences = normalizeDiscoverySessionPreferences(parse('preferences'))
  } catch (error) { throw new DiscoveryQueryError(error instanceof Error ? error.message : 'Invalid filters.') }
  const issues = discoveryFilterCapabilityIssues(filters, DISCOVERY_FILTER_CAPABILITIES)
  if (issues.length) throw new DiscoveryQueryError(`Unsupported filter: ${issues.map(issue => issue.field).join(', ')}.`, 400, 'unsupported_discovery_filter')
  const personalized = mode === 'for_you' || mode === 'similar_taste'
  if (!personalized && JSON.stringify(preferences) !== JSON.stringify(normalizeDiscoverySessionPreferences(DEFAULT_DISCOVERY_SESSION_PREFERENCES))) {
    throw new DiscoveryQueryError('Session preferences are only supported for personalized discovery.', 400, 'unsupported_discovery_filter')
  }
  const sorts: readonly string[] = DISCOVERY_QUERY_SORTS[mode]
  const sort = url.searchParams.get('sort') ?? sorts[0]
  if (!sorts.includes(sort) || (sort === 'distance' && !filters.distance)) throw new DiscoveryQueryError('Invalid Discovery sort or missing distance reference.')
  return { filters, preferences, sort, viewerStateFilterExplicit,
    fingerprint: JSON.stringify([1, filters, preferences, sort, viewerStateFilterExplicit]) }
}
export type DiscoveryQuery = ReturnType<typeof readDiscoveryQuery>
export interface DiscoveryFilterFacts {
  pricePerPerson?: number | null
  tags: readonly string[]
  latitude: number | null
  longitude: number | null
  publicScoreOutOfTen: number | null
  publicRatingUsers: number
  viewerState: 'none' | 'want_to_go' | 'visited'
  actualPhoto: boolean
}
export function discoveryDistanceMeters(facts: Pick<DiscoveryFilterFacts, 'latitude' | 'longitude'>, reference: { latitude: number; longitude: number }): number | null {
  if (facts.latitude === null || facts.longitude === null || !Number.isFinite(facts.latitude) || !Number.isFinite(facts.longitude)
    || Math.abs(facts.latitude) > 90 || Math.abs(facts.longitude) > 180) return null
  const rad = Math.PI / 180
  const a = Math.sin((facts.latitude - reference.latitude) * rad / 2) ** 2
    + Math.cos(facts.latitude * rad) * Math.cos(reference.latitude * rad) * Math.sin((facts.longitude - reference.longitude) * rad / 2) ** 2
  return 6_371_000 * 2 * Math.asin(Math.sqrt(Math.min(1, a)))
}
export function matchesDiscoveryHardFilters(facts: DiscoveryFilterFacts, filters: NormalizedDiscoveryFilters): boolean {
  if (filters.cuisines.length && !filters.cuisines.some(tag => facts.tags.includes(tag))) return false
  if (filters.types.length && !filters.types.some(tag => facts.tags.includes(tag))) return false
  if (filters.minimumPublicScoreOutOfTen !== null && (facts.publicScoreOutOfTen === null || facts.publicScoreOutOfTen < filters.minimumPublicScoreOutOfTen)) return false
  if (filters.minimumPublicRatingUsers !== null && facts.publicRatingUsers < filters.minimumPublicRatingUsers) return false
  if (filters.viewerStates.length && !filters.viewerStates.includes(facts.viewerState)) return false
  if (filters.requireActualPhoto && !facts.actualPhoto) return false
  if (filters.distance) {
    const distance = discoveryDistanceMeters(facts, filters.distance.reference)
    if (distance === null || distance > filters.distance.maximumMeters) return false
  }
  const money = resolveRecordedMoney(facts.pricePerPerson)
  return filters.priceRange === null || discoveryPriceMatchesRange(money
    ? { amount: money.value, currency: money.currency, basis: 'reference_per_person' } : null, filters.priceRange)
}

/** A hard bound must fail explicitly, never silently classify omitted photos
 * as absent. The previous 1,800/2,000 row truncation produced false negatives. */
export const DISCOVERY_PHOTO_SCAN_LIMIT = 20_000
export function assertCompleteDiscoveryPhotos(count: number) {
  if (count > DISCOVERY_PHOTO_SCAN_LIMIT) throw new DiscoveryQueryError('This city exceeds the supported photo scan capacity. Narrow the city and retry.', 503, 'discovery_capacity_exceeded')
}

/** Public restaurant evidence, not the selected activity's rating. Resolve
 * transitive explicit provider identities before aggregating; repeat Visits
 * remain records, while reviewer count is distinct per person. */
export async function readPublicFilterStatistics(database: D1Database, viewerId: string, restaurantIDs: string[], snapshotISO: string) {
  if (!restaurantIDs.length) return new Map<string, { score: number | null; users: number }>()
  const rows = await database.prepare(`WITH RECURSIVE aliases(root, id) AS (
    SELECT value, value FROM json_each(?)
    UNION
    SELECT a.root, other.restaurant_id FROM aliases a
    JOIN restaurant_place_identities own ON own.restaurant_id = a.id AND own.provider <> 'manual'
    JOIN restaurant_place_identities other ON other.provider = own.provider AND other.external_id = own.external_id
  )
  SELECT a.root, AVG(CASE WHEN v.rating > 0 AND v.rating <= 5 THEN v.rating END) * 2 AS score,
    COUNT(DISTINCT CASE WHEN v.rating > 0 AND v.rating <= 5 THEN v.user_id END) AS users
  FROM aliases a
  JOIN restaurants r ON r.id = a.id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
  JOIN visits v ON v.restaurant_id = r.id AND v.deleted_at IS NULL AND COALESCE(v.is_test_data, 0) = 0 AND v.visibility = 'public' AND v.visited_at <= ?
  JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL AND up.visibility = 'public'
  WHERE NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE ub.deleted_at IS NULL AND (
    (ub.blocker_user_id = ? AND ub.blocked_user_id = v.user_id) OR (ub.blocker_user_id = v.user_id AND ub.blocked_user_id = ?)))
  AND NOT EXISTS (SELECT 1 FROM content_reports cr WHERE cr.status = 'actioned' AND (
    (cr.content_type = 'visit' AND cr.content_id = v.id) OR (cr.content_type = 'user' AND cr.content_id = v.user_id)))
  GROUP BY a.root`).bind(JSON.stringify(restaurantIDs), snapshotISO, viewerId, viewerId).all<{ root: string; score: number | null; users: number }>()
  return new Map(rows.results.map(row => [row.root, { score: row.score, users: row.users }]))
}
