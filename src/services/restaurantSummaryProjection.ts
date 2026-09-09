import type { Restaurant, RestaurantSummary, Visit } from '../types/domain'
import { queueDurationApproximateMinutes } from '../types/domain'
import { projectPersonalRestaurantRating } from './personalRestaurantRating'
import { restaurantPriceInsight } from './priceIntelligence'

/**
 * The shared Browser projection used by both the existing Browser App and the
 * Hybrid Browser adapter. It keeps Restaurant/Visit semantics out of either UI
 * shell and prevents a second summary calculation from drifting during the
 * migration.
 */
export function buildRestaurantSummaries(
  restaurants: Restaurant[],
  visits: Visit[],
  _options: { development?: boolean } = {},
): RestaurantSummary[] {
  const visitsByRestaurant = new Map<string, Visit[]>()
  for (const visit of visits) {
    if (visit.deletedAt) continue
    const group = visitsByRestaurant.get(visit.restaurantId) ?? []
    group.push(visit)
    visitsByRestaurant.set(visit.restaurantId, group)
  }
  visitsByRestaurant.forEach((group) => group.sort((a, b) => b.visitedAt.localeCompare(a.visitedAt)))

  return restaurants.flatMap((restaurant) => {
    if (restaurant.deletedAt) return []
    const restaurantVisits = (visitsByRestaurant.get(restaurant.id) ?? []).filter((visit) => visit.userId === restaurant.userId)
    const ratedVisits = restaurantVisits.filter((visit) => visit.rating !== null)
    const priceInsight = restaurantPriceInsight(restaurant, restaurantVisits)
    const queuedVisits = restaurantVisits
      .map((visit) => queueDurationApproximateMinutes(visit.queueDuration))
      .filter((minutes): minutes is number => minutes !== null)
    const { averageRating, scoreOutOfTen } = projectPersonalRestaurantRating(ratedVisits.map(visit => visit.rating!))
    const averageQueueMinutes = queuedVisits.length
      ? queuedVisits.reduce((sum, minutes) => sum + minutes, 0) / queuedVisits.length
      : null

    return [{
      ...restaurant,
      markerType: restaurant.markerType || 'emoji',
      markerImageData: restaurant.markerImageData ?? null,
      markerPhotoId: restaurant.markerPhotoId ?? null,
      merchantImageUrl: restaurant.merchantImageUrl ?? null,
      markerEmoji: restaurant.markerEmoji || '🍽️',
      pricePerPerson: restaurant.pricePerPerson ?? null,
      visitCount: restaurantVisits.length,
      averageRating,
      scoreOutOfTen: restaurant.overallRating ?? scoreOutOfTen,
      latestVisitDate: restaurantVisits[0]?.visitedAt ?? null,
      latestVisit: restaurantVisits[0] ?? null,
      visits: restaurantVisits,
      averagePricePerPerson: priceInsight.referencePrice,
      priceConfidence: priceInsight.confidence,
      priceSource: priceInsight.source,
      priceSampleCount: priceInsight.sampleCount,
      averageQueueMinutes,
    }]
  })
}
