import type { RestaurantSummary } from '../types/domain'
import { predictLiking } from '../contracts/predictedLiking'

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
    && typeof restaurant.scoreOutOfTen === 'number'
    && Number.isFinite(restaurant.scoreOutOfTen)
    && restaurantKey(restaurant) !== targetKey
  ))
  if (!ratedHistory.length) {
    return { score: null, ratedRestaurantCount: 0, ratedVisitCount: 0, matchedRestaurantCount: 0, description: '记录更多评分后生成' }
  }

  const evidence = (restaurant: RestaurantSummary) => ({ id: restaurantKey(restaurant), tags: restaurant.tags, city: restaurant.city,
    price: finiteNumber(restaurant.averagePricePerPerson) ?? finiteNumber(restaurant.pricePerPerson), scoreOutOfTen: restaurant.scoreOutOfTen,
    visitCount: finiteNumber(restaurant.visitCount) ?? restaurant.visits.length,
    ratedVisitCount: restaurant.visits.filter(visit => !visit.deletedAt && visit.rating !== null).length })
  const prediction = predictLiking(evidence(target), ratedHistory.map(evidence))
  const { ratedVisitCount, matchedRestaurantCount } = prediction
  const description = matchedRestaurantCount
    ? `基于 ${ratedVisitCount} 条历史评分与 ${matchedRestaurantCount} 家相近餐厅推算`
    : `基于 ${ratedVisitCount} 条历史评分习惯推算`

  return {
    score: prediction.scoreOutOfTen,
    ratedRestaurantCount: prediction.ratedRestaurantCount,
    ratedVisitCount,
    matchedRestaurantCount,
    description,
  }
}

function restaurantKey(restaurant: RestaurantSummary) {
  return restaurant.amapPoiId || restaurant.id
}

function finiteNumber(value: number | null | undefined) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}
