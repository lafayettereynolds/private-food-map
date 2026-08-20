import Dexie from 'dexie'
import { db } from './appDb'
import type {
  MarkerType,
  PoiSearchResult,
  PreferenceLevel,
  QueueDuration,
  Restaurant,
  RestaurantStatus,
  StarRating,
  Visit,
  VisitDish,
} from '../types/domain'
import { calculatePricePerPerson } from '../types/domain'
import { syncQueueId } from '../types/sync'
import { requestCloudSync } from '../services/syncEvents'

export class DuplicateRestaurantError extends Error {
  constructor() {
    super('这家餐厅已经在你的地图中。')
    this.name = 'DuplicateRestaurantError'
  }
}

function createId() {
  if ('randomUUID' in crypto) return crypto.randomUUID()
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`
}

function legacyPreferenceLevelFromRating(rating: number | null): PreferenceLevel {
  if (rating === null) return 'normal'
  if (rating >= 4.5) return 'favorite'
  if (rating >= 3.5) return 'like'
  if (rating >= 2.5) return 'normal'
  return 'avoid'
}

function normalizeDishes(dishes: VisitDish[]) {
  return dishes
    .filter((dish) => dish.name.trim() || (dish.taste ?? '').trim() || dish.rating !== null || dish.price !== null || dish.imageData)
    .map((dish) => ({
      ...dish,
      name: dish.name.trim(),
      taste: (dish.taste ?? '').trim(),
      rating: dish.rating ?? null,
    }))
}

export interface InitialVisitInput {
  visitedAt: string
  rating: StarRating
  totalPrice: number | null
  partySize: number
  queueDuration: QueueDuration
  companions: string[]
  dishes: VisitDish[]
  note: string
  photos: string[]
}

export interface AddRestaurantInput {
  poi: PoiSearchResult
  address: string
  status: RestaurantStatus
  tags: string[]
  pricePerPerson: number | null
  markerType: MarkerType
  markerImageData: string | null
  markerEmoji: string
  initialVisit: InitialVisitInput | null
}

export async function addRestaurantFromPoi(
  input: AddRestaurantInput,
): Promise<Restaurant> {
  const now = new Date().toISOString()
  const existingRestaurant = await db.restaurants.where('amapPoiId').equals(input.poi.amapPoiId).first()
  if (existingRestaurant && !existingRestaurant.deletedAt) throw new DuplicateRestaurantError()
  const restaurantId = existingRestaurant?.id ?? createId()
  const restaurant: Restaurant = {
    id: restaurantId,
    amapPoiId: input.poi.amapPoiId,
    name: input.poi.name,
    address: input.address.trim() || input.poi.address,
    city: input.poi.city,
    latitude: input.poi.latitude,
    longitude: input.poi.longitude,
    status: input.status,
    preferenceLevel: legacyPreferenceLevelFromRating(input.initialVisit?.rating ?? null),
    overallRating: null,
    foodRating: null,
    environmentRating: null,
    serviceRating: null,
    valueRating: null,
    tags: input.tags,
    longTermNote: '',
    pricePerPerson: input.pricePerPerson,
    markerType: input.markerType,
    markerImageData: input.markerImageData,
    merchantImageUrl: input.poi.merchantImageUrl,
    markerEmoji: input.markerEmoji || '🍽️',
    createdAt: existingRestaurant?.createdAt ?? now,
    updatedAt: now,
    deletedAt: null,
  }

  const visit: Visit | null = input.initialVisit
    ? {
        id: createId(),
        restaurantId,
        visitedAt: input.initialVisit.visitedAt,
        rating: input.initialVisit.rating,
        totalPrice: input.initialVisit.totalPrice,
        pricePerPerson: calculatePricePerPerson(
          input.initialVisit.totalPrice,
          Math.max(1, input.initialVisit.partySize, input.initialVisit.companions.length + 1),
        ),
        partySize: Math.max(1, input.initialVisit.partySize, input.initialVisit.companions.length + 1),
        queueDuration: input.initialVisit.queueDuration,
        companions: input.initialVisit.companions,
        dishes: normalizeDishes(input.initialVisit.dishes),
        note: input.initialVisit.note.trim(),
        photos: input.initialVisit.photos,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      }
    : null

  try {
    await db.transaction('rw', db.restaurants, db.visits, db.syncQueue, async () => {
      await db.restaurants.put(restaurant)
      if (visit) await db.visits.add(visit)
      await db.syncQueue.put({
        id: syncQueueId('restaurant', restaurant.id),
        entityType: 'restaurant',
        entityId: restaurant.id,
        updatedAt: now,
      })
      if (visit) {
        await db.syncQueue.put({
          id: syncQueueId('visit', visit.id),
          entityType: 'visit',
          entityId: visit.id,
          updatedAt: now,
        })
      }
    })
    requestCloudSync()
    return restaurant
  } catch (error) {
    if (error instanceof Dexie.ConstraintError) {
      throw new DuplicateRestaurantError()
    }
    throw error
  }
}

export interface RestaurantBasicsUpdate {
  name: string
  address: string
  city: string
  status: RestaurantStatus
  tags: string[]
  pricePerPerson: number | null
  markerType: MarkerType
  markerImageData: string | null
  markerEmoji: string
}

export async function updateRestaurantBasics(
  id: string,
  changes: RestaurantBasicsUpdate,
) {
  const now = new Date().toISOString()
  let updated = 0
  await db.transaction('rw', db.restaurants, db.syncQueue, async () => {
    updated = await db.restaurants.update(id, {
      ...changes,
      name: changes.name.trim(),
      address: changes.address.trim(),
      city: changes.city.trim(),
      tags: changes.tags.map((tag) => tag.trim()).filter(Boolean),
      markerEmoji: changes.markerEmoji.trim() || '🍽️',
      updatedAt: now,
      deletedAt: null,
    })
    if (updated) {
      await db.syncQueue.put({
        id: syncQueueId('restaurant', id),
        entityType: 'restaurant',
        entityId: id,
        updatedAt: now,
      })
    }
  })

  if (!updated) throw new Error('没有找到要更新的餐厅。')
  requestCloudSync()
}

export interface AddVisitInput {
  visitedAt: string
  rating: StarRating
  totalPrice: number | null
  partySize: number
  queueDuration: QueueDuration
  companions: string[]
  dishes: VisitDish[]
  note: string
  photos: string[]
}

export async function addVisit(restaurantId: string, input: AddVisitInput) {
  const now = new Date().toISOString()
  const normalizedPartySize = Math.max(1, input.partySize, input.companions.length + 1)
  const pricePerPerson = calculatePricePerPerson(input.totalPrice, normalizedPartySize)
  const visit: Visit = {
    id: createId(),
    restaurantId,
    visitedAt: input.visitedAt,
    rating: input.rating,
    totalPrice: input.totalPrice,
    pricePerPerson,
    partySize: normalizedPartySize,
    queueDuration: input.queueDuration,
    companions: input.companions,
    dishes: normalizeDishes(input.dishes),
    note: input.note.trim(),
    photos: input.photos,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  }

  await db.transaction('rw', db.restaurants, db.visits, db.syncQueue, async () => {
    const restaurant = await db.restaurants.get(restaurantId)
    if (!restaurant) throw new Error('没有找到这家餐厅。')
    await db.visits.add(visit)
    const ratings = (await db.visits.where('restaurantId').equals(restaurantId).toArray())
      .map((item) => item.rating)
      .filter((rating): rating is StarRating => rating !== null)
    const averageRating = ratings.length
      ? ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length
      : null
    await db.restaurants.update(restaurantId, {
      status: 'visited',
      preferenceLevel: legacyPreferenceLevelFromRating(averageRating),
      pricePerPerson: pricePerPerson ?? restaurant.pricePerPerson,
      updatedAt: now,
      deletedAt: null,
    })
    await db.syncQueue.bulkPut([
      {
        id: syncQueueId('restaurant', restaurantId),
        entityType: 'restaurant',
        entityId: restaurantId,
        updatedAt: now,
      },
      {
        id: syncQueueId('visit', visit.id),
        entityType: 'visit',
        entityId: visit.id,
        updatedAt: now,
      },
    ])
  })

  requestCloudSync()
  return visit
}

export async function deleteRestaurant(id: string) {
  const now = new Date().toISOString()
  await db.transaction('rw', db.restaurants, db.visits, db.syncQueue, async () => {
    const restaurant = await db.restaurants.get(id)
    if (!restaurant) return
    const visits = await db.visits.where('restaurantId').equals(id).toArray()
    await db.restaurants.update(id, { deletedAt: now, updatedAt: now })
    if (visits.length) {
      await db.visits.bulkPut(visits.map((visit) => ({ ...visit, deletedAt: now, updatedAt: now })))
    }
    await db.syncQueue.bulkPut([
      {
        id: syncQueueId('restaurant', id),
        entityType: 'restaurant',
        entityId: id,
        updatedAt: now,
      },
      ...visits.map((visit) => ({
        id: syncQueueId('visit' as const, visit.id),
        entityType: 'visit' as const,
        entityId: visit.id,
        updatedAt: now,
      })),
    ])
  })
  requestCloudSync()
}
