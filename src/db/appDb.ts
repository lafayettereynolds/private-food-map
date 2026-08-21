import Dexie, { type EntityTable } from 'dexie'
import { DATABASE_NAME } from '../config/appEnvironment'
import { calculatePricePerPerson } from '../types/domain'
import type { Photo, PhotoCacheEntry, Restaurant, Visit } from '../types/domain'
import type { SyncMetadata, SyncQueueItem } from '../types/sync'

const legacyRestaurantSchema =
  'id, &amapPoiId, name, city, status, preferenceLevel, *tags, createdAt, updatedAt'
const legacyVisitSchema = 'id, restaurantId, visitedAt, createdAt, updatedAt'
const restaurantSchema =
  'id, &amapPoiId, name, city, status, preferenceLevel, *tags, createdAt, updatedAt, deletedAt'
const visitSchema = 'id, restaurantId, visitedAt, createdAt, updatedAt, deletedAt'

class FoodMapDatabase extends Dexie {
  restaurants!: EntityTable<Restaurant, 'id'>
  visits!: EntityTable<Visit, 'id'>
  syncQueue!: EntityTable<SyncQueueItem, 'id'>
  syncMetadata!: EntityTable<SyncMetadata, 'key'>
  photos!: EntityTable<Photo, 'id'>
  photoCache!: EntityTable<PhotoCacheEntry, 'photoId'>

  constructor() {
    super(DATABASE_NAME)

    this.version(1).stores({
      restaurants:
        'id, &amapPoiId, name, city, status, preferenceLevel, createdAt, updatedAt',
    })

    this.version(2)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.markerType ??= 'emoji'
          restaurant.markerImageData ??= null
          restaurant.merchantImageUrl ??= null
          restaurant.markerEmoji ??= '🍽️'
          restaurant.tags ??= []
          restaurant.pricePerPerson ??= null
        })
      })

    this.version(3)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.companions ??= []
          visit.partySize ??= Math.max(1, visit.companions.length + 1)
        })
      })

    this.version(4)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.queueDuration ??= null
        })
      })

    this.version(5)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.companions ??= []
          visit.partySize ??= Math.max(1, visit.companions.length + 1)
          visit.queueDuration ??= null
          const dishes = Array.isArray(visit.dishes) ? visit.dishes : []
          visit.dishes = dishes.map((dish: unknown, index: number) => {
            if (typeof dish === 'string') {
              return {
                id: `${visit.id}-dish-${index}`,
                name: dish,
                taste: '',
                rating: null,
                price: null,
                imageData: null,
                photoId: null,
              }
            }
            const storedDish = dish as Record<string, unknown>
            return {
              id: typeof storedDish.id === 'string' ? storedDish.id : `${visit.id}-dish-${index}`,
              name: typeof storedDish.name === 'string' ? storedDish.name : '',
              taste: typeof storedDish.taste === 'string' ? storedDish.taste : '',
              rating: null,
              price: typeof storedDish.price === 'number' ? storedDish.price : null,
              imageData: typeof storedDish.imageData === 'string' ? storedDish.imageData : null,
              photoId: typeof storedDish.photoId === 'string' ? storedDish.photoId : null,
            }
          })
        })

        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.markerType ??= 'emoji'
          restaurant.markerImageData ??= null
          restaurant.merchantImageUrl ??= null
          restaurant.markerEmoji ??= '🍽️'
          restaurant.tags ??= []
          restaurant.pricePerPerson ??= null
        })
      })

    this.version(6)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.companions ??= []
          visit.partySize ??= Math.max(1, visit.companions.length + 1)
          const legacyEnteredPrice =
            typeof visit.totalPrice === 'number'
              ? visit.totalPrice
              : typeof visit.pricePerPerson === 'number'
                ? visit.pricePerPerson
                : null
          visit.totalPrice = legacyEnteredPrice
          visit.pricePerPerson = calculatePricePerPerson(legacyEnteredPrice, visit.partySize)
          visit.photos = Array.isArray(visit.photos) ? visit.photos : []
        })

        const migratedVisits = await transaction.table('visits').toArray()
        const pricesByRestaurant = new Map<string, number[]>()
        migratedVisits.forEach((visit) => {
          if (typeof visit.pricePerPerson !== 'number') return
          const prices = pricesByRestaurant.get(visit.restaurantId) ?? []
          prices.push(visit.pricePerPerson)
          pricesByRestaurant.set(visit.restaurantId, prices)
        })

        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          const prices = pricesByRestaurant.get(restaurant.id)
          if (prices?.length) {
            restaurant.pricePerPerson = Math.round(
              prices.reduce((sum, price) => sum + price, 0) / prices.length,
            )
          }
        })
      })

    this.version(7)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.dishes = Array.isArray(visit.dishes)
            ? visit.dishes.map((dish: Record<string, unknown>) => ({
                ...dish,
                taste: typeof dish.taste === 'string' ? dish.taste : '',
              }))
            : []
        })
      })

    this.version(8)
      .stores({ restaurants: legacyRestaurantSchema, visits: legacyVisitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.dishes = Array.isArray(visit.dishes)
            ? visit.dishes.map((dish: Record<string, unknown>) => ({
                ...dish,
                rating:
                  Number.isInteger(dish.rating) && Number(dish.rating) >= 1 && Number(dish.rating) <= 5
                    ? dish.rating
                    : null,
              }))
            : []
        })
      })

    this.version(9)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.deletedAt ??= null
        })
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.deletedAt ??= null
        })
      })

    this.version(10)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        photos: 'id, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
        photoCache: 'photoId, cachedAt, lastAccessedAt',
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.markerPhotoId ??= null
        })
        await transaction.table('visits').toCollection().modify((visit) => {
          const photos = Array.isArray(visit.photos) ? visit.photos : []
          visit.photoIds = Array.isArray(visit.photoIds)
            ? photos.map((_: string, index: number) => visit.photoIds[index] ?? null)
            : photos.map(() => null)
          visit.dishes = Array.isArray(visit.dishes)
            ? visit.dishes.map((dish: Record<string, unknown>) => ({ ...dish, photoId: dish.photoId ?? null }))
            : []
        })
      })
  }
}

export const db = new FoodMapDatabase()
