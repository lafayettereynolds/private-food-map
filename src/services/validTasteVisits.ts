import type { RestaurantSummary, Visit } from '../types/domain'

export interface ValidTasteVisit {
  visit: Visit
  restaurant: RestaurantSummary
  ratingOutOfTen: number | null
  normalizedPerCapitaSpend: number | null
}

/** Shared platform-neutral dataset. Each analysis module filters only the fields it needs. */
export function buildValidTasteVisits(restaurants: RestaurantSummary[], visits: Visit[]): ValidTasteVisit[] {
  const restaurantById = new Map(restaurants.filter((item) => !item.deletedAt).map((item) => [item.id, item]))
  return visits.flatMap((visit) => {
    const restaurant = restaurantById.get(visit.restaurantId)
    if (!restaurant || visit.deletedAt || !Number.isFinite(Date.parse(visit.visitedAt))) return []
    return [{ visit, restaurant, ratingOutOfTen: visit.rating == null ? null : Number(visit.rating) * 2, normalizedPerCapitaSpend: normalizedPerCapitaSpend(visit) }]
  })
}

export function normalizedPerCapitaSpend(visit: Visit) {
  if (visit.paymentMode === 'separate') return null
  if (visit.totalPrice == null || !Number.isFinite(visit.totalPrice) || visit.totalPrice <= 0) return null
  if (!Number.isFinite(visit.partySize) || visit.partySize < 1) return null
  return visit.totalPrice / visit.partySize
}

export type ModuleConfidence = 'insufficient' | 'emerging' | 'established'
export function moduleConfidence(sampleCount: number, establishedAt = 12, emergingAt = 4): ModuleConfidence {
  return sampleCount >= establishedAt ? 'established' : sampleCount >= emergingAt ? 'emerging' : 'insufficient'
}
