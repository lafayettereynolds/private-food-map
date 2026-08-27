import type { RestaurantSummary, RestaurantStatus } from '../types/domain'

export type ProfileRestaurantStatus = Extract<RestaurantStatus, 'visited' | 'wantToGo'>

export const OWNER_PROFILE_STAT_LABELS = ['我关注的', '关注我的', '去过', '想吃'] as const
export const PUBLIC_PROFILE_STAT_LABELS = ['关注', '粉丝', '去过餐厅', '想去餐厅'] as const

export function visibleProfileBio(bio: string | null | undefined) {
  const value = bio?.trim()
  return value || null
}

export function publicProfileTabLabels(hasTasteSummary: boolean) {
  return hasTasteSummary ? ['动态', '口味', '食单'] as const : ['动态', '食单'] as const
}

export function shouldShowMutualWant(count: number) { return count > 0 }
export function shouldShowPremiumBurger(membershipTier: string | null | undefined) { return membershipTier === 'member' }

export function profileRestaurantIdentity(restaurant: RestaurantSummary) {
  const poiId = restaurant.amapPoiId?.trim().toLocaleLowerCase()
  if (poiId) return `poi:${poiId}`

  const city = restaurant.city.trim().toLocaleLowerCase()
  const name = restaurant.name.trim().toLocaleLowerCase()
  const address = restaurant.address.trim().toLocaleLowerCase()
  const coordinates = `${restaurant.latitude.toFixed(5)}:${restaurant.longitude.toFixed(5)}`
  return `restaurant:${city}:${name}:${address || coordinates}`
}

export function selectUniqueProfileRestaurants(restaurants: RestaurantSummary[], status: ProfileRestaurantStatus) {
  const identities = new Set<string>()
  return restaurants.filter((restaurant) => {
    if (restaurant.status !== status) return false
    const identity = profileRestaurantIdentity(restaurant)
    if (identities.has(identity)) return false
    identities.add(identity)
    return true
  })
}
