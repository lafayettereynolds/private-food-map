import { scoreColor, type RestaurantSummary } from '../types/domain'
import { resolveRestaurantFoodEmoji } from '../visuals/FoodCategoryVisualContract'
import { SyncedImage } from './SyncedImage'
import { restaurantAvatarSelection } from '../services/restaurantAvatarSelection'

interface RestaurantAvatarProps {
  restaurant: RestaurantSummary
  size?: 'small' | 'large'
}

export function RestaurantAvatar({ restaurant, size = 'small' }: RestaurantAvatarProps) {
  const selected = restaurantAvatarSelection(restaurant)
  const useImage = Boolean(selected)
  const fallback = <span>{resolveRestaurantFoodEmoji(restaurant, restaurant.markerEmoji)}</span>

  return (
    <span
      aria-label={`${restaurant.name} 餐厅头像${useImage ? '' : ` ${resolveRestaurantFoodEmoji(restaurant, restaurant.markerEmoji)}`}`}
      className={`restaurant-avatar restaurant-avatar--${size}`}
      role="img"
      style={{ borderColor: scoreColor(restaurant.scoreOutOfTen) }}
    >
      {useImage ? (
        <SyncedImage alt="" fallback={fallback} failureFallback={fallback} photoId={selected?.photoId} source={selected?.source} />
      ) : (
        <span aria-hidden="true">{fallback}</span>
      )}
    </span>
  )
}
