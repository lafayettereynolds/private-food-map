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
  return !photo.deleted_at && !photo.binary_deleted_at && photo.moderation_eligible !== 0 && photo.moderation_eligible !== false
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
