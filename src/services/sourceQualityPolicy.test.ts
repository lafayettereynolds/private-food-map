import { describe, it, expect } from 'vitest'
import { sourcePitfall, compareSourcePitfalls, sourcePositiveRank } from './sourceQualityPolicy'
describe('source outcome policy', () => {
  it('uses an inclusive unrounded one-point gap, not an absolute low score', () => {
    expect(sourcePitfall(7, 8)).toBe(true)
    expect(sourcePitfall(5, 5)).toBe(false)
    expect(sourcePitfall(6, 6.999)).toBe(false)
    expect(sourcePitfall(null, 8)).toBe(false)
    expect(sourcePitfall(4, null)).toBe(false)
  })
  it('breaks equal raw pitfall rates by first average, not sample or repeat weighting', () => {
    const items = [{ id: 'a', pitfallRate: .5, firstAverage: 7 }, { id: 'z', pitfallRate: .5, firstAverage: 6 }, { id: 'c', pitfallRate: .6, firstAverage: 8 }]
    expect(items.sort(compareSourcePitfalls).map(item => item.id)).toEqual(['c', 'z', 'a'])
    expect(sourcePositiveRank(4, 5, .5)).toBe(.65)
  })
})
