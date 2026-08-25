import { describe, expect, it } from 'vitest'
import { buildRecommendationSourceInsights, sourceInsightConfidence } from './recommendationSourceInsights'
import type { RestaurantSummary, Visit } from '../types/domain'

const restaurants = [{ id: 'r1', name: '餐厅 A', tags: ['日料'] }, { id: 'r2', name: '餐厅 B', tags: ['咖啡'] }] as RestaurantSummary[]
function visit(id: string, restaurantId: string, rating: Visit['rating']): Visit { return { id, userId: 'owner', restaurantId, visitedAt: `2026-08-${id.padStart(2, '0')}T12:00:00.000Z`, rating, visibility: 'private', diningMode: 'dine_in', totalPrice: null, myActualSpend: 100, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null, diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: 'xiaohongshu', recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [], dishes: [], note: '', photos: [], photoIds: [], createdAt: '', updatedAt: '', deletedAt: null } }

describe('recommendation source insights', () => {
  it('counts unique restaurants instead of visits', () => {
    const result = buildRecommendationSourceInsights(restaurants, [visit('1', 'r1', 4), visit('2', 'r1', 5), visit('3', 'r2', 2.5)])[0]
    expect(result.visitedRestaurantCount).toBe(2)
    expect(result.repeatRestaurantCount).toBe(1)
    expect(result.averagePostVisitRating).toBe(7)
  })

  it('does not allow tiny samples to become stable', () => {
    expect(sourceInsightConfidence(2)).toBe('INSUFFICIENT')
    expect(sourceInsightConfidence(3)).toBe('EMERGING')
    expect(sourceInsightConfidence(6)).toBe('LOW')
    expect(sourceInsightConfidence(10)).toBe('STABLE')
  })

  it('groups standard platforms by source type instead of incidental source text', () => {
    const first = { ...visit('1', 'r1', 4), recommendationSourceText: '博主甲' }
    const second = { ...visit('2', 'r2', 4.5), recommendationSourceText: '博主乙' }
    const result = buildRecommendationSourceInsights(restaurants, [first, second])

    expect(result).toHaveLength(1)
    expect(result[0].label).toBe('小红书')
    expect(result[0].visitedRestaurantCount).toBe(2)
  })
})
