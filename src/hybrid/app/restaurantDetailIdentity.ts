import type { TasteMapRestaurantDetailViewModel } from '../../platform/TasteMapPlatform'

/** UUID/local/global aliases retain their existing case-insensitive contract.
 * Provider identities are different: their external ID is an opaque exact key,
 * even when two branches differ only by case. Do not normalize that suffix. */
export function restaurantDetailIdentityKey(id: string): string {
  const separator = id.indexOf(':')
  const provider = separator < 0 ? '' : id.slice(0, separator).toLowerCase()
  return ['amap', 'apple_maps', 'other', 'manual'].includes(provider)
    ? `${provider}:${id.slice(separator + 1)}`
    : id.toLowerCase()
}

/** A successful scoped read can resolve a provider/global key to an owned ID. */
export function detailMatchesRoute(detail: TasteMapRestaurantDetailViewModel | null, routeID: string, resolvedRequestID: string | null) {
  if (!detail) return false
  const key = restaurantDetailIdentityKey(routeID)
  return restaurantDetailIdentityKey(detail.restaurant.id) === key
    || (resolvedRequestID != null && restaurantDetailIdentityKey(resolvedRequestID) === key)
}
