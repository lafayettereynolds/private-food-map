import type { RestaurantSummary, Visit } from '../types/domain'
import { reviewService } from './reviewService'

/** Exact-day matching remains owned by reviewService. Nearby is explicitly separate. */
export function nearbyMemoryVisits(restaurants: RestaurantSummary[], visits: Visit[], reference: Date) {
  const eligible = visits.filter(visit => !visit.deletedAt && restaurants.some(item => item.id === visit.restaurantId && !item.deletedAt))
  const ids = new Set<string>()
  for (const offset of [-3, -2, -1, 1, 2, 3]) {
    const date = new Date(reference); date.setDate(date.getDate() + offset)
    // Around New Year the reference year stays the current one for prior-year eligibility.
    const matches = eligible.filter(visit => { const value = new Date(visit.visitedAt); return value.getFullYear() < reference.getFullYear() && value.getMonth() === date.getMonth() && value.getDate() === date.getDate() })
    matches.forEach(item => ids.add(item.id))
  }
  return eligible.filter(item => ids.has(item.id)).sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt))
}
export function exactMemoryReview(restaurants: RestaurantSummary[], visits: Visit[], reference: Date) {
  return reviewService.onThisDay(restaurants.filter(item => !item.deletedAt), visits.filter(visit => !visit.deletedAt && restaurants.some(item => item.id === visit.restaurantId && !item.deletedAt)), reference)
}

/** Presentation grouping of the already-authorized exact-day result; never adds nearby/current-year records. */
export function memoryYearGroups(visits: Visit[]) {
  const years = new Map<number, Visit[]>()
  for (const visit of visits) {
    const year = new Date(visit.visitedAt).getFullYear()
    if (!Number.isFinite(year)) continue
    years.set(year, [...(years.get(year) ?? []), visit])
  }
  return [...years].sort(([a], [b]) => b - a).map(([year, records]) => ({
    year,
    visits: records.sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt) || a.id.localeCompare(b.id)),
  }))
}
