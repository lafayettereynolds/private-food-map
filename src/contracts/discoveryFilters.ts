/** Request semantics only. No shipping endpoint supports a filter merely by
 * importing this file. Visibility, identity merging and query execution remain
 * server responsibilities; account/city/mode/sort scope belongs to the caller. */
export const DISCOVERY_FILTER_VIEWER_STATES = ['none', 'want_to_go', 'visited'] as const
export const DISCOVERY_DISTANCE_REFERENCE_SOURCES = ['device_location', 'user_selected_point'] as const
export const DISCOVERY_PRICE_BASES = ['reference_per_person', 'recorded_per_person'] as const

export type DiscoveryFilterViewerState = typeof DISCOVERY_FILTER_VIEWER_STATES[number]
export type DiscoveryDistanceReferenceSource = typeof DISCOVERY_DISTANCE_REFERENCE_SOURCES[number]
export type DiscoveryPriceBasis = typeof DISCOVERY_PRICE_BASES[number]

/** Explicit product taxonomy, not a classifier derived from names/emoji/artwork.
 * Empty registries reject nonempty facet selections until a taxonomy is wired. */
export interface DiscoveryFilterTaxonomy {
  cuisines?: readonly string[]
  types?: readonly string[]
}

/** These facets classify explicit stored tags only. Names, images, city names
 * and addresses are not evidence for a cuisine or restaurant type. */
export const DISCOVERY_FILTER_TAXONOMY: Required<DiscoveryFilterTaxonomy> = {
  cuisines: ['中餐', '杭帮菜', '江浙菜', '川菜', '粤菜', '湘菜', '日料', '韩餐', '泰餐', '越南菜', '西餐', '意大利菜', '法国菜', '墨西哥菜', '印度菜', '中东菜'],
  types: ['正餐', '火锅', '烧烤', '咖啡', '甜品', '小吃', '面馆', '快餐', '酒吧', '海鲜', '早午餐'],
}

export interface DiscoveryPriceRange {
  minimum: number
  maximumExclusive: number | null
  basis: DiscoveryPriceBasis
  /** Missing currency is representable, but cannot pass capability validation. */
  currency: string | null
}

export interface DiscoveryDistanceFilter {
  maximumMeters: number
  /** Structural provenance, not proof of location permission or freshness.
   * The trusted platform must supply/verify this; no coordinates are inferred. */
  reference: {
    latitude: number
    longitude: number
    source: DiscoveryDistanceReferenceSource
  }
}

export interface NormalizedDiscoveryFilters {
  cuisines: string[]
  types: string[]
  priceRange: DiscoveryPriceRange | null
  minimumPublicScoreOutOfTen: number | null
  minimumPublicRatingUsers: number | null
  viewerStates: DiscoveryFilterViewerState[]
  requireActualPhoto: boolean
  distance: DiscoveryDistanceFilter | null
}

export interface DiscoveryAppliedQuery {
  filters: NormalizedDiscoveryFilters
  sort: string
  preferences: import('./discoverySessionPreferences').DiscoverySessionPreferences
}

export class DiscoveryFilterValidationError extends Error {
  readonly code = 'invalid_discovery_filter'
  constructor(readonly path: string) {
    super(`Invalid Discovery filter: ${path}`)
    this.name = 'DiscoveryFilterValidationError'
  }
}

const fail = (path: string): never => { throw new DiscoveryFilterValidationError(path) }
const absent = (value: unknown) => value === undefined || value === null

function record(value: unknown, keys: readonly string[], path: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)
    || (Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null)) return fail(path)
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key !== 'string' || !keys.includes(key)) return fail(`${path}.${String(key)}`)
  }
  return value as Record<string, unknown>
}

function number(value: unknown, path: string, minimum: number, maximum = Number.MAX_VALUE): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum || value > maximum) return fail(path)
  return Object.is(value, -0) ? 0 : value
}

function enumeration<T extends string>(value: unknown, values: readonly T[], path: string): T {
  return typeof value === 'string' && values.includes(value as T) ? value as T : fail(path)
}

function selection<T extends string>(value: unknown, values: readonly T[], path: string): T[] {
  if (absent(value)) return []
  if (!Array.isArray(value)) return fail(path)
  return [...new Set(Array.from(value, (item, index) => enumeration(item, values, `${path}[${index}]`)))].sort()
}

function priceRange(value: unknown): DiscoveryPriceRange | null {
  if (absent(value)) return null
  const path = 'filters.priceRange'
  const range = record(value, ['minimum', 'maximumExclusive', 'basis', 'currency'], path)
  const minimum = number(range.minimum, `${path}.minimum`, 0)
  const maximumExclusive = absent(range.maximumExclusive) ? null : number(range.maximumExclusive, `${path}.maximumExclusive`, 0)
  if (maximumExclusive !== null && maximumExclusive <= minimum) return fail(`${path}.maximumExclusive`)
  const basis = enumeration(range.basis, DISCOVERY_PRICE_BASES, `${path}.basis`)
  // This checks an identifier's syntax, not whether a currency is supported or
  // matches the stored amount. The capability check below is mandatory.
  const currency = absent(range.currency) ? null : range.currency
  if (currency !== null && (typeof currency !== 'string' || !/^[A-Z]{3}$/.test(currency))) return fail(`${path}.currency`)
  return { minimum, maximumExclusive, basis, currency: currency as string | null }
}

function distanceFilter(value: unknown): DiscoveryDistanceFilter | null {
  if (absent(value)) return null
  const path = 'filters.distance'
  const distance = record(value, ['maximumMeters', 'reference'], path)
  const maximumMeters = number(distance.maximumMeters, `${path}.maximumMeters`, 0)
  if (maximumMeters === 0) return fail(`${path}.maximumMeters`)
  const reference = record(distance.reference, ['latitude', 'longitude', 'source'], `${path}.reference`)
  return { maximumMeters, reference: {
    latitude: number(reference.latitude, `${path}.reference.latitude`, -90, 90),
    longitude: number(reference.longitude, `${path}.reference.longitude`, -180, 180),
    source: enumeration(reference.source, DISCOVERY_DISTANCE_REFERENCE_SOURCES, `${path}.reference.source`),
  } }
}

/** OR within a facet, AND across active facets. Missing/null numeric filters
 * mean no condition, never zero; explicit 0 remains an active numeric bound.
 * Unknown fields fail closed, including administrative area/city/sort fields. */
export function normalizeDiscoveryFilters(raw: unknown = {}, taxonomy: DiscoveryFilterTaxonomy = {}): NormalizedDiscoveryFilters {
  const input = record(raw, ['cuisines', 'types', 'priceRange', 'minimumPublicScoreOutOfTen',
    'minimumPublicRatingUsers', 'viewerStates', 'requireActualPhoto', 'distance'], 'filters')
  const minimumPublicScoreOutOfTen = absent(input.minimumPublicScoreOutOfTen) ? null
    : number(input.minimumPublicScoreOutOfTen, 'filters.minimumPublicScoreOutOfTen', 0, 10)
  const minimumPublicRatingUsers = absent(input.minimumPublicRatingUsers) ? null
    : number(input.minimumPublicRatingUsers, 'filters.minimumPublicRatingUsers', 0, Number.MAX_SAFE_INTEGER)
  if (minimumPublicRatingUsers !== null && !Number.isInteger(minimumPublicRatingUsers)) return fail('filters.minimumPublicRatingUsers')
  if (input.requireActualPhoto !== undefined && typeof input.requireActualPhoto !== 'boolean') return fail('filters.requireActualPhoto')
  return {
    cuisines: selection(input.cuisines, taxonomy.cuisines ?? [], 'filters.cuisines'),
    types: selection(input.types, taxonomy.types ?? [], 'filters.types'),
    priceRange: priceRange(input.priceRange),
    minimumPublicScoreOutOfTen,
    minimumPublicRatingUsers,
    viewerStates: selection(input.viewerStates, DISCOVERY_FILTER_VIEWER_STATES, 'filters.viewerStates'),
    requireActualPhoto: input.requireActualPhoto === true,
    distance: distanceFilter(input.distance),
  }
}

/** Deterministic canonical JSON, not a hash, signature, or authorized cursor.
 * Caller must bind its owner/mode/city/sort/window separately and must not log
 * precise location fingerprints as non-sensitive analytics. */
export function discoveryFiltersFingerprint(raw: unknown = {}, taxonomy: DiscoveryFilterTaxonomy = {}): string {
  return JSON.stringify([1, normalizeDiscoveryFilters(raw, taxonomy)])
}

/** A producer must explicitly advertise implemented capability. No defaults
 * assert support for the existing Worker, Browser, Native or debug endpoints. */
export interface DiscoveryFilterCapabilities {
  cuisines?: boolean
  types?: boolean
  publicScore?: boolean
  publicRatingUsers?: boolean
  viewerStates?: boolean
  actualPhoto?: boolean
  distanceReferenceSources?: readonly DiscoveryDistanceReferenceSource[]
  price?: { bases: readonly DiscoveryPriceBasis[]; currencies: readonly string[] }
}

export interface DiscoveryFilterCapabilityIssue {
  field: keyof NormalizedDiscoveryFilters
  code: 'unsupported_filter' | 'currency_required' | 'unsupported_currency' | 'unsupported_price_basis' | 'unsupported_reference_source'
}

export function discoveryFilterCapabilityIssues(
  filters: NormalizedDiscoveryFilters,
  capabilities: DiscoveryFilterCapabilities = {},
): DiscoveryFilterCapabilityIssue[] {
  const issues: DiscoveryFilterCapabilityIssue[] = []
  const unsupported = (field: keyof NormalizedDiscoveryFilters, active: boolean, supported: boolean | undefined) => {
    if (active && supported !== true) issues.push({ field, code: 'unsupported_filter' })
  }
  unsupported('cuisines', filters.cuisines.length > 0, capabilities.cuisines)
  unsupported('types', filters.types.length > 0, capabilities.types)
  unsupported('minimumPublicScoreOutOfTen', filters.minimumPublicScoreOutOfTen !== null, capabilities.publicScore)
  unsupported('minimumPublicRatingUsers', filters.minimumPublicRatingUsers !== null, capabilities.publicRatingUsers)
  unsupported('viewerStates', filters.viewerStates.length > 0, capabilities.viewerStates)
  unsupported('requireActualPhoto', filters.requireActualPhoto, capabilities.actualPhoto)
  if (filters.distance && !capabilities.distanceReferenceSources?.includes(filters.distance.reference.source)) {
    issues.push({ field: 'distance', code: 'unsupported_reference_source' })
  }
  if (filters.priceRange) {
    const { basis, currency } = filters.priceRange
    if (!capabilities.price) issues.push({ field: 'priceRange', code: 'unsupported_filter' })
    else if (!capabilities.price.bases.includes(basis)) issues.push({ field: 'priceRange', code: 'unsupported_price_basis' })
    if (!currency) issues.push({ field: 'priceRange', code: 'currency_required' })
    else if (capabilities.price && !capabilities.price.currencies.includes(currency)) issues.push({ field: 'priceRange', code: 'unsupported_currency' })
  }
  return issues
}

/** Pure numeric boundary primitive for a known, same-basis/same-currency value.
 * Unknown price/currency must not be treated as free or converted implicitly. */
export function discoveryPriceMatchesRange(
  value: { amount: number | null; currency: string | null; basis: DiscoveryPriceBasis } | null,
  range: DiscoveryPriceRange,
): boolean {
  return value !== null && value.amount !== null && Number.isFinite(value.amount)
    && range.currency !== null && value.currency === range.currency && value.basis === range.basis
    && value.amount >= range.minimum && (range.maximumExclusive === null || value.amount < range.maximumExclusive)
}
