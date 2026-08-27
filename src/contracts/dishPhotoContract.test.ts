import { describe, expect, it } from 'vitest'
import { decodeDishJSONContract, decodePhotoJSONContract, decodeVisitDishJSONContract } from './dishPhotoContract'
import { decodeSyncPushRequest } from './syncV1'

const timestamp = '2026-08-27T08:00:00.000Z'
const dish = {
  schemaVersion: 1,
  id: 'dish-1',
  userId: 'client-claimed-owner',
  restaurantId: 'restaurant-1',
  visitId: 'visit-1',
  name: '寿喜烧',
  taste: '甜香',
  rating: 4.5,
  price: 88,
  photoId: 'photo-1',
  sortOrder: 0,
  createdAt: timestamp,
  updatedAt: timestamp,
  deletedAt: null,
}
const photo = {
  schemaVersion: 1,
  id: 'photo-1',
  userId: 'client-claimed-owner',
  restaurantId: 'restaurant-1',
  visitId: 'visit-1',
  dishId: 'dish-1',
  kind: 'dish',
  storageProvider: 'google-drive',
  storageKey: 'drive-file-stable-id',
  providerAccountId: 'drive-account',
  thumbnailStorageKey: null,
  fileName: 'dish.heic',
  mimeType: 'image/heic',
  byteSize: 1024,
  width: 1200,
  height: 900,
  sortOrder: 0,
  visibility: 'private',
  createdAt: timestamp,
  updatedAt: timestamp,
  deletedAt: null,
}
const visitDish = {
  schemaVersion: 1,
  id: 'visit-dish-1',
  userId: 'client-claimed-owner',
  restaurantId: 'restaurant-1',
  visitId: 'visit-1',
  dishId: 'dish-1',
  sortOrder: 0,
  createdAt: timestamp,
  updatedAt: timestamp,
  deletedAt: null,
}

describe('Dish and Photo JSON contracts', () => {
  it('round-trips the exact Web Dish fields plus stable relationships', () => {
    expect(decodeDishJSONContract(JSON.parse(JSON.stringify(dish)))).toEqual(dish)
    expect(decodeSyncPushRequest(push('dish', dish))).toMatchObject({
      mutations: [{ entityType: 'dish', payload: { visitId: 'visit-1', rating: 4.5 } }],
    })
  })

  it('keeps the Taste Map Photo ID separate from provider storage identity', () => {
    expect(decodePhotoJSONContract(JSON.parse(JSON.stringify(photo)))).toMatchObject({
      id: 'photo-1', storageProvider: 'google-drive', storageKey: 'drive-file-stable-id',
    })
    expect(decodeSyncPushRequest(push('photo', photo))).toMatchObject({
      mutations: [{ entityType: 'photo', payload: { id: 'photo-1', storageKey: 'drive-file-stable-id' } }],
    })
  })

  it('round-trips an explicit Visit-to-Restaurant-Dish association', () => {
    expect(decodeVisitDishJSONContract(JSON.parse(JSON.stringify(visitDish)))).toEqual(visitDish)
    expect(decodeSyncPushRequest(push('visitDish', visitDish))).toMatchObject({
      mutations: [{ entityType: 'visitDish', payload: { visitId: 'visit-1', dishId: 'dish-1' } }],
    })
    expect(() => decodeVisitDishJSONContract({ ...visitDish, dishId: '' })).toThrow(/dishId/)
  })

  it('supports provider-neutral metadata without treating a signed URL as identity', () => {
    expect(decodePhotoJSONContract({ ...photo, storageProvider: 'r2', storageKey: 'users/tm/photos/photo-1' }))
      .toMatchObject({ storageProvider: 'r2', storageKey: 'users/tm/photos/photo-1' })
    expect(() => decodePhotoJSONContract({ ...photo, temporarySignedURL: 'https://temporary.example/photo' }))
      .toThrow(/Unknown Photo field/)
  })

  it('rejects invalid relation, rating, price, and dimensions', () => {
    expect(() => decodeDishJSONContract({ ...dish, rating: 4.2 })).toThrow(/half-step/)
    expect(() => decodeDishJSONContract({ ...dish, price: -1 })).toThrow(/non-negative/)
    expect(() => decodePhotoJSONContract({ ...photo, dishId: null })).toThrow(/Dish photo/)
    expect(() => decodePhotoJSONContract({ ...photo, width: 0 })).toThrow(/positive integer/)
  })

  it('requires nullable fields to be present explicitly', () => {
    const { rating: _rating, ...dishWithoutRating } = dish
    const { providerAccountId: _account, ...photoWithoutAccount } = photo
    expect(() => decodeDishJSONContract(dishWithoutRating)).toThrow(/Dish.rating/)
    expect(() => decodePhotoJSONContract(photoWithoutAccount)).toThrow(/Photo.providerAccountId/)
  })
})

function push(
  entityType: 'dish' | 'visitDish' | 'photo',
  payload: typeof dish | typeof visitDish | typeof photo,
) {
  return {
    apiVersion: 1,
    schemaVersion: 1,
    mutations: [{
      mutationId: `mutation-${entityType}`,
      entityType,
      entityId: payload.id,
      operation: 'upsert',
      baseVersion: 0,
      clientTimestamp: payload.updatedAt,
      payload,
    }],
  }
}
