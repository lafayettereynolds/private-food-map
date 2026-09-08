import { describe, expect, it } from 'vitest'
import { calculateTasteSimilarities, findSimilarTasteUserIds, tasteSimilarityForDisplay, type TasteRatingSignal } from './tasteSimilarity'

function pair(count = 5): TasteRatingSignal[] {
  return Array.from({ length: count }, (_, index) => [
    { userId: 'owner', poiId: String(index), ratingOutOfTen: 3 + index % 5, tags: ['日料'] },
    { userId: 'similar', poiId: String(index), ratingOutOfTen: 5 + index % 5, tags: ['完全不同标签'] },
    { userId: 'different', poiId: String(index), ratingOutOfTen: 8 - index % 5, tags: ['日料'] },
  ]).flat()
}
describe('relative restaurant Pearson evidence', () => {
  it('gates legacy and friend precise-similarity consumers on sufficient evidence only', () => {
    expect(tasteSimilarityForDisplay(undefined)).toBeNull()
    expect(tasteSimilarityForDisplay({ evidenceState: 'insufficient', similarity: 1 })).toBeNull()
    expect(tasteSimilarityForDisplay({ evidenceState: 'forming', similarity: 1 })).toBeNull()
    expect(tasteSimilarityForDisplay({ evidenceState: 'sufficient', similarity: 0.8 })).toBe(0.8)
  })
  it('compares relative judgement despite different absolute score habits and ignores tags', () => {
    const result = calculateTasteSimilarities(pair(), 'owner')
    expect(result[0]).toMatchObject({ userId: 'similar', similarity: 1, sharedRestaurantCount: 5, evidenceState: 'forming', userMeanOutOfTen: 7, viewerMeanOutOfTen: 5 })
    expect(result[0].weightedSimilarity).toBeCloseTo(1 / 3)
    expect(result.at(-1)?.similarity).toBe(-1)
    expect([...findSimilarTasteUserIds(pair(), 'owner')]).toEqual(['similar'])
  })
  it('requires five distinct stable restaurants, not visits or tags', () => {
    expect(calculateTasteSimilarities(pair(4), 'owner')).toEqual([])
    expect(calculateTasteSimilarities(pair(1).flatMap(row => Array(50).fill(row)), 'owner')).toEqual([])
    expect(calculateTasteSimilarities(pair().map(row => row.userId === 'similar' ? { ...row, poiId: 'other-' + row.poiId } : row), 'owner').some(row => row.userId === 'similar')).toBe(false)
  })
  it('rejects constant and almost constant scoring, even all-nine common restaurants', () => {
    for (const scale of [0, 0.001]) expect(calculateTasteSimilarities(pair(10).map(row => ({ ...row, ratingOutOfTen: 9 + Number(row.poiId) * scale })), 'owner')).toEqual([])
  })
  it('keeps rho separate from shrinking evidence contribution for five versus fifty', () => {
    const five = calculateTasteSimilarities(pair(), 'owner')[0]
    const fifty = calculateTasteSimilarities(pair(50), 'owner')[0]
    expect(fifty.similarity).toBe(five.similarity)
    expect(fifty.evidenceState).toBe('sufficient')
    expect(fifty.weightedSimilarity).toBeCloseTo(50 / 60)
    expect(fifty.weightedSimilarity).toBeGreaterThan(five.weightedSimilarity)
  })
  it('weights repeated visits within a restaurant, but baseline weights distinct restaurants equally', () => {
    const signals = pair().filter(row => row.userId !== 'different')
    signals.push({ userId: 'similar', poiId: '0', ratingOutOfTen: 7, sampleCount: 3, tags: [] })
    const result = calculateTasteSimilarities(signals, 'owner')[0]
    // Restaurant zero: (5 + 3*7)/4=6.5; other restaurants 6,7,8,9.
    expect(result.userMeanOutOfTen).toBeCloseTo(7.3)
    expect(result.sharedRestaurantCount).toBe(5)
    expect(result.evidenceState).toBe('forming')
  })
  it('ignores invalid numeric data and resolves ties deterministically', () => {
    const signals = pair().filter(row => row.userId !== 'different').flatMap(row => [row, ...(row.userId === 'similar' ? [{ ...row, userId: 'similar-z' }] : [])])
    signals.push({ userId: 'similar', poiId: 'invalid', ratingOutOfTen: NaN, tags: [] })
    expect(calculateTasteSimilarities(signals, 'owner').map(row => row.userId)).toEqual(['similar', 'similar-z'])
  })
})
