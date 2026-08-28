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
import type { DishJSONContractV1, VisitDishJSONContractV1, PhotoJSONContractV1 } from '../src/contracts/dishPhotoContract'
import type { RestaurantPlaceIdentity } from '../src/types/restaurantIdentity'
import {
  normalizedPrivateDirectoryName,
  type DiningCompanionSyncContractV1,
  type RecommendationSourceSyncContractV1,
} from '../src/contracts/companionSourceContract'
import { groupRestaurantPlaceIdentities, type RestaurantPlaceIdentityRow } from './restaurantIdentityMapping'

const MAX_PULL_LIMIT = 200
const CHANGE_LOG_TABLE = 'sync_change_log_v4'
const RECEIPT_TABLE = 'sync_mutation_receipts_v4'

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
  dining_mode: VisitSyncContractV1['diningMode']
  visibility: VisitSyncContractV1['visibility']
  party_size: number
  party_size_optional: number | null
  total_price: number | null
  payment_mode: string | null
  price_per_person: number | null
  queue_duration: string | null
  dining_occasion: string | null
  dining_occasion_text: string
  dining_occasions_json: string
  rating: number | null
  value_rating: number | null
  environment_rating: number | null
  service_rating: number | null
  value_tags_json: string
  environment_tags_json: string
  service_tags_json: string
  noise_level: string | null
  dining_duration: string | null
  portion_level: string | null
  transport_convenience: string | null
  special_notes: string
  companions_json: string
  companion_ids_json: string
  recommendation_source_id: string | null
  recommendation_source_type: VisitSyncContractV1['recommendationSourceType']
  recommendation_source_user_id: string | null
  recommendation_source_text: string
  shared_meal_id: string | null
  note: string
  my_actual_spend: number | null
  created_at: string
  updated_at: string
}

interface SyncCompanionRow {
  id: string
  owner_user_id: string
  display_name: string
  normalized_name: string
  linked_user_id: string | null
  created_at: string
  updated_at: string
  deleted_at: string | null
  server_version: number
  last_mutation_id: string | null
}

interface SyncRecommendationSourceRow extends VersionedEntityRow {
  display_name: string
  normalized_name: string
  source_type: RecommendationSourceSyncContractV1['sourceType']
  linked_user_id: string | null
  created_at: string
  updated_at: string
}

interface SyncDishRow extends VersionedEntityRow {
  restaurant_id: string
  visit_id: string
  name: string
  taste: string
  rating: number | null
  price: number | null
  photo_id: string | null
  sort_order: number
  created_at: string
  updated_at: string
}

interface SyncVisitDishRow extends VersionedEntityRow {
  restaurant_id: string
  visit_id: string
  dish_id: string
  sort_order: number
  created_at: string
  updated_at: string
}

interface SyncPhotoRow extends VersionedEntityRow {
  restaurant_id: string | null
  visit_id: string | null
  dish_id: string | null
  kind: PhotoJSONContractV1['kind']
  storage_provider: PhotoJSONContractV1['storageProvider']
  storage_key: string | null
  drive_account_id: string
  drive_file_id: string
  thumbnail_storage_key: string | null
  file_name: string | null
  mime_type: string
  file_size: number
  width: number | null
  height: number | null
  sort_order: number
  visibility: PhotoJSONContractV1['visibility']
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
  const result = await database.prepare(`SELECT * FROM ${CHANGE_LOG_TABLE}
    WHERE user_id = ? AND revision > ? ORDER BY revision ASC LIMIT ?`)
    .bind(viewerId, cursor, limit).all<ChangeRow>()
  const changes = result.results
  const latestInPage = new Map<string, ChangeRow>()
  changes.forEach((change) => latestInPage.set(`${change.entity_type}:${change.entity_id}`, change))

  const restaurants = [] as SyncPullResponseV1['restaurants']
  const visits = [] as SyncPullResponseV1['visits']
  const dishes = [] as SyncPullResponseV1['dishes']
  const visitDishes = [] as SyncPullResponseV1['visitDishes']
  const photos = [] as SyncPullResponseV1['photos']
  const companions = [] as SyncPullResponseV1['companions']
  const recommendationSources = [] as SyncPullResponseV1['recommendationSources']
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
    } else if (change.entity_type === 'visit') {
      const row = await database.prepare('SELECT * FROM visits WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncVisitRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        visits.push({ serverVersion: row.server_version, record: rowToVisit(row) })
      }
    } else if (change.entity_type === 'dish') {
      const row = await database.prepare('SELECT * FROM dishes WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncDishRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        dishes.push({ serverVersion: row.server_version, record: rowToDish(row) })
      }
    } else if (change.entity_type === 'visitDish') {
      const row = await database.prepare('SELECT * FROM visit_dishes WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncVisitDishRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        visitDishes.push({ serverVersion: row.server_version, record: rowToVisitDish(row) })
      }
    } else if (change.entity_type === 'photo') {
      const row = await database.prepare('SELECT * FROM photos WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncPhotoRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        photos.push({ serverVersion: row.server_version, record: rowToPhoto(row) })
      }
    } else if (change.entity_type === 'companion') {
      const row = await database.prepare('SELECT * FROM dining_companions WHERE id = ? AND owner_user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncCompanionRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        companions.push({ serverVersion: row.server_version, record: rowToCompanion(row) })
      }
    } else {
      const row = await database.prepare('SELECT * FROM recommendation_sources WHERE id = ? AND user_id = ?')
        .bind(change.entity_id, viewerId).first<SyncRecommendationSourceRow>()
      if (!row || row.server_version !== change.server_version) continue
      if (change.operation === 'delete' || row.deleted_at) {
        tombstones.push(tombstone(change, row.deleted_at))
      } else {
        recommendationSources.push({ serverVersion: row.server_version, record: rowToRecommendationSource(row) })
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
  const includedVisitIDs = new Set(visits.map((item) => item.record.id))
  for (const child of [...dishes, ...visitDishes, ...photos].filter((item) => item.record.visitId)) {
    const visitId = child.record.visitId as string
    if (includedVisitIDs.has(visitId)) continue
    const parent = await database.prepare('SELECT * FROM visits WHERE id = ? AND user_id = ?')
      .bind(visitId, viewerId).first<SyncVisitRow>()
    if (!parent) throw new SyncV1RequestError(`Child entity has no Visit ${visitId}.`, 500)
    visits.push({ serverVersion: parent.server_version, record: rowToVisit(parent) })
    includedVisitIDs.add(parent.id)
    if (!includedRestaurantIDs.has(parent.restaurant_id)) {
      const restaurant = await database.prepare('SELECT * FROM restaurants WHERE id = ? AND user_id = ?')
        .bind(parent.restaurant_id, viewerId).first<SyncRestaurantRow>()
      if (!restaurant) throw new SyncV1RequestError(`Visit ${parent.id} has no Restaurant.`, 500)
      restaurants.push({ serverVersion: restaurant.server_version, record: rowToRestaurant(
        restaurant, await readPlaceIdentities(database, viewerId, restaurant.id),
      ) })
      includedRestaurantIDs.add(restaurant.id)
    }
  }
  const includedDishIDs = new Set(dishes.map((item) => item.record.id))
  for (const child of [...visitDishes, ...photos]) {
    const dishId = child.record.dishId
    if (!dishId || includedDishIDs.has(dishId)) continue
    const parent = await database.prepare('SELECT * FROM dishes WHERE id = ? AND user_id = ?')
      .bind(dishId, viewerId).first<SyncDishRow>()
    if (!parent) throw new SyncV1RequestError(`Child ${child.record.id} has no Dish.`, 500)
    dishes.push({ serverVersion: parent.server_version, record: rowToDish(parent) })
    includedDishIDs.add(parent.id)
  }
  for (const photo of photos) {
    const restaurantId = photo.record.restaurantId
    if (!restaurantId || includedRestaurantIDs.has(restaurantId)) continue
    const parent = await database.prepare('SELECT * FROM restaurants WHERE id = ? AND user_id = ?')
      .bind(restaurantId, viewerId).first<SyncRestaurantRow>()
    if (!parent) throw new SyncV1RequestError(`Photo ${photo.record.id} has no Restaurant.`, 500)
    restaurants.push({ serverVersion: parent.server_version, record: rowToRestaurant(
      parent, await readPlaceIdentities(database, viewerId, parent.id),
    ) })
    includedRestaurantIDs.add(parent.id)
  }

  return {
    apiVersion: SYNC_API_VERSION,
    schemaVersion: SYNC_SCHEMA_VERSION,
    restaurants,
    visits,
    dishes,
    visitDishes,
    photos,
    companions,
    recommendationSources,
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
    const table = entityTable(change.entityType)
    const ownerColumn = entityOwnerColumn(change.entityType)
    const operation = change.deletedAt ? 'delete' : 'upsert'
    const changedAt = new Date().toISOString()
    await database.batch([
      database.prepare(`UPDATE ${table}
        SET server_version = MAX(server_version, 0) + 1, last_mutation_id = ?
        WHERE id = ? AND ${ownerColumn} = ? AND updated_at = ?
          AND NOT EXISTS (
            SELECT 1 FROM ${CHANGE_LOG_TABLE} WHERE user_id = ? AND mutation_id = ?
          )`)
        .bind(mutationId, change.entityId, change.userId, change.updatedAt, change.userId, mutationId),
      database.prepare(`INSERT INTO ${CHANGE_LOG_TABLE} (
        user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
      )
      SELECT ?, ?, ?, ?, server_version, ?, ? FROM ${table}
      WHERE id = ? AND ${ownerColumn} = ? AND last_mutation_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM ${CHANGE_LOG_TABLE} WHERE user_id = ? AND mutation_id = ?
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
  if (mutation.operation === 'upsert' &&
    (mutation.entityType === 'companion' || mutation.entityType === 'recommendationSource')) {
    const directory = mutation.payload as DiningCompanionSyncContractV1 | RecommendationSourceSyncContractV1
    const normalizedName = normalizedPrivateDirectoryName(directory.displayName)
    const duplicate = mutation.entityType === 'companion'
      ? await database.prepare(`SELECT id, server_version FROM dining_companions
          WHERE owner_user_id = ? AND normalized_name = ? AND deleted_at IS NULL AND id <> ? LIMIT 1`)
        .bind(viewerId, normalizedName, mutation.entityId).first<{ id: string; server_version: number }>()
      : await database.prepare(`SELECT id, server_version FROM recommendation_sources
          WHERE user_id = ? AND normalized_name = ? AND deleted_at IS NULL AND id <> ? LIMIT 1`)
        .bind(viewerId, normalizedName, mutation.entityId).first<{ id: string; server_version: number }>()
    if (duplicate) {
      return recordConflict(database, viewerId, mutation, fingerprint, duplicate.server_version, `duplicate_name:${duplicate.id}`)
    }
  }
  if (mutation.entityType === 'visit' && mutation.operation === 'upsert') {
    const visit = mutation.payload as VisitSyncContractV1
    const restaurant = await readEntityVersion(database, 'restaurant', visit.restaurantId)
    if (!restaurant || restaurant.user_id !== viewerId || restaurant.deleted_at) {
      throw new SyncV1RequestError('Visit.restaurantId must reference an active Restaurant owned by the authenticated user.', 403)
    }
    await assertOwnedVisitPeople(database, viewerId, visit)
  }
  if (mutation.entityType === 'dish' && mutation.operation === 'upsert') {
    const dish = mutation.payload as DishJSONContractV1
    await assertOwnedDishParents(database, viewerId, dish)
  }
  if (mutation.entityType === 'visitDish' && mutation.operation === 'upsert') {
    const association = mutation.payload as VisitDishJSONContractV1
    await assertOwnedVisitDishParents(database, viewerId, association)
    if (current && mutation.baseVersion === 0 &&
      await equivalentLegacyVisitDish(database, viewerId, association, current)) {
      return recordEquivalentMutation(database, viewerId, mutation, fingerprint, current)
    }
  }
  if (mutation.entityType === 'photo' && mutation.operation === 'upsert') {
    const photo = mutation.payload as PhotoJSONContractV1
    await assertOwnedPhotoParents(database, viewerId, photo)
  }
  const conflictReason = conflictForMutation(current, mutation)
  if (conflictReason) {
    return recordConflict(database, viewerId, mutation, fingerprint, current?.server_version ?? 0, conflictReason)
  }

  const nextVersion = (current?.server_version ?? 0) + 1
  const processedAt = new Date().toISOString()
  const statements = (() => {
    switch (mutation.entityType) {
      case 'restaurant': return restaurantMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
      case 'visit': return visitMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
      case 'dish': return dishMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
      case 'visitDish': return visitDishMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
      case 'photo': return photoMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
      case 'companion': return companionMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
      case 'recommendationSource': return recommendationSourceMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt)
    }
  })()
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
  if (current.deleted_at && !(mutation.entityType === 'visitDish' && mutation.operation === 'upsert')) return 'entity_deleted'
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
    id, user_id, restaurant_id, visited_at, dining_mode, visibility,
    total_price, my_actual_spend, payment_mode, price_per_person,
    party_size, party_size_optional, queue_duration,
    dining_occasion, dining_occasion_text, dining_occasions_json,
    rating, value_rating, environment_rating, service_rating,
    value_tags_json, environment_tags_json, service_tags_json,
    noise_level, dining_duration, portion_level, transport_convenience, special_notes, note,
    companions_json, companion_ids_json, recommendation_source_id,
    recommendation_source_type, recommendation_source_user_id,
    recommendation_source_text, shared_meal_id,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  )
  SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (SELECT 1 FROM restaurants WHERE id = ? AND user_id = ? AND deleted_at IS NULL)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id, visited_at = excluded.visited_at,
    dining_mode = excluded.dining_mode, visibility = excluded.visibility,
    total_price = excluded.total_price, my_actual_spend = excluded.my_actual_spend,
    payment_mode = excluded.payment_mode, price_per_person = excluded.price_per_person,
    party_size = excluded.party_size,
    party_size_optional = excluded.party_size_optional,
    queue_duration = excluded.queue_duration,
    dining_occasion = excluded.dining_occasion,
    dining_occasion_text = excluded.dining_occasion_text,
    dining_occasions_json = excluded.dining_occasions_json,
    rating = excluded.rating, value_rating = excluded.value_rating,
    environment_rating = excluded.environment_rating, service_rating = excluded.service_rating,
    value_tags_json = excluded.value_tags_json,
    environment_tags_json = excluded.environment_tags_json,
    service_tags_json = excluded.service_tags_json,
    noise_level = excluded.noise_level, dining_duration = excluded.dining_duration,
    portion_level = excluded.portion_level,
    transport_convenience = excluded.transport_convenience,
    special_notes = excluded.special_notes,
    companions_json = excluded.companions_json,
    companion_ids_json = excluded.companion_ids_json,
    recommendation_source_id = excluded.recommendation_source_id,
    recommendation_source_type = excluded.recommendation_source_type,
    recommendation_source_user_id = excluded.recommendation_source_user_id,
    recommendation_source_text = excluded.recommendation_source_text,
    shared_meal_id = excluded.shared_meal_id,
    note = excluded.note, updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version, last_mutation_id = excluded.last_mutation_id
  WHERE visits.user_id = ? AND visits.server_version = ? AND visits.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, visit.restaurantId, visit.visitedAt, visit.diningMode,
      visit.visibility, visit.totalPrice, visit.myActualSpend, visit.paymentMode, visit.pricePerPerson,
      visit.partySize ?? 0, visit.partySize, visit.queueDuration,
      visit.diningOccasions[0] ?? null, visit.diningOccasionText ?? '', JSON.stringify(visit.diningOccasions),
      visit.rating,
      visit.valueRating, visit.environmentRating, visit.serviceRating,
      JSON.stringify(visit.valueTags), JSON.stringify(visit.environmentTags), JSON.stringify(visit.serviceTags),
      visit.noiseLevel, visit.diningDuration, visit.portionLevel, visit.transportConvenience,
      visit.specialNotes ?? '', visit.note ?? '', JSON.stringify(visit.companions),
      JSON.stringify(visit.companionIds), visit.recommendationSourceId,
      visit.recommendationSourceType, visit.recommendationSourceUserId,
      visit.recommendationSourceText ?? '', visit.sharedMealId,
      visit.createdAt, visit.updatedAt,
      nextVersion, mutation.mutationId, visit.restaurantId, viewerId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, entityStatement)
}

function companionMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      database.prepare(`UPDATE dining_companions
        SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
        WHERE id = ? AND owner_user_id = ? AND server_version = ? AND deleted_at IS NULL`)
        .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
          mutation.entityId, viewerId, mutation.baseVersion))
  }
  const companion = mutation.payload as DiningCompanionSyncContractV1
  const normalizedName = normalizedPrivateDirectoryName(companion.displayName)
  const statement = database.prepare(`INSERT INTO dining_companions (
    id, owner_user_id, display_name, normalized_name, linked_user_id,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    display_name = excluded.display_name, normalized_name = excluded.normalized_name,
    linked_user_id = excluded.linked_user_id, updated_at = excluded.updated_at,
    deleted_at = NULL, server_version = excluded.server_version,
    last_mutation_id = excluded.last_mutation_id
  WHERE dining_companions.owner_user_id = ?
    AND dining_companions.server_version = ? AND dining_companions.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, companion.displayName, normalizedName,
      companion.linkedTasteMapUserId, companion.createdAt, companion.updatedAt,
      nextVersion, mutation.mutationId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, statement)
}

function recommendationSourceMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      database.prepare(`UPDATE recommendation_sources
        SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
        WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL`)
        .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
          mutation.entityId, viewerId, mutation.baseVersion))
  }
  const source = mutation.payload as RecommendationSourceSyncContractV1
  const normalizedName = normalizedPrivateDirectoryName(source.displayName)
  const statement = database.prepare(`INSERT INTO recommendation_sources (
    id, user_id, display_name, normalized_name, source_type, linked_user_id,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    display_name = excluded.display_name, normalized_name = excluded.normalized_name,
    source_type = excluded.source_type, linked_user_id = excluded.linked_user_id,
    updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version, last_mutation_id = excluded.last_mutation_id
  WHERE recommendation_sources.user_id = ?
    AND recommendation_sources.server_version = ? AND recommendation_sources.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, source.displayName, normalizedName, source.sourceType,
      source.linkedTasteMapUserId, source.createdAt, source.updatedAt,
      nextVersion, mutation.mutationId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, statement)
}

function dishMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    const entityStatement = database.prepare(`UPDATE dishes
      SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
      WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL`)
      .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
        mutation.entityId, viewerId, mutation.baseVersion)
    return finalMutationStatements(
      database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      entityStatement, [dishProjectionStatement(database, viewerId, mutation.entityId)],
    )
  }
  const dish = mutation.payload as DishJSONContractV1
  const entityStatement = database.prepare(`INSERT INTO dishes (
    id, user_id, restaurant_id, visit_id, name, taste, rating, price, photo_id,
    sort_order, created_at, updated_at, deleted_at, server_version, last_mutation_id
  )
  SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1 FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
    WHERE v.id = ? AND v.user_id = ? AND v.deleted_at IS NULL
      AND r.id = ? AND r.user_id = ? AND r.deleted_at IS NULL
  )
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id, visit_id = excluded.visit_id,
    name = excluded.name, taste = excluded.taste, rating = excluded.rating,
    price = excluded.price, photo_id = excluded.photo_id,
    sort_order = excluded.sort_order, updated_at = excluded.updated_at,
    deleted_at = NULL, server_version = excluded.server_version,
    last_mutation_id = excluded.last_mutation_id
  WHERE dishes.user_id = ? AND dishes.server_version = ? AND dishes.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, dish.restaurantId, dish.visitId, dish.name,
      dish.taste, dish.rating, dish.price, dish.photoId, dish.sortOrder,
      dish.createdAt, dish.updatedAt, nextVersion, mutation.mutationId,
      dish.visitId, viewerId, dish.restaurantId, viewerId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(
    database, viewerId, mutation, fingerprint, nextVersion, processedAt,
    entityStatement, [
      ...legacyVisitDishStatements(database, viewerId, mutation, dish, processedAt),
      dishProjectionStatement(database, viewerId, mutation.entityId),
    ],
  )
}

function visitDishMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    const entityStatement = database.prepare(`UPDATE visit_dishes
      SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
      WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL`)
      .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
        mutation.entityId, viewerId, mutation.baseVersion)
    return finalMutationStatements(
      database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      entityStatement, [visitDishProjectionStatement(database, viewerId, mutation.entityId)],
    )
  }
  const association = mutation.payload as VisitDishJSONContractV1
  const entityStatement = database.prepare(`INSERT INTO visit_dishes (
    id, user_id, restaurant_id, visit_id, dish_id, sort_order,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id, visit_id = excluded.visit_id,
    dish_id = excluded.dish_id, sort_order = excluded.sort_order,
    updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version, last_mutation_id = excluded.last_mutation_id
  WHERE visit_dishes.user_id = ? AND visit_dishes.server_version = ?`)
    .bind(
      mutation.entityId, viewerId, association.restaurantId, association.visitId,
      association.dishId, association.sortOrder, association.createdAt,
      association.updatedAt, nextVersion, mutation.mutationId,
      viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(
    database, viewerId, mutation, fingerprint, nextVersion, processedAt,
    entityStatement, [visitDishProjectionStatement(database, viewerId, mutation.entityId)],
  )
}

function legacyVisitDishStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  dish: DishJSONContractV1,
  processedAt: string,
) {
  const associationID = `legacy:${mutation.entityId}:${dish.visitId}`
  const associationMutationID = `legacy-association:${mutation.mutationId}`
  return [
    database.prepare(`INSERT OR IGNORE INTO visit_dishes (
      id, user_id, restaurant_id, visit_id, dish_id, sort_order,
      created_at, updated_at, deleted_at, server_version, last_mutation_id
    ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, ?
    WHERE EXISTS (SELECT 1 FROM dishes WHERE id = ? AND user_id = ? AND last_mutation_id = ?)`)
      .bind(
        associationID, viewerId, dish.restaurantId, dish.visitId, mutation.entityId,
        dish.sortOrder, dish.createdAt, dish.updatedAt, associationMutationID,
        mutation.entityId, viewerId, mutation.mutationId,
      ),
    database.prepare(`INSERT OR IGNORE INTO ${CHANGE_LOG_TABLE} (
      user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
    ) SELECT ?, 'visitDish', id, 'upsert', server_version, ?, ?
      FROM visit_dishes WHERE id = ? AND user_id = ? AND last_mutation_id = ?`)
      .bind(viewerId, associationMutationID, processedAt, associationID, viewerId, associationMutationID),
  ]
}

function visitDishProjectionStatement(database: D1Database, viewerId: string, associationID: string) {
  return database.prepare(`UPDATE visits SET dishes_json = COALESCE((
    SELECT json_group_array(json_object(
      'id', d.id, 'name', d.name, 'taste', d.taste, 'rating', d.rating,
      'price', d.price, 'photoId', d.photo_id
    )) FROM (
      SELECT d.id, d.name, d.taste, d.rating, d.price, d.photo_id, vd.sort_order, vd.created_at
      FROM visit_dishes vd JOIN dishes d ON d.id = vd.dish_id AND d.user_id = vd.user_id
      WHERE vd.user_id = ? AND vd.visit_id = visits.id
        AND vd.deleted_at IS NULL AND d.deleted_at IS NULL
      ORDER BY vd.sort_order ASC, vd.created_at ASC, vd.id ASC
    ) d
  ), '[]')
  WHERE user_id = ? AND id = (
    SELECT visit_id FROM visit_dishes WHERE id = ? AND user_id = ?
  )`).bind(viewerId, viewerId, associationID, viewerId)
}

function photoMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    const entityStatement = database.prepare(`UPDATE photos
      SET deleted_at = ?, updated_at = ?, sync_status = 'delete-pending',
        server_version = ?, last_mutation_id = ?
      WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL`)
      .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
        mutation.entityId, viewerId, mutation.baseVersion)
    return finalMutationStatements(
      database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      entityStatement, photoProjectionStatements(database, viewerId, mutation.entityId),
    )
  }
  const photo = mutation.payload as PhotoJSONContractV1
  const legacyDriveKey = photo.storageProvider === 'google-drive' ? photo.storageKey : ''
  const entityStatement = database.prepare(`INSERT INTO photos (
    id, user_id, restaurant_id, visit_id, dish_id, storage_provider,
    drive_account_id, drive_file_id, storage_key, thumbnail_storage_key,
    thumbnail_file_size, kind, file_name, mime_type, file_size, width, height,
    sort_order, visibility, sync_status, created_at, updated_at, deleted_at,
    server_version, last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, NULL, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id, visit_id = excluded.visit_id,
    dish_id = excluded.dish_id, storage_provider = excluded.storage_provider,
    drive_account_id = excluded.drive_account_id, drive_file_id = excluded.drive_file_id,
    storage_key = excluded.storage_key, thumbnail_storage_key = excluded.thumbnail_storage_key,
    kind = excluded.kind, file_name = excluded.file_name, mime_type = excluded.mime_type,
    file_size = excluded.file_size, width = excluded.width, height = excluded.height,
    sort_order = excluded.sort_order, visibility = excluded.visibility,
    sync_status = 'synced', updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version, last_mutation_id = excluded.last_mutation_id
  WHERE photos.user_id = ? AND photos.server_version = ? AND photos.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, photo.restaurantId, photo.visitId, photo.dishId,
      photo.storageProvider, photo.providerAccountId ?? '', legacyDriveKey,
      photo.storageKey, photo.thumbnailStorageKey, photo.kind, photo.fileName,
      photo.mimeType, photo.byteSize, photo.width, photo.height, photo.sortOrder,
      photo.visibility, photo.createdAt, photo.updatedAt, nextVersion,
      mutation.mutationId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(
    database, viewerId, mutation, fingerprint, nextVersion, processedAt,
    entityStatement, photoProjectionStatements(database, viewerId, mutation.entityId),
  )
}

function dishProjectionStatement(database: D1Database, viewerId: string, dishId: string) {
  return database.prepare(`UPDATE visits SET dishes_json = COALESCE((
    SELECT json_group_array(json_object(
      'id', id, 'name', name, 'taste', taste, 'rating', rating,
      'price', price, 'photoId', photo_id
    )) FROM (
      SELECT d.id, d.name, d.taste, d.rating, d.price, d.photo_id,
        vd.sort_order, vd.created_at
      FROM visit_dishes vd JOIN dishes d ON d.id = vd.dish_id AND d.user_id = vd.user_id
      WHERE vd.user_id = ? AND vd.visit_id = visits.id
        AND vd.deleted_at IS NULL AND d.deleted_at IS NULL
      ORDER BY vd.sort_order ASC, vd.created_at ASC, vd.id ASC
    )
  ), '[]')
  WHERE user_id = ? AND id IN (
    SELECT visit_id FROM visit_dishes WHERE dish_id = ? AND user_id = ?
  )`)
    .bind(viewerId, viewerId, dishId, viewerId)
}

function photoProjectionStatements(database: D1Database, viewerId: string, photoId: string) {
  return [
    database.prepare(`UPDATE visits SET photo_ids_json = COALESCE((
      SELECT json_group_array(id) FROM (
        SELECT id FROM photos WHERE user_id = ? AND visit_id = visits.id
          AND kind = 'visit' AND deleted_at IS NULL
        ORDER BY sort_order ASC, created_at ASC, id ASC
      )
    ), '[]')
    WHERE user_id = ? AND id = (SELECT visit_id FROM photos WHERE id = ? AND user_id = ?)`)
      .bind(viewerId, viewerId, photoId, viewerId),
    database.prepare(`UPDATE restaurants SET marker_photo_id = (
      SELECT id FROM photos WHERE user_id = ? AND restaurant_id = restaurants.id
        AND kind = 'restaurant-marker' AND deleted_at IS NULL
      ORDER BY sort_order ASC, updated_at DESC LIMIT 1
    )
    WHERE user_id = ? AND id = (SELECT restaurant_id FROM photos WHERE id = ? AND user_id = ?)`)
      .bind(viewerId, viewerId, photoId, viewerId),
    database.prepare(`UPDATE dishes SET photo_id = (
      SELECT id FROM photos WHERE user_id = ? AND dish_id = dishes.id
        AND kind = 'dish' AND deleted_at IS NULL
      ORDER BY sort_order ASC, updated_at DESC LIMIT 1
    )
    WHERE user_id = ? AND id = (SELECT dish_id FROM photos WHERE id = ? AND user_id = ?)`)
      .bind(viewerId, viewerId, photoId, viewerId),
    database.prepare(`UPDATE visits SET dishes_json = COALESCE((
      SELECT json_group_array(json_object(
        'id', id, 'name', name, 'taste', taste, 'rating', rating,
        'price', price, 'photoId', photo_id
      )) FROM (
        SELECT d.id, d.name, d.taste, d.rating, d.price, d.photo_id,
          vd.sort_order, vd.created_at
        FROM visit_dishes vd JOIN dishes d ON d.id = vd.dish_id AND d.user_id = vd.user_id
        WHERE vd.user_id = ? AND vd.visit_id = visits.id
          AND vd.deleted_at IS NULL AND d.deleted_at IS NULL
        ORDER BY vd.sort_order ASC, vd.created_at ASC, vd.id ASC
      )
    ), '[]')
    WHERE user_id = ? AND id IN (
      SELECT vd.visit_id FROM visit_dishes vd JOIN photos p ON p.dish_id = vd.dish_id
      WHERE p.id = ? AND p.user_id = ? AND vd.user_id = ?
    )`).bind(viewerId, viewerId, photoId, viewerId, viewerId),
  ]
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
  const table = entityTable(mutation.entityType)
  const ownerColumn = entityOwnerColumn(mutation.entityType)
  const operation = mutation.operation === 'delete' ? 'delete' : 'upsert'
  const logStatement = database.prepare(`INSERT INTO ${CHANGE_LOG_TABLE} (
    user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
  )
  SELECT ?, ?, ?, ?, server_version, ?, ? FROM ${table}
  WHERE id = ? AND ${ownerColumn} = ? AND last_mutation_id = ?`)
    .bind(viewerId, mutation.entityType, mutation.entityId, operation, mutation.mutationId,
      processedAt, mutation.entityId, viewerId, mutation.mutationId)
  const receiptStatement = database.prepare(`INSERT INTO ${RECEIPT_TABLE} (
    user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
    status, server_version, revision, conflict_reason, processed_at
  )
  SELECT ?, ?, ?, ?, ?, ?, 'applied', ?, revision, NULL, ?
  FROM ${CHANGE_LOG_TABLE} WHERE user_id = ? AND mutation_id = ?`)
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
  await database.prepare(`INSERT OR IGNORE INTO ${RECEIPT_TABLE} (
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
  return database.prepare(`SELECT * FROM ${RECEIPT_TABLE} WHERE user_id = ? AND mutation_id = ?`)
    .bind(viewerId, mutationId).first<ReceiptRow>()
}

async function equivalentLegacyVisitDish(
  database: D1Database,
  viewerId: string,
  association: VisitDishJSONContractV1,
  current: VersionedEntityRow,
) {
  const legacyMutation = current.last_mutation_id?.startsWith('legacy-association:') ||
    current.last_mutation_id?.startsWith('bootstrap:visitDish:')
  if (current.deleted_at || current.server_version !== 1 || !legacyMutation) return false
  const row = await database.prepare(`SELECT restaurant_id, visit_id, dish_id, sort_order
    FROM visit_dishes WHERE id = ? AND user_id = ?`)
    .bind(association.id, viewerId)
    .first<{ restaurant_id: string; visit_id: string; dish_id: string; sort_order: number }>()
  return row?.restaurant_id === association.restaurantId &&
    row.visit_id === association.visitId && row.dish_id === association.dishId &&
    row.sort_order === association.sortOrder
}

async function recordEquivalentMutation(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  current: VersionedEntityRow,
) {
  const processedAt = new Date().toISOString()
  await database.prepare(`INSERT INTO ${RECEIPT_TABLE} (
    user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
    status, server_version, revision, conflict_reason, processed_at
  ) SELECT ?, ?, ?, ?, ?, 'upsert', 'applied', ?, revision, NULL, ?
    FROM ${CHANGE_LOG_TABLE}
    WHERE user_id = ? AND entity_type = ? AND entity_id = ?
    ORDER BY revision DESC LIMIT 1`)
    .bind(
      viewerId, mutation.mutationId, fingerprint, mutation.entityType,
      mutation.entityId, current.server_version, processedAt,
      viewerId, mutation.entityType, mutation.entityId,
    ).run()
  const receipt = await readReceipt(database, viewerId, mutation.mutationId)
  if (!receipt) throw new SyncV1RequestError('Unable to persist equivalent mutation receipt.', 500)
  return acknowledgement(receipt, fingerprint, true)
}

async function readEntityVersion(database: D1Database, type: SyncEntityType, id: string) {
  const table = entityTable(type)
  const ownerColumn = entityOwnerColumn(type)
  return database.prepare(`SELECT id, ${ownerColumn} AS user_id, server_version, deleted_at, last_mutation_id FROM ${table} WHERE id = ?`)
    .bind(id).first<VersionedEntityRow>()
}

async function assertOwnedVisitPeople(database: D1Database, viewerId: string, visit: VisitSyncContractV1) {
  for (const companionId of visit.companionIds) {
    const companion = await database.prepare(`SELECT id FROM dining_companions
      WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL`)
      .bind(companionId, viewerId).first<{ id: string }>()
    if (!companion) {
      throw new SyncV1RequestError('Visit companionIds must reference active private companions owned by the authenticated user.', 403)
    }
  }
  if (visit.recommendationSourceId) {
    const source = await database.prepare(`SELECT id FROM recommendation_sources
      WHERE id = ? AND user_id = ? AND deleted_at IS NULL`)
      .bind(visit.recommendationSourceId, viewerId).first<{ id: string }>()
    if (!source) {
      throw new SyncV1RequestError('Visit recommendationSourceId must reference an active private source owned by the authenticated user.', 403)
    }
  }
}

async function assertOwnedDishParents(database: D1Database, viewerId: string, dish: DishJSONContractV1) {
  const row = await database.prepare(`SELECT v.id, v.restaurant_id FROM visits v
    JOIN restaurants r ON r.id = v.restaurant_id
    WHERE v.id = ? AND v.user_id = ? AND v.deleted_at IS NULL
      AND r.id = ? AND r.user_id = ? AND r.deleted_at IS NULL`)
    .bind(dish.visitId, viewerId, dish.restaurantId, viewerId)
    .first<{ id: string; restaurant_id: string }>()
  if (!row) {
    throw new SyncV1RequestError('Dish must reference an active Visit and Restaurant owned by the authenticated user.', 403)
  }
}

async function assertOwnedVisitDishParents(
  database: D1Database,
  viewerId: string,
  association: VisitDishJSONContractV1,
) {
  const row = await database.prepare(`SELECT v.id FROM visits v
    JOIN restaurants r ON r.id = v.restaurant_id
    JOIN dishes d ON d.id = ? AND d.restaurant_id = r.id
    WHERE v.id = ? AND v.user_id = ? AND v.deleted_at IS NULL
      AND r.id = ? AND r.user_id = ? AND r.deleted_at IS NULL
      AND d.user_id = ? AND d.deleted_at IS NULL`)
    .bind(
      association.dishId, association.visitId, viewerId,
      association.restaurantId, viewerId, viewerId,
    ).first<{ id: string }>()
  if (!row) {
    throw new SyncV1RequestError('VisitDish must reference active owned Restaurant, Visit, and Dish records.', 403)
  }
}

async function assertOwnedPhotoParents(database: D1Database, viewerId: string, photo: PhotoJSONContractV1) {
  if (photo.restaurantId) {
    const restaurant = await readEntityVersion(database, 'restaurant', photo.restaurantId)
    if (!restaurant || restaurant.user_id !== viewerId || restaurant.deleted_at) {
      throw new SyncV1RequestError('Photo.restaurantId must reference an active owned Restaurant.', 403)
    }
  }
  if (photo.visitId) {
    const visit = await database.prepare('SELECT id, user_id, restaurant_id, deleted_at FROM visits WHERE id = ?')
      .bind(photo.visitId).first<{ id: string; user_id: string; restaurant_id: string; deleted_at: string | null }>()
    if (!visit || visit.user_id !== viewerId || visit.deleted_at || visit.restaurant_id !== photo.restaurantId) {
      throw new SyncV1RequestError('Photo.visitId must reference an active owned Visit with the same Restaurant.', 403)
    }
  }
  if (photo.dishId) {
    const dish = await database.prepare('SELECT id, user_id, restaurant_id, visit_id, deleted_at FROM dishes WHERE id = ?')
      .bind(photo.dishId).first<{ id: string; user_id: string; restaurant_id: string; visit_id: string; deleted_at: string | null }>()
    const association = dish && photo.visitId
      ? await database.prepare(`SELECT id FROM visit_dishes
          WHERE user_id = ? AND visit_id = ? AND dish_id = ? AND deleted_at IS NULL`)
        .bind(viewerId, photo.visitId, photo.dishId).first<{ id: string }>()
      : null
    if (!dish || dish.user_id !== viewerId || dish.deleted_at ||
      dish.restaurant_id !== photo.restaurantId ||
      (dish.visit_id !== photo.visitId && !association)) {
      throw new SyncV1RequestError('Photo.dishId must reference an active owned Dish with matching parents.', 403)
    }
  }
}

function entityTable(type: SyncEntityType) {
  switch (type) {
    case 'restaurant': return 'restaurants'
    case 'visit': return 'visits'
    case 'dish': return 'dishes'
    case 'visitDish': return 'visit_dishes'
    case 'photo': return 'photos'
    case 'companion': return 'dining_companions'
    case 'recommendationSource': return 'recommendation_sources'
  }
}

function entityOwnerColumn(type: SyncEntityType) {
  return type === 'companion' ? 'owner_user_id' : 'user_id'
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
  const diningOccasions = parseStringArray(row.dining_occasions_json)
  if (!diningOccasions.length && row.dining_occasion) diningOccasions.push(row.dining_occasion)
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    restaurantId: row.restaurant_id,
    visitedAt: row.visited_at,
    diningMode: row.dining_mode ?? 'dine_in',
    visibility: row.visibility === 'friends' || row.visibility === 'public' ? row.visibility : 'private',
    partySize: row.party_size_optional ?? (row.party_size >= 1 ? row.party_size : null),
    totalPrice: row.total_price,
    paymentMode: row.payment_mode || null,
    pricePerPerson: row.price_per_person,
    queueDuration: row.queue_duration || null,
    diningOccasions,
    diningOccasionText: row.dining_occasion_text || null,
    rating: row.rating,
    valueRating: row.value_rating,
    environmentRating: row.environment_rating,
    serviceRating: row.service_rating,
    valueTags: parseStringArray(row.value_tags_json),
    environmentTags: parseStringArray(row.environment_tags_json),
    serviceTags: parseStringArray(row.service_tags_json),
    noiseLevel: row.noise_level || null,
    diningDuration: row.dining_duration || null,
    portionLevel: row.portion_level || null,
    transportConvenience: row.transport_convenience || null,
    specialNotes: row.special_notes || null,
    companions: parseStringArray(row.companions_json),
    companionIds: parseStringArray(row.companion_ids_json),
    recommendationSourceId: row.recommendation_source_id,
    recommendationSourceType: row.recommendation_source_type,
    recommendationSourceUserId: row.recommendation_source_user_id,
    recommendationSourceText: row.recommendation_source_text || null,
    sharedMealId: row.shared_meal_id,
    note: row.note || null,
    myActualSpend: row.my_actual_spend,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToCompanion(row: SyncCompanionRow): DiningCompanionSyncContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.owner_user_id,
    displayName: row.display_name,
    linkedTasteMapUserId: row.linked_user_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToRecommendationSource(row: SyncRecommendationSourceRow): RecommendationSourceSyncContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    displayName: row.display_name,
    sourceType: row.source_type,
    linkedTasteMapUserId: row.linked_user_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToDish(row: SyncDishRow): DishJSONContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    restaurantId: row.restaurant_id,
    visitId: row.visit_id,
    name: row.name,
    taste: row.taste,
    rating: row.rating as DishJSONContractV1['rating'],
    price: row.price,
    photoId: row.photo_id,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToVisitDish(row: SyncVisitDishRow): VisitDishJSONContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    restaurantId: row.restaurant_id,
    visitId: row.visit_id,
    dishId: row.dish_id,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToPhoto(row: SyncPhotoRow): PhotoJSONContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    restaurantId: row.restaurant_id,
    visitId: row.visit_id,
    dishId: row.dish_id,
    kind: row.kind,
    storageProvider: row.storage_provider,
    storageKey: row.storage_key ?? row.drive_file_id,
    providerAccountId: row.drive_account_id || null,
    thumbnailStorageKey: row.thumbnail_storage_key,
    fileName: row.file_name,
    mimeType: row.mime_type,
    byteSize: row.file_size,
    width: row.width,
    height: row.height,
    sortOrder: row.sort_order,
    visibility: row.visibility,
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
