export const TASTE_MAP_BACKUP_FORMAT = 'com.tastemap.backup' as const
export const TASTE_MAP_BACKUP_SCHEMA_VERSION = 1 as const
export const TASTE_MAP_BACKUP_CANONICALIZATION = 'tastemap-backup-v1' as const
export const TASTE_MAP_BACKUP_INTEGRITY_ALGORITHM = 'sha256' as const

export const BACKUP_ENTITY_TYPES = [
  'restaurant',
  'visit',
  'dish',
  'visitDish',
  'photo',
  'companion',
  'recommendationSource',
  'profile',
  'restaurantList',
  'restaurantListItem',
] as const

export type BackupEntityTypeV1 = typeof BACKUP_ENTITY_TYPES[number]
export type BackupVisibilityV1 = 'private' | 'friends' | 'public'
export type BackupRestaurantStatusV1 = 'visited' | 'wantToGo'
export type BackupRestaurantPreferenceV1 = 'favorite' | 'like' | 'normal' | 'avoid'
export type BackupPlaceProviderV1 = 'amap' | 'apple_maps' | 'manual' | 'other'
export type BackupPhotoKindV1 = 'restaurant-marker' | 'visit' | 'dish' | 'avatar'
export type BackupRecommendationSourceTypeV1 =
  | 'friend'
  | 'xiaohongshu'
  | 'douyin'
  | 'dianping'
  | 'blogger'
  | 'self'
  | 'other'

/**
 * UTC ISO-8601 instant with exactly millisecond precision:
 * YYYY-MM-DDTHH:mm:ss.SSSZ. It never stores an inferred original timezone.
 */
export type BackupTimestampV1 = string

/**
 * Non-negative decimal money encoded as a JSON string with exactly two
 * fractional digits. It is never encoded as a JSON number.
 */
export type BackupMoneyV1 = string

export interface BackupSourceV1 {
  platform: 'ios' | 'web'
  appVersion: string
  appBuild: string
  environment: 'development' | 'production'
}

export interface BackupScopeV1 {
  kind: 'user-data'
  includesPhotoBinaries: false
}

export interface BackupPlaceIdentityV1 {
  provider: BackupPlaceProviderV1
  externalId: string
  isPrimary: boolean
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

/** `id` is a stable backup identity, not a provider ID or ownership proof. */
export interface BackupRestaurantV1 {
  id: string
  placeIdentities: BackupPlaceIdentityV1[]
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  status: BackupRestaurantStatusV1
  preferenceLevel: BackupRestaurantPreferenceV1
  overallRating: number | null
  foodRating: number | null
  environmentRating: number | null
  serviceRating: number | null
  valueRating: number | null
  tags: string[]
  longTermNote: string
  pricePerPerson: BackupMoneyV1 | null
  phone: string | null
  openingHours: string | null
  markerType: 'image' | 'emoji'
  markerPhotoId: string | null
  merchantImageUrl: string | null
  markerEmoji: string
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

export interface BackupVisitV1 {
  id: string
  restaurantId: string
  visitedAt: BackupTimestampV1
  diningMode: 'dine_in' | 'takeout'
  visibility: BackupVisibilityV1
  partySize: number | null
  totalPrice: BackupMoneyV1 | null
  myActualSpend: BackupMoneyV1 | null
  paymentMode: 'aa' | 'my_treat' | 'treated' | 'separate' | 'other' | null
  pricePerPerson: BackupMoneyV1 | null
  queueDuration: 'none' | 'under15' | 'under30' | 'under60' | 'under90' | 'under120' | 'over120' | null
  diningOccasions: Array<'solo' | 'date' | 'friends' | 'family' | 'business' | 'celebration' | 'other'>
  diningOccasionText: string | null
  rating: number | null
  valueRating: number | null
  environmentRating: number | null
  serviceRating: number | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: 'quiet' | 'normal' | 'loud' | 'very_loud' | null
  diningDuration: 'under15' | 'under30' | 'under45' | 'under60' | 'under90' | 'under120' | 'over120' | null
  portionLevel: 'small' | 'normal' | 'generous' | null
  transportConvenience: 'very_convenient' | 'convenient' | 'normal' | 'inconvenient' | null
  specialNotes: string | null
  companionIds: string[]
  recommendationSourceId: string | null
  recommendationSourceType: BackupRecommendationSourceTypeV1 | null
  recommendationSourceText: string | null
  /** Non-authoritative; Import cannot recreate shared-meal acceptance from it. */
  sharedMealReferenceHint: string | null
  note: string | null
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

/** Restaurant-level identity. `originVisitId` preserves the current legacy origin only. */
export interface BackupDishV1 {
  id: string
  restaurantId: string
  originVisitId: string
  name: string
  taste: string
  rating: number | null
  price: BackupMoneyV1 | null
  photoId: string | null
  sortOrder: number
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

export interface BackupVisitDishV1 {
  id: string
  restaurantId: string
  visitId: string
  dishId: string
  sortOrder: number
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

export interface BackupPhotoParentV1 {
  entityType: 'restaurant' | 'visit' | 'dish' | 'profile'
  entityId: string
}

/** Metadata only. No provider locator, local path, retry state, or binary. */
export interface BackupPhotoV1 {
  id: string
  parent: BackupPhotoParentV1
  kind: BackupPhotoKindV1
  fileName: string | null
  mimeType: string
  byteSize: number
  width: number | null
  height: number | null
  sortOrder: number
  visibility: BackupVisibilityV1
  contentSha256: string | null
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

/** Private user-authored directory entry; linked user authority is intentionally absent. */
export interface BackupDiningCompanionV1 {
  id: string
  displayName: string
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

/** Private user-authored directory entry; linked user authority is intentionally absent. */
export interface BackupRecommendationSourceV1 {
  id: string
  displayName: string
  sourceType: BackupRecommendationSourceTypeV1
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

/** Presentation allowlist only. Taste Map user/auth/entitlement identity is absent. */
export interface BackupUserProfileV1 {
  id: string
  displayName: string
  bio: string
  city: string
  avatarPhotoId: string | null
  avatarPresetId:
    | 'polar-bear' | 'penguin' | 'cat' | 'dog'
    | 'parrot' | 'dinosaur' | 'shiba' | 'panda'
    | 'otter' | 'hedgehog' | 'rabbit' | 'koala'
    | 'fox' | 'raccoon' | 'deer' | 'whale'
  visibility: BackupVisibilityV1
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

export interface BackupRestaurantListV1 {
  id: string
  title: string
  description: string
  visibility: BackupVisibilityV1
  isRanked: boolean
  coverMode: 'automatic' | 'custom'
  customCoverPhotoId: string | null
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

export interface BackupRestaurantListPlaceIdentityV1 {
  provider: BackupPlaceProviderV1
  externalId: string
  isPrimary: boolean
}

export interface BackupRestaurantListPlaceV1 {
  globalKey: string
  restaurantId: string
  placeIdentities: BackupRestaurantListPlaceIdentityV1[]
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  markerPhotoId: string | null
  merchantImageUrl: string | null
  markerEmoji: string
}

export interface BackupRestaurantListItemV1 {
  id: string
  listId: string
  restaurantId: string
  restaurantGlobalKey: string
  position: number
  note: string
  restaurant: BackupRestaurantListPlaceV1
  createdAt: BackupTimestampV1
  updatedAt: BackupTimestampV1
}

export interface BackupEntitiesV1 {
  restaurants: BackupRestaurantV1[]
  visits: BackupVisitV1[]
  dishes: BackupDishV1[]
  visitDishes: BackupVisitDishV1[]
  photos: BackupPhotoV1[]
  companions: BackupDiningCompanionV1[]
  recommendationSources: BackupRecommendationSourceV1[]
  profiles: BackupUserProfileV1[]
  restaurantLists: BackupRestaurantListV1[]
  restaurantListItems: BackupRestaurantListItemV1[]
}

/** Negative evidence only. It never authorizes a remote delete. */
export interface BackupTombstoneV1 {
  entityType: BackupEntityTypeV1
  id: string
  deletedAt: BackupTimestampV1
}

export interface BackupEntityCountsV1 {
  restaurants: number
  visits: number
  dishes: number
  visitDishes: number
  photos: number
  companions: number
  recommendationSources: number
  profiles: number
  restaurantLists: number
  restaurantListItems: number
}

export interface BackupMetadataV1 {
  entityCounts: BackupEntityCountsV1
  tombstoneCount: number
}

export interface BackupIntegrityV1 {
  canonicalization: typeof TASTE_MAP_BACKUP_CANONICALIZATION
  algorithm: typeof TASTE_MAP_BACKUP_INTEGRITY_ALGORITHM
  digest: string
}

export interface BackupEnvelopeV1 {
  format: typeof TASTE_MAP_BACKUP_FORMAT
  schemaVersion: typeof TASTE_MAP_BACKUP_SCHEMA_VERSION
  exportId: string
  exportedAt: BackupTimestampV1
  source: BackupSourceV1
  scope: BackupScopeV1
  entities: BackupEntitiesV1
  tombstones: BackupTombstoneV1[]
  metadata: BackupMetadataV1
  integrity: BackupIntegrityV1
}

export type BackupIntegrityPayloadV1 = Omit<BackupEnvelopeV1, 'integrity'>

/** The digest covers every top-level field except `integrity`. */
export function backupIntegrityPayloadV1(envelope: BackupEnvelopeV1): BackupIntegrityPayloadV1 {
  const { integrity: _integrity, ...payload } = envelope
  return payload
}

/**
 * Contract primitive, not an exporter. It applies recursive lexical object-key
 * ordering while preserving array order. Entity/set sorting remains an exporter
 * precondition documented by `tastemap-backup-v1`.
 */
export function canonicalizeBackupJSONV1(value: unknown): string {
  if (value === null) return 'null'
  if (typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value)
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new TypeError('Backup canonical JSON rejects non-finite numbers.')
    return JSON.stringify(value)
  }
  if (Array.isArray(value)) return `[${value.map(canonicalizeBackupJSONV1).join(',')}]`
  if (typeof value === 'object') {
    const record = value as Record<string, unknown>
    return `{${Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalizeBackupJSONV1(record[key])}`
    ).join(',')}}`
  }
  throw new TypeError(`Backup canonical JSON rejects ${typeof value}.`)
}

export async function sha256HexV1(canonicalJSON: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalJSON))
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('')
}
