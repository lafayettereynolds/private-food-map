import type { RestaurantSummary } from '../types/domain'

/** Collection membership is derived from live Visits, not a stale stored flag.
 * A zero-Visit Restaurant remains readable/editable and may still belong to
 * lists; it is neither a visited pin nor an implicitly created Want save.
 */
export function hasVisitedMembership(restaurant: Pick<RestaurantSummary, 'deletedAt' | 'visitCount'>) {
  return !restaurant.deletedAt && restaurant.visitCount > 0
}
