import { db } from './appDb'
import type { Restaurant, Visit } from '../types/domain'

interface FoodMapBackup {
  app: '食途'
  version: 1
  exportedAt: string
  restaurants: Restaurant[]
  visits: Visit[]
}

function createId() {
  if ('randomUUID' in crypto) return crypto.randomUUID()
  return `import-${Date.now()}-${Math.random().toString(36).slice(2)}`
}

export async function createFoodMapBackup() {
  const [restaurants, visits] = await Promise.all([
    db.restaurants.toArray(),
    db.visits.toArray(),
  ])
  const backup: FoodMapBackup = {
    app: '食途',
    version: 1,
    exportedAt: new Date().toISOString(),
    restaurants,
    visits,
  }
  return JSON.stringify(backup, null, 2)
}

export async function importFoodMapBackup(rawText: string) {
  let parsed: unknown
  try {
    parsed = JSON.parse(rawText)
  } catch {
    throw new Error('这个文件不是有效的 JSON 备份。')
  }

  if (!isBackupShape(parsed)) {
    throw new Error('没有识别到食途的餐厅和到访数据。')
  }

  const importedRestaurants = parsed.restaurants.filter(isRestaurantShape)
  const importedVisits = parsed.visits.filter(isVisitShape)
  if (!importedRestaurants.length && !importedVisits.length) {
    throw new Error('备份中没有可导入的记录。')
  }

  let restaurantCount = 0
  let visitCount = 0
  await db.transaction('rw', db.restaurants, db.visits, async () => {
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
        merchantImageUrl: imported.merchantImageUrl ?? null,
        markerEmoji: imported.markerEmoji || '🍽️',
        longTermNote: imported.longTermNote ?? '',
        pricePerPerson: imported.pricePerPerson ?? null,
        updatedAt: imported.updatedAt || new Date().toISOString(),
      }
      await db.restaurants.put(normalized)
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
            }))
          : [],
        photos: Array.isArray(imported.photos) ? imported.photos : [],
        note: imported.note ?? '',
        updatedAt: imported.updatedAt || new Date().toISOString(),
      }
      await db.visits.put(normalized)
      visitCount += 1
    }
  })

  return { restaurantCount, visitCount }
}

function isBackupShape(value: unknown): value is { restaurants: unknown[]; visits: unknown[] } {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Record<string, unknown>
  return Array.isArray(candidate.restaurants) && Array.isArray(candidate.visits)
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
