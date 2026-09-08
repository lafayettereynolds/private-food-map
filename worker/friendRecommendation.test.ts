import { describe, expect, it } from 'vitest'
import { rankFriendRecommendations } from './friendRecommendation'
import { calculateTasteSimilarities, tasteSimilarityForDisplay } from './tasteSimilarity'

describe('rankFriendRecommendations', () => {
  it('consumes shared evidence without turning forming or flat ratings into a taste claim', () => {
    for (const [count, flat] of [[5, false], [10, true], [10, false]] as const) {
      const signals = ['owner', 'peer'].flatMap(userId => Array.from({ length: count }, (_, index) => ({ userId, poiId: String(index), ratingOutOfTen: flat ? 9 : 5 + index % 5, tags: [] })))
      const evidence = calculateTasteSimilarities(signals, 'owner')[0]
      const [result] = rankFriendRecommendations([{ userId: 'peer', mutualFriendCount: 0, linkedCompanion: false,
        tasteSimilarity: tasteSimilarityForDisplay(evidence), tasteSignalCount: evidence?.evidenceState === 'sufficient' ? evidence.signalCount : 0,
        sharedRestaurantCount: count, sameCity: true }])
      expect(result.primaryReason.code).toBe(count === 10 && !flat ? 'taste_similarity' : 'shared_restaurants')
      expect(result.primaryReason.text).not.toContain('%')
    }
  })
  it('uses one strongest explainable reason and does not rank candidates without signals', () => {
    const result = rankFriendRecommendations([
      { userId: 'mutual', mutualFriendCount: 3, linkedCompanion: false, tasteSimilarity: null, tasteSignalCount: 0, sharedRestaurantCount: 0, sameCity: false },
      { userId: 'companion', mutualFriendCount: 0, linkedCompanion: true, tasteSimilarity: null, tasteSignalCount: 0, sharedRestaurantCount: 0, sameCity: false },
      { userId: 'none', mutualFriendCount: 0, linkedCompanion: false, tasteSimilarity: null, tasteSignalCount: 0, sharedRestaurantCount: 0, sameCity: false },
    ])
    expect(result.map((item) => item.userId)).toEqual(['mutual', 'companion'])
    expect(result[0].primaryReason.text).toBe('3 位共同好友')
    expect(result[0].strength).toBe('priority')
    expect(result[1].strength).toBe('priority')
  })

  it('does not claim taste similarity when evidence is insufficient', () => {
    const [result] = rankFriendRecommendations([
      { userId: 'candidate', mutualFriendCount: 0, linkedCompanion: false, tasteSimilarity: 0.98, tasteSignalCount: 2, sharedRestaurantCount: 2, sameCity: true },
    ])
    expect(result.primaryReason.code).toBe('shared_restaurants')
    expect(result.strength).toBe('recommended')
  })

  it('keeps same-city as a weak fallback signal', () => {
    const [result] = rankFriendRecommendations([
      { userId: 'candidate', mutualFriendCount: 0, linkedCompanion: false, tasteSimilarity: null, tasteSignalCount: 0, sharedRestaurantCount: 0, sameCity: true },
    ])
    expect(result.primaryReason.code).toBe('same_city')
    expect(result.score).toBe(5)
    expect(result.strength).toBe('discovery')
  })
})
