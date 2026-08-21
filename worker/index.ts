import type { CloudPhoto, CloudRestaurant, CloudSnapshot, CloudVisit, CloudVisitDish } from '../src/types/cloudSync'
import type { MarkerType, PhotoKind, PreferenceLevel, QueueDuration, RestaurantStatus, StarRating } from '../src/types/domain'

interface Env {
  DB: D1Database
  ASSETS: Fetcher
}

interface RestaurantRow {
  id: string
  amap_poi_id: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  status: RestaurantStatus
  preference_level: PreferenceLevel
  overall_rating: number | null
  food_rating: number | null
  environment_rating: number | null
  service_rating: number | null
  value_rating: number | null
  tags_json: string
  long_term_note: string
  price_per_person: number | null
  marker_type: MarkerType
  marker_photo_id: string | null
  merchant_image_url: string | null
  marker_emoji: string
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface VisitRow {
  id: string
  restaurant_id: string
  visited_at: string
  rating: StarRating | null
  total_price: number | null
  price_per_person: number | null
  party_size: number
  queue_duration: QueueDuration | null
  companions_json: string
  dishes_json: string
  note: string
  photo_ids_json: string
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface PhotoRow {
  id: string
  restaurant_id: string | null
  visit_id: string | null
  storage_provider: 'google-drive'
  drive_account_id: string
  drive_file_id: string
  kind: PhotoKind
  file_name: string | null
  mime_type: string
  file_size: number
  width: number | null
  height: number | null
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface SyncPayload {
  restaurants: CloudRestaurant[]
  visits: CloudVisit[]
  photos: CloudPhoto[]
}

const RESTAURANT_UPSERT = `
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, overall_rating, food_rating, environment_rating, service_rating,
    value_rating, tags_json, long_term_note, price_per_person, marker_type,
    marker_photo_id, merchant_image_url, marker_emoji, created_at, updated_at, deleted_at
  ) VALUES (?, 'owner', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    amap_poi_id = excluded.amap_poi_id,
    name = excluded.name,
    address = excluded.address,
    city = excluded.city,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    status = excluded.status,
    preference_level = excluded.preference_level,
    overall_rating = excluded.overall_rating,
    food_rating = excluded.food_rating,
    environment_rating = excluded.environment_rating,
    service_rating = excluded.service_rating,
    value_rating = excluded.value_rating,
    tags_json = excluded.tags_json,
    long_term_note = excluded.long_term_note,
    price_per_person = excluded.price_per_person,
    marker_type = excluded.marker_type,
    marker_photo_id = excluded.marker_photo_id,
    merchant_image_url = excluded.merchant_image_url,
    marker_emoji = excluded.marker_emoji,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > restaurants.updated_at
`

const VISIT_UPSERT = `
  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, total_price, price_per_person,
    party_size, queue_duration, companions_json, dishes_json, note, photo_ids_json,
    created_at, updated_at, deleted_at
  ) VALUES (?, 'owner', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id,
    visited_at = excluded.visited_at,
    rating = excluded.rating,
    total_price = excluded.total_price,
    price_per_person = excluded.price_per_person,
    party_size = excluded.party_size,
    queue_duration = excluded.queue_duration,
    companions_json = excluded.companions_json,
    dishes_json = excluded.dishes_json,
    note = excluded.note,
    photo_ids_json = excluded.photo_ids_json,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > visits.updated_at
`

const PHOTO_UPSERT = `
  INSERT INTO photos (
    id, user_id, restaurant_id, visit_id, storage_provider, drive_account_id,
    drive_file_id, kind, file_name, mime_type, file_size, width, height,
    created_at, updated_at, deleted_at
  ) VALUES (?, 'owner', ?, ?, 'google-drive', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id,
    visit_id = excluded.visit_id,
    storage_provider = excluded.storage_provider,
    drive_account_id = excluded.drive_account_id,
    drive_file_id = excluded.drive_file_id,
    kind = excluded.kind,
    file_name = excluded.file_name,
    mime_type = excluded.mime_type,
    file_size = excluded.file_size,
    width = excluded.width,
    height = excluded.height,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > photos.updated_at
`

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url)
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request)
    if (url.pathname !== '/api/sync') return json({ error: '没有找到这个 API。' }, 404)
    if (!isSameOriginRequest(request, url)) return json({ error: '不允许跨站访问同步 API。' }, 403)

    try {
      if (request.method === 'GET') return json(await readSnapshot(env.DB))
      if (request.method === 'POST') {
        const payload = await readPayload(request)
        await upsertRestaurants(env.DB, payload.restaurants)
        await upsertVisits(env.DB, payload.visits)
        await upsertPhotos(env.DB, payload.photos)
        return json(await readSnapshot(env.DB))
      }
      return json({ error: '这个 API 只支持 GET 和 POST。' }, 405)
    } catch (error) {
      console.error('Taste Map sync error', error)
      const message = error instanceof Error ? error.message : 'D1 同步发生未知错误。'
      return json({ error: message }, error instanceof RequestError ? error.status : 500)
    }
  },
} satisfies ExportedHandler<Env>

async function readPayload(request: Request): Promise<SyncPayload> {
  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (contentLength > 5_000_000) throw new RequestError('同步数据过大，照片不应上传到 D1。', 413)
  const value: unknown = await request.json().catch(() => {
    throw new RequestError('同步请求不是有效的 JSON。', 400)
  })
  if (!isRecord(value) || !Array.isArray(value.restaurants) || !Array.isArray(value.visits)) {
    throw new RequestError('同步请求的数据格式不正确。', 400)
  }
  const photos = Array.isArray(value.photos) ? value.photos : []
  if (!value.restaurants.every(isCloudRestaurant) || !value.visits.every(isCloudVisit) || !photos.every(isCloudPhoto)) {
    throw new RequestError('同步请求包含无法识别的餐厅或到访记录。', 400)
  }
  return { restaurants: value.restaurants, visits: value.visits, photos }
}

async function upsertRestaurants(database: D1Database, restaurants: CloudRestaurant[]) {
  const statements = restaurants.map((restaurant) => database.prepare(RESTAURANT_UPSERT).bind(
    restaurant.id,
    restaurant.amapPoiId,
    restaurant.name,
    restaurant.address,
    restaurant.city,
    restaurant.latitude,
    restaurant.longitude,
    restaurant.status,
    restaurant.preferenceLevel,
    restaurant.overallRating,
    restaurant.foodRating,
    restaurant.environmentRating,
    restaurant.serviceRating,
    restaurant.valueRating,
    JSON.stringify(restaurant.tags),
    restaurant.longTermNote,
    restaurant.pricePerPerson,
    restaurant.markerType,
    restaurant.markerPhotoId ?? null,
    restaurant.merchantImageUrl,
    restaurant.markerEmoji,
    restaurant.createdAt,
    restaurant.updatedAt,
    restaurant.deletedAt,
  ))
  await runInChunks(database, statements)
}

async function upsertVisits(database: D1Database, visits: CloudVisit[]) {
  const statements = visits.map((visit) => database.prepare(VISIT_UPSERT).bind(
    visit.id,
    visit.restaurantId,
    visit.visitedAt,
    visit.rating,
    visit.totalPrice,
    visit.pricePerPerson,
    visit.partySize,
    visit.queueDuration,
    JSON.stringify(visit.companions),
    JSON.stringify(visit.dishes),
    visit.note,
    JSON.stringify(visit.photoIds ?? []),
    visit.createdAt,
    visit.updatedAt,
    visit.deletedAt,
  ))
  await runInChunks(database, statements)
}

async function upsertPhotos(database: D1Database, photos: CloudPhoto[]) {
  const statements = photos.map((photo) => database.prepare(PHOTO_UPSERT).bind(
    photo.id,
    photo.restaurantId,
    photo.visitId,
    photo.driveAccountId,
    photo.driveFileId,
    photo.kind,
    photo.fileName,
    photo.mimeType,
    photo.fileSize,
    photo.width,
    photo.height,
    photo.createdAt,
    photo.updatedAt,
    photo.deletedAt,
  ))
  await runInChunks(database, statements)
}

async function runInChunks(database: D1Database, statements: D1PreparedStatement[]) {
  for (let index = 0; index < statements.length; index += 50) {
    await database.batch(statements.slice(index, index + 50))
  }
}

async function readSnapshot(database: D1Database): Promise<CloudSnapshot> {
  const [restaurantResult, visitResult, photoResult] = await database.batch([
    database.prepare('SELECT * FROM restaurants ORDER BY updated_at ASC'),
    database.prepare('SELECT * FROM visits ORDER BY updated_at ASC'),
    database.prepare('SELECT * FROM photos ORDER BY updated_at ASC'),
  ])
  return {
    restaurants: (restaurantResult.results as unknown as RestaurantRow[]).map(rowToRestaurant),
    visits: (visitResult.results as unknown as VisitRow[]).map(rowToVisit),
    photos: (photoResult.results as unknown as PhotoRow[]).map(rowToPhoto),
    serverTime: new Date().toISOString(),
  }
}

function rowToRestaurant(row: RestaurantRow): CloudRestaurant {
  return {
    id: row.id,
    amapPoiId: row.amap_poi_id,
    name: row.name,
    address: row.address,
    city: row.city,
    latitude: row.latitude,
    longitude: row.longitude,
    status: row.status,
    preferenceLevel: row.preference_level,
    overallRating: row.overall_rating,
    foodRating: row.food_rating,
    environmentRating: row.environment_rating,
    serviceRating: row.service_rating,
    valueRating: row.value_rating,
    tags: parseStringArray(row.tags_json),
    longTermNote: row.long_term_note,
    pricePerPerson: row.price_per_person,
    markerType: row.marker_type,
    markerPhotoId: row.marker_photo_id,
    merchantImageUrl: row.merchant_image_url,
    markerEmoji: row.marker_emoji,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToVisit(row: VisitRow): CloudVisit {
  return {
    id: row.id,
    restaurantId: row.restaurant_id,
    visitedAt: row.visited_at,
    rating: row.rating,
    totalPrice: row.total_price,
    pricePerPerson: row.price_per_person,
    partySize: row.party_size,
    queueDuration: row.queue_duration,
    companions: parseStringArray(row.companions_json),
    dishes: parseDishes(row.dishes_json),
    note: row.note,
    photoIds: parseNullableStringArray(row.photo_ids_json),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToPhoto(row: PhotoRow): CloudPhoto {
  return {
    id: row.id,
    restaurantId: row.restaurant_id,
    visitId: row.visit_id,
    kind: row.kind,
    storageProvider: 'google-drive',
    driveAccountId: row.drive_account_id,
    driveFileId: row.drive_file_id,
    fileName: row.file_name,
    mimeType: row.mime_type,
    fileSize: row.file_size,
    width: row.width,
    height: row.height,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function parseStringArray(raw: string) {
  try {
    const value: unknown = JSON.parse(raw)
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []
  } catch {
    return []
  }
}

function parseNullableStringArray(raw: string) {
  try {
    const value: unknown = JSON.parse(raw)
    return Array.isArray(value)
      ? value.map((item) => typeof item === 'string' ? item : null)
      : []
  } catch {
    return []
  }
}

function parseDishes(raw: string): CloudVisitDish[] {
  try {
    const value: unknown = JSON.parse(raw)
    return Array.isArray(value) ? value.filter(isCloudVisitDish) : []
  } catch {
    return []
  }
}

function isCloudRestaurant(value: unknown): value is CloudRestaurant {
  if (!isRecord(value)) return false
  return typeof value.id === 'string' && typeof value.amapPoiId === 'string' &&
    typeof value.name === 'string' && typeof value.address === 'string' &&
    typeof value.city === 'string' && typeof value.latitude === 'number' &&
    typeof value.longitude === 'number' && typeof value.updatedAt === 'string' &&
    typeof value.createdAt === 'string' && Array.isArray(value.tags) &&
    !('markerImageData' in value)
}

function isCloudVisit(value: unknown): value is CloudVisit {
  if (!isRecord(value)) return false
  return typeof value.id === 'string' && typeof value.restaurantId === 'string' &&
    typeof value.visitedAt === 'string' && typeof value.updatedAt === 'string' &&
    typeof value.createdAt === 'string' && Array.isArray(value.companions) &&
    Array.isArray(value.dishes) && value.dishes.every(isCloudVisitDish) &&
    !('photos' in value)
}

function isCloudVisitDish(value: unknown): value is CloudVisitDish {
  return isRecord(value) && typeof value.id === 'string' && typeof value.name === 'string' &&
    typeof value.taste === 'string' && !('imageData' in value)
}

function isCloudPhoto(value: unknown): value is CloudPhoto {
  if (!isRecord(value)) return false
  return typeof value.id === 'string' &&
    (typeof value.restaurantId === 'string' || value.restaurantId === null) &&
    (typeof value.visitId === 'string' || value.visitId === null) &&
    value.storageProvider === 'google-drive' &&
    typeof value.driveAccountId === 'string' && typeof value.driveFileId === 'string' &&
    (value.kind === 'restaurant-marker' || value.kind === 'visit' || value.kind === 'dish') &&
    typeof value.mimeType === 'string' && typeof value.fileSize === 'number' &&
    typeof value.createdAt === 'string' && typeof value.updatedAt === 'string'
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object'
}

function isSameOriginRequest(request: Request, url: URL) {
  const origin = request.headers.get('origin')
  return !origin || origin === url.origin
}

function json(value: unknown, status = 200) {
  return Response.json(value, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
      'X-Content-Type-Options': 'nosniff',
    },
  })
}

class RequestError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
    this.name = 'RequestError'
  }
}
