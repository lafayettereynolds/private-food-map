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

function normalizeDishes(dishes: VisitDish[]) {
  return dishes
    .filter((dish) => dish.name.trim() || (dish.taste ?? '').trim() || dish.price !== null || dish.imageData)
    .map((dish) => ({
      ...dish,
      name: dish.name.trim(),
      taste: (dish.taste ?? '').trim(),
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
  preferenceLevel: PreferenceLevel
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
  const restaurantId = createId()
  const restaurant: Restaurant = {
    id: restaurantId,
    amapPoiId: input.poi.amapPoiId,
    name: input.poi.name,
    address: input.address.trim() || input.poi.address,
    city: input.poi.city,
    latitude: input.poi.latitude,
    longitude: input.poi.longitude,
    status: input.status,
    preferenceLevel: input.preferenceLevel,
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
    createdAt: now,
    updatedAt: now,
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
      }
    : null

  try {
    await db.transaction('rw', db.restaurants, db.visits, async () => {
      await db.restaurants.add(restaurant)
      if (visit) await db.visits.add(visit)
    })
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
  preferenceLevel: PreferenceLevel
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
  const updated = await db.restaurants.update(id, {
    ...changes,
    name: changes.name.trim(),
    address: changes.address.trim(),
    city: changes.city.trim(),
    tags: changes.tags.map((tag) => tag.trim()).filter(Boolean),
    markerEmoji: changes.markerEmoji.trim() || '🍽️',
    updatedAt: new Date().toISOString(),
  })

  if (!updated) throw new Error('没有找到要更新的餐厅。')
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
  }

  await db.transaction('rw', db.restaurants, db.visits, async () => {
    const restaurant = await db.restaurants.get(restaurantId)
    if (!restaurant) throw new Error('没有找到这家餐厅。')
    await db.visits.add(visit)
    await db.restaurants.update(restaurantId, {
      status: 'visited',
      pricePerPerson: pricePerPerson ?? restaurant.pricePerPerson,
      updatedAt: now,
    })
  })

  return visit
}

export async function deleteRestaurant(id: string) {
  await db.transaction('rw', db.restaurants, db.visits, async () => {
    await db.visits.where('restaurantId').equals(id).delete()
    await db.restaurants.delete(id)
  })
}
