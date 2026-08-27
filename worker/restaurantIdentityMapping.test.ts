import { describe, expect, it } from 'vitest'
import { contractProviderForEvidence, groupRestaurantPlaceIdentities } from './restaurantIdentityMapping'

describe('Worker Restaurant identity mapping', () => {
  it('maps external resolver providers to contract namespaces', () => {
    expect(contractProviderForEvidence('apple')).toBe('apple_maps')
    expect(contractProviderForEvidence('amap')).toBe('amap')
    expect(contractProviderForEvidence('generic')).toBeNull()
  })

  it('groups provider identities by Taste Map Restaurant ID without merging records', () => {
    const rows = [row('restaurant-1'), row('restaurant-2')]
    const grouped = groupRestaurantPlaceIdentities(rows)

    expect(grouped.size).toBe(2)
    expect(grouped.get('restaurant-1')?.[0]).toMatchObject({ provider: 'amap', externalId: 'B0DUPLICATE' })
    expect(grouped.get('restaurant-2')?.[0]).toMatchObject({ provider: 'amap', externalId: 'B0DUPLICATE' })
  })
})

function row(restaurantID: string) {
  return {
    restaurant_id: restaurantID,
    user_id: 'owner',
    provider: 'amap' as const,
    external_id: 'B0DUPLICATE',
    is_primary: 1,
    created_at: '2026-08-27T05:00:00.000Z',
    updated_at: '2026-08-27T05:00:00.000Z',
  }
}
