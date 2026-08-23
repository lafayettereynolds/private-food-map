import Dexie from 'dexie'
import { db } from './appDb'
import type {
  DiningDuration,
  DiningMode,
  DiningOccasion,
  MarkerType,
  NoiseLevel,
  PaymentMode,
  PoiSearchResult,
  PortionLevel,
  PreferenceLevel,
  QueueDuration,
  RecommendationSourceType,
  Restaurant,
  RestaurantStatus,
  StarRating,
  TransportConvenience,
  Visit,
  VisitDish,
  Visibility,
} from '../types/domain'
import { calculatePricePerPerson } from '../types/domain'
import { syncQueueId } from '../types/sync'
import { requestCloudSync } from '../services/syncEvents'
import { createSharedMealInvitations } from './social'
import { ensureDiningCompanions } from './diningCompanions'

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
    .filter((dish) => dish.name.trim() || (dish.taste ?? '').trim() || dish.rating !== null || dish.price !== null || dish.imageData || dish.photoId)
    .map((dish) => ({
      ...dish,
      name: dish.name.trim(),
      taste: (dish.taste ?? '').trim(),
      rating: dish.rating ?? null,
    }))
}

function normalizeCompanions(companions: string[]) {
  return [...new Set(companions.map((companion) => companion.trim()).filter(Boolean))]
}

function normalizeLabels(labels: string[]) {
  return [...new Set(labels.map((label) => label.trim().slice(0, 12)).filter(Boolean))]
}

export interface InitialVisitInput {
  visitedAt: string
  rating: StarRating
  visibility: Visibility
  diningMode: DiningMode
  totalPrice: number | null
  myActualSpend: number | null
  paymentMode: PaymentMode | null
  partySize: number
  queueDuration: QueueDuration
  diningOccasions: DiningOccasion[]
  diningOccasion: DiningOccasion | null
  diningOccasionText: string
  valueRating: StarRating | null
  environmentRating: StarRating | null
  serviceRating: StarRating | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: NoiseLevel | null
  diningDuration: DiningDuration | null
  portionLevel: PortionLevel | null
  transportConvenience: TransportConvenience | null
  specialNotes: string
  recommendationSourceType: RecommendationSourceType | null
  recommendationSourceUserId: string | null
  recommendationSourceText: string
  sharedParticipantUserIds: string[]
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
    userId: existingRestaurant?.userId ?? 'owner',
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
    markerPhotoId: null,
    merchantImageUrl: input.poi.merchantImageUrl,
    markerEmoji: input.markerEmoji || '🍽️',
    createdAt: existingRestaurant?.createdAt ?? now,
    updatedAt: now,
    deletedAt: null,
  }

  const normalizedInitialCompanions = input.initialVisit ? normalizeCompanions(input.initialVisit.companions) : []
  const initialCompanionIds = (await ensureDiningCompanions(normalizedInitialCompanions)).map((companion) => companion.id)
  const visit: Visit | null = input.initialVisit
    ? {
        id: createId(),
        userId: 'owner',
        restaurantId,
        visitedAt: input.initialVisit.visitedAt,
        rating: input.initialVisit.rating,
        visibility: input.initialVisit.visibility,
        diningMode: input.initialVisit.diningMode,
        totalPrice: input.initialVisit.totalPrice,
        myActualSpend: input.initialVisit.myActualSpend,
        paymentMode: input.initialVisit.paymentMode,
        pricePerPerson: calculatePricePerPerson(
          input.initialVisit.totalPrice,
          Math.max(1, input.initialVisit.partySize, input.initialVisit.companions.length + 1),
        ),
        partySize: Math.max(1, input.initialVisit.partySize, input.initialVisit.companions.length + 1),
        queueDuration: input.initialVisit.queueDuration,
        diningOccasions: [...new Set(input.initialVisit.diningOccasions)],
        diningOccasion: input.initialVisit.diningOccasion,
        diningOccasionText: input.initialVisit.diningOccasionText.trim(),
        valueRating: input.initialVisit.valueRating,
        environmentRating: input.initialVisit.environmentRating,
        serviceRating: input.initialVisit.serviceRating,
        valueTags: normalizeLabels(input.initialVisit.valueTags),
        environmentTags: normalizeLabels(input.initialVisit.environmentTags),
        serviceTags: normalizeLabels(input.initialVisit.serviceTags),
        noiseLevel: input.initialVisit.noiseLevel,
        diningDuration: input.initialVisit.diningDuration,
        portionLevel: input.initialVisit.portionLevel,
        transportConvenience: input.initialVisit.transportConvenience,
        specialNotes: input.initialVisit.specialNotes.trim(),
        recommendationSourceType: input.initialVisit.recommendationSourceType,
        recommendationSourceUserId: input.initialVisit.recommendationSourceUserId,
        recommendationSourceText: input.initialVisit.recommendationSourceText.trim(),
        sharedMealId: null,
        companions: normalizedInitialCompanions,
        companionIds: initialCompanionIds,
        dishes: normalizeDishes(input.initialVisit.dishes),
        note: input.initialVisit.note.trim(),
        photos: input.initialVisit.photos,
        photoIds: input.initialVisit.photos.map(() => null),
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
    if (visit && input.initialVisit?.sharedParticipantUserIds.length) {
      await createSharedMealInvitations(visit, input.initialVisit.sharedParticipantUserIds)
    }
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
  markerPhotoId: string | null
  markerEmoji: string
  latitude: number
  longitude: number
}

export async function updateRestaurantBasics(
  id: string,
  changes: RestaurantBasicsUpdate,
) {
  const now = new Date().toISOString()
  let updated = 0
  await db.transaction('rw', db.restaurants, db.photos, db.syncQueue, async () => {
    const existing = await db.restaurants.get(id)
    if (!existing) return
    if (existing.markerPhotoId && existing.markerPhotoId !== changes.markerPhotoId) {
      await db.photos.update(existing.markerPhotoId, {
        localState: 'delete-pending',
        updatedAt: now,
        lastError: null,
      })
    }
    updated = await db.restaurants.update(id, {
      ...changes,
      name: changes.name.trim(),
      address: changes.address.trim(),
      city: changes.city.trim(),
      latitude: changes.latitude,
      longitude: changes.longitude,
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
  visibility: Visibility
  diningMode: DiningMode
  totalPrice: number | null
  myActualSpend: number | null
  paymentMode: PaymentMode | null
  partySize: number
  queueDuration: QueueDuration
  diningOccasions: DiningOccasion[]
  diningOccasion: DiningOccasion | null
  diningOccasionText: string
  valueRating: StarRating | null
  environmentRating: StarRating | null
  serviceRating: StarRating | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: NoiseLevel | null
  diningDuration: DiningDuration | null
  portionLevel: PortionLevel | null
  transportConvenience: TransportConvenience | null
  specialNotes: string
  recommendationSourceType: RecommendationSourceType | null
  recommendationSourceUserId: string | null
  recommendationSourceText: string
  sharedParticipantUserIds: string[]
  companions: string[]
  dishes: VisitDish[]
  note: string
  photos: string[]
  photoIds: Array<string | null>
}

export async function addVisit(restaurantId: string, input: AddVisitInput) {
  const now = new Date().toISOString()
  const companions = normalizeCompanions(input.companions)
  const companionIds = (await ensureDiningCompanions(companions)).map((companion) => companion.id)
  const normalizedPartySize = Math.max(1, input.partySize, companions.length + 1)
  const pricePerPerson = calculatePricePerPerson(input.totalPrice, normalizedPartySize)
  const visit: Visit = {
    id: createId(),
    userId: 'owner',
    restaurantId,
    visitedAt: input.visitedAt,
    rating: input.rating,
    visibility: input.visibility,
    diningMode: input.diningMode,
    totalPrice: input.totalPrice,
    myActualSpend: input.myActualSpend,
    paymentMode: input.paymentMode,
    pricePerPerson,
    partySize: normalizedPartySize,
    queueDuration: input.queueDuration,
    diningOccasions: [...new Set(input.diningOccasions)],
    diningOccasion: input.diningOccasion,
    diningOccasionText: input.diningOccasionText.trim(),
    valueRating: input.valueRating,
    environmentRating: input.environmentRating,
    serviceRating: input.serviceRating,
    valueTags: normalizeLabels(input.valueTags),
    environmentTags: normalizeLabels(input.environmentTags),
    serviceTags: normalizeLabels(input.serviceTags),
    noiseLevel: input.noiseLevel,
    diningDuration: input.diningDuration,
    portionLevel: input.portionLevel,
    transportConvenience: input.transportConvenience,
    specialNotes: input.specialNotes.trim(),
    recommendationSourceType: input.recommendationSourceType,
    recommendationSourceUserId: input.recommendationSourceUserId,
    recommendationSourceText: input.recommendationSourceText.trim(),
    sharedMealId: null,
    companions,
    companionIds,
    dishes: normalizeDishes(input.dishes),
    note: input.note.trim(),
    photos: input.photos,
    photoIds: input.photos.map((_, index) => input.photoIds[index] ?? null),
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  }

  await db.transaction('rw', db.restaurants, db.visits, db.photos, db.syncQueue, async () => {
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
  if (input.sharedParticipantUserIds.length) {
    await createSharedMealInvitations(visit, input.sharedParticipantUserIds)
  }
  return visit
}

export async function updateVisit(id: string, input: AddVisitInput) {
  const now = new Date().toISOString()
  const companions = normalizeCompanions(input.companions)
  const companionIds = (await ensureDiningCompanions(companions)).map((companion) => companion.id)
  const normalizedPartySize = Math.max(1, input.partySize, companions.length + 1)
  const pricePerPerson = calculatePricePerPerson(input.totalPrice, normalizedPartySize)
  let updatedVisit: Visit | null = null

  await db.transaction('rw', db.restaurants, db.visits, db.syncQueue, async () => {
    const existingVisit = await db.visits.get(id)
    if (!existingVisit || existingVisit.deletedAt) throw new Error('没有找到要更新的到访记录。')
    const restaurant = await db.restaurants.get(existingVisit.restaurantId)
    if (!restaurant || restaurant.deletedAt) throw new Error('没有找到这家餐厅。')

    updatedVisit = {
      ...existingVisit,
      visitedAt: input.visitedAt,
      rating: input.rating,
      visibility: input.visibility,
      diningMode: input.diningMode,
      totalPrice: input.totalPrice,
      myActualSpend: input.myActualSpend,
      paymentMode: input.paymentMode,
      pricePerPerson,
      partySize: normalizedPartySize,
      queueDuration: input.queueDuration,
      diningOccasions: [...new Set(input.diningOccasions)],
      diningOccasion: input.diningOccasion,
      diningOccasionText: input.diningOccasionText.trim(),
      valueRating: input.valueRating,
      environmentRating: input.environmentRating,
      serviceRating: input.serviceRating,
      valueTags: normalizeLabels(input.valueTags),
      environmentTags: normalizeLabels(input.environmentTags),
      serviceTags: normalizeLabels(input.serviceTags),
      noiseLevel: input.noiseLevel,
      diningDuration: input.diningDuration,
      portionLevel: input.portionLevel,
      transportConvenience: input.transportConvenience,
      specialNotes: input.specialNotes.trim(),
      recommendationSourceType: input.recommendationSourceType,
      recommendationSourceUserId: input.recommendationSourceUserId,
      recommendationSourceText: input.recommendationSourceText.trim(),
      companions,
      companionIds,
      dishes: normalizeDishes(input.dishes),
      note: input.note.trim(),
      photos: input.photos,
      photoIds: input.photos.map((_, index) => input.photoIds[index] ?? null),
      updatedAt: now,
      deletedAt: null,
    }
    const retainedPhotoIds = new Set([
      ...updatedVisit.photoIds,
      ...updatedVisit.dishes.map((dish) => dish.photoId),
    ].filter((photoId): photoId is string => Boolean(photoId)))
    const removedPhotoIds = [
      ...existingVisit.photoIds,
      ...existingVisit.dishes.map((dish) => dish.photoId),
    ].filter((photoId): photoId is string => Boolean(photoId) && !retainedPhotoIds.has(photoId as string))
    if (removedPhotoIds.length) {
      await db.photos.where('id').anyOf(removedPhotoIds).modify({
        localState: 'delete-pending',
        updatedAt: now,
        lastError: null,
      })
    }
    await db.visits.put(updatedVisit)

    const activeVisits = (await db.visits.where('restaurantId').equals(existingVisit.restaurantId).toArray())
      .filter((visit) => !visit.deletedAt)
    const ratings = activeVisits
      .map((visit) => visit.rating)
      .filter((rating): rating is StarRating => rating !== null)
    const averageRating = ratings.length
      ? ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length
      : null
    const latestPricePerPerson = activeVisits
      .filter((visit) => visit.pricePerPerson !== null)
      .sort((a, b) => b.visitedAt.localeCompare(a.visitedAt))[0]?.pricePerPerson

    await db.restaurants.update(restaurant.id, {
      status: 'visited',
      preferenceLevel: legacyPreferenceLevelFromRating(averageRating),
      pricePerPerson: latestPricePerPerson ?? restaurant.pricePerPerson,
      updatedAt: now,
      deletedAt: null,
    })
    await db.syncQueue.bulkPut([
      {
        id: syncQueueId('restaurant', restaurant.id),
        entityType: 'restaurant',
        entityId: restaurant.id,
        updatedAt: now,
      },
      {
        id: syncQueueId('visit', id),
        entityType: 'visit',
        entityId: id,
        updatedAt: now,
      },
    ])
  })

  requestCloudSync()
  if (!updatedVisit) throw new Error('没有找到要更新的到访记录。')
  return updatedVisit
}

export async function deleteRestaurant(id: string) {
  const now = new Date().toISOString()
  await db.transaction('rw', db.restaurants, db.visits, db.photos, db.syncQueue, async () => {
    const restaurant = await db.restaurants.get(id)
    if (!restaurant) return
    const visits = await db.visits.where('restaurantId').equals(id).toArray()
    const photos = await db.photos.where('restaurantId').equals(id).toArray()
    await db.restaurants.update(id, { deletedAt: now, updatedAt: now })
    if (visits.length) {
      await db.visits.bulkPut(visits.map((visit) => ({ ...visit, deletedAt: now, updatedAt: now })))
    }
    if (photos.length) {
      await db.photos.bulkPut(photos.map((photo) => ({
        ...photo,
        localState: 'delete-pending' as const,
        updatedAt: now,
        lastError: null,
      })))
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
