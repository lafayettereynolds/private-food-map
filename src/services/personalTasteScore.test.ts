import { describe, expect, it } from 'vitest'
import type { RestaurantSummary } from '../types/domain'
import { predictPersonalTasteScore } from './personalTasteScore'

describe('predictPersonalTasteScore', () => {
  it('uses similar historical restaurants and excludes the current restaurant', () => {
    const target = restaurant({ id: 'target', tags: ['日料'], scoreOutOfTen: 1, visitCount: 1 })
    const result = predictPersonalTasteScore(target, [
      target,
      restaurant({ id: 'sushi', tags: ['日料'], scoreOutOfTen: 9, visitCount: 2 }),
      restaurant({ id: 'cafe', tags: ['咖啡'], scoreOutOfTen: 5, visitCount: 1, city: '上海市' }),
    ])

    expect(result.score).toBe(9)
    expect(result.matchedRestaurantCount).toBe(1)
    expect(result.ratedVisitCount).toBe(2)
  })

  it('returns no fabricated score without rated history', () => {
    const result = predictPersonalTasteScore(restaurant({ id: 'target' }), [])
    expect(result.score).toBeNull()
    expect(result.description).toBe('记录更多评分后生成')
  })
})

function restaurant(overrides: Partial<RestaurantSummary>): RestaurantSummary {
  const id = overrides.id ?? 'restaurant'
  const visitCount = overrides.visitCount ?? 0
  return {
    id, userId: 'owner', amapPoiId: id, name: id, address: '', city: '杭州市', latitude: 0, longitude: 0,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null,
    serviceRating: null, valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, merchantImageUrl: null,
    phone: null, openingHours: null, markerType: 'emoji', markerImageData: null, markerPhotoId: null, markerEmoji: '🍽️',
    createdAt: '', updatedAt: '', deletedAt: null, visits: Array.from({ length: visitCount }, (_, index) => ({
      id: `${id}-visit-${index}`, restaurantId: id, userId: 'owner', visitedAt: '', rating: 4.5, totalPrice: null,
      partySize: 1, pricePerPerson: null, myActualSpend: null, companions: [], queueDuration: null, servingDuration: null,
      diningMode: 'dine_in', paymentMode: null, diningOccasions: [], diningOccasion: null, diningOccasionText: '',
      valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], serviceTags: [], environmentTags: [],
      noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null,
      recommendationSourceType: null, recommendationSourceText: '', recommendationSourceUserId: null, note: '', specialNotes: '',
      sharedMealId: null, companionIds: [], photos: [], photoIds: [], dishes: [], visibility: 'private', createdAt: '', updatedAt: '', deletedAt: null,
    })), visitCount, averageRating: null, scoreOutOfTen: null, latestVisitDate: null, latestVisit: null,
    averagePricePerPerson: null, averageQueueMinutes: null,
    ...overrides,
  }
}
