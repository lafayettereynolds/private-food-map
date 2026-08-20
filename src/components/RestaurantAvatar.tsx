import { ImageIcon } from 'lucide-react'
import { PREFERENCE_META, type RestaurantSummary } from '../types/domain'

interface RestaurantAvatarProps {
  restaurant: RestaurantSummary
  size?: 'small' | 'large'
}

export function RestaurantAvatar({ restaurant, size = 'small' }: RestaurantAvatarProps) {
  const imageSource = restaurant.markerImageData || restaurant.merchantImageUrl
  const useImage = restaurant.markerType === 'image' && imageSource

  return (
    <span
      className={`restaurant-avatar restaurant-avatar--${size}`}
      style={{ borderColor: PREFERENCE_META[restaurant.preferenceLevel].color }}
    >
      {useImage ? (
        <img alt="" src={imageSource} />
      ) : restaurant.markerType === 'emoji' ? (
        <span>{restaurant.markerEmoji || '🍽️'}</span>
      ) : (
        <ImageIcon size={16} />
      )}
    </span>
  )
}
