import type { RestaurantPlaceIdentity, RestaurantPlaceProvider } from '../src/types/restaurantIdentity'

export interface RestaurantPlaceIdentityRow {
  restaurant_id: string
  user_id: string
  provider: RestaurantPlaceProvider
  external_id: string
  is_primary: number
  created_at: string
  updated_at: string
}

export function groupRestaurantPlaceIdentities(rows: RestaurantPlaceIdentityRow[]) {
  const grouped = new Map<string, RestaurantPlaceIdentity[]>()
  rows.forEach((row) => {
    const identities = grouped.get(row.restaurant_id) ?? []
    identities.push({
      provider: row.provider,
      externalId: row.external_id,
      isPrimary: Boolean(row.is_primary),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    })
    grouped.set(row.restaurant_id, identities)
  })
  return grouped
}

export function contractProviderForEvidence(provider: 'apple' | 'amap' | 'generic' | 'text') {
  if (provider === 'apple') return 'apple_maps' as const
  if (provider === 'amap') return 'amap' as const
  return null
}
