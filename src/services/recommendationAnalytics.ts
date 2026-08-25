import { SOCIAL_API_ENABLED } from '../config/appEnvironment'
import type { RecommendationEvent, RecommendationEventName, RestaurantRecommendation } from '../types/recommendation'
import type { CommunityVisit } from '../types/domain'

export function trackRecommendationEvent(eventName: RecommendationEventName, recommendation: RestaurantRecommendation) {
  const event: RecommendationEvent = {
    id: crypto.randomUUID(), userId: 'owner', eventName,
    recommendationType: recommendation.source, surface: recommendation.surface, restaurantId: recommendation.restaurant.id,
    rank: recommendation.rank, score: recommendation.score, reasonCodes: recommendation.reasonCodes, createdAt: new Date().toISOString(),
  }
  if (SOCIAL_API_ENABLED) void fetch('/api/recommendation-events', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(event) }).catch(() => undefined)
  return event
}

export function trackDiscoveryRecommendationEvent(eventName: RecommendationEventName, item: CommunityVisit) {
  if (!item.recommendationType || !item.surface) return null
  const event: RecommendationEvent = {
    id: crypto.randomUUID(), userId: 'owner', eventName,
    recommendationType: item.recommendationType, surface: item.surface, restaurantId: item.restaurant.id,
    rank: item.recommendationRank ?? null, score: null, reasonCodes: item.reasonCodes ?? [], createdAt: new Date().toISOString(),
  }
  if (SOCIAL_API_ENABLED) void fetch('/api/recommendation-events', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(event) }).catch(() => undefined)
  return event
}
