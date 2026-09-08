import type {
  DiningDuration,
  DiningMode,
  DiningOccasion,
  NoiseLevel,
  PaymentMode,
  PortionLevel,
  RecommendationSourceType,
  StarRating,
  TransportConvenience,
  Visibility,
} from './domain'

export interface VisitExtraFieldsValue {
  visibility: Visibility
  diningMode: DiningMode
  paymentMode: PaymentMode | null
  diningOccasions: DiningOccasion[]
  diningOccasionText: string
  valueRating: StarRating | null
  environmentRating: StarRating | null
  serviceRating: StarRating | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: NoiseLevel | null
  diningDuration: DiningDuration | null
  portionLevel: PortionLevel | null
  transportConvenience: TransportConvenience | null
  specialNotes: string
  recommendationSourceType: RecommendationSourceType | null
  recommendationSourceUserId: string | null
  recommendationSourceText: string
  sharedParticipantUserIds: string[]
}

export function createDefaultVisitExtraFields(): VisitExtraFieldsValue {
  return {
    visibility: 'private',
    diningMode: 'dine_in',
    paymentMode: null,
    diningOccasions: [],
    diningOccasionText: '',
    valueRating: null,
    environmentRating: null,
    serviceRating: null,
    valueTags: [],
    environmentTags: [],
    serviceTags: [],
    noiseLevel: null,
    diningDuration: null,
    portionLevel: null,
    transportConvenience: null,
    specialNotes: '',
    recommendationSourceType: null,
    recommendationSourceUserId: null,
    recommendationSourceText: '',
    sharedParticipantUserIds: [],
  }
}
