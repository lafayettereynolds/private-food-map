import type { Coordinates, PoiSearchResult } from '../types/domain'
import { loadAmap, type AMapNamespace } from './amap'
import { AmapProvider } from './maps/amapProvider'
import type { MapProvider, NavigationTarget, PlaceResult, PlaceSearchOptions } from './maps/types'
import { rankRestaurantSearchMatches } from './restaurantSearchRelevance'

export { rankRestaurantSearchMatches } from './restaurantSearchRelevance'

function toLegacyPoi(place: PlaceResult): PoiSearchResult {
  return {
    amapPoiId: place.externalId,
    name: place.name,
    address: place.address,
    city: place.city,
    district: place.district,
    longitude: place.longitude,
    latitude: place.latitude,
    categoryHints: place.categoryHints,
    merchantImageUrl: place.merchantImageUrl,
    phone: place.phone,
    openingHours: place.openingHours,
  }
}

export class MapService {
  constructor(private readonly provider: MapProvider) {}

  get providerId() {
    return this.provider.id
  }

  get isConfigured() {
    return this.provider.isConfigured
  }

  // The current Web renderer is intentionally provider-specific. Business
  // components use the generic methods below; only MapView consumes this SDK.
  loadWebMapSdk(): Promise<AMapNamespace> {
    return loadAmap()
  }

  detectCurrentCoordinates() {
    return this.provider.detectCurrentCoordinates()
  }

  detectCurrentLocation() {
    return this.provider.detectCurrentLocation()
  }

  detectCurrentCity() {
    return this.provider.detectCurrentCity()
  }

  resolveCoordinatesLocation(coordinates: Coordinates) {
    return this.provider.resolveCoordinatesLocation(coordinates)
  }

  resolveAddressLocation(address: string, city?: string) {
    return this.provider.resolveAddressLocation(address, city)
  }

  searchPlaces(keyword: string, city?: string, options: PlaceSearchOptions = {}) {
    return this.provider.searchPlaces(keyword, city, options)
  }

  searchNearbyRestaurants(
    center: Coordinates,
    city?: string,
    options: Pick<PlaceSearchOptions, 'timeoutMs' | 'radiusMeters'> = {},
  ) {
    return this.provider.searchNearbyRestaurants(center, city, options)
  }

  // Transitional adapter for the existing Web forms. The external provider ID
  // stays outside Taste Map's stable Restaurant.id.
  async searchRestaurantPois(keyword: string, city?: string, options: PlaceSearchOptions = {}) {
    const variants = keyword.trim() === '兰州拉面' ? [keyword, '兰州牛肉拉面'] : [keyword]
    const batches = await Promise.all(variants.map((variant, index) =>
      this.searchPlaces(variant, city, options).catch((error: unknown) => {
        if (index === 0) throw error
        return []
      })))
    const values = batches.flat().filter((item, index, all) => all.findIndex((other) => other.externalId === item.externalId) === index)
    return rankRestaurantSearchMatches(
      values.map(toLegacyPoi),
      keyword,
    )
  }

  async searchNearbyRestaurantPois(
    center: Coordinates,
    city?: string,
    options: Pick<PlaceSearchOptions, 'timeoutMs' | 'radiusMeters'> = {},
  ) {
    return (await this.searchNearbyRestaurants(center, city, options)).map(toLegacyPoi)
  }

  directionsUrl(target: NavigationTarget) {
    return this.provider.directionsUrl(target)
  }

  openDirections(target: NavigationTarget) {
    if (typeof window === 'undefined') return
    window.open(this.directionsUrl(target), '_blank', 'noopener,noreferrer')
  }
}

export const mapService = new MapService(new AmapProvider())

export type { MapProvider, NavigationTarget, PlaceResult, PlaceSearchOptions } from './maps/types'
