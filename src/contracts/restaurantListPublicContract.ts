import type {
  RestaurantListPlaceContractV1,
  RestaurantListVisibilityContract,
} from './restaurantListContract'
import type { ProfileAvatarPresetContract } from './profileContract'

export const RESTAURANT_LIST_PUBLIC_API_VERSION = 1 as const

export interface PublicListOwnerDTO {
  userId: string
  displayName: string
  avatarPhotoId: string | null
  avatarPresetId: ProfileAvatarPresetContract
}

export interface PublicListPreviewRestaurantDTO {
  globalKey: string
  name: string
  photoId: string | null
  merchantImageUrl: string | null
  markerEmoji: string
}

export interface PublicListSummaryDTO {
  id: string
  title: string
  description: string
  visibility: RestaurantListVisibilityContract
  isRanked: boolean
  coverMode: 'automatic' | 'custom'
  customCoverPhotoId: string | null
  restaurantCount: number
  previewRestaurants: PublicListPreviewRestaurantDTO[]
  owner: PublicListOwnerDTO
  updatedAt: string
}

export interface PublicListItemDTO {
  id: string
  position: number
  note: string
  restaurant: RestaurantListPlaceContractV1
}

export interface PublicListSummaryPageDTO {
  apiVersion: typeof RESTAURANT_LIST_PUBLIC_API_VERSION
  items: PublicListSummaryDTO[]
  nextCursor: string | null
  generatedAt: string
}

export interface PublicListDetailDTO {
  apiVersion: typeof RESTAURANT_LIST_PUBLIC_API_VERSION
  list: PublicListSummaryDTO
  items: PublicListItemDTO[]
  nextCursor: string | null
  generatedAt: string
}
