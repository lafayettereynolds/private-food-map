import { describe, expect, it } from 'vitest'
import { normalizeDiscoverySessionPreferences as normalize, discoverySessionPreferenceBonus as bonus, discoveryExplorationPages as pages } from './discoverySessionPreferences'

describe('session-only recommendation preferences', () => {
  it('does not manufacture position or budget from empty preferences', () => {
    expect(normalize()).toEqual({ exploration: 'balanced', budget: null, occasion: 'any', nearby: false, reference: null })
    expect(bonus({}, normalize())).toBe(0)
  })
  it.each([{ nearby: true }, { reference: { latitude: 30, longitude: 120, source: 'city_center' } }, { exploration: 'anything' }, { occasion: 'three_companions' }, { budget: { minimum: 100, maximumExclusive: 100, currency: 'CNY' } }])('rejects invalid assumptions %j', raw => {
    expect(() => normalize(raw)).toThrow()
  })
  it('soft budget preserves unknown and out-of-range candidates without claiming a match', () => {
    const p = normalize({ budget: { minimum: 100, maximumExclusive: 200, currency: 'CNY' } })
    expect(bonus({}, p)).toBe(0)
    expect(bonus({ reliablePrice: { value: 100, currency: 'CNY' } }, p)).toBeGreaterThan(0)
    expect(bonus({ reliablePrice: { value: 200, currency: 'CNY' } }, p)).toBe(0)
    expect(bonus({ reliablePrice: { value: 150, currency: 'USD' } }, p)).toBe(0)
  })
  it('occasion affects ranking only with verified Restaurant scene data', () => {
    const p = normalize({ occasion: 'group' })
    expect(bonus({}, p)).toBe(0)
    expect(bonus({ verifiedOccasions: ['solo'] }, p)).toBe(0)
    expect(bonus({ verifiedOccasions: ['group'] }, p)).toBeGreaterThan(0)
  })
  it.each([['balanced', 4], ['adventurous', 8]] as const)('caps %s on every page including all-exploration tails', (exploration, cap) => {
    const items = Array.from({ length: 53 }, (_, id) => ({ id, explore: id % 9 !== 0 }))
    const result = pages(items, x => x.explore, 20, normalize({ exploration }))
    expect(result.every(page => page.length <= 20 && page.filter(x => x.explore).length <= cap)).toBe(true)
    expect(new Set(result.flat().map(x => x.id)).size).toBe(items.length)
    expect(result.flat()).toHaveLength(items.length)
    expect(items[0].id).toBe(0)
  })
  it('familiar mode never includes exploration and does not loop on an all-exploration pool', () => {
    expect(pages([1, 2, 3], () => true, 20, normalize({ exploration: 'familiar' }))).toEqual([])
    expect(pages([1, 2, 3], x => x === 2, 20, normalize({ exploration: 'familiar' }))).toEqual([[1, 3]])
  })
})
