import { describe, expect, it } from 'vitest'
import {
  discoveryFilterCapabilityIssues, discoveryFiltersFingerprint, discoveryPriceMatchesRange,
  DiscoveryFilterValidationError, normalizeDiscoveryFilters,
} from './discoveryFilters'

const taxonomy = { cuisines: ['川菜', '日料'], types: ['面馆', '咖啡'] }
const price = { minimum: 50, maximumExclusive: 100, basis: 'recorded_per_person', currency: 'CNY' }
const distance = { maximumMeters: 3000, reference: { latitude: 30.25, longitude: 120.15, source: 'device_location' } }

describe('Discovery hard-filter request normalization (not endpoint support)', () => {
  it('keeps missing numeric values unknown rather than zero and returns fresh values', () => {
    expect(normalizeDiscoveryFilters()).toEqual({ cuisines: [], types: [], priceRange: null,
      minimumPublicScoreOutOfTen: null, minimumPublicRatingUsers: null,
      viewerStates: [], requireActualPhoto: false, distance: null })
    expect(normalizeDiscoveryFilters({ minimumPublicScoreOutOfTen: null, minimumPublicRatingUsers: null })).toEqual(normalizeDiscoveryFilters())
    const explicitZero = normalizeDiscoveryFilters({ minimumPublicScoreOutOfTen: 0, minimumPublicRatingUsers: 0 })
    expect(explicitZero.minimumPublicScoreOutOfTen).toBe(0)
    expect(discoveryFiltersFingerprint(explicitZero)).not.toBe(discoveryFiltersFingerprint())
    const first = normalizeDiscoveryFilters(); first.viewerStates.push('visited')
    expect(normalizeDiscoveryFilters().viewerStates).toEqual([])
  })

  it('canonicalizes key/selection order, duplicates and negative zero without mutating input', () => {
    const input = { cuisines: ['日料', '川菜', '日料'], viewerStates: ['visited', 'none'] }
    const equivalent = { viewerStates: ['none', 'visited', 'none'], cuisines: ['川菜', '日料'] }
    expect(discoveryFiltersFingerprint(input, taxonomy)).toBe(discoveryFiltersFingerprint(equivalent, taxonomy))
    expect(input.cuisines).toEqual(['日料', '川菜', '日料'])
    expect(discoveryFiltersFingerprint({ minimumPublicScoreOutOfTen: -0 })).toBe(discoveryFiltersFingerprint({ minimumPublicScoreOutOfTen: 0 }))
    const normalized = normalizeDiscoveryFilters({ ...input, priceRange: price, distance }, taxonomy)
    expect(normalizeDiscoveryFilters(normalized, taxonomy)).toEqual(normalized)
  })

  it.each([null, [], 'all', 4, { city: '杭州' }, { sort: 'rating' }, { district: '西湖区' },
    { owner: 'other' }, { requireActualPhoto: 1 }, { requireActualPhoto: null },
    { viewerStates: ['all'] }, { viewerStates: 'visited' }, { cuisines: ['chinese'] },
    { types: ['restaurant'] }, { types: [' 咖啡 '] }, new Date(),
  ])('rejects unknown fields, values and implicit coercions: %j', input => {
    expect(() => normalizeDiscoveryFilters(input, taxonomy)).toThrow(DiscoveryFilterValidationError)
  })

  it('requires an explicit taxonomy; artwork/name guesses never create cuisine IDs', () => {
    expect(() => normalizeDiscoveryFilters({ cuisines: ['日料'] })).toThrow()
    expect(normalizeDiscoveryFilters({ cuisines: ['日料'] }, taxonomy).cuisines).toEqual(['日料'])
    expect(() => normalizeDiscoveryFilters({ cuisines: ['japaneseKorean'] }, taxonomy)).toThrow()
    expect(() => normalizeDiscoveryFilters({ viewerStates: Array(1) })).toThrow()
  })

  it.each([-1, 10.01, NaN, Infinity, '8', true])('rejects invalid 10-point score %s', value => {
    expect(() => normalizeDiscoveryFilters({ minimumPublicScoreOutOfTen: value })).toThrow()
  })

  it('preserves ten-point decimal boundaries without rounding or five-point conversion', () => {
    expect(normalizeDiscoveryFilters({ minimumPublicScoreOutOfTen: 7.5 }).minimumPublicScoreOutOfTen).toBe(7.5)
    expect(normalizeDiscoveryFilters({ minimumPublicScoreOutOfTen: 10 }).minimumPublicScoreOutOfTen).toBe(10)
  })

  it.each([-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '3'])('requires an exact nonnegative different-user count %s', value => {
    expect(() => normalizeDiscoveryFilters({ minimumPublicRatingUsers: value })).toThrow()
  })

  it.each([
    { minimum: 100, maximumExclusive: 100 }, { minimum: 101, maximumExclusive: 100 },
    { minimum: -1 }, { minimum: '50' }, { maximumExclusive: Infinity }, { basis: 'any' },
    { currency: 'cny' }, { currency: '¥' }, { currency: 'USD ' }, { exchangeRate: 7 },
  ])('validates price ranges and explicit basis without currency assumptions: %j', change => {
    expect(() => normalizeDiscoveryFilters({ priceRange: { ...price, ...change } })).toThrow()
  })

  it('uses [minimum, maximumExclusive), includes genuine zero, rejects missing/mismatched prices', () => {
    const range = normalizeDiscoveryFilters({ priceRange: price }).priceRange!
    const matches = (amount: number | null, currency = 'CNY') => discoveryPriceMatchesRange({ amount, currency, basis: 'recorded_per_person' }, range)
    expect([49.99, 50, 99.99, 100].map(amount => matches(amount))).toEqual([false, true, true, false])
    expect(matches(null)).toBe(false); expect(matches(60, 'USD')).toBe(false)
    expect(discoveryPriceMatchesRange({ amount: 60, currency: 'CNY', basis: 'reference_per_person' }, range)).toBe(false)
    const open = normalizeDiscoveryFilters({ priceRange: { ...price, minimum: 0, maximumExclusive: null } }).priceRange!
    expect(discoveryPriceMatchesRange({ amount: 0, currency: 'CNY', basis: 'recorded_per_person' }, open)).toBe(true)
    expect(discoveryPriceMatchesRange({ amount: Infinity, currency: 'CNY', basis: 'recorded_per_person' }, open)).toBe(false)
    expect(discoveryPriceMatchesRange(null, open)).toBe(false)
  })

  it.each([
    { maximumMeters: 0 }, { maximumMeters: -1 }, { maximumMeters: Infinity }, { reference: null },
    { reference: { latitude: 91, longitude: 120, source: 'device_location' } },
    { reference: { latitude: 30, longitude: 181, source: 'device_location' } },
    { reference: { latitude: 30, longitude: 120, source: 'city_center' } },
    { reference: { latitude: 30, longitude: 120 } },
  ])('requires a valid distance reference and never substitutes a city center: %j', change => {
    expect(() => normalizeDiscoveryFilters({ distance: { ...distance, ...change } })).toThrow()
  })

  it('preserves legitimate zero coordinates and differentiates reference provenance', () => {
    const device = { distance: { ...distance, reference: { latitude: 0, longitude: 0, source: 'device_location' } } }
    const selected = { distance: { ...distance, reference: { latitude: 0, longitude: 0, source: 'user_selected_point' } } }
    expect(normalizeDiscoveryFilters(device).distance?.reference.latitude).toBe(0)
    expect(discoveryFiltersFingerprint(device)).not.toBe(discoveryFiltersFingerprint(selected))
  })

  it('fingerprints every hard condition, while never accepting account, mode, city or sort', () => {
    const candidates = [{ cuisines: ['日料'] }, { types: ['咖啡'] }, { priceRange: price },
      { minimumPublicScoreOutOfTen: 8 }, { minimumPublicRatingUsers: 3 },
      { viewerStates: ['want_to_go'] }, { requireActualPhoto: true }, { distance }]
    const fingerprints = candidates.map(value => discoveryFiltersFingerprint(value, taxonomy))
    expect(new Set(fingerprints).size).toBe(candidates.length)
    expect(fingerprints).not.toContain(discoveryFiltersFingerprint())
  })
})

describe('Discovery filter capability validation is distinct from request validation', () => {
  it('does not declare any active filter supported by default', () => {
    expect(discoveryFilterCapabilityIssues(normalizeDiscoveryFilters())).toEqual([])
    const filters = normalizeDiscoveryFilters({ cuisines: ['日料'], types: ['咖啡'], priceRange: price,
      minimumPublicScoreOutOfTen: 0, minimumPublicRatingUsers: 0, viewerStates: ['visited'], requireActualPhoto: true, distance }, taxonomy)
    expect(new Set(discoveryFilterCapabilityIssues(filters).map(issue => issue.field)).size).toBe(8)
  })

  it('requires explicit supported capabilities and compatible price/reference semantics', () => {
    const filters = normalizeDiscoveryFilters({ cuisines: ['日料'], types: ['咖啡'], priceRange: price,
      minimumPublicScoreOutOfTen: 8, minimumPublicRatingUsers: 3, viewerStates: ['none'], requireActualPhoto: true, distance }, taxonomy)
    expect(discoveryFilterCapabilityIssues(filters, { cuisines: true, types: true, publicScore: true,
      publicRatingUsers: true, viewerStates: true, actualPhoto: true, distanceReferenceSources: ['device_location'],
      price: { bases: ['recorded_per_person'], currencies: ['CNY'] } })).toEqual([])
    expect(discoveryFilterCapabilityIssues(filters, { price: { bases: ['reference_per_person'], currencies: ['USD'] },
      distanceReferenceSources: ['user_selected_point'] })).toEqual(expect.arrayContaining([
      { field: 'priceRange', code: 'unsupported_price_basis' }, { field: 'priceRange', code: 'unsupported_currency' },
      { field: 'distance', code: 'unsupported_reference_source' },
    ]))
  })

  it('never assumes a currency for stored legacy prices, even with price support', () => {
    const filters = normalizeDiscoveryFilters({ priceRange: { minimum: 0, basis: 'reference_per_person' } })
    expect(filters.priceRange?.currency).toBeNull()
    expect(discoveryFilterCapabilityIssues(filters, { price: { bases: ['reference_per_person'], currencies: ['CNY'] } }))
      .toEqual([{ field: 'priceRange', code: 'currency_required' }])
    expect(discoveryPriceMatchesRange({ amount: 20, currency: null, basis: 'reference_per_person' }, filters.priceRange!)).toBe(false)
  })
})
