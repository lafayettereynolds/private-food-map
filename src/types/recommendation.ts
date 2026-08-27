import type { RestaurantSummary } from './domain'
import type { RecommendationBudget } from '../services/priceIntelligence'

export type RecommendationType = 'for_you' | 'similar_taste' | 'trending'
export type RecommendationSurface = 'map' | 'discover'
export type RecommendationConfidence = 'low' | 'medium' | 'high'
export type RecommendationFitLevel = 'STRONG_MATCH' | 'GOOD_MATCH' | 'MODERATE_MATCH' | 'EXPLORATION'
export type RecommendationReasonCode =
  | 'TASTE_MATCH'
  | 'PRICE_MATCH'
  | 'QUALITY'
  | 'NEARBY'
  | 'REPEAT_AFFINITY'
  | 'SIMILAR_USERS'
  | 'EXPLORATION'
  | 'TRENDING'
  | 'COLD_START'
  | 'HIGH_CUISINE_MATCH'
  | 'PRICE_RANGE_MATCH'
  | 'REPEAT_VISIT_PATTERN'
  | 'HIGH_RATING_TRAIT_MATCH'
  | 'COMPANION_CONTEXT_MATCH'
  | 'SOURCE_AFFINITY_MATCH'
  | 'SHORT_TERM_DIVERSITY'
  | 'NEARBY_AND_OPEN'
  | 'WANT_TO_GO_SIGNAL'
  | 'CROSS_CITY_TASTE_MATCH'
export type SimilarTasteEvidenceLevel = 'DIRECT_LOCAL' | 'NEARBY_DIRECT' | 'SIMILAR_CLUSTER_INFERRED' | 'PERSONAL_PROFILE_ONLY'

export interface RecommendationReason {
  code: RecommendationReasonCode
  text: string
  evidence?: {
    referenceRestaurantName?: string
    similarityPercent?: number
    cuisine?: string
    priceRange?: string
    repeatVisitCount?: number
    distanceKilometers?: number
  }
}

export interface PublicRatingReference {
  value: number | null
  sampleCount: number
}

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
  fitLevel: RecommendationFitLevel
  primaryReasons: RecommendationReason[]
  secondaryReasons: RecommendationReason[]
  isExploration: boolean
  publicRating?: PublicRatingReference
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
  fitLevel?: RecommendationFitLevel
  confidence?: RecommendationConfidence
  isExploration?: boolean
  createdAt: string
}
