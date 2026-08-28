import type { RestaurantPlaceProvider } from '../types/restaurantIdentity'

export const RESTAURANT_LIST_TITLE_MAX_LENGTH = 60
export const RESTAURANT_LIST_DESCRIPTION_MAX_LENGTH = 240
export const RESTAURANT_LIST_ITEM_NOTE_MAX_LENGTH = 160

export type RestaurantListVisibilityContract = 'private' | 'friends' | 'public'
export type RestaurantListCoverModeContract = 'automatic' | 'custom'

export interface RestaurantListPlaceIdentityContractV1 {
  provider: RestaurantPlaceProvider
  externalId: string
  isPrimary: boolean
}

/**
 * Public-safe place snapshot carried by a list item. `globalKey` is the
 * provider-neutral identity key; `restaurantId` remains the owner's stable
 * Taste Map Restaurant reference when one exists. No user state or Visit data
 * is allowed in this projection.
 */
export interface RestaurantListPlaceContractV1 {
  globalKey: string
  restaurantId: string
  placeIdentities: RestaurantListPlaceIdentityContractV1[]
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  markerPhotoId: string | null
  merchantImageUrl: string | null
  markerEmoji: string
}

export interface RestaurantListSyncContractV1 {
  schemaVersion: 1
  id: string
  userId: string
  title: string
  description: string
  visibility: RestaurantListVisibilityContract
  isRanked: boolean
  coverMode: RestaurantListCoverModeContract
  customCoverPhotoId: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface RestaurantListItemSyncContractV1 {
  schemaVersion: 1
  id: string
  userId: string
  listId: string
  restaurantId: string
  restaurantGlobalKey: string
  position: number
  note: string
  restaurant: RestaurantListPlaceContractV1
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export class RestaurantListContractError extends Error {}

export function decodeRestaurantListSyncContract(value: unknown): RestaurantListSyncContractV1 {
  if (!isRecord(value) || value.schemaVersion !== 1 || !isNonBlank(value.id) ||
    !isNonBlank(value.userId) || !isISODateTime(value.createdAt) ||
    !isISODateTime(value.updatedAt) || !isNullableISODateTime(value.deletedAt)) {
    throw new RestaurantListContractError('RestaurantList contract is invalid.')
  }
  const title = typeof value.title === 'string' ? value.title.trim() : ''
  if (!title || [...title].length > RESTAURANT_LIST_TITLE_MAX_LENGTH) {
    throw new RestaurantListContractError('RestaurantList title must contain 1-60 Unicode characters.')
  }
  const description = typeof value.description === 'string' ? value.description.trim() : ''
  if ([...description].length > RESTAURANT_LIST_DESCRIPTION_MAX_LENGTH) {
    throw new RestaurantListContractError('RestaurantList description is too long.')
  }
  if (value.visibility !== 'private' && value.visibility !== 'friends' && value.visibility !== 'public') {
    throw new RestaurantListContractError('RestaurantList visibility is invalid.')
  }
  if (value.coverMode !== 'automatic' && value.coverMode !== 'custom') {
    throw new RestaurantListContractError('RestaurantList coverMode is invalid.')
  }
  if (typeof value.isRanked !== 'boolean' ||
    (value.customCoverPhotoId !== null && typeof value.customCoverPhotoId !== 'string')) {
    throw new RestaurantListContractError('RestaurantList options are invalid.')
  }
  return { ...value, title, description } as RestaurantListSyncContractV1
}

export function decodeRestaurantListItemSyncContract(value: unknown): RestaurantListItemSyncContractV1 {
  if (!isRecord(value) || value.schemaVersion !== 1 || !isNonBlank(value.id) ||
    !isNonBlank(value.userId) || !isNonBlank(value.listId) || !isNonBlank(value.restaurantId) ||
    !isNonBlank(value.restaurantGlobalKey) || !Number.isInteger(value.position) ||
    Number(value.position) < 0 || !isISODateTime(value.createdAt) ||
    !isISODateTime(value.updatedAt) || !isNullableISODateTime(value.deletedAt)) {
    throw new RestaurantListContractError('RestaurantListItem contract is invalid.')
  }
  const note = typeof value.note === 'string' ? value.note.trim() : ''
  if ([...note].length > RESTAURANT_LIST_ITEM_NOTE_MAX_LENGTH) {
    throw new RestaurantListContractError('RestaurantListItem note is too long.')
  }
  const restaurant = decodeRestaurantListPlace(value.restaurant)
  if (restaurant.globalKey !== value.restaurantGlobalKey || restaurant.restaurantId !== value.restaurantId) {
    throw new RestaurantListContractError('RestaurantListItem place identity does not match its reference.')
  }
  return { ...value, note, restaurant } as RestaurantListItemSyncContractV1
}

export function decodeRestaurantListPlace(value: unknown): RestaurantListPlaceContractV1 {
  if (!isRecord(value) || !isNonBlank(value.globalKey) || !isNonBlank(value.restaurantId) ||
    !isNonBlank(value.name) || typeof value.address !== 'string' || typeof value.city !== 'string' ||
    !isCoordinate(value.latitude, -90, 90) || !isCoordinate(value.longitude, -180, 180) ||
    !Array.isArray(value.placeIdentities) || value.placeIdentities.length === 0 ||
    !value.placeIdentities.every(isPlaceIdentity) ||
    (value.markerPhotoId !== null && typeof value.markerPhotoId !== 'string') ||
    (value.merchantImageUrl !== null && typeof value.merchantImageUrl !== 'string') ||
    typeof value.markerEmoji !== 'string') {
    throw new RestaurantListContractError('RestaurantList place projection is invalid.')
  }
  if (!value.placeIdentities.some((identity) => identity.isPrimary)) {
    throw new RestaurantListContractError('RestaurantList place requires a primary external identity.')
  }
  return value as unknown as RestaurantListPlaceContractV1
}

function isPlaceIdentity(value: unknown): value is RestaurantListPlaceIdentityContractV1 {
  if (!isRecord(value) || !isNonBlank(value.externalId) || typeof value.isPrimary !== 'boolean') return false
  return ['amap', 'apple_maps', 'manual', 'other'].includes(String(value.provider))
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

function isNonBlank(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isISODateTime(value: unknown): value is string {
  return isNonBlank(value) && Number.isFinite(Date.parse(value))
}

function isNullableISODateTime(value: unknown): value is string | null {
  return value === null || isISODateTime(value)
}

function isCoordinate(value: unknown, minimum: number, maximum: number) {
  return typeof value === 'number' && Number.isFinite(value) && value >= minimum && value <= maximum
}
