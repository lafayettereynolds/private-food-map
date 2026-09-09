import { describe, expect, it } from 'vitest'
import { usesCanonicalForYou } from './discoveryDefaultScope'
import { normalizeDiscoveryQueryDraft } from './DiscoveryQueryPanel'
import { normalizeDiscoveryFilters } from '../contracts/discoveryFilters'
import { normalizeDiscoverySessionPreferences } from '../contracts/discoverySessionPreferences'
const draft = () => ({ city: '', filters: normalizeDiscoveryFilters(), sort: 'recommended' as const, windowDays: 7 as const, preferences: normalizeDiscoverySessionPreferences() })
describe('Discovery default and explicit query boundaries', () => {
  it('shares the canonical default but never substitutes it for an explicit city', () => {
    const query = { ...draft(), mode: 'for_you' as const, city: '杭州' }
    expect(usesCanonicalForYou(true, query)).toBe(true)
    expect(usesCanonicalForYou(false, query)).toBe(false)
    expect(usesCanonicalForYou(true, { ...query, mode: 'latest' })).toBe(false)
    expect(usesCanonicalForYou(true, { ...query, sort: 'taste' })).toBe(false)
  })
  it('sends every explicit hard condition and session preference to the full query', () => {
    const query = { ...draft(), mode: 'for_you' as const }
    for (const filters of [
      { cuisines: ['川菜'] }, { types: ['火锅'] }, { minimumPublicScoreOutOfTen: 8 },
      { minimumPublicRatingUsers: 3 }, { viewerStates: ['visited' as const] }, { requireActualPhoto: true },
      { priceRange: { minimum: 0, maximumExclusive: 50, currency: 'CNY', basis: 'reference_per_person' as const } },
      { distance: { maximumMeters: 500, reference: { latitude: 30, longitude: 120, source: 'device_location' as const } } },
    ]) expect(usesCanonicalForYou(true, { ...query, filters: { ...query.filters, ...filters } })).toBe(false)
    expect(usesCanonicalForYou(true, { ...query, preferences: { ...query.preferences, exploration: 'adventurous' } })).toBe(false)
    expect(usesCanonicalForYou(true, { ...query, filters: { ...query.filters, viewerStates: ['none'] } })).toBe(true)
  })
  it('applies a default-city query even when location is not yet available', () => {
    expect(normalizeDiscoveryQueryDraft(draft()).city).toBe('')
    expect(normalizeDiscoveryQueryDraft({ ...draft(), city: ' 杭州 ' }).city).toBe('杭州')
  })
  it('rejects distance sorting without authorized coordinates and invalid filters', () => {
    expect(() => normalizeDiscoveryQueryDraft({ ...draft(), sort: 'distance' })).toThrow('距离排序')
    expect(() => normalizeDiscoveryQueryDraft({ ...draft(), filters: { ...draft().filters, minimumPublicScoreOutOfTen: 11 } })).toThrow()
  })
})
