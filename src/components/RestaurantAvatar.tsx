import { ImageIcon } from 'lucide-react'
import { scoreColor, type RestaurantSummary } from '../types/domain'
import { SyncedImage } from './SyncedImage'

interface RestaurantAvatarProps {
  restaurant: RestaurantSummary
  size?: 'small' | 'large'
}

export function RestaurantAvatar({ restaurant, size = 'small' }: RestaurantAvatarProps) {
  const imageSource = restaurant.markerImageData || restaurant.merchantImageUrl
  const useImage = restaurant.markerType === 'image' && (imageSource || restaurant.markerPhotoId)

  return (
    <span
      className={`restaurant-avatar restaurant-avatar--${size}`}
      style={{ borderColor: scoreColor(restaurant.scoreOutOfTen) }}
    >
      {useImage ? (
        <SyncedImage alt="" photoId={restaurant.markerPhotoId} source={imageSource} />
      ) : restaurant.markerType === 'emoji' ? (
        <span>{restaurant.markerEmoji || '🍽️'}</span>
      ) : (
        <ImageIcon size={16} />
      )}
    </span>
  )
}
