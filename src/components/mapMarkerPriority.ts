import type { RestaurantSummary } from '../types/domain'

type PrioritizedRestaurant = Pick<RestaurantSummary, 'id' | 'scoreOutOfTen' | 'visitCount' | 'recommendationRank' | 'recommendationScore'>
type LocatedRestaurant = Pick<RestaurantSummary, 'latitude' | 'longitude'>

export interface MarkerScreenPoint {
  x: number
  y: number
}

// Latitude span is a zoom measure, not an administrative city boundary.
const regionalGroupingMinimumLatitudeDelta = 0.8
const regionalGroupingFullLatitudeDelta = 2.4
export const markerStackMaximumVisibleMembers = 3

export function markerUsesRegionalGrouping(latitudeDelta: number) {
  return Number.isFinite(latitudeDelta) && Math.abs(latitudeDelta) >= regionalGroupingMinimumLatitudeDelta
}

/** Exact provider coordinates only; never guess that nearby venues share a mall. */
export function markerIsCoincidentGroup(group: readonly LocatedRestaurant[]) {
  const first = group[0]
  return !!first && group.every((member) => member.latitude === first.latitude && member.longitude === first.longitude)
}

export function markerCoincidentGroups<T extends PrioritizedRestaurant & LocatedRestaurant>(restaurants: readonly T[]): T[][] {
  const groups = new Map<string, T[]>()
  const ordered = [...restaurants].sort((left, right) => compareMarkerLayerPriority(right, left))
  for (const restaurant of ordered) {
    const key = `${restaurant.latitude}:${restaurant.longitude}`
    const group = groups.get(key) ?? []
    group.push(restaurant)
    groups.set(key, group)
  }
  return [...groups.values()]
}

/** Strictly same-coordinate members only: a real front and up to two real backs. */
export function markerCoincidentStackMembers<T extends PrioritizedRestaurant & LocatedRestaurant>(group: readonly T[]): T[] {
  if (group.length < 2 || !markerIsCoincidentGroup(group)) return []
  return [...group].sort((left, right) => compareMarkerLayerPriority(right, left)).slice(0, markerStackMaximumVisibleMembers)
}

/** Only wide regional views consolidate into real Restaurant representatives. */
export function markerRegionalGroupingDistance(latitudeDelta: number, markerDiameter: number) {
  const span = Math.abs(latitudeDelta)
  if (!Number.isFinite(span) || span <= regionalGroupingMinimumLatitudeDelta) return 0
  const progress = Math.min(1, Math.log(span / regionalGroupingMinimumLatitudeDelta)
    / Math.log(regionalGroupingFullLatitudeDelta / regionalGroupingMinimumLatitudeDelta))
  return Math.ceil(markerDiameter * 1.14 + 7) * progress
}

/** Only visibility changes; every member retains its exact provider coordinate. */
export function markerRegionalGroups<T extends PrioritizedRestaurant>(
  restaurants: readonly T[],
  screenPoints: ReadonlyMap<string, MarkerScreenPoint>,
  requiredCenterDistance: number,
): T[][] {
  const ordered = [...restaurants].sort((left, right) => compareMarkerLayerPriority(right, left))
  if (!Number.isFinite(requiredCenterDistance) || requiredCenterDistance <= 0) return ordered.map((restaurant) => [restaurant])
  const remaining = new Set(ordered.map((restaurant) => restaurant.id))
  const groups: T[][] = []
  for (const representative of ordered) {
    if (!remaining.delete(representative.id)) continue
    const group = [representative]
    for (let index = 0; index < group.length; index += 1) {
      const point = screenPoints.get(group[index].id)
      if (!point) continue
      for (const candidate of ordered) {
        if (!remaining.has(candidate.id)) continue
        const candidatePoint = screenPoints.get(candidate.id)
        if (!candidatePoint || Math.hypot(candidatePoint.x - point.x, candidatePoint.y - point.y) >= requiredCenterDistance) continue
        remaining.delete(candidate.id)
        group.push(candidate)
      }
    }
    groups.push(group)
  }
  return groups
}

/**
 * Canonical Restaurant marker ordering. The user-location marker deliberately
 * lives outside this comparator at zIndex 2_000_000_000.
 */
export function markerLayerPriorities(restaurants: readonly PrioritizedRestaurant[], selectedID?: string) {
  // Assign ordinal z-indices after comparing the actual values. Numeric
  // weighting/rounding must not let a low score overtake a higher one.
  return new Map([...restaurants].sort(compareMarkerLayerPriority)
    .map((restaurant, index) => [restaurant.id, restaurant.id === selectedID ? 1_500_000_000 : index + 1]))
}

/** Ascending back-to-front, matching Native MapKit's exact ordering. */
export function compareMarkerLayerPriority(left: PrioritizedRestaurant, right: PrioritizedRestaurant) {
  const leftRating = finiteValue(left.scoreOutOfTen)
  const rightRating = finiteValue(right.scoreOutOfTen)
  if (leftRating !== rightRating) {
    if (leftRating == null) return -1
    if (rightRating == null) return 1
    return leftRating - rightRating
  }
  const leftRank = positiveRank(left.recommendationRank)
  const rightRank = positiveRank(right.recommendationRank)
  if (leftRank !== rightRank) {
    if (leftRank == null) return -1
    if (rightRank == null) return 1
    return rightRank - leftRank
  }
  const leftVisits = Math.max(0, finiteValue(left.visitCount) ?? 0)
  const rightVisits = Math.max(0, finiteValue(right.visitCount) ?? 0)
  if (leftVisits !== rightVisits) return leftVisits - rightVisits
  const leftID = left.id.toLowerCase()
  const rightID = right.id.toLowerCase()
  return leftID < rightID ? -1 : leftID > rightID ? 1 : 0
}

function finiteValue(value: number | null | undefined) {
  return value != null && Number.isFinite(value) ? value : null
}

function positiveRank(value: number | null | undefined) {
  const finite = finiteValue(value)
  return finite != null && finite > 0 ? finite : null
}
