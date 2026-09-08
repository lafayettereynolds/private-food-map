import { describe, expect, it } from 'vitest'
import type { RestaurantSummary, Visit } from '../types/domain'
import { tasteDataProgress, tasteDataProgressForCount } from './tasteDataProgress'

describe('taste data progress', () => {
  it.each([
    [0, 5, 5, '再评分 5 家，开始形成你的口味判断'],
    [5, 5, 0, '开始形成你的口味判断'],
    [6, 10, 4, '再评分 4 家，推荐和分析会更准确'],
    [7, 10, 3, '再评分 3 家，推荐和分析会更准确'],
    [10, 10, 0, '推荐和分析正在变得更准确'],
    [11, 15, 4, '再评分 4 家，口味分析会更完整'],
    [13, 15, 2, '再评分 2 家，口味分析会更完整'],
    [15, 15, 0, '口味分析正在变得更完整'],
    [16, 20, 4, '再评分 4 家，口味判断会更稳定'],
    [18, 20, 2, '再评分 2 家，口味判断会更稳定'],
    [19, 20, 1, '再评分 1 家，口味判断会更稳定'],
    [20, 20, 0, '口味数据已较稳定'],
    [24, 20, 0, '口味数据已较稳定'],
  ] as const)('uses the correct stage at %i rated Restaurants', (count, target, remaining, message) => {
    const progress = tasteDataProgressForCount(count)
    expect(progress).toMatchObject({ displayCount: Math.min(count, 20), target, remaining, message })
    expect(progress.message).not.toContain('再评分 0 家')
  })

  it('counts distinct Restaurants with at least one valid rating instead of counting Visits', () => {
    const restaurants = [
      restaurant('A', [visit('a-1', 4.5), visit('a-2', 5)]),
      restaurant('a', [visit('a-duplicate', 3.5)]),
      restaurant('B', [visit('b-unrated', null)]),
      restaurant('C', [visit('c-deleted', 4, true)]),
      restaurant('D', [visit('d-invalid', 4.2 as Visit['rating'])]),
      restaurant('E', [visit('e-rated', 0.5)]),
      { ...restaurant('F', [visit('f-rated', 4)]), deletedAt: '2026-09-05T00:00:00.000Z' },
    ]

    expect(tasteDataProgress(restaurants)).toMatchObject({
      ratedRestaurantCount: 2,
      displayCount: 2,
      target: 5,
      remaining: 3,
    })
  })
})

function restaurant(id: string, visits: Visit[]): RestaurantSummary {
  return {
    id, userId: 'owner', amapPoiId: '', name: id, address: '', city: '', latitude: 30, longitude: 120,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null,
    serviceRating: null, valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, markerType: 'emoji',
    markerImageData: null, markerPhotoId: null, merchantImageUrl: null, markerEmoji: '', createdAt: '', updatedAt: '',
    deletedAt: null, visitCount: visits.length, averageRating: null, scoreOutOfTen: null, latestVisitDate: null,
    latestVisit: visits[0] ?? null, visits, averagePricePerPerson: null, averageQueueMinutes: null,
  }
}

function visit(id: string, rating: Visit['rating'], deleted = false): Visit {
  return {
    id, userId: 'owner', restaurantId: 'restaurant', visitedAt: '', rating, visibility: 'private', diningMode: 'dine_in',
    totalPrice: null, myActualSpend: null, paymentMode: null, pricePerPerson: null, partySize: null, queueDuration: null,
    diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null,
    serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null,
    portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null,
    recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [],
    dishes: [], note: '', photos: [], photoIds: [], createdAt: '', updatedAt: '', deletedAt: deleted ? 'deleted' : null,
  }
}
