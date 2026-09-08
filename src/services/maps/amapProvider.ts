import type { Coordinates } from '../../types/domain'
import {
  detectCurrentCity,
  detectCurrentCoordinates,
  detectCurrentLocation,
  isAmapConfigured,
  resolveAddressLocation,
  resolveCoordinatesLocation,
  searchNearbyRestaurantPois,
  searchRestaurantPois,
} from '../amap'
import type { MapProvider, NavigationTarget, PlaceResult, PlaceSearchOptions } from './types'

function toPlaceResult(poi: Awaited<ReturnType<typeof searchRestaurantPois>>[number]): PlaceResult {
  return {
    provider: 'amap',
    externalId: poi.amapPoiId,
    name: poi.name,
    address: poi.address,
    city: poi.city,
    district: poi.district,
    longitude: poi.longitude,
    latitude: poi.latitude,
    categoryHints: poi.categoryHints,
    merchantImageUrl: poi.merchantImageUrl,
    phone: poi.phone ?? null,
    openingHours: poi.openingHours ?? null,
  }
}

export class AmapProvider implements MapProvider {
  readonly id = 'amap' as const
  readonly isConfigured = isAmapConfigured

  detectCurrentCoordinates() {
    return detectCurrentCoordinates()
  }

  detectCurrentLocation() {
    return detectCurrentLocation()
  }

  detectCurrentCity() {
    return detectCurrentCity()
  }

  resolveCoordinatesLocation(coordinates: Coordinates) {
    return resolveCoordinatesLocation(coordinates)
  }

  resolveAddressLocation(address: string, city?: string) {
    return resolveAddressLocation(address, city)
  }

  async searchPlaces(keyword: string, city?: string, options: PlaceSearchOptions = {}) {
    return (await searchRestaurantPois(keyword, city, options)).map(toPlaceResult)
  }

  async searchNearbyRestaurants(
    center: Coordinates,
    city?: string,
    options: Pick<PlaceSearchOptions, 'timeoutMs' | 'radiusMeters'> = {},
  ) {
    return (await searchNearbyRestaurantPois(center, city, options)).map(toPlaceResult)
  }

  directionsUrl(target: NavigationTarget) {
    const parameters = new URLSearchParams({
      from: '',
      to: `${target.longitude},${target.latitude},${target.name}`,
      mode: 'car',
      policy: '0',
      src: 'taste-map',
      callnative: '1',
    })
    return `https://uri.amap.com/navigation?${parameters.toString()}`
  }
}
