import type { TasteMapImageDescriptor, TasteMapImageResolutionDTO, TasteMapRestaurantDTO } from '../platform/TasteMapPlatform'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import { FoodLibraryArtwork } from '../visuals/FoodLibraryArtwork'
import { HybridRestaurantImage } from './TasteMapHybridShared'
import { SyncedImage } from './SyncedImage'

/** Older DTOs may carry a custom avatar in `image`: it is never content evidence. */
export function restaurantContentResolution(restaurant: Pick<TasteMapRestaurantDTO, 'id' | 'name' | 'tags' | 'image' | 'contentImage' | 'contentImageResolution'>): TasteMapImageResolutionDTO {
  if (restaurant.contentImageResolution) return restaurant.contentImageResolution
  const fallback = {
    kind: 'foodCategoryVisual' as const, categoryVisualID: resolveFoodCategoryVisualID(restaurant),
    stableSeed: restaurant.id, accessibilityLabel: `${restaurant.name} 素材插画`, exportAllowed: false as const,
  }
  const candidate = restaurant.contentImage ?? restaurant.image
  const approvedContent = restaurant.contentImage !== undefined
    ? candidate.kind !== 'foodCategoryVisual' && candidate.kind !== 'foodDiningFallback' && candidate.kind !== 'providerMerchant'
    : (candidate.kind === 'activityPhoto' || candidate.kind === 'publicUGC' || candidate.kind === 'ownerPhoto') && Boolean(candidate.visitID)
  return { sources: approvedContent ? [candidate] : [], fallback }
}

export function HybridRestaurantContentImage({ restaurant, activityImage, className, onResolved }: {
  restaurant: Pick<TasteMapRestaurantDTO, 'id' | 'name' | 'tags' | 'image' | 'contentImage' | 'contentImageResolution'>
  /** The adapter has authorized this exact Activity's album, not the Restaurant avatar. */
  activityImage?: TasteMapImageDescriptor
  className?: string
  onResolved?: (image: TasteMapImageDescriptor) => void
}) {
  const resolution = restaurantContentResolution(restaurant)
  return <HybridRestaurantImage onResolved={onResolved} appearance="content" className={className} name={restaurant.name} tags={restaurant.tags}
    resolution={activityImage ? { sources: [activityImage], fallback: resolution.fallback } : resolution} />
}

/** Browser real Visit/dish refs and bridge-authorized descriptors share one content renderer. */
export function RestaurantContentImage({ name, tags, image, resolution, photos = [], onResolved }: {
  name: string; tags?: readonly string[]; image?: TasteMapImageDescriptor; resolution?: TasteMapImageResolutionDTO
  photos?: readonly { source: string; photoId?: string | null }[]
  onResolved?: (image: TasteMapImageDescriptor) => void
}) {
  if (image || resolution) return <HybridRestaurantImage onResolved={onResolved} appearance="content" image={image} resolution={resolution} name={name} tags={tags} />
  const artwork = <FoodLibraryArtwork name={name} tags={tags} />
  return photos.reduceRight((fallback, photo, index) => <SyncedImage alt={`${name} 用户实拍`} key={photo.photoId || `${photo.source}-${index}`}
    source={photo.source} photoId={photo.photoId} loading="lazy" fallback={fallback} failureFallback={fallback} />, artwork)
}
