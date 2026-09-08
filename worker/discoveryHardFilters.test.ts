import { describe, expect, it } from 'vitest'
import { readDiscoveryQuery, matchesDiscoveryHardFilters, assertCompleteDiscoveryPhotos, discoveryDistanceMeters, type DiscoveryFilterFacts } from './discoveryHardFilters'

const query = (filters: unknown = {}, sort?: string, mode: 'for_you' | 'latest' | 'trending' | 'similar_taste' = 'for_you') =>
  readDiscoveryQuery(new URL(`https://example.test/?filters=${encodeURIComponent(JSON.stringify(filters))}${sort ? `&sort=${sort}` : ''}`), mode)
const facts: DiscoveryFilterFacts = { tags: ['日料', '正餐'], latitude: 30, longitude: 120, publicScoreOutOfTen: 8, publicRatingUsers: 2, viewerState: 'none', actualPhoto: true }
describe('shipping Discovery query semantics', () => {
  it('applies CNY reference price before pagination with half-open bounds and unknown excluded', () => {
    const filters = query({ priceRange: { minimum: 100, maximumExclusive: 200, basis: 'reference_per_person', currency: 'CNY' } }).filters
    expect(matchesDiscoveryHardFilters({ ...facts, pricePerPerson: 100 }, filters)).toBe(true)
    expect(matchesDiscoveryHardFilters({ ...facts, pricePerPerson: 199 }, filters)).toBe(true)
    for (const pricePerPerson of [null, undefined, -1, 99, 200, NaN]) expect(matchesDiscoveryHardFilters({ ...facts, pricePerPerson }, filters)).toBe(false)
  })
  it('accepts complete explicit empty defaults and advertises no inferred region or currency', () => {
    expect(query(query().filters).filters).toEqual(query().filters)
    expect(() => query({ region: '西湖区' })).toThrow()
    expect(() => query({ priceRange: { minimum: 10, maximumExclusive: 50, basis: 'reference_per_person', currency: 'CNY' } })).not.toThrow()
    expect(() => query({ priceRange: { minimum: 10, maximumExclusive: 50, basis: 'reference_per_person', currency: 'USD' } })).toThrow('Unsupported')
    expect(() => query({ cuisines: ['name-guessed-cuisine'] })).toThrow()
  })
  it('uses OR within a facet, AND across facets; unknown scores never satisfy even explicit zero', () => {
    const filters = query({ cuisines: ['日料', '川菜'], types: ['正餐'], minimumPublicScoreOutOfTen: 8, minimumPublicRatingUsers: 2, viewerStates: ['none'], requireActualPhoto: true }).filters
    expect(matchesDiscoveryHardFilters(facts, filters)).toBe(true)
    for (const override of [{ tags: ['日料'] }, { publicScoreOutOfTen: 7.9 }, { publicRatingUsers: 1 }, { viewerState: 'visited' as const }, { actualPhoto: false }]) {
      expect(matchesDiscoveryHardFilters({ ...facts, ...override }, filters)).toBe(false)
    }
    expect(matchesDiscoveryHardFilters({ ...facts, publicScoreOutOfTen: null }, query({ minimumPublicScoreOutOfTen: 0 }).filters)).toBe(false)
  })
  it('requires a real declared reference for distance, never a city center', () => {
    expect(() => query({}, 'distance')).toThrow()
    const filters = query({ distance: { maximumMeters: 1000, reference: { latitude: 30, longitude: 120, source: 'device_location' } } }, 'distance').filters
    expect(matchesDiscoveryHardFilters(facts, filters)).toBe(true)
    expect(matchesDiscoveryHardFilters({ ...facts, latitude: null }, filters)).toBe(false)
    expect(matchesDiscoveryHardFilters({ ...facts, latitude: 31 }, filters)).toBe(false)
    expect(discoveryDistanceMeters({ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 0 })).toBe(0)
  })
  it.each([['latest', 'taste'], ['trending', 'public_rating'], ['similar_taste', 'taste']] as const)('rejects unsupported mode %s sort %s', (mode, sort) => {
    expect(() => query({}, sort, mode)).toThrow()
  })
  it('binds every normalized filter, session preference and sort into the fingerprint', () => {
    expect(query({ viewerStates: [] }).fingerprint).not.toBe(query().fingerprint)
    expect(query({ viewerStates: [] }).viewerStateFilterExplicit).toBe(true)
    expect(query().viewerStateFilterExplicit).toBe(false)
    expect(query({ types: ['咖啡', '正餐'] }).fingerprint).toBe(query({ types: ['正餐', '咖啡', '咖啡'] }).fingerprint)
    expect(query({ requireActualPhoto: true }).fingerprint).not.toBe(query().fingerprint)
    expect(query({}, 'taste').fingerprint).not.toBe(query().fingerprint)
    expect(readDiscoveryQuery(new URL('https://example.test/?preferences=%7B%22exploration%22:%22familiar%22%7D'), 'for_you').fingerprint).not.toBe(query().fingerprint)
  })
  it('does not silently truncate city photo eligibility beyond the old 1800 boundary', () => {
    expect(() => assertCompleteDiscoveryPhotos(1801)).not.toThrow()
    expect(() => assertCompleteDiscoveryPhotos(20_001)).toThrow('capacity')
  })
})
