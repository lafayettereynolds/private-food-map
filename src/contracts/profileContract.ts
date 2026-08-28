export const PROFILE_SCHEMA_VERSION = 1 as const
export const PROFILE_API_VERSION = 1 as const
// New edits are capped at 30 Unicode code points. A wider wire ceiling keeps
// untouched legacy Web nicknames lossless during the additive migration.
export const PROFILE_WIRE_DISPLAY_NAME_MAX_LENGTH = 200 as const

export const PROFILE_VISIBILITIES = ['private', 'friends', 'public'] as const
export const AVATAR_PRESET_IDS = [
  'polar-bear', 'penguin', 'cat', 'dog',
  'parrot', 'dinosaur', 'shiba', 'panda',
  'otter', 'hedgehog', 'rabbit', 'koala',
  'fox', 'raccoon', 'deer', 'whale',
] as const

export type ProfileVisibilityContract = typeof PROFILE_VISIBILITIES[number]
export type ProfileAvatarPresetContract = typeof AVATAR_PRESET_IDS[number]

/**
 * Private, owner-scoped sync record. Every key is required; nullable values
 * are explicitly represented by null so Swift and TypeScript never infer
 * clear-vs-omitted semantics independently.
 */
export interface OwnProfileSyncContractV1 {
  schemaVersion: typeof PROFILE_SCHEMA_VERSION
  userId: string
  displayName: string
  bio: string
  city: string
  avatarPhotoId: string | null
  avatarPresetId: ProfileAvatarPresetContract
  visibility: ProfileVisibilityContract
  createdAt: string
  updatedAt: string
  deletedAt: null
}

export interface PublicProfileStatisticsV1 {
  publicRestaurantCount: number
  publicVisitCount: number
}

/** Deliberate allowlist. Auth, email, sessions, private records and storage keys are absent. */
export interface PublicUserProfileV1 {
  apiVersion: typeof PROFILE_API_VERSION
  userId: string
  displayName: string
  bio: string | null
  city: string | null
  avatarPhotoId: string | null
  avatarPresetId: ProfileAvatarPresetContract
  joinedAt: string
  statistics: PublicProfileStatisticsV1
}

export class ProfileContractError extends Error {}

export function decodeOwnProfileSyncContract(value: unknown): OwnProfileSyncContractV1 {
  if (!isRecord(value) || !hasExactKeys(value, [
    'schemaVersion', 'userId', 'displayName', 'bio', 'city', 'avatarPhotoId',
    'avatarPresetId', 'visibility', 'createdAt', 'updatedAt', 'deletedAt',
  ]) || value.schemaVersion !== PROFILE_SCHEMA_VERSION ||
    !isNonBlank(value.userId) ||
    !isBoundedRequired(value.displayName, PROFILE_WIRE_DISPLAY_NAME_MAX_LENGTH) ||
    !isBoundedString(value.bio, 160) || !isBoundedString(value.city, 30) ||
    !isNullableNonBlank(value.avatarPhotoId) ||
    !AVATAR_PRESET_IDS.includes(value.avatarPresetId as ProfileAvatarPresetContract) ||
    !PROFILE_VISIBILITIES.includes(value.visibility as ProfileVisibilityContract) ||
    !isISODate(value.createdAt) || !isISODate(value.updatedAt) || value.deletedAt !== null) {
    throw new ProfileContractError('Own Profile sync contract is invalid.')
  }
  return {
    schemaVersion: PROFILE_SCHEMA_VERSION,
    userId: value.userId.trim(),
    displayName: value.displayName.trim(),
    bio: value.bio.trim(),
    city: value.city.trim(),
    avatarPhotoId: value.avatarPhotoId,
    avatarPresetId: value.avatarPresetId as ProfileAvatarPresetContract,
    visibility: value.visibility as ProfileVisibilityContract,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    deletedAt: null,
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

function hasExactKeys(value: Record<string, unknown>, expected: string[]) {
  const keys = Object.keys(value)
  return keys.length === expected.length && expected.every((key) => keys.includes(key))
}

function isNonBlank(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isBoundedRequired(value: unknown, maximum: number): value is string {
  return isNonBlank(value) && [...value.trim()].length <= maximum
}

function isBoundedString(value: unknown, maximum: number): value is string {
  return typeof value === 'string' && [...value.trim()].length <= maximum
}

function isNullableNonBlank(value: unknown): value is string | null {
  return value === null || isNonBlank(value)
}

function isISODate(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(Date.parse(value))
}
