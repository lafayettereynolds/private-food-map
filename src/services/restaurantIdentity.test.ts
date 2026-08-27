import { describe, expect, it } from 'vitest'
import type { PlaceResult, RestaurantIdentityCandidate } from './maps/types'
import { findMatchingRestaurant } from './restaurantIdentity'

const applePlace: PlaceResult = {
  provider: 'apple_maps', externalId: 'apple-123', name: '同一家店', address: '中山路 1 号',
  city: '杭州', district: '上城', longitude: 120.16, latitude: 30.25,
  merchantImageUrl: null, phone: null, openingHours: null,
}

describe('Global Restaurant Identity mapping', () => {
  it('matches a provider identity without treating it as Restaurant.id', () => {
    const restaurant = candidate('taste-map-owned-id')
    expect(restaurant.id).not.toBe(applePlace.externalId)
    expect(findMatchingRestaurant(applePlace, [restaurant])?.id).toBe('taste-map-owned-id')
  })

  it('does not silently choose when legacy data contains duplicate mappings', () => {
    expect(findMatchingRestaurant(applePlace, [candidate('one'), candidate('two')])).toBeNull()
  })

  it('keeps provider namespaces independent', () => {
    const amapOnly = candidate('amap-record', 'amap')
    expect(findMatchingRestaurant(applePlace, [amapOnly])).toBeNull()
  })
})

function candidate(id: string, provider: 'amap' | 'apple_maps' = 'apple_maps'): RestaurantIdentityCandidate {
  return {
    id,
    amapPoiId: provider === 'amap' ? applePlace.externalId : 'different-amap-id',
    name: provider === 'amap' ? '另一家店' : applePlace.name,
    address: provider === 'amap' ? '另一条路' : applePlace.address,
    latitude: provider === 'amap' ? 31 : applePlace.latitude,
    longitude: provider === 'amap' ? 121 : applePlace.longitude,
    placeIdentities: [{
      provider,
      externalId: applePlace.externalId,
      isPrimary: true,
      createdAt: '2026-08-27T05:00:00.000Z',
      updatedAt: '2026-08-27T05:00:00.000Z',
    }],
  }
}
