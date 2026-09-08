export type RestaurantUGCSourceType = 'currentOwnerPhoto' | 'activityAuthorPhoto' | 'publicUGC' | 'nonPublic'

export interface RestaurantUGCPhotoRecord {
  id: string
  restaurant_id: string
  visit_id: string | null
  user_id: string
  visibility: 'private' | 'friends' | 'public'
  visit_visibility: 'private' | 'friends' | 'public' | null
  profile_visibility: 'private' | 'friends' | 'public' | null
  created_at: string
  sort_order: number
  marker_photo_id: string | null
  kind?: string | null
  storage_key?: string | null
  thumbnail_storage_key?: string | null
  sync_status?: string | null
  deleted_at?: string | null
  binary_deleted_at?: string | null
  moderation_eligible?: number | boolean | null
}

export interface RestaurantUGCPhotoSelection {
  sourceType: RestaurantUGCSourceType
  photo: RestaurantUGCPhotoRecord
  exportAllowed: boolean
}

export type RestaurantVisualSurface =
  | 'map'
  | 'search'
  | 'nearby'
  | 'detail'
  | 'following'
  | 'for_you'
  | 'similar_taste'
  | 'latest'
  | 'trending'

export interface RestaurantVisualSelectionContext {
  surface: RestaurantVisualSurface
  restaurantIDs: readonly string[]
  viewerID: string
  activityVisitID?: string | null
  canSeeFriendsActivity?: boolean
}

export class RestaurantUGCImagePool {
  private readonly byVisit = new Map<string, RestaurantUGCPhotoRecord[]>()
  private readonly byRestaurant = new Map<string, RestaurantUGCPhotoRecord[]>()

  constructor(records: RestaurantUGCPhotoRecord[]) {
    for (const record of records.filter(active)) {
      if (record.visit_id) this.byVisit.set(record.visit_id, [...(this.byVisit.get(record.visit_id) ?? []), record])
      this.byRestaurant.set(record.restaurant_id, [...(this.byRestaurant.get(record.restaurant_id) ?? []), record])
    }
  }

  currentOwner(restaurantIDs: readonly string[], viewerID: string) {
    return this.pick(restaurantIDs.flatMap((id) => this.byRestaurant.get(id) ?? [])
      .filter((photo) => photo.user_id === viewerID), 'currentOwnerPhoto', true)
  }

  activity(visitID: string, viewerID: string, canSeeFriends: boolean) {
    return this.pick((this.byVisit.get(visitID) ?? []).filter((photo) =>
      photo.user_id === viewerID || isPublic(photo) || (canSeeFriends && isFriendsVisible(photo)),
    ), 'activityAuthorPhoto', false)
  }

  /** Gallery order is Visit order, not the Restaurant marker-photo preference. */
  activityPhotos(visitID: string, authorID: string, viewerID: string, canSeeFriends: boolean): RestaurantUGCPhotoSelection[] {
    const seen = new Set<string>()
    return [...(this.byVisit.get(visitID) ?? [])].filter((photo) =>
      photo.user_id === authorID &&
      (photo.user_id === viewerID || isPublic(photo) || (canSeeFriends && isFriendsVisible(photo))),
    ).sort((left, right) => left.sort_order - right.sort_order ||
      right.created_at.localeCompare(left.created_at) || left.id.localeCompare(right.id),
    ).filter((photo) => !seen.has(photo.id) && Boolean(seen.add(photo.id)))
      .map((photo) => ({ sourceType: 'activityAuthorPhoto', photo, exportAllowed: photo.user_id === viewerID }))
  }

  publicUGC(restaurantIDs: readonly string[]) {
    return this.pick(restaurantIDs.flatMap((id) => this.byRestaurant.get(id) ?? []).filter(isPublic), 'publicUGC', false)
  }

  private pick(records: RestaurantUGCPhotoRecord[], sourceType: RestaurantUGCSourceType, exportAllowed: boolean): RestaurantUGCPhotoSelection | null {
    const photo = [...records].sort((left, right) =>
      Number(right.marker_photo_id === right.id) - Number(left.marker_photo_id === left.id) ||
      left.sort_order - right.sort_order ||
      right.created_at.localeCompare(left.created_at) ||
      left.id.localeCompare(right.id),
    )[0]
    return photo ? { sourceType, photo, exportAllowed: exportAllowed && sourceType === 'currentOwnerPhoto' } : null
  }
}

/**
 * Batch-load only the accepted page's concrete Visits. A capped city thumbnail
 * pool must not silently truncate an activity album. This read repeats all
 * visibility/block/deletion checks; callers still bind each result to its author.
 */
export async function loadActivityPhotoPool(database: D1Database, viewerID: string, visitIDs: readonly string[]) {
  const ids = [...new Set(visitIDs.filter(Boolean))]
  const records: RestaurantUGCPhotoRecord[] = []
  // Remain below D1's bind limit without introducing a query per card.
  for (let offset = 0; offset < ids.length; offset += 80) {
    const chunk = ids.slice(offset, offset + 80)
    const result = await database.prepare(`SELECT p.id, p.restaurant_id, p.visit_id, p.user_id, p.kind,
        p.storage_key, p.thumbnail_storage_key, p.sync_status,
        p.visibility, v.visibility AS visit_visibility, up.visibility AS profile_visibility,
        p.created_at, p.sort_order, r.marker_photo_id, p.deleted_at,
        CASE WHEN EXISTS (
          SELECT 1 FROM content_reports cr WHERE cr.status = 'actioned' AND (
            (cr.content_type = 'visit' AND cr.content_id = p.visit_id) OR
            (cr.content_type = 'user' AND cr.content_id = p.user_id)
          )
        ) THEN 0 ELSE 1 END AS moderation_eligible
      FROM photos p
      JOIN visits v ON v.id = p.visit_id AND v.user_id = p.user_id AND v.restaurant_id = p.restaurant_id
      JOIN restaurants r ON r.id = p.restaurant_id AND r.user_id = p.user_id
      JOIN user_profiles up ON up.user_id = p.user_id AND up.deleted_at IS NULL
      WHERE p.visit_id IN (${chunk.map(() => '?').join(',')})
        AND p.kind IN ('visit', 'dish')
        AND p.deleted_at IS NULL AND v.deleted_at IS NULL AND r.deleted_at IS NULL
        AND COALESCE(r.is_test_data, 0) = 0 AND COALESCE(v.is_test_data, 0) = 0 AND p.storage_provider = 'r2'
        AND p.sync_status = 'synced' AND LENGTH(TRIM(COALESCE(p.storage_key, ''))) > 0
        AND LENGTH(TRIM(COALESCE(p.thumbnail_storage_key, ''))) > 0
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b WHERE b.deleted_at IS NULL AND (
            (b.blocker_user_id = ? AND b.blocked_user_id = p.user_id) OR
            (b.blocker_user_id = p.user_id AND b.blocked_user_id = ?)
          )
        ) AND (
          p.user_id = ? OR
          (p.visibility = 'public' AND v.visibility = 'public' AND up.visibility = 'public') OR (
            p.visibility IN ('public', 'friends') AND v.visibility IN ('public', 'friends')
            AND up.visibility IN ('public', 'friends') AND EXISTS (
              SELECT 1 FROM friendships f WHERE f.status = 'accepted' AND f.deleted_at IS NULL AND (
                (f.requester_id = ? AND f.addressee_id = p.user_id) OR
                (f.requester_id = p.user_id AND f.addressee_id = ?)
              )
            )
          )
        )
      ORDER BY p.sort_order ASC, p.created_at DESC, p.id ASC`)
      .bind(...chunk, viewerID, viewerID, viewerID, viewerID, viewerID).all<RestaurantUGCPhotoRecord>()
    records.push(...result.results)
  }
  return new RestaurantUGCImagePool(records)
}

/**
 * One surface-aware product policy for choosing eligible UGC. A null result is
 * an intentional instruction to render the deterministic Food Category Visual.
 */
export function resolveRestaurantVisualSelection(
  pool: RestaurantUGCImagePool,
  context: RestaurantVisualSelectionContext,
): RestaurantUGCPhotoSelection | null {
  switch (context.surface) {
  case 'map':
    return pool.currentOwner(context.restaurantIDs, context.viewerID)
  case 'following':
  case 'similar_taste':
  case 'latest':
    return (context.activityVisitID
      ? pool.activity(context.activityVisitID, context.viewerID, context.canSeeFriendsActivity === true)
      : null) ?? pool.publicUGC(context.restaurantIDs)
  case 'search':
  case 'nearby':
  case 'detail':
  case 'for_you':
  case 'trending':
    return pool.currentOwner(context.restaurantIDs, context.viewerID)
      ?? pool.publicUGC(context.restaurantIDs)
  }
}

export function isActiveRestaurantUGCPhoto(photo: RestaurantUGCPhotoRecord) {
  const actualPhoto = photo.kind != null ? ['visit', 'dish'].includes(photo.kind) : Boolean(photo.visit_id)
  // Shipping SQL supplies binary metadata. Older in-memory callers without
  // these fields retain their established source-policy contract.
  const checksBinaryMetadata = photo.storage_key !== undefined || photo.thumbnail_storage_key !== undefined || photo.sync_status !== undefined
  const prefix = `users/${encodeURIComponent(photo.user_id)}/photos/${photo.id}/`
  const metadataReadable = !checksBinaryMetadata || (photo.sync_status === 'synced'
    && photo.storage_key?.startsWith(`${prefix}display.`) && photo.thumbnail_storage_key?.startsWith(`${prefix}thumbnail.`))
  return !!(actualPhoto && metadataReadable && !photo.deleted_at && !photo.binary_deleted_at && photo.moderation_eligible !== 0 && photo.moderation_eligible !== false)
}

const active = isActiveRestaurantUGCPhoto

function isPublic(photo: RestaurantUGCPhotoRecord) {
  return photo.visibility === 'public'
    && (photo.visit_visibility === null || photo.visit_visibility === 'public')
    && photo.profile_visibility === 'public'
}

function isFriendsVisible(photo: RestaurantUGCPhotoRecord) {
  return (photo.visibility === 'public' || photo.visibility === 'friends')
    && (photo.visit_visibility === 'public' || photo.visit_visibility === 'friends')
    && (photo.profile_visibility === 'public' || photo.profile_visibility === 'friends')
}
