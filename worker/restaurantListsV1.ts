import {
  RESTAURANT_LIST_PUBLIC_API_VERSION,
  type PublicListDetailDTO,
  type PublicListItemDTO,
  type PublicListOwnerDTO,
  type PublicListPreviewRestaurantDTO,
  type PublicListSummaryDTO,
  type PublicListSummaryPageDTO,
} from '../src/contracts/restaurantListPublicContract'
import {
  decodeRestaurantListPlace,
  type RestaurantListPlaceContractV1,
  type RestaurantListVisibilityContract,
} from '../src/contracts/restaurantListContract'
import type { ProfileAvatarPresetContract } from '../src/contracts/profileContract'
import type { RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { consumePublicAPIQuota } from './publicAPIRateLimit'

const DEFAULT_LIMIT = 20
const MAX_LIMIT = 50

interface ListRow {
  id: string
  user_id: string
  title: string
  description: string
  visibility: RestaurantListVisibilityContract
  is_ranked: number
  cover_mode: 'automatic' | 'custom'
  custom_cover_photo_id: string | null
  active_item_count: number
  updated_at: string
  display_name: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract
}

interface ItemRow {
  id: string
  list_id: string
  restaurant_id: string
  restaurant_global_key: string
  restaurant_snapshot_json: string | null
  position: number
  note: string
  name: string | null
  address: string | null
  city: string | null
  latitude: number | null
  longitude: number | null
  marker_photo_id: string | null
  merchant_image_url: string | null
  marker_emoji: string | null
}

interface IdentityRow {
  provider: RestaurantPlaceProvider
  external_id: string
  is_primary: number
}

export class RestaurantListsV1RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

export async function handleRestaurantListsV1(
  request: Request,
  database: D1Database,
  viewerId: string,
): Promise<PublicListSummaryPageDTO | PublicListDetailDTO> {
  if (request.method !== 'GET') {
    throw new RestaurantListsV1RequestError('Restaurant list method is not supported.', 405)
  }
  await consumePublicAPIQuota(database, viewerId, 'restaurant-list-read', 180)
  const url = new URL(request.url)
  const profileMatch = url.pathname.match(/^\/api\/v1\/lists\/users\/([^/]+)$/)
  if (profileMatch) {
    return readProfileLists(database, viewerId, decodeURIComponent(profileMatch[1]), url)
  }
  const detailMatch = url.pathname.match(/^\/api\/v1\/lists\/([^/]+)$/)
  if (detailMatch) {
    return readListDetail(database, viewerId, decodeURIComponent(detailMatch[1]), url)
  }
  throw new RestaurantListsV1RequestError('Restaurant list endpoint was not found.', 404)
}

async function readProfileLists(
  database: D1Database,
  viewerId: string,
  ownerId: string,
  url: URL,
): Promise<PublicListSummaryPageDTO> {
  const limit = pageLimit(url)
  const offset = decodeCursor(url.searchParams.get('cursor'))
  const owner = await readOwner(database, ownerId)
  if (!owner) throw new RestaurantListsV1RequestError('Profile was not found.', 404)
  const result = await database.prepare(`SELECT rl.*, up.display_name, up.avatar_photo_id, up.avatar_preset_id
    FROM restaurant_lists rl
    JOIN user_profiles up ON up.user_id = rl.user_id AND up.deleted_at IS NULL
    WHERE rl.user_id = ? AND rl.deleted_at IS NULL AND ${visibilityClause('rl')}
    ORDER BY rl.updated_at DESC, rl.id ASC LIMIT ? OFFSET ?`)
    .bind(ownerId, viewerId, viewerId, viewerId, limit + 1, offset).all<ListRow>()
  const visible = result.results.slice(0, limit)
  const previews = await readPreviewRows(database, visible.map((row) => row.id))
  return {
    apiVersion: RESTAURANT_LIST_PUBLIC_API_VERSION,
    items: await Promise.all(visible.map((row) => summary(
      database, viewerId, row, previews.get(row.id) ?? [],
    ))),
    nextCursor: result.results.length > limit ? encodeCursor(offset + limit) : null,
    generatedAt: new Date().toISOString(),
  }
}

async function readListDetail(
  database: D1Database,
  viewerId: string,
  listId: string,
  url: URL,
): Promise<PublicListDetailDTO> {
  const list = await database.prepare(`SELECT rl.*, up.display_name, up.avatar_photo_id, up.avatar_preset_id
    FROM restaurant_lists rl
    JOIN user_profiles up ON up.user_id = rl.user_id AND up.deleted_at IS NULL
    WHERE rl.id = ? AND rl.deleted_at IS NULL AND ${visibilityClause('rl')} LIMIT 1`)
    .bind(listId, viewerId, viewerId, viewerId).first<ListRow>()
  if (!list) throw new RestaurantListsV1RequestError('Restaurant list is unavailable.', 404)
  const limit = pageLimit(url)
  const offset = decodeCursor(url.searchParams.get('cursor'))
  const rows = await readItemRows(database, list.id, limit + 1, offset)
  const items = await Promise.all(rows.slice(0, limit).map((row) => publicItem(database, viewerId, list.user_id, row)))
  return {
    apiVersion: RESTAURANT_LIST_PUBLIC_API_VERSION,
    list: await summary(database, viewerId, list),
    items,
    nextCursor: rows.length > limit ? encodeCursor(offset + limit) : null,
    generatedAt: new Date().toISOString(),
  }
}

function visibilityClause(alias: string) {
  return `(
    ${alias}.user_id = ? OR ${alias}.visibility = 'public' OR (
      ${alias}.visibility = 'friends' AND EXISTS (
        SELECT 1 FROM friendships f
        WHERE f.status = 'accepted' AND f.deleted_at IS NULL AND (
          (f.requester_id = ${alias}.user_id AND f.addressee_id = ?) OR
          (f.addressee_id = ${alias}.user_id AND f.requester_id = ?)
        )
      )
    )
  )`
}

async function summary(
  database: D1Database,
  viewerId: string,
  row: ListRow,
  previewRows?: ItemRow[],
): Promise<PublicListSummaryDTO> {
  const previews = previewRows ?? await readItemRows(database, row.id, 4, 0)
  const previewRestaurants: PublicListPreviewRestaurantDTO[] = await Promise.all(previews.map(async (item) => {
    const place = await placeForItem(database, item)
    return {
      globalKey: place.globalKey,
      name: place.name,
      photoId: await authorizedPhotoID(database, viewerId, row.user_id, place.markerPhotoId),
      merchantImageUrl: place.merchantImageUrl,
      markerEmoji: place.markerEmoji,
    }
  }))
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    visibility: row.visibility,
    isRanked: Boolean(row.is_ranked),
    coverMode: row.cover_mode,
    customCoverPhotoId: await authorizedPhotoID(database, viewerId, row.user_id, row.custom_cover_photo_id),
    restaurantCount: row.active_item_count,
    previewRestaurants,
    owner: ownerFromRow(row),
    updatedAt: row.updated_at,
  }
}

async function readPreviewRows(database: D1Database, listIDs: string[]) {
  const grouped = new Map<string, ItemRow[]>()
  if (!listIDs.length) return grouped
  const placeholders = listIDs.map(() => '?').join(', ')
  const result = await database.prepare(`WITH ranked AS (
      SELECT rli.*,
        r.name, r.address, r.city, r.latitude, r.longitude,
        r.marker_photo_id, r.merchant_image_url, r.marker_emoji,
        ROW_NUMBER() OVER (
          PARTITION BY rli.list_id
          ORDER BY rli.position ASC, rli.created_at ASC, rli.id ASC
        ) AS preview_rank
      FROM restaurant_list_items rli
      LEFT JOIN restaurants r ON r.id = rli.restaurant_id AND r.user_id = rli.user_id
      WHERE rli.list_id IN (${placeholders}) AND rli.deleted_at IS NULL
    ) SELECT * FROM ranked WHERE preview_rank <= 4
    ORDER BY list_id ASC, preview_rank ASC`).bind(...listIDs).all<ItemRow>()
  for (const row of result.results) {
    const values = grouped.get(row.list_id) ?? []
    values.push(row)
    grouped.set(row.list_id, values)
  }
  return grouped
}

async function publicItem(
  database: D1Database,
  viewerId: string,
  ownerId: string,
  row: ItemRow,
): Promise<PublicListItemDTO> {
  const place = await placeForItem(database, row)
  return {
    id: row.id,
    position: row.position,
    note: row.note,
    restaurant: {
      ...place,
      markerPhotoId: await authorizedPhotoID(database, viewerId, ownerId, place.markerPhotoId),
    },
  }
}

async function placeForItem(database: D1Database, row: ItemRow): Promise<RestaurantListPlaceContractV1> {
  if (row.restaurant_snapshot_json) {
    try {
      return decodeRestaurantListPlace(JSON.parse(row.restaurant_snapshot_json))
    } catch {
      // A stale snapshot never widens access. Fall through to the allowlisted
      // Restaurant projection and repair on the next owner mutation.
    }
  }
  const identities = await database.prepare(`SELECT provider, external_id, is_primary
    FROM restaurant_place_identities WHERE restaurant_id = ?
    ORDER BY is_primary DESC, updated_at ASC`).bind(row.restaurant_id).all<IdentityRow>()
  const placeIdentities = identities.results.length ? identities.results.map((identity) => ({
    provider: identity.provider,
    externalId: identity.external_id,
    isPrimary: Boolean(identity.is_primary),
  })) : [{ provider: 'manual' as const, externalId: `tastemap:${row.restaurant_id}`, isPrimary: true }]
  return {
    globalKey: row.restaurant_global_key || `${placeIdentities[0].provider}:${placeIdentities[0].externalId}`,
    restaurantId: row.restaurant_id,
    placeIdentities,
    name: row.name ?? '餐厅',
    address: row.address ?? '',
    city: row.city ?? '',
    latitude: row.latitude ?? 0,
    longitude: row.longitude ?? 0,
    markerPhotoId: row.marker_photo_id,
    merchantImageUrl: row.merchant_image_url,
    markerEmoji: row.marker_emoji || '🍽️',
  }
}

async function readItemRows(database: D1Database, listId: string, limit: number, offset: number) {
  const result = await database.prepare(`SELECT rli.*,
      r.name, r.address, r.city, r.latitude, r.longitude,
      r.marker_photo_id, r.merchant_image_url, r.marker_emoji
    FROM restaurant_list_items rli
    LEFT JOIN restaurants r ON r.id = rli.restaurant_id AND r.user_id = rli.user_id
    WHERE rli.list_id = ? AND rli.deleted_at IS NULL
    ORDER BY rli.position ASC, rli.created_at ASC, rli.id ASC
    LIMIT ? OFFSET ?`).bind(listId, limit, offset).all<ItemRow>()
  return result.results
}

async function authorizedPhotoID(
  database: D1Database,
  viewerId: string,
  ownerId: string,
  photoId: string | null,
) {
  if (!photoId) return null
  if (viewerId === ownerId) return photoId
  const row = await database.prepare(`SELECT id FROM photos p WHERE p.id = ? AND p.user_id = ?
    AND p.deleted_at IS NULL AND (
      p.visibility = 'public' OR (p.visibility = 'friends' AND EXISTS (
        SELECT 1 FROM friendships f WHERE f.status = 'accepted' AND f.deleted_at IS NULL AND (
          (f.requester_id = ? AND f.addressee_id = ?) OR
          (f.requester_id = ? AND f.addressee_id = ?)
        )
      ))
    ) LIMIT 1`).bind(photoId, ownerId, ownerId, viewerId, viewerId, ownerId).first<{ id: string }>()
  return row?.id ?? null
}

async function readOwner(database: D1Database, ownerId: string): Promise<PublicListOwnerDTO | null> {
  const row = await database.prepare(`SELECT user_id, display_name, avatar_photo_id, avatar_preset_id
    FROM user_profiles WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`)
    .bind(ownerId).first<{ user_id: string; display_name: string; avatar_photo_id: string | null; avatar_preset_id: ProfileAvatarPresetContract }>()
  return row ? { userId: row.user_id, displayName: row.display_name,
    avatarPhotoId: row.avatar_photo_id, avatarPresetId: row.avatar_preset_id } : null
}

function ownerFromRow(row: ListRow): PublicListOwnerDTO {
  return {
    userId: row.user_id,
    displayName: row.display_name,
    avatarPhotoId: row.avatar_photo_id,
    avatarPresetId: row.avatar_preset_id,
  }
}

function pageLimit(url: URL) {
  const requested = Number(url.searchParams.get('limit') ?? DEFAULT_LIMIT)
  return Number.isInteger(requested) ? Math.min(MAX_LIMIT, Math.max(1, requested)) : DEFAULT_LIMIT
}

function encodeCursor(offset: number) {
  return btoa(JSON.stringify({ offset })).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

function decodeCursor(value: string | null) {
  if (!value) return 0
  try {
    const normalized = value.replaceAll('-', '+').replaceAll('_', '/')
    const parsed: unknown = JSON.parse(atob(normalized))
    if (!parsed || typeof parsed !== 'object' || !Number.isInteger((parsed as { offset?: unknown }).offset) ||
      Number((parsed as { offset: number }).offset) < 0) throw new Error()
    return (parsed as { offset: number }).offset
  } catch {
    throw new RestaurantListsV1RequestError('Restaurant list cursor is invalid.', 400)
  }
}
