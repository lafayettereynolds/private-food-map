import type { PhotoKind, StarRating, Visibility } from '../types/domain'

export const DISH_CONTRACT_VERSION = 1 as const
export const PHOTO_CONTRACT_VERSION = 1 as const

export type PhotoStorageProviderContract = 'google-drive' | 'cloudkit' | 'r2' | 'oss' | 'cos'

export interface DishJSONContractV1 {
  schemaVersion: typeof DISH_CONTRACT_VERSION
  id: string
  userId: string
  restaurantId: string
  visitId: string
  name: string
  taste: string
  rating: StarRating | null
  price: number | null
  photoId: string | null
  sortOrder: number
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface PhotoJSONContractV1 {
  schemaVersion: typeof PHOTO_CONTRACT_VERSION
  id: string
  userId: string
  restaurantId: string | null
  visitId: string | null
  dishId: string | null
  kind: PhotoKind
  storageProvider: PhotoStorageProviderContract
  storageKey: string
  providerAccountId: string | null
  thumbnailStorageKey: string | null
  fileName: string | null
  mimeType: string
  byteSize: number
  width: number | null
  height: number | null
  sortOrder: number
  visibility: Visibility
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

const dishKeys = new Set([
  'schemaVersion', 'id', 'userId', 'restaurantId', 'visitId', 'name', 'taste',
  'rating', 'price', 'photoId', 'sortOrder', 'createdAt', 'updatedAt', 'deletedAt',
])
const photoKeys = new Set([
  'schemaVersion', 'id', 'userId', 'restaurantId', 'visitId', 'dishId', 'kind',
  'storageProvider', 'storageKey', 'providerAccountId', 'thumbnailStorageKey',
  'fileName', 'mimeType', 'byteSize', 'width', 'height', 'sortOrder', 'visibility',
  'createdAt', 'updatedAt', 'deletedAt',
])
const photoKinds = new Set<PhotoKind>(['restaurant-marker', 'visit', 'dish', 'avatar'])
const providers = new Set<PhotoStorageProviderContract>(['google-drive', 'cloudkit', 'r2', 'oss', 'cos'])
const visibilities = new Set<Visibility>(['private', 'friends', 'public'])

export class DishPhotoContractError extends Error {}

export function decodeDishJSONContract(value: unknown): DishJSONContractV1 {
  if (!isRecord(value) || value.schemaVersion !== DISH_CONTRACT_VERSION) {
    throw new DishPhotoContractError('Dish contract must be a schemaVersion=1 JSON object.')
  }
  assertAllowedKeys(value, dishKeys, 'Dish')
  for (const key of ['id', 'userId', 'restaurantId', 'visitId'] as const) {
    if (!isNonEmptyString(value[key])) throw new DishPhotoContractError(`Dish.${key} is required.`)
  }
  if (typeof value.name !== 'string' || typeof value.taste !== 'string') {
    throw new DishPhotoContractError('Dish name and taste are required strings.')
  }
  assertNullableHalfRating(value.rating, 'Dish.rating')
  assertNullableNonNegativeNumber(value.price, 'Dish.price')
  assertNullableString(value.photoId, 'Dish.photoId')
  assertSortOrder(value.sortOrder, 'Dish.sortOrder')
  assertDateFields(value, 'Dish')
  return value as unknown as DishJSONContractV1
}

export function decodePhotoJSONContract(value: unknown): PhotoJSONContractV1 {
  if (!isRecord(value) || value.schemaVersion !== PHOTO_CONTRACT_VERSION) {
    throw new DishPhotoContractError('Photo contract must be a schemaVersion=1 JSON object.')
  }
  assertAllowedKeys(value, photoKeys, 'Photo')
  for (const key of ['id', 'userId', 'storageKey', 'mimeType'] as const) {
    if (!isNonEmptyString(value[key])) throw new DishPhotoContractError(`Photo.${key} is required.`)
  }
  for (const key of ['restaurantId', 'visitId', 'dishId', 'providerAccountId', 'thumbnailStorageKey', 'fileName'] as const) {
    assertNullableString(value[key], `Photo.${key}`)
  }
  if (!photoKinds.has(value.kind as PhotoKind) || !providers.has(value.storageProvider as PhotoStorageProviderContract) ||
    !visibilities.has(value.visibility as Visibility)) {
    throw new DishPhotoContractError('Photo contains an unsupported kind, provider, or visibility.')
  }
  if (!Number.isInteger(value.byteSize) || Number(value.byteSize) < 0) {
    throw new DishPhotoContractError('Photo.byteSize must be a non-negative integer.')
  }
  for (const key of ['width', 'height'] as const) {
    const dimension = value[key]
    if (dimension !== null && (!Number.isInteger(dimension) || Number(dimension) <= 0)) {
      throw new DishPhotoContractError(`Photo.${key} must be null or a positive integer.`)
    }
  }
  assertSortOrder(value.sortOrder, 'Photo.sortOrder')
  assertDateFields(value, 'Photo')
  assertPhotoRelationships(value)
  return value as unknown as PhotoJSONContractV1
}

function assertPhotoRelationships(value: Record<string, unknown>) {
  const restaurantId = value.restaurantId
  const visitId = value.visitId
  const dishId = value.dishId
  switch (value.kind as PhotoKind) {
    case 'restaurant-marker':
      if (!isNonEmptyString(restaurantId)) throw new DishPhotoContractError('Restaurant photo requires restaurantId.')
      break
    case 'visit':
      if (!isNonEmptyString(restaurantId) || !isNonEmptyString(visitId)) {
        throw new DishPhotoContractError('Visit photo requires restaurantId and visitId.')
      }
      break
    case 'dish':
      if (!isNonEmptyString(restaurantId) || !isNonEmptyString(visitId) || !isNonEmptyString(dishId)) {
        throw new DishPhotoContractError('Dish photo requires restaurantId, visitId, and dishId.')
      }
      break
    case 'avatar':
      break
  }
}

function assertDateFields(value: Record<string, unknown>, label: string) {
  if (!isISODateTime(value.createdAt) || !isISODateTime(value.updatedAt) ||
    (value.deletedAt !== null && !isISODateTime(value.deletedAt))) {
    throw new DishPhotoContractError(`${label} timestamps are invalid.`)
  }
}

function assertNullableHalfRating(value: unknown, label: string) {
  if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) ||
    value < 0.5 || value > 5 || value * 2 % 1 !== 0)) {
    throw new DishPhotoContractError(`${label} must be null or a half-step from 0.5 through 5.0.`)
  }
}

function assertNullableNonNegativeNumber(value: unknown, label: string) {
  if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
    throw new DishPhotoContractError(`${label} must be null or a non-negative number.`)
  }
}

function assertNullableString(value: unknown, label: string) {
  if (value !== null && typeof value !== 'string') {
    throw new DishPhotoContractError(`${label} must be a string or null.`)
  }
}

function assertSortOrder(value: unknown, label: string) {
  if (!Number.isInteger(value) || Number(value) < 0) {
    throw new DishPhotoContractError(`${label} must be a non-negative integer.`)
  }
}

function assertAllowedKeys(value: Record<string, unknown>, keys: Set<string>, label: string) {
  const unknownKey = Object.keys(value).find((key) => !keys.has(key))
  if (unknownKey) throw new DishPhotoContractError(`Unknown ${label} field: ${unknownKey}`)
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
