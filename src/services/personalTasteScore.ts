import type { RestaurantSummary } from '../types/domain'

export interface PersonalTastePrediction {
  score: number | null
  ratedRestaurantCount: number
  ratedVisitCount: number
  matchedRestaurantCount: number
  description: string
}

export function predictPersonalTasteScore(target: RestaurantSummary, history: RestaurantSummary[]): PersonalTastePrediction {
  const targetKey = restaurantKey(target)
  const ratedHistory = history.filter((restaurant) => (
    !restaurant.deletedAt
    && restaurant.scoreOutOfTen !== null
    && restaurantKey(restaurant) !== targetKey
  ))
  if (!ratedHistory.length) {
    return { score: null, ratedRestaurantCount: 0, ratedVisitCount: 0, matchedRestaurantCount: 0, description: '记录更多评分后生成' }
  }

  const targetTags = normalizedTags(target.tags)
  const targetPrice = target.averagePricePerPerson ?? target.pricePerPerson
  const weighted = ratedHistory.map((restaurant) => {
    const tagSimilarity = jaccard(targetTags, normalizedTags(restaurant.tags))
    const historyPrice = restaurant.averagePricePerPerson ?? restaurant.pricePerPerson
    const priceSimilarity = targetPrice !== null && historyPrice !== null
      ? Math.max(0, 1 - Math.abs(targetPrice - historyPrice) / Math.max(160, targetPrice, historyPrice))
      : 0
    const sameCity = Boolean(target.city && target.city === restaurant.city)
    const isMatch = tagSimilarity > 0 || priceSimilarity >= 0.65 || sameCity
    const weight = 0.35 + tagSimilarity * 1.2 + priceSimilarity * 0.3 + (sameCity ? 0.15 : 0) + Math.min(restaurant.visitCount, 4) * 0.04
    const ratedVisits = restaurant.visits.filter((visit) => !visit.deletedAt && visit.rating !== null).length
    return { score: restaurant.scoreOutOfTen as number, weight, isMatch, ratedVisits }
  })
  const strongest = weighted.filter((item) => item.isMatch)
  const samples = strongest.length ? strongest : weighted
  const ratedVisitCount = samples.reduce((sum, item) => sum + item.ratedVisits, 0)
  const weightTotal = samples.reduce((sum, item) => sum + item.weight, 0)
  const score = samples.reduce((sum, item) => sum + item.score * item.weight, 0) / weightTotal
  const matchedRestaurantCount = strongest.length
  const description = matchedRestaurantCount
    ? `基于 ${ratedVisitCount} 条历史评分与 ${matchedRestaurantCount} 家相近餐厅推算`
    : `基于 ${ratedVisitCount} 条历史评分习惯推算`

  return {
    score: round1(Math.min(10, Math.max(1, score))),
    ratedRestaurantCount: samples.length,
    ratedVisitCount,
    matchedRestaurantCount,
    description,
  }
}

function restaurantKey(restaurant: RestaurantSummary) {
  return restaurant.amapPoiId || restaurant.id
}

function normalizedTags(tags: string[]) {
  return new Set(tags.map((tag) => tag.trim().toLocaleLowerCase('zh-CN')).filter(Boolean))
}

function jaccard(left: Set<string>, right: Set<string>) {
  if (!left.size || !right.size) return 0
  const intersection = [...left].filter((tag) => right.has(tag)).length
  return intersection / new Set([...left, ...right]).size
}

function round1(value: number) {
  return Math.round(value * 10) / 10
}
