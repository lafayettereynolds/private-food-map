import { SOCIAL_API_ENABLED } from '../config/appEnvironment'
import { apiURL } from '../config/apiEnvironment'
import type { RecommendationEvent, RecommendationEventName, RestaurantRecommendation } from '../types/recommendation'
import type { CommunityVisit } from '../types/domain'

export function trackRecommendationEvent(eventName: RecommendationEventName, recommendation: RestaurantRecommendation) {
  const event: RecommendationEvent = {
    id: crypto.randomUUID(), userId: 'owner', eventName,
    recommendationType: recommendation.source, surface: recommendation.surface, restaurantId: recommendation.restaurant.id,
    rank: recommendation.rank, score: recommendation.score, reasonCodes: recommendation.reasonCodes,
    fitLevel: recommendation.fitLevel, confidence: recommendation.confidence, isExploration: recommendation.isExploration,
    createdAt: new Date().toISOString(),
  }
  if (SOCIAL_API_ENABLED) void fetch(apiURL('/api/recommendation-events'), { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(event) }).catch(() => undefined)
  return event
}

export function trackDiscoveryRecommendationEvent(eventName: RecommendationEventName, item: CommunityVisit) {
  if (!item.recommendationType || !item.surface) return null
  const event: RecommendationEvent = {
    id: crypto.randomUUID(), userId: 'owner', eventName,
    recommendationType: item.recommendationType, surface: item.surface, restaurantId: item.restaurant.id,
    rank: item.recommendationRank ?? null, score: null, reasonCodes: item.reasonCodes ?? [],
    fitLevel: item.recommendationFitLevel ?? undefined, confidence: item.recommendationConfidence ?? undefined,
    isExploration: item.isExploration ?? false, createdAt: new Date().toISOString(),
  }
  if (SOCIAL_API_ENABLED) void fetch(apiURL('/api/recommendation-events'), { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(event) }).catch(() => undefined)
  return event
}
