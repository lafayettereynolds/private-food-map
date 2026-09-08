import type { Restaurant } from '../types/domain'
import type { RestaurantPlaceIdentity, RestaurantPlaceProvider } from '../types/restaurantIdentity'

export const RESTAURANT_CONTRACT_VERSION = 1 as const

export interface RestaurantJSONContractV1 {
  schemaVersion: typeof RESTAURANT_CONTRACT_VERSION
  id: string
  userId: string
  placeIdentities: RestaurantPlaceIdentity[]
  /** Transitional Web compatibility only. New clients use placeIdentities. */
  amapPoiId?: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  status: Restaurant['status']
  preferenceLevel: Restaurant['preferenceLevel']
  overallRating: number | null
  foodRating: number | null
  environmentRating: number | null
  serviceRating: number | null
  valueRating: number | null
  tags: string[]
  longTermNote: string
  pricePerPerson: number | null
  phone: string | null
  websiteUrl?: string | null
  openingHours: string | null
  markerType: Restaurant['markerType']
  markerPhotoId: string | null
  merchantImageUrl: string | null
  markerEmoji: string
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  isTestData?: boolean
}

const providers = new Set<RestaurantPlaceProvider>(['amap', 'apple_maps', 'manual', 'other'])
const statuses = new Set<Restaurant['status']>(['visited', 'wantToGo'])
const preferences = new Set<Restaurant['preferenceLevel']>(['favorite', 'like', 'normal', 'avoid'])
const markerTypes = new Set<Restaurant['markerType']>(['image', 'emoji'])

const requiredStringKeys = [
  'id', 'userId', 'name', 'address', 'city', 'status', 'preferenceLevel',
  'longTermNote', 'markerType', 'markerEmoji', 'createdAt', 'updatedAt',
] as const
const requiredNumberKeys = ['latitude', 'longitude'] as const
const requiredNullableNumberKeys = [
  'overallRating', 'foodRating', 'environmentRating', 'serviceRating',
  'valueRating', 'pricePerPerson',
] as const
const requiredNullableStringKeys = [
  'phone', 'openingHours', 'markerPhotoId', 'merchantImageUrl', 'deletedAt',
] as const
const allowedKeys = new Set([
  'schemaVersion', 'id', 'userId', 'placeIdentities', 'amapPoiId', 'name',
  'address', 'city', 'latitude', 'longitude', 'status', 'preferenceLevel',
  'overallRating', 'foodRating', 'environmentRating', 'serviceRating',
  'valueRating', 'tags', 'longTermNote', 'pricePerPerson', 'phone',
  'websiteUrl', 'openingHours', 'markerType', 'markerPhotoId', 'merchantImageUrl',
  'markerEmoji', 'createdAt', 'updatedAt', 'deletedAt', 'isTestData',
])
const legacyAllowedKeys = new Set([...allowedKeys].filter((key) => !['schemaVersion', 'placeIdentities'].includes(key)))

export class RestaurantContractError extends Error {}

export function restaurantToJSONContract(
  restaurant: Restaurant,
  identities: RestaurantPlaceIdentity[] = restaurant.placeIdentities ?? [],
): RestaurantJSONContractV1 & { amapPoiId: string } {
  const placeIdentities = normalizeRestaurantPlaceIdentities(
    identities,
    restaurant.amapPoiId,
    restaurant.createdAt,
    restaurant.updatedAt,
  )
  return {
    schemaVersion: RESTAURANT_CONTRACT_VERSION,
    id: restaurant.id,
    userId: restaurant.userId,
    placeIdentities,
    amapPoiId: restaurant.amapPoiId,
    name: restaurant.name,
    address: restaurant.address,
    city: restaurant.city,
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    status: restaurant.status,
    preferenceLevel: restaurant.preferenceLevel,
    overallRating: restaurant.overallRating,
    foodRating: restaurant.foodRating,
    environmentRating: restaurant.environmentRating,
    serviceRating: restaurant.serviceRating,
    valueRating: restaurant.valueRating,
    tags: restaurant.tags,
    longTermNote: restaurant.longTermNote,
    pricePerPerson: restaurant.pricePerPerson,
    phone: restaurant.phone ?? null,
    websiteUrl: restaurant.websiteUrl ?? null,
    openingHours: restaurant.openingHours ?? null,
    markerType: restaurant.markerType,
    markerPhotoId: restaurant.markerPhotoId ?? null,
    merchantImageUrl: restaurant.merchantImageUrl,
    markerEmoji: restaurant.markerEmoji,
    createdAt: restaurant.createdAt,
    updatedAt: restaurant.updatedAt,
    deletedAt: restaurant.deletedAt,
    ...(restaurant.isTestData === undefined ? {} : { isTestData: restaurant.isTestData }),
  }
}

export function decodeRestaurantJSONContract(value: unknown): RestaurantJSONContractV1 {
  if (!isRecord(value)) throw new RestaurantContractError('Restaurant contract must be a JSON object.')
  if (!('schemaVersion' in value)) return decodeLegacyRestaurantJSON(value)
  if (value.schemaVersion !== RESTAURANT_CONTRACT_VERSION) {
    throw new RestaurantContractError(`Unsupported Restaurant schemaVersion: ${String(value.schemaVersion)}`)
  }
  assertAllowedKeys(value)
  assertCommonRestaurantFields(value)
  if (!Array.isArray(value.placeIdentities) || value.placeIdentities.length === 0) {
    throw new RestaurantContractError('placeIdentities is required and cannot be empty.')
  }
  const placeIdentities = value.placeIdentities.map(decodeRestaurantPlaceIdentity)
  assertPrimaryIdentity(placeIdentities)
  if ('amapPoiId' in value && !isNonEmptyString(value.amapPoiId)) {
    throw new RestaurantContractError('amapPoiId must be a non-empty string when present.')
  }
  if ('isTestData' in value && typeof value.isTestData !== 'boolean') {
    throw new RestaurantContractError('isTestData must be boolean when present.')
  }
  if ('websiteUrl' in value && value.websiteUrl !== null && typeof value.websiteUrl !== 'string') {
    throw new RestaurantContractError('websiteUrl must be a string or null when present.')
  }
  if (typeof value.websiteUrl === 'string' && !isSafeWebsiteURL(value.websiteUrl)) {
    throw new RestaurantContractError('websiteUrl must use http or https when present.')
  }
  return { ...value, placeIdentities } as unknown as RestaurantJSONContractV1
}

export function decodeLegacyRestaurantJSON(value: Record<string, unknown>): RestaurantJSONContractV1 {
  assertAllowedKeys(value, legacyAllowedKeys)
  assertCommonRestaurantFields(value)
  if (!isNonEmptyString(value.amapPoiId)) {
    throw new RestaurantContractError('Legacy Restaurant requires a non-empty amapPoiId.')
  }
  if ('isTestData' in value && typeof value.isTestData !== 'boolean') {
    throw new RestaurantContractError('isTestData must be boolean when present.')
  }
  return {
    ...(value as unknown as Omit<RestaurantJSONContractV1, 'schemaVersion' | 'placeIdentities'>),
    schemaVersion: RESTAURANT_CONTRACT_VERSION,
    placeIdentities: [{
      provider: 'amap',
      externalId: value.amapPoiId,
      isPrimary: true,
      createdAt: value.createdAt as string,
      updatedAt: value.updatedAt as string,
    }],
  }
}

export function normalizeRestaurantPlaceIdentities(
  identities: RestaurantPlaceIdentity[],
  legacyAmapPoiId: string | undefined,
  createdAt: string,
  updatedAt: string,
) {
  const candidates = identities.length > 0
    ? identities
    : legacyAmapPoiId?.trim()
      ? [{ provider: 'amap' as const, externalId: legacyAmapPoiId, isPrimary: true, createdAt, updatedAt }]
      : []
  const deduplicated = new Map<string, RestaurantPlaceIdentity>()
  candidates.forEach((identity) => {
    const decoded = decodeRestaurantPlaceIdentity(identity)
    deduplicated.set(restaurantPlaceIdentityKey(decoded.provider, decoded.externalId), decoded)
  })
  const result = [...deduplicated.values()]
  if (result.length === 0) throw new RestaurantContractError('Restaurant requires at least one provider identity.')
  const primaryIndex = result.findIndex((identity) => identity.isPrimary)
  return result.map((identity, index) => ({ ...identity, isPrimary: index === (primaryIndex < 0 ? 0 : primaryIndex) }))
}

export function restaurantPlaceIdentityKey(provider: RestaurantPlaceProvider, externalId: string) {
  return `${provider}:${externalId.trim()}`
}

function decodeRestaurantPlaceIdentity(value: unknown): RestaurantPlaceIdentity {
  if (!isRecord(value) || !providers.has(value.provider as RestaurantPlaceProvider) ||
    !isNonEmptyString(value.externalId) || typeof value.isPrimary !== 'boolean' ||
    !isNonEmptyString(value.createdAt) || !isNonEmptyString(value.updatedAt)) {
    throw new RestaurantContractError('Restaurant provider identity is invalid.')
  }
  const keys = Object.keys(value)
  if (keys.some((key) => !['provider', 'externalId', 'isPrimary', 'createdAt', 'updatedAt'].includes(key))) {
    throw new RestaurantContractError('Restaurant provider identity contains unknown fields.')
  }
  return {
    provider: value.provider as RestaurantPlaceProvider,
    externalId: value.externalId.trim(),
    isPrimary: value.isPrimary,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
  }
}

function assertCommonRestaurantFields(value: Record<string, unknown>) {
  requiredStringKeys.forEach((key) => {
    if (!isNonEmptyString(value[key]) && !['address', 'city', 'longTermNote'].includes(key)) {
      throw new RestaurantContractError(`${key} is required and must be a non-empty string.`)
    }
    if (['address', 'city', 'longTermNote'].includes(key) && typeof value[key] !== 'string') {
      throw new RestaurantContractError(`${key} is required and must be a string.`)
    }
  })
  requiredNumberKeys.forEach((key) => {
    if (typeof value[key] !== 'number' || !Number.isFinite(value[key])) {
      throw new RestaurantContractError(`${key} is required and must be finite.`)
    }
  })
  requiredNullableNumberKeys.forEach((key) => {
    if (!(key in value) || (value[key] !== null && (typeof value[key] !== 'number' || !Number.isFinite(value[key])))) {
      throw new RestaurantContractError(`${key} is required and must be a number or null.`)
    }
  })
  requiredNullableStringKeys.forEach((key) => {
    if (!(key in value) || (value[key] !== null && typeof value[key] !== 'string')) {
      throw new RestaurantContractError(`${key} is required and must be a string or null.`)
    }
  })
  if (!statuses.has(value.status as Restaurant['status']) ||
    !preferences.has(value.preferenceLevel as Restaurant['preferenceLevel']) ||
    !markerTypes.has(value.markerType as Restaurant['markerType'])) {
    throw new RestaurantContractError('Restaurant contains an unsupported enum value.')
  }
  if (!Array.isArray(value.tags) || value.tags.some((tag) => typeof tag !== 'string')) {
    throw new RestaurantContractError('tags is required and must contain only strings.')
  }
}

function assertAllowedKeys(value: Record<string, unknown>, keys = allowedKeys) {
  const unknownKey = Object.keys(value).find((key) => !keys.has(key))
  if (unknownKey) throw new RestaurantContractError(`Unknown Restaurant field: ${unknownKey}`)
}

function assertPrimaryIdentity(identities: RestaurantPlaceIdentity[]) {
  if (identities.filter((identity) => identity.isPrimary).length !== 1) {
    throw new RestaurantContractError('Restaurant requires exactly one primary provider identity.')
  }
  const keys = identities.map((identity) => restaurantPlaceIdentityKey(identity.provider, identity.externalId))
  if (new Set(keys).size !== keys.length) throw new RestaurantContractError('Restaurant provider identities must be unique.')
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isSafeWebsiteURL(value: string) {
  try {
    const url = new URL(value)
    return (url.protocol === 'http:' || url.protocol === 'https:') && Boolean(url.hostname)
  } catch {
    return false
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}
