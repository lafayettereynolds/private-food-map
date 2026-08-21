import type { Photo, Restaurant, Visit } from '../types/domain'
import type {
  CloudPhoto,
  CloudRestaurant,
  CloudSnapshot,
  CloudVisit,
  SyncCounts,
} from '../types/cloudSync'

export function toCloudRestaurant(restaurant: Restaurant): CloudRestaurant {
  const { markerImageData, ...cloudRestaurant } = restaurant
  void markerImageData
  return cloudRestaurant
}

export function toCloudVisit(visit: Visit): CloudVisit {
  const { photos, dishes, ...cloudVisit } = visit
  void photos
  return {
    ...cloudVisit,
    dishes: dishes.map(({ imageData, ...dish }) => {
      void imageData
      return dish
    }),
  }
}

export function toCloudPhoto(photo: Photo): CloudPhoto {
  const { localState, lastError, ...cloudPhoto } = photo
  void localState
  void lastError
  return cloudPhoto
}

export function mergeCloudData(
  localRestaurants: Restaurant[],
  localVisits: Visit[],
  localPhotos: Photo[],
  cloud: CloudSnapshot,
) {
  const restaurants = mergeById(
    localRestaurants,
    cloud.restaurants,
    mergeRestaurant,
  )
  const visits = mergeById(localVisits, cloud.visits, mergeVisit)
  const photos = mergeById(localPhotos, cloud.photos, mergePhoto)
  return { restaurants, visits, photos }
}

export function activeCounts(
  restaurants: Array<Pick<Restaurant | CloudRestaurant, 'deletedAt'>>,
  visits: Array<Pick<Visit | CloudVisit, 'deletedAt'>>,
  photos: Array<Pick<Photo | CloudPhoto, 'deletedAt'>> = [],
): SyncCounts {
  return {
    restaurants: restaurants.filter((restaurant) => !restaurant.deletedAt).length,
    visits: visits.filter((visit) => !visit.deletedAt).length,
    photos: photos.filter((photo) => !photo.deletedAt).length,
  }
}

function mergeById<Local extends { id: string }, Cloud extends { id: string }>(
  localItems: Local[],
  cloudItems: Cloud[],
  merge: (local: Local | undefined, cloud: Cloud) => Local,
) {
  const merged = new Map(localItems.map((item) => [item.id, item]))
  cloudItems.forEach((cloudItem) => {
    merged.set(cloudItem.id, merge(merged.get(cloudItem.id), cloudItem))
  })
  return [...merged.values()]
}

function mergeRestaurant(
  local: Restaurant | undefined,
  cloud: CloudRestaurant,
): Restaurant {
  if (local && local.updatedAt >= cloud.updatedAt) return local
  const localPendingImage = local?.markerPhotoId === null && local.markerImageData?.startsWith('data:image/')
  const matchingLocalImage = local?.markerPhotoId === cloud.markerPhotoId ? local.markerImageData : null
  return {
    ...cloud,
    markerImageData: localPendingImage
      ? local.markerImageData
      : matchingLocalImage ?? (cloud.markerPhotoId ? drivePhotoReference(cloud.markerPhotoId) : null),
  }
}

function mergeVisit(local: Visit | undefined, cloud: CloudVisit): Visit {
  if (local && local.updatedAt >= cloud.updatedAt) return local
  const localDishes = new Map(
    (local?.dishes ?? []).map((dish) => [dish.id, dish]),
  )
  const localPhotoSources = new Map(
    (local?.photoIds ?? []).map((photoId, index) => [photoId, local?.photos[index]]),
  )
  const pendingLocalPhotos = (local?.photos ?? [])
    .map((source, index) => ({ source, photoId: local?.photoIds[index] ?? null }))
    .filter((photo) => !photo.photoId && Boolean(photo.source))
  const cloudPhotos = cloud.photoIds.map((photoId) => (
    photoId ? localPhotoSources.get(photoId) ?? drivePhotoReference(photoId) : ''
  ))
  return {
    ...cloud,
    dishes: cloud.dishes.map((dish) => ({
      ...dish,
      imageData: localDishes.get(dish.id)?.imageData ?? (dish.photoId ? drivePhotoReference(dish.photoId) : null),
    })),
    photos: [...cloudPhotos, ...pendingLocalPhotos.map((photo) => photo.source)],
    photoIds: [...cloud.photoIds, ...pendingLocalPhotos.map(() => null)],
  }
}

function mergePhoto(local: Photo | undefined, cloud: CloudPhoto): Photo {
  if (local && local.updatedAt >= cloud.updatedAt) return local
  return { ...cloud, localState: 'synced', lastError: null }
}

export const DRIVE_PHOTO_REFERENCE_PREFIX = 'drive-photo:'

export function drivePhotoReference(photoId: string) {
  return `${DRIVE_PHOTO_REFERENCE_PREFIX}${photoId}`
}

export function photoIdFromReference(value: string | null | undefined) {
  return value?.startsWith(DRIVE_PHOTO_REFERENCE_PREFIX)
    ? value.slice(DRIVE_PHOTO_REFERENCE_PREFIX.length)
    : null
}
