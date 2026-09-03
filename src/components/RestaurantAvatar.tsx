import { scoreColor, type RestaurantSummary } from '../types/domain'
import { resolveRestaurantFoodEmoji } from '../visuals/FoodCategoryVisualContract'
import { SyncedImage } from './SyncedImage'

interface RestaurantAvatarProps {
  restaurant: RestaurantSummary
  size?: 'small' | 'large'
}

export function RestaurantAvatar({ restaurant, size = 'small' }: RestaurantAvatarProps) {
  // Merchant/provider artwork is not a user's Restaurant avatar. When the
  // owner has not supplied a marker photo, use the themed food emoji instead.
  const imageSource = restaurant.markerImageData
  const useImage = restaurant.markerType === 'image' && (imageSource || restaurant.markerPhotoId)
  const fallback = <span>{resolveRestaurantFoodEmoji(restaurant, restaurant.markerEmoji)}</span>

  return (
    <span
      className={`restaurant-avatar restaurant-avatar--${size}`}
      style={{ borderColor: scoreColor(restaurant.scoreOutOfTen) }}
    >
      {useImage ? (
        <SyncedImage alt="" fallback={fallback} photoId={restaurant.markerPhotoId} source={imageSource} />
      ) : (
        fallback
      )}
    </span>
  )
}
