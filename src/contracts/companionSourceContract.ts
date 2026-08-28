export const RECOMMENDATION_SOURCE_TYPES = [
  'friend',
  'xiaohongshu',
  'douyin',
  'dianping',
  'blogger',
  'self',
  'other',
] as const

export type RecommendationSourceContractType = typeof RECOMMENDATION_SOURCE_TYPES[number]

export interface DiningCompanionSyncContractV1 {
  schemaVersion: 1
  id: string
  userId: string
  displayName: string
  linkedTasteMapUserId: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface RecommendationSourceSyncContractV1 {
  schemaVersion: 1
  id: string
  userId: string
  displayName: string
  sourceType: RecommendationSourceContractType
  linkedTasteMapUserId: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export function decodeDiningCompanionSyncContract(value: unknown): DiningCompanionSyncContractV1 {
  if (!isRecord(value) || value.schemaVersion !== 1 ||
    !isBoundedNonBlank(value.id, 200) || !isBoundedNonBlank(value.userId, 200) ||
    !isBoundedNonBlank(value.displayName, 100) ||
    !isNullableBoundedString(value.linkedTasteMapUserId, 200) ||
    !isDate(value.createdAt) || !isDate(value.updatedAt) || !isNullableDate(value.deletedAt)) {
    throw new Error('Dining companion sync contract is invalid.')
  }
  return {
    schemaVersion: 1,
    id: value.id,
    userId: value.userId,
    displayName: normalizedDisplayName(value.displayName),
    linkedTasteMapUserId: normalizedNullable(value.linkedTasteMapUserId),
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    deletedAt: value.deletedAt,
  }
}

export function decodeRecommendationSourceSyncContract(value: unknown): RecommendationSourceSyncContractV1 {
  if (!isRecord(value) || value.schemaVersion !== 1 ||
    !isBoundedNonBlank(value.id, 200) || !isBoundedNonBlank(value.userId, 200) ||
    !isBoundedNonBlank(value.displayName, 160) ||
    !RECOMMENDATION_SOURCE_TYPES.includes(value.sourceType as RecommendationSourceContractType) ||
    !isNullableBoundedString(value.linkedTasteMapUserId, 200) ||
    !isDate(value.createdAt) || !isDate(value.updatedAt) || !isNullableDate(value.deletedAt)) {
    throw new Error('Recommendation source sync contract is invalid.')
  }
  return {
    schemaVersion: 1,
    id: value.id,
    userId: value.userId,
    displayName: normalizedDisplayName(value.displayName),
    sourceType: value.sourceType as RecommendationSourceContractType,
    linkedTasteMapUserId: normalizedNullable(value.linkedTasteMapUserId),
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    deletedAt: value.deletedAt,
  }
}

export function normalizedPrivateDirectoryName(value: string) {
  return normalizedDisplayName(value).normalize('NFKC')
}

function normalizedDisplayName(value: string) {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ')
}

function normalizedNullable(value: unknown) {
  if (typeof value !== 'string') return null
  const normalized = normalizedDisplayName(value)
  return normalized || null
}

function isBoundedNonBlank(value: unknown, maximum: number): value is string {
  return typeof value === 'string' && normalizedDisplayName(value).length > 0 && normalizedDisplayName(value).length <= maximum
}

function isNullableBoundedString(value: unknown, maximum: number) {
  return value === null || (typeof value === 'string' && value.trim().length > 0 && value.trim().length <= maximum)
}

function isDate(value: unknown): value is string {
  return typeof value === 'string' && Number.isFinite(Date.parse(value))
}

function isNullableDate(value: unknown) {
  return value === null || isDate(value)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}
