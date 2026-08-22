import type {
  CloudFriendship,
  CloudPhoto,
  CloudRestaurant,
  CloudSharedMeal,
  CloudSharedMealParticipant,
  CloudSnapshot,
  CloudUser,
  CloudVisit,
  CloudVisitDish,
} from '../src/types/cloudSync'
import type {
  DiningDuration,
  DiningMode,
  DiningOccasion,
  AvatarPresetId,
  MarkerType,
  MembershipTier,
  NoiseLevel,
  PaymentMode,
  PhotoKind,
  PortionLevel,
  PreferenceLevel,
  QueueDuration,
  RecommendationSourceType,
  RestaurantStatus,
  StarRating,
  TransportConvenience,
  Visibility,
} from '../src/types/domain'

interface Env {
  DB: D1Database
  ASSETS: Fetcher
}

interface RestaurantRow {
  id: string
  user_id: string
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
  user_id: string
  restaurant_id: string
  visited_at: string
  rating: StarRating | null
  visibility: Visibility
  dining_mode: DiningMode
  total_price: number | null
  my_actual_spend: number | null
  payment_mode: PaymentMode | null
  price_per_person: number | null
  party_size: number
  queue_duration: QueueDuration | null
  dining_occasion: DiningOccasion | null
  dining_occasion_text: string
  dining_occasions_json: string
  value_rating: StarRating | null
  environment_rating: StarRating | null
  service_rating: StarRating | null
  value_tags_json: string
  environment_tags_json: string
  service_tags_json: string
  noise_level: NoiseLevel | null
  dining_duration: DiningDuration | null
  portion_level: PortionLevel | null
  transport_convenience: TransportConvenience | null
  special_notes: string
  recommendation_source_type: RecommendationSourceType | null
  recommendation_source_user_id: string | null
  recommendation_source_text: string
  shared_meal_id: string | null
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
  user_id: string
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

interface UserRow {
  id: string
  auth_provider: 'cloudflare-access' | 'local'
  auth_subject: string | null
  email: string | null
  nickname: string
  bio: string
  city: string
  avatar_image_data: string | null
  avatar_photo_id: string | null
  avatar_preset_id: AvatarPresetId
  membership_tier: MembershipTier
  map_sharing_enabled: number
  map_visibility: Visibility
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface FriendshipRow {
  id: string
  requester_id: string
  addressee_id: string
  status: CloudFriendship['status']
  created_at: string
  updated_at: string
}

interface SharedMealRow {
  id: string
  restaurant_id: string
  created_by_user_id: string
  occurred_at: string
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface SharedMealParticipantRow {
  id: string
  shared_meal_id: string
  user_id: string
  visit_id: string | null
  status: CloudSharedMealParticipant['status']
  created_at: string
  updated_at: string
}

interface SyncPayload {
  restaurants: CloudRestaurant[]
  visits: CloudVisit[]
  photos: CloudPhoto[]
  users: CloudUser[]
  friendships: CloudFriendship[]
  sharedMeals: CloudSharedMeal[]
  sharedMealParticipants: CloudSharedMealParticipant[]
}

const RESTAURANT_UPSERT = `
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, overall_rating, food_rating, environment_rating, service_rating,
    value_rating, tags_json, long_term_note, price_per_person, marker_type,
    marker_photo_id, merchant_image_url, marker_emoji, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    user_id = excluded.user_id,
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
    id, user_id, restaurant_id, visited_at, rating, visibility, dining_mode,
    total_price, my_actual_spend, payment_mode, price_per_person, party_size,
    queue_duration, dining_occasion, dining_occasion_text, dining_occasions_json, value_rating, environment_rating, service_rating,
    value_tags_json, environment_tags_json, service_tags_json,
    noise_level, dining_duration, portion_level, transport_convenience, special_notes,
    recommendation_source_type, recommendation_source_user_id, recommendation_source_text,
    shared_meal_id, companions_json, dishes_json, note, photo_ids_json,
    created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    user_id = excluded.user_id,
    restaurant_id = excluded.restaurant_id,
    visited_at = excluded.visited_at,
    rating = excluded.rating,
    visibility = excluded.visibility,
    dining_mode = excluded.dining_mode,
    total_price = excluded.total_price,
    my_actual_spend = excluded.my_actual_spend,
    payment_mode = excluded.payment_mode,
    price_per_person = excluded.price_per_person,
    party_size = excluded.party_size,
    queue_duration = excluded.queue_duration,
    dining_occasion = excluded.dining_occasion,
    dining_occasion_text = excluded.dining_occasion_text,
    dining_occasions_json = excluded.dining_occasions_json,
    value_rating = excluded.value_rating,
    environment_rating = excluded.environment_rating,
    service_rating = excluded.service_rating,
    value_tags_json = excluded.value_tags_json,
    environment_tags_json = excluded.environment_tags_json,
    service_tags_json = excluded.service_tags_json,
    noise_level = excluded.noise_level,
    dining_duration = excluded.dining_duration,
    portion_level = excluded.portion_level,
    transport_convenience = excluded.transport_convenience,
    special_notes = excluded.special_notes,
    recommendation_source_type = excluded.recommendation_source_type,
    recommendation_source_user_id = excluded.recommendation_source_user_id,
    recommendation_source_text = excluded.recommendation_source_text,
    shared_meal_id = excluded.shared_meal_id,
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
  ) VALUES (?, ?, ?, ?, 'google-drive', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    user_id = excluded.user_id,
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

const USER_UPSERT = `
  INSERT INTO users (
    id, auth_provider, auth_subject, email, nickname, bio, city, avatar_image_data,
    avatar_photo_id, avatar_preset_id, membership_tier, map_sharing_enabled, map_visibility,
    created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    auth_provider = excluded.auth_provider,
    auth_subject = excluded.auth_subject,
    email = excluded.email,
    nickname = excluded.nickname,
    bio = excluded.bio,
    city = excluded.city,
    avatar_image_data = excluded.avatar_image_data,
    avatar_photo_id = excluded.avatar_photo_id,
    avatar_preset_id = excluded.avatar_preset_id,
    map_sharing_enabled = excluded.map_sharing_enabled,
    map_visibility = excluded.map_visibility,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > users.updated_at
`

const FRIENDSHIP_UPSERT = `
  INSERT INTO friendships (id, requester_id, addressee_id, status, created_at, updated_at)
  VALUES (?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    requester_id = excluded.requester_id,
    addressee_id = excluded.addressee_id,
    status = excluded.status,
    updated_at = excluded.updated_at
  WHERE excluded.updated_at > friendships.updated_at
`

const SHARED_MEAL_UPSERT = `
  INSERT INTO shared_meals (
    id, restaurant_id, created_by_user_id, occurred_at, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id,
    created_by_user_id = excluded.created_by_user_id,
    occurred_at = excluded.occurred_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > shared_meals.updated_at
`

const SHARED_MEAL_PARTICIPANT_UPSERT = `
  INSERT INTO shared_meal_participants (
    id, shared_meal_id, user_id, visit_id, status, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    visit_id = excluded.visit_id,
    status = excluded.status,
    updated_at = excluded.updated_at
  WHERE excluded.updated_at > shared_meal_participants.updated_at
`

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url)
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request)
    if (!isSameOriginRequest(request, url)) return json({ error: '不允许跨站访问同步 API。' }, 403)

    try {
      const viewer = await resolveViewer(request, env.DB)
      if (url.pathname === '/api/sync' && request.method === 'GET') return json(await readSnapshot(env.DB, viewer.id))
      if (url.pathname === '/api/sync' && request.method === 'POST') {
        const payload = await readPayload(request)
        const mapUserId = (id: string | null | undefined) => id === 'owner' ? viewer.id : id
        await upsertRestaurants(env.DB, payload.restaurants.map((item) => ({ ...item, userId: viewer.id })))
        await upsertVisits(env.DB, payload.visits.map((item) => ({
          ...item,
          userId: viewer.id,
          recommendationSourceUserId: mapUserId(item.recommendationSourceUserId) ?? null,
        })))
        await upsertPhotos(env.DB, payload.photos.map((item) => ({ ...item, userId: viewer.id })))
        await upsertUsers(env.DB, payload.users
          .filter((item) => item.id === 'owner' || item.id === viewer.id)
          .map((item) => ({ ...item, id: viewer.id, email: viewer.email ?? item.email, authProvider: viewer.authProvider, authSubject: viewer.authSubject })))
        const friendships = payload.friendships.map((item) => ({
          ...item,
          requesterId: mapUserId(item.requesterId) as string,
          addresseeId: mapUserId(item.addresseeId) as string,
        })).filter((item) => item.requesterId === viewer.id || item.addresseeId === viewer.id)
        await upsertFriendships(env.DB, friendships)
        const sharedMeals = payload.sharedMeals.map((item) => ({
          ...item,
          createdByUserId: mapUserId(item.createdByUserId) as string,
        })).filter((item) => item.createdByUserId === viewer.id)
        await upsertSharedMeals(env.DB, sharedMeals)
        await upsertSharedMealParticipants(env.DB, payload.sharedMealParticipants.map((item) => ({
          ...item,
          userId: mapUserId(item.userId) as string,
        })).filter((item) => item.userId === viewer.id || sharedMeals.some((meal) => meal.id === item.sharedMealId)))
        return json(await readSnapshot(env.DB, viewer.id))
      }
      if (url.pathname === '/api/community' && request.method === 'GET') return json(await readCommunity(env.DB, viewer.id))
      if (url.pathname.startsWith('/api/profiles/') && request.method === 'GET') {
        const profileId = decodeURIComponent(url.pathname.slice('/api/profiles/'.length))
        return json(await readProfile(env.DB, viewer.id, profileId))
      }
      if (url.pathname === '/api/users/search' && request.method === 'GET') return json(await searchUsers(env.DB, viewer.id, url.searchParams.get('q') ?? ''))
      if (url.pathname === '/api/friendships' && request.method === 'GET') return json(await readFriendships(env.DB, viewer.id))
      if (url.pathname === '/api/friendships' && request.method === 'POST') return json(await mutateFriendship(env.DB, viewer.id, request))
      if (url.pathname === '/api/shared-meals' && request.method === 'GET') return json(await readSharedMeals(env.DB, viewer.id))
      if (url.pathname === '/api/shared-meals' && request.method === 'POST') return json(await createSharedMeal(env.DB, viewer.id, request), 201)
      return json({ error: '没有找到这个 API。' }, 404)
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
  const users = Array.isArray(value.users) ? value.users : []
  const friendships = Array.isArray(value.friendships) ? value.friendships : []
  const sharedMeals = Array.isArray(value.sharedMeals) ? value.sharedMeals : []
  const sharedMealParticipants = Array.isArray(value.sharedMealParticipants) ? value.sharedMealParticipants : []
  if (!value.restaurants.every(isCloudRestaurant) || !value.visits.every(isCloudVisit) || !photos.every(isCloudPhoto) ||
    !users.every(isCloudUser) || !friendships.every(isCloudFriendship) || !sharedMeals.every(isCloudSharedMeal) ||
    !sharedMealParticipants.every(isCloudSharedMealParticipant)) {
    throw new RequestError('同步请求包含无法识别的餐厅或到访记录。', 400)
  }
  return { restaurants: value.restaurants, visits: value.visits, photos, users, friendships, sharedMeals, sharedMealParticipants }
}

async function upsertRestaurants(database: D1Database, restaurants: CloudRestaurant[]) {
  const statements = restaurants.map((restaurant) => database.prepare(RESTAURANT_UPSERT).bind(
    restaurant.id,
    restaurant.userId ?? 'owner',
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
    visit.userId ?? 'owner',
    visit.restaurantId,
    visit.visitedAt,
    visit.rating,
    visit.visibility ?? 'private',
    visit.diningMode ?? 'dine_in',
    visit.totalPrice,
    visit.myActualSpend ?? null,
    visit.paymentMode ?? null,
    visit.pricePerPerson,
    visit.partySize,
    visit.queueDuration,
    visit.diningOccasion ?? visit.diningOccasions?.[0] ?? null,
    visit.diningOccasionText ?? '',
    JSON.stringify(visit.diningOccasions ?? (visit.diningOccasion ? [visit.diningOccasion] : [])),
    visit.valueRating ?? null,
    visit.environmentRating ?? null,
    visit.serviceRating ?? null,
    JSON.stringify(visit.valueTags ?? []),
    JSON.stringify(visit.environmentTags ?? []),
    JSON.stringify(visit.serviceTags ?? []),
    visit.noiseLevel ?? null,
    visit.diningDuration ?? null,
    visit.portionLevel ?? null,
    visit.transportConvenience ?? null,
    visit.specialNotes ?? '',
    visit.recommendationSourceType ?? null,
    visit.recommendationSourceUserId ?? null,
    visit.recommendationSourceText ?? '',
    visit.sharedMealId ?? null,
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
    photo.userId ?? 'owner',
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

async function upsertUsers(database: D1Database, users: CloudUser[]) {
  const statements = await Promise.all(users.map(async (user) => {
    const existing = await database.prepare('SELECT membership_tier FROM users WHERE id = ? LIMIT 1').bind(user.id).first<{ membership_tier: MembershipTier }>()
    const membershipTier: MembershipTier = existing?.membership_tier === 'member' ? 'member' : 'free'
    return database.prepare(USER_UPSERT).bind(
      user.id,
      user.authProvider,
      user.authSubject,
      user.email,
      user.nickname,
      user.bio,
      user.city,
      membershipTier === 'member' ? user.avatarImageData : null,
      membershipTier === 'member' ? user.avatarPhotoId : null,
      user.avatarPresetId ?? 'polar-bear',
      membershipTier,
      user.mapSharingEnabled ? 1 : 0,
      user.mapVisibility ?? 'private',
      user.createdAt,
      user.updatedAt,
      user.deletedAt,
    )
  }))
  await runInChunks(database, statements)
}

async function upsertFriendships(database: D1Database, friendships: CloudFriendship[]) {
  const statements = friendships.map((item) => database.prepare(FRIENDSHIP_UPSERT).bind(
    item.id, item.requesterId, item.addresseeId, item.status, item.createdAt, item.updatedAt,
  ))
  await runInChunks(database, statements)
}

async function upsertSharedMeals(database: D1Database, meals: CloudSharedMeal[]) {
  const statements = meals.map((item) => database.prepare(SHARED_MEAL_UPSERT).bind(
    item.id, item.restaurantId, item.createdByUserId, item.occurredAt,
    item.createdAt, item.updatedAt, item.deletedAt,
  ))
  await runInChunks(database, statements)
}

async function upsertSharedMealParticipants(database: D1Database, participants: CloudSharedMealParticipant[]) {
  const statements = participants.map((item) => database.prepare(SHARED_MEAL_PARTICIPANT_UPSERT).bind(
    item.id, item.sharedMealId, item.userId, item.visitId, item.status, item.createdAt, item.updatedAt,
  ))
  await runInChunks(database, statements)
}

async function runInChunks(database: D1Database, statements: D1PreparedStatement[]) {
  for (let index = 0; index < statements.length; index += 50) {
    await database.batch(statements.slice(index, index + 50))
  }
}

async function readSnapshot(database: D1Database, userId = 'owner'): Promise<CloudSnapshot> {
  const [restaurantResult, visitResult, photoResult, userResult, friendshipResult, sharedMealResult, participantResult] = await database.batch([
    database.prepare('SELECT * FROM restaurants WHERE user_id = ? ORDER BY updated_at ASC').bind(userId),
    database.prepare('SELECT * FROM visits WHERE user_id = ? ORDER BY updated_at ASC').bind(userId),
    database.prepare('SELECT * FROM photos WHERE user_id = ? ORDER BY updated_at ASC').bind(userId),
    database.prepare(`SELECT * FROM users WHERE id = ? OR id IN (
      SELECT CASE WHEN requester_id = ? THEN addressee_id ELSE requester_id END
      FROM friendships WHERE requester_id = ? OR addressee_id = ?
    ) ORDER BY updated_at ASC`).bind(userId, userId, userId, userId),
    database.prepare('SELECT * FROM friendships WHERE requester_id = ? OR addressee_id = ? ORDER BY updated_at ASC').bind(userId, userId),
    database.prepare(`SELECT * FROM shared_meals WHERE created_by_user_id = ? OR id IN (
      SELECT shared_meal_id FROM shared_meal_participants WHERE user_id = ?
    ) ORDER BY updated_at ASC`).bind(userId, userId),
    database.prepare(`SELECT * FROM shared_meal_participants WHERE shared_meal_id IN (
      SELECT id FROM shared_meals WHERE created_by_user_id = ? OR id IN (
        SELECT shared_meal_id FROM shared_meal_participants WHERE user_id = ?
      )
    ) ORDER BY updated_at ASC`).bind(userId, userId),
  ])
  const clientUserId = (id: string) => id === userId ? 'owner' : id
  return {
    restaurants: (restaurantResult.results as unknown as RestaurantRow[]).map((row) => ({ ...rowToRestaurant(row), userId: 'owner' })),
    visits: (visitResult.results as unknown as VisitRow[]).map((row) => {
      const visit = rowToVisit(row)
      return { ...visit, userId: 'owner', recommendationSourceUserId: visit.recommendationSourceUserId ? clientUserId(visit.recommendationSourceUserId) : null }
    }),
    photos: (photoResult.results as unknown as PhotoRow[]).map((row) => ({ ...rowToPhoto(row), userId: 'owner' })),
    users: (userResult.results as unknown as UserRow[]).map((row) => ({ ...rowToUser(row), id: clientUserId(row.id) })),
    friendships: (friendshipResult.results as unknown as FriendshipRow[]).map((row) => {
      const item = rowToFriendship(row)
      return { ...item, requesterId: clientUserId(item.requesterId), addresseeId: clientUserId(item.addresseeId) }
    }),
    sharedMeals: (sharedMealResult.results as unknown as SharedMealRow[]).map((row) => {
      const item = rowToSharedMeal(row)
      return { ...item, createdByUserId: clientUserId(item.createdByUserId) }
    }),
    sharedMealParticipants: (participantResult.results as unknown as SharedMealParticipantRow[]).map((row) => {
      const item = rowToSharedMealParticipant(row)
      return { ...item, userId: clientUserId(item.userId) }
    }),
    serverTime: new Date().toISOString(),
  }
}

interface ViewerIdentity {
  id: string
  email: string | null
  authProvider: 'cloudflare-access' | 'local'
  authSubject: string | null
}

async function resolveViewer(request: Request, database: D1Database): Promise<ViewerIdentity> {
  const accessEmail = request.headers.get('Cf-Access-Authenticated-User-Email')?.trim().toLowerCase() ?? null
  const accessAssertion = request.headers.get('Cf-Access-Jwt-Assertion')
  if (!accessEmail || !accessAssertion) {
    return { id: 'owner', email: null, authProvider: 'local', authSubject: null }
  }
  const authSubject = `cloudflare-access:${accessEmail}`
  const existing = await database.prepare('SELECT * FROM users WHERE auth_provider = ? AND auth_subject = ? LIMIT 1')
    .bind('cloudflare-access', authSubject).first<UserRow>()
  if (existing) return { id: existing.id, email: accessEmail, authProvider: 'cloudflare-access', authSubject }

  const legacyOwner = await database.prepare('SELECT * FROM users WHERE id = ? LIMIT 1').bind('owner').first<UserRow>()
  if (legacyOwner && !legacyOwner.auth_subject) {
    await database.prepare(`UPDATE users SET auth_provider = 'cloudflare-access', auth_subject = ?, email = ?, updated_at = ? WHERE id = 'owner'`)
      .bind(authSubject, accessEmail, new Date().toISOString()).run()
    return { id: 'owner', email: accessEmail, authProvider: 'cloudflare-access', authSubject }
  }

  const id = `user-${await shortHash(accessEmail)}`
  const now = new Date().toISOString()
  await database.prepare(`INSERT OR IGNORE INTO users (
    id, auth_provider, auth_subject, email, nickname, bio, city, created_at, updated_at
  ) VALUES (?, 'cloudflare-access', ?, ?, ?, '', '', ?, ?)`)
    .bind(id, authSubject, accessEmail, accessEmail.split('@')[0], now, now).run()
  return { id, email: accessEmail, authProvider: 'cloudflare-access', authSubject }
}

async function shortHash(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].slice(0, 12).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function readCommunity(database: D1Database, viewerId: string) {
  const [visitsResult, restaurantsResult, usersResult, friendshipsResult] = await database.batch([
    database.prepare(`SELECT * FROM visits WHERE deleted_at IS NULL ORDER BY visited_at DESC LIMIT 160`),
    database.prepare(`SELECT * FROM restaurants WHERE deleted_at IS NULL AND id IN (
      SELECT restaurant_id FROM visits WHERE deleted_at IS NULL
    )`),
    database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL AND id IN (
      SELECT user_id FROM visits WHERE deleted_at IS NULL
    )`),
    database.prepare(`SELECT * FROM friendships WHERE status = 'accepted' AND (requester_id = ? OR addressee_id = ?)`)
      .bind(viewerId, viewerId),
  ])
  const restaurants = new Map((restaurantsResult.results as unknown as RestaurantRow[]).map((row) => [row.id, {
    id: row.id,
    name: row.name,
    address: row.address,
    city: row.city,
    latitude: row.latitude,
    longitude: row.longitude,
  }]))
  const users = new Map((usersResult.results as unknown as UserRow[]).map((row) => [row.id, publicUser(row)]))
  const userRows = new Map((usersResult.results as unknown as UserRow[]).map((row) => [row.id, row]))
  const followedUserIds = new Set((friendshipsResult.results as unknown as FriendshipRow[]).flatMap((row) => [row.requester_id, row.addressee_id]))
  return {
    items: (visitsResult.results as unknown as VisitRow[]).flatMap((row) => {
      const restaurant = restaurants.get(row.restaurant_id)
      const user = users.get(row.user_id)
      const userRow = userRows.get(row.user_id)
      const canSeeMap = row.user_id === viewerId || Boolean(userRow?.map_sharing_enabled) && (
        userRow?.map_visibility === 'public' ||
        userRow?.map_visibility === 'friends' && followedUserIds.has(row.user_id)
      )
      return restaurant && user && canSeeMap ? [{ visit: rowToVisit(row), restaurant, user }] : []
    }),
  }
}

async function searchUsers(database: D1Database, viewerId: string, query: string) {
  const keyword = query.trim()
  if (!keyword) return { users: [] }
  const result = await database.prepare(`SELECT * FROM users
    WHERE id != ? AND deleted_at IS NULL AND (nickname LIKE ? OR city LIKE ?)
    ORDER BY nickname LIMIT 20`).bind(viewerId, `%${keyword}%`, `%${keyword}%`).all<UserRow>()
  return { users: result.results.map(publicUser) }
}

async function readProfile(database: D1Database, viewerId: string, profileId: string) {
  const user = await database.prepare('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL').bind(profileId).first<UserRow>()
  if (!user) throw new RequestError('没有找到这个用户。', 404)
  const friendship = profileId === viewerId ? true : Boolean(await database.prepare(`SELECT id FROM friendships
    WHERE status = 'accepted' AND ((requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)) LIMIT 1`)
    .bind(viewerId, profileId, profileId, viewerId).first())
  const visibilitySql = profileId === viewerId
    ? '1 = 1'
    : !user.map_sharing_enabled || user.map_visibility === 'private'
      ? '1 = 0'
      : user.map_visibility === 'friends' && !friendship
        ? '1 = 0'
        : '1 = 1'
  const [visitsResult, restaurantsResult] = await database.batch([
    database.prepare(`SELECT * FROM visits WHERE user_id = ? AND deleted_at IS NULL AND ${visibilitySql} ORDER BY visited_at DESC`).bind(profileId),
    database.prepare(`SELECT * FROM restaurants WHERE id IN (
      SELECT restaurant_id FROM visits WHERE user_id = ? AND deleted_at IS NULL AND ${visibilitySql}
    ) AND deleted_at IS NULL`).bind(profileId),
  ])
  const restaurants = new Map((restaurantsResult.results as unknown as RestaurantRow[]).map((row) => [row.id, {
    id: row.id, name: row.name, address: row.address, city: row.city, latitude: row.latitude, longitude: row.longitude,
  }]))
  return {
    user: publicUser(user),
    items: (visitsResult.results as unknown as VisitRow[]).flatMap((row) => {
      const restaurant = restaurants.get(row.restaurant_id)
      return restaurant ? [{ visit: rowToVisit(row), restaurant }] : []
    }),
  }
}

async function readFriendships(database: D1Database, viewerId: string) {
  const result = await database.prepare('SELECT * FROM friendships WHERE requester_id = ? OR addressee_id = ? ORDER BY updated_at DESC')
    .bind(viewerId, viewerId).all<FriendshipRow>()
  return { friendships: result.results.map(rowToFriendship) }
}

async function mutateFriendship(database: D1Database, viewerId: string, request: Request) {
  const body = await readObjectBody(request)
  const now = new Date().toISOString()
  if (body.action === 'request' && typeof body.userId === 'string' && body.userId !== viewerId) {
    const friendship: CloudFriendship = {
      id: relationshipId(viewerId, body.userId),
      requesterId: viewerId,
      addresseeId: body.userId,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    }
    await upsertFriendships(database, [friendship])
    return friendship
  }
  if ((body.action === 'respond' || body.action === 'remove') && typeof body.friendshipId === 'string') {
    const existing = await database.prepare('SELECT * FROM friendships WHERE id = ? AND (requester_id = ? OR addressee_id = ?)')
      .bind(body.friendshipId, viewerId, viewerId).first<FriendshipRow>()
    if (!existing) throw new RequestError('没有找到这条好友关系。', 404)
    const requestedStatus = body.action === 'remove' ? 'removed' : body.status
    if (!['accepted', 'rejected', 'removed'].includes(String(requestedStatus))) throw new RequestError('好友状态不正确。', 400)
    const friendship = { ...rowToFriendship(existing), status: requestedStatus as CloudFriendship['status'], updatedAt: now }
    await upsertFriendships(database, [friendship])
    return friendship
  }
  throw new RequestError('好友操作格式不正确。', 400)
}

async function readSharedMeals(database: D1Database, viewerId: string) {
  const snapshot = await readSnapshot(database, viewerId)
  return { sharedMeals: snapshot.sharedMeals, participants: snapshot.sharedMealParticipants }
}

async function createSharedMeal(database: D1Database, viewerId: string, request: Request) {
  const body = await readObjectBody(request)
  if (body.action === 'respond' && typeof body.participantId === 'string') {
    const status = body.status
    if (status !== 'accepted' && status !== 'declined') throw new RequestError('饭局邀请状态不正确。', 400)
    const participant = await database.prepare('SELECT * FROM shared_meal_participants WHERE id = ? AND user_id = ?')
      .bind(body.participantId, viewerId).first<SharedMealParticipantRow>()
    if (!participant) throw new RequestError('没有找到这条饭局邀请。', 404)
    const now = new Date().toISOString()
    await database.prepare('UPDATE shared_meal_participants SET status = ?, visit_id = ?, updated_at = ? WHERE id = ?')
      .bind(status, typeof body.visitId === 'string' ? body.visitId : null, now, participant.id).run()
    if (status === 'accepted' && typeof body.visitId === 'string') {
      await database.prepare('UPDATE visits SET shared_meal_id = ?, updated_at = ? WHERE id = ? AND user_id = ?')
        .bind(participant.shared_meal_id, now, body.visitId, viewerId).run()
    }
    return { ...rowToSharedMealParticipant(participant), status, visitId: typeof body.visitId === 'string' ? body.visitId : null, updatedAt: now }
  }

  if (typeof body.restaurantId !== 'string' || typeof body.occurredAt !== 'string' || !Array.isArray(body.participantUserIds)) {
    throw new RequestError('共同饭局的数据不完整。', 400)
  }
  const restaurant = await database.prepare('SELECT id FROM restaurants WHERE id = ? AND user_id = ? AND deleted_at IS NULL')
    .bind(body.restaurantId, viewerId).first<{ id: string }>()
  if (!restaurant) throw new RequestError('没有找到这家餐厅。', 404)
  const participantIds = [...new Set(body.participantUserIds.filter((item): item is string => typeof item === 'string' && item !== viewerId))]
  const now = new Date().toISOString()
  const mealId = crypto.randomUUID()
  const meal: CloudSharedMeal = { id: mealId, restaurantId: body.restaurantId, createdByUserId: viewerId, occurredAt: body.occurredAt, createdAt: now, updatedAt: now, deletedAt: null }
  const participants: CloudSharedMealParticipant[] = [
    { id: `${mealId}:${viewerId}`, sharedMealId: mealId, userId: viewerId, visitId: typeof body.visitId === 'string' ? body.visitId : null, status: 'accepted', createdAt: now, updatedAt: now },
    ...participantIds.map((userId) => ({ id: `${mealId}:${userId}`, sharedMealId: mealId, userId, visitId: null, status: 'pending' as const, createdAt: now, updatedAt: now })),
  ]
  await upsertSharedMeals(database, [meal])
  await upsertSharedMealParticipants(database, participants)
  return { meal, participants }
}

function publicUser(row: UserRow) {
  return { id: row.id, nickname: row.nickname, bio: row.bio, city: row.city, avatarImageData: row.avatar_image_data, avatarPhotoId: row.avatar_photo_id, avatarPresetId: row.avatar_preset_id ?? 'polar-bear', membershipTier: row.membership_tier ?? 'free' }
}

async function readObjectBody(request: Request) {
  const value: unknown = await request.json().catch(() => null)
  if (!isRecord(value)) throw new RequestError('请求不是有效的 JSON 对象。', 400)
  return value
}

function relationshipId(first: string, second: string) {
  return `friendship:${[first, second].sort().join(':')}`
}

function rowToRestaurant(row: RestaurantRow): CloudRestaurant {
  return {
    id: row.id,
    userId: row.user_id,
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
    userId: row.user_id,
    restaurantId: row.restaurant_id,
    visitedAt: row.visited_at,
    rating: row.rating,
    visibility: row.visibility ?? 'private',
    diningMode: row.dining_mode ?? 'dine_in',
    totalPrice: row.total_price,
    myActualSpend: row.my_actual_spend,
    paymentMode: row.payment_mode,
    pricePerPerson: row.price_per_person,
    partySize: row.party_size,
    queueDuration: row.queue_duration,
    diningOccasions: (() => {
      const occasions = parseStringArray(row.dining_occasions_json) as DiningOccasion[]
      return occasions.length ? occasions : row.dining_occasion ? [row.dining_occasion] : []
    })(),
    diningOccasion: row.dining_occasion,
    diningOccasionText: row.dining_occasion_text ?? '',
    valueRating: row.value_rating,
    environmentRating: row.environment_rating,
    serviceRating: row.service_rating,
    valueTags: parseStringArray(row.value_tags_json),
    environmentTags: parseStringArray(row.environment_tags_json),
    serviceTags: parseStringArray(row.service_tags_json),
    noiseLevel: row.noise_level,
    diningDuration: row.dining_duration,
    portionLevel: row.portion_level,
    transportConvenience: row.transport_convenience,
    specialNotes: row.special_notes ?? '',
    recommendationSourceType: row.recommendation_source_type,
    recommendationSourceUserId: row.recommendation_source_user_id,
    recommendationSourceText: row.recommendation_source_text ?? '',
    sharedMealId: row.shared_meal_id,
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
    userId: row.user_id,
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

function rowToUser(row: UserRow): CloudUser {
  return {
    id: row.id,
    nickname: row.nickname,
    email: row.email,
    bio: row.bio,
    city: row.city,
    avatarImageData: row.avatar_image_data,
    avatarPhotoId: row.avatar_photo_id,
    avatarPresetId: row.avatar_preset_id ?? 'polar-bear',
    membershipTier: row.membership_tier ?? 'free',
    mapSharingEnabled: Boolean(row.map_sharing_enabled),
    mapVisibility: row.map_visibility ?? 'private',
    authProvider: row.auth_provider,
    authSubject: row.auth_subject,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
}

function rowToFriendship(row: FriendshipRow): CloudFriendship {
  return { id: row.id, requesterId: row.requester_id, addresseeId: row.addressee_id, status: row.status, createdAt: row.created_at, updatedAt: row.updated_at }
}

function rowToSharedMeal(row: SharedMealRow): CloudSharedMeal {
  return { id: row.id, restaurantId: row.restaurant_id, createdByUserId: row.created_by_user_id, occurredAt: row.occurred_at, createdAt: row.created_at, updatedAt: row.updated_at, deletedAt: row.deleted_at }
}

function rowToSharedMealParticipant(row: SharedMealParticipantRow): CloudSharedMealParticipant {
  return { id: row.id, sharedMealId: row.shared_meal_id, userId: row.user_id, visitId: row.visit_id, status: row.status, createdAt: row.created_at, updatedAt: row.updated_at }
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
    (value.kind === 'restaurant-marker' || value.kind === 'visit' || value.kind === 'dish' || value.kind === 'avatar') &&
    typeof value.mimeType === 'string' && typeof value.fileSize === 'number' &&
    typeof value.createdAt === 'string' && typeof value.updatedAt === 'string'
}

function isCloudUser(value: unknown): value is CloudUser {
  return isRecord(value) && typeof value.id === 'string' && typeof value.nickname === 'string' &&
    typeof value.bio === 'string' && typeof value.city === 'string' &&
    typeof value.createdAt === 'string' && typeof value.updatedAt === 'string' &&
    (value.avatarImageData === null || typeof value.avatarImageData === 'string')
}

function isCloudFriendship(value: unknown): value is CloudFriendship {
  return isRecord(value) && typeof value.id === 'string' && typeof value.requesterId === 'string' &&
    typeof value.addresseeId === 'string' && ['pending', 'accepted', 'rejected', 'removed'].includes(String(value.status)) &&
    typeof value.createdAt === 'string' && typeof value.updatedAt === 'string'
}

function isCloudSharedMeal(value: unknown): value is CloudSharedMeal {
  return isRecord(value) && typeof value.id === 'string' && typeof value.restaurantId === 'string' &&
    typeof value.createdByUserId === 'string' && typeof value.occurredAt === 'string' &&
    typeof value.createdAt === 'string' && typeof value.updatedAt === 'string'
}

function isCloudSharedMealParticipant(value: unknown): value is CloudSharedMealParticipant {
  return isRecord(value) && typeof value.id === 'string' && typeof value.sharedMealId === 'string' &&
    typeof value.userId === 'string' && ['pending', 'accepted', 'declined'].includes(String(value.status)) &&
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
