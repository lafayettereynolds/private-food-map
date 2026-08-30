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
import {
  type OwnProfileSyncContractV1,
} from '../src/contracts/profileContract'
import {
  decodeRestaurantListPlace,
  type RestaurantListItemSyncContractV1,
  type RestaurantListPlaceContractV1,
  type RestaurantListSyncContractV1,
} from '../src/contracts/restaurantListContract'
import { groupRestaurantPlaceIdentities, type RestaurantPlaceIdentityRow } from './restaurantIdentityMapping'

const MAX_PULL_LIMIT = 200
const PULL_ID_BATCH_SIZE = 50
const CHANGE_LOG_TABLE = 'sync_change_log_v6'
const RECEIPT_TABLE = 'sync_mutation_receipts_v6'

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

interface SyncProfileRow extends VersionedEntityRow {
  display_name: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: OwnProfileSyncContractV1['avatarPresetId']
  visibility: OwnProfileSyncContractV1['visibility']
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

interface SyncRestaurantListRow extends VersionedEntityRow {
  title: string
  description: string
  visibility: RestaurantListSyncContractV1['visibility']
  is_ranked: number
  cover_mode: RestaurantListSyncContractV1['coverMode']
  custom_cover_photo_id: string | null
  active_item_count: number
  created_at: string
  updated_at: string
}

interface SyncRestaurantListItemRow extends VersionedEntityRow {
  list_id: string
  restaurant_id: string
  restaurant_global_key: string
  restaurant_snapshot_json: string | null
  position: number
  note: string
  created_at: string
  updated_at: string
}

type SyncEntityDatabaseRow = SyncRestaurantRow | SyncVisitRow | SyncDishRow |
  SyncVisitDishRow | SyncPhotoRow | SyncCompanionRow | SyncRecommendationSourceRow |
  SyncProfileRow | SyncRestaurantListRow | SyncRestaurantListItemRow

const SYNC_ENTITY_READ_SPECS: Record<SyncEntityType, {
  table: string
  ownerColumn: string
  idColumn: string
}> = {
  restaurant: { table: 'restaurants', ownerColumn: 'user_id', idColumn: 'id' },
  visit: { table: 'visits', ownerColumn: 'user_id', idColumn: 'id' },
  dish: { table: 'dishes', ownerColumn: 'user_id', idColumn: 'id' },
  visitDish: { table: 'visit_dishes', ownerColumn: 'user_id', idColumn: 'id' },
  photo: { table: 'photos', ownerColumn: 'user_id', idColumn: 'id' },
  companion: { table: 'dining_companions', ownerColumn: 'owner_user_id', idColumn: 'id' },
  recommendationSource: { table: 'recommendation_sources', ownerColumn: 'user_id', idColumn: 'id' },
  profile: { table: 'user_profiles', ownerColumn: 'user_id', idColumn: 'user_id' },
  restaurantList: { table: 'restaurant_lists', ownerColumn: 'user_id', idColumn: 'id' },
  restaurantListItem: { table: 'restaurant_list_items', ownerColumn: 'user_id', idColumn: 'id' },
}

export class SyncV1RequestError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
    this.name = 'SyncV1RequestError'
  }
}

export interface SyncV1PullObservation {
  ledgerQueryDurationMs: number
  hydrationQueryDurationMs: number
  responseAssemblyDurationMs: number
  changeCount: number
  hydratedEntityCount: number
  tombstoneCount: number
  cursorFrom: string
  cursorTo: string
  hasMore: boolean
}

export async function handleSyncV1Push(
  database: D1Database,
  viewerId: string,
  request: Request,
  access: { isPremium: boolean; visitPhotoLimit: number } = {
    isPremium: true,
    visitPhotoLimit: 20,
  },
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
    acknowledgements.push(await applyMutation(database, viewerId, mutation, access))
  }
  return { apiVersion: SYNC_API_VERSION, acknowledgements, serverTime: new Date().toISOString() }
}

export async function handleSyncV1Pull(
  database: D1Database,
  viewerId: string,
  request: Request,
  observation?: SyncV1PullObservation,
): Promise<SyncPullResponseV1> {
  const pullStartedAt = performance.now()
  const url = new URL(request.url)
  if (url.searchParams.get('schemaVersion') !== String(SYNC_SCHEMA_VERSION)) {
    throw new SyncV1RequestError('schemaVersion=1 is required.', 400)
  }
  const cursor = parseCursor(url.searchParams.get('cursor'))
  const requestedLimit = Number(url.searchParams.get('limit') ?? MAX_PULL_LIMIT)
  const limit = Number.isInteger(requestedLimit) && requestedLimit > 0
    ? Math.min(requestedLimit, MAX_PULL_LIMIT)
    : MAX_PULL_LIMIT
  const ledgerQueryStartedAt = performance.now()
  const result = await database.prepare(`SELECT * FROM ${CHANGE_LOG_TABLE}
    WHERE user_id = ? AND revision > ? ORDER BY revision ASC LIMIT ?`)
    .bind(viewerId, cursor, limit).all<ChangeRow>()
  if (observation) observation.ledgerQueryDurationMs += performance.now() - ledgerQueryStartedAt
  const changes = result.results
  const latestInPage = new Map<string, ChangeRow>()
  changes.forEach((change) => latestInPage.set(`${change.entity_type}:${change.entity_id}`, change))

  const pageRows = await readSyncEntityRows(
    database, viewerId, groupChangeIDs(latestInPage.values()), observation,
  )
  const activeRestaurantRows: SyncRestaurantRow[] = []
  const activeVisitRows: SyncVisitRow[] = []
  const activeDishRows: SyncDishRow[] = []
  const activeVisitDishRows: SyncVisitDishRow[] = []
  const activePhotoRows: SyncPhotoRow[] = []
  const activeCompanionRows: SyncCompanionRow[] = []
  const activeRecommendationSourceRows: SyncRecommendationSourceRow[] = []
  const activeProfileRows: SyncProfileRow[] = []
  const activeRestaurantListRows: SyncRestaurantListRow[] = []
  const activeRestaurantListItemRows: SyncRestaurantListItemRow[] = []
  const tombstones = [] as SyncPullResponseV1['tombstones']
  for (const change of latestInPage.values()) {
    const row = pageRows.get(change.entity_type)?.get(change.entity_id)
    if (!row || row.server_version !== change.server_version) continue
    if (change.operation === 'delete' || row.deleted_at) {
      tombstones.push(tombstone(change, row.deleted_at))
      continue
    }
    switch (change.entity_type) {
      case 'restaurant': activeRestaurantRows.push(row as SyncRestaurantRow); break
      case 'visit': activeVisitRows.push(row as SyncVisitRow); break
      case 'dish': activeDishRows.push(row as SyncDishRow); break
      case 'visitDish': activeVisitDishRows.push(row as SyncVisitDishRow); break
      case 'photo': activePhotoRows.push(row as SyncPhotoRow); break
      case 'companion': activeCompanionRows.push(row as SyncCompanionRow); break
      case 'recommendationSource':
        activeRecommendationSourceRows.push(row as SyncRecommendationSourceRow); break
      case 'profile': activeProfileRows.push(row as SyncProfileRow); break
      case 'restaurantList': activeRestaurantListRows.push(row as SyncRestaurantListRow); break
      case 'restaurantListItem':
        activeRestaurantListItemRows.push(row as SyncRestaurantListItemRow); break
    }
  }

  const restaurantRows = new Map(activeRestaurantRows.map((row) => [row.id, row]))
  const visitRows = new Map(activeVisitRows.map((row) => [row.id, row]))
  const dishRows = new Map(activeDishRows.map((row) => [row.id, row]))
  const requiredVisitIDs = new Set<string>()
  const requiredDishIDs = new Set<string>()
  const requiredRestaurantIDs = new Set<string>()
  activeVisitRows.forEach((row) => requiredRestaurantIDs.add(row.restaurant_id))
  activeDishRows.forEach((row) => requiredVisitIDs.add(row.visit_id))
  activeVisitDishRows.forEach((row) => {
    requiredVisitIDs.add(row.visit_id)
    requiredDishIDs.add(row.dish_id)
  })
  activePhotoRows.forEach((row) => {
    if (row.visit_id) requiredVisitIDs.add(row.visit_id)
    if (row.dish_id) requiredDishIDs.add(row.dish_id)
    if (row.restaurant_id) requiredRestaurantIDs.add(row.restaurant_id)
  })
  activeRestaurantListItemRows.forEach((row) => {
    if (!validRestaurantListPlaceSnapshot(row.restaurant_snapshot_json)) {
      requiredRestaurantIDs.add(row.restaurant_id)
    }
  })

  const parentRows = await readSyncEntityRows(database, viewerId, {
    restaurant: [...requiredRestaurantIDs].filter((id) => !restaurantRows.has(id)),
    visit: [...requiredVisitIDs].filter((id) => !visitRows.has(id)),
    dish: [...requiredDishIDs].filter((id) => !dishRows.has(id)),
  }, observation)
  for (const id of requiredVisitIDs) {
    if (visitRows.has(id)) continue
    const row = parentRows.get('visit')?.get(id) as SyncVisitRow | undefined
    if (!row) throw new SyncV1RequestError(`Child entity has no Visit ${id}.`, 500)
    visitRows.set(id, row)
  }
  for (const id of requiredDishIDs) {
    if (dishRows.has(id)) continue
    const row = parentRows.get('dish')?.get(id) as SyncDishRow | undefined
    if (!row) throw new SyncV1RequestError(`Child entity has no Dish ${id}.`, 500)
    dishRows.set(id, row)
  }
  for (const id of requiredRestaurantIDs) {
    if (restaurantRows.has(id)) continue
    const row = parentRows.get('restaurant')?.get(id) as SyncRestaurantRow | undefined
    if (!row) throw new SyncV1RequestError(`Child entity has no Restaurant ${id}.`, 500)
    restaurantRows.set(id, row)
  }

  const restaurantsRequiredByParentVisits = [...visitRows.values()]
    .map((row) => row.restaurant_id)
    .filter((id) => !restaurantRows.has(id))
  const additionalRestaurants = await readSyncEntityRows(database, viewerId, {
    restaurant: restaurantsRequiredByParentVisits,
  }, observation)
  for (const id of restaurantsRequiredByParentVisits) {
    if (restaurantRows.has(id)) continue
    const row = additionalRestaurants.get('restaurant')?.get(id) as SyncRestaurantRow | undefined
    if (!row) throw new SyncV1RequestError(`Visit has no Restaurant ${id}.`, 500)
    restaurantRows.set(id, row)
  }

  const identitiesByRestaurant = await readPlaceIdentitiesForRestaurants(
    database, viewerId, [...restaurantRows.keys()], observation,
  )
  const restaurants = [...restaurantRows.values()].map((row) => ({
    serverVersion: row.server_version,
    record: rowToRestaurant(row, identitiesByRestaurant.get(row.id) ?? []),
  }))
  const visits = [...visitRows.values()].map((row) => ({
    serverVersion: row.server_version, record: rowToVisit(row),
  }))
  const dishes = [...dishRows.values()].map((row) => ({
    serverVersion: row.server_version, record: rowToDish(row),
  }))
  const visitDishes = activeVisitDishRows.map((row) => ({
    serverVersion: row.server_version, record: rowToVisitDish(row),
  }))
  const photos = activePhotoRows.map((row) => ({
    serverVersion: row.server_version, record: rowToPhoto(row),
  }))
  const companions = activeCompanionRows.map((row) => ({
    serverVersion: row.server_version, record: rowToCompanion(row),
  }))
  const recommendationSources = activeRecommendationSourceRows.map((row) => ({
    serverVersion: row.server_version, record: rowToRecommendationSource(row),
  }))
  const profiles = activeProfileRows.map((row) => ({
    serverVersion: row.server_version, record: rowToProfile(row),
  }))
  const restaurantLists = activeRestaurantListRows.map((row) => ({
    serverVersion: row.server_version, record: rowToRestaurantList(row),
  }))
  const restaurantListItems = activeRestaurantListItemRows.map((row) => ({
    serverVersion: row.server_version,
    record: rowToRestaurantListItem(
      row,
      restaurantRows.get(row.restaurant_id),
      identitiesByRestaurant.get(row.restaurant_id) ?? [],
    ),
  }))

  const response: SyncPullResponseV1 = {
    apiVersion: SYNC_API_VERSION,
    schemaVersion: SYNC_SCHEMA_VERSION,
    restaurants,
    visits,
    dishes,
    visitDishes,
    photos,
    companions,
    recommendationSources,
    profiles,
    restaurantLists,
    restaurantListItems,
    tombstones,
    nextCursor: String(changes.at(-1)?.revision ?? cursor),
    hasMore: changes.length === limit,
    serverTime: new Date().toISOString(),
  }
  if (observation) {
    observation.changeCount = changes.length
    observation.hydratedEntityCount = restaurants.length + visits.length + dishes.length +
      visitDishes.length + photos.length + companions.length + recommendationSources.length +
      profiles.length + restaurantLists.length + restaurantListItems.length
    observation.tombstoneCount = tombstones.length
    observation.cursorFrom = String(cursor)
    observation.cursorTo = response.nextCursor
    observation.hasMore = response.hasMore
    observation.responseAssemblyDurationMs = Math.max(
      0,
      performance.now() - pullStartedAt - observation.ledgerQueryDurationMs -
        observation.hydrationQueryDurationMs,
    )
  }
  return response
}

function groupChangeIDs(changes: Iterable<ChangeRow>) {
  const grouped: Partial<Record<SyncEntityType, string[]>> = {}
  for (const change of changes) {
    const ids = grouped[change.entity_type] ?? []
    ids.push(change.entity_id)
    grouped[change.entity_type] = ids
  }
  return grouped
}

function placeholders(values: readonly unknown[]) {
  return values.map(() => '?').join(',')
}

async function readSyncEntityRows(
  database: D1Database,
  viewerId: string,
  idsByType: Partial<Record<SyncEntityType, string[]>>,
  observation?: SyncV1PullObservation,
) {
  const statements: D1PreparedStatement[] = []
  const statementTypes: SyncEntityType[] = []
  for (const entityType of Object.keys(SYNC_ENTITY_READ_SPECS) as SyncEntityType[]) {
    const ids = [...new Set(idsByType[entityType] ?? [])]
    const spec = SYNC_ENTITY_READ_SPECS[entityType]
    for (let offset = 0; offset < ids.length; offset += PULL_ID_BATCH_SIZE) {
      const chunk = ids.slice(offset, offset + PULL_ID_BATCH_SIZE)
      statements.push(database.prepare(`SELECT * FROM ${spec.table}
        WHERE ${spec.ownerColumn} = ? AND ${spec.idColumn} IN (${placeholders(chunk)})`)
        .bind(viewerId, ...chunk))
      statementTypes.push(entityType)
    }
  }
  const rowsByType = new Map<SyncEntityType, Map<string, SyncEntityDatabaseRow>>()
  if (!statements.length) return rowsByType
  const queryStartedAt = performance.now()
  const results = await database.batch<SyncEntityDatabaseRow>(statements)
  if (observation) observation.hydrationQueryDurationMs += performance.now() - queryStartedAt
  results.forEach((result, index) => {
    const entityType = statementTypes[index]
    const rows = rowsByType.get(entityType) ?? new Map<string, SyncEntityDatabaseRow>()
    for (const row of result.results ?? []) {
      const raw = row as unknown as Record<string, unknown>
      const id = String(raw[SYNC_ENTITY_READ_SPECS[entityType].idColumn])
      rows.set(id, row)
    }
    rowsByType.set(entityType, rows)
  })
  return rowsByType
}

async function readPlaceIdentitiesForRestaurants(
  database: D1Database,
  viewerId: string,
  restaurantIDs: string[],
  observation?: SyncV1PullObservation,
) {
  const ids = [...new Set(restaurantIDs)]
  const statements: D1PreparedStatement[] = []
  for (let offset = 0; offset < ids.length; offset += PULL_ID_BATCH_SIZE) {
    const chunk = ids.slice(offset, offset + PULL_ID_BATCH_SIZE)
    statements.push(database.prepare(`SELECT * FROM restaurant_place_identities
      WHERE user_id = ? AND restaurant_id IN (${placeholders(chunk)})
      ORDER BY restaurant_id ASC, is_primary DESC, updated_at ASC`).bind(viewerId, ...chunk))
  }
  if (!statements.length) return new Map<string, RestaurantPlaceIdentity[]>()
  const queryStartedAt = performance.now()
  const results = await database.batch<RestaurantPlaceIdentityRow>(statements)
  if (observation) observation.hydrationQueryDurationMs += performance.now() - queryStartedAt
  return groupRestaurantPlaceIdentities(results.flatMap((result) => result.results ?? []))
}

function validRestaurantListPlaceSnapshot(value: string | null) {
  if (!value) return false
  try {
    decodeRestaurantListPlace(JSON.parse(value))
    return true
  } catch {
    return false
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
    const idColumn = entityIDColumn(change.entityType)
    const operation = change.deletedAt ? 'delete' : 'upsert'
    const changedAt = new Date().toISOString()
    await database.batch([
      database.prepare(`UPDATE ${table}
        SET server_version = MAX(server_version, 0) + 1, last_mutation_id = ?
        WHERE ${idColumn} = ? AND ${ownerColumn} = ? AND updated_at = ?
          AND NOT EXISTS (
            SELECT 1 FROM ${CHANGE_LOG_TABLE} WHERE user_id = ? AND mutation_id = ?
          )`)
        .bind(mutationId, change.entityId, change.userId, change.updatedAt, change.userId, mutationId),
      database.prepare(`INSERT INTO ${CHANGE_LOG_TABLE} (
        user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
      )
      SELECT ?, ?, ?, ?, server_version, ?, ? FROM ${table}
      WHERE ${idColumn} = ? AND ${ownerColumn} = ? AND last_mutation_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM ${CHANGE_LOG_TABLE} WHERE user_id = ? AND mutation_id = ?
        )`)
        .bind(change.userId, change.entityType, change.entityId, operation, mutationId, changedAt,
          change.entityId, change.userId, mutationId, change.userId, mutationId),
    ])
  }
}

async function applyMutation(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  access: { isPremium: boolean; visitPhotoLimit: number },
) {
  const fingerprint = await sha256(stableSyncMutationJSON(mutation))
  const existingReceipt = await readReceipt(database, viewerId, mutation.mutationId)
  if (existingReceipt) return acknowledgement(existingReceipt, fingerprint, true)

  const current = await readEntityVersion(database, mutation.entityType, mutation.entityId)
  if (current && current.user_id !== viewerId) {
    throw new SyncV1RequestError('The authenticated user does not own this entity.', 403)
  }
  if (mutation.entityType === 'profile') {
    if (mutation.entityId !== viewerId) {
      throw new SyncV1RequestError('A Profile entity must belong to the authenticated Taste Map user.', 403)
    }
    if (mutation.operation === 'delete') {
      throw new SyncV1RequestError('Profile deletion is not available through Sync V1.', 405)
    }
    const profile = mutation.payload as OwnProfileSyncContractV1
    if ([...profile.displayName].length > 30) {
      const legacy = await database.prepare(`SELECT display_name FROM user_profiles
        WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`)
        .bind(viewerId).first<{ display_name: string }>()
      if (legacy?.display_name !== profile.displayName) {
        throw new SyncV1RequestError(
          'New Profile display names are limited to 30 Unicode code points.',
          400,
        )
      }
    }
    if (profile.avatarPhotoId) {
      const avatar = await database.prepare(`SELECT id FROM photos
        WHERE id = ? AND user_id = ? AND kind = 'avatar' AND deleted_at IS NULL LIMIT 1`)
        .bind(profile.avatarPhotoId, viewerId).first<{ id: string }>()
      if (!avatar) {
        throw new SyncV1RequestError('Profile.avatarPhotoId must reference an active owned avatar Photo.', 403)
      }
      if (!access.isPremium) {
        const existingProfile = await database.prepare(`SELECT avatar_photo_id FROM user_profiles
          WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(viewerId)
          .first<{ avatar_photo_id: string | null }>()
        if (existingProfile?.avatar_photo_id !== profile.avatarPhotoId) {
          throw new SyncV1RequestError('A new custom Profile avatar requires Premium.', 403)
        }
      }
    }
  }
  if (mutation.operation === 'upsert' &&
    (mutation.entityType === 'companion' || mutation.entityType === 'recommendationSource')) {
    const directory = mutation.payload as DiningCompanionSyncContractV1 | RecommendationSourceSyncContractV1
    if (mutation.entityType === 'companion' && directory.linkedTasteMapUserId) {
      const currentLink = await database.prepare(`SELECT linked_user_id FROM dining_companions
        WHERE id = ? AND owner_user_id = ? LIMIT 1`).bind(mutation.entityId, viewerId)
        .first<{ linked_user_id: string | null }>()
      if (currentLink?.linked_user_id !== directory.linkedTasteMapUserId) {
        const acceptedFriend = await database.prepare(`SELECT id FROM friendships
          WHERE status = 'accepted' AND deleted_at IS NULL AND (
            (requester_id = ? AND addressee_id = ?) OR
            (requester_id = ? AND addressee_id = ?)
          ) LIMIT 1`).bind(
            viewerId, directory.linkedTasteMapUserId,
            directory.linkedTasteMapUserId, viewerId,
          ).first()
        if (!acceptedFriend) {
          throw new SyncV1RequestError(
            'Companion.linkedTasteMapUserId must reference an accepted friend.', 403,
          )
        }
      }
    }
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
    if (!current && photo.visitId) {
      const count = await database.prepare(`SELECT COUNT(*) AS count FROM photos
        WHERE user_id = ? AND visit_id = ? AND deleted_at IS NULL`)
        .bind(viewerId, photo.visitId).first<{ count: number | string }>()
      if (Number(count?.count ?? 0) >= access.visitPhotoLimit) {
        throw new SyncV1RequestError(
          `This Visit has reached its ${access.visitPhotoLimit}-Photo entitlement limit.`, 403,
        )
      }
    }
  }
  if (mutation.entityType === 'restaurantList' && mutation.operation === 'upsert') {
    const list = mutation.payload as RestaurantListSyncContractV1
    if (list.customCoverPhotoId) {
      const photo = await database.prepare(`SELECT id FROM photos
        WHERE id = ? AND user_id = ? AND deleted_at IS NULL LIMIT 1`)
        .bind(list.customCoverPhotoId, viewerId).first<{ id: string }>()
      if (!photo) throw new SyncV1RequestError('RestaurantList cover must reference an active owned Photo.', 403)
    }
  }
  if (mutation.entityType === 'restaurantListItem' && mutation.operation === 'upsert') {
    const item = mutation.payload as RestaurantListItemSyncContractV1
    const parent = await database.prepare(`SELECT id FROM restaurant_lists
      WHERE id = ? AND user_id = ? AND deleted_at IS NULL LIMIT 1`)
      .bind(item.listId, viewerId).first<{ id: string }>()
    if (!parent) {
      throw new SyncV1RequestError('RestaurantListItem.listId must reference an active owned RestaurantList.', 403)
    }
    const duplicate = await database.prepare(`SELECT id, server_version FROM restaurant_list_items
      WHERE list_id = ? AND restaurant_global_key = ? AND deleted_at IS NULL AND id <> ? LIMIT 1`)
      .bind(item.listId, item.restaurantGlobalKey, mutation.entityId)
      .first<{ id: string; server_version: number }>()
    if (duplicate) {
      return recordConflict(database, viewerId, mutation, fingerprint, duplicate.server_version,
        `duplicate_restaurant:${duplicate.id}`)
    }
  }
  // Authentication bootstraps an empty server Profile before the first sync request.
  // An offline-first client can independently create its local Profile at base version 0.
  // Adopt that local record only while the server row is still the untouched bootstrap;
  // once either side has edited it, normal optimistic concurrency remains authoritative.
  const applicableMutation = canAdoptUntouchedBootstrapProfile(current, viewerId, mutation)
    ? { ...mutation, baseVersion: current!.server_version }
    : mutation
  const conflictReason = conflictForMutation(current, applicableMutation)
  if (conflictReason) {
    return recordConflict(database, viewerId, mutation, fingerprint, current?.server_version ?? 0, conflictReason)
  }

  const nextVersion = (current?.server_version ?? 0) + 1
  const processedAt = new Date().toISOString()
  const statements = (() => {
    switch (applicableMutation.entityType) {
      case 'restaurant': return restaurantMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'visit': return visitMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'dish': return dishMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'visitDish': return visitDishMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'photo': return photoMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'companion': return companionMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'recommendationSource': return recommendationSourceMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'profile': return profileMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'restaurantList': return restaurantListMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
      case 'restaurantListItem': return restaurantListItemMutationStatements(database, viewerId, applicableMutation, fingerprint, nextVersion, processedAt)
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
  if (current.deleted_at && !(
    (mutation.entityType === 'visitDish' || mutation.entityType === 'restaurantListItem') &&
    mutation.operation === 'upsert'
  )) return 'entity_deleted'
  return null
}

function canAdoptUntouchedBootstrapProfile(
  current: VersionedEntityRow | null,
  viewerId: string,
  mutation: SyncMutationV1,
) {
  return mutation.entityType === 'profile' &&
    mutation.operation === 'upsert' &&
    mutation.entityId === viewerId &&
    mutation.baseVersion === 0 &&
    current?.user_id === viewerId &&
    current.server_version === 1 &&
    current.deleted_at === null &&
    current.last_mutation_id === `bootstrap:profile:${viewerId}`
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

function profileMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  const profile = mutation.payload as OwnProfileSyncContractV1
  const statement = database.prepare(`INSERT INTO user_profiles (
    user_id, display_name, bio, city, avatar_photo_id, avatar_preset_id,
    visibility, created_at, updated_at, deleted_at, server_version,
    last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
  ON CONFLICT(user_id) DO UPDATE SET
    display_name = excluded.display_name, bio = excluded.bio, city = excluded.city,
    avatar_photo_id = excluded.avatar_photo_id,
    avatar_preset_id = excluded.avatar_preset_id,
    visibility = excluded.visibility, updated_at = excluded.updated_at,
    deleted_at = NULL, server_version = excluded.server_version,
    last_mutation_id = excluded.last_mutation_id
  WHERE user_profiles.server_version = ? AND user_profiles.deleted_at IS NULL`)
    .bind(
      viewerId, profile.displayName, profile.bio, profile.city,
      profile.avatarPhotoId, profile.avatarPresetId, profile.visibility,
      profile.createdAt, profile.updatedAt, nextVersion, mutation.mutationId,
      mutation.baseVersion,
    )
  const legacyProjection = database.prepare(`UPDATE users SET
    nickname = ?, bio = ?, city = ?, avatar_photo_id = ?, avatar_preset_id = ?,
    map_sharing_enabled = ?, map_visibility = ?, updated_at = ?
    WHERE id = ?`)
    .bind(
      profile.displayName, profile.bio, profile.city, profile.avatarPhotoId,
      profile.avatarPresetId, profile.visibility === 'private' ? 0 : 1,
      profile.visibility, profile.updatedAt, viewerId,
    )
  return finalMutationStatements(
    database, viewerId, mutation, fingerprint, nextVersion, processedAt,
    statement, [legacyProjection],
  )
}

function restaurantListMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  if (mutation.operation === 'delete') {
    const deleteList = database.prepare(`UPDATE restaurant_lists
        SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
        WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL`)
        .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
          mutation.entityId, viewerId, mutation.baseVersion)
    const cascadeItems = database.prepare(`UPDATE restaurant_list_items
      SET deleted_at = ?, updated_at = ?, server_version = server_version + 1,
          last_mutation_id = 'cascade:' || ? || ':' || id
      WHERE list_id = ? AND user_id = ? AND deleted_at IS NULL`)
      .bind(processedAt, processedAt, mutation.mutationId, mutation.entityId, viewerId)
    const logCascades = database.prepare(`INSERT OR IGNORE INTO ${CHANGE_LOG_TABLE} (
        user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
      ) SELECT user_id, 'restaurantListItem', id, 'delete', server_version,
        last_mutation_id, ? FROM restaurant_list_items
      WHERE list_id = ? AND user_id = ? AND deleted_at = ?
        AND last_mutation_id = 'cascade:' || ? || ':' || id`)
      .bind(processedAt, mutation.entityId, viewerId, processedAt, mutation.mutationId)
    return finalMutationStatements(
      database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      deleteList, [cascadeItems, logCascades],
    )
  }
  const list = mutation.payload as RestaurantListSyncContractV1
  const statement = database.prepare(`INSERT INTO restaurant_lists (
    id, user_id, title, description, visibility, is_ranked, cover_mode,
    custom_cover_photo_id, created_at, updated_at, deleted_at,
    server_version, last_mutation_id, active_item_count
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 0)
  ON CONFLICT(id) DO UPDATE SET
    title = excluded.title, description = excluded.description,
    visibility = excluded.visibility, is_ranked = excluded.is_ranked,
    cover_mode = excluded.cover_mode,
    custom_cover_photo_id = excluded.custom_cover_photo_id,
    updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version,
    last_mutation_id = excluded.last_mutation_id
  WHERE restaurant_lists.user_id = ? AND restaurant_lists.server_version = ?
    AND restaurant_lists.deleted_at IS NULL`)
    .bind(
      mutation.entityId, viewerId, list.title, list.description, list.visibility,
      list.isRanked ? 1 : 0, list.coverMode, list.customCoverPhotoId,
      list.createdAt, list.updatedAt, nextVersion, mutation.mutationId,
      viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(database, viewerId, mutation, fingerprint, nextVersion, processedAt, statement)
}

function restaurantListItemMutationStatements(
  database: D1Database,
  viewerId: string,
  mutation: SyncMutationV1,
  fingerprint: string,
  nextVersion: number,
  processedAt: string,
) {
  const countStatement = database.prepare(`UPDATE restaurant_lists SET active_item_count = (
      SELECT COUNT(*) FROM restaurant_list_items rli
      WHERE rli.list_id = restaurant_lists.id AND rli.deleted_at IS NULL
    ) WHERE id = (SELECT list_id FROM restaurant_list_items WHERE id = ? AND user_id = ?)
      AND user_id = ?`)
    .bind(mutation.entityId, viewerId, viewerId)
  if (mutation.operation === 'delete') {
    const statement = database.prepare(`UPDATE restaurant_list_items
      SET deleted_at = ?, updated_at = ?, server_version = ?, last_mutation_id = ?
      WHERE id = ? AND user_id = ? AND server_version = ? AND deleted_at IS NULL`)
      .bind(processedAt, processedAt, nextVersion, mutation.mutationId,
        mutation.entityId, viewerId, mutation.baseVersion)
    return finalMutationStatements(
      database, viewerId, mutation, fingerprint, nextVersion, processedAt,
      statement, [countStatement],
    )
  }
  const item = mutation.payload as RestaurantListItemSyncContractV1
  const statement = database.prepare(`INSERT INTO restaurant_list_items (
    id, user_id, list_id, restaurant_id, restaurant_global_key,
    restaurant_snapshot_json, position, note, created_at, updated_at,
    deleted_at, server_version, last_mutation_id
  ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?
  WHERE EXISTS (
    SELECT 1 FROM restaurant_lists WHERE id = ? AND user_id = ? AND deleted_at IS NULL
  )
  ON CONFLICT(id) DO UPDATE SET
    list_id = excluded.list_id, restaurant_id = excluded.restaurant_id,
    restaurant_global_key = excluded.restaurant_global_key,
    restaurant_snapshot_json = excluded.restaurant_snapshot_json,
    position = excluded.position, note = excluded.note,
    updated_at = excluded.updated_at, deleted_at = NULL,
    server_version = excluded.server_version,
    last_mutation_id = excluded.last_mutation_id
  WHERE restaurant_list_items.user_id = ? AND restaurant_list_items.server_version = ?`)
    .bind(
      mutation.entityId, viewerId, item.listId, item.restaurantId,
      item.restaurantGlobalKey, JSON.stringify(item.restaurant), item.position,
      item.note, item.createdAt, item.updatedAt, nextVersion, mutation.mutationId,
      item.listId, viewerId, viewerId, mutation.baseVersion,
    )
  return finalMutationStatements(
    database, viewerId, mutation, fingerprint, nextVersion, processedAt,
    statement, [countStatement],
  )
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
  const idColumn = entityIDColumn(mutation.entityType)
  const operation = mutation.operation === 'delete' ? 'delete' : 'upsert'
  const logStatement = database.prepare(`INSERT INTO ${CHANGE_LOG_TABLE} (
    user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
  )
  SELECT ?, ?, ?, ?, server_version, ?, ? FROM ${table}
  WHERE ${idColumn} = ? AND ${ownerColumn} = ? AND last_mutation_id = ?`)
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
  const idColumn = entityIDColumn(type)
  return database.prepare(`SELECT ${idColumn} AS id, ${ownerColumn} AS user_id, server_version, deleted_at, last_mutation_id FROM ${table} WHERE ${idColumn} = ?`)
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
  if (visit.sharedMealId) {
    const legacy = await database.prepare(`SELECT shared_meal_id FROM visits
      WHERE id = ? AND user_id = ? LIMIT 1`).bind(visit.id, viewerId)
      .first<{ shared_meal_id: string | null }>()
    if (legacy?.shared_meal_id === visit.sharedMealId) return
    const invitation = await database.prepare(`SELECT sm.id FROM shared_meals sm
      JOIN shared_meal_participants smp ON smp.shared_meal_id = sm.id
      WHERE sm.id = ? AND sm.deleted_at IS NULL AND sm.revoked_at IS NULL
        AND smp.user_id = ? AND smp.status = 'accepted' AND smp.deleted_at IS NULL
      LIMIT 1`).bind(visit.sharedMealId, viewerId).first<{ id: string }>()
    if (!invitation) {
      throw new SyncV1RequestError(
        'Visit.sharedMealId must reference an accepted active invitation for the authenticated user.', 403,
      )
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
    case 'profile': return 'user_profiles'
    case 'restaurantList': return 'restaurant_lists'
    case 'restaurantListItem': return 'restaurant_list_items'
  }
}

function entityOwnerColumn(type: SyncEntityType) {
  return type === 'companion' ? 'owner_user_id' : 'user_id'
}

function entityIDColumn(type: SyncEntityType) {
  return type === 'profile' ? 'user_id' : 'id'
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

function rowToProfile(row: SyncProfileRow): OwnProfileSyncContractV1 {
  return {
    schemaVersion: 1,
    userId: row.user_id,
    displayName: row.display_name,
    bio: row.bio,
    city: row.city,
    avatarPhotoId: row.avatar_photo_id,
    avatarPresetId: row.avatar_preset_id,
    visibility: row.visibility,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: null,
  }
}

function rowToRestaurantList(row: SyncRestaurantListRow): RestaurantListSyncContractV1 {
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    title: row.title,
    description: row.description,
    visibility: row.visibility,
    isRanked: Boolean(row.is_ranked),
    coverMode: row.cover_mode,
    customCoverPhotoId: row.custom_cover_photo_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToRestaurantListItem(
  row: SyncRestaurantListItemRow,
  restaurant: SyncRestaurantRow | undefined,
  identities: RestaurantPlaceIdentity[],
): RestaurantListItemSyncContractV1 {
  let place: RestaurantListPlaceContractV1 | null = null
  if (row.restaurant_snapshot_json) {
    try { place = decodeRestaurantListPlace(JSON.parse(row.restaurant_snapshot_json)) } catch { place = null }
  }
  if (!place) {
    if (!restaurant) throw new SyncV1RequestError(`RestaurantListItem ${row.id} has no place projection.`, 500)
    const safeIdentities = identities.length ? identities : [{
      provider: 'manual' as const,
      externalId: `tastemap:${restaurant.id}`,
      isPrimary: true,
      createdAt: restaurant.created_at,
      updatedAt: restaurant.updated_at,
    }]
    place = {
      globalKey: row.restaurant_global_key || `${safeIdentities[0].provider}:${safeIdentities[0].externalId}`,
      restaurantId: restaurant.id,
      placeIdentities: safeIdentities.map((identity) => ({
        provider: identity.provider,
        externalId: identity.externalId,
        isPrimary: identity.isPrimary,
      })),
      name: restaurant.name,
      address: restaurant.address,
      city: restaurant.city,
      latitude: restaurant.latitude,
      longitude: restaurant.longitude,
      markerPhotoId: restaurant.marker_photo_id,
      merchantImageUrl: restaurant.merchant_image_url,
      markerEmoji: restaurant.marker_emoji,
    }
  }
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    listId: row.list_id,
    restaurantId: row.restaurant_id,
    restaurantGlobalKey: row.restaurant_global_key || place.globalKey,
    position: row.position,
    note: row.note,
    restaurant: place,
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
