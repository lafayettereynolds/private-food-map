import type { RestaurantSummary } from '../types/domain'

/** Custom avatar choices are personal; automatic candidates are only actual Visit/dish photos. */
export function restaurantAvatarSelection(restaurant: RestaurantSummary) {
  if (restaurant.markerType === 'image' && (restaurant.markerImageData || restaurant.markerPhotoId)) {
    return { source: restaurant.markerImageData, photoId: restaurant.markerPhotoId, visit: null }
  }
  if (restaurant.markerType === 'emoji' && restaurant.markerEmoji.trim()) return null
  for (const visit of restaurant.visits.filter(visit => !visit.deletedAt).sort((a, b) => b.visitedAt.localeCompare(a.visitedAt))) {
    for (let index = 0; index < Math.max(visit.photos.length, visit.photoIds.length); index++) {
      const source = visit.photos[index] || null
      const photoId = visit.photoIds[index] || null
      if (source || photoId) return { source, photoId, visit }
    }
    const dish = visit.dishes.find(dish => dish.imageData || dish.photoId)
    if (dish) return { source: dish.imageData, photoId: dish.photoId, visit }
  }
  return null
}
