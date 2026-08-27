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

export const SYNC_API_VERSION = 1 as const
export const SYNC_SCHEMA_VERSION = 1 as const

export type SyncEntityType = 'restaurant' | 'visit' | 'dish' | 'visitDish' | 'photo'
export type SyncMutationOperation = 'upsert' | 'delete'
export type VisitDiningModeContract = 'dine_in' | 'takeout'

export interface VisitSyncContractV1 {
  schemaVersion: typeof SYNC_SCHEMA_VERSION
  id: string
  userId: string
  restaurantId: string
  visitedAt: string
  diningMode: VisitDiningModeContract
  partySize: number | null
  rating: number | null
  valueRating: number | null
  environmentRating: number | null
  serviceRating: number | null
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
  payload?: RestaurantJSONContractV1 | VisitSyncContractV1 | DishJSONContractV1 | VisitDishJSONContractV1 | PhotoJSONContractV1
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
  const partySize = 'partySize' in value ? value.partySize : null
  const valueRating = 'valueRating' in value ? value.valueRating : null
  const environmentRating = 'environmentRating' in value ? value.environmentRating : null
  const serviceRating = 'serviceRating' in value ? value.serviceRating : null
  if (diningMode !== 'dine_in' && diningMode !== 'takeout') {
    throw new SyncContractError('Visit diningMode must be dine_in or takeout.')
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
  return {
    ...value,
    diningMode,
    partySize,
    valueRating,
    environmentRating,
    serviceRating,
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
    !['restaurant', 'visit', 'dish', 'visitDish', 'photo'].includes(String(value.entityType)) ||
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
    }
  })()
  if (payload.id !== mutation.entityId) {
    throw new SyncContractError('Mutation entityId must match payload.id.')
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

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isISODateTime(value: unknown): value is string {
  return isNonEmptyString(value) && Number.isFinite(Date.parse(value))
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}
