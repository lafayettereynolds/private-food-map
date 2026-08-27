import {
  SYNC_API_VERSION,
  SYNC_SCHEMA_VERSION,
  SyncContractError,
  decodeSyncPushRequest,
  stableSyncMutationJSON,
  type SyncEntityType,
  type SyncMutationAcknowledgementV1,
  type SyncMutationV1,
  type SyncPullResponseV1,
  type SyncPushResponseV1,
  type VisitSyncContractV1,
} from '../src/contracts/syncV1'
import type { RestaurantJSONContractV1 } from '../src/contracts/restaurantContract'
import type { RestaurantPlaceIdentity } from '../src/types/restaurantIdentity'
import { groupRestaurantPlaceIdentities, type RestaurantPlaceIdentityRow } from './restaurantIdentityMapping'

const MAX_PULL_LIMIT = 200

interface VersionedEntityRow {
  id: string
  user_id: string
  server_version: number
  deleted_at: string | null
  last_mutation_id: string | null
}

interface ChangeRow {
  revision: number
  user_id: string
  entity_type: SyncEntityType
  entity_id: string
  operation: 'upsert' | 'delete'
  server_version: number
  mutation_id: string
  changed_at: string
}

interface ReceiptRow {
  user_id: string
  mutation_id: string
  request_fingerprint: string
  entity_type: SyncEntityType
  entity_id: string
  operation: 'upsert' | 'delete'
  status: 'applied' | 'conflict'
  server_version: number
  revision: number | null
  conflict_reason: string | null
  processed_at: string
}

interface SyncRestaurantRow extends VersionedEntityRow {
  amap_poi_id: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  status: RestaurantJSONContractV1['status']
  preference_level: RestaurantJSONContractV1['preferenceLevel']
  overall_rating: number | null
  food_rating: number | null
  environment_rating: number | null
  service_rating: number | null
  value_rating: number | null
  tags_json: string
  long_term_note: string
  price_per_person: number | null
  phone: string | null
  opening_hours: string | null
  marker_type: RestaurantJSONContractV1['markerType']
  marker_photo_id: string | null
  merchant_image_url: string | null
  marker_emoji: string
  created_at: string
  updated_at: string
  is_test_data: number
}

interface SyncVisitRow extends VersionedEntityRow {
  restaurant_id: string
  visited_at: string
  rating: number | null
  note: string
  my_actual_spend: number | null
  created_at: string
  updated_at: string
}

export class SyncV1RequestError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
    this.name = 'SyncV1RequestError'
  }
}

export async function handleSyncV1Push(
  database: D1Database,
  viewerId: string,
  request: Request,
): Promise<SyncPushResponseV1> {
  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (contentLength > 2_000_000) throw new SyncV1RequestError('Sync push payload is too large.', 413)
  const raw: unknown = await request.json().catch(() => {
    throw new SyncV1RequestError('Sync push body is not valid JSON.', 400)
  })
  let payload
  try {
    payload = decodeSyncPushRequest(raw)
  } catch (error) {
    throw new SyncV1RequestError(error instanceof Error ? error.message : 'Sync push contract is invalid.', 400)
  }

  const acknowledgements: SyncMutationAcknowledgementV1[] = []
  for (const mutation of payload.mutations) {
    acknowledgements.push(await applyMutation(database, viewerId, mutation))
  }
  return { apiVersion: SYNC_API_VERSION, acknowledgements, serverTime: new Date().toISOString() }
}

export async function handleSyncV1Pull(
  database: D1Database,
  viewerId: string,
  request: Request,
): Promise<SyncPullResponseV1> {
  const url = new URL(request.url)
  if (url.searchParams.get('schemaVersion') !== String(SYNC_SCHEMA_VERSION)) {
    throw new SyncV1RequestError('schemaVersion=1 is required.', 400)
  }
  const cursor = parseCursor(url.searchParams.get('cursor'))
  const requestedLimit = Number(url.searchParams.get('limit') ?? MAX_PULL_LIMIT)
  const limit = Number.isInteger(requestedLimit) && requestedLimit > 0
    ? Math.min(requestedLimit, MAX_PULL_LIMIT)
    : MAX_PULL_LIMIT
  const result = await database.prepare(`SELECT * FROM sync_change_log
    WHERE user_id = ? AND revision > ? ORDER BY revision ASC LIMIT ?`)
    .bind(viewerId, cursor, limit).all<ChangeRow>()
  const changes = result.results
  const latestInPage = new Map<string, ChangeRow>()
  changes.forEach((change) => latestInPage.set(`${change.entity_type}:${change.entity_id}`, change))

  const restaurants = [] as SyncPullResponseV1['restaurants']
  const visits = [] as SyncPullResponseV1['visits']
  const tombstones = [] as SyncPullResponseV1['tombstones']
  for (const change of latestInPage.values()) {
    if (change.entity_type === 'restaurant') {
      const row = await database.prepare('SELECT * FROM restaurants WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncRestaurantRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        const identities = await readPlaceIdentities(database, viewerId, row.id)
        restaurants.push({ serverVersion: row.server_version, record: rowToRestaurant(row, identities) })
      }
    } else {
      const row = await database.prepare('SELECT * FROM visits WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncVisitRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        visits.push({ serverVersion: row.server_version, record: rowToVisit(row) })
      }
    }
  }
  const includedRestaurantIDs = new Set(restaurants.map((item) => item.record.id))
  for (const visit of visits) {
    if (includedRestaurantIDs.has(visit.record.restaurantId)) continue
    const parent = await database.prepare('SELECT * FROM restaurants WHERE id = ? AND user_id = ?')
      .bind(visit.record.restaurantId, viewerId).first<SyncRestaurantRow>()
    if (!parent) throw new SyncV1RequestError(`Visit ${visit.record.id} has no Restaurant.`, 500)
    const identities = await readPlaceIdentities(database, viewerId, parent.id)
    restaurants.push({ serverVersion: parent.server_version, record: rowToRestaurant(parent, identities) })
    includedRestaurantIDs.add(parent.id)
  }

  return {
    apiVersion: SYNC_API_VERSION,
    schemaVersion: SYNC_SCHEMA_VERSION,
    restaurants,
    visits,
    tombstones,
    nextCursor: String(changes.at(-1)?.revision ?? cursor),
    hasMore: changes.length === limit,
    serverTime: new Date().toISOString(),
  }
}

export async function recordUnversionedSyncChanges(
  database: D1Database,
  changes: Array<{
    userId: string
    entityType: SyncEntityType
    entityId: string
    updatedAt: string
    deletedAt: string | null
  }>,
) {
  for (const change of changes) {
    const mutationId = `legacy:v0:${await sha256([
      change.userId, change.entityType, change.entityId, change.updatedAt, change.deletedAt ?? '',
    ].join(':'))}`
    const table = change.entityType === 'restaurant' ? 'restaurants' : 'visits'
    const operation = change.deletedAt ? 'delete' : 'upsert'
    const changedAt = new Date().toISOString()
    await database.batch([
      database.prepare(`UPDATE ${table}
        SET server_version = MAX(server_version, 0) + 1, last_mutation_id = ?
        WHERE id = ? AND user_id = ? AND updated_at = ?
          AND NOT EXISTS (
            SELECT 1 FROM sync_change_log WHERE user_id = ? AND mutation_id = ?
          )`)
        .bind(mutationId, change.entityId, change.userId, change.updatedAt, change.userId, mutationId),
      database.prepare(`INSERT INTO sync_change_log (
        user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
      )
      SELECT ?, ?, ?, ?, server_version, ?, ? FROM ${table}
      WHERE id = ? AND user_id = ? AND last_mutation_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM sync_change_log WHERE user_id = ? AND mutation_id = ?
        )`)
        .bind(change.userId, change.entityType, change.entityId, operation, mutationId, changedAt,
          change.entityId, change.userId, mutationId, change.userId, mutationId),
    ])
  }
}

async function applyMutation(database: D1Database, viewerId: string, mutation: SyncMutationV1) {
  const fingerprint = await sha256(stableSyncMutationJSON(mutation))
  const existingReceipt = await readReceipt(database, viewerId, mutation.mutationId)
  if (existingReceipt) return acknowledgement(existingReceipt, fingerprint, true)

  const current = await readEntityVersion(database, mutation.entityType, mutation.entityId)
  if (current && current.user_id !== viewerId) {
    throw new SyncV1RequestError('The authenticated user does not own this entity.', 403)
  }
  if (mutation.entityType === 'visit' && mutation.operation === 'upsert') {
    const visit = mutation.payload as VisitSyncContractV1
    const restaurant = await readEntityVersion(database, 'restaurant', visit.restaurantId)
    if (!restaurant || restaurant.user_id !== viewerId || restaurant.deleted_at) {
      throw new SyncV1RequestError('Visit.restaurantId must reference an active Restaurant owned by the authenticated user.', 403)
    }
  }
  const conflictReason = conflictForMutation(current, mutation)
  if (conflictReason) {
    return recordConflict(database, viewerId, mutation, fingerprint, current?.server_version ?? 0, conflictReason)
  }

  const nextVersion = (current?.server_version ?? 0) + 1
  const processedAt = new Date().toISOString()
  const statements = mutation.entityType === 'restaurant'
    ? restaurantMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
    : visitMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
  try {
    await database.batch(statements)
  } catch (error) {
    const receipt = await readReceipt(database, viewerId, mutation.mutationId)
    if (receipt) return acknowledgement(receipt, fingerprint, true)
    throw error
  }
  const receipt = await readReceipt(database, viewerId, mutation.mutationId)
  if (receipt) return acknowledgement(receipt, fingerprint, false)

  const latest = await readEntityVersion(database, mutation.entityType, mutation.entityId)
  return recordConflict(database, viewerId, mutation, fingerprint, latest?.server_version ?? 0, 'server_version_mismatch')
}

function conflictForMutation(current: VersionedEntityRow | null, mutation: SyncMutationV1) {
  if (!current) return mutation.operation === 'delete' ? 'missing_entity' : mutation.baseVersion === 0 ? null : 'server_version_mismatch'
  if (current.server_version !== mutation.baseVersion) return 'server_version_mismatch'
  if (current.deleted_at) return 'entity_deleted'
  return null
}

function restaurantMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, database.prepare(`
      UPDATE restaurants SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
      WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL
    `).bind(processedAt, processedAt, nextVersion, mutation.mutationId, mutation.entityId, viewerId, mutation.baseVersion))
  }
  const restaurant = mutation.payload as RestaurantJSONContractV1
  const entityStatement = database.prepare(`INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status, preference_level,
    overall_rating, food_rating, environment_rating, service_rating, value_rating, tags_json,
    long_term_note, price_per_person, phone, opening_hours, marker_type, marker_photo_id,
    merchant_image_url, marker_emoji, created_at, updated_at, deleted_at, is_test_data,
    server_version, last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    name = excluded.name, address = excluded.address, city = excluded.city,
    latitude = excluded.latitude, longitude = excluded.longitude, status = excluded.status,
    preference_level = excluded.preference_level, overall_rating = excluded.overall_rating,
    food_rating = excluded.food_rating, environment_rating = excluded.environment_rating,
    service_rating = excluded.service_rating, value_rating = excluded.value_rating,
    tags_json = excluded.tags_json, long_term_note = excluded.long_term_note,
    price_per_person = excluded.price_per_person, phone = excluded.phone,
    opening_hours = excluded.opening_hours, marker_type = excluded.marker_type,
    marker_photo_id = excluded.marker_photo_id, merchant_image_url = excluded.merchant_image_url,
    marker_emoji = excluded.marker_emoji, updated_at = excluded.updated_at,
    is_test_data = excluded.is_test_data, deleted_at = NULL,
    server_version = excluded.server_version, last_mutation_id = excluded.last_mutation_id
  WHERE restaurants.user_id = ? AND restaurants.server_version = ? AND restaurants.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, restaurant.amapPoiId ?? '', restaurant.name, restaurant.address,
      restaurant.city, restaurant.latitude, restaurant.longitude, restaurant.status, restaurant.preferenceLevel,
      restaurant.overallRating, restaurant.foodRating, restaurant.environmentRating, restaurant.serviceRating,
      restaurant.valueRating, JSON.stringify(restaurant.tags), restaurant.longTermNote,
      restaurant.pricePerPerson, restaurant.phone, restaurant.openingHours, restaurant.markerType,
      restaurant.markerPhotoId, restaurant.merchantImageUrl, restaurant.markerEmoji,
      restaurant.createdAt, restaurant.updatedAt, restaurant.isTestData ? 1 : 0,
      nextVersion, mutation.mutationId, viewerId, mutation.baseVersion,
    )
  const identityStatements = restaurant.placeIdentities.map((identity) => database.prepare(`
    INSERT INTO restaurant_place_identities (
      restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
    )
    SELECT ?, ?, ?, ?, ?, ?, ?
    WHERE EXISTS (SELECT 1 FROM restaurants WHERE id = ? AND user_id = ? AND last_mutation_id = ?)
    ON CONFLICT(restaurant_id, provider, external_id) DO UPDATE SET
      user_id = excluded.user_id, is_primary = excluded.is_primary,
      updated_at = MAX(excluded.updated_at, restaurant_place_identities.updated_at)
  `).bind(
    mutation.entityId, viewerId, identity.provider, identity.externalId, identity.isPrimary ? 1 : 0,
    identity.createdAt, identity.updatedAt, mutation.entityId, viewerId, mutation.mutationId,
  ))
  const clearPrimary = database.prepare(`UPDATE restaurant_place_identities
    SET is_primary = 0, updated_at = MAX(updated_at, ?)
    WHERE restaurant_id = ? AND is_primary = 1
      AND EXISTS (SELECT 1 FROM restaurants WHERE id = ? AND user_id = ? AND last_mutation_id = ?)`)
    .bind(restaurant.updatedAt, mutation.entityId, mutation.entityId, viewerId, mutation.mutationId)
  return finalMutationStatements(
    database, viewerId, mutation, fingerprint, nextVersion, processedAt,
    entityStatement, [clearPrimary, ...identityStatements],
  )
}

function visitMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, database.prepare(`
      UPDATE visits SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
      WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL
    `).bind(processedAt, processedAt, nextVersion, mutation.mutationId, mutation.entityId, viewerId, mutation.baseVersion))
  }
  const visit = mutation.payload as VisitSyncContractV1
  const entityStatement = database.prepare(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, my_actual_spend, note,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  )
  SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (SELECT 1 FROM restaurants WHERE id = ? AND user_id = ? AND deleted_at IS NULL)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id, visited_at = excluded.visited_at,
    rating = excluded.rating, my_actual_spend = excluded.my_actual_spend,
    note = excluded.note, updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version, last_mutation_id = excluded.last_mutation_id
  WHERE visits.user_id = ? AND visits.server_version = ? AND visits.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, visit.restaurantId, visit.visitedAt, visit.rating,
      visit.myActualSpend, visit.note ?? '', visit.createdAt, visit.updatedAt,
      nextVersion, mutation.mutationId, visit.restaurantId, viewerId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, entityStatement)
}

function finalMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
  entityStatement: D1PreparedStatement,
  afterEntity: D1PreparedStatement[] = [],
) {
  const table = mutation.entityType === 'restaurant' ? 'restaurants' : 'visits'
  const operation = mutation.operation === 'delete' ? 'delete' : 'upsert'
  const logStatement = database.prepare(`INSERT INTO sync_change_log (
    user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
  )
  SELECT ?, ?, ?, ?, server_version, ?, ? FROM ${table}
  WHERE id = ? AND user_id = ? AND last_mutation_id = ?`)
    .bind(viewerId, mutation.entityType, mutation.entityId, operation, mutation.mutationId,
      processedAt, mutation.entityId, viewerId, mutation.mutationId)
  const receiptStatement = database.prepare(`INSERT INTO sync_mutation_receipts (
    user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
    status, server_version, revision, conflict_reason, processed_at
  )
  SELECT ?, ?, ?, ?, ?, ?, 'applied', ?, revision, NULL, ?
  FROM sync_change_log WHERE user_id = ? AND mutation_id = ?`)
    .bind(viewerId, mutation.mutationId, fingerprint, mutation.entityType, mutation.entityId,
      operation, nextVersion, processedAt, viewerId, mutation.mutationId)
  return [entityStatement, ...afterEntity, logStatement, receiptStatement]
}

async function recordConflict(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  serverVersion: number,
  reason: string,
): Promise<SyncMutationAcknowledgementV1> {
  const processedAt = new Date().toISOString()
  await database.prepare(`INSERT OR IGNORE INTO sync_mutation_receipts (
    user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
    status, server_version, revision, conflict_reason, processed_at
  ) VALUES (?, ?, ?, ?, ?, ?, 'conflict', ?, NULL, ?, ?)`)
    .bind(viewerId, mutation.mutationId, fingerprint, mutation.entityType, mutation.entityId,
      mutation.operation, serverVersion, reason, processedAt).run()
  const receipt = await readReceipt(database, viewerId, mutation.mutationId)
  if (!receipt) throw new SyncV1RequestError('Unable to persist conflict receipt.', 500)
  return acknowledgement(receipt, fingerprint, false)
}

async function readReceipt(database: D1Database, viewerId: string, mutationId: string) {
  return database.prepare('SELECT * FROM sync_mutation_receipts WHERE user_id = ? AND mutation_id = ?')
    .bind(viewerId, mutationId).first<ReceiptRow>()
}

async function readEntityVersion(database: D1Database, type: SyncEntityType, id: string) {
  const table = type === 'restaurant' ? 'restaurants' : 'visits'
  return database.prepare(`SELECT id, user_id, server_version, deleted_at, last_mutation_id FROM ${table} WHERE id = ?`)
    .bind(id).first<VersionedEntityRow>()
}

function acknowledgement(receipt: ReceiptRow, fingerprint: string, duplicate: boolean): SyncMutationAcknowledgementV1 {
  if (receipt.request_fingerprint !== fingerprint) {
    throw new SyncV1RequestError('mutationId was already used for a different mutation.', 409)
  }
  return {
    mutationId: receipt.mutation_id,
    entityType: receipt.entity_type,
    entityId: receipt.entity_id,
    status: receipt.status,
    duplicate,
    serverVersion: receipt.server_version,
    revision: receipt.revision,
    conflictReason: receipt.conflict_reason,
  }
}

async function readPlaceIdentities(database: D1Database, viewerId: string, restaurantId: string) {
  const result = await database.prepare(`SELECT * FROM restaurant_place_identities
    WHERE user_id = ? AND restaurant_id = ? ORDER BY is_primary DESC, updated_at ASC`)
    .bind(viewerId, restaurantId).all<RestaurantPlaceIdentityRow>()
  return groupRestaurantPlaceIdentities(result.results).get(restaurantId) ?? []
}

function rowToRestaurant(row: SyncRestaurantRow, identities: RestaurantPlaceIdentity[]): RestaurantJSONContractV1 {
  if (identities.length === 0) throw new SyncV1RequestError(`Restaurant ${row.id} has no place identity.`, 500)
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    placeIdentities: identities,
    ...(row.amap_poi_id ? { amapPoiId: row.amap_poi_id } : {}),
    name: row.name,
    address: row.address,
    city: row.city,
    latitude: row.latitude,
    longitude: row.longitude,
    status: row.status,
    preferenceLevel: row.preference_level,
    overallRating: row.overall_rating,
    foodRating: row.food_rating,
    environmentRating: row.environment_rating,
    serviceRating: row.service_rating,
    valueRating: row.value_rating,
    tags: parseStringArray(row.tags_json),
    longTermNote: row.long_term_note,
    pricePerPerson: row.price_per_person,
    phone: row.phone,
    openingHours: row.opening_hours,
    markerType: row.marker_type,
    markerPhotoId: row.marker_photo_id,
    merchantImageUrl: row.merchant_image_url,
    markerEmoji: row.marker_emoji,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    ...(row.is_test_data ? { isTestData: true } : {}),
  }
}

function rowToVisit(row: SyncVisitRow): VisitSyncContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    restaurantId: row.restaurant_id,
    visitedAt: row.visited_at,
    rating: row.rating,
    note: row.note || null,
    myActualSpend: row.my_actual_spend,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function tombstone(change: ChangeRow, deletedAt: string | null) {
  return {
    entityType: change.entity_type,
    entityId: change.entity_id,
    serverVersion: change.server_version,
    deletedAt: deletedAt ?? change.changed_at,
  }
}

function parseCursor(raw: string | null) {
  if (raw === null || raw === '') return 0
  if (!/^\d+$/.test(raw)) throw new SyncV1RequestError('Sync cursor is invalid.', 400)
  const value = Number(raw)
  if (!Number.isSafeInteger(value)) throw new SyncV1RequestError('Sync cursor is invalid.', 400)
  return value
}

function parseStringArray(value: string) {
  try {
    const parsed: unknown = JSON.parse(value)
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === 'string') : []
  } catch {
    return []
  }
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

export function assertSyncContractError(error: unknown): never {
  if (error instanceof SyncContractError) throw new SyncV1RequestError(error.message, 400)
  throw error
}
