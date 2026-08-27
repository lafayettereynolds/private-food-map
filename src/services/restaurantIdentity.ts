import type { PlaceResult, RestaurantIdentityCandidate } from './maps/types'

const MAX_LOCATION_MATCH_METERS = 120

export function findMatchingRestaurant(
  place: PlaceResult,
  restaurants: RestaurantIdentityCandidate[],
): RestaurantIdentityCandidate | null {
  const externalIdMatches = restaurants.filter((restaurant) => (
    restaurant.placeIdentities?.some((identity) => (
      identity.provider === place.provider && identity.externalId === place.externalId
    ))
    ||
    restaurant.externalPlaceIds?.[place.provider] === place.externalId
    || (place.provider === 'amap' && restaurant.amapPoiId === place.externalId)
  ))
  if (externalIdMatches.length === 1) return externalIdMatches[0]
  // Existing duplicates must be surfaced for cleanup; never silently pick one.
  if (externalIdMatches.length > 1) return null

  const normalizedName = normalizeIdentityText(place.name)
  const normalizedAddress = normalizeIdentityText(place.address)
  const candidates = restaurants.filter((restaurant) => normalizeIdentityText(restaurant.name) === normalizedName)
  const byAddress = candidates.find((restaurant) => {
    const candidateAddress = normalizeIdentityText(restaurant.address)
    return candidateAddress === normalizedAddress
      || (candidateAddress.length >= 6 && normalizedAddress.includes(candidateAddress))
      || (normalizedAddress.length >= 6 && candidateAddress.includes(normalizedAddress))
  })
  if (byAddress) return byAddress

  return candidates.find((restaurant) => distanceMeters(place, restaurant) <= MAX_LOCATION_MATCH_METERS) ?? null
}

export function normalizeIdentityText(value: string) {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase('zh-CN')
    .replace(/[\s—_·•（）()【】[\]，,。.-]/g, '')
    .replace(/(餐厅|饭店|店)$/g, '')
}

function distanceMeters(
  left: Pick<PlaceResult, 'latitude' | 'longitude'>,
  right: Pick<RestaurantIdentityCandidate, 'latitude' | 'longitude'>,
) {
  const radians = (degrees: number) => degrees * Math.PI / 180
  const latitudeDelta = radians(right.latitude - left.latitude)
  const longitudeDelta = radians(right.longitude - left.longitude)
  const leftLatitude = radians(left.latitude)
  const rightLatitude = radians(right.latitude)
  const value = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(leftLatitude) * Math.cos(rightLatitude) * Math.sin(longitudeDelta / 2) ** 2
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value))
}
