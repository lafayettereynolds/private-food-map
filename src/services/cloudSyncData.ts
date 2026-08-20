import type { Restaurant, Visit } from '../types/domain'
import type {
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

export function mergeCloudData(
  localRestaurants: Restaurant[],
  localVisits: Visit[],
  cloud: CloudSnapshot,
) {
  const restaurants = mergeById(
    localRestaurants,
    cloud.restaurants,
    mergeRestaurant,
  )
  const visits = mergeById(localVisits, cloud.visits, mergeVisit)
  return { restaurants, visits }
}

export function activeCounts(
  restaurants: Array<Pick<Restaurant | CloudRestaurant, 'deletedAt'>>,
  visits: Array<Pick<Visit | CloudVisit, 'deletedAt'>>,
): SyncCounts {
  return {
    restaurants: restaurants.filter((restaurant) => !restaurant.deletedAt).length,
    visits: visits.filter((visit) => !visit.deletedAt).length,
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
  return {
    ...cloud,
    markerImageData: local?.markerImageData ?? null,
  }
}

function mergeVisit(local: Visit | undefined, cloud: CloudVisit): Visit {
  if (local && local.updatedAt >= cloud.updatedAt) return local
  const localDishImages = new Map(
    (local?.dishes ?? []).map((dish) => [dish.id, dish.imageData]),
  )
  return {
    ...cloud,
    dishes: cloud.dishes.map((dish) => ({
      ...dish,
      imageData: localDishImages.get(dish.id) ?? null,
    })),
    photos: local?.photos ?? [],
  }
}
