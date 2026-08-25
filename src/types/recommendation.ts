import type { RestaurantSummary } from './domain'
import type { RecommendationBudget } from '../services/priceIntelligence'

export type RecommendationType = 'for_you' | 'similar_taste' | 'trending'
export type RecommendationSurface = 'map' | 'discover'
export type RecommendationConfidence = 'low' | 'medium' | 'high'
export type RecommendationReasonCode = 'TASTE_MATCH' | 'PRICE_MATCH' | 'QUALITY' | 'NEARBY' | 'REPEAT_AFFINITY' | 'SIMILAR_USERS' | 'EXPLORATION' | 'TRENDING' | 'COLD_START'
export type SimilarTasteEvidenceLevel = 'DIRECT_LOCAL' | 'NEARBY_DIRECT' | 'SIMILAR_CLUSTER_INFERRED' | 'PERSONAL_PROFILE_ONLY'

export interface RecommendationContext {
  type: RecommendationType
  surface: RecommendationSurface
  city?: string | null
  budget?: RecommendationBudget | null
  location?: { latitude: number; longitude: number } | null
  viewport?: { north: number; south: number; east: number; west: number } | null
  partyContext?: 'solo' | 'group' | null
  preferLocalSpecialty?: boolean
  preferNearby?: boolean
  avoidQueue?: boolean
  preferExploration?: boolean
}

export interface RestaurantRecommendation {
  restaurant: RestaurantSummary
  score: number
  rank: number
  reasonCodes: RecommendationReasonCode[]
  confidence: RecommendationConfidence
  source: RecommendationType
  surface: RecommendationSurface
  recommendationEvidence?: { similarTasteLevel?: SimilarTasteEvidenceLevel; sampleCount?: number; referenceRestaurantName?: string }
}

export type RecommendationEventName = 'impression' | 'restaurantDetailOpen' | 'wantToGoAdded' | 'wheelCandidateAdded' | 'navigationStarted' | 'visitCreated' | 'visitRating' | 'repeatVisit' | 'hideRecommendation'
export interface RecommendationEvent {
  id: string
  userId: string
  eventName: RecommendationEventName
  recommendationType: RecommendationType
  surface: RecommendationSurface
  restaurantId: string
  rank: number | null
  score: number | null
  reasonCodes: RecommendationReasonCode[]
  createdAt: string
}
