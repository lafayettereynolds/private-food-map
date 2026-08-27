export type RestaurantPlaceProvider = 'amap' | 'apple_maps' | 'manual' | 'other'

export interface RestaurantPlaceIdentity {
  provider: RestaurantPlaceProvider
  externalId: string
  isPrimary: boolean
  createdAt: string
  updatedAt: string
}
