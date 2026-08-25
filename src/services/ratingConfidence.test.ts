import { describe, expect, it } from 'vitest'
import { groupRatingDisplay, personalRestaurantRating, ratingConfidence } from './ratingConfidence'
import type { Visit } from '../types/domain'

describe('rating confidence', () => {
  it.each([
    [0, 'NO_DATA'], [1, 'INSUFFICIENT'], [4, 'INSUFFICIENT'], [5, 'LOW'], [9, 'LOW'], [10, 'NORMAL'],
  ] as const)('maps %s samples to %s', (count, expected) => {
    expect(ratingConfidence(count)).toBe(expected)
  })

  it('hides precise group scores below five independent users', () => {
    expect(groupRatingDisplay(9.2, 3)).toEqual({ confidence: 'INSUFFICIENT', displayScore: null, sampleLabel: '样本不足' })
    expect(groupRatingDisplay(8.3, 9)).toEqual({ confidence: 'LOW', displayScore: 8.3, sampleLabel: '样本较少' })
  })

  it('averages only valid rated visits for the current user', () => {
    const visits = [visit('a', 4), visit('b', 5), visit('c', null), { ...visit('d', 1), deletedAt: '2026-08-24' }]
    expect(personalRestaurantRating(visits)).toEqual({ score: 9, ratedVisitCount: 2 })
  })
})

function visit(id: string, rating: Visit['rating']): Visit {
  return {
    id, userId: 'owner', restaurantId: 'restaurant', visitedAt: '2026-08-24T12:00:00.000Z', rating, visibility: 'private', diningMode: 'dine_in', totalPrice: null, myActualSpend: null, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null, diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [], dishes: [], note: '', photos: [], photoIds: [], createdAt: '2026-08-24T12:00:00.000Z', updatedAt: '2026-08-24T12:00:00.000Z', deletedAt: null,
  }
}
