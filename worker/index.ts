import { resumeAccountDeletions } from './accountDeletionV1'
import { prohibitedUGCText } from './ugcTextPolicy'
import { runPrivacyRetention } from './privacyRetentionV1'
import { referralAvailable } from '../src/config/referralAvailability'
import { signupTrialEligibility, claimSignupTrial } from './signupTrialV1'
import { referralDashboard, qualifyReferral, settlePremiumRewards, settleAllPremiumRewards, revokeReferral } from './referralsV1'
import { referralLandingPage } from './referralLandingPage'
import { handlePrivateDirectoryV1, privateDirectoryAvatar } from './privateDirectoryV1'
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
import type { RestaurantPlaceIdentity, RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { decodeRestaurantJSONContract, RestaurantContractError } from '../src/contracts/restaurantContract'
import { readRestaurantSocialStats } from './restaurantStats'
import { calculateTasteSimilarities, tasteSimilarityForDisplay } from './tasteSimilarity'
import { recommendationHistoryReasons } from '../src/services/recommendationHistoryReasons'
import { rankFriendRecommendations } from './friendRecommendation'
import { rankTasteTags } from '../src/services/tasteProfileCore'
// The direct expression is intentional: esbuild must eliminate branches in
// its first pass, before importing Development-only module dependencies.
declare const __TASTEMAP_DEVELOPMENT_TOOLS__: boolean
import {
  ExternalLinkResolveError,
  resolveExternalRestaurantEvidence,
  type ExternalRestaurantResolveInput,
} from './externalRestaurantLinkResolver'
import {
  contractProviderForEvidence,
  groupRestaurantPlaceIdentities,
  type RestaurantPlaceIdentityRow,
} from './restaurantIdentityMapping'
import {
  handleSyncV1Pull,
  handleSyncV1Push,
  handleSyncConflictSnapshot,
  recordUnversionedSyncChanges,
  SyncV1RequestError,
  type SyncV1PullObservation,
} from './syncV1'
import {
  authenticateAccessToken,
  AuthV1RequestError,
  handleAuthV1Request,
} from './authV1'
import {
  handlePhotoBinaryV1,
  resumePhotoBinaryDeletions,
  PhotoBinaryV1Error,
} from './photoBinaryV1'
import {
  ensureUserProfile,
  ProfileV1RequestError,
  readPublicProfile as readPublicProfileV1,
} from './profileV1'
import { handleSocialV1, SocialV1RequestError } from './socialV1'
import {
  handleSocialCollaborationV1,
  SocialCollaborationV1Error,
} from './socialCollaborationV1'
import { handleDiscoveryV1, DiscoveryV1RequestError } from './discoveryV1'
import { handleRecommendationPreferencesV1, RecommendationPreferencesV1Error } from './recommendationPreferencesV1'
import { DiscoveryQueryError } from './discoveryHardFilters'
import { DiscoveryAggregateCapacityError } from './discoveryVisitAggregates'
import { handleCommunityV1, CommunityV1RequestError } from './communityV1'
import {
  CommunityInteractionV1Error,
  handleCommunityInteractionsV1,
} from './communityInteractionsV1'
import {
  handleRestaurantListsV1,
  RestaurantListsV1RequestError,
} from './restaurantListsV1'
import {
  consumePublicAPIQuota,
  PublicAPIRateLimitError,
} from './publicAPIRateLimit'
import { membershipSelfResponseV1 } from './membershipV1'
import {
  AppStoreCommerceV1Error,
  handleAppStoreCommerceV1,
  handleAppStoreServerNotificationV1,
} from './appStoreCommerceV1'
import {
  PublicSharingV1Error,
  createPublicShareV1,
  readPublicShareV1,
} from './publicSharingV1'
import {
  AccountDeletionV1Error,
  handleAccountDeletionV1,
} from './accountDeletionV1'
import {
  handleModerationV1,
  ModerationV1Error,
} from './moderationV1'

interface Env {
  PRIVACY_RETENTION_ENABLED?: string
  DB: D1Database
  ASSETS: Fetcher
  PHOTO_STORAGE?: R2Bucket
  APP_ENVIRONMENT?: 'development' | 'production'
  SYNC_AUTH_MODE?: 'cloudflare-access' | 'development-test'
  APPLE_CLIENT_IDS?: string
  ADMIN_EMAILS?: string
  MEMBERSHIP_ADMIN_USER_IDS?: string
  APP_STORE_BUNDLE_ID?: string
  APP_STORE_MONTHLY_PRODUCT_ID?: string
  APP_STORE_YEARLY_PRODUCT_ID?: string
  APP_STORE_API_ENVIRONMENT?: 'sandbox' | 'production'
  APP_STORE_ISSUER_ID?: string
  APP_STORE_KEY_ID?: string
  APP_STORE_PRIVATE_KEY?: string
  APP_STORE_APP_APPLE_ID?: string
  PUBLIC_SHARE_ORIGIN?: string
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
  website_url: string | null
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
  party_size_optional: number | null
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
  auth_provider: 'apple' | 'cloudflare-access' | 'local'
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
  is_test_user: number
}

interface MembershipEntitlementRow {
  id: string
  user_id: string
  source: 'app_store_monthly' | 'app_store_annual' | 'gift_annual' | 'gift_lifetime' | 'app_store_subscription'
  | 'promotion'
  | 'signup_trial'
  | 'referral_reward' | 'app_store_yearly' | 'app_store_lifetime' | 'admin_grant' | 'promo' | 'redeem_code'
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
    value_rating, tags_json, long_term_note, price_per_person, phone, website_url, opening_hours, marker_type,
    marker_photo_id, merchant_image_url, marker_emoji, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    website_url = excluded.website_url,
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

const RESTAURANT_PLACE_IDENTITY_UPSERT = `
  INSERT INTO restaurant_place_identities (
    restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
  )
  SELECT ?, ?, ?, ?, ?, ?, ?
  WHERE EXISTS (
    SELECT 1 FROM restaurants WHERE id = ? AND updated_at = ?
  )
  ON CONFLICT(restaurant_id, provider, external_id) DO UPDATE SET
    user_id = excluded.user_id,
    is_primary = excluded.is_primary,
    updated_at = MAX(excluded.updated_at, restaurant_place_identities.updated_at)
`

const RESTAURANT_PLACE_IDENTITY_CLEAR_PRIMARY = `
  UPDATE restaurant_place_identities
  SET is_primary = 0, updated_at = MAX(updated_at, ?)
  WHERE restaurant_id = ? AND is_primary = 1
    AND EXISTS (
      SELECT 1 FROM restaurants WHERE id = ? AND updated_at = ?
    )
`

const VISIT_UPSERT = `
  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, visibility, dining_mode,
    total_price, my_actual_spend, payment_mode, price_per_person, party_size, party_size_optional,
    queue_duration, dining_occasion, dining_occasion_text, dining_occasions_json, value_rating, environment_rating, service_rating,
    value_tags_json, environment_tags_json, service_tags_json,
    noise_level, dining_duration, portion_level, transport_convenience, special_notes,
    recommendation_source_type, recommendation_source_user_id, recommendation_source_text,
    shared_meal_id, companions_json, companion_ids_json, dishes_json, note, photo_ids_json,
    created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    party_size_optional = excluded.party_size_optional,
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

const LEGACY_DISH_UPSERT = `
  INSERT INTO dishes (
    id, user_id, restaurant_id, visit_id, name, taste, rating, price, photo_id,
    sort_order, created_at, updated_at, deleted_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    restaurant_id = excluded.restaurant_id,
    visit_id = excluded.visit_id,
    name = excluded.name,
    taste = excluded.taste,
    rating = excluded.rating,
    price = excluded.price,
    photo_id = excluded.photo_id,
    sort_order = excluded.sort_order,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE dishes.user_id = excluded.user_id AND excluded.updated_at > dishes.updated_at
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

import { premiumAdminPage } from './premiumAdminPage'
import productionEnvironment from '../ios/TasteMap/TasteMap/Configuration/ProductionEnvironment.json'
import { withProductionCORS } from './productionBoundary'
import { productionReadiness } from './productionReadiness'

const worker = {
  async scheduled(controller, env) {
    try {
      await settleAllPremiumRewards(env.DB)
    } finally {
      await resumePhotoBinaryDeletions(env, new Date(controller.scheduledTime))
        .catch(() => console.error('Photo binary deletion reconciliation remains pending.'))
      if (env.PRIVACY_RETENTION_ENABLED === 'true') {
        const now = new Date(controller.scheduledTime)
        await resumeAccountDeletions(env, now)
        // Reuse the existing five-minute cron, with one daily retention pass.
        if (now.getUTCHours() === 18 && now.getUTCMinutes() === 0) await runPrivacyRetention(env.DB, env.PHOTO_STORAGE, now)
      }
    }
  },
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url)
    // Public liveness probe: never touch authentication, data bindings, or SPA assets.
    if (url.pathname === '/health' && request.method === 'GET') {
      return new Response('{"status":"ok"}', {
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      })
    }
    if (url.pathname === '/ready' && request.method === 'GET') return productionReadiness(env)
    if (url.pathname.startsWith('/invite/') && !referralAvailable()) return new Response('邀请功能暂未开放。', {status:404,headers:{'Cache-Control':'no-store'}})
    if (url.pathname.startsWith('/invite/') && request.method==='GET') return referralLandingPage(url.pathname.slice('/invite/'.length))
    if (url.pathname === '/internal/premium' && request.method === 'GET') {
      try {
        const user = await authenticateAccessToken(request, env.DB)
        if (!user) return json({ error: 'Authentication required' }, 401)
        if (!(env.MEMBERSHIP_ADMIN_USER_IDS ?? '').split(',').map(id => id.trim()).includes(user.id)) {
          return json({ error: 'Administrator required' }, 403)
        }
        return premiumAdminPage()
      } catch (error) {
        // This HTML route precedes the API catch boundary. Reject invalid or
        // expired sessions as JSON without leaking infrastructure exceptions.
        if (error instanceof AuthV1RequestError) {
          return json({ error: 'Authentication required', code: error.code }, error.status)
        }
        return json({ error: 'Administrator authentication unavailable' }, 503)
      }
    }
    if (url.pathname === '/.well-known/apple-app-site-association' && request.method === 'GET') {
      return new Response(JSON.stringify({
        applinks: {
          details: [{
            appIDs: [productionEnvironment.appleAppID],
            components: [{ '/': '/share/*', comment: 'Taste Map public sharing' }, { '/': '/invite/*', comment: 'Taste Map referral registration' }],
          }],
        },
      }), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' } })
    }
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request)
    if (!isSameOriginRequest(request, url)) return json({ error: '不允许跨站访问同步 API。' }, 403)

    try {
      if (url.pathname === '/api/v1/admin/memberships' || url.pathname === '/api/admin/memberships') {
        // Never accept spoofable Access-email headers or development test identities here.
        const authenticated = await authenticateAccessToken(request, env.DB)
        if (!authenticated) throw new RequestError('请使用有效的 Taste Map 管理员登录会话。', 401)
        const viewer: ViewerIdentity = { id: authenticated.id, email: authenticated.email, authProvider: 'apple', authSubject: null }
        requireMembershipAdmin(request, env, viewer)
        if (request.method === 'GET') return json(await searchMembershipUsers(env.DB, url.searchParams.get('q') ?? ''))
        if (request.method === 'POST') return json(await mutateMembership(env.DB, viewer.id, request))
        throw new RequestError('不支持这个会员操作。', 405)
      }
      if (url.pathname.startsWith('/api/v1/auth/')) {
        return json(await handleAuthV1Request(request, env))
      }
      if (url.pathname === '/api/v1/referrals') {
        if (!referralAvailable()) return json({error:'邀请功能暂未开放。',code:'referral_unavailable'},403)
        if (request.method !== 'GET') throw new RequestError('邀请只能在新账号注册时绑定。', 405)
        const user = await authenticateAccessToken(request, env.DB)
        if (!user) throw new RequestError('请先登录。',401)
        return json(await referralDashboard(env.DB,user.id,env.APP_ENVIRONMENT === 'production' ? productionEnvironment.publicWebOrigin : url.origin))
      }
      if (url.pathname === '/api/v1/admin/referrals/revoke') {
        if (request.method !== 'POST') throw new RequestError('Method not allowed.',405)
        const user = await authenticateAccessToken(request,env.DB)
        if (!user) throw new RequestError('请先登录。',401)
        requireMembershipAdmin(request,env,{id:user.id,email:user.email,authProvider:'apple',authSubject:null})
        const body = await request.json() as {inviteeID?:string,note?:string}
        if (typeof body.inviteeID!=='string' || typeof body.note!=='string' || !body.note.trim()) throw new RequestError('需要被邀请人 ID 和撤销原因。',400)
        await revokeReferral(env.DB,body.inviteeID,user.id,body.note)
        return json({revoked:true})
      }
      if (url.pathname === '/api/v1/account-deletion/status' ||
          url.pathname === '/api/v1/account-deletion/retry') {
        return json(await handleAccountDeletionV1(request, env, null))
      }
      if (url.pathname.startsWith('/api/v1/account-deletion/')) {
        const viewer = await resolveSyncViewer(request, env)
        return json(await handleAccountDeletionV1(request, env, {
          id: viewer.id,
          authenticatedAt: viewer.authenticatedAt,
          developmentIdentity: viewer.authProvider === 'local' && env.APP_ENVIRONMENT === 'development',
        }))
      }
      if (url.pathname === '/api/v1/storekit/notifications') {
        return json(await handleAppStoreServerNotificationV1(request, env.DB, env))
      }
      if ((typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && url.pathname.startsWith('/api/v1/development/demo-data')) {
        const { handleDevelopmentDemoAdminV1, DevelopmentDemoAdminV1Error } = await import('./developmentDemoAdminV1')
        const viewer = await resolveSyncViewer(request, env)
        try {
          return json(await handleDevelopmentDemoAdminV1(request, env.DB, viewer.id, env))
        } catch (error) {
          if (error instanceof DevelopmentDemoAdminV1Error) throw new RequestError(error.message, error.status)
          throw error
        }
      }
      if (url.pathname === '/api/v1/me/premium-trial-eligibility' || url.pathname === '/api/v1/me/premium-trial/claim') {
        const claim = url.pathname.endsWith('/claim')
        if (request.method !== (claim ? 'POST' : 'GET')) throw new RequestError('Trial method is not supported.', 405)
        const viewer = await resolveSyncViewer(request, env)
        if (viewer.testMembership !== undefined) throw new RequestError('请使用正式登录账号领取。', 403)
        if (!claim) return json(await signupTrialEligibility(env.DB, viewer.id))
        const body = await request.text()
        if (body.trim() && body.trim() !== '{}') throw new RequestError('领取接口不接受客户端资格、账号或时间字段。', 400)
        const trial = await claimSignupTrial(env.DB, viewer.id)
        if (!trial) throw new RequestError('这个账号已经领取过 7 天 Premium。', 409)
        return json({ apiVersion: 1, userId: viewer.id, ...trial,
          membership: membershipSelfResponseV1(viewer.id, await readEffectiveMembership(env.DB, viewer.id)) })
      }
      if (url.pathname === '/api/v1/me/entitlements') {
        if (request.method !== 'GET') throw new RequestError('Membership method is not supported.', 405)
        const viewer = await resolveSyncViewer(request, env)
        const entitlement = await readViewerMembership(env.DB, viewer)
        return json(membershipSelfResponseV1(
          viewer.id,
          entitlement,
          viewer.testMembership !== undefined,
        ))
      }
      if (url.pathname.startsWith('/api/v1/storekit/')) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        return json(await handleAppStoreCommerceV1(request, env.DB, viewer.id, env, fetch, viewer.sessionId))
      }
      const publicShareMatch = url.pathname.match(/^\/api\/public\/shares\/([A-Za-z0-9_-]+)$/)
      if (publicShareMatch) {
        return json(await readPublicShareV1(request, env.DB, publicShareMatch[1]))
      }
      if (url.pathname === '/api/v1/public-shares') {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        return json(await createPublicShareV1(request, env.DB, viewer.id, env))
      }
      const publicRestaurantMatch = url.pathname.match(/^\/api\/public\/restaurants\/([a-f0-9]{24})$/)
      if (publicRestaurantMatch && request.method === 'GET') {
        return json(await readPublicRestaurant(env.DB, publicRestaurantMatch[1]))
      }
      if (url.pathname === '/api/v1/sync/conflict-snapshot' && request.method === 'GET') {
        const viewer = await resolveSyncViewer(request, env)
        return json(await handleSyncConflictSnapshot(env.DB, viewer.id, request))
      }
      if (url.pathname === '/api/v1/sync/pull' && request.method === 'GET') {
        const requestStartedAt = performance.now()
        const authStartedAt = performance.now()
        const viewer = await resolveSyncViewer(request, env)
        const authDurationMs = performance.now() - authStartedAt
        const profileStartedAt = performance.now()
        await ensureUserProfile(env.DB, viewer.id)
        const profileDurationMs = performance.now() - profileStartedAt
        const observation: SyncV1PullObservation = {
          ledgerQueryDurationMs: 0,
          hydrationQueryDurationMs: 0,
          responseAssemblyDurationMs: 0,
          changeCount: 0,
          hydratedEntityCount: 0,
          tombstoneCount: 0,
          cursorFrom: '0',
          cursorTo: '0',
          hasMore: false,
        }
        const payload = await handleSyncV1Pull(env.DB, viewer.id, request, observation)
        const encodingStartedAt = performance.now()
        const serialized = JSON.stringify(payload)
        const encodingDurationMs = performance.now() - encodingStartedAt
        const responseBytes = new TextEncoder().encode(serialized).byteLength
        const totalDurationMs = performance.now() - requestStartedAt
        if (env.APP_ENVIRONMENT === 'development') {
          console.info(JSON.stringify({
            event: 'sync_v1_pull_response_ready',
            environment: 'development',
            status: 200,
            authDurationMs: observedDuration(authDurationMs),
            profileDurationMs: observedDuration(profileDurationMs),
            ledgerQueryDurationMs: observedDuration(observation.ledgerQueryDurationMs),
            hydrationQueryDurationMs: observedDuration(observation.hydrationQueryDurationMs),
            responseAssemblyDurationMs: observedDuration(observation.responseAssemblyDurationMs),
            encodingDurationMs: observedDuration(encodingDurationMs),
            totalDurationMs: observedDuration(totalDurationMs),
            responseBytes,
            changeCount: observation.changeCount,
            hydratedEntityCount: observation.hydratedEntityCount,
            tombstoneCount: observation.tombstoneCount,
            cursorFrom: observation.cursorFrom,
            cursorTo: observation.cursorTo,
            hasMore: observation.hasMore,
          }))
        }
        return new Response(serialized, {
          status: 200,
          headers: {
            'Cache-Control': 'no-store',
            'Content-Type': 'application/json; charset=utf-8',
            'X-Content-Type-Options': 'nosniff',
            'Server-Timing': [
              `auth;dur=${observedDuration(authDurationMs)}`,
              `profile;dur=${observedDuration(profileDurationMs)}`,
              `ledger;dur=${observedDuration(observation.ledgerQueryDurationMs)}`,
              `hydrate;dur=${observedDuration(observation.hydrationQueryDurationMs)}`,
              `assemble;dur=${observedDuration(observation.responseAssemblyDurationMs)}`,
              `encode;dur=${observedDuration(encodingDurationMs)}`,
            ].join(', '),
          },
        })
      }
      if (url.pathname === '/api/v1/sync/push' && request.method === 'POST') {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        const membership = await readViewerMembership(env.DB, viewer)
        const result = await handleSyncV1Push(env.DB, viewer.id, request, {
          isPremium: membership.isPremium,
          visitPhotoLimit: membership.isPremium ? 20 : 2,
        })
        await qualifyReferral(env.DB,viewer.id)
        return json(result)
      }
      if (url.pathname.startsWith('/api/v1/public/profiles/') && request.method === 'GET') {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        await consumePublicAPIQuota(env.DB, viewer.id, 'public-profile-read', 180)
        const profileId = decodeURIComponent(url.pathname.slice('/api/v1/public/profiles/'.length))
        return json(await readPublicProfileV1(env.DB, viewer.id, profileId))
      }
      if (url.pathname === '/api/v1/directory' || url.pathname.startsWith('/api/v1/directory/avatar/')) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        await consumePublicAPIQuota(env.DB, viewer.id, request.method === 'GET' ? 'social-read' : 'social-mutation', 120)
        if(url.pathname.startsWith('/api/v1/directory/avatar/') && request.method==='GET') {
          const parts=url.pathname.split('/'); return await privateDirectoryAvatar(env.DB,viewer.id,parts[5],decodeURIComponent(parts.slice(6).join('/')))
        }
        return json(await handlePrivateDirectoryV1(request,env.DB,viewer.id))
      }
      if (url.pathname.startsWith('/api/v1/social/')) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        if (url.pathname === '/api/v1/social/suggestions' ||
          url.pathname.startsWith('/api/v1/social/companion-links') ||
          url.pathname.startsWith('/api/v1/social/shared-meals')) {
          return json(await handleSocialCollaborationV1(request, env.DB, viewer.id))
        }
        return json(await handleSocialV1(request, env.DB, viewer.id))
      }
      if (url.pathname.startsWith('/api/v1/discovery/')) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        const membership = await readViewerMembership(env.DB, viewer)
        return json(await handleDiscoveryV1(request, env.DB, viewer.id, {
          isPremium: membership.isPremium,
        }))
      }
      if (url.pathname.startsWith('/api/v1/community/')) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        if (url.pathname === '/api/v1/community/reports' || url.pathname === '/api/v1/community/safety' ||
            url.pathname.startsWith('/api/v1/community/blocks/')) {
          return json(await handleModerationV1(request, env.DB, viewer.id))
        }
        if (url.pathname.startsWith('/api/v1/community/content/') ||
          url.pathname.startsWith('/api/v1/community/comments/')) {
          return json(await handleCommunityInteractionsV1(request, env.DB, viewer.id))
        }
        return json(await handleCommunityV1(request, env.DB, viewer.id))
      }
      if (url.pathname.startsWith('/api/v1/recommendation-preferences/')) {
        const viewer = await resolveSyncViewer(request, env)
        return json(await handleRecommendationPreferencesV1(request, env.DB, viewer.id))
      }
      if (url.pathname.startsWith('/api/v1/lists/')) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        return json(await handleRestaurantListsV1(request, env.DB, viewer.id))
      }
      const photoContentMatch = url.pathname.match(/^\/api\/v1\/photos\/([0-9a-f-]+)\/content$/i)
      if (photoContentMatch) {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        return handlePhotoBinaryV1(request, env, viewer.id, photoContentMatch[1])
      }
      if (url.pathname === '/api/v1/external-place/resolve' && request.method === 'POST') {
        const viewer = await resolveSyncViewer(request, env)
        await ensureUserProfile(env.DB, viewer.id)
        return json(await resolveExternalPlaceRequest(env.DB, viewer.id, request))
      }
      const viewer = env.APP_ENVIRONMENT === 'production'
        ? await resolveSyncViewer(request, env)
        : await resolveViewer(request, env.DB)
      if (url.pathname === '/api/external-place/resolve' && request.method === 'POST') {
        return json(await resolveExternalPlaceRequest(env.DB, viewer.id, request))
      }
      if (url.pathname === '/api/sync' && request.method === 'GET') return json(await readSnapshot(env.DB, viewer.id, url.searchParams.get('since')))
      if (url.pathname === '/api/sync' && request.method === 'POST') {
        const payload = await readPayload(request)
        if (payload.visits.some(visit => !visit.deletedAt && visit.visibility && visit.visibility !== 'private' && prohibitedUGCText([visit.note, visit.specialNotes, visit.diningOccasionText].join('\n'))) ||
            payload.users.some(user => (user.id === 'owner' || user.id === viewer.id) && !user.deletedAt && user.mapVisibility && user.mapVisibility !== 'private' && prohibitedUGCText([user.nickname, user.bio].join('\n')))) {
          throw new SyncV1RequestError('公开内容包含不允许发布的攻击、违法或垃圾内容，请修改后重试。', 422)
        }
        const mapUserId = (id: string | null | undefined) => id === 'owner' ? viewer.id : id
        await upsertRestaurants(env.DB, payload.restaurants.map((item) => ({ ...item, userId: viewer.id })))
        await upsertVisits(env.DB, payload.visits.map((item) => ({
          ...item,
          userId: viewer.id,
          recommendationSourceUserId: mapUserId(item.recommendationSourceUserId) ?? null,
        })))
        await qualifyReferral(env.DB,viewer.id)
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
        await upsertRestaurantListItems(env.DB, payload.restaurantListItems, viewer.id)
        return json(await readSnapshot(env.DB, viewer.id))
      }
      if (url.pathname === '/api/community' && request.method === 'GET') {
        await consumePublicAPIQuota(env.DB, viewer.id, 'legacy-community-read', 120)
        const membership = await readViewerMembership(env.DB, viewer)
        return json(await readCommunity(env.DB, viewer.id, url.searchParams.get('mode') ?? 'for_you', url.searchParams.get('city') ?? '', url.searchParams.get('window') === '30' ? 30 : 7, membership.isPremium))
      }
      if (url.pathname === '/api/recommendation-events' && request.method === 'POST') {
        return json(await createRecommendationEvent(env.DB, viewer.id, request), 201)
      }
      if (url.pathname === '/api/membership' && request.method === 'GET') {
        return json({ entitlement: await readViewerMembership(env.DB, viewer), isAdmin: isMembershipAdmin(request, env, viewer) })
      }
      if (url.pathname === '/api/follows' && request.method === 'GET') return json(await readFollows(env.DB, viewer.id))
      if (url.pathname === '/api/follows' && request.method === 'POST') {
        await consumePublicAPIQuota(env.DB, viewer.id, 'legacy-social-mutation', 60)
        return json(await mutateFollow(env.DB, viewer.id, request))
      }
      if (url.pathname === '/api/friend-recommendations' && request.method === 'GET') {
        return json(await readFriendRecommendations(env.DB, viewer.id,
          (typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && Boolean(request.headers.get('X-Taste-Map-Test-User'))))
      }
      const restaurantStatsMatch = url.pathname.match(/^\/api\/restaurants\/([^/]+)\/stats$/)
      if (restaurantStatsMatch && request.method === 'GET') {
        return json(await readRestaurantSocialStats(env.DB, viewer.id, decodeURIComponent(restaurantStatsMatch[1])))
      }
      const restaurantListMatch = url.pathname.match(/^\/api\/restaurant-lists\/([^/]+)$/)
      if (restaurantListMatch && request.method === 'GET') {
        return json(await readRestaurantList(env.DB, viewer.id, decodeURIComponent(restaurantListMatch[1])))
      }
      if (url.pathname.startsWith('/api/profiles/') && request.method === 'GET') {
        await consumePublicAPIQuota(env.DB, viewer.id, 'legacy-profile-read', 180)
        const profileId = decodeURIComponent(url.pathname.slice('/api/profiles/'.length))
        return json(await readProfile(env.DB, viewer.id, profileId))
      }
      if (url.pathname === '/api/users/search' && request.method === 'GET') {
        await consumePublicAPIQuota(env.DB, viewer.id, 'legacy-social-search', 60)
        return json(await searchUsers(env.DB, viewer.id, url.searchParams.get('q') ?? ''))
      }
      if (url.pathname === '/api/companion-links' && request.method === 'GET') return json(await readCompanionLinks(env.DB, viewer.id))
      if (url.pathname === '/api/companion-links' && request.method === 'POST') {
        await consumePublicAPIQuota(env.DB, viewer.id, 'legacy-social-mutation', 60)
        return json(await mutateCompanionLink(env.DB, viewer.id, request))
      }
      const companionHistoryMatch = url.pathname.match(/^\/api\/companion-links\/([^/]+)\/history$/)
      if (companionHistoryMatch && request.method === 'GET') return json(await readCompanionHistory(env.DB, viewer.id, decodeURIComponent(companionHistoryMatch[1])))
      if (url.pathname === '/api/friendships' && request.method === 'GET') return json(await readFriendships(env.DB, viewer.id))
      if (url.pathname === '/api/friendships' && request.method === 'POST') {
        await consumePublicAPIQuota(env.DB, viewer.id, 'legacy-social-mutation', 60)
        return json(await mutateFriendship(env.DB, viewer.id, request))
      }
      if (url.pathname === '/api/shared-meals' && request.method === 'GET') return json(await readSharedMeals(env.DB, viewer.id))
      if (url.pathname === '/api/shared-meals' && request.method === 'POST') return json(await createSharedMeal(env.DB, viewer.id, request), 201)
      return json({ error: '没有找到这个 API。' }, 404)
    } catch (error) {
      console.error('Taste Map request failed', {
        type: error instanceof Error ? error.name : 'UnknownError',
        status: error instanceof PublicAPIRateLimitError ? error.status : undefined,
      })
      const message = error instanceof Error ? error.message : 'D1 同步发生未知错误。'
      const status = error instanceof RecommendationPreferencesV1Error || error instanceof DiscoveryQueryError || error instanceof RequestError || error instanceof SyncV1RequestError || error instanceof AuthV1RequestError || error instanceof PhotoBinaryV1Error || error instanceof ProfileV1RequestError || error instanceof SocialV1RequestError || error instanceof SocialCollaborationV1Error || error instanceof DiscoveryV1RequestError || error instanceof DiscoveryAggregateCapacityError || error instanceof CommunityV1RequestError || error instanceof CommunityInteractionV1Error || error instanceof RestaurantListsV1RequestError || error instanceof PublicAPIRateLimitError || error instanceof AppStoreCommerceV1Error || error instanceof PublicSharingV1Error || error instanceof AccountDeletionV1Error || error instanceof ModerationV1Error ? error.status : 500
      const code = error instanceof RecommendationPreferencesV1Error || error instanceof DiscoveryQueryError || error instanceof AuthV1RequestError || error instanceof DiscoveryV1RequestError || error instanceof DiscoveryAggregateCapacityError || error instanceof AppStoreCommerceV1Error || error instanceof PublicSharingV1Error || error instanceof AccountDeletionV1Error || error instanceof ModerationV1Error ? error.code : undefined
      return json({ error: message, ...(code ? { code } : {}) }, status)
    }
  },
} satisfies ExportedHandler<Env>

export default {
  scheduled: worker.scheduled,
  fetch: (request, env) => withProductionCORS(request, () => worker.fetch(request, env)),
} satisfies ExportedHandler<Env>

interface ExternalPlaceCandidate {
  restaurantId: string | null
  amapPoiId: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  merchantImageUrl: string | null
  phone: string | null
  openingHours: string | null
  placeIdentities: Array<{ provider: RestaurantPlaceProvider; externalId: string; isPrimary: boolean }>
  matchScore: number
}

interface ExternalPlaceCandidateRow extends RestaurantRow {
  matched_provider: RestaurantPlaceProvider | null
  matched_external_id: string | null
}

async function resolveExternalPlaceRequest(database: D1Database, viewerId: string, request: Request) {
  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (contentLength > 32_000) throw new RequestError('分享内容过大，无法解析。', 413)
  const payload = await request.json().catch(() => {
    throw new RequestError('链接解析请求不是有效的 JSON。', 400)
  }) as ExternalRestaurantResolveInput
  if (!isRecord(payload) || (typeof payload.url !== 'string' && typeof payload.text !== 'string')) {
    throw new RequestError('请提供餐厅链接或分享文字。', 400)
  }

  let evidence
  try {
    evidence = await resolveExternalRestaurantEvidence({
      url: typeof payload.url === 'string' ? payload.url : undefined,
      text: typeof payload.text === 'string' ? payload.text : undefined,
      currentCity: typeof payload.currentCity === 'string' ? payload.currentCity.slice(0, 80) : undefined,
    })
  } catch (error) {
    if (error instanceof ExternalLinkResolveError) throw new RequestError(error.message, error.status)
    throw error
  }

  const candidates = await findExternalPlaceCandidates(database, viewerId, evidence)
  if (evidence.provider === 'amap' && evidence.externalId && evidence.name && evidence.address && evidence.latitude !== null && evidence.longitude !== null) {
    if (!candidates.some((candidate) => candidate.amapPoiId === evidence.externalId)) {
      candidates.unshift({
        restaurantId: null,
        amapPoiId: evidence.externalId,
        name: evidence.name,
        address: evidence.address,
        city: evidence.city,
        latitude: evidence.latitude,
        longitude: evidence.longitude,
        merchantImageUrl: null,
        phone: null,
        openingHours: null,
        placeIdentities: [{ provider: 'amap', externalId: evidence.externalId, isPrimary: true }],
        matchScore: 100,
      })
    }
  }

  const ranked = candidates.sort((left, right) => right.matchScore - left.matchScore).slice(0, 8)
  const topScore = ranked[0]?.matchScore ?? 0
  const confidence = topScore >= 85 && (ranked.length === 1 || topScore - (ranked[1]?.matchScore ?? 0) >= 20)
    ? 'HIGH'
    : ranked.length > 0
      ? 'MEDIUM'
      : evidence.name
        ? 'LOW'
        : 'NONE'
  const matchType = confidence === 'HIGH' ? 'single' : confidence === 'MEDIUM' ? 'multiple' : 'search_fallback'

  return {
    apiVersion: 1,
    sourceType: evidence.sourceType,
    sourceHost: evidence.sourceUrl ? new URL(evidence.sourceUrl).hostname : null,
    confidence,
    matchType,
    candidates: ranked.map(({ matchScore, ...candidate }) => {
      void matchScore
      return candidate
    }),
    searchFallback: evidence.name ? {
      keyword: evidence.name,
      city: evidence.city,
      addressHint: evidence.address,
      latitude: evidence.latitude,
      longitude: evidence.longitude,
    } : null,
    sourceSuggestion: recommendationSourceSuggestion(evidence.sourceType, evidence.sourceUrl),
    message: confidence === 'NONE'
      ? '没有识别出餐厅，请改用名称搜索。'
      : confidence === 'LOW'
        ? '已提取餐厅线索，请从搜索结果中确认具体门店。'
        : confidence === 'MEDIUM'
          ? '找到多个可能的门店，请选择正确的一家。'
          : '已识别餐厅，请确认后继续。',
  }
}

async function findExternalPlaceCandidates(
  database: D1Database,
  viewerId: string,
  evidence: Awaited<ReturnType<typeof resolveExternalRestaurantEvidence>>,
) {
  const identityProvider = contractProviderForEvidence(evidence.provider) ?? ''
  const identityExternalId = identityProvider ? evidence.externalId ?? '' : ''
  const result = await database.prepare(`
    SELECT DISTINCT r.*, identity.provider AS matched_provider, identity.external_id AS matched_external_id
    FROM restaurants r
    LEFT JOIN visits v ON v.restaurant_id = r.id AND v.deleted_at IS NULL AND v.visibility = 'public'
    LEFT JOIN restaurant_place_identities identity
      ON identity.restaurant_id = r.id AND identity.provider = ? AND identity.external_id = ?
    WHERE r.deleted_at IS NULL
      AND (r.user_id = ? OR v.id IS NOT NULL)
      AND (
        (? <> '' AND identity.restaurant_id IS NOT NULL)
        OR (? <> '' AND r.name LIKE ?)
        OR (? <> '' AND r.address LIKE ?)
      )
    ORDER BY r.updated_at DESC
    LIMIT 80
  `).bind(
    identityProvider,
    identityExternalId,
    viewerId,
    identityExternalId,
    evidence.name,
    `%${escapeSqlLike(evidence.name)}%`,
    evidence.address,
    `%${escapeSqlLike(evidence.address.slice(0, 32))}%`,
  ).all()
  const seen = new Set<string>()
  const candidates: ExternalPlaceCandidate[] = []
  for (const row of result.results as unknown as ExternalPlaceCandidateRow[]) {
    if (seen.has(row.id)) continue
    seen.add(row.id)
    const matchScore = scoreExternalPlaceCandidate(evidence, row)
    if (matchScore < 35) continue
    candidates.push({
      restaurantId: row.user_id === viewerId ? row.id : null,
      amapPoiId: row.amap_poi_id,
      name: row.name,
      address: row.address,
      city: row.city,
      latitude: row.latitude,
      longitude: row.longitude,
      merchantImageUrl: row.merchant_image_url,
      phone: row.phone,
      openingHours: row.opening_hours,
      placeIdentities: externalCandidateIdentities(row),
      matchScore,
    })
  }
  return candidates
}

function externalCandidateIdentities(row: ExternalPlaceCandidateRow) {
  if (row.matched_provider && row.matched_external_id) {
    return [{ provider: row.matched_provider, externalId: row.matched_external_id, isPrimary: true }]
  }
  if (row.amap_poi_id) {
    return [{ provider: 'amap' as const, externalId: row.amap_poi_id, isPrimary: true }]
  }
  return [{ provider: 'manual' as const, externalId: `tastemap:${row.id}`, isPrimary: true }]
}

function scoreExternalPlaceCandidate(
  evidence: Awaited<ReturnType<typeof resolveExternalRestaurantEvidence>>,
  row: ExternalPlaceCandidateRow,
) {
  let score = 0
  if (evidence.externalId && row.matched_external_id === evidence.externalId) score += 100
  const evidenceName = normalizeExternalIdentityText(evidence.name)
  const rowName = normalizeExternalIdentityText(row.name)
  if (evidenceName && rowName === evidenceName) score += 48
  else if (evidenceName && (rowName.includes(evidenceName) || evidenceName.includes(rowName))) score += 34
  const evidenceAddress = normalizeExternalIdentityText(evidence.address)
  const rowAddress = normalizeExternalIdentityText(row.address)
  if (evidenceAddress && rowAddress === evidenceAddress) score += 34
  else if (evidenceAddress && (rowAddress.includes(evidenceAddress) || evidenceAddress.includes(rowAddress))) score += 22
  if (evidence.latitude !== null && evidence.longitude !== null) {
    const distance = externalDistanceMeters(evidence.latitude, evidence.longitude, row.latitude, row.longitude)
    if (distance <= 80) score += 36
    else if (distance <= 300) score += 20
    else if (distance <= 1_500) score += 8
  }
  if (evidence.city && normalizeExternalIdentityText(evidence.city) === normalizeExternalIdentityText(row.city)) score += 6
  return score
}

function normalizeExternalIdentityText(value: string) {
  return value.normalize('NFKC').toLocaleLowerCase('zh-CN').replace(/[\s—_·•（）()【】[\]，,。.-]/g, '').replace(/(餐厅|饭店|店)$/g, '')
}

function externalDistanceMeters(leftLatitude: number, leftLongitude: number, rightLatitude: number, rightLongitude: number) {
  const radians = (degrees: number) => degrees * Math.PI / 180
  const latitudeDelta = radians(rightLatitude - leftLatitude)
  const longitudeDelta = radians(rightLongitude - leftLongitude)
  const leftRadians = radians(leftLatitude)
  const rightRadians = radians(rightLatitude)
  const value = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(leftRadians) * Math.cos(rightRadians) * Math.sin(longitudeDelta / 2) ** 2
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value))
}

function recommendationSourceSuggestion(sourceType: string, sourceUrl: string | null) {
  const hostname = sourceUrl ? new URL(sourceUrl).hostname.toLowerCase() : ''
  if (hostname.includes('xiaohongshu')) return '小红书'
  if (hostname.includes('dianping')) return '大众点评'
  if (hostname.includes('douyin')) return '抖音'
  if (sourceType === 'apple_maps') return 'Apple 地图'
  if (sourceType === 'amap') return '高德地图'
  return '链接分享'
}

function escapeSqlLike(value: string) {
  return value.replace(/[%_]/g, '')
}

async function readPayload(request: Request): Promise<SyncPayload> {
  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (contentLength > 5_000_000) throw new RequestError('同步数据过大，照片不应上传到 D1。', 413)
  const value: unknown = await request.json().catch(() => {
    throw new RequestError('同步请求不是有效的 JSON。', 400)
  })
  if (!isRecord(value) || !Array.isArray(value.restaurants) || !Array.isArray(value.visits)) {
    throw new RequestError('同步请求的数据格式不正确。', 400)
  }
  let restaurants: CloudRestaurant[]
  try {
    restaurants = value.restaurants.map(normalizeCloudRestaurant)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Restaurant JSON contract 无法识别。'
    throw new RequestError(message, 400)
  }
  const photos = Array.isArray(value.photos) ? value.photos : []
  const users = Array.isArray(value.users) ? value.users : []
  const friendships = Array.isArray(value.friendships) ? value.friendships : []
  const sharedMeals = Array.isArray(value.sharedMeals) ? value.sharedMeals : []
  const sharedMealParticipants = Array.isArray(value.sharedMealParticipants) ? value.sharedMealParticipants : []
  const restaurantLists = Array.isArray(value.restaurantLists) ? value.restaurantLists : []
  const restaurantListItems = Array.isArray(value.restaurantListItems) ? value.restaurantListItems : []
  if (!value.visits.every(isCloudVisit) || !photos.every(isCloudPhoto) ||
    !users.every(isCloudUser) || !friendships.every(isCloudFriendship) || !sharedMeals.every(isCloudSharedMeal) ||
    !sharedMealParticipants.every(isCloudSharedMealParticipant) || !restaurantLists.every(isCloudRestaurantList) ||
    !restaurantListItems.every(isCloudRestaurantListItem)) {
    throw new RequestError('同步请求包含无法识别的餐厅或到访记录。', 400)
  }
  return { restaurants, visits: value.visits, photos, users, friendships, sharedMeals, sharedMealParticipants, restaurantLists, restaurantListItems }
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
    restaurant.websiteUrl ?? null,
    restaurant.openingHours ?? null,
    restaurant.markerType,
    restaurant.markerPhotoId ?? null,
    restaurant.merchantImageUrl,
    restaurant.markerEmoji,
    restaurant.createdAt,
    restaurant.updatedAt,
    restaurant.deletedAt,
  ))
  const results = await runInChunks(database, statements)
  for (const restaurant of restaurants) {
    const primaryIdentity = restaurant.placeIdentities.find((identity) => identity.isPrimary)
    if (!primaryIdentity) throw new RestaurantContractError('Restaurant requires one primary provider identity.')
    const identityStatements = restaurant.placeIdentities.map((identity) => (
      database.prepare(RESTAURANT_PLACE_IDENTITY_UPSERT).bind(
        restaurant.id,
        restaurant.userId ?? 'owner',
        identity.provider,
        identity.externalId,
        identity.isPrimary ? 1 : 0,
        identity.createdAt,
        identity.updatedAt,
        restaurant.id,
        restaurant.updatedAt,
      )
    ))
    await database.batch([
      database.prepare(RESTAURANT_PLACE_IDENTITY_CLEAR_PRIMARY).bind(
        primaryIdentity.updatedAt,
        restaurant.id,
        restaurant.id,
        restaurant.updatedAt,
      ),
      ...identityStatements,
    ])
  }
  const changed = restaurants.filter((_, index) => Number(results[index]?.meta.changes ?? 0) > 0)
  await recordUnversionedSyncChanges(database, changed.map((restaurant) => ({
    userId: restaurant.userId ?? 'owner',
    entityType: 'restaurant',
    entityId: restaurant.id,
    updatedAt: restaurant.updatedAt,
    deletedAt: restaurant.deletedAt,
  })))
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
    visit.partySize ?? 0,
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
  const results = await runInChunks(database, statements)
  const changed = visits.filter((_, index) => Number(results[index]?.meta.changes ?? 0) > 0)
  await recordUnversionedSyncChanges(database, changed.map((visit) => ({
    userId: visit.userId ?? 'owner',
    entityType: 'visit',
    entityId: visit.id,
    updatedAt: visit.updatedAt,
    deletedAt: visit.deletedAt,
  })))
  await upsertLegacyDishes(database, changed)
}

async function upsertLegacyDishes(database: D1Database, visits: CloudVisit[]) {
  for (const visit of visits) {
    const userId = visit.userId ?? 'owner'
    const current = await database.prepare('SELECT id, updated_at, deleted_at FROM dishes WHERE user_id = ? AND visit_id = ?')
      .bind(userId, visit.id).all<{ id: string; updated_at: string; deleted_at: string | null }>()
    const incomingIDs = new Set(visit.dishes.map((dish) => dish.id))
    const statements = visit.dishes.map((dish, index) => database.prepare(LEGACY_DISH_UPSERT).bind(
      dish.id, userId, visit.restaurantId, visit.id, dish.name, dish.taste,
      dish.rating, dish.price, dish.photoId, index, visit.createdAt, visit.updatedAt,
      visit.deletedAt,
    ))
    const removed = current.results.filter((dish) => !incomingIDs.has(dish.id) && !dish.deleted_at)
    statements.push(...removed.map((dish) => database.prepare(`UPDATE dishes
      SET deleted_at = ?, updated_at = ? WHERE id = ? AND user_id = ? AND deleted_at IS NULL`)
      .bind(visit.updatedAt, visit.updatedAt, dish.id, userId)))
    const results = await runInChunks(database, statements)
    const changes = [
      ...visit.dishes.map((dish, index) => ({
        id: dish.id,
        changed: Number(results[index]?.meta.changes ?? 0) > 0,
        deletedAt: visit.deletedAt,
      })),
      ...removed.map((dish, index) => ({
        id: dish.id,
        changed: Number(results[visit.dishes.length + index]?.meta.changes ?? 0) > 0,
        deletedAt: visit.updatedAt,
      })),
    ].filter((dish) => dish.changed)
    await recordUnversionedSyncChanges(database, changes.map((dish) => ({
      userId,
      entityType: 'dish',
      entityId: dish.id,
      updatedAt: visit.updatedAt,
      deletedAt: dish.deletedAt,
    })))
  }
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
  const results = await runInChunks(database, statements)
  const changed = photos.filter((_, index) => Number(results[index]?.meta.changes ?? 0) > 0)
  for (const photo of changed) {
    const userId = photo.userId ?? 'owner'
    await database.prepare(`UPDATE photos
      SET dish_id = (
        SELECT id FROM dishes
        WHERE user_id = ? AND photo_id = ? AND deleted_at IS NULL
        ORDER BY updated_at DESC LIMIT 1
      )
      WHERE id = ? AND user_id = ? AND kind = 'dish'`)
      .bind(userId, photo.id, photo.id, userId).run()
  }
  await recordUnversionedSyncChanges(database, changed.map((photo) => ({
    userId: photo.userId ?? 'owner',
    entityType: 'photo',
    entityId: photo.id,
    updatedAt: photo.updatedAt,
    deletedAt: photo.deletedAt,
  })))
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
  const profileStatements = users.map((user) => database.prepare(`INSERT INTO user_profiles (
    user_id, display_name, bio, city, avatar_photo_id, avatar_preset_id,
    visibility, created_at, updated_at, deleted_at, server_version,
    last_mutation_id
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)
  ON CONFLICT(user_id) DO UPDATE SET
    display_name = excluded.display_name, bio = excluded.bio, city = excluded.city,
    avatar_photo_id = excluded.avatar_photo_id,
    avatar_preset_id = excluded.avatar_preset_id,
    visibility = excluded.visibility, updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  WHERE excluded.updated_at > user_profiles.updated_at`)
    .bind(
      user.id, user.nickname.trim() || 'Taste Map 用户', user.bio.trim(), user.city.trim(),
      user.avatarPhotoId, user.avatarPresetId ?? 'polar-bear',
      user.mapSharingEnabled ? (user.mapVisibility ?? 'private') : 'private',
      user.createdAt, user.updatedAt, user.deletedAt,
    ))
  await runInChunks(database, profileStatements)
  await recordUnversionedSyncChanges(database, users.map((user) => ({
    userId: user.id,
    entityType: 'profile' as const,
    entityId: user.id,
    updatedAt: user.updatedAt,
    deletedAt: user.deletedAt,
  })))
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
  for (const item of lists) {
    const existing = await database.prepare('SELECT user_id FROM restaurant_lists WHERE id = ? LIMIT 1')
      .bind(item.id).first<{ user_id: string }>()
    if (existing && existing.user_id !== item.userId) {
      throw new RequestError('不能修改其他用户的榜单。', 403)
    }
  }
  const statements = lists.map((item) => database.prepare(RESTAURANT_LIST_UPSERT).bind(
    item.id, item.userId, item.title, item.description, item.visibility, item.isRanked ? 1 : 0,
    item.coverMode, item.customCoverPhotoId, item.createdAt, item.updatedAt, item.deletedAt,
  ))
  await runInChunks(database, statements)
  await recordUnversionedSyncChanges(database, lists.map((item) => ({
    userId: item.userId,
    entityType: 'restaurantList' as const,
    entityId: item.id,
    updatedAt: item.updatedAt,
    deletedAt: item.deletedAt,
  })))
}

async function upsertRestaurantListItems(database: D1Database, items: CloudRestaurantListItem[], viewerId: string) {
  for (const item of items) {
    const [parent, restaurant, existing] = await Promise.all([
      database.prepare('SELECT user_id FROM restaurant_lists WHERE id = ? LIMIT 1')
        .bind(item.listId).first<{ user_id: string }>(),
      database.prepare('SELECT user_id FROM restaurants WHERE id = ? LIMIT 1')
        .bind(item.restaurantId).first<{ user_id: string }>(),
      database.prepare('SELECT user_id FROM restaurant_list_items WHERE id = ? LIMIT 1')
        .bind(item.id).first<{ user_id: string | null }>(),
    ])
    if (!parent || parent.user_id !== viewerId || !restaurant || restaurant.user_id !== viewerId ||
      (existing?.user_id && existing.user_id !== viewerId)) {
      throw new RequestError('不能修改其他用户的榜单餐厅。', 403)
    }
  }
  const statements = items.map((item) => database.prepare(RESTAURANT_LIST_ITEM_UPSERT).bind(
    item.id, item.listId, item.restaurantId, item.position, item.note, item.createdAt, item.updatedAt, item.deletedAt,
  ))
  await runInChunks(database, statements)
  const identityStatements = items.map((item) => database.prepare(`UPDATE restaurant_list_items
    SET user_id = ?,
        restaurant_global_key = COALESCE((
          SELECT provider || ':' || external_id
          FROM restaurant_place_identities
          WHERE restaurant_id = ? AND user_id = ?
          ORDER BY is_primary DESC, updated_at ASC
          LIMIT 1
        ), 'manual:tastemap:' || restaurant_id)
    WHERE id = ? AND list_id IN (SELECT id FROM restaurant_lists WHERE user_id = ?)`)
    .bind(viewerId, item.restaurantId, viewerId, item.id, viewerId))
  await runInChunks(database, identityStatements)
  await recordUnversionedSyncChanges(database, items.map((item) => ({
    userId: viewerId,
    entityType: 'restaurantListItem' as const,
    entityId: item.id,
    updatedAt: item.updatedAt,
    deletedAt: item.deletedAt,
  })))
}

async function runInChunks(database: D1Database, statements: D1PreparedStatement[]) {
  const results: D1Result[] = []
  for (let index = 0; index < statements.length; index += 50) {
    results.push(...await database.batch(statements.slice(index, index + 50)))
  }
  return results
}

async function readSnapshot(database: D1Database, userId = 'owner', since: string | null = null): Promise<CloudSnapshot> {
  const updatedFilter = since ? ' AND updated_at > ?' : ''
  const bindSince = <T extends D1PreparedStatement>(statement: T) => since ? statement.bind(userId, since) : statement.bind(userId)
  const [restaurantResult, visitResult, photoResult, userResult, friendshipResult, sharedMealResult, participantResult, restaurantListResult, restaurantListItemResult, restaurantIdentityResult] = await database.batch([
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
    database.prepare(`SELECT i.* FROM restaurant_place_identities i
      JOIN restaurants r ON r.id = i.restaurant_id
      WHERE r.user_id = ?
      ORDER BY i.restaurant_id ASC, i.is_primary DESC, i.updated_at ASC`).bind(userId),
  ])
  const identitiesByRestaurant = groupRestaurantPlaceIdentities(
    restaurantIdentityResult.results as unknown as RestaurantPlaceIdentityRow[],
  )
  const clientUserId = (id: string) => id === userId ? 'owner' : id
  return {
    restaurants: (restaurantResult.results as unknown as RestaurantRow[]).map((row) => ({
      ...rowToRestaurant(row, identitiesByRestaurant.get(row.id)),
      userId: 'owner',
    })),
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
    restaurants: (restaurantResult.results as unknown as RestaurantRow[]).map((row) => rowToRestaurant(row)),
  }
}

interface ViewerIdentity {
  id: string
  email: string | null
  authProvider: 'apple' | 'cloudflare-access' | 'local'
  authSubject: string | null
  testMembership?: 'premium' | 'free'
  authenticatedAt?: string
  sessionId?: string
  storeEnvironment?: 'Sandbox' | 'Production'
}

async function resolveViewer(request: Request, database: D1Database): Promise<ViewerIdentity> {
  const hostname = new URL(request.url).hostname
  if ((typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && (hostname === 'localhost' || hostname === '127.0.0.1')) {
    const localTestUser = request.headers.get('X-Taste-Map-Test-User')
    if (localTestUser === 'free-tester') return { id: 'free-tester', email: null, authProvider: 'local', authSubject: null, testMembership: 'free' }
    return { id: 'owner', email: null, authProvider: 'local', authSubject: null, testMembership: 'premium' }
  }
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

async function resolveSyncViewer(request: Request, env: Env): Promise<ViewerIdentity> {
  const authenticated = await authenticateAccessToken(request, env.DB)
  if (authenticated) {
    return {
      id: authenticated.id,
      email: authenticated.email,
      authProvider: 'apple',
      authSubject: null,
      authenticatedAt: authenticated.authenticatedAt,
      sessionId: authenticated.sessionId,
      storeEnvironment: authenticated.storeEnvironment,
    }
  }
  if (env.APP_ENVIRONMENT === 'production') {
    if (env.SYNC_AUTH_MODE === 'development-test') {
      throw new SyncV1RequestError('Development authentication is forbidden in Production.', 503)
    }
    throw new SyncV1RequestError('A verified Taste Map session is required.', 401)
  }
  const hostname = new URL(request.url).hostname
  if ((typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && (hostname === 'localhost' || hostname === '127.0.0.1')) {
    const requestedUser = request.headers.get('X-Taste-Map-Test-User')?.trim() || 'owner'
    if (!/^[a-zA-Z0-9:_-]{1,80}$/.test(requestedUser)) {
      throw new SyncV1RequestError('Development sync identity is invalid.', 400)
    }
    await ensureDevelopmentSyncUser(env.DB, requestedUser)
    return {
      id: requestedUser,
      email: null,
      authProvider: 'local',
      authSubject: null,
      testMembership: requestedUser === 'free-tester' ? 'free' : 'premium',
    }
  }
  if ((typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && env.SYNC_AUTH_MODE === 'development-test') {
    if (env.APP_ENVIRONMENT !== 'development') {
      throw new SyncV1RequestError('Development sync authentication is not allowed in this environment.', 503)
    }
    const requestedUser = request.headers.get('X-Taste-Map-Test-User')?.trim()
    if (!requestedUser) throw new SyncV1RequestError('Development sync identity is required.', 401)
    if (!/^[a-zA-Z0-9:_-]{1,80}$/.test(requestedUser)) {
      throw new SyncV1RequestError('Development sync identity is invalid.', 400)
    }
    await ensureDevelopmentSyncUser(env.DB, requestedUser)
    return {
      id: requestedUser,
      email: null,
      authProvider: 'local',
      authSubject: null,
      testMembership: requestedUser === 'free-tester' ? 'free' : 'premium',
    }
  }
  if (env.SYNC_AUTH_MODE !== 'cloudflare-access') {
    throw new SyncV1RequestError('Production sync authentication is not configured.', 503)
  }
  if (!request.headers.get('Cf-Access-Authenticated-User-Email') || !request.headers.get('Cf-Access-Jwt-Assertion')) {
    throw new SyncV1RequestError('Sync authentication is required.', 401)
  }
  return resolveViewer(request, env.DB)
}

async function ensureDevelopmentSyncUser(database: D1Database, userId: string) {
  const now = new Date().toISOString()
  const active = await database.prepare(`INSERT INTO users (
    id, auth_provider, nickname, bio, city, created_at, updated_at, is_test_user
  ) VALUES (?, 'local', ?, '', '', ?, ?, 1)
  ON CONFLICT(id) DO UPDATE SET updated_at = users.updated_at
  WHERE users.deleted_at IS NULL
  RETURNING deleted_at`).bind(userId, `Development ${userId}`, now, now)
    .first<{ deleted_at: string | null }>()
  if (!active) throw new SyncV1RequestError('Deleted account cannot be restored by a stale client.', 401)
}

function isMembershipAdmin(request: Request, env: Env, viewer: ViewerIdentity) {
  // Internal authority is always server configured; localhost/test identities cannot grant.
  if (viewer.authProvider === 'local' || viewer.testMembership) return false
  const ids = (env.MEMBERSHIP_ADMIN_USER_IDS ?? '').split(',').map((item) => item.trim()).filter(Boolean)
  return ids.includes(viewer.id)
}

function requireMembershipAdmin(request: Request, env: Env, viewer: ViewerIdentity) {
  if (!isMembershipAdmin(request, env, viewer)) throw new RequestError('没有会员管理权限。', 403)
}

export async function readEffectiveMembership(database: D1Database, userId: string, storeEnvironment: 'Sandbox' | 'Production' = 'Production') {
  if (storeEnvironment === 'Production') await settlePremiumRewards(database,userId)
  const table = storeEnvironment === 'Sandbox' ? 'sandbox_membership_entitlements' : 'membership_entitlements'
  const result = await database.prepare(`SELECT * FROM ${table}
    WHERE user_id = ? ORDER BY created_at DESC`).bind(userId).all<MembershipEntitlementRow>()
  const entitlements = result.results.map(rowToMembershipEntitlement)
  const now = Date.now()
  const active = entitlements.filter((item) => item.status === 'active' && item.revokedAt === null
    && new Date(item.startsAt).getTime() <= now
    && (item.isLifetime || (item.expiresAt !== null && new Date(item.expiresAt).getTime() > now)))
  const primary = [...active].sort((left, right) => {
    // Gift identity wins display precedence. Access is the union of all active sources.
    const priority = (source: string) => source === 'gift_lifetime' ? 4 : source === 'gift_annual' ? 3 : source.startsWith('app_store_') ? 2 : 1
    if (priority(left.source) !== priority(right.source)) return priority(right.source) - priority(left.source)
    if (left.isLifetime !== right.isLifetime) return left.isLifetime ? -1 : 1
    return (right.expiresAt ? new Date(right.expiresAt).getTime() : 0) - (left.expiresAt ? new Date(left.expiresAt).getTime() : 0) || left.id.localeCompare(right.id)
  })[0]
  // A Gift's displayed end includes only contiguous Reward intervals, never Apple dates.
  let effectiveExpiry = primary?.expiresAt ?? null
  if (primary && !primary.isLifetime && !primary.source.startsWith('app_store_') && effectiveExpiry) {
    for (const reward of entitlements.filter(e=>e.source==='referral_reward' && e.status==='active')
      .sort((a,b)=>a.startsAt.localeCompare(b.startsAt))) {
      if (reward.startsAt <= effectiveExpiry && reward.expiresAt && reward.expiresAt > effectiveExpiry) effectiveExpiry = reward.expiresAt
    }
  }
  return {
    isPremium: Boolean(primary),
    source: primary?.source ?? null,
    startsAt: primary?.startsAt ?? null,
    startedAt: primary?.startsAt ?? null,
    expiresAt: effectiveExpiry,
    isLifetime: primary?.isLifetime ?? false,
    entitlements,
  }
}

async function readViewerMembership(database: D1Database, viewer: ViewerIdentity) {
  if ((typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && viewer.testMembership === 'premium') {
    const startsAt = '2026-01-01T00:00:00.000Z'
    return {
      isPremium: true,
      source: 'admin_grant' as const,
      startsAt,
      expiresAt: null,
      isLifetime: true,
      entitlements: [{
        id: 'local-premium-owner', userId: viewer.id, source: 'admin_grant' as const,
        startsAt, expiresAt: null, isLifetime: true, status: 'active' as const,
        note: '本地全功能测试账号', createdAt: startsAt, updatedAt: startsAt, revokedAt: null,
      }],
    }
  }
  if ((typeof __TASTEMAP_DEVELOPMENT_TOOLS__ === 'undefined' || __TASTEMAP_DEVELOPMENT_TOOLS__) && viewer.testMembership === 'free') {
    return { isPremium: false, source: null, startsAt: null, expiresAt: null, isLifetime: false, entitlements: [] }
  }
  return readEffectiveMembership(database, viewer.id, viewer.storeEnvironment)
}

async function searchMembershipUsers(database: D1Database, query: string) {
  const keyword = query.trim()
  const result = keyword
    ? await database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL
        AND (id = ? OR nickname LIKE ? OR COALESCE(email, '') LIKE ? OR city LIKE ?)
        ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, nickname LIMIT 30`).bind(keyword, `%${keyword}%`, `%${keyword}%`, `%${keyword}%`, keyword).all<UserRow>()
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

export async function mutateMembership(database: D1Database, actorUserId: string, request: Request) {
  const body = await request.json().catch(() => null) as Record<string, unknown> | null
  if (!body || typeof body.action !== 'string') throw new RequestError('会员操作格式不正确。', 400)
  const now = new Date()
  const nowIso = now.toISOString()

  if (body.action === 'grant') {
    if (body.source !== undefined && body.source !== 'gift_annual' && body.source !== 'gift_lifetime') throw new RequestError('赠送来源无效。', 400)
    if (typeof body.userId !== 'string') throw new RequestError('请选择要赠送会员的用户。', 400)
    const exists = await database.prepare('SELECT id FROM users WHERE id = ? AND deleted_at IS NULL').bind(body.userId).first()
    if (!exists) throw new RequestError('没有找到这个用户。', 404)
    const duration = body.source === 'gift_annual' ? '1y' : body.source === 'gift_lifetime' ? 'lifetime' : body.duration
    if (duration !== '1y' && duration !== 'lifetime') throw new RequestError('只能赠送 Premium 1 年或永久。', 400)
    const expiresAt = membershipExpiry(now, duration, typeof body.expiresAt === 'string' ? body.expiresAt : null)
    const isLifetime = duration === 'lifetime'
    const note = typeof body.note === 'string' ? body.note.slice(0, 160) : ''
    const id = `membership:${crypto.randomUUID()}`
    await database.prepare(`INSERT INTO membership_entitlements (
      id, user_id, source, starts_at, expires_at, is_lifetime, status, note, metadata_json,
      created_by_user_id, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, 'active', ?, '{}', ?, ?, ?)`)
      .bind(id, body.userId, isLifetime ? 'gift_lifetime' : 'gift_annual', nowIso, expiresAt, isLifetime ? 1 : 0, note, actorUserId, nowIso, nowIso).run()
    await refreshMembershipTier(database, body.userId)
    return { entitlement: await readEffectiveMembership(database, body.userId) }
  }

  if (body.action === 'extend' || body.action === 'note') {
    if (typeof body.entitlementId !== 'string') throw new RequestError('会员权益无效。', 400)
    const before = await database.prepare(`SELECT * FROM membership_entitlements WHERE id = ? AND source IN ('gift_annual', 'gift_lifetime') AND status = 'active'`)
      .bind(body.entitlementId).first<MembershipEntitlementRow>()
    if (!before) throw new RequestError('只能操作未撤销的 Gift。', 404)
    if (body.action === 'extend' && before.source !== 'gift_annual') throw new RequestError('永久会员无需延长。', 400)
    const expiresAt = body.action === 'extend'
      ? membershipExpiry(new Date(Math.max(now.getTime(), Date.parse(before.expires_at!))), '1y', null)
      : before.expires_at
    const note = typeof body.note === 'string' ? body.note.slice(0, 160) : before.note
    const result = await database.prepare(`UPDATE membership_entitlements SET expires_at = ?, note = ?, updated_at = ?, updated_by_user_id = ?
      WHERE id = ? AND status = 'active' AND updated_at = ? AND expires_at IS ?`)
      .bind(expiresAt, note, nowIso, actorUserId, before.id, before.updated_at, before.expires_at).run()
    if (!result.meta.changes) throw new RequestError('权益已被其他操作更新，请刷新后重试。', 409)
    await refreshMembershipTier(database, before.user_id)
    return { entitlement: await readEffectiveMembership(database, before.user_id) }
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
    const before = await database.prepare(`SELECT * FROM membership_entitlements WHERE id = ? AND source IN ('gift_annual', 'gift_lifetime', 'admin_grant') AND status = 'active'`)
      .bind(body.entitlementId).first<MembershipEntitlementRow>()
    if (!before) throw new RequestError('只能撤销管理员赠送，真实购买不会受影响。', 404)
    const reason = typeof body.reason === 'string' ? body.reason.slice(0, 160) : ''
    const note = typeof body.note === 'string' && body.note.trim() ? body.note.slice(0, 160) : before.note
    await database.prepare(`UPDATE membership_entitlements SET status = 'revoked', revoked_at = ?, revoked_by_user_id = ?, updated_at = ?, updated_by_user_id = ?, note = ? WHERE id = ? AND status = 'active'`)
      .bind(nowIso, actorUserId, nowIso, actorUserId, note, before.id).run()
    const after = await database.prepare('SELECT * FROM membership_entitlements WHERE id = ?').bind(before.id).first<MembershipEntitlementRow>()
    if (before.source === 'admin_grant') await writeMembershipAudit(database, actorUserId, before.user_id, 'revoke', before.id, before, after, reason)
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
  const day = expires.getUTCDate()
  expires.setUTCDate(1)
  expires.setUTCMonth(expires.getUTCMonth() + months)
  const lastDay = new Date(Date.UTC(expires.getUTCFullYear(), expires.getUTCMonth() + 1, 0)).getUTCDate()
  expires.setUTCDate(Math.min(day, lastDay))
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
    startedAt: row.starts_at,
    grantedAt: row.created_at,
    grantedBy: row.created_by_user_id,
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

const PUBLIC_RESTAURANT_CUISINES = new Set([
  '中餐', '日料', '日本料理', '韩餐', '韩国料理', '西餐', '法餐', '意大利菜', '泰国菜', '东南亚菜',
  '杭帮菜', '江浙菜', '川菜', '粤菜', '湘菜', '火锅', '烧烤', '咖啡', '甜品', '小吃', '面馆', '快餐',
])

async function readPublicRestaurant(database: D1Database, publicRestaurantId: string) {
  // A stable share identifier is not authorization by itself. Only restaurants
  // backed by a currently public Visit on a public Profile are eligible.
  const result = await database.prepare(`SELECT DISTINCT r.* FROM restaurants r
    JOIN visits v ON v.restaurant_id = r.id AND v.deleted_at IS NULL AND v.visibility = 'public'
    JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      AND up.visibility = 'public'
    WHERE r.deleted_at IS NULL ORDER BY r.updated_at DESC LIMIT 5000`).all()
  const rows = result.results as unknown as RestaurantRow[]
  const matchingRows: RestaurantRow[] = []
  for (const row of rows) {
    if (await publicRestaurantIdForRow(row) === publicRestaurantId) matchingRows.push(row)
  }
  if (!matchingRows.length) throw new RequestError('没有找到这家餐厅，或公开链接已经失效。', 404)

  const canonical = [...matchingRows].sort((left, right) => publicRestaurantCompleteness(right) - publicRestaurantCompleteness(left))[0]
  const placeholders = matchingRows.map(() => '?').join(', ')
  const visits = await database.prepare(`
    SELECT v.user_id, v.rating
    FROM visits v
    JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      AND up.visibility = 'public'
    WHERE v.deleted_at IS NULL
      AND v.visibility = 'public'
      AND v.rating IS NOT NULL
      AND v.restaurant_id IN (${placeholders})
  `).bind(...matchingRows.map((row) => row.id)).all()
  const ratingsByUser = new Map<string, number[]>()
  for (const visit of visits.results as unknown as Array<{ user_id: string; rating: number }>) {
    const ratings = ratingsByUser.get(visit.user_id) ?? []
    ratings.push(Number(visit.rating) * 2)
    ratingsByUser.set(visit.user_id, ratings)
  }
  const userRatings = [...ratingsByUser.values()].map((ratings) => ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length)
  const sampleCount = userRatings.length
  const publicRating = sampleCount >= 5 ? {
    value: Math.round((userRatings.reduce((sum, rating) => sum + rating, 0) / sampleCount) * 10) / 10,
    sampleCount,
    confidence: sampleCount < 10 ? 'low' : 'normal',
  } : null

  return {
    publicRestaurantId,
    name: canonical.name,
    coverImageUrl: canonical.merchant_image_url || null,
    cuisines: parseStringArray(canonical.tags_json).filter((tag) => PUBLIC_RESTAURANT_CUISINES.has(tag)).slice(0, 3),
    pricePerPerson: canonical.price_per_person,
    city: canonical.city,
    address: canonical.address,
    phone: canonical.phone,
    openingHours: canonical.opening_hours,
    publicRating,
  }
}

async function publicRestaurantIdForRow(row: RestaurantRow) {
  const identity = row.amap_poi_id
    ? `amap:${row.amap_poi_id}`
    : `restaurant:${normalizePublicIdentity(row.name)}|${normalizePublicIdentity(row.city)}|${normalizePublicIdentity(row.address)}`
  return shortHash(`taste-map-public:${identity}`)
}

function normalizePublicIdentity(value: string) {
  return value.trim().toLocaleLowerCase().replace(/\s+/g, '')
}

function escapeSQLLike(value: string) {
  return value.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')
}

function publicRestaurantCompleteness(row: RestaurantRow) {
  return Number(Boolean(row.merchant_image_url)) * 8 + Number(Boolean(row.phone)) * 4 + Number(Boolean(row.opening_hours)) * 4 +
    Number(Boolean(row.address)) * 2 + Number(Boolean(row.price_per_person)) + parseStringArray(row.tags_json).length
}

async function readCommunity(database: D1Database, viewerId: string, requestedMode: string, requestedCity: string, trendWindow: 7 | 30, isPremium = false) {
  const mode = ['following', 'for_you', 'similar', 'latest', 'trending'].includes(requestedMode) ? requestedMode : 'for_you'
  const [visitsResult, restaurantsResult, usersResult, followsResult, wantsResult] = await database.batch([
    database.prepare(`SELECT v.* FROM visits v
      JOIN users u ON u.id = v.user_id AND u.deleted_at IS NULL
      WHERE v.deleted_at IS NULL AND (
        v.user_id = ? OR (
          v.visibility = 'public' AND u.map_sharing_enabled = 1 AND u.map_visibility = 'public'
        )
      ) ORDER BY v.visited_at DESC LIMIT 5000`).bind(viewerId),
    database.prepare(`SELECT * FROM restaurants WHERE deleted_at IS NULL AND id IN (
      SELECT restaurant_id FROM visits WHERE deleted_at IS NULL
    )`),
    database.prepare(`SELECT * FROM users WHERE deleted_at IS NULL AND id IN (
      SELECT user_id FROM visits WHERE deleted_at IS NULL
    )`),
    database.prepare(`SELECT * FROM follows WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT w.restaurant_id, w.created_at FROM want_to_go w
      JOIN users u ON u.id = w.user_id AND u.deleted_at IS NULL
      WHERE w.deleted_at IS NULL AND u.map_sharing_enabled = 1 AND u.map_visibility = 'public'
      ORDER BY w.created_at DESC LIMIT 3000`),
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
  const similarityByUser = new Map(calculateTasteSimilarities(signals, viewerId).map((item) => [item.userId, item]))
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
      similarity: tasteSimilarityForDisplay(similarityByUser.get(row.user_id)),
      recommendationReason: null as string | null,
    }]
  })
  const ratedHistoryCount = visitRows.filter((visit) => visit.user_id === viewerId && visit.rating).length
  const viewerHistoryVisits = visitRows.filter((visit) => visit.user_id === viewerId)
  const deepRecommendation = isPremium && ratedHistoryCount >= 12
  const publicRatings = aggregatePublicRestaurantRatings(visitRows)
  let selected = candidates
  if (mode === 'following') selected = candidates.filter((item) => followedUserIds.has(item.row.user_id))
  if (mode === 'for_you') selected = personalizedCandidates(candidates.filter((item) => !viewerVisitedRestaurantIds.has(item.restaurant.id)), visitRows.flatMap((row) => {
    const restaurant = restaurants.get(row.restaurant_id)
    return row.user_id === viewerId && row.rating && restaurant ? [{ restaurant, ratingOutOfTen: Number(row.rating) * 2 }] : []
  }), defaultCity)
  if (mode === 'similar' && !isPremium) selected = []
  if (mode === 'similar' && isPremium) selected = uniqueCandidatesByRestaurant(candidates
    .filter((item) => {
      const evidence = similarityByUser.get(item.row.user_id)
      return evidence && evidence.evidenceState !== 'insufficient' && Number(item.row.rating) >= 3.75 &&
        item.restaurant.city.trim().replace(/市$/, '') === defaultCity.trim().replace(/市$/, '')
    })
    .sort((a, b) => Number(b.row.rating) - Number(a.row.rating) ||
      similarityByUser.get(b.row.user_id)!.weightedSimilarity - similarityByUser.get(a.row.user_id)!.weightedSimilarity || b.row.visited_at.localeCompare(a.row.visited_at))
    .map(item => ({ ...item, recommendationReason: `与你共同评过${similarityByUser.get(item.row.user_id)!.sharedRestaurantCount}家餐厅，双方对高低分的判断较接近。` })))
  if (mode === 'latest' && requestedCity) selected = candidates.filter((item) => item.restaurant.city === defaultCity)
  if (mode === 'trending') selected = trendingCandidates(candidates, wantsResult.results as Array<{ restaurant_id: string; created_at: string }>, defaultCity, now, trendWindow)
  return {
    mode, city: defaultCity,
    access: {
      entitlementTier: isPremium ? 'premium' : 'free',
      experienceTier: mode === 'for_you' && deepRecommendation ? 'deep' : 'basic',
      profileConfidence: ratedHistoryCount >= 12 ? 'ready' : 'insufficient',
      advancedFiltersEnabled: isPremium,
      fullExplanationEnabled: deepRecommendation,
      similarTasteEnabled: isPremium,
      message: isPremium
        ? deepRecommendation
          ? '深度推荐已开启 · 结合长期口味、近期偏好和重复到访进行排序'
          : '你的口味正在形成 · 继续积累评分后会自动启用深度推荐'
        : null,
    },
    items: selected.slice(0, 160).map(({ row, restaurant, user, similarity, recommendationReason }, index) => {
      const reasons = mode === 'for_you'
        ? buildRecommendationReasons(restaurant, viewerHistoryVisits, restaurants, row, now, visitRows.length < 5000)
        : []
      const isExploration = reasons.some((reason) => reason.code === 'SHORT_TERM_DIVERSITY')
      const primaryLimit = deepRecommendation ? 3 : 1
      const primaryReasons = reasons.slice(0, primaryLimit)
      const primaryTexts = new Set(primaryReasons.map((item) => item.text))
      const secondaryReasons = deepRecommendation ? reasons.filter((item) => !primaryTexts.has(item.text)).slice(0, 5) : []
      return {
        visit: rowToVisit(row),
        restaurant: { id: restaurant.id, amapPoiId: restaurant.amap_poi_id, name: restaurant.name, address: restaurant.address, city: restaurant.city, latitude: restaurant.latitude, longitude: restaurant.longitude, merchantImageUrl: restaurant.merchant_image_url, phone: restaurant.phone, openingHours: restaurant.opening_hours, pricePerPerson: restaurant.price_per_person, tags: parseStringArray(restaurant.tags_json), markerEmoji: restaurant.marker_emoji },
        user, similarity: similarity === null ? null : Math.round(similarity * 100),
        recommendationReason: primaryReasons[0]?.text ?? recommendationReason,
        recommendationReasons: mode === 'for_you' ? reasons.map((item) => item.text) : undefined,
        primaryReasons: mode === 'for_you' ? primaryReasons : undefined,
        secondaryReasons: mode === 'for_you' ? secondaryReasons : undefined,
        recommendationFitLevel: mode === 'for_you' ? recommendationFitLevel(index, deepRecommendation, reasons.length, isExploration) : undefined,
        isExploration,
        publicRating: publicRatings.get(restaurant.id) ?? { value: null, sampleCount: 0 },
        recommendationType: mode === 'similar' ? 'similar_taste' : mode === 'trending' ? 'trending' : mode === 'for_you' ? 'for_you' : null,
        recommendationRank: index + 1,
        recommendationConfidence: recommendationConfidence(mode, similarity, ratedHistoryCount),
        reasonCodes: mode === 'for_you' ? reasons.map((item) => item.code) : recommendationReasonCodes(mode, similarity, recommendationReason),
        surface: 'discover',
      }
    }),
  }
}

function buildRecommendationReasons(restaurant: RestaurantRow, viewerVisits: VisitRow[], restaurants: Map<string, RestaurantRow>, candidateVisit: VisitRow, now: number, completeHistory: boolean) {
  // This legacy endpoint still caps rows. A truncated prefix cannot establish
  // complete historical means, repeat counts, or a last-year absence.
  if (!completeHistory) return []
  const byPlace = new Map<string, { record: RestaurantRow; visits: VisitRow[] }>()
  for (const visit of viewerVisits) {
    const record = restaurants.get(visit.restaurant_id)
    if (visit.deleted_at != null || !record || record.deleted_at != null) continue
    const key = record.amap_poi_id?.trim() || record.id
    const group = byPlace.get(key) ?? { record, visits: [] }
    group.visits.push(visit); byPlace.set(key, group)
  }
  const bill = (visit: VisitRow) => visit.total_price != null && Number.isFinite(visit.total_price) && visit.total_price > 0 && visit.party_size_optional != null && Number.isInteger(visit.party_size_optional) && visit.party_size_optional > 0 ? visit.total_price / visit.party_size_optional : null
  const history = [...byPlace].map(([canonicalID, { record, visits }]) => {
    const ratings = visits.flatMap(visit => visit.rating != null && Number.isFinite(Number(visit.rating)) && Number(visit.rating) > 0 && Number(visit.rating) <= 5 ? [Number(visit.rating)] : [])
    const prices = visits.flatMap(visit => { const value = bill(visit); return value != null ? [value] : [] })
    const dates = visits.map(visit => visit.visited_at).sort()
    return { canonicalID, name: record.name, tags: parseStringArray(record.tags_json),
      pricePerPerson: prices.length ? prices.reduce((sum, value) => sum + value, 0) / prices.length : null, priceReliable: prices.length > 0,
      firstVisitedAt: dates[0], lastVisitedAt: dates[dates.length - 1],
      referenceRatingOutOfFive: visits.filter(visit => visit.rating != null && visit.rating >= 4 && visit.rating <= 5).sort((a, b) => b.visited_at.localeCompare(a.visited_at))[0]?.rating ?? null,
      ratingCount: ratings.length, ratingSumOutOfFive: ratings.reduce((sum, value) => sum + value, 0), visitCount: visits.length }
  })
  const pricePerPerson = bill(candidateVisit)
  return recommendationHistoryReasons({ tags: parseStringArray(restaurant.tags_json), pricePerPerson, priceReliable: pricePerPerson != null,
    explorationEligible: candidateVisit.rating != null && candidateVisit.rating >= 4 }, history, { now })
}

function recommendationFitLevel(index: number, deep: boolean, evidenceCount: number, exploration: boolean) {
  if (exploration) return 'EXPLORATION'
  if (deep && evidenceCount >= 2 && index < 12) return 'STRONG_MATCH'
  if (evidenceCount >= 1) return 'GOOD_MATCH'
  return 'MODERATE_MATCH'
}

function aggregatePublicRestaurantRatings(visits: VisitRow[]) {
  const byRestaurantAndUser = new Map<string, number[]>()
  visits.forEach((visit) => {
    if (visit.visibility !== 'public' || visit.rating == null) return
    const key = `${visit.restaurant_id}\u0000${visit.user_id}`
    byRestaurantAndUser.set(key, [...(byRestaurantAndUser.get(key) ?? []), Number(visit.rating) * 2])
  })
  const byRestaurant = new Map<string, number[]>()
  byRestaurantAndUser.forEach((ratings, key) => {
    const restaurantId = key.split('\u0000')[0]
    const userAverage = ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length
    byRestaurant.set(restaurantId, [...(byRestaurant.get(restaurantId) ?? []), userAverage])
  })
  return new Map([...byRestaurant.entries()].map(([restaurantId, ratings]) => [restaurantId, {
    value: Math.round((ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length) * 10) / 10,
    sampleCount: ratings.length,
  }]))
}

function recommendationConfidence(mode: string, similarity: number | null, viewerRatedCount: number) {
  if (mode === 'for_you') return viewerRatedCount >= 12 ? 'high' : viewerRatedCount >= 4 ? 'medium' : 'low'
  if (mode === 'similar') return similarity !== null && similarity >= .78 ? 'high' : similarity !== null ? 'medium' : 'low'
  if (mode === 'trending') return 'medium'
  return 'low'
}

function recommendationReasonCodes(mode: string, similarity: number | null, reason: string | null) {
  if (mode === 'trending') return ['TRENDING']
  if (mode === 'similar') return ['SIMILAR_USERS']
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
  const qualityCandidates = candidates.filter((item) => item.row.rating == null || Number(item.row.rating) * 2 >= 5.5)
  if (viewerHistory.length < 3) {
    return uniqueCandidatesByRestaurant(qualityCandidates.filter((item) => item.restaurant.city === city)
      .sort((left, right) => Number(right.row.rating ?? 0) - Number(left.row.rating ?? 0) || right.row.visited_at.localeCompare(left.row.visited_at)))
      .slice(0, 60)
      .map((item) => ({ ...item, recommendationReason: '基于当前城市公开高分记录的初步推荐' }))
  }
  const rankedTags = rankTasteTags(viewerHistory.map((signal) => ({ tags: parseStringArray(signal.restaurant.tags_json), restaurantKey: signal.restaurant.amap_poi_id, ratingOutOfTen: signal.ratingOutOfTen })))
  const tagValues = new Map(rankedTags.map((item) => [item.tag.trim().toLocaleLowerCase(), item]))
  const byRestaurant = new Map<string, { item: typeof candidates[number]; score: number }>()
  qualityCandidates.filter((item) => item.restaurant.city === city).forEach((item) => {
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
  const result = await database.prepare(`SELECT * FROM follows
    WHERE (follower_id = ? OR followed_user_id = ?) AND deleted_at IS NULL
    ORDER BY created_at DESC`).bind(viewerId, viewerId).all<FollowRow>()
  const clientUserId = (id: string) => id === viewerId ? 'owner' : id
  return { follows: result.results.map((row) => ({ id: row.id, followerId: clientUserId(row.follower_id), followedUserId: clientUserId(row.followed_user_id), createdAt: row.created_at })) }
}

async function mutateFollow(database: D1Database, viewerId: string, request: Request) {
  const body = await readObjectBody(request)
  if (typeof body.userId !== 'string' || body.userId === viewerId) throw new RequestError('关注用户无效。', 400)
  const id = `follow:${viewerId}:${body.userId}`
  if (body.action === 'remove') {
    const now = new Date().toISOString()
    await database.prepare(`UPDATE follows SET deleted_at = ?, updated_at = ?,
      server_version = server_version + 1
      WHERE follower_id = ? AND followed_user_id = ? AND deleted_at IS NULL`)
      .bind(now, now, viewerId, body.userId).run()
    return { removed: true }
  }
  if (body.action !== 'add') throw new RequestError('关注操作无效。', 400)
  const now = new Date().toISOString()
  await database.prepare(`INSERT INTO follows (
    id, follower_id, followed_user_id, created_at, updated_at, deleted_at, server_version
  ) VALUES (?, ?, ?, ?, ?, NULL, 1)
  ON CONFLICT(id) DO UPDATE SET deleted_at = NULL, updated_at = excluded.updated_at,
    server_version = follows.server_version + 1`)
    .bind(id, viewerId, body.userId, now, now).run()
  return { id, followerId: viewerId, followedUserId: body.userId }
}

async function searchUsers(database: D1Database, viewerId: string, query: string) {
  const keyword = query.trim()
  if ([...keyword].length < 2) return { users: [] }
  const like = `%${escapeSQLLike(keyword.toLocaleLowerCase())}%`
  const result = await database.prepare(`SELECT u.*,
      p.display_name AS public_display_name, p.bio AS public_bio,
      p.city AS public_city, p.avatar_photo_id AS public_avatar_photo_id,
      p.avatar_preset_id AS public_avatar_preset_id, p.created_at AS public_created_at
    FROM users u JOIN user_profiles p ON p.user_id = u.id
    WHERE u.id != ? AND u.deleted_at IS NULL AND p.deleted_at IS NULL
      AND p.visibility = 'public'
      AND (LOWER(p.display_name) LIKE ? ESCAPE '\\' OR LOWER(p.city) LIKE ? ESCAPE '\\')
    ORDER BY LOWER(p.display_name), u.id LIMIT 20`)
    .bind(viewerId, like, like).all<UserRow & {
      public_display_name: string
      public_bio: string
      public_city: string
      public_avatar_photo_id: string | null
      public_avatar_preset_id: AvatarPresetId
      public_created_at: string
    }>()
  return { users: result.results.map((row) => publicUser({
    ...row,
    nickname: row.public_display_name,
    bio: row.public_bio,
    city: row.public_city,
    avatar_photo_id: row.public_avatar_photo_id,
    avatar_preset_id: row.public_avatar_preset_id,
    created_at: row.public_created_at,
  })) }
}

interface FriendRecommendationVisitRow {
  user_id: string
  rating: number
  amap_poi_id: string
  tags_json: string
}

async function readFriendRecommendations(database: D1Database, viewerId: string, allowTestUsers: boolean) {
  const [viewer, usersResult, friendshipsResult, companionsResult, visitsResult] = await Promise.all([
    database.prepare('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL').bind(viewerId).first<UserRow>(),
    database.prepare(`SELECT * FROM users
      WHERE id != ? AND deleted_at IS NULL
        AND map_sharing_enabled = 1 AND map_visibility != 'private'
      ORDER BY nickname LIMIT 300`).bind(viewerId).all<UserRow>(),
    database.prepare(`SELECT * FROM friendships
      WHERE requester_id = ? OR addressee_id = ? OR status = 'accepted'
      ORDER BY updated_at DESC`).bind(viewerId, viewerId).all<FriendshipRow>(),
    database.prepare(`SELECT linked_user_id FROM dining_companions
      WHERE owner_user_id = ? AND linked_user_id IS NOT NULL AND deleted_at IS NULL`).bind(viewerId).all<{ linked_user_id: string }>(),
    database.prepare(`SELECT v.user_id, v.rating, r.amap_poi_id, r.tags_json
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
      JOIN users u ON u.id = v.user_id AND u.deleted_at IS NULL
      WHERE v.deleted_at IS NULL AND r.deleted_at IS NULL AND v.rating IS NOT NULL
        AND (v.user_id = ? OR (
          v.visibility = 'public' AND u.map_sharing_enabled = 1 AND u.map_visibility = 'public'
        ))`).bind(viewerId).all<FriendRecommendationVisitRow>(),
  ])
  if (!viewer) return { recommendations: [] }

  const friendshipRows = friendshipsResult.results
  const excluded = new Set<string>()
  const acceptedNeighbors = new Map<string, Set<string>>()
  const addAcceptedNeighbor = (first: string, second: string) => {
    const neighbors = acceptedNeighbors.get(first) ?? new Set<string>()
    neighbors.add(second)
    acceptedNeighbors.set(first, neighbors)
  }
  const rejectionCutoff = Date.now() - 30 * 24 * 60 * 60 * 1000
  friendshipRows.forEach((row) => {
    if (row.status === 'accepted') {
      addAcceptedNeighbor(row.requester_id, row.addressee_id)
      addAcceptedNeighbor(row.addressee_id, row.requester_id)
    }
    if (row.requester_id !== viewerId && row.addressee_id !== viewerId) return
    const otherId = row.requester_id === viewerId ? row.addressee_id : row.requester_id
    if (row.status === 'accepted' || row.status === 'pending') excluded.add(otherId)
    if (row.status === 'rejected' && Date.parse(row.updated_at) >= rejectionCutoff) excluded.add(otherId)
  })

  const linkedCompanionIds = new Set(companionsResult.results.map((row) => row.linked_user_id))
  const signals = visitsResult.results.map((row) => ({
    userId: row.user_id,
    poiId: row.amap_poi_id,
    ratingOutOfTen: Number(row.rating) * 2,
    tags: parseStringArray(row.tags_json),
  }))
  const similarities = new Map(calculateTasteSimilarities(signals, viewerId).map((item) => [item.userId, item]))
  const ratedPoisByUser = new Map<string, Set<string>>()
  visitsResult.results.forEach((row) => {
    const pois = ratedPoisByUser.get(row.user_id) ?? new Set<string>()
    pois.add(row.amap_poi_id)
    ratedPoisByUser.set(row.user_id, pois)
  })
  const viewerPois = ratedPoisByUser.get(viewerId) ?? new Set<string>()
  const viewerFriends = acceptedNeighbors.get(viewerId) ?? new Set<string>()
  const candidatesById = new Map(usersResult.results.filter((user) => allowTestUsers || !user.is_test_user).filter((user) => !excluded.has(user.id)).map((user) => [user.id, user]))
  const ranked = rankFriendRecommendations([...candidatesById.values()].map((candidate) => {
    const candidateFriends = acceptedNeighbors.get(candidate.id) ?? new Set<string>()
    const candidatePois = ratedPoisByUser.get(candidate.id) ?? new Set<string>()
    const similarity = similarities.get(candidate.id)
    return {
      userId: candidate.id,
      mutualFriendCount: [...viewerFriends].filter((friendId) => candidateFriends.has(friendId)).length,
      linkedCompanion: linkedCompanionIds.has(candidate.id),
      tasteSimilarity: tasteSimilarityForDisplay(similarity),
      tasteSignalCount: similarity?.evidenceState === 'sufficient' ? similarity.signalCount : 0,
      sharedRestaurantCount: [...viewerPois].filter((poiId) => candidatePois.has(poiId)).length,
      sameCity: Boolean(viewer.city.trim() && candidate.city.trim() && viewer.city.trim().toLocaleLowerCase() === candidate.city.trim().toLocaleLowerCase()),
    }
  }))
  return {
    recommendations: ranked.slice(0, 24).flatMap((recommendation) => {
      const user = candidatesById.get(recommendation.userId)
      return user ? [{ ...recommendation, user: publicUser(user), friendshipState: null }] : []
    }),
  }
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
        schemaVersion: 1, id: restaurantId, userId: viewerId,
        placeIdentities: [{ provider: 'amap', externalId: fact.restaurant.amapPoiId, isPrimary: true, createdAt: now, updatedAt: now }],
        ...fact.restaurant, status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null, openingHours: null, markerType: fact.restaurant.merchantImageUrl ? 'image' : 'emoji', markerPhotoId: null, markerEmoji: '🍽️', createdAt: now, updatedAt: now, deletedAt: null,
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
        : friendship
          ? "visibility IN ('public', 'friends')"
          : "visibility = 'public'"
  const canViewRestaurantCollection = profileId === viewerId || Boolean(
    user.map_sharing_enabled
    && user.map_visibility !== 'private'
    && (user.map_visibility !== 'friends' || friendship),
  )
  const [visitsResult, restaurantsResult, wantRestaurantsResult, followerResult, followingResult, followersResult, followingUsersResult] = await database.batch([
    database.prepare(`SELECT * FROM visits WHERE user_id = ? AND deleted_at IS NULL AND ${visibilitySql} ORDER BY visited_at DESC`).bind(profileId),
    database.prepare(`SELECT * FROM restaurants WHERE id IN (
      SELECT restaurant_id FROM visits WHERE user_id = ? AND deleted_at IS NULL AND ${visibilitySql}
    ) AND deleted_at IS NULL`).bind(profileId),
    database.prepare(`SELECT * FROM restaurants
      WHERE user_id = ? AND status = 'wantToGo' AND deleted_at IS NULL
      AND ${canViewRestaurantCollection ? '1 = 1' : '1 = 0'}
      ORDER BY updated_at DESC`).bind(profileId),
    database.prepare('SELECT COUNT(*) AS count FROM follows WHERE followed_user_id = ? AND deleted_at IS NULL').bind(profileId),
    database.prepare('SELECT COUNT(*) AS count FROM follows WHERE follower_id = ? AND deleted_at IS NULL').bind(profileId),
    database.prepare(`SELECT u.* FROM follows f
      JOIN users u ON u.id = f.follower_id
      WHERE f.followed_user_id = ? AND f.deleted_at IS NULL AND u.deleted_at IS NULL
      ORDER BY f.created_at DESC`).bind(profileId),
    database.prepare(`SELECT u.* FROM follows f
      JOIN users u ON u.id = f.followed_user_id
      WHERE f.follower_id = ? AND f.deleted_at IS NULL AND u.deleted_at IS NULL
      ORDER BY f.created_at DESC`).bind(profileId),
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
    wantRestaurants: (wantRestaurantsResult.results as unknown as RestaurantRow[]).map((row) => rowToRestaurant(row)),
    followerCount: Number((followerResult.results[0] as { count?: number } | undefined)?.count ?? 0),
    followingCount: Number((followingResult.results[0] as { count?: number } | undefined)?.count ?? 0),
    followers: (followersResult.results as unknown as UserRow[]).map(publicUser),
    following: (followingUsersResult.results as unknown as UserRow[]).map(publicUser),
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
  return { id: row.id, nickname: row.nickname, bio: row.bio, city: row.city, avatarImageData: row.avatar_image_data, avatarPhotoId: row.avatar_photo_id, avatarPresetId: row.avatar_preset_id ?? 'polar-bear', membershipTier: row.membership_tier ?? 'free', createdAt: row.created_at }
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

function rowToRestaurant(row: RestaurantRow, identities?: RestaurantPlaceIdentity[]): CloudRestaurant {
  const placeIdentities = identities?.length ? identities : [{
    provider: 'amap' as const,
    externalId: row.amap_poi_id,
    isPrimary: true,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }]
  return {
    schemaVersion: 1,
    id: row.id,
    userId: row.user_id,
    placeIdentities,
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
    websiteUrl: row.website_url,
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
    partySize: row.party_size_optional ?? (row.party_size >= 1 ? row.party_size : null),
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

function normalizeCloudRestaurant(value: unknown): CloudRestaurant {
  try {
    const restaurant = decodeRestaurantJSONContract(value)
    if (!restaurant.amapPoiId) {
      throw new RestaurantContractError('旧版 /api/sync 暂时需要 amapPoiId；Apple Maps-only 写入将在 P0-B 接入。')
    }
    return { ...restaurant, amapPoiId: restaurant.amapPoiId }
  } catch (error) {
    if (error instanceof RestaurantContractError) throw error
    throw new RestaurantContractError('Restaurant JSON contract 无法识别。')
  }
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
  if (!origin || origin === url.origin) return true
  if (origin === productionEnvironment.publicWebOrigin &&
      url.origin === productionEnvironment.apiBaseURL) return true

  // Vite's local proxy rewrites the request host to the Worker port while
  // preserving the browser Origin. Treat loopback-to-loopback traffic as the
  // same local app, but keep the strict equality rule everywhere else.
  if (typeof __TASTEMAP_DEVELOPMENT_TOOLS__ !== 'undefined' && !__TASTEMAP_DEVELOPMENT_TOOLS__) return false
  try {
    const originUrl = new URL(origin)
    const loopbackHosts = new Set(['localhost', '127.0.0.1', '[::1]', '::1'])
    return loopbackHosts.has(originUrl.hostname) && loopbackHosts.has(url.hostname)
  } catch {
    return false
  }
}

function observedDuration(value: number) {
  return Math.round(Math.max(0, value) * 100) / 100
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
