import type { Coordinates, Restaurant } from '../../types/domain'
import type { RestaurantPlaceIdentity, RestaurantPlaceProvider } from '../../types/restaurantIdentity'

export type MapProviderId = Extract<RestaurantPlaceProvider, 'amap' | 'apple_maps'>

export interface PlaceResult {
  provider: MapProviderId
  externalId: string
  name: string
  address: string
  city: string
  district: string
  longitude: number
  latitude: number
  merchantImageUrl: string | null
  phone: string | null
  openingHours: string | null
}

export interface ResolvedPlaceLocation extends Coordinates {
  address: string
  city: string
  district: string
}

export interface PlaceSearchOptions {
  center?: Coordinates
  timeoutMs?: number
  radiusMeters?: number
  categoryOnly?: boolean
}

export interface NavigationTarget extends Coordinates {
  name: string
  address?: string
}

export interface MapProvider {
  readonly id: MapProviderId
  readonly isConfigured: boolean
  detectCurrentCoordinates(): Promise<Coordinates>
  detectCurrentLocation(): Promise<ResolvedPlaceLocation>
  detectCurrentCity(): Promise<string>
  resolveCoordinatesLocation(coordinates: Coordinates): Promise<ResolvedPlaceLocation>
  resolveAddressLocation(address: string, city?: string): Promise<ResolvedPlaceLocation>
  searchPlaces(keyword: string, city?: string, options?: PlaceSearchOptions): Promise<PlaceResult[]>
  searchNearbyRestaurants(center: Coordinates, city?: string, options?: Pick<PlaceSearchOptions, 'timeoutMs' | 'radiusMeters'>): Promise<PlaceResult[]>
  directionsUrl(target: NavigationTarget): string
}

export interface RestaurantIdentityCandidate extends Pick<Restaurant, 'id' | 'amapPoiId' | 'name' | 'address' | 'latitude' | 'longitude'> {
  externalPlaceIds?: Partial<Record<MapProviderId, string>>
  placeIdentities?: RestaurantPlaceIdentity[]
}
