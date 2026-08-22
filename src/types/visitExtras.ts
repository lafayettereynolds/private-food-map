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
  myActualSpend: string
  paymentMode: PaymentMode | null
  diningOccasion: DiningOccasion | null
  valueRating: StarRating | null
  environmentRating: StarRating | null
  serviceRating: StarRating | null
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
    myActualSpend: '',
    paymentMode: null,
    diningOccasion: null,
    valueRating: null,
    environmentRating: null,
    serviceRating: null,
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
