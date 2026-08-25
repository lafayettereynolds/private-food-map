import { RECOMMENDATION_SOURCE_OPTIONS, type RecommendationSourceType, type RestaurantSummary, type Visit } from '../types/domain'

export type SourceInsightConfidence = 'INSUFFICIENT' | 'EMERGING' | 'LOW' | 'STABLE'

export interface RecommendationSourceInsight {
  id: string
  label: string
  type: RecommendationSourceType
  linkedUserId: string | null
  confidence: SourceInsightConfidence
  restaurantCount: number
  visitedRestaurantCount: number
  ratedRestaurantCount: number
  averagePostVisitRating: number | null
  highRatingHitRate: number | null
  lowRatingRate: number | null
  repeatRestaurantCount: number
  repeatRestaurantRate: number | null
  spend: { average: number | null; sampleCount: number }
  cuisines: Array<{ label: string; restaurantCount: number; averageRating: number | null }>
  restaurants: Array<{ restaurantId: string; name: string; visitCount: number; averageRating: number | null }>
}

export function sourceInsightConfidence(visitedRestaurantCount: number): SourceInsightConfidence {
  if (visitedRestaurantCount < 3) return 'INSUFFICIENT'
  if (visitedRestaurantCount < 6) return 'EMERGING'
  if (visitedRestaurantCount < 10) return 'LOW'
  return 'STABLE'
}

export function buildRecommendationSourceInsights(restaurants: RestaurantSummary[], visits: Visit[], sourceUserNames: ReadonlyMap<string, string> = new Map()): RecommendationSourceInsight[] {
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const byRestaurant = groupBy(visits.filter((visit) => !visit.deletedAt), (visit) => visit.restaurantId)
  const sourceGroups = new Map<string, { type: RecommendationSourceType; linkedUserId: string | null; label: string; restaurantVisits: Map<string, Visit[]> }>()
  byRestaurant.forEach((entries, restaurantId) => {
    const acquisition = [...entries].sort((a, b) => a.visitedAt.localeCompare(b.visitedAt)).find((visit) => visit.recommendationSourceType)
    if (!acquisition?.recommendationSourceType) return
    const key = sourceKey(acquisition)
    const group = sourceGroups.get(key) ?? { type: acquisition.recommendationSourceType, linkedUserId: acquisition.recommendationSourceUserId, label: sourceLabel(acquisition, sourceUserNames), restaurantVisits: new Map() }
    group.restaurantVisits.set(restaurantId, entries)
    sourceGroups.set(key, group)
  })
  return [...sourceGroups].map(([id, source]) => {
    const evidence = [...source.restaurantVisits].map(([restaurantId, entries]) => {
      const ratings = entries.flatMap((visit) => visit.rating === null ? [] : [visit.rating * 2])
      const spends = entries.flatMap((visit) => visit.myActualSpend === null ? [] : [visit.myActualSpend])
      const restaurant = restaurantById.get(restaurantId)
      return { restaurantId, name: restaurant?.name ?? '已删除餐厅', visits: entries.length, rating: averageOrNull(ratings), spend: averageOrNull(spends), cuisines: restaurant?.tags.slice(0, 2).filter(Boolean) ?? [] }
    })
    const rated = evidence.filter((item) => item.rating !== null)
    const spendValues = evidence.flatMap((item) => item.spend === null ? [] : [item.spend])
    const cuisineGroups = new Map<string, typeof evidence>()
    evidence.forEach((item) => (item.cuisines.length ? item.cuisines : ['未分类']).forEach((label) => cuisineGroups.set(label, [...(cuisineGroups.get(label) ?? []), item])))
    return {
      id,
      label: source.label,
      type: source.type,
      linkedUserId: source.linkedUserId,
      confidence: sourceInsightConfidence(evidence.length),
      restaurantCount: evidence.length,
      visitedRestaurantCount: evidence.length,
      ratedRestaurantCount: rated.length,
      averagePostVisitRating: averageOrNull(rated.map((item) => item.rating!)),
      highRatingHitRate: rated.length ? rated.filter((item) => item.rating! >= 8).length / rated.length : null,
      lowRatingRate: rated.length ? rated.filter((item) => item.rating! <= 5).length / rated.length : null,
      repeatRestaurantCount: evidence.filter((item) => item.visits >= 2).length,
      repeatRestaurantRate: evidence.length ? evidence.filter((item) => item.visits >= 2).length / evidence.length : null,
      spend: { average: averageOrNull(spendValues), sampleCount: spendValues.length },
      cuisines: [...cuisineGroups].map(([label, items]) => ({ label, restaurantCount: items.length, averageRating: averageOrNull(items.flatMap((item) => item.rating === null ? [] : [item.rating])) })).sort((a, b) => b.restaurantCount - a.restaurantCount || (b.averageRating ?? 0) - (a.averageRating ?? 0)).slice(0, 6),
      restaurants: evidence.map((item) => ({ restaurantId: item.restaurantId, name: item.name, visitCount: item.visits, averageRating: item.rating })).sort((a, b) => (b.averageRating ?? -1) - (a.averageRating ?? -1) || b.visitCount - a.visitCount),
    }
  }).sort((a, b) => b.visitedRestaurantCount - a.visitedRestaurantCount || (b.averagePostVisitRating ?? 0) - (a.averagePostVisitRating ?? 0))
}

export function sourceAffinitySignal(insight: RecommendationSourceInsight, cuisine?: string) {
  if (insight.confidence === 'INSUFFICIENT') return { value: 0, confidence: insight.confidence }
  const cuisineEvidence = cuisine ? insight.cuisines.find((item) => item.label === cuisine) : null
  const rating = cuisineEvidence?.averageRating ?? insight.averagePostVisitRating ?? 7.4
  const sample = cuisineEvidence?.restaurantCount ?? insight.visitedRestaurantCount
  const adjusted = (rating * sample + 7.4 * 5) / (sample + 5)
  const outcome = (insight.highRatingHitRate ?? .5) * .35 + (insight.repeatRestaurantRate ?? 0) * .25 + adjusted / 10 * .4
  return { value: Math.round(outcome * 100) / 100, confidence: insight.confidence }
}

function sourceKey(visit: Visit) {
  const identity = visit.recommendationSourceType === 'friend'
    ? visit.recommendationSourceUserId ?? 'unlinked'
    : visit.recommendationSourceType === 'other' || visit.recommendationSourceType === 'blogger'
      ? visit.recommendationSourceText.trim().toLocaleLowerCase('zh-CN') || 'unspecified'
      : 'aggregate'
  return `${visit.recommendationSourceType}:${identity}`
}
function sourceLabel(visit: Visit, sourceUserNames: ReadonlyMap<string, string>) {
  if (visit.recommendationSourceType === 'friend' && visit.recommendationSourceUserId) return sourceUserNames.get(visit.recommendationSourceUserId) ?? '好友推荐'
  if ((visit.recommendationSourceType === 'other' || visit.recommendationSourceType === 'blogger') && visit.recommendationSourceText.trim()) return visit.recommendationSourceText.trim()
  return RECOMMENDATION_SOURCE_OPTIONS.find((item) => item.value === visit.recommendationSourceType)?.label ?? '其他来源'
}
function groupBy<T, K>(values: T[], key: (value: T) => K) { const result = new Map<K, T[]>(); values.forEach((value) => result.set(key(value), [...(result.get(key(value)) ?? []), value])); return result }
function averageOrNull(values: number[]) { return values.length ? Math.round(values.reduce((sum, value) => sum + value, 0) / values.length * 10) / 10 : null }
