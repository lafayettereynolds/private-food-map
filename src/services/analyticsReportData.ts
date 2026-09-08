import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { RestaurantSummary, Visit } from '../types/domain'
import type { AnalyticsDataset, AnalyticsRestaurantEvidence, AnalyticsReportSummary, AnalyticsSpend } from './analyticsReportTypes'
import { restaurantCityComparisonKey, restaurantCityFilterOptions } from './restaurantCity'
import { resolveVisitActualSpend, summarizeVisitSpend } from './visitSpend'

/** Owner/date/tombstone filtering happens once, before any report or period query. */
export function analyticsDataset(profile: TasteMapProfileDashboardViewModel, now = new Date()): AnalyticsDataset {
  const ownerID = profile.user.id
  const identity = profile.analyticsIdentity
  const recordOwnerID = identity?.ownerUserID === ownerID ? identity.recordOwnerID : ownerID
  const restaurantRecords = latestAnalyticsRecords(profile.restaurants.filter((item) => item.userId === recordOwnerID))
  const visitRecords = latestAnalyticsRecords(profile.visits.filter((item) => item.userId === recordOwnerID))
  const knownRestaurantIDs = new Set(restaurantRecords.map(item => item.id))
  const restaurants = restaurantRecords
    .filter((item) => !item.deletedAt).map((item) => ({ ...item, userId: ownerID }))
  const restaurantIDs = new Set(restaurants.map((item) => item.id))
  const visits = visitRecords
    .filter((visit) => !visit.deletedAt && restaurantIDs.has(visit.restaurantId) && Number.isFinite(Date.parse(visit.visitedAt)) && Date.parse(visit.visitedAt) <= now.getTime())
    .map((visit) => ({ ...visit, userId: ownerID, rating: validRating(visit.rating), valueRating: validRating(visit.valueRating), environmentRating: validRating(visit.environmentRating), serviceRating: validRating(visit.serviceRating), dishes: visit.dishes.map(dish => ({ ...dish, rating: validRating(dish.rating) })) }))
    .sort((a, b) => Date.parse(a.visitedAt) - Date.parse(b.visitedAt) || a.id.localeCompare(b.id))
  // Known tombstones/future dates are intentional exclusions, not a broken load.
  // Missing ownership proof, invalid dates and genuinely orphaned active rows
  // remain unavailable rather than masquerading as a new empty account.
  const unavailableVisitCount = visitRecords.length === 0 ? profile.visits.length : visitRecords.filter(visit => !visit.deletedAt
    && (!Number.isFinite(Date.parse(visit.visitedAt)) || !knownRestaurantIDs.has(visit.restaurantId))).length
  return { ownerID, restaurants, visits, excludedVisitCount: profile.visits.length - visits.length, unavailableVisitCount }
}

function validRating(value: Visit['rating']): Visit['rating'] {
  return value != null && Number.isFinite(value) && value >= 0.5 && value <= 5 ? value : null
}

export function latestAnalyticsRecords<T extends { id: string; updatedAt: string; deletedAt: string | null }>(records: readonly T[]): T[] {
  const latest = new Map<string, T>()
  for (const record of records) {
    const prior = latest.get(record.id)
    const timestamp = (value: string) => Number.isFinite(Date.parse(value)) ? Date.parse(value) : -Infinity
    const difference = prior ? timestamp(record.updatedAt) - timestamp(prior.updatedAt) : 0
    if (!prior || difference > 0 || (!(difference < 0) && !(difference > 0) && record.deletedAt && !prior.deletedAt)) latest.set(record.id, record)
  }
  return [...latest.values()]
}

export function analyticsAverage(values: number[]): number | null {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null
}
export function analyticsPercentile(input: number[], fraction: number): number | null {
  if (!input.length) return null
  const values = [...input].sort((a, b) => a - b)
  const position = (values.length - 1) * fraction
  const lower = Math.floor(position)
  return values[lower] + (values[Math.ceil(position)] - values[lower]) * (position - lower)
}
export function analyticsRatings(visits: Visit[]): number[] {
  return visits.flatMap((visit) => visit.rating != null && Number.isFinite(visit.rating) && visit.rating >= 0.5 && visit.rating <= 5 ? [visit.rating * 2] : [])
}
export function analyticsSpend(visits: Visit[]): AnalyticsSpend {
  const summary = summarizeVisitSpend(visits)
  const values = visits.flatMap((visit) => { const value = resolveVisitActualSpend(visit); return value == null ? [] : [value] })
  const coverage = visits.length ? summary.recordedVisitCount / visits.length : 0
  return { ...summary, coverage, display: coverage === 1 ? 'total' : coverage >= 0.6 ? 'recorded' : 'hidden',
    median: analyticsPercentile(values, 0.5), lowerQuartile: analyticsPercentile(values, 0.25), upperQuartile: analyticsPercentile(values, 0.75) }
}
export function analyticsRestaurantRanking(restaurants: RestaurantSummary[], visits: Visit[]): AnalyticsRestaurantEvidence[] {
  const byID = new Map(restaurants.map((item) => [item.id, item]))
  const groups = new Map<string, Visit[]>()
  for (const visit of visits) groups.set(visit.restaurantId, [...(groups.get(visit.restaurantId) ?? []), visit])
  return [...groups].flatMap(([restaurantID, values]) => {
    const restaurant = byID.get(restaurantID)
    if (!restaurant) return []
    const scoreOutOfTen = analyticsAverage(analyticsRatings(values))
    const latestVisitAt = [...values].sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt))[0].visitedAt
    return [{ id: restaurantID, restaurantID, label: restaurant.name, count: values.length, scoreOutOfTen, latestVisitAt,
      value: `${values.length} 次`, detail: scoreOutOfTen == null ? '未评分' : `平均 ${scoreOutOfTen.toFixed(1)} / 10` }]
  }).sort((a, b) => b.count - a.count || (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1) || Date.parse(b.latestVisitAt) - Date.parse(a.latestVisitAt) || a.id.localeCompare(b.id))
}
export function analyticsCities(restaurants: RestaurantSummary[], visits: Visit[]) {
  const byID = new Map(restaurants.map((item) => [item.id, item]))
  const labels = restaurantCityFilterOptions(visits.map((visit) => byID.get(visit.restaurantId)?.city ?? ''))
  return labels.map((label) => ({ id: restaurantCityComparisonKey(label), label,
    count: visits.filter((visit) => restaurantCityComparisonKey(byID.get(visit.restaurantId)?.city ?? '') === restaurantCityComparisonKey(label)).length,
    restaurantCount: new Set(visits.filter((visit) => restaurantCityComparisonKey(byID.get(visit.restaurantId)?.city ?? '') === restaurantCityComparisonKey(label)).map((visit) => visit.restaurantId)).size,
  })).sort((a, b) => b.count - a.count || a.id.localeCompare(b.id))
}
export function analyticsSummary(restaurants: RestaurantSummary[], visits: Visit[]): AnalyticsReportSummary {
  const ratings = analyticsRatings(visits)
  return { visitCount: visits.length, restaurantCount: new Set(visits.map((item) => item.restaurantId)).size,
    ratedVisitCount: ratings.length, averageScoreOutOfTen: analyticsAverage(ratings), cityCount: analyticsCities(restaurants, visits).length, spend: analyticsSpend(visits) }
}
export function analyticsConfidence(count: number, emergingAt = 3, establishedAt = 10) {
  return count < emergingAt ? 'insufficient' as const : count < establishedAt ? 'emerging' as const : 'established' as const
}
