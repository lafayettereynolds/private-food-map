import { describe, expect, it } from 'vitest'
import type { RestaurantSummary, Visit } from '../types/domain'
import { reviewService } from './reviewService'

const restaurants = [
  restaurant('r1', '山海小馆', '杭州', ['日料'], 'merchant-r1'),
  restaurant('r2', '湖畔餐厅', '上海', ['火锅'], 'merchant-r2'),
  restaurant('r3', '旧城咖啡', '北京', ['咖啡'], null),
]

describe('review service', () => {
  it('uses month boundaries and excludes deleted visits', () => {
    const review = reviewService.monthly(restaurants, [visit('a', 'r1', '2026-08-01', 4), visit('b', 'r2', '2026-08-31', 5), visit('c', 'r3', '2026-09-01', 5), { ...visit('d', 'r3', '2026-08-12', 5), deletedAt: '2026-08-13' }], 2026, 8)
    expect(review.visitCount).toBe(2)
    expect(review.restaurantCount).toBe(2)
  })

  it('builds an annual review independently from the monthly review', () => {
    const visits = [visit('a', 'r1', '2026-01-12', 4), visit('b', 'r2', '2026-08-12', 5)]
    expect(reviewService.annual(restaurants, visits, 2026).visitCount).toBe(2)
    expect(reviewService.monthly(restaurants, visits, 2026, 8).visitCount).toBe(1)
  })

  it('separates first-time restaurants from revisits', () => {
    const visits = [visit('old', 'r1', '2026-07-12', 4), visit('a', 'r1', '2026-08-12', 4), visit('b', 'r1', '2026-08-20', 5), visit('c', 'r2', '2026-08-21', 4)]
    const review = reviewService.monthly(restaurants, visits, 2026, 8)
    expect(review.newRestaurantCount).toBe(1)
    expect(review.revisitCount).toBe(1)
  })

  it('hides money when fewer than 60 percent of visits have actual spend', () => {
    const review = reviewService.monthly(restaurants, [visit('a', 'r1', '2026-08-12', 4, 100), visit('b', 'r2', '2026-08-13', 4), visit('c', 'r3', '2026-08-14', 4)], 2026, 8)
    expect(review.spendCoverage).toBeCloseTo(1 / 3)
    expect(review.spendDisplay).toBe('hidden')
  })

  it('labels partially covered money as recorded rather than total', () => {
    const review = reviewService.monthly(restaurants, [visit('a', 'r1', '2026-08-12', 4, 100), visit('b', 'r2', '2026-08-13', 4, 80), visit('c', 'r3', '2026-08-14', 4)], 2026, 8)
    expect(review.spendDisplay).toBe('recorded')
    expect(review.actualSpend).toBe(180)
  })

  it('uses total only at complete spend coverage', () => {
    const review = reviewService.monthly(restaurants, [visit('a', 'r1', '2026-08-12', 4, 100), visit('b', 'r2', '2026-08-13', 4, 80)], 2026, 8)
    expect(review.spendCoverage).toBe(1)
    expect(review.spendDisplay).toBe('total')
  })

  it('never substitutes an ambiguous table total for my actual spend', () => {
    const input = { ...visit('a', 'r1', '2026-08-12', 4), totalPrice: 999, paymentMode: 'other' as const }
    const review = reviewService.monthly(restaurants, [input], 2026, 8)
    expect(review.actualSpend).toBe(0)
    expect(review.visitsWithSpend).toBe(0)
  })

  it('recovers personal spend when the former one-price form payment mode is deterministic', () => {
    const input = { ...visit('a', 'r1', '2026-08-12', 4), totalPrice: 300, paymentMode: 'aa' as const, partySize: 2 }
    const review = reviewService.monthly(restaurants, [input], 2026, 8)
    expect(review.actualSpend).toBe(150)
    expect(review.visitsWithSpend).toBe(1)
  })

  it('prioritizes a visit photo over the restaurant and provider cover', () => {
    const input = { ...visit('a', 'r1', '2026-08-12', 4), photos: ['visit-photo'], photoIds: ['photo-1'] }
    expect(reviewService.monthly(restaurants, [input], 2026, 8).memories[0].photo).toEqual({ source: 'visit-photo', photoId: 'photo-1', origin: 'visit' })
  })

  it('falls back to the stable restaurant image and then provider image', () => {
    const withStable = { ...restaurants[0], markerImageData: 'stable-image', markerPhotoId: 'stable-id' }
    const stableReview = reviewService.monthly([withStable], [visit('a', 'r1', '2026-08-12', 4)], 2026, 8)
    expect(stableReview.memories[0].photo.origin).toBe('restaurant')
    expect(stableReview.memories[0].photo.source).toBe('stable-image')
    const providerReview = reviewService.monthly(restaurants, [visit('a', 'r1', '2026-08-12', 4)], 2026, 8)
    expect(providerReview.memories[0].photo.origin).toBe('provider')
  })

  it('prefers a richly documented high-rated visit as the highlight', () => {
    const plain = visit('a', 'r1', '2026-08-12', 4)
    const rich = { ...visit('b', 'r2', '2026-08-13', 5), note: '非常值得记住', photos: ['visit-photo'], photoIds: ['p2'], companions: ['小王'] }
    expect(reviewService.monthly(restaurants, [plain, rich], 2026, 8).highlightVisit?.visitId).toBe('b')
  })

  it('does not fabricate comparison or patterns from one visit', () => {
    const review = reviewService.monthly(restaurants, [visit('a', 'r1', '2026-08-12', 4)], 2026, 8)
    expect(review.comparison).toBeNull()
    expect(review.diningPatterns).toEqual([])
  })

  it('creates companion and recommendation-source insights only from real data', () => {
    const input = { ...visit('a', 'r1', '2026-08-12', 4), companions: ['小王'], recommendationSourceType: 'friend' as const }
    const populated = reviewService.monthly(restaurants, [input], 2026, 8)
    expect(populated.companionInsight?.name).toBe('小王')
    expect(populated.sourceInsight?.source.label).toBe('朋友推荐')
    const empty = reviewService.monthly(restaurants, [visit('b', 'r2', '2026-08-13', 4)], 2026, 8)
    expect(empty.companionInsight).toBeNull()
    expect(empty.sourceInsight).toBeNull()
  })

  it('builds annual key restaurants and a real city footprint', () => {
    const visits = [visit('a', 'r1', '2026-01-02', 3), visit('b', 'r2', '2026-03-02', 5), visit('c', 'r2', '2026-05-02', 4.5)]
    const review = reviewService.annual(restaurants, visits, 2026)
    expect(review.keyRestaurants.map((item) => item.kind)).toEqual(expect.arrayContaining(['first', 'highest']))
    expect(review.mapFootprint).toEqual(expect.arrayContaining([{ city: '杭州', count: 1 }, { city: '上海', count: 2 }]))
  })

  it('shows multiple years on the same calendar day and omits absent optional facts', () => {
    const visits = [visit('a', 'r1', '2024-08-26', null), visit('b', 'r2', '2025-08-26', 5)]
    const review = reviewService.onThisDay(restaurants, visits, new Date('2026-08-26T12:00:00'))
    expect(review.memories.map((memory) => memory.yearsAgo)).toEqual([1, 2])
    expect(review.memories.find((memory) => memory.visitId === 'a')?.scoreOutOfTen).toBeNull()
    expect(review.memories.find((memory) => memory.visitId === 'a')?.actualSpend).toBeNull()
  })

  it('keeps empty periods explicit instead of inventing highlights', () => {
    const review = reviewService.annual(restaurants, [], 2026)
    expect(review.visitCount).toBe(0)
    expect(review.highlightVisit).toBeNull()
    expect(review.heroPhotos).toEqual([])
    expect(review.summary).toContain('还没有')
  })
})

function restaurant(id: string, name: string, city: string, tags: string[], merchantImageUrl: string | null): RestaurantSummary {
  return {
    id, userId: 'owner', amapPoiId: id, name, address: `${city}测试地址`, city, latitude: 30, longitude: 120, status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags, longTermNote: '', pricePerPerson: null, phone: null, openingHours: null, markerType: 'image', markerImageData: null, markerPhotoId: null, merchantImageUrl, markerEmoji: '🍴', createdAt: '', updatedAt: '', deletedAt: null, visitCount: 0, averageRating: null, scoreOutOfTen: null, latestVisitDate: null, latestVisit: null, visits: [], averagePricePerPerson: null, averageQueueMinutes: null,
  }
}

function visit(id: string, restaurantId: string, date: string, rating: Visit['rating'], myActualSpend: number | null = null): Visit {
  const visitedAt = `${date}T12:00:00`
  return {
    id, userId: 'owner', restaurantId, visitedAt, rating, visibility: 'private', diningMode: 'dine_in', totalPrice: null, myActualSpend, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null, diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [], dishes: [], note: '', photos: [], photoIds: [], createdAt: visitedAt, updatedAt: visitedAt, deletedAt: null,
  }
}
