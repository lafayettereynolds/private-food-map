import Dexie, { type EntityTable } from 'dexie'
import { DATABASE_NAME } from '../config/appEnvironment'
import { calculatePricePerPerson } from '../types/domain'
import type {
  Friendship,
  Follow,
  DiningCompanion,
  Photo,
  PhotoCacheEntry,
  Restaurant,
  SharedMeal,
  SharedMealParticipant,
  UserProfile,
  Visit,
} from '../types/domain'
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
  users!: EntityTable<UserProfile, 'id'>
  friendships!: EntityTable<Friendship, 'id'>
  follows!: EntityTable<Follow, 'id'>
  sharedMeals!: EntityTable<SharedMeal, 'id'>
  sharedMealParticipants!: EntityTable<SharedMealParticipant, 'id'>
  diningCompanions!: EntityTable<DiningCompanion, 'id'>

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

    this.version(11)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        photos: 'id, userId, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
        photoCache: 'photoId, cachedAt, lastAccessedAt',
        users: 'id, nickname, email, updatedAt, deletedAt',
        friendships: 'id, requesterId, addresseeId, status, updatedAt',
        sharedMeals: 'id, restaurantId, createdByUserId, occurredAt, updatedAt, deletedAt',
        sharedMealParticipants: 'id, sharedMealId, userId, visitId, status, updatedAt',
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        const now = new Date().toISOString()
        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.userId ??= 'owner'
        })
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.userId ??= 'owner'
          visit.visibility ??= 'private'
          visit.diningMode ??= 'dine_in'
          visit.myActualSpend ??= null
          visit.paymentMode ??= null
          visit.diningOccasion ??= null
          visit.diningOccasionText ??= ''
          visit.valueRating ??= null
          visit.environmentRating ??= null
          visit.serviceRating ??= null
          visit.noiseLevel ??= null
          visit.diningDuration ??= null
          visit.portionLevel ??= null
          visit.transportConvenience ??= null
          visit.specialNotes ??= ''
          visit.recommendationSourceType ??= null
          visit.recommendationSourceUserId ??= null
          visit.recommendationSourceText ??= ''
          visit.sharedMealId ??= null
        })
        await transaction.table('photos').toCollection().modify((photo) => {
          photo.userId ??= 'owner'
        })
        const users = transaction.table('users')
        if (!(await users.get('owner'))) {
          await users.put({
            id: 'owner',
            nickname: 'Taste Map 用户',
            email: null,
            bio: '',
            city: '',
            avatarImageData: null,
            avatarPhotoId: null,
            mapSharingEnabled: false,
            mapVisibility: 'private',
            authProvider: 'local',
            authSubject: null,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
          })
        }
      })

    this.version(12)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        photos: 'id, userId, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
        photoCache: 'photoId, cachedAt, lastAccessedAt',
        users: 'id, nickname, email, updatedAt, deletedAt',
        friendships: 'id, requesterId, addresseeId, status, updatedAt',
        sharedMeals: 'id, restaurantId, createdByUserId, occurredAt, updatedAt, deletedAt',
        sharedMealParticipants: 'id, sharedMealId, userId, visitId, status, updatedAt',
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.valueTags = Array.isArray(visit.valueTags) ? visit.valueTags : []
          visit.environmentTags = Array.isArray(visit.environmentTags) ? visit.environmentTags : []
          visit.serviceTags = Array.isArray(visit.serviceTags) ? visit.serviceTags : []
        })
        await transaction.table('users').toCollection().modify((user) => {
          user.mapSharingEnabled ??= false
          user.mapVisibility ??= 'private'
        })
      })

    this.version(13)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        photos: 'id, userId, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
        photoCache: 'photoId, cachedAt, lastAccessedAt',
        users: 'id, nickname, email, updatedAt, deletedAt',
        friendships: 'id, requesterId, addresseeId, status, updatedAt',
        sharedMeals: 'id, restaurantId, createdByUserId, occurredAt, updatedAt, deletedAt',
        sharedMealParticipants: 'id, sharedMealId, userId, visitId, status, updatedAt',
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.diningOccasionText ??= ''
        })
        await transaction.table('users').toCollection().modify((user) => {
          user.avatarPresetId ??= 'polar-bear'
          user.membershipTier ??= 'free'
        })
      })

    this.version(14)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        photos: 'id, userId, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
        photoCache: 'photoId, cachedAt, lastAccessedAt',
        users: 'id, nickname, email, updatedAt, deletedAt',
        friendships: 'id, requesterId, addresseeId, status, updatedAt',
        sharedMeals: 'id, restaurantId, createdByUserId, occurredAt, updatedAt, deletedAt',
        sharedMealParticipants: 'id, sharedMealId, userId, visitId, status, updatedAt',
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.diningOccasions = Array.isArray(visit.diningOccasions)
            ? visit.diningOccasions
            : visit.diningOccasion ? [visit.diningOccasion] : []
          visit.diningOccasion = visit.diningOccasions[0] ?? null
        })
      })

    this.version(15)
      .stores({
        restaurants: restaurantSchema,
        visits: visitSchema,
        photos: 'id, userId, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
        photoCache: 'photoId, cachedAt, lastAccessedAt',
        users: 'id, nickname, email, updatedAt, deletedAt',
        friendships: 'id, requesterId, addresseeId, status, updatedAt',
        sharedMeals: 'id, restaurantId, createdByUserId, occurredAt, updatedAt, deletedAt',
        sharedMealParticipants: 'id, sharedMealId, userId, visitId, status, updatedAt',
        diningCompanions: 'id, ownerUserId, displayName, linkedUserId, updatedAt, deletedAt',
        syncQueue: 'id, entityType, entityId, updatedAt',
        syncMetadata: 'key',
      })
      .upgrade(async (transaction) => {
        const now = new Date().toISOString()
        const companions = transaction.table('diningCompanions')
        const companionByName = new Map<string, string>()
        const visits = await transaction.table('visits').toArray()
        visits.forEach((visit) => {
          const names = Array.isArray(visit.companions) ? visit.companions.map((name: string) => name.trim()).filter(Boolean) : []
          names.forEach((name: string) => {
            const key = name.toLocaleLowerCase('zh-CN')
            if (!companionByName.has(key)) companionByName.set(key, `companion:owner:${encodeURIComponent(key)}`)
          })
        })
        await companions.bulkPut([...companionByName].map(([key, id]) => {
          const displayName = visits.flatMap((visit) => Array.isArray(visit.companions) ? visit.companions : []).find((name: string) => name.trim().toLocaleLowerCase('zh-CN') === key) ?? key
          return { id, ownerUserId: 'owner', displayName, linkedUserId: null, createdAt: now, updatedAt: now, deletedAt: null }
        }))
        await transaction.table('visits').toCollection().modify((visit) => {
          const names = Array.isArray(visit.companions) ? visit.companions.map((name: string) => name.trim()).filter(Boolean) : []
          visit.companionIds = names.map((name: string) => companionByName.get(name.toLocaleLowerCase('zh-CN')) as string)
        })
      })

    this.version(16).stores({
      restaurants: restaurantSchema,
      visits: visitSchema,
      photos: 'id, userId, restaurantId, visitId, kind, updatedAt, deletedAt, localState',
      photoCache: 'photoId, cachedAt, lastAccessedAt',
      users: 'id, nickname, email, updatedAt, deletedAt, isTestUser',
      friendships: 'id, requesterId, addresseeId, status, updatedAt, isTestData',
      follows: 'id, followerId, followedUserId, createdAt, isTestData',
      sharedMeals: 'id, restaurantId, createdByUserId, occurredAt, updatedAt, deletedAt, isTestData',
      sharedMealParticipants: 'id, sharedMealId, userId, visitId, status, updatedAt, isTestData',
      diningCompanions: 'id, ownerUserId, displayName, linkedUserId, updatedAt, deletedAt',
      syncQueue: 'id, entityType, entityId, updatedAt',
      syncMetadata: 'key',
    })
  }
}

export const db = new FoodMapDatabase()
