import { describe, expect, it } from 'vitest'
import { buildCompanionInsights, companionInsightConfidence } from './companionInsights'
import type { DiningCompanion, RestaurantSummary, Visit } from '../types/domain'

const companion: DiningCompanion = { id: 'c1', ownerUserId: 'owner', displayName: '小王', linkedUserId: null, createdAt: '', updatedAt: '', deletedAt: null }
const restaurant = { id: 'r1', name: '餐厅 A', city: '杭州', tags: ['日料'] } as RestaurantSummary
function visit(id: string, rating: Visit['rating'], spend: number | null, restaurantId = 'r1'): Visit { return { id, userId: 'owner', restaurantId, visitedAt: `2026-08-${id.padStart(2, '0')}T12:00:00.000Z`, rating, visibility: 'private', diningMode: 'dine_in', totalPrice: 999, myActualSpend: spend, paymentMode: null, pricePerPerson: null, partySize: 2, queueDuration: null, diningOccasions: ['friends'], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: ['小王'], companionIds: ['c1'], dishes: [], note: '', photos: [], photoIds: [], createdAt: '', updatedAt: '', deletedAt: null } }

describe('companion insights', () => {
  it('uses configurable confidence thresholds', () => {
    expect(companionInsightConfidence(2)).toBe('INSUFFICIENT')
    expect(companionInsightConfidence(3)).toBe('EMERGING')
    expect(companionInsightConfidence(6)).toBe('STABLE')
  })

  it('uses only myActualSpend and keeps repeated restaurants distinct from visit count', () => {
    const result = buildCompanionInsights(companion, [restaurant], [visit('1', 4, 60), visit('2', 5, 80)])
    expect(result.sharedVisitCount).toBe(2)
    expect(result.restaurantCount).toBe(1)
    expect(result.repeatRestaurantCount).toBe(1)
    expect(result.spend.total).toBe(140)
    expect(result.spend.average).toBe(70)
    expect(result.rating.average).toBe(9)
  })
})
