import { describe, expect, it } from 'vitest'
import {
  decodeRestaurantListItemSyncContract,
  decodeRestaurantListPlace,
  decodeRestaurantListSyncContract,
} from './restaurantListContract'
import { decodeSyncPushRequest } from './syncV1'

const timestamp = '2026-08-28T12:00:00.000Z'
const place = {
  globalKey: 'apple_maps:apple-place-1',
  restaurantId: 'restaurant-1',
  placeIdentities: [{ provider: 'apple_maps' as const, externalId: 'apple-place-1', isPrimary: true }],
  name: '寿司店', address: '西湖边', city: '杭州', latitude: 30.25, longitude: 120.16,
  markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍣',
}
const list = {
  schemaVersion: 1 as const, id: 'list-1', userId: 'forged-user', title: ' 杭州日料 Top 10 ',
  description: ' 自己会反复去的店 ', visibility: 'friends' as const, isRanked: true,
  coverMode: 'automatic' as const, customCoverPhotoId: null,
  createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
}
const item = {
  schemaVersion: 1 as const, id: 'item-1', userId: 'forged-user', listId: list.id,
  restaurantId: place.restaurantId, restaurantGlobalKey: place.globalKey,
  position: 0, note: ' 一定要点海胆 ', restaurant: place,
  createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
}

describe('Restaurant List JSON contract', () => {
  it('normalizes Unicode title, description and item note without changing identity', () => {
    expect(decodeRestaurantListSyncContract(list)).toMatchObject({
      title: '杭州日料 Top 10', description: '自己会反复去的店', visibility: 'friends',
    })
    expect(decodeRestaurantListItemSyncContract(item)).toMatchObject({
      note: '一定要点海胆', restaurantGlobalKey: place.globalKey,
    })
  })

  it('allows duplicate titles because list identity is the stable ID', () => {
    const first = decodeRestaurantListSyncContract(list)
    const second = decodeRestaurantListSyncContract({ ...list, id: 'list-2' })
    expect(first.title).toBe(second.title)
    expect(first.id).not.toBe(second.id)
  })

  it('keeps optional photos nullable and supports Apple Maps-only identity', () => {
    expect(decodeRestaurantListPlace(place)).toMatchObject({
      globalKey: 'apple_maps:apple-place-1', markerPhotoId: null, merchantImageUrl: null,
    })
  })

  it('rejects missing primary identity and mismatched global identity', () => {
    expect(() => decodeRestaurantListPlace({
      ...place, placeIdentities: [{ ...place.placeIdentities[0], isPrimary: false }],
    })).toThrow(/primary/)
    expect(() => decodeRestaurantListItemSyncContract({
      ...item, restaurantGlobalKey: 'amap:wrong',
    })).toThrow(/does not match/)
  })

  it('enforces title, description and note limits by Unicode code points', () => {
    expect(() => decodeRestaurantListSyncContract({ ...list, title: '🍣'.repeat(61) })).toThrow(/1-60/)
    expect(() => decodeRestaurantListSyncContract({ ...list, description: '味'.repeat(241) })).toThrow(/too long/)
    expect(() => decodeRestaurantListItemSyncContract({ ...item, note: '好'.repeat(161) })).toThrow(/too long/)
  })

  it('requires a non-negative deterministic position', () => {
    expect(() => decodeRestaurantListItemSyncContract({ ...item, position: -1 })).toThrow(/invalid/)
    expect(() => decodeRestaurantListItemSyncContract({ ...item, position: 1.5 })).toThrow(/invalid/)
  })

  it('accepts soft-delete timestamps while keeping required payload fields', () => {
    expect(decodeRestaurantListSyncContract({ ...list, deletedAt: timestamp }).deletedAt).toBe(timestamp)
    expect(decodeRestaurantListItemSyncContract({ ...item, deletedAt: timestamp }).deletedAt).toBe(timestamp)
  })

  it('decodes list entities through the versioned Sync V1 envelope', () => {
    const request = decodeSyncPushRequest({
      apiVersion: 1, schemaVersion: 1,
      mutations: [
        { mutationId: 'm-list', entityType: 'restaurantList', entityId: list.id,
          operation: 'upsert', baseVersion: 0, clientTimestamp: timestamp, payload: list },
        { mutationId: 'm-item', entityType: 'restaurantListItem', entityId: item.id,
          operation: 'upsert', baseVersion: 0, clientTimestamp: timestamp, payload: item },
      ],
    })
    expect(request.mutations.map((mutation) => mutation.entityType))
      .toEqual(['restaurantList', 'restaurantListItem'])
  })

  it('does not infer WantToGo or private Visit fields into a list place', () => {
    const decoded = decodeRestaurantListPlace(place)
    expect(decoded).not.toHaveProperty('status')
    expect(decoded).not.toHaveProperty('visits')
    expect(decoded).not.toHaveProperty('longTermNote')
    expect(decoded).not.toHaveProperty('myActualSpend')
  })
})
