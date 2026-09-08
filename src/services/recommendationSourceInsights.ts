import { RECOMMENDATION_SOURCE_OPTIONS, type RecommendationSourceType, type RestaurantSummary, type Visit } from '../types/domain'
import { resolveVisitActualSpend } from './visitSpend'
import { sourcePitfall, sourcePositiveRank, SOURCE_QUALITY_MINIMUM, compareSourcePitfalls } from './sourceQualityPolicy'

export type SourceInsightConfidence = 'INSUFFICIENT' | 'EMERGING' | 'LOW' | 'STABLE'
export type RecommendationSourceTimeRange =
  | { type: 'ALL_TIME' }
  | { type: 'THIS_YEAR'; year?: number }
  | { type: 'THIS_MONTH'; year?: number; month?: number }
  | { type: 'CUSTOM'; from: string; to: string }

export interface WorstSourceConfig { minRatedRestaurants: number; stableSample: number }
export const DEFAULT_WORST_SOURCE_CONFIG: WorstSourceConfig = { minRatedRestaurants: SOURCE_QUALITY_MINIMUM, stableSample: 10 }

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
  personalBaselineRating: number | null
  ratingDeltaFromBaseline: number | null
  highRatingHitRate: number | null
  lowRatingRate: number | null
  repeatRestaurantCount: number
  repeatRestaurantRate: number | null
  latestVisitedAt: string | null
  recentAverageRating: number | null
  recentRatedRestaurantCount: number
  spend: { average: number | null; sampleCount: number }
  cuisines: Array<{ label: string; restaurantCount: number; averageRating: number | null }>
  restaurants: Array<{ restaurantId: string; name: string; visitCount: number; averageRating: number | null; latestVisitedAt: string | null }>
}

export interface WorstRecommendationSourceResult {
  insight: RecommendationSourceInsight
  score: number
  confidence: 'LOW' | 'STABLE'
}

interface BuildRecommendationSourceOptions { timeRange?: RecommendationSourceTimeRange; now?: Date }

export function sourceInsightConfidence(visitedRestaurantCount: number): SourceInsightConfidence {
  if (visitedRestaurantCount < 3) return 'INSUFFICIENT'
  if (visitedRestaurantCount < SOURCE_QUALITY_MINIMUM) return 'EMERGING'
  if (visitedRestaurantCount < 10) return 'LOW'
  return 'STABLE'
}

export function buildRecommendationSourceInsights(
  restaurants: RestaurantSummary[],
  visits: Visit[],
  sourceUserNames: ReadonlyMap<string, string> = new Map(),
  options: BuildRecommendationSourceOptions = {},
): RecommendationSourceInsight[] {
  const history = visits.filter(visit => !visit.deletedAt && Number.isFinite(Date.parse(visit.visitedAt)) && Date.parse(visit.visitedAt) <= (options.now ?? new Date()).getTime() && restaurants.some(restaurant => restaurant.id === visit.restaurantId && !restaurant.deletedAt))
    .sort((a, b) => Date.parse(a.visitedAt) - Date.parse(b.visitedAt) || a.id.localeCompare(b.id))
  const validVisits = filterVisitsByTimeRange(history, options.timeRange, options.now)
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const byRestaurant = groupBy(validVisits, (visit) => visit.restaurantId)
  const personalBaselineRating = averageOrNull([...groupBy(history, visit => visit.restaurantId).values()].flatMap((entries) => {
    const rating = firstRating(entries)
    return rating === null ? [] : [rating]
  }))
  const sourceGroups = new Map<string, { type: RecommendationSourceType; linkedUserId: string | null; label: string; restaurantVisits: Map<string, Visit[]> }>()

  byRestaurant.forEach((entries, restaurantId) => {
    const all = history.filter(visit => visit.restaurantId === restaurantId)
    if (new Set(all.filter(visit => visit.recommendationSourceType).map(sourceKey)).size > 1) return
    const acquisition = all.find((visit) => visit.recommendationSourceType)
    if (!acquisition?.recommendationSourceType) return
    if (!entries.some(visit => visit.id === acquisition.id)) return
    const key = sourceKey(acquisition)
    const group = sourceGroups.get(key) ?? {
      type: acquisition.recommendationSourceType,
      linkedUserId: acquisition.recommendationSourceUserId,
      label: sourceLabel(acquisition, sourceUserNames),
      restaurantVisits: new Map(),
    }
    group.label = sourceLabel(acquisition, sourceUserNames)
    group.restaurantVisits.set(restaurantId, entries.filter(visit => Date.parse(visit.visitedAt) >= Date.parse(acquisition.visitedAt)))
    sourceGroups.set(key, group)
  })

  return [...sourceGroups].map(([id, source]) => {
    const evidence = [...source.restaurantVisits].map(([restaurantId, entries]) => {
      const rating = firstRating(entries)
      const spends = entries.flatMap((visit) => {
        const spend = resolveVisitActualSpend(visit)
        return spend === null ? [] : [spend]
      })
      const restaurant = restaurantById.get(restaurantId)
      const latestVisitedAt = entries.reduce<string | null>((latest, visit) => !latest || visit.visitedAt > latest ? visit.visitedAt : latest, null)
      return {
        restaurantId,
        name: restaurant?.name ?? '已删除餐厅',
        visits: entries.length,
        rating,
        spend: averageOrNull(spends),
        cuisines: restaurant?.tags.slice(0, 2).filter(Boolean) ?? [],
        latestVisitedAt,
      }
    })
    const rated = evidence.filter((item) => item.rating !== null)
    const spendValues = evidence.flatMap((item) => item.spend === null ? [] : [item.spend])
    const cuisineGroups = new Map<string, typeof evidence>()
    evidence.forEach((item) => (item.cuisines.length ? item.cuisines : ['未分类']).forEach((label) => cuisineGroups.set(label, [...(cuisineGroups.get(label) ?? []), item])))
    const latestRated = [...rated].sort((a, b) => (b.latestVisitedAt ?? '').localeCompare(a.latestVisitedAt ?? '')).slice(0, 3)
    const averagePostVisitRating = averageOrNull(rated.map((item) => item.rating!))
    return {
      id,
      label: source.label,
      type: source.type,
      linkedUserId: source.linkedUserId,
      confidence: sourceInsightConfidence(evidence.length),
      restaurantCount: evidence.length,
      visitedRestaurantCount: evidence.length,
      ratedRestaurantCount: rated.length,
      averagePostVisitRating,
      personalBaselineRating,
      ratingDeltaFromBaseline: averagePostVisitRating === null || personalBaselineRating === null ? null : round1(averagePostVisitRating - personalBaselineRating),
      highRatingHitRate: rated.length ? rated.filter((item) => item.rating! >= 8).length / rated.length : null,
      lowRatingRate: rated.length ? rated.filter((item) => sourcePitfall(item.rating, personalBaselineRating)).length / rated.length : null,
      repeatRestaurantCount: evidence.filter((item) => item.visits >= 2).length,
      repeatRestaurantRate: evidence.length ? evidence.filter((item) => item.visits >= 2).length / evidence.length : null,
      latestVisitedAt: evidence.reduce<string | null>((latest, item) => !latest || (item.latestVisitedAt ?? '') > latest ? item.latestVisitedAt : latest, null),
      recentAverageRating: averageOrNull(latestRated.map((item) => item.rating!)),
      recentRatedRestaurantCount: latestRated.length,
      spend: { average: averageOrNull(spendValues), sampleCount: spendValues.length },
      cuisines: [...cuisineGroups]
        .map(([label, items]) => ({ label, restaurantCount: items.length, averageRating: averageOrNull(items.flatMap((item) => item.rating === null ? [] : [item.rating])) }))
        .sort((a, b) => b.restaurantCount - a.restaurantCount || (b.averageRating ?? 0) - (a.averageRating ?? 0))
        .slice(0, 6),
      restaurants: evidence
        .map((item) => ({ restaurantId: item.restaurantId, name: item.name, visitCount: item.visits, averageRating: item.rating, latestVisitedAt: item.latestVisitedAt }))
        .sort((a, b) => (b.averageRating ?? -1) - (a.averageRating ?? -1) || b.visitCount - a.visitCount),
    }
  }).sort((a, b) => b.visitedRestaurantCount - a.visitedRestaurantCount || (b.averagePostVisitRating ?? 0) - (a.averagePostVisitRating ?? 0))
}

export function selectWorstRecommendationSource(
  insights: RecommendationSourceInsight[],
  config: WorstSourceConfig = DEFAULT_WORST_SOURCE_CONFIG,
): WorstRecommendationSourceResult | null {
  const candidates = insights.filter((insight) => insight.type !== 'self' && insight.ratedRestaurantCount >= config.minRatedRestaurants && (insight.lowRatingRate ?? 0) > 0)
  if (!candidates.length) return null
  return candidates.map((insight) => ({
    insight,
    score: insight.lowRatingRate!,
    confidence: insight.ratedRestaurantCount >= config.stableSample ? 'STABLE' as const : 'LOW' as const,
  })).sort((a, b) => compareSourcePitfalls({ id: a.insight.id, pitfallRate: a.score, firstAverage: a.insight.averagePostVisitRating! }, { id: b.insight.id, pitfallRate: b.score, firstAverage: b.insight.averagePostVisitRating! }))[0]
}

export function sourceQualityRank(insight: RecommendationSourceInsight, all: RecommendationSourceInsight[]) {
  if (insight.type === 'self' || insight.ratedRestaurantCount < SOURCE_QUALITY_MINIMUM) return null
  const total = all.reduce((sum, item) => sum + item.ratedRestaurantCount, 0)
  const high = all.reduce((sum, item) => sum + (item.highRatingHitRate ?? 0) * item.ratedRestaurantCount, 0)
  return sourcePositiveRank((insight.highRatingHitRate ?? 0) * insight.ratedRestaurantCount, insight.ratedRestaurantCount, total ? high / total : 0)
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

function filterVisitsByTimeRange(visits: Visit[], timeRange: RecommendationSourceTimeRange | undefined, now = new Date()) {
  if (!timeRange || timeRange.type === 'ALL_TIME') return visits
  const year = timeRange.type === 'CUSTOM' ? null : timeRange.year ?? now.getFullYear()
  const month = timeRange.type === 'THIS_MONTH' ? timeRange.month ?? now.getMonth() + 1 : null
  return visits.filter((visit) => {
    const date = new Date(visit.visitedAt)
    if (Number.isNaN(date.getTime())) return false
    if (timeRange.type === 'THIS_YEAR') return date.getUTCFullYear() === year
    if (timeRange.type === 'THIS_MONTH') return date.getUTCFullYear() === year && date.getUTCMonth() + 1 === month
    const timestamp = date.getTime()
    return timestamp >= new Date(timeRange.from).getTime() && timestamp <= new Date(timeRange.to).getTime()
  })
}

function firstRating(entries: Visit[]) { const value = entries[0]?.rating; return value != null && Number.isFinite(value) && value >= .5 && value <= 5 ? value * 2 : null }
function sourceKey(visit: Visit) {
  const identity = visit.recommendationSourceType === 'friend'
    ? visit.recommendationSourceUserId ?? (visit.recommendationSourceText.trim().toLocaleLowerCase('zh-CN') || 'unlinked')
    : visit.recommendationSourceType === 'other' || visit.recommendationSourceType === 'blogger'
      ? visit.recommendationSourceText.trim().toLocaleLowerCase('zh-CN') || 'unspecified'
      : 'aggregate'
  return `${visit.recommendationSourceType}:${identity}`
}
function sourceLabel(visit: Visit, sourceUserNames: ReadonlyMap<string, string>) {
  if (visit.recommendationSourceType === 'friend') {
    if (visit.recommendationSourceUserId) return sourceUserNames.get(visit.recommendationSourceUserId) ?? (visit.recommendationSourceText.trim() || '好友推荐')
    if (visit.recommendationSourceText.trim()) return visit.recommendationSourceText.trim()
  }
  if ((visit.recommendationSourceType === 'other' || visit.recommendationSourceType === 'blogger') && visit.recommendationSourceText.trim()) return visit.recommendationSourceText.trim()
  return RECOMMENDATION_SOURCE_OPTIONS.find((item) => item.value === visit.recommendationSourceType)?.label ?? '其他来源'
}
function groupBy<T, K>(values: T[], key: (value: T) => K) { const result = new Map<K, T[]>(); values.forEach((value) => result.set(key(value), [...(result.get(key(value)) ?? []), value])); return result }
function averageOrNull(values: number[]) { return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null }
function round1(value: number) { return Math.round(value * 10) / 10 }
