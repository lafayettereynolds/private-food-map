import type {
  TasteMapHybridActivityItemDTO,
  TasteMapHybridDiscoveryItemDTO,
} from './TasteMapPlatform'
import { DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE } from '../contracts/discoveryContract'

function isQualifiedVisitRating(rating: number | null) {
  return rating != null && rating >= DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE
}

/**
 * Public Discovery is an evidence surface, not a complete visit ledger.
 *
 * A Visit below 7.5/10 remains valid personal/history data and may contribute
 * to visit-count Trends, but it is not qualified public recommendation
 * evidence. Want-to-go events are kept as explicitly labelled social intent
 * and never masquerade as a Visit rating.
 */
export function isDiscoveryFeedActivityEligible(item: TasteMapHybridActivityItemDTO) {
  return item.kind !== 'visit' || (item.visitID != null && isQualifiedVisitRating(item.visitRating))
}

/**
 * Trends are restaurant-level count aggregates, so their inclusion does not
 * depend on an individual rating. Similar-taste cards always require a rated
 * concrete Visit. A system For You recommendation may have no concrete Visit;
 * if it does carry one, that Visit must be rated.
 */
export function isDiscoveryPlacementEligible(item: TasteMapHybridDiscoveryItemDTO) {
  if (item.mode === 'trending') return true
  if (item.mode === 'similar_taste') return isQualifiedVisitRating(item.activityRating)
  const isConcreteUserActivity = item.interaction != null || item.sourceUser != null || item.activityVisitedAt != null
  return !isConcreteUserActivity || isQualifiedVisitRating(item.activityRating)
}
