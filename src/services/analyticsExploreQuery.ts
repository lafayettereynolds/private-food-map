import type { RestaurantSummary, Visit } from '../types/domain'
import { restaurantCityComparisonKey } from './restaurantCity'
import { analyticsDiningContext, analyticsHasMealTime } from './analyticsDiningContext'
import { resolveVisitActualSpend, visitReferencePrice } from './visitSpend'
import { tasteDimensions } from './tasteProfileSnapshot'
import { spendCategory } from './analyticsTasteReport'

export interface AnalyticsExploreFilter { days?: 90 | 365; city?: string }
// Session-only reading preferences, never persisted personal records. A new
// owner replaces the previous owner's entry rather than reviving it later.
let readingFilter: { ownerID: string; value: AnalyticsExploreFilter } | null = null
export function getAnalyticsReadingFilter(ownerID: string) { return readingFilter?.ownerID === ownerID ? readingFilter.value : {} }
export function setAnalyticsReadingFilter(ownerID: string, value: AnalyticsExploreFilter) { readingFilter = { ownerID, value } }
export interface AnalyticsRecordCondition {
  label: string
  cuisine?: string
  restaurantIDs?: string[]
  visitIDs?: string[]
  city?: string
  time?: string
  weekday?: number
  price?: { minimum: number; maximum: number }
  score?: { minimum: number; maximum: number }
  coverage?: 'rated' | 'spend' | 'time' | 'companion' | 'source' | 'dishes'
  context?: 'solo' | 'together' | 'conflict'
  taste?: string
  spendCategory?: string
}
export function analyticsMealTime(visit: Visit) {
  if (!analyticsHasMealTime(visit)) return null
  const hour = new Date(visit.visitedAt).getHours()
  return hour >= 5 && hour < 10 ? '早餐' : hour >= 10 && hour < 14 ? '午餐' : hour >= 14 && hour < 17 ? '下午茶' : hour >= 17 && hour < 22 ? '晚餐' : '夜宵'
}
export function analyticsFilterVisits(restaurants: RestaurantSummary[], visits: Visit[], filter: AnalyticsExploreFilter, now: Date) {
  const byID = new Map(restaurants.map(item => [item.id, item]))
  const start = new Date(now); if (filter.days) start.setDate(start.getDate() - filter.days)
  return visits.filter(visit => (!filter.days || Date.parse(visit.visitedAt) >= start.getTime())
    && (!filter.city || restaurantCityComparisonKey(byID.get(visit.restaurantId)?.city ?? '') === restaurantCityComparisonKey(filter.city)))
}
/** Every active predicate must match the SAME Visit. No label parsing, inferred
 * midnight, unrelated-Visit joins or changes to the source records. */
export function analyticsQueryRecords(restaurants: RestaurantSummary[], visits: Visit[], condition: AnalyticsRecordCondition) {
  const byID = new Map(restaurants.map(item => [item.id, item]))
  return visits.filter(visit => {
    const restaurant = byID.get(visit.restaurantId)
    if (condition.visitIDs && !condition.visitIDs.includes(visit.id)) return false
    if (condition.restaurantIDs && !condition.restaurantIDs.includes(visit.restaurantId)) return false
    if (condition.cuisine && !restaurant?.tags.some(tag => tag.trim() === condition.cuisine)) return false
    if (condition.city && restaurantCityComparisonKey(restaurant?.city ?? '') !== restaurantCityComparisonKey(condition.city)) return false
    if (condition.time && analyticsMealTime(visit) !== condition.time) return false
    if (condition.weekday != null && new Date(visit.visitedAt).getDay() !== condition.weekday) return false
    if (condition.context && analyticsDiningContext(visit) !== condition.context) return false
    if (condition.taste && !visit.dishes.some(dish => tasteDimensions(dish.taste).includes(condition.taste!))) return false
    if (condition.spendCategory && (resolveVisitActualSpend(visit) == null || spendCategory(restaurant) !== condition.spendCategory)) return false
    if (condition.price) { const price = visitReferencePrice(visit); if (price == null || price < condition.price.minimum || price >= condition.price.maximum) return false }
    if (condition.score && (visit.rating == null || visit.rating * 2 < condition.score.minimum || visit.rating * 2 >= condition.score.maximum)) return false
    switch (condition.coverage) {
      case 'rated': return visit.rating != null
      case 'spend': return resolveVisitActualSpend(visit) != null
      case 'time': return analyticsHasMealTime(visit)
      case 'companion': return ['solo', 'together'].includes(analyticsDiningContext(visit))
      case 'source': return !!visit.recommendationSourceType
      case 'dishes': return visit.dishes.length > 0
      default: return true
    }
  })
}
