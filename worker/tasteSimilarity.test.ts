import { describe, expect, it } from 'vitest'
import { calculateTasteSimilarities, findSimilarTasteUserIds, type TasteRatingSignal } from './tasteSimilarity'

const signals: TasteRatingSignal[] = [
  { userId: 'owner', poiId: 'sushi', ratingOutOfTen: 9.5, tags: ['日料'] },
  { userId: 'owner', poiId: 'yakiniku', ratingOutOfTen: 9, tags: ['烧肉'] },
  { userId: 'owner', poiId: 'coffee', ratingOutOfTen: 8.5, tags: ['咖啡'] },
  { userId: 'similar', poiId: 'sushi', ratingOutOfTen: 9, tags: ['日料'] },
  { userId: 'similar', poiId: 'yakiniku', ratingOutOfTen: 9.5, tags: ['烧肉'] },
  { userId: 'similar', poiId: 'coffee', ratingOutOfTen: 8, tags: ['咖啡'] },
  { userId: 'different', poiId: 'sushi', ratingOutOfTen: 3, tags: ['日料'] },
  { userId: 'different', poiId: 'yakiniku', ratingOutOfTen: 4, tags: ['烧肉'] },
  { userId: 'different', poiId: 'coffee', ratingOutOfTen: 5, tags: ['咖啡'] },
]

describe('TasteSimilarityService', () => {
  it('ranks users with aligned restaurant and cuisine ratings first', () => {
    const result = calculateTasteSimilarities(signals, 'owner')
    expect(result[0].userId).toBe('similar')
    expect(result[0].similarity).toBeGreaterThan(0.9)
    expect(result.at(-1)?.userId).toBe('different')
  })

  it('only returns users that clear the shared-signal threshold', () => {
    expect([...findSimilarTasteUserIds(signals, 'owner')]).toEqual(['similar'])
  })

  it('does not claim similarity from one shared restaurant plus several tags', () => {
    const sparse: TasteRatingSignal[] = [
      { userId: 'owner', poiId: 'one-place', ratingOutOfTen: 9, tags: ['日料', '寿司', '海鲜'] },
      { userId: 'candidate', poiId: 'one-place', ratingOutOfTen: 9, tags: ['日料', '寿司', '海鲜'] },
    ]
    expect(calculateTasteSimilarities(sparse, 'owner')).toEqual([])
  })

  it('uses the user id as a stable tie-breaker', () => {
    const tied = signals.filter((signal) => signal.userId !== 'different').flatMap((signal) => [
      signal,
      ...(signal.userId === 'similar' ? [{ ...signal, userId: 'similar-z' }] : []),
    ])
    expect(calculateTasteSimilarities(tied, 'owner').map((item) => item.userId))
      .toEqual(['similar', 'similar-z'])
  })
})
