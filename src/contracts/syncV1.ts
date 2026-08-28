import {
  decodeRestaurantJSONContract,
  type RestaurantJSONContractV1,
} from './restaurantContract'
import {
  decodeDishJSONContract,
  decodeVisitDishJSONContract,
  decodePhotoJSONContract,
  type DishJSONContractV1,
  type VisitDishJSONContractV1,
  type PhotoJSONContractV1,
} from './dishPhotoContract'
import {
  decodeDiningCompanionSyncContract,
  decodeRecommendationSourceSyncContract,
  RECOMMENDATION_SOURCE_TYPES,
  type DiningCompanionSyncContractV1,
  type RecommendationSourceContractType,
  type RecommendationSourceSyncContractV1,
} from './companionSourceContract'
import {
  decodeOwnProfileSyncContract,
  type OwnProfileSyncContractV1,
} from './profileContract'
import {
  decodeRestaurantListItemSyncContract,
  decodeRestaurantListSyncContract,
  type RestaurantListItemSyncContractV1,
  type RestaurantListSyncContractV1,
} from './restaurantListContract'

export const SYNC_API_VERSION = 1 as const
export const SYNC_SCHEMA_VERSION = 1 as const

export type SyncEntityType = 'restaurant' | 'visit' | 'dish' | 'visitDish' | 'photo' | 'companion' | 'recommendationSource' | 'profile' | 'restaurantList' | 'restaurantListItem'
export type SyncMutationOperation = 'upsert' | 'delete'
export type VisitDiningModeContract = 'dine_in' | 'takeout'
export type VisitVisibilityContract = 'private' | 'friends' | 'public'

export interface VisitSyncContractV1 {
  schemaVersion: typeof SYNC_SCHEMA_VERSION
  id: string
  userId: string
  restaurantId: string
  visitedAt: string
  diningMode: VisitDiningModeContract
  visibility: VisitVisibilityContract
  partySize: number | null
  totalPrice: number | null
  paymentMode: string | null
  pricePerPerson: number | null
  queueDuration: string | null
  diningOccasions: string[]
  diningOccasionText: string | null
  rating: number | null
  valueRating: number | null
  environmentRating: number | null
  serviceRating: number | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: string | null
  diningDuration: string | null
  portionLevel: string | null
  transportConvenience: string | null
  specialNotes: string | null
  companions: string[]
  companionIds: string[]
  recommendationSourceId: string | null
  recommendationSourceType: RecommendationSourceContractType | null
  recommendationSourceUserId: string | null
  recommendationSourceText: string | null
  sharedMealId: string | null
  note: string | null
  myActualSpend: number | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface SyncMutationV1 {
  mutationId: string
  entityType: SyncEntityType
  entityId: string
  operation: SyncMutationOperation
  baseVersion: number
  clientTimestamp: string
  payload?: RestaurantJSONContractV1 | VisitSyncContractV1 | DishJSONContractV1 | VisitDishJSONContractV1 | PhotoJSONContractV1 | DiningCompanionSyncContractV1 | RecommendationSourceSyncContractV1 | OwnProfileSyncContractV1 | RestaurantListSyncContractV1 | RestaurantListItemSyncContractV1
}

export interface SyncPushRequestV1 {
  apiVersion: typeof SYNC_API_VERSION
  schemaVersion: typeof SYNC_SCHEMA_VERSION
  mutations: SyncMutationV1[]
}

export interface SyncMutationAcknowledgementV1 {
  mutationId: string
  entityType: SyncEntityType
  entityId: string
  status: 'applied' | 'conflict'
  duplicate: boolean
  serverVersion: number
  revision: number | null
  conflictReason: string | null
}

export interface SyncPushResponseV1 {
  apiVersion: typeof SYNC_API_VERSION
  acknowledgements: SyncMutationAcknowledgementV1[]
  serverTime: string
}

export interface SyncRecordEnvelopeV1<RecordType> {
  serverVersion: number
  record: RecordType
}

export interface SyncTombstoneV1 {
  entityType: SyncEntityType
  entityId: string
  serverVersion: number
  deletedAt: string
}

export interface SyncPullResponseV1 {
  apiVersion: typeof SYNC_API_VERSION
  schemaVersion: typeof SYNC_SCHEMA_VERSION
  restaurants: Array<SyncRecordEnvelopeV1<RestaurantJSONContractV1>>
  visits: Array<SyncRecordEnvelopeV1<VisitSyncContractV1>>
  dishes: Array<SyncRecordEnvelopeV1<DishJSONContractV1>>
  visitDishes: Array<SyncRecordEnvelopeV1<VisitDishJSONContractV1>>
  photos: Array<SyncRecordEnvelopeV1<PhotoJSONContractV1>>
  companions: Array<SyncRecordEnvelopeV1<DiningCompanionSyncContractV1>>
  recommendationSources: Array<SyncRecordEnvelopeV1<RecommendationSourceSyncContractV1>>
  profiles: Array<SyncRecordEnvelopeV1<OwnProfileSyncContractV1>>
  restaurantLists: Array<SyncRecordEnvelopeV1<RestaurantListSyncContractV1>>
  restaurantListItems: Array<SyncRecordEnvelopeV1<RestaurantListItemSyncContractV1>>
  tombstones: SyncTombstoneV1[]
  nextCursor: string
  hasMore: boolean
  serverTime: string
}

export class SyncContractError extends Error {}

export function decodeSyncPushRequest(value: unknown): SyncPushRequestV1 {
  if (!isRecord(value) || value.apiVersion !== SYNC_API_VERSION || value.schemaVersion !== SYNC_SCHEMA_VERSION ||
    !Array.isArray(value.mutations) || value.mutations.length > 100) {
    throw new SyncContractError('Sync push contract is invalid.')
  }
  return {
    apiVersion: SYNC_API_VERSION,
    schemaVersion: SYNC_SCHEMA_VERSION,
    mutations: value.mutations.map(decodeSyncMutation),
  }
}

export function decodeVisitSyncContract(value: unknown): VisitSyncContractV1 {
  if (!isRecord(value) || value.schemaVersion !== SYNC_SCHEMA_VERSION ||
    !isNonEmptyString(value.id) || !isNonEmptyString(value.userId) ||
    !isNonEmptyString(value.restaurantId) || !isISODateTime(value.visitedAt) ||
    !isISODateTime(value.createdAt) || !isISODateTime(value.updatedAt) ||
    !hasNullableString(value, 'note') || !hasNullableString(value, 'deletedAt') ||
    !hasNullableNumber(value, 'myActualSpend') || !hasNullableNumber(value, 'rating')) {
    throw new SyncContractError('Visit sync contract is invalid.')
  }
  const diningMode = 'diningMode' in value ? value.diningMode : 'dine_in'
  const visibility = 'visibility' in value ? value.visibility : 'private'
  const partySize = 'partySize' in value ? value.partySize : null
  const totalPrice = 'totalPrice' in value ? value.totalPrice : null
  const paymentMode = legacyNullableString(value, 'paymentMode')
  const pricePerPerson = 'pricePerPerson' in value ? value.pricePerPerson : null
  const queueDuration = legacyNullableString(value, 'queueDuration')
  const diningOccasions = legacyStringArray(value, 'diningOccasions')
  const diningOccasionText = legacyNullableString(value, 'diningOccasionText')
  const valueRating = 'valueRating' in value ? value.valueRating : null
  const environmentRating = 'environmentRating' in value ? value.environmentRating : null
  const serviceRating = 'serviceRating' in value ? value.serviceRating : null
  if (diningMode !== 'dine_in' && diningMode !== 'takeout') {
    throw new SyncContractError('Visit diningMode must be dine_in or takeout.')
  }
  if (visibility !== 'private' && visibility !== 'friends' && visibility !== 'public') {
    throw new SyncContractError('Visit visibility must be private, friends, or public.')
  }
  if (partySize !== null && (!Number.isInteger(partySize) || Number(partySize) < 1)) {
    throw new SyncContractError('Visit partySize must be null or a positive integer.')
  }
  validateVisitRating(value.rating, 'rating')
  validateVisitRating(valueRating, 'valueRating')
  validateVisitRating(environmentRating, 'environmentRating')
  validateVisitRating(serviceRating, 'serviceRating')
  if (value.myActualSpend !== null && Number(value.myActualSpend) < 0) {
    throw new SyncContractError('Visit myActualSpend cannot be negative.')
  }
  for (const [field, amount] of [['totalPrice', totalPrice], ['pricePerPerson', pricePerPerson]] as const) {
    if (amount !== null && (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0)) {
      throw new SyncContractError(`Visit ${field} must be null or a non-negative finite number.`)
    }
  }
  const valueTags = legacyStringArray(value, 'valueTags')
  const environmentTags = legacyStringArray(value, 'environmentTags')
  const serviceTags = legacyStringArray(value, 'serviceTags')
  const noiseLevel = legacyNullableString(value, 'noiseLevel')
  const diningDuration = legacyNullableString(value, 'diningDuration')
  const portionLevel = legacyNullableString(value, 'portionLevel')
  const transportConvenience = legacyNullableString(value, 'transportConvenience')
  const specialNotes = legacyNullableString(value, 'specialNotes')
  const companions = legacyStringArray(value, 'companions')
  const companionIds = legacyStringArray(value, 'companionIds')
  if (companions.length !== companionIds.length && companionIds.length !== 0) {
    throw new SyncContractError('Visit companionIds must be empty for legacy data or parallel companions.')
  }
  const recommendationSourceId = legacyNullableString(value, 'recommendationSourceId')
  const recommendationSourceType = legacyNullableString(value, 'recommendationSourceType')
  if (recommendationSourceType !== null &&
    !RECOMMENDATION_SOURCE_TYPES.includes(recommendationSourceType as RecommendationSourceContractType)) {
    throw new SyncContractError('Visit recommendationSourceType is invalid.')
  }
  const recommendationSourceUserId = legacyNullableString(value, 'recommendationSourceUserId')
  const recommendationSourceText = legacyNullableString(value, 'recommendationSourceText')
  const sharedMealId = legacyNullableString(value, 'sharedMealId')
  return {
    ...value,
    diningMode,
    visibility,
    partySize,
    totalPrice,
    paymentMode,
    pricePerPerson,
    queueDuration,
    diningOccasions,
    diningOccasionText,
    valueRating,
    environmentRating,
    serviceRating,
    valueTags,
    environmentTags,
    serviceTags,
    noiseLevel,
    diningDuration,
    portionLevel,
    transportConvenience,
    specialNotes,
    companions,
    companionIds,
    recommendationSourceId,
    recommendationSourceType: recommendationSourceType as RecommendationSourceContractType | null,
    recommendationSourceUserId,
    recommendationSourceText,
    sharedMealId,
  } as unknown as VisitSyncContractV1
}

function validateVisitRating(value: unknown, field: string) {
  if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0.5 || value > 5 || value * 2 % 1 !== 0)) {
    throw new SyncContractError(`Visit ${field} must be null or a half-step from 0.5 through 5.0.`)
  }
}

export function stableSyncMutationJSON(mutation: SyncMutationV1) {
  return stableJSONString(mutation)
}

function decodeSyncMutation(value: unknown): SyncMutationV1 {
  if (!isRecord(value) || !isNonEmptyString(value.mutationId) ||
    !['restaurant', 'visit', 'dish', 'visitDish', 'photo', 'companion', 'recommendationSource', 'profile', 'restaurantList', 'restaurantListItem'].includes(String(value.entityType)) ||
    !isNonEmptyString(value.entityId) || !['upsert', 'delete'].includes(String(value.operation)) ||
    !Number.isInteger(value.baseVersion) || Number(value.baseVersion) < 0 ||
    !isNonEmptyString(value.clientTimestamp)) {
    throw new SyncContractError('Sync mutation is invalid.')
  }
  const mutation = {
    mutationId: value.mutationId,
    entityType: value.entityType as SyncEntityType,
    entityId: value.entityId,
    operation: value.operation as SyncMutationOperation,
    baseVersion: value.baseVersion as number,
    clientTimestamp: value.clientTimestamp,
  }
  if (mutation.operation === 'delete') {
    if ('payload' in value && value.payload !== null && value.payload !== undefined) {
      throw new SyncContractError('Delete mutation must not contain a payload.')
    }
    return mutation
  }
  const payload = (() => {
    switch (mutation.entityType) {
      case 'restaurant': return decodeRestaurantJSONContract(value.payload)
      case 'visit': return decodeVisitSyncContract(value.payload)
      case 'dish': return decodeDishJSONContract(value.payload)
      case 'visitDish': return decodeVisitDishJSONContract(value.payload)
      case 'photo': return decodePhotoJSONContract(value.payload)
      case 'companion': return decodeDiningCompanionSyncContract(value.payload)
      case 'recommendationSource': return decodeRecommendationSourceSyncContract(value.payload)
      case 'profile': return decodeOwnProfileSyncContract(value.payload)
      case 'restaurantList': return decodeRestaurantListSyncContract(value.payload)
      case 'restaurantListItem': return decodeRestaurantListItemSyncContract(value.payload)
    }
  })()
  const payloadEntityId = mutation.entityType === 'profile'
    ? (payload as OwnProfileSyncContractV1).userId
    : (payload as Exclude<typeof payload, OwnProfileSyncContractV1>).id
  if (payloadEntityId !== mutation.entityId) {
    throw new SyncContractError('Mutation entityId must match the payload entity identity.')
  }
  if (payload.deletedAt !== null) {
    throw new SyncContractError('Tombstones must use operation=delete instead of an upsert payload.')
  }
  return { ...mutation, payload }
}

function stableJSONString(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJSONString).join(',')}]`
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJSONString(value[key])}`).join(',')}}`
  }
  return JSON.stringify(value) ?? 'null'
}

function hasNullableString(value: Record<string, unknown>, key: string) {
  return key in value && (value[key] === null || typeof value[key] === 'string')
}

function hasNullableNumber(value: Record<string, unknown>, key: string) {
  return key in value && (value[key] === null || (typeof value[key] === 'number' && Number.isFinite(value[key])))
}

function legacyNullableString(value: Record<string, unknown>, key: string) {
  if (!(key in value) || value[key] === null || value[key] === '') return null
  if (typeof value[key] !== 'string' || value[key].trim().length > 1000) {
    throw new SyncContractError(`Visit ${key} must be null or a bounded string.`)
  }
  return value[key].trim()
}

function legacyStringArray(value: Record<string, unknown>, key: string) {
  if (!(key in value)) return []
  const raw = value[key]
  if (!Array.isArray(raw) || raw.length > 40 ||
    !raw.every((item) => typeof item === 'string' && item.trim().length > 0 && item.trim().length <= 100)) {
    throw new SyncContractError(`Visit ${key} must be an array of bounded non-empty strings.`)
  }
  return [...new Set(raw.map((item) => (item as string).trim()))]
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isISODateTime(value: unknown): value is string {
  return isNonEmptyString(value) && Number.isFinite(Date.parse(value))
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}
