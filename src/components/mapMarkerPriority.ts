import type { RestaurantSummary } from '../types/domain'

/**
 * Canonical Restaurant marker ordering. The user-location marker deliberately
 * lives outside this comparator at zIndex 2_000_000_000.
 */
export function markerLayerPriority(
  restaurant: Pick<RestaurantSummary, 'id' | 'scoreOutOfTen' | 'visitCount'>,
  selected = false,
) {
  if (selected) return 1_500_000_000
  const ratingPriority = Math.round((restaurant.scoreOutOfTen ?? -1) * 100)
  const visitPriority = Math.min(Math.max(restaurant.visitCount, 0), 9_999)
  // Every tier has a disjoint numeric range: stable ID can never overtake a
  // one-visit difference, and visits can never overtake a 0.01 score step.
  return (ratingPriority + 100) * 1_000_000 + visitPriority * 1_000 + stableIDPriority(restaurant.id)
}

function stableIDPriority(id: string) {
  let hash = 0
  for (let index = 0; index < id.length; index += 1) hash = (hash * 31 + id.charCodeAt(index)) >>> 0
  return hash % 997
}
