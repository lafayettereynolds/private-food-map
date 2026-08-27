import { describe, expect, it } from 'vitest'
import type { RestaurantSummary, Visit } from '../types/domain'
import type { RecommendationContext } from '../types/recommendation'
import { RecommendationService } from './recommendationService'

const service = new RecommendationService()
const context: RecommendationContext = { type: 'for_you', surface: 'discover', city: '杭州市', preferExploration: true }

describe('premium recommendation presentation contract', () => {
  it('keeps recommendation fit semantic instead of exposing the ranking score', () => {
    const result = service.recommend([restaurant('candidate', 8.8, ['日料'])], history(), context)[0]
    expect(['STRONG_MATCH', 'GOOD_MATCH', 'MODERATE_MATCH', 'EXPLORATION']).toContain(result.fitLevel)
    expect(result.primaryReasons.length).toBeGreaterThan(0)
    expect(result.primaryReasons.length).toBeLessThanOrEqual(3)
    expect(result.primaryReasons.every((reason) => !reason.text.includes(String(result.score)))).toBe(true)
    expect(result.primaryReasons.every((reason) => !['NEARBY_AND_OPEN', 'COLD_START', 'HIGH_RATING_TRAIT_MATCH'].includes(reason.code))).toBe(true)
  })

  it('does not let exploration bypass the minimum quality gate', () => {
    const results = service.recommend([
      restaurant('good', 8.6, ['日料']),
      restaurant('low', 4.8, ['新口味']),
    ], history(), context)
    expect(results.map((item) => item.restaurant.id)).toContain('good')
    expect(results.map((item) => item.restaurant.id)).not.toContain('low')
  })

  it('counts independent public users rather than public visits', () => {
    const candidate = restaurant('candidate', 8.8, ['日料'])
    const result = service.recommend([candidate], [
      ...history(),
      visit('public-a-1', 'candidate', 'a', 4),
      visit('public-a-2', 'candidate', 'a', 5),
      visit('public-b-1', 'candidate', 'b', 3.5),
    ], context)[0]
    expect(result.publicRating).toEqual({ value: 8, sampleCount: 2 })
  })
})

function restaurant(id: string, scoreOutOfTen: number, tags: string[]): RestaurantSummary {
  return {
    id, userId: 'owner', amapPoiId: id, name: id, address: '测试路 1 号', city: '杭州市', latitude: 30.25, longitude: 120.17,
    status: 'wantToGo', preferenceLevel: 'like', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
    valueRating: null, tags, longTermNote: '', pricePerPerson: 120, markerType: 'emoji', markerImageData: null, markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: '🍽️', createdAt: '2026-08-25T00:00:00.000Z', updatedAt: '2026-08-25T00:00:00.000Z', deletedAt: null,
    visitCount: 12, averageRating: scoreOutOfTen / 2, scoreOutOfTen, latestVisitDate: null, latestVisit: null, visits: [],
    averagePricePerPerson: 120, averageQueueMinutes: null,
  }
}

function history(): Visit[] {
  return [
    visit('history-1', 'history-a', 'owner', 5),
    visit('history-2', 'history-b', 'owner', 4.5),
    visit('history-3', 'history-c', 'owner', 5),
  ]
}

function visit(id: string, restaurantId: string, userId: string, rating: Visit['rating']): Visit {
  return {
    id, userId, restaurantId, visitedAt: '2026-08-25T12:00:00.000Z', rating, visibility: 'public', diningMode: 'dine_in',
    totalPrice: null, myActualSpend: null, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null,
    diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null,
    valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null,
    transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [], dishes: [], note: '', photos: [], photoIds: [],
    createdAt: '2026-08-25T12:00:00.000Z', updatedAt: '2026-08-25T12:00:00.000Z', deletedAt: null,
  }
}
