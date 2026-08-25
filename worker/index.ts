import type {
  CloudFriendship,
  CloudPhoto,
  CloudRestaurant,
  CloudRestaurantList,
  CloudRestaurantListItem,
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
  Photo,
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
import { readRestaurantSocialStats } from './restaurantStats'
import { calculateTasteSimilarities } from './tasteSimilarity'
import { rankTasteTags } from '../src/services/tasteProfileCore'

interface Env {
  DB: D1Database
  ASSETS: Fetcher
  ADMIN_EMAILS?: string
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
  phone: string | null
  opening_hours: string | null
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
  companion_ids_json: string
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
  storage_provider: Photo['storageProvider']
  storage_key: string | null
  thumbnail_storage_key: string | null
  thumbnail_file_size: number | null
  drive_account_id: string
  drive_file_id: string
  kind: PhotoKind
  file_name: string | null
  mime_type: string
  file_size: number
  width: number | null
  height: number | null
  visibility: Visibility
  sync_status: Photo['syncStatus']
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

interface MembershipEntitlementRow {
  id: string
  user_id: string
  source: 'app_store_monthly' | 'app_store_yearly' | 'app_store_lifetime' | 'admin_grant' | 'promo' | 'redeem_code'
  starts_at: string
  expires_at: string | null
  is_lifetime: number
  status: 'active' | 'revoked'
  note: string
  metadata_json: string
  created_by_user_id: string | null
  created_at: string
  updated_at: string
  revoked_at: string | null
  revoked_by_user_id: string | null
}

interface FriendshipRow {
  id: string
  requester_id: string
  addressee_id: string
  status: CloudFriendship['status']
  created_at: string
  updated_at: string
}

interface FollowRow {
  id: string
  follower_id: string
  followed_user_id: string
  created_at: string
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

interface DiningCompanionRow {
  id: string
  owner_user_id: string
  display_name: string
  linked_user_id: string | null
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface RestaurantListRow {
  id: string
  user_id: string
  title: string
  description: string
  visibility: Visibility
  is_ranked: number
  cover_mode: 'automatic' | 'custom'
  custom_cover_photo_id: string | null
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface RestaurantListItemRow {
  id: string
  list_id: string
  restaurant_id: string
  position: number
  note: string
  created_at: string
  updated_at: string
  deleted_at: string | null
}

interface CompanionLinkRequestRow {
  id: string
  companion_id: string
  companion_display_name: string
  requester_user_id: string
  target_user_id: string
  status: 'pending' | 'accepted' | 'rejected' | 'cancelled'
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
  restaurantLists: CloudRestaurantList[]
  restaurantListItems: CloudRestaurantListItem[]
}

const RESTAURANT_UPSERT = `
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, overall_rating, food_rating, environment_rating, service_rating,
    value_rating, tags_json, long_term_note, price_per_person, phone, opening_hours, marker_type,
    marker_photo_id, merchant_image_url, marker_emoji, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    phone = excluded.phone,
    opening_hours = excluded.opening_hours,
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
    shared_meal_id, companions_json, companion_ids_json, dishes_json, note, photo_ids_json,
    created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    companion_ids_json = excluded.companion_ids_json,
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
    drive_file_id, storage_key, thumbnail_storage_key, thumbnail_file_size,
    kind, file_name, mime_type, file_size, width, height, visibility, sync_status,
    created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    user_id = excluded.user_id,
    restaurant_id = excluded.restaurant_id,
    visit_id = excluded.visit_id,
    storage_provider = excluded.storage_provider,
    drive_account_id = excluded.drive_account_id,
    drive_file_id = excluded.drive_file_id,
    storage_key = excluded.storage_key,
    thumbnail_storage_key = excluded.thumbnail_storage_key,
    thumbnail_file_size = excluded.thumbnail_file_size,
    kind = excluded.kind,
    file_name = excluded.file_name,
    mime_type = excluded.mime_type,
    file_size = excluded.file_size,
    width = excluded.width,
    height = excluded.height,
    visibility = excluded.visibility,
    sync_status = excluded.sync_status,
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

const RESTAURANT_LIST_UPSERT = `
  INSERT INTO restaurant_lists (
    id, user_id, title, description, visibility, is_ranked, cover_mode,
    custom_cover_photo_id, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    title = excluded.title,
    description = excluded.description,
    visibility = excluded.visibility,
    is_ranked = excluded.is_ranked,
    cover_mode = excluded.cover_mode,
    custom_cover_photo_id = excluded.custom_cover_photo_id,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > restaurant_lists.updated_at
`

const RESTAURANT_LIST_ITEM_UPSERT = `
  INSERT INTO restaurant_list_items (
    id, list_id, restaurant_id, position, note, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    list_id = excluded.list_id,
    restaurant_id = excluded.restaurant_id,
    position = excluded.position,
    note = excluded.note,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > restaurant_list_items.updated_at
`

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url)
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request)
    if (!isSameOriginRequest(request, url)) return json({ error: '不允许跨站访问同步 API。' }, 403)

    try {
      const viewer = await resolveViewer(request, env.DB)
      if (url.pathname === '/api/sync' && request.method === 'GET') return json(await readSnapshot(env.DB, viewer.id, url.searchParams.get('since')))
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
        await upsertRestaurantLists(env.DB, payload.restaurantLists.map((item) => ({ ...item, userId: viewer.id })))
        await upsertRestaurantListItems(env.DB, payload.restaurantListItems)
        return json(await readSnapshot(env.DB, viewer.id))
      }
      if (url.pathname === '/api/community' && request.method === 'GET') return json(await readCommunity(env.DB, viewer.id, url.searchParams.get('mode') ?? 'for_you', url.searchParams.get('city') ?? '', url.searchParams.get('window') === '30' ? 30 : 7))
      if (url.pathname === '/api/recommendation-events' && request.method === 'POST') {
        return json(await createRecommendationEvent(env.DB, viewer.id, request), 201)
      }
      if (url.pathname === '/api/membership' && request.method === 'GET') {
        return json({ entitlement: await readEffectiveMembership(env.DB, viewer.id), isAdmin: isMembershipAdmin(request, env, viewer) })
      }
      if (url.pathname === '/api/admin/memberships' && request.method === 'GET') {
        requireMembershipAdmin(request, env, viewer)
        return json(await searchMembershipUsers(env.DB, url.searchParams.get('q') ?? ''))
      }
      if (url.pathname === '/api/admin/memberships' && request.method === 'POST') {
        requireMembershipAdmin(request, env, viewer)
        return json(await mutateMembership(env.DB, viewer.id, request))
      }
      if (url.pathname === '/api/follows' && request.method === 'GET') return json(await readFollows(env.DB, viewer.id))
      if (url.pathname === '/api/follows' && request.method === 'POST') return json(await mutateFollow(env.DB, viewer.id, request))
      const restaurantStatsMatch = url.pathname.match(/^\/api\/restaurants\/([^/]+)\/stats$/)
      if (restaurantStatsMatch && request.method === 'GET') {
        return json(await readRestaurantSocialStats(env.DB, viewer.id, decodeURIComponent(restaurantStatsMatch[1])))
      }
      const restaurantListMatch = url.pathname.match(/^\/api\/restaurant-lists\/([^/]+)$/)
      if (restaurantListMatch && request.method === 'GET') {
        return json(await readRestaurantList(env.DB, viewer.id, decodeURIComponent(restaurantListMatch[1])))
      }
      if (url.pathname.startsWith('/api/profiles/') && request.method === 'GET') {
        const profileId = decodeURIComponent(url.pathname.slice('/api/profiles/'.length))
        return json(await readProfile(env.DB, viewer.id, profileId))
      }
      if (url.pathname === '/api/users/search' && request.method === 'GET') return json(await searchUsers(env.DB, viewer.id, url.searchParams.get('q') ?? ''))
      if (url.pathname === '/api/companion-links' && request.method === 'GET') return json(await readCompanionLinks(env.DB, viewer.id))
      if (url.pathname === '/api/companion-links' && request.method === 'POST') return json(await mutateCompanionLink(env.DB, viewer.id, request))
      const companionHistoryMatch = url.pathname.match(/^\/api\/companion-links\/([^/]+)\/history$/)
      if (companionHistoryMatch && request.method === 'GET') return json(await readCompanionHistory(env.DB, viewer.id, decodeURIComponent(companionHistoryMatch[1])))
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
  const restaurantLists = Array.isArray(value.restaurantLists) ? value.restaurantLists : []
  const restaurantListItems = Array.isArray(value.restaurantListItems) ? value.restaurantListItems : []
  if (!value.restaurants.every(isCloudRestaurant) || !value.visits.every(isCloudVisit) || !photos.every(isCloudPhoto) ||
    !users.every(isCloudUser) || !friendships.every(isCloudFriendship) || !sharedMeals.every(isCloudSharedMeal) ||
    !sharedMealParticipants.every(isCloudSharedMealParticipant) || !restaurantLists.every(isCloudRestaurantList) ||
    !restaurantListItems.every(isCloudRestaurantListItem)) {
    throw new RequestError('同步请求包含无法识别的餐厅或到访记录。', 400)
  }
  return { restaurants: value.restaurants, visits: value.visits, photos, users, friendships, sharedMeals, sharedMealParticipants, restaurantLists, restaurantListItems }
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
    restaurant.phone ?? null,
    restaurant.openingHours ?? null,
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
    JSON.stringify(visit.companionIds ?? []),
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
    photo.storageProvider,
    photo.driveAccountId,
    photo.driveFileId,
    photo.storageKey,
    photo.thumbnailStorageKey,
    photo.thumbnailFileSize,
    photo.kind,
    photo.fileName,
    photo.mimeType,
    photo.fileSize,
    photo.width,
    photo.height,
    photo.visibility,
    photo.syncStatus,
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

async function upsertRestaurantLists(database: D1Database, lists: CloudRestaurantList[]) {
  const statements = lists.map((item) => database.prepare(RESTAURANT_LIST_UPSERT).bind(
    item.id, item.userId, item.title, item.description, item.visibility, item.isRanked ? 1 : 0,
    item.coverMode, item.customCoverPhotoId, item.createdAt, item.updatedAt, item.deletedAt,
  ))
  await runInChunks(database, statements)
}

async function upsertRestaurantListItems(database: D1Database, items: CloudRestaurantListItem[]) {
  const statements = items.map((item) => database.prepare(RESTAURANT_LIST_ITEM_UPSERT).bind(
    item.id, item.listId, item.restaurantId, item.position, item.note, item.createdAt, item.updatedAt, item.deletedAt,
  ))
  await runInChunks(database, statements)
}

async function runInChunks(database: D1Database, statements: D1PreparedStatement[]) {
  for (let index = 0; index < statements.length; index += 50) {
    await database.batch(statements.slice(index, index + 50))
  }
}

async function readSnapshot(database: D1Database, userId = 'owner', since: string | null = null): Promise<CloudSnapshot> {
  const updatedFilter = since ? ' AND updated_at > ?' : ''
  const bindSince = <T extends D1PreparedStatement>(statement: T) => since ? statement.bind(userId, since) : statement.bind(userId)
  const [restaurantResult, visitResult, photoResult, userResult, friendshipResult, sharedMealResult, participantResult, restaurantListResult, restaurantListItemResult] = await database.batch([
    bindSince(database.prepare(`SELECT * FROM restaurants WHERE user_id = ?${updatedFilter} ORDER BY updated_at ASC`)),
    bindSince(database.prepare(`SELECT * FROM visits WHERE user_id = ?${updatedFilter} ORDER BY updated_at ASC`)),
    bindSince(database.prepare(`SELECT * FROM photos WHERE user_id = ?${updatedFilter} ORDER BY updated_at ASC`)),
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
    bindSince(database.prepare(`SELECT * FROM restaurant_lists WHERE user_id = ?${updatedFilter} ORDER BY updated_at ASC`)),
    bindSince(database.prepare(`SELECT * FROM restaurant_list_items WHERE list_id IN (
      SELECT id FROM restaurant_lists WHERE user_id = ?
    )${updatedFilter} ORDER BY updated_at ASC`)),
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
    restaurantLists: (restaurantListResult.results as unknown as RestaurantListRow[]).map((row) => ({
      id: row.id, userId: 'owner', title: row.title, description: row.description, visibility: row.visibility,
      isRanked: Boolean(row.is_ranked), coverMode: row.cover_mode, customCoverPhotoId: row.custom_cover_photo_id,
      createdAt: row.created_at, updatedAt: row.updated_at, deletedAt: row.deleted_at,
    })),
    restaurantListItems: (restaurantListItemResult.results as unknown as RestaurantListItemRow[]).map((row) => ({
      id: row.id, listId: row.list_id, restaurantId: row.restaurant_id, position: row.position, note: row.note,
      createdAt: row.created_at, updatedAt: row.updated_at, deletedAt: row.deleted_at,
    })),
    serverTime: new Date().toISOString(),
  }
}

async function readRestaurantList(database: D1Database, viewerId: string, listId: string) {
  const list = await database.prepare('SELECT * FROM restaurant_lists WHERE id = ? AND deleted_at IS NULL LIMIT 1').bind(listId).first<RestaurantListRow>()
  if (!list) throw new Error('没有找到这份食单。')
  if (list.user_id !== viewerId && list.visibility === 'private') throw new Error('这份食单仅自己可见。')
  if (list.user_id !== viewerId && list.visibility === 'friends') {
    const friendship = await database.prepare(`SELECT id FROM friendships WHERE status = 'accepted' AND ((requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)) LIMIT 1`)
      .bind(viewerId, list.user_id, list.user_id, viewerId).first<{ id: string }>()
    if (!friendship) throw new Error('这份食单仅好友可见。')
  }
  const [itemResult, restaurantResult] = await database.batch([
    database.prepare('SELECT * FROM restaurant_list_items WHERE list_id = ? AND deleted_at IS NULL ORDER BY position ASC').bind(listId),
    database.prepare(`SELECT r.* FROM restaurants r JOIN restaurant_list_items i ON i.restaurant_id = r.id WHERE i.list_id = ? AND i.deleted_at IS NULL AND r.deleted_at IS NULL ORDER BY i.position ASC`).bind(listId),
  ])
  return {
    list: {
      id: list.id, userId: list.user_id, title: list.title, description: list.description, visibility: list.visibility,
      isRanked: Boolean(list.is_ranked), coverMode: list.cover_mode, customCoverPhotoId: list.custom_cover_photo_id,
      createdAt: list.created_at, updatedAt: list.updated_at, deletedAt: list.deleted_at,
    },
    items: (itemResult.results as unknown as RestaurantListItemRow[]).map((row) => ({
      id: row.id, listId: row.list_id, restaurantId: row.restaurant_id, position: row.position, note: row.note,
      createdAt: row.created_at, updatedAt: row.updated_at, deletedAt: row.deleted_at,
    })),
    restaurants: (restaurantResult.results as unknown as RestaurantRow[]).map(rowToRestaurant),
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
    await database.prepare(`UPDATE users SET auth_provider = 'cloudflare-access', auth_subject = ?, email = ? WHERE id = 'owner'`)
      .bind(authSubject, accessEmail).run()
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

function isMembershipAdmin(request: Request, env: Env, viewer: ViewerIdentity) {
  const hostname = new URL(request.url).hostname
  if ((hostname === 'localhost' || hostname === '127.0.0.1') && viewer.authProvider === 'local') return true
  if (!viewer.email) return false
  const allowed = (env.ADMIN_EMAILS ?? '').split(',').map((item) => item.trim().toLowerCase()).filter(Boolean)
  return allowed.includes(viewer.email.toLowerCase())
}

function requireMembershipAdmin(request: Request, env: Env, viewer: ViewerIdentity) {
  if (!isMembershipAdmin(request, env, viewer)) throw new RequestError('没有会员管理权限。', 403)
}

async function readEffectiveMembership(database: D1Database, userId: string) {
  const result = await database.prepare(`SELECT * FROM membership_entitlements
    WHERE user_id = ? ORDER BY created_at DESC`).bind(userId).all<MembershipEntitlementRow>()
  const entitlements = result.results.map(rowToMembershipEntitlement)
  const now = Date.now()
  const active = entitlements.filter((item) => item.status === 'active'
    && new Date(item.startsAt).getTime() <= now
    && (item.isLifetime || (item.expiresAt !== null && new Date(item.expiresAt).getTime() > now)))
  const primary = [...active].sort((left, right) => {
    if (left.isLifetime !== right.isLifetime) return left.isLifetime ? -1 : 1
    return (right.expiresAt ? new Date(right.expiresAt).getTime() : 0) - (left.expiresAt ? new Date(left.expiresAt).getTime() : 0)
  })[0]
  return {
    isPremium: Boolean(primary),
    source: primary?.source ?? null,
    startsAt: primary?.startsAt ?? null,
    expiresAt: primary?.expiresAt ?? null,
    isLifetime: primary?.isLifetime ?? false,
    entitlements,
  }
}

async function searchMembershipUsers(database: D1Database, query: string) {
  const keyword = query.trim()
  const result = keyword
    ? await database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL
        AND (nickname LIKE ? OR COALESCE(email, '') LIKE ? OR city LIKE ?)
        ORDER BY nickname LIMIT 30`).bind(`%${keyword}%`, `%${keyword}%`, `%${keyword}%`).all<UserRow>()
    : await database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT 30`).all<UserRow>()
  return {
    users: await Promise.all(result.results.map(async (user) => ({
      id: user.id,
      nickname: user.nickname,
      email: user.email,
      city: user.city,
      entitlement: await readEffectiveMembership(database, user.id),
    }))),
  }
}

async function mutateMembership(database: D1Database, actorUserId: string, request: Request) {
  const body = await request.json().catch(() => null) as Record<string, unknown> | null
  if (!body || typeof body.action !== 'string') throw new RequestError('会员操作格式不正确。', 400)
  const now = new Date()
  const nowIso = now.toISOString()

  if (body.action === 'grant') {
    if (typeof body.userId !== 'string') throw new RequestError('请选择要赠送会员的用户。', 400)
    const exists = await database.prepare('SELECT id FROM users WHERE id = ? AND deleted_at IS NULL').bind(body.userId).first()
    if (!exists) throw new RequestError('没有找到这个用户。', 404)
    const duration = typeof body.duration === 'string' ? body.duration : '1m'
    const expiresAt = membershipExpiry(now, duration, typeof body.expiresAt === 'string' ? body.expiresAt : null)
    const isLifetime = duration === 'lifetime'
    const note = typeof body.note === 'string' ? body.note.slice(0, 160) : ''
    const id = `membership:${crypto.randomUUID()}`
    await database.prepare(`INSERT INTO membership_entitlements (
      id, user_id, source, starts_at, expires_at, is_lifetime, status, note, metadata_json,
      created_by_user_id, created_at, updated_at
    ) VALUES (?, ?, 'admin_grant', ?, ?, ?, 'active', ?, '{}', ?, ?, ?)`)
      .bind(id, body.userId, nowIso, expiresAt, isLifetime ? 1 : 0, note, actorUserId, nowIso, nowIso).run()
    const after = await database.prepare('SELECT * FROM membership_entitlements WHERE id = ?').bind(id).first<MembershipEntitlementRow>()
    await writeMembershipAudit(database, actorUserId, body.userId, 'grant', id, null, after, note)
    await refreshMembershipTier(database, body.userId)
    return { entitlement: await readEffectiveMembership(database, body.userId) }
  }

  if (body.action === 'update') {
    if (typeof body.entitlementId !== 'string') throw new RequestError('会员权益无效。', 400)
    const before = await database.prepare(`SELECT * FROM membership_entitlements WHERE id = ? AND source = 'admin_grant' AND status = 'active'`)
      .bind(body.entitlementId).first<MembershipEntitlementRow>()
    if (!before) throw new RequestError('只能修改仍然有效的管理员赠送。', 404)
    const isLifetime = body.isLifetime === true
    const expiresAt = isLifetime ? null : typeof body.expiresAt === 'string' && Number.isFinite(new Date(body.expiresAt).getTime()) ? new Date(body.expiresAt).toISOString() : before.expires_at
    const note = typeof body.note === 'string' ? body.note.slice(0, 160) : before.note
    await database.prepare(`UPDATE membership_entitlements SET expires_at = ?, is_lifetime = ?, note = ?, updated_at = ? WHERE id = ?`)
      .bind(expiresAt, isLifetime ? 1 : 0, note, nowIso, before.id).run()
    const after = await database.prepare('SELECT * FROM membership_entitlements WHERE id = ?').bind(before.id).first<MembershipEntitlementRow>()
    await writeMembershipAudit(database, actorUserId, before.user_id, 'update', before.id, before, after, note)
    await refreshMembershipTier(database, before.user_id)
    return { entitlement: await readEffectiveMembership(database, before.user_id) }
  }

  if (body.action === 'revoke') {
    if (typeof body.entitlementId !== 'string') throw new RequestError('会员权益无效。', 400)
    const before = await database.prepare(`SELECT * FROM membership_entitlements WHERE id = ? AND source = 'admin_grant' AND status = 'active'`)
      .bind(body.entitlementId).first<MembershipEntitlementRow>()
    if (!before) throw new RequestError('只能撤销管理员赠送，真实购买不会受影响。', 404)
    const reason = typeof body.reason === 'string' ? body.reason.slice(0, 160) : ''
    await database.prepare(`UPDATE membership_entitlements SET status = 'revoked', revoked_at = ?, revoked_by_user_id = ?, updated_at = ? WHERE id = ?`)
      .bind(nowIso, actorUserId, nowIso, before.id).run()
    const after = await database.prepare('SELECT * FROM membership_entitlements WHERE id = ?').bind(before.id).first<MembershipEntitlementRow>()
    await writeMembershipAudit(database, actorUserId, before.user_id, 'revoke', before.id, before, after, reason)
    await refreshMembershipTier(database, before.user_id)
    return { entitlement: await readEffectiveMembership(database, before.user_id) }
  }

  throw new RequestError('不支持这个会员操作。', 400)
}

function membershipExpiry(now: Date, duration: string, custom: string | null) {
  if (duration === 'lifetime') return null
  if (duration === 'custom') {
    const timestamp = custom ? new Date(custom).getTime() : NaN
    if (!Number.isFinite(timestamp) || timestamp <= now.getTime()) throw new RequestError('自定义到期时间必须晚于现在。', 400)
    return new Date(timestamp).toISOString()
  }
  const months = ({ '1m': 1, '3m': 3, '6m': 6, '1y': 12 } as Record<string, number>)[duration]
  if (!months) throw new RequestError('会员赠送期限无效。', 400)
  const expires = new Date(now)
  expires.setUTCMonth(expires.getUTCMonth() + months)
  return expires.toISOString()
}

async function refreshMembershipTier(database: D1Database, userId: string) {
  const effective = await readEffectiveMembership(database, userId)
  await database.prepare('UPDATE users SET membership_tier = ?, updated_at = ? WHERE id = ?')
    .bind(effective.isPremium ? 'member' : 'free', new Date().toISOString(), userId).run()
}

async function writeMembershipAudit(
  database: D1Database,
  actorUserId: string,
  targetUserId: string,
  action: string,
  entitlementId: string,
  before: MembershipEntitlementRow | null,
  after: MembershipEntitlementRow | null | undefined,
  reason: string,
) {
  await database.prepare(`INSERT INTO membership_audit_log (
    id, actor_user_id, target_user_id, action, entitlement_id, before_json, after_json, reason, created_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(`membership-audit:${crypto.randomUUID()}`, actorUserId, targetUserId, action, entitlementId,
      before ? JSON.stringify(before) : null, after ? JSON.stringify(after) : null, reason, new Date().toISOString()).run()
}

function rowToMembershipEntitlement(row: MembershipEntitlementRow) {
  return {
    id: row.id,
    userId: row.user_id,
    source: row.source,
    startsAt: row.starts_at,
    expiresAt: row.expires_at,
    isLifetime: Boolean(row.is_lifetime),
    status: row.status,
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    revokedAt: row.revoked_at,
  }
}

async function shortHash(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].slice(0, 12).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function readCommunity(database: D1Database, viewerId: string, requestedMode: string, requestedCity: string, trendWindow: 7 | 30) {
  const mode = ['following', 'for_you', 'similar', 'latest', 'trending'].includes(requestedMode) ? requestedMode : 'for_you'
  const [visitsResult, restaurantsResult, usersResult, followsResult, wantsResult] = await database.batch([
    database.prepare(`SELECT * FROM visits WHERE deleted_at IS NULL AND (user_id = ? OR visibility = 'public') ORDER BY visited_at DESC LIMIT 5000`).bind(viewerId),
    database.prepare(`SELECT * FROM restaurants WHERE deleted_at IS NULL AND id IN (
      SELECT restaurant_id FROM visits WHERE deleted_at IS NULL
    )`),
    database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL AND id IN (
      SELECT user_id FROM visits WHERE deleted_at IS NULL
    )`),
    database.prepare(`SELECT * FROM follows WHERE follower_id = ?`).bind(viewerId),
    database.prepare(`SELECT restaurant_id, created_at FROM want_to_go WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 3000`),
  ])
  const restaurantRows = restaurantsResult.results as unknown as RestaurantRow[]
  const restaurants = new Map(restaurantRows.map((row) => [row.id, row]))
  const users = new Map((usersResult.results as unknown as UserRow[]).map((row) => [row.id, publicUser(row)]))
  const userRows = new Map((usersResult.results as unknown as UserRow[]).map((row) => [row.id, row]))
  const followedUserIds = new Set((followsResult.results as unknown as FollowRow[]).map((row) => row.followed_user_id))
  const visitRows = visitsResult.results as unknown as VisitRow[]
  const signals = visitRows.flatMap((row) => {
    const restaurant = restaurants.get(row.restaurant_id)
    return row.rating && restaurant ? [{ userId: row.user_id, poiId: restaurant.amap_poi_id, ratingOutOfTen: Number(row.rating) * 2, tags: parseStringArray(restaurant.tags_json) }] : []
  })
  const similarityByUser = new Map(calculateTasteSimilarities(signals, viewerId).map((item) => [item.userId, item.similarity]))
  const viewerVisitedRestaurantIds = new Set(visitRows.filter((row) => row.user_id === viewerId).map((row) => row.restaurant_id))
  const defaultCity = requestedCity.trim() || userRows.get(viewerId)?.city || '杭州市'
  const now = Date.now()
  const candidates = visitRows.flatMap((row) => {
    if (row.user_id === viewerId || row.visibility !== 'public') return []
    const restaurant = restaurants.get(row.restaurant_id)
    const user = users.get(row.user_id)
    const userRow = userRows.get(row.user_id)
    if (!restaurant || !user || !userRow?.map_sharing_enabled || userRow.map_visibility !== 'public') return []
    return [{
      row,
      restaurant,
      user,
      similarity: similarityByUser.get(row.user_id) ?? null,
      recommendationReason: null as string | null,
    }]
  })
  let selected = candidates
  if (mode === 'following') selected = candidates.filter((item) => followedUserIds.has(item.row.user_id))
  if (mode === 'for_you') selected = personalizedCandidates(candidates.filter((item) => !viewerVisitedRestaurantIds.has(item.restaurant.id)), visitRows.flatMap((row) => {
    const restaurant = restaurants.get(row.restaurant_id)
    return row.user_id === viewerId && row.rating && restaurant ? [{ restaurant, ratingOutOfTen: Number(row.rating) * 2 }] : []
  }), defaultCity)
  if (mode === 'similar') selected = uniqueCandidatesByRestaurant(candidates
    .filter((item) => item.similarity !== null && item.similarity >= 0.58 && (!requestedCity || item.restaurant.city === defaultCity))
    .sort((a, b) => recommendationRank(b, now, defaultCity) - recommendationRank(a, now, defaultCity)))
  if (mode === 'similar' && !selected.length) selected = personalizedCandidates(
    candidates.filter((item) => !viewerVisitedRestaurantIds.has(item.restaurant.id)),
    visitRows.flatMap((row) => {
      const restaurant = restaurants.get(row.restaurant_id)
      return row.user_id === viewerId && row.rating && restaurant ? [{ restaurant, ratingOutOfTen: Number(row.rating) * 2 }] : []
    }),
    defaultCity,
  ).map((item) => ({ ...item, similarity: null, recommendationReason: '同味样本不足，先按你的个人口味匹配' }))
  if (mode === 'latest' && requestedCity) selected = candidates.filter((item) => item.restaurant.city === defaultCity)
  if (mode === 'trending') selected = trendingCandidates(candidates, wantsResult.results as Array<{ restaurant_id: string; created_at: string }>, defaultCity, now, trendWindow)
  return {
    mode, city: defaultCity,
    items: selected.slice(0, 160).map(({ row, restaurant, user, similarity, recommendationReason }, index) => ({
      visit: rowToVisit(row),
      restaurant: { id: restaurant.id, amapPoiId: restaurant.amap_poi_id, name: restaurant.name, address: restaurant.address, city: restaurant.city, latitude: restaurant.latitude, longitude: restaurant.longitude, merchantImageUrl: restaurant.merchant_image_url },
      user, similarity: similarity === null ? null : Math.round(similarity * 100),
      recommendationReason: recommendationReason ?? null,
      recommendationType: mode === 'similar' ? 'similar_taste' : mode === 'trending' ? 'trending' : mode === 'for_you' ? 'for_you' : null,
      recommendationRank: index + 1,
      recommendationConfidence: recommendationConfidence(mode, similarity, visitRows.filter((visit) => visit.user_id === viewerId && visit.rating).length),
      reasonCodes: recommendationReasonCodes(mode, similarity, recommendationReason),
      surface: 'discover',
    })),
  }
}

function recommendationConfidence(mode: string, similarity: number | null, viewerRatedCount: number) {
  if (mode === 'for_you') return viewerRatedCount >= 12 ? 'high' : viewerRatedCount >= 4 ? 'medium' : 'low'
  if (mode === 'similar') return similarity !== null && similarity >= .78 ? 'high' : similarity !== null ? 'medium' : 'low'
  if (mode === 'trending') return 'medium'
  return 'low'
}

function recommendationReasonCodes(mode: string, similarity: number | null, reason: string | null) {
  if (mode === 'trending') return ['TRENDING']
  if (mode === 'similar') return similarity !== null ? ['SIMILAR_USERS'] : ['TASTE_MATCH', 'COLD_START']
  if (mode === 'for_you') return reason?.includes('初步') ? ['QUALITY', 'COLD_START'] : ['TASTE_MATCH', 'QUALITY']
  return []
}

function uniqueCandidatesByRestaurant<T extends { restaurant: RestaurantRow }>(items: T[]) {
  const seen = new Set<string>()
  return items.filter((item) => {
    if (seen.has(item.restaurant.id)) return false
    seen.add(item.restaurant.id)
    return true
  })
}

function personalizedCandidates(candidates: Array<{ row: VisitRow; restaurant: RestaurantRow; user: ReturnType<typeof publicUser>; similarity: number | null; recommendationReason: string | null }>, viewerHistory: Array<{ restaurant: RestaurantRow; ratingOutOfTen: number }>, city: string) {
  if (viewerHistory.length < 3) {
    return uniqueCandidatesByRestaurant(candidates.filter((item) => item.restaurant.city === city)
      .sort((left, right) => Number(right.row.rating ?? 0) - Number(left.row.rating ?? 0) || right.row.visited_at.localeCompare(left.row.visited_at)))
      .slice(0, 60)
      .map((item) => ({ ...item, recommendationReason: '基于当前城市公开高分记录的初步推荐' }))
  }
  const rankedTags = rankTasteTags(viewerHistory.map((signal) => ({ tags: parseStringArray(signal.restaurant.tags_json), restaurantKey: signal.restaurant.amap_poi_id, ratingOutOfTen: signal.ratingOutOfTen })))
  const tagValues = new Map(rankedTags.map((item) => [item.tag.trim().toLocaleLowerCase(), item]))
  const byRestaurant = new Map<string, { item: typeof candidates[number]; score: number }>()
  candidates.filter((item) => item.restaurant.city === city).forEach((item) => {
    const tags = parseStringArray(item.restaurant.tags_json)
    const matched = tags.flatMap((rawTag) => {
      const value = tagValues.get(rawTag.trim().toLocaleLowerCase())
      return value ? [{ tag: rawTag, score: value.score, count: value.visits }] : []
    }).sort((a, b) => b.score - a.score || b.count - a.count)
    if (!matched.length) return
    const best = matched[0]
    const nearest = viewerHistory.filter((history) => history.ratingOutOfTen >= 8).map((history) => {
      const historyTags = parseStringArray(history.restaurant.tags_json)
      const intersection = tags.filter((tag) => historyTags.some((historyTag) => historyTag.trim().toLocaleLowerCase() === tag.trim().toLocaleLowerCase())).length
      const union = new Set([...tags, ...historyTags].map((tag) => tag.trim().toLocaleLowerCase())).size
      const tagSimilarity = union ? intersection / union : 0
      const candidateRating = Math.max(0, Math.min(10, Number(item.row.rating ?? 0) * 2))
      const ratingAffinity = Math.max(0, 1 - Math.abs(history.ratingOutOfTen - candidateRating) / 10)
      const similarity = Math.min(0.97, 0.55 + tagSimilarity * 0.27 + ratingAffinity * 0.15)
      return { history, similarity, tagSimilarity }
    }).sort((a, b) => b.tagSimilarity - a.tagSimilarity || b.history.ratingOutOfTen - a.history.ratingOutOfTen)[0]
    if (!nearest) return
    const similarityPercent = Math.round(nearest.similarity * 100)
    const score = best.score * 8 + Math.min(best.count, 8) + Number(item.row.rating ?? 0) * 3 + similarityPercent
    const referenceName = nearest.history.restaurant.name.replace(/[（(][^）)]*[）)]/g, '').trim()
    const current = byRestaurant.get(item.restaurant.id)
    if (!current || score > current.score) byRestaurant.set(item.restaurant.id, { item: { ...item, similarity: nearest.similarity, recommendationReason: `与「${referenceName}」相似 ${similarityPercent}%` }, score })
  })
  return [...byRestaurant.values()].sort((a, b) => b.score - a.score).map((entry) => entry.item)
}

function recommendationRank(item: { row: VisitRow; restaurant: RestaurantRow; similarity: number | null }, now: number, city: string) {
  const recency = Math.max(0, 1 - (now - Date.parse(item.row.visited_at)) / (120 * 86400000))
  return (item.similarity ?? 0) * 60 + Number(item.row.rating ?? 0) * 6 + recency * 12 + (item.restaurant.city === city ? 10 : 0)
}

function trendingCandidates(candidates: Array<{ row: VisitRow; restaurant: RestaurantRow; user: ReturnType<typeof publicUser>; similarity: number | null; recommendationReason: string | null }>, wants: Array<{ restaurant_id: string; created_at: string }>, city: string, now: number, trendWindow: 7 | 30) {
  const grouped = new Map<string, typeof candidates>()
  candidates.filter((item) => item.restaurant.city === city).forEach((item) => grouped.set(item.restaurant.id, [...(grouped.get(item.restaurant.id) ?? []), item]))
  return [...grouped.values()].map((items) => {
    const recent7 = new Set(items.filter((item) => now - Date.parse(item.row.visited_at) <= 7 * 86400000).map((item) => item.row.user_id)).size
    const recent30 = new Set(items.filter((item) => now - Date.parse(item.row.visited_at) <= 30 * 86400000).map((item) => item.row.user_id)).size
    const previous30 = new Set(items.filter((item) => { const age = now - Date.parse(item.row.visited_at); return age > 30 * 86400000 && age <= 60 * 86400000 }).map((item) => item.row.user_id)).size
    const recentWants = wants.filter((want) => want.restaurant_id === items[0].restaurant.id && now - Date.parse(want.created_at) <= 30 * 86400000).length
    const highScores = items.filter((item) => now - Date.parse(item.row.visited_at) <= 30 * 86400000 && Number(item.row.rating ?? 0) >= 4).length
    const recentUsers = trendWindow === 7 ? recent7 : recent30
    const score = recentUsers * (trendWindow === 7 ? 3 : 1.5) + recentWants * 1.2 + highScores * 0.7 - previous30 * 0.6
    const latest = [...items].sort((a, b) => b.row.visited_at.localeCompare(a.row.visited_at))[0]
    const description = recentUsers >= 4 ? `近 ${trendWindow} 天有 ${recentUsers} 位用户到访` : `近 ${trendWindow} 天有新的公开到访，属于近期活跃餐厅`
    return { item: { ...latest, recommendationReason: description }, score }
  }).sort((a, b) => b.score - a.score).map((entry) => entry.item)
}

async function createRecommendationEvent(database: D1Database, viewerId: string, request: Request) {
  const body = await readObjectBody(request)
  const eventNames = new Set(['impression', 'restaurantDetailOpen', 'wantToGoAdded', 'wheelCandidateAdded', 'navigationStarted', 'visitCreated', 'visitRating', 'repeatVisit', 'hideRecommendation'])
  const recommendationTypes = new Set(['for_you', 'similar_taste', 'trending'])
  const surfaces = new Set(['map', 'discover'])
  if (typeof body.id !== 'string' || typeof body.restaurantId !== 'string' || typeof body.eventName !== 'string' || !eventNames.has(body.eventName) ||
    typeof body.recommendationType !== 'string' || !recommendationTypes.has(body.recommendationType) || typeof body.surface !== 'string' || !surfaces.has(body.surface)) {
    throw new RequestError('推荐反馈数据格式不正确。', 400)
  }
  const createdAt = typeof body.createdAt === 'string' ? body.createdAt : new Date().toISOString()
  const reasonCodes = Array.isArray(body.reasonCodes) ? body.reasonCodes.filter((value): value is string => typeof value === 'string').slice(0, 12) : []
  await database.prepare(`INSERT OR IGNORE INTO recommendation_events
    (id, user_id, event_name, recommendation_type, surface, restaurant_id, rank, score, reason_codes_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(body.id, viewerId, body.eventName, body.recommendationType, body.surface, body.restaurantId,
      typeof body.rank === 'number' ? body.rank : null, typeof body.score === 'number' ? body.score : null, JSON.stringify(reasonCodes), createdAt).run()
  return { id: body.id, accepted: true }
}

async function readFollows(database: D1Database, viewerId: string) {
  const result = await database.prepare('SELECT * FROM follows WHERE follower_id = ? OR followed_user_id = ? ORDER BY created_at DESC').bind(viewerId, viewerId).all<FollowRow>()
  const clientUserId = (id: string) => id === viewerId ? 'owner' : id
  return { follows: result.results.map((row) => ({ id: row.id, followerId: clientUserId(row.follower_id), followedUserId: clientUserId(row.followed_user_id), createdAt: row.created_at })) }
}

async function mutateFollow(database: D1Database, viewerId: string, request: Request) {
  const body = await readObjectBody(request)
  if (typeof body.userId !== 'string' || body.userId === viewerId) throw new RequestError('关注用户无效。', 400)
  const id = `follow:${viewerId}:${body.userId}`
  if (body.action === 'remove') {
    await database.prepare('DELETE FROM follows WHERE follower_id = ? AND followed_user_id = ?').bind(viewerId, body.userId).run()
    return { removed: true }
  }
  if (body.action !== 'add') throw new RequestError('关注操作无效。', 400)
  await database.prepare('INSERT OR IGNORE INTO follows (id, follower_id, followed_user_id, created_at) VALUES (?, ?, ?, ?)').bind(id, viewerId, body.userId, new Date().toISOString()).run()
  return { id, followerId: viewerId, followedUserId: body.userId }
}

async function searchUsers(database: D1Database, viewerId: string, query: string) {
  const keyword = query.trim()
  if (!keyword) {
    const suggestions = await database.prepare(`SELECT * FROM users
      WHERE id != ? AND deleted_at IS NULL
      ORDER BY is_test_user DESC, nickname LIMIT 100`).bind(viewerId).all<UserRow>()
    return { users: suggestions.results.map(publicUser) }
  }
  const result = await database.prepare(`SELECT * FROM users
    WHERE id != ? AND deleted_at IS NULL AND (nickname LIKE ? OR city LIKE ?)
    ORDER BY nickname LIMIT 20`).bind(viewerId, `%${keyword}%`, `%${keyword}%`).all<UserRow>()
  return { users: result.results.map(publicUser) }
}

async function readCompanionLinks(database: D1Database, viewerId: string) {
  const [companionsResult, requestsResult] = await database.batch([
    database.prepare(`SELECT * FROM dining_companions WHERE deleted_at IS NULL AND (owner_user_id = ? OR linked_user_id = ?) ORDER BY updated_at DESC`).bind(viewerId, viewerId),
    database.prepare(`SELECT * FROM companion_link_requests WHERE requester_user_id = ? OR target_user_id = ? ORDER BY updated_at DESC`).bind(viewerId, viewerId),
  ])
  const requests = requestsResult.results as unknown as CompanionLinkRequestRow[]
  const userIds = [...new Set(requests.flatMap((item) => [item.requester_user_id, item.target_user_id]))]
  const users = userIds.length
    ? await database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL AND id IN (${userIds.map(() => '?').join(',')})`).bind(...userIds).all<UserRow>()
    : { results: [] as UserRow[] }
  return {
    companions: (companionsResult.results as unknown as DiningCompanionRow[]).map(rowToDiningCompanion),
    requests: await Promise.all(requests.map((row) => companionLinkRequestWithCounts(database, row))),
    users: users.results.map(publicUser),
  }
}

async function mutateCompanionLink(database: D1Database, viewerId: string, request: Request) {
  const body = await readObjectBody(request)
  const now = new Date().toISOString()
  if (body.action === 'request' && typeof body.companionId === 'string' && typeof body.displayName === 'string' && typeof body.targetUserId === 'string') {
    if (body.targetUserId === viewerId) throw new RequestError('不能关联到自己的账号。', 400)
    const target = await database.prepare('SELECT id FROM users WHERE id = ? AND deleted_at IS NULL').bind(body.targetUserId).first()
    if (!target) throw new RequestError('没有找到要关联的用户。', 404)
    const displayName = body.displayName.trim()
    if (!displayName) throw new RequestError('饭搭子名称不能为空。', 400)
    await database.prepare(`INSERT INTO dining_companions (id, owner_user_id, display_name, linked_user_id, created_at, updated_at, deleted_at)
      VALUES (?, ?, ?, NULL, ?, ?, NULL)
      ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, updated_at = excluded.updated_at, deleted_at = NULL
      WHERE dining_companions.owner_user_id = ?`).bind(body.companionId, viewerId, displayName, now, now, viewerId).run()
    const id = `companion-link:${viewerId}:${body.companionId}:${body.targetUserId}`
    await database.prepare(`INSERT INTO companion_link_requests (id, companion_id, companion_display_name, requester_user_id, target_user_id, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)
      ON CONFLICT(id) DO UPDATE SET status = 'pending', companion_display_name = excluded.companion_display_name, updated_at = excluded.updated_at`)
      .bind(id, body.companionId, displayName, viewerId, body.targetUserId, now, now).run()
    const row = await database.prepare('SELECT * FROM companion_link_requests WHERE id = ?').bind(id).first<CompanionLinkRequestRow>()
    return companionLinkRequestWithCounts(database, row as CompanionLinkRequestRow)
  }
  if (body.action === 'respond' && typeof body.requestId === 'string' && (body.status === 'accepted' || body.status === 'rejected')) {
    const row = await database.prepare('SELECT * FROM companion_link_requests WHERE id = ? AND target_user_id = ? AND status = \'pending\'')
      .bind(body.requestId, viewerId).first<CompanionLinkRequestRow>()
    if (!row) throw new RequestError('没有找到待处理的关联请求。', 404)
    await database.prepare('UPDATE companion_link_requests SET status = ?, updated_at = ? WHERE id = ?').bind(body.status, now, row.id).run()
    if (body.status === 'accepted') await database.prepare('UPDATE dining_companions SET linked_user_id = ?, updated_at = ? WHERE id = ? AND owner_user_id = ?').bind(viewerId, now, row.companion_id, row.requester_user_id).run()
    return companionLinkRequestWithCounts(database, { ...row, status: body.status, updated_at: now })
  }
  if (body.action === 'cancel' && typeof body.requestId === 'string') {
    const row = await database.prepare('SELECT * FROM companion_link_requests WHERE id = ? AND requester_user_id = ?').bind(body.requestId, viewerId).first<CompanionLinkRequestRow>()
    if (!row) throw new RequestError('没有找到这条关联请求。', 404)
    await database.prepare("UPDATE companion_link_requests SET status = 'cancelled', updated_at = ? WHERE id = ?").bind(now, row.id).run()
    return companionLinkRequestWithCounts(database, { ...row, status: 'cancelled', updated_at: now })
  }
  if (body.action === 'unlink' && typeof body.companionId === 'string') {
    const companion = await database.prepare('SELECT * FROM dining_companions WHERE id = ? AND (owner_user_id = ? OR linked_user_id = ?)').bind(body.companionId, viewerId, viewerId).first<DiningCompanionRow>()
    if (!companion) throw new RequestError('没有找到这位饭搭子。', 404)
    await database.prepare('UPDATE dining_companions SET linked_user_id = NULL, updated_at = ? WHERE id = ?').bind(now, companion.id).run()
    return { ...rowToDiningCompanion(companion), linkedUserId: null, updatedAt: now }
  }
  if (body.action === 'import' && typeof body.requestId === 'string' && Array.isArray(body.sourceVisitIds)) {
    return importCompanionHistory(database, viewerId, body.requestId, body.sourceVisitIds.filter((id): id is string => typeof id === 'string'))
  }
  throw new RequestError('饭搭子关联操作格式不正确。', 400)
}

async function readCompanionHistory(database: D1Database, viewerId: string, requestId: string) {
  const request = await database.prepare(`SELECT * FROM companion_link_requests WHERE id = ? AND status = 'accepted' AND (requester_user_id = ? OR target_user_id = ?)`)
    .bind(requestId, viewerId, viewerId).first<CompanionLinkRequestRow>()
  if (!request) throw new RequestError('没有找到已接受的历史关联。', 404)
  const facts = await companionHistoryFacts(database, request)
  return { request: await companionLinkRequestWithCounts(database, request), facts }
}

async function companionLinkRequestWithCounts(database: D1Database, row: CompanionLinkRequestRow) {
  const facts = await companionHistoryFacts(database, row)
  return {
    id: row.id,
    companionId: row.companion_id,
    companionDisplayName: row.companion_display_name,
    requesterUserId: row.requester_user_id,
    targetUserId: row.target_user_id,
    status: row.status,
    visitCount: facts.length,
    restaurantCount: new Set(facts.map((fact) => fact.restaurant.amapPoiId)).size,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

async function companionHistoryFacts(database: D1Database, request: CompanionLinkRequestRow) {
  const result = await database.prepare(`SELECT v.*, r.amap_poi_id, r.name, r.address, r.city, r.latitude, r.longitude, r.merchant_image_url
    FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
    WHERE v.user_id = ? AND v.deleted_at IS NULL AND r.deleted_at IS NULL ORDER BY v.visited_at DESC`)
    .bind(request.requester_user_id).all<VisitRow & RestaurantRow>()
  return result.results.flatMap((row) => {
    const companionIds = parseStringArray(row.companion_ids_json)
    const companionNames = parseStringArray(row.companions_json)
    if (!companionIds.includes(request.companion_id) && !companionNames.some((name) => name.trim().toLocaleLowerCase('zh-CN') === request.companion_display_name.trim().toLocaleLowerCase('zh-CN'))) return []
    return [{
      sourceVisitId: row.id,
      restaurant: { amapPoiId: row.amap_poi_id, name: row.name, address: row.address, city: row.city, latitude: row.latitude, longitude: row.longitude, merchantImageUrl: row.merchant_image_url },
      visitedAt: row.visited_at,
      sharedMealId: row.shared_meal_id,
    }]
  })
}

async function importCompanionHistory(database: D1Database, viewerId: string, requestId: string, sourceVisitIds: string[]) {
  const request = await database.prepare(`SELECT * FROM companion_link_requests WHERE id = ? AND target_user_id = ? AND status = 'accepted'`).bind(requestId, viewerId).first<CompanionLinkRequestRow>()
  if (!request) throw new RequestError('没有找到可导入的历史关联。', 404)
  const selected = new Set(sourceVisitIds)
  const facts = (await companionHistoryFacts(database, request)).filter((fact) => selected.has(fact.sourceVisitId))
  const now = new Date().toISOString()
  let imported = 0
  for (const fact of facts) {
    let restaurant = await database.prepare('SELECT * FROM restaurants WHERE user_id = ? AND amap_poi_id = ? AND deleted_at IS NULL LIMIT 1').bind(viewerId, fact.restaurant.amapPoiId).first<RestaurantRow>()
    if (!restaurant) {
      const restaurantId = `history-restaurant:${viewerId}:${await shortHash(fact.restaurant.amapPoiId)}`
      const cloudRestaurant: CloudRestaurant = {
        id: restaurantId, userId: viewerId, ...fact.restaurant, status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, markerType: fact.restaurant.merchantImageUrl ? 'image' : 'emoji', markerPhotoId: null, markerEmoji: '🍽️', createdAt: now, updatedAt: now, deletedAt: null,
      }
      await upsertRestaurants(database, [cloudRestaurant])
      restaurant = await database.prepare('SELECT * FROM restaurants WHERE id = ?').bind(restaurantId).first<RestaurantRow>()
    }
    const visitId = `history-visit:${viewerId}:${await shortHash(`${requestId}:${fact.sourceVisitId}`)}`
    const exists = await database.prepare('SELECT id FROM visits WHERE id = ?').bind(visitId).first()
    if (exists) continue
    const visit: CloudVisit = {
      id: visitId, userId: viewerId, restaurantId: (restaurant as RestaurantRow).id, visitedAt: fact.visitedAt, rating: null, visibility: 'private', diningMode: 'dine_in', totalPrice: null, myActualSpend: null, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null, diningOccasions: [], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: fact.sharedMealId, companions: [], companionIds: [], dishes: [], note: '', photoIds: [], createdAt: now, updatedAt: now, deletedAt: null,
    }
    await upsertVisits(database, [visit])
    imported += 1
  }
  return { imported }
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
  const [visitsResult, restaurantsResult, followerResult, followingResult] = await database.batch([
    database.prepare(`SELECT * FROM visits WHERE user_id = ? AND deleted_at IS NULL AND ${visibilitySql} ORDER BY visited_at DESC`).bind(profileId),
    database.prepare(`SELECT * FROM restaurants WHERE id IN (
      SELECT restaurant_id FROM visits WHERE user_id = ? AND deleted_at IS NULL AND ${visibilitySql}
    ) AND deleted_at IS NULL`).bind(profileId),
    database.prepare('SELECT COUNT(*) AS count FROM follows WHERE followed_user_id = ?').bind(profileId),
    database.prepare('SELECT COUNT(*) AS count FROM follows WHERE follower_id = ?').bind(profileId),
  ])
  const restaurants = new Map((restaurantsResult.results as unknown as RestaurantRow[]).map((row) => [row.id, {
    id: row.id, amapPoiId: row.amap_poi_id, name: row.name, address: row.address, city: row.city, latitude: row.latitude, longitude: row.longitude,
    tags: parseStringArray(row.tags_json), pricePerPerson: row.price_per_person, phone: row.phone, openingHours: row.opening_hours,
    merchantImageUrl: row.merchant_image_url, markerEmoji: row.marker_emoji,
  }]))
  return {
    user: publicUser(user),
    items: (visitsResult.results as unknown as VisitRow[]).flatMap((row) => {
      const restaurant = restaurants.get(row.restaurant_id)
      return restaurant ? [{ visit: rowToVisit(row), restaurant }] : []
    }),
    followerCount: Number((followerResult.results[0] as { count?: number } | undefined)?.count ?? 0),
    followingCount: Number((followingResult.results[0] as { count?: number } | undefined)?.count ?? 0),
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

function rowToDiningCompanion(row: DiningCompanionRow) {
  return {
    id: row.id,
    ownerUserId: row.owner_user_id,
    displayName: row.display_name,
    linkedUserId: row.linked_user_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  }
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
    phone: row.phone,
    openingHours: row.opening_hours,
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
    companionIds: parseStringArray(row.companion_ids_json),
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
    storageProvider: row.storage_provider ?? 'google-drive',
    storageKey: row.storage_key ?? row.drive_file_id,
    thumbnailStorageKey: row.thumbnail_storage_key ?? null,
    thumbnailFileSize: row.thumbnail_file_size ?? null,
    driveAccountId: row.drive_account_id,
    driveFileId: row.drive_file_id,
    fileName: row.file_name,
    mimeType: row.mime_type,
    fileSize: row.file_size,
    width: row.width,
    height: row.height,
    visibility: row.visibility ?? 'private',
    syncStatus: row.sync_status ?? 'synced',
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

function isCloudRestaurantList(value: unknown): value is CloudRestaurantList {
  return isRecord(value) && typeof value.id === 'string' && typeof value.title === 'string' &&
    typeof value.description === 'string' && ['private', 'friends', 'public'].includes(String(value.visibility)) &&
    typeof value.isRanked === 'boolean' && ['automatic', 'custom'].includes(String(value.coverMode)) &&
    typeof value.createdAt === 'string' && typeof value.updatedAt === 'string' && !('customCoverImageData' in value)
}

function isCloudRestaurantListItem(value: unknown): value is CloudRestaurantListItem {
  return isRecord(value) && typeof value.id === 'string' && typeof value.listId === 'string' &&
    typeof value.restaurantId === 'string' && typeof value.position === 'number' && typeof value.note === 'string' &&
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
