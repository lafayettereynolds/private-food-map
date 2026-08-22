import { describe, expect, it } from 'vitest'
import type { Photo, Restaurant, Visit } from '../types/domain'
import type { CloudSnapshot } from '../types/cloudSync'
import { activeCounts, mergeCloudData, toCloudPhoto, toCloudRestaurant, toCloudVisit } from './cloudSyncData'

describe('cloud sync data', () => {
  it('never sends local photos or image data to D1', () => {
    const restaurant = makeRestaurant({ markerImageData: 'data:image/png;base64,secret' })
    const visit = makeVisit({ photos: ['data:image/jpeg;base64,secret'] })

    expect(toCloudRestaurant(restaurant)).not.toHaveProperty('markerImageData')
    expect(toCloudVisit(visit)).not.toHaveProperty('photos')
    expect(toCloudVisit(visit).dishes[0]).not.toHaveProperty('imageData')
    expect(toCloudPhoto(makePhoto())).not.toHaveProperty('localState')
    expect(toCloudPhoto(makePhoto())).not.toHaveProperty('lastError')
  })

  it('uses a newer cloud record while preserving device-local images', () => {
    const localRestaurant = makeRestaurant({ markerImageData: 'local-cover' })
    const localVisit = makeVisit({ photos: ['local-photo'] })
    const cloud = snapshot({
      restaurants: [{ ...toCloudRestaurant(localRestaurant), name: '云端新名字', updatedAt: '2026-08-20T12:00:00.000Z' }],
      visits: [{
        ...toCloudVisit(localVisit),
        note: '手机新感受',
        updatedAt: '2026-08-20T12:00:00.000Z',
      }],
    })

    const merged = mergeCloudData([localRestaurant], [localVisit], [], cloud)
    expect(merged.restaurants[0]).toMatchObject({ name: '云端新名字', markerImageData: 'local-cover' })
    expect(merged.visits[0]).toMatchObject({ note: '手机新感受', photos: ['local-photo'] })
    expect(merged.visits[0].dishes[0].imageData).toBe('local-dish-photo')
  })

  it('keeps a newer local record and applies a newer cloud tombstone', () => {
    const local = makeRestaurant({ name: '电脑较新', updatedAt: '2026-08-20T13:00:00.000Z' })
    const olderCloud = snapshot({
      restaurants: [{ ...toCloudRestaurant(local), name: '云端较旧', updatedAt: '2026-08-20T12:00:00.000Z' }],
      visits: [],
    })
    expect(mergeCloudData([local], [], [], olderCloud).restaurants[0].name).toBe('电脑较新')

    const deletedCloud = snapshot({
      restaurants: [{
        ...toCloudRestaurant(local),
        updatedAt: '2026-08-20T14:00:00.000Z',
        deletedAt: '2026-08-20T14:00:00.000Z',
      }],
      visits: [],
    })
    expect(mergeCloudData([local], [], [], deletedCloud).restaurants[0].deletedAt).toBe('2026-08-20T14:00:00.000Z')
  })

  it('does not count soft-deleted records', () => {
    expect(activeCounts(
      [makeRestaurant(), makeRestaurant({ id: 'deleted', deletedAt: '2026-08-20T14:00:00.000Z' })],
      [makeVisit(), makeVisit({ id: 'deleted-visit', deletedAt: '2026-08-20T14:00:00.000Z' })],
    )).toEqual({ restaurants: 1, visits: 1, photos: 0 })
  })

  it('restores Drive references on a new device without putting binary data in D1', () => {
    const restaurant = makeRestaurant({ markerPhotoId: 'photo-marker' })
    const visit = makeVisit({ photoIds: ['photo-visit'], photos: [] })
    const cloud = snapshot({
      restaurants: [toCloudRestaurant(restaurant)],
      visits: [toCloudVisit(visit)],
      photos: [toCloudPhoto(makePhoto({ id: 'photo-marker' })), toCloudPhoto(makePhoto({ id: 'photo-visit', kind: 'visit', visitId: visit.id }))],
    })

    const merged = mergeCloudData([], [], [], cloud)
    expect(merged.restaurants[0].markerImageData).toBe('drive-photo:photo-marker')
    expect(merged.visits[0].photos).toEqual(['drive-photo:photo-visit'])
    expect(merged.photos).toHaveLength(2)
  })
})

function makeRestaurant(changes: Partial<Restaurant> = {}): Restaurant {
  return {
    id: 'restaurant-1',
    userId: 'owner',
    amapPoiId: 'poi-1',
    name: '测试餐厅',
    address: '测试路 1 号',
    city: '杭州',
    latitude: 30.25,
    longitude: 120.16,
    status: 'visited',
    preferenceLevel: 'favorite',
    overallRating: 9.2,
    foodRating: null,
    environmentRating: null,
    serviceRating: null,
    valueRating: null,
    tags: ['杭帮菜'],
    longTermNote: '本地笔记',
    pricePerPerson: 128,
    markerType: 'image',
    markerImageData: null,
    markerPhotoId: null,
    merchantImageUrl: null,
    markerEmoji: '🍽️',
    createdAt: '2026-08-20T10:00:00.000Z',
    updatedAt: '2026-08-20T11:00:00.000Z',
    deletedAt: null,
    ...changes,
  }
}

function makePhoto(changes: Partial<Photo> = {}): Photo {
  return {
    id: 'photo-1',
    userId: 'owner',
    restaurantId: 'restaurant-1',
    visitId: null,
    kind: 'restaurant-marker',
    storageProvider: 'google-drive',
    driveAccountId: 'google-account-1',
    driveFileId: 'drive-file-1',
    fileName: 'photo-1.webp',
    mimeType: 'image/webp',
    fileSize: 1234,
    width: 800,
    height: 600,
    createdAt: '2026-08-20T10:00:00.000Z',
    updatedAt: '2026-08-20T11:00:00.000Z',
    deletedAt: null,
    localState: 'synced',
    lastError: null,
    ...changes,
  }
}

function makeVisit(changes: Partial<Visit> = {}): Visit {
  return {
    id: 'visit-1',
    userId: 'owner',
    restaurantId: 'restaurant-1',
    visitedAt: '2026-08-20T10:30:00.000Z',
    rating: 5,
    visibility: 'private',
    diningMode: 'dine_in',
    totalPrice: 256,
    myActualSpend: null,
    paymentMode: null,
    pricePerPerson: 128,
    partySize: 2,
    queueDuration: 'under15',
    diningOccasion: null,
    valueRating: null,
    environmentRating: null,
    serviceRating: null,
    noiseLevel: null,
    diningDuration: null,
    portionLevel: null,
    transportConvenience: null,
    specialNotes: '',
    recommendationSourceType: null,
    recommendationSourceUserId: null,
    recommendationSourceText: '',
    sharedMealId: null,
    companions: ['朋友'],
    dishes: [{ id: 'dish-1', name: '东坡肉', taste: '偏甜', rating: 5, price: 88, imageData: 'local-dish-photo', photoId: null }],
    note: '本地感受',
    photos: [],
    photoIds: [],
    createdAt: '2026-08-20T10:00:00.000Z',
    updatedAt: '2026-08-20T11:00:00.000Z',
    deletedAt: null,
    ...changes,
  }
}

function snapshot(changes: Partial<CloudSnapshot>): CloudSnapshot {
  return {
    restaurants: [],
    visits: [],
    photos: [],
    users: [],
    friendships: [],
    sharedMeals: [],
    sharedMealParticipants: [],
    serverTime: '2026-08-20T15:00:00.000Z',
    ...changes,
  }
}
