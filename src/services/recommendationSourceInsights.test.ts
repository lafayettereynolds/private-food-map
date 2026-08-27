import { describe, expect, it } from 'vitest'
import { buildRecommendationSourceInsights, selectWorstRecommendationSource, sourceInsightConfidence } from './recommendationSourceInsights'
import type { RecommendationSourceType, RestaurantSummary, Visit } from '../types/domain'

const restaurants = Array.from({ length: 24 }, (_, index) => ({ id: `r${index + 1}`, name: `餐厅 ${index + 1}`, tags: [index % 2 ? '日料' : '咖啡'] })) as RestaurantSummary[]

function visit(id: string, restaurantId: string, rating: Visit['rating'], options: { type?: RecommendationSourceType; text?: string; userId?: string | null; date?: string } = {}): Visit {
  return {
    id,
    userId: 'owner',
    restaurantId,
    visitedAt: options.date ?? `2026-08-${String((Number(id.replace(/\D/g, '')) % 27) + 1).padStart(2, '0')}T12:00:00.000Z`,
    rating,
    visibility: 'private',
    diningMode: 'dine_in',
    totalPrice: null,
    myActualSpend: 100,
    paymentMode: null,
    pricePerPerson: null,
    partySize: 1,
    queueDuration: null,
    diningOccasions: [],
    diningOccasion: null,
    diningOccasionText: '',
    valueRating: null,
    environmentRating: null,
    serviceRating: null,
    valueTags: [],
    environmentTags: [],
    serviceTags: [],
    noiseLevel: null,
    diningDuration: null,
    portionLevel: null,
    transportConvenience: null,
    specialNotes: '',
    recommendationSourceType: options.type ?? 'xiaohongshu',
    recommendationSourceUserId: options.userId ?? null,
    recommendationSourceText: options.text ?? '',
    sharedMealId: null,
    companions: [],
    companionIds: [],
    dishes: [],
    note: '',
    photos: [],
    photoIds: [],
    createdAt: '',
    updatedAt: '',
    deletedAt: null,
  }
}

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
    const result = buildRecommendationSourceInsights(restaurants, [
      visit('1', 'r1', 4, { text: '博主甲' }),
      visit('2', 'r2', 4.5, { text: '博主乙' }),
    ])
    expect(result).toHaveLength(1)
    expect(result[0].label).toBe('小红书')
    expect(result[0].visitedRestaurantCount).toBe(2)
  })

  it('selects the worst qualified source and excludes a worse tiny sample', () => {
    const visits = [
      ...Array.from({ length: 8 }, (_, index) => visit(`w${index}`, `r${index + 1}`, 2.5, { type: 'friend', userId: 'u-wang', text: '小王' })),
      ...Array.from({ length: 2 }, (_, index) => visit(`l${index}`, `r${index + 9}`, 1, { type: 'friend', userId: 'u-li', text: '小李' })),
      ...Array.from({ length: 8 }, (_, index) => visit(`x${index}`, `r${index + 11}`, 4.5, { type: 'xiaohongshu' })),
    ]
    const insights = buildRecommendationSourceInsights(restaurants, visits, new Map([['u-wang', '小王'], ['u-li', '小李']]))
    const worst = selectWorstRecommendationSource(insights)
    expect(worst?.insight.label).toBe('小王')
    expect(insights.find((item) => item.label === '小李')?.ratedRestaurantCount).toBe(2)
  })

  it('allows a platform source to be the worst source', () => {
    const insights = buildRecommendationSourceInsights(restaurants, Array.from({ length: 6 }, (_, index) => visit(`p${index}`, `r${index + 1}`, 2, { type: 'xiaohongshu' })))
    expect(selectWorstRecommendationSource(insights)?.insight.label).toBe('小红书')
  })

  it('uses the latest linked user name without anonymizing it', () => {
    const visits = Array.from({ length: 6 }, (_, index) => visit(`n${index}`, `r${index + 1}`, 2, { type: 'friend', userId: 'u-source', text: '旧名字' }))
    const first = buildRecommendationSourceInsights(restaurants, visits, new Map([['u-source', '小王']]))
    const renamed = buildRecommendationSourceInsights(restaurants, visits, new Map([['u-source', '王同学']]))
    expect(selectWorstRecommendationSource(first)?.insight.label).toBe('小王')
    expect(selectWorstRecommendationSource(renamed)?.insight.label).toBe('王同学')
  })

  it('returns no worst result when every source is below the minimum sample', () => {
    const insights = buildRecommendationSourceInsights(restaurants, Array.from({ length: 5 }, (_, index) => visit(`e${index}`, `r${index + 1}`, 1)))
    expect(selectWorstRecommendationSource(insights)).toBeNull()
  })

  it('uses only visits inside the selected year', () => {
    const visits = [
      ...Array.from({ length: 6 }, (_, index) => visit(`y${index}`, `r${index + 1}`, 2, { date: `2026-0${(index % 6) + 1}-02T12:00:00.000Z` })),
      ...Array.from({ length: 6 }, (_, index) => visit(`o${index}`, `r${index + 7}`, 5, { date: `2025-0${(index % 6) + 1}-02T12:00:00.000Z` })),
    ]
    const insight = buildRecommendationSourceInsights(restaurants, visits, new Map(), { timeRange: { type: 'THIS_YEAR', year: 2026 } })[0]
    expect(insight.ratedRestaurantCount).toBe(6)
    expect(insight.averagePostVisitRating).toBe(4)
  })

  it('counts five visits to one restaurant as one sample and a repeat signal', () => {
    const visits = Array.from({ length: 5 }, (_, index) => visit(`rpt${index}`, 'r1', 2.5))
    const insight = buildRecommendationSourceInsights(restaurants, visits)[0]
    expect(insight.ratedRestaurantCount).toBe(1)
    expect(insight.repeatRestaurantCount).toBe(1)
    expect(selectWorstRecommendationSource([insight])).toBeNull()
  })
})
