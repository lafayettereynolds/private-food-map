import type { RestaurantSummary, Visit } from '../types/domain'

export type TasteFootprintEventKind = 'visit' | 'wantToGo'

export interface TasteFootprintEvent {
  id: string
  kind: TasteFootprintEventKind
  eventAt: string
  restaurant: RestaurantSummary
  visit: Visit | null
}

/** Builds the owner's private food timeline from timestamps we can faithfully reconstruct. */
export function buildTasteFootprintEvents(
  restaurants: RestaurantSummary[],
  visits?: Visit[],
): TasteFootprintEvent[] {
  const restaurantById = new Map<string, RestaurantSummary>()
  for (const restaurant of restaurants) {
    if (!restaurant.deletedAt && !restaurantById.has(restaurant.id)) restaurantById.set(restaurant.id, restaurant)
  }

  const visitSource = [...(visits ?? []), ...restaurants.flatMap((restaurant) => restaurant.visits)]
  const deletedVisitIds = new Set(visitSource.filter((visit) => visit.deletedAt).map((visit) => visit.id))
  const uniqueVisits = new Map<string, Visit>()
  for (const visit of visitSource) {
    if (!visit.deletedAt && !deletedVisitIds.has(visit.id) && !uniqueVisits.has(visit.id)) uniqueVisits.set(visit.id, visit)
  }

  const events: TasteFootprintEvent[] = []
  for (const visit of uniqueVisits.values()) {
    const restaurant = restaurantById.get(visit.restaurantId)
    if (!restaurant) continue
    events.push({ id: `visit:${visit.id}`, kind: 'visit', eventAt: visit.visitedAt, restaurant, visit })
  }

  for (const restaurant of restaurantById.values()) {
    if (restaurant.status !== 'wantToGo') continue
    events.push({ id: `wantToGo:${restaurant.id}`, kind: 'wantToGo', eventAt: restaurant.createdAt, restaurant, visit: null })
  }

  return events.sort((left, right) => {
    const timeDifference = timestamp(right.eventAt) - timestamp(left.eventAt)
    return timeDifference || left.id.localeCompare(right.id)
  })
}

function timestamp(value: string) {
  const parsed = Date.parse(value)
  return Number.isFinite(parsed) ? parsed : 0
}
