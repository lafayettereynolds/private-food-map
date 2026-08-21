import { db } from './appDb'
import { APP_ENVIRONMENT, DATABASE_NAME } from '../config/appEnvironment'
import type { Photo, Restaurant, Visit } from '../types/domain'
import type { CloudPhoto } from '../types/cloudSync'
import { syncQueueId } from '../types/sync'
import { requestCloudSync } from '../services/syncEvents'
import { BACKUP_FILE_PREFIX } from '../config/appEnvironment'

interface FoodMapBackup {
  app: 'Taste Map'
  version: 2
  environment: typeof APP_ENVIRONMENT
  databaseName: string
  exportedAt: string
  restaurants: Restaurant[]
  visits: Visit[]
  photos: CloudPhoto[]
}

function createId() {
  if ('randomUUID' in crypto) return crypto.randomUUID()
  return `import-${Date.now()}-${Math.random().toString(36).slice(2)}`
}

export async function createFoodMapBackup() {
  const [restaurants, visits, localPhotos] = await Promise.all([
    db.restaurants.toArray(),
    db.visits.toArray(),
    db.photos.toArray(),
  ])
  const photos = localPhotos.map(({ localState, lastError, ...photo }) => {
    void localState
    void lastError
    return photo
  })
  const backup: FoodMapBackup = {
    app: 'Taste Map',
    version: 2,
    environment: APP_ENVIRONMENT,
    databaseName: DATABASE_NAME,
    exportedAt: new Date().toISOString(),
    restaurants,
    visits,
    photos,
  }
  return JSON.stringify(backup, null, 2)
}

export async function downloadFoodMapBackup() {
  const json = await createFoodMapBackup()
  const blob = new Blob([json], { type: 'application/json;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${BACKUP_FILE_PREFIX}-${new Date().toISOString().slice(0, 10)}.json`
  link.click()
  window.setTimeout(() => URL.revokeObjectURL(url), 0)
}

export async function importFoodMapBackup(rawText: string) {
  let parsed: unknown
  try {
    parsed = JSON.parse(rawText)
  } catch {
    throw new Error('这个文件不是有效的 JSON 备份。')
  }

  if (!isBackupShape(parsed)) {
    throw new Error('没有识别到 Taste Map 的餐厅和到访数据。')
  }

  const importedRestaurants = parsed.restaurants.filter(isRestaurantShape)
  const importedVisits = parsed.visits.filter(isVisitShape)
  const importedPhotos = (parsed.photos ?? []).filter(isPhotoShape)
  if (!importedRestaurants.length && !importedVisits.length) {
    throw new Error('备份中没有可导入的记录。')
  }

  let restaurantCount = 0
  let visitCount = 0
  await db.transaction('rw', db.restaurants, db.visits, db.photos, db.syncQueue, async () => {
    const existingRestaurants = await db.restaurants.toArray()
    const existingByPoiId = new Map(existingRestaurants.map((restaurant) => [restaurant.amapPoiId, restaurant]))
    const existingById = new Map(existingRestaurants.map((restaurant) => [restaurant.id, restaurant]))
    const restaurantIdMap = new Map<string, string>()

    for (const imported of importedRestaurants) {
      const samePoi = existingByPoiId.get(imported.amapPoiId)
      const idConflict = existingById.get(imported.id)
      const targetId = samePoi?.id ?? (idConflict ? createId() : imported.id)
      const normalized: Restaurant = {
        ...imported,
        id: targetId,
        tags: Array.isArray(imported.tags) ? imported.tags : [],
        markerType: imported.markerType || 'emoji',
        markerImageData: imported.markerImageData ?? null,
        markerPhotoId: imported.markerPhotoId ?? null,
        merchantImageUrl: imported.merchantImageUrl ?? null,
        markerEmoji: imported.markerEmoji || '🍽️',
        longTermNote: imported.longTermNote ?? '',
        pricePerPerson: imported.pricePerPerson ?? null,
        updatedAt: imported.updatedAt || new Date().toISOString(),
        deletedAt: imported.deletedAt ?? null,
      }
      await db.restaurants.put(normalized)
      await db.syncQueue.put({
        id: syncQueueId('restaurant', normalized.id),
        entityType: 'restaurant',
        entityId: normalized.id,
        updatedAt: normalized.updatedAt,
      })
      restaurantIdMap.set(imported.id, targetId)
      existingByPoiId.set(normalized.amapPoiId, normalized)
      existingById.set(targetId, normalized)
      restaurantCount += 1
    }

    for (const imported of importedVisits) {
      const targetRestaurantId = restaurantIdMap.get(imported.restaurantId) ?? imported.restaurantId
      if (!existingById.has(targetRestaurantId)) continue
      const normalized: Visit = {
        ...imported,
        restaurantId: targetRestaurantId,
        companions: Array.isArray(imported.companions) ? imported.companions : [],
        dishes: Array.isArray(imported.dishes)
          ? imported.dishes.map((dish) => ({
              ...dish,
              taste: typeof dish.taste === 'string' ? dish.taste : '',
              rating: isStarRating(dish.rating) ? dish.rating : null,
              photoId: typeof dish.photoId === 'string' ? dish.photoId : null,
            }))
          : [],
        photos: Array.isArray(imported.photos) ? imported.photos : [],
        photoIds: Array.isArray(imported.photoIds)
          ? (imported.photos ?? []).map((_, index) => imported.photoIds[index] ?? null)
          : (imported.photos ?? []).map(() => null),
        note: imported.note ?? '',
        updatedAt: imported.updatedAt || new Date().toISOString(),
        deletedAt: imported.deletedAt ?? null,
      }
      await db.visits.put(normalized)
      await db.syncQueue.put({
        id: syncQueueId('visit', normalized.id),
        entityType: 'visit',
        entityId: normalized.id,
        updatedAt: normalized.updatedAt,
      })
      visitCount += 1
    }

    for (const imported of importedPhotos) {
      const normalized: Photo = {
        ...imported,
        restaurantId: imported.restaurantId ? (restaurantIdMap.get(imported.restaurantId) ?? imported.restaurantId) : null,
        localState: 'synced',
        lastError: null,
      }
      await db.photos.put(normalized)
    }
  })

  requestCloudSync()
  return { restaurantCount, visitCount }
}

function isStarRating(value: unknown): value is 1 | 2 | 3 | 4 | 5 {
  return Number.isInteger(value) && Number(value) >= 1 && Number(value) <= 5
}

function isBackupShape(value: unknown): value is { restaurants: unknown[]; visits: unknown[]; photos?: unknown[] } {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Record<string, unknown>
  return Array.isArray(candidate.restaurants) && Array.isArray(candidate.visits)
}

function isPhotoShape(value: unknown): value is CloudPhoto {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Partial<CloudPhoto>
  return Boolean(
    candidate.id && candidate.storageProvider === 'google-drive' && candidate.driveAccountId &&
    candidate.driveFileId && candidate.mimeType && typeof candidate.fileSize === 'number' &&
    candidate.createdAt && candidate.updatedAt,
  )
}

function isRestaurantShape(value: unknown): value is Restaurant {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Partial<Restaurant>
  return Boolean(
    candidate.id &&
    candidate.amapPoiId &&
    candidate.name &&
    candidate.city &&
    Number.isFinite(candidate.latitude) &&
    Number.isFinite(candidate.longitude) &&
    (candidate.status === 'visited' || candidate.status === 'wantToGo'),
  )
}

function isVisitShape(value: unknown): value is Visit {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Partial<Visit>
  return Boolean(candidate.id && candidate.restaurantId && candidate.visitedAt)
}
