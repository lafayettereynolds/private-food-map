import {
  COMMUNITY_API_VERSION,
  COMMUNITY_DEFAULT_LIMIT,
  COMMUNITY_MAX_LIMIT,
  type CommunityFeedPageV1,
  type CommunityFeedScopeV1,
  type PublicContentCacheScopeV1,
  type PublicContentItemV1,
  type PublicContentPhotoV1,
  type PublicContentPlaceIdentityV1,
  type PublicContentRestaurantV1,
  type PublicContentSectionV1,
  type PublicContentStatisticsV1,
  type PublicContentUserV1,
  type PublicProfileOverviewV1,
  type PublicContentViewerStateV1,
  type PublicProfileContentPageV1,
} from '../src/contracts/communityContract'
import { DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE } from '../src/contracts/discoveryContract'
import type { ProfileAvatarPresetContract, ProfileVisibilityContract } from '../src/contracts/profileContract'
import type { RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { DISCOVERY_FILTER_TAXONOMY } from '../src/contracts/discoveryFilterTaxonomy'
import { readDiscoveryQuery, matchesDiscoveryHardFilters, readPublicFilterStatistics, DISCOVERY_FILTER_CAPABILITIES,
  DISCOVERY_PHOTO_SCAN_LIMIT, assertCompleteDiscoveryPhotos, DiscoveryQueryError } from './discoveryHardFilters'
import { consumePublicAPIQuota } from './publicAPIRateLimit'
import { engagementForVisits } from './communityInteractionsV1'
import { communityCityKey, communityRestaurantCitySQL, decodeCommunityFeedCursor, encodeCommunityFeedCursor } from './communityCityQuery'
import {
  loadActivityPhotoPool,
  RestaurantUGCImagePool,
  resolveRestaurantVisualSelection,
  type RestaurantUGCPhotoRecord,
  type RestaurantUGCPhotoSelection,
} from './restaurantUGCImagePool'

const MAX_NOTE_LENGTH = 1_200

interface ContentRow {
  visit_id: string
  user_id: string
  restaurant_id: string
  visited_at: string
  rating: number | null
  note: string
  visit_visibility: 'public' | 'friends'
  visit_updated_at: string
  restaurant_name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags_json: string
  price_per_person: number | null
  merchant_image_url: string | null
  marker_emoji: string
  profile_display_name: string
  profile_bio: string
  profile_city: string
  profile_avatar_photo_id: string | null
  profile_avatar_preset_id: ProfileAvatarPresetContract
  profile_visibility: ProfileVisibilityContract
}

interface WantRow {
  restaurant_id: string
  user_id: string
  updated_at: string
  restaurant_name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags_json: string
  price_per_person: number | null
  merchant_image_url: string | null
  marker_emoji: string
  profile_display_name: string
  profile_bio: string
  profile_city: string
  profile_avatar_photo_id: string | null
  profile_avatar_preset_id: ProfileAvatarPresetContract
  profile_visibility: ProfileVisibilityContract
}

interface IdentityRow {
  restaurant_id: string
  provider: RestaurantPlaceProvider
  external_id: string
  is_primary: number
}

interface CommunityPhotoRow extends RestaurantUGCPhotoRecord {
  restaurant_name: string
  address: string
  city: string
  latitude: number
  longitude: number
}
interface FriendshipRow {
  id: string
  requester_id: string
  addressee_id: string
  status: string
  deleted_at: string | null
}
interface ProfileRow {
  user_id: string
  display_name: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract
  visibility: ProfileVisibilityContract
  created_at: string
  deleted_at: string | null
}

export class CommunityV1RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

export async function handleCommunityV1(
  request: Request,
  database: D1Database,
  viewerId: string,
): Promise<CommunityFeedPageV1 | PublicProfileContentPageV1 | PublicProfileOverviewV1> {
  if (request.method !== 'GET') throw new CommunityV1RequestError('Community method is not supported.', 405)
  await consumePublicAPIQuota(database, viewerId, 'community-read', 180)
  const url = new URL(request.url)
  if (url.pathname === '/api/v1/community/feed') return readFeed(database, viewerId, url)
  const contentMatch = url.pathname.match(/^\/api\/v1\/community\/users\/([^/]+)\/content$/)
  if (contentMatch) {
    return readPublicContent(database, viewerId, decodeURIComponent(contentMatch[1]), url)
  }
  const overviewMatch = url.pathname.match(/^\/api\/v1\/community\/users\/([^/]+)\/overview$/)
  if (overviewMatch) {
    return readPublicOverview(database, viewerId, decodeURIComponent(overviewMatch[1]))
  }
  throw new CommunityV1RequestError('Community endpoint was not found.', 404)
}

async function readFeed(database: D1Database, viewerId: string, url: URL): Promise<CommunityFeedPageV1> {
  const scope = (url.searchParams.get('scope') ?? 'following') as CommunityFeedScopeV1
  if (scope !== 'following' && scope !== 'latest') throw new CommunityV1RequestError('Community feed scope is invalid.', 400)
  const limit = pageLimit(url)
  const filtersQuery = readDiscoveryQuery(url, scope)
  const requestedCity = url.searchParams.get('city') ?? ''
  if (requestedCity.length > 80 || /[\u0000-\u001f\u007f]/u.test(requestedCity)) throw new CommunityV1RequestError('Community city is invalid.', 400)
  const city = communityCityKey(requestedCity)
  const queryScope = { viewerId, scope, city, query: filtersQuery.fingerprint }
  let cursor: ReturnType<typeof decodeCommunityFeedCursor>
  try { cursor = decodeCommunityFeedCursor(url.searchParams.get('cursor'), queryScope) }
  catch { throw new CommunityV1RequestError('Community cursor does not match this city or feed. Refresh and retry.', 400) }
  const snapshot = cursor.snapshot ?? Date.now()
  const snapshotISO = new Date(snapshot).toISOString()
  const relationClause = scope === 'following' ? `AND (
    EXISTS (SELECT 1 FROM follows ff WHERE ff.follower_id = ? AND ff.followed_user_id = v.user_id AND ff.deleted_at IS NULL)
  )` : ''
  const bindings: unknown[] = [viewerId, viewerId, viewerId, viewerId]
  if (scope === 'following') bindings.unshift(viewerId)
  if (scope === 'following') bindings.push(viewerId)
  if (city) bindings.push(city)
  bindings.push(snapshotISO)
  const query = `SELECT ${visitProjection}
    FROM visits v
    JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
    JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
    WHERE ${scope === 'following' ? 'v.user_id <> ? AND' : ''} v.deleted_at IS NULL AND COALESCE(v.is_test_data, 0) = 0
      AND v.rating <= 5 AND v.rating >= ${DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE} AND (
      (v.visibility = 'public' AND up.visibility = 'public') OR (
        v.visibility IN ('public', 'friends') AND up.visibility IN ('public', 'friends') AND
        EXISTS (SELECT 1 FROM friendships vf WHERE vf.status = 'accepted' AND vf.deleted_at IS NULL AND (
          (vf.requester_id = ? AND vf.addressee_id = v.user_id) OR
          (vf.requester_id = v.user_id AND vf.addressee_id = ?)
        ))
      )
    ) AND NOT EXISTS (
      SELECT 1 FROM user_blocks ub WHERE ub.deleted_at IS NULL AND (
        (ub.blocker_user_id = ? AND ub.blocked_user_id = v.user_id) OR
        (ub.blocker_user_id = v.user_id AND ub.blocked_user_id = ?)
      )
    ) AND NOT EXISTS (SELECT 1 FROM content_reports cr WHERE cr.status = 'actioned' AND (
      (cr.content_type = 'visit' AND cr.content_id = v.id) OR (cr.content_type = 'user' AND cr.content_id = v.user_id)))
    ${relationClause}
      ${city ? `AND ${communityRestaurantCitySQL} = ?` : ''}
      AND v.visited_at <= ?
      AND (v.visited_at < ? OR (v.visited_at = ? AND v.id > ?))
    ORDER BY v.visited_at DESC, v.id ASC LIMIT ?`
  // Scan qualified activity rows until a full matching page plus lookahead is
  // found. Filtering the previous LIMIT 20 hydration silently hid older matches.
  const matched: Array<{ row: ContentRow; item: PublicContentItemV1 }> = []
  let scanCursor = { eventAt: cursor.eventAt, id: cursor.id }
  let scanned = 0
  while (matched.length <= limit) {
    const rows = await database.prepare(query).bind(...bindings, scanCursor.eventAt, scanCursor.eventAt, scanCursor.id, 50).all<ContentRow>()
    if (!rows.results.length) break
    scanned += rows.results.length
    if (scanned > 5_000) throw new DiscoveryQueryError('This feed exceeds the supported filter scan capacity. Choose a city or narrow the query.', 503, 'discovery_capacity_exceeded')
    const hydrated = await hydrateVisits(database, viewerId, rows.results)
    const filters = filtersQuery.filters
    const statistics = filters.minimumPublicRatingUsers !== null || filters.minimumPublicScoreOutOfTen !== null
      ? await readPublicFilterStatistics(database, viewerId, rows.results.map(row => row.restaurant_id), snapshotISO)
      : new Map<string, { score: number | null; users: number }>()
    for (const [index, item] of hydrated.entries()) {
      const row = rows.results[index]
      const stats = statistics.get(row.restaurant_id)
      if (matchesDiscoveryHardFilters({ ...item.restaurant,
        publicScoreOutOfTen: stats?.score ?? null, publicRatingUsers: stats?.users ?? 0,
        viewerState: item.viewerState, actualPhoto: !!item.restaurant.photo || !!item.visit?.photos.length,
      }, filters)) matched.push({ row, item })
      if (matched.length > limit) break
    }
    const tail = rows.results.at(-1)!
    scanCursor = { eventAt: tail.visited_at, id: tail.visit_id }
    if (rows.results.length < 50) break
  }
  const visible = matched.slice(0, limit)
  const items = visible.map(entry => entry.item)
  return {
    apiVersion: COMMUNITY_API_VERSION,
    scope,
    city,
    filterCapabilities: DISCOVERY_FILTER_CAPABILITIES,
    filterTaxonomy: DISCOVERY_FILTER_TAXONOMY,
    appliedQuery: { filters: filtersQuery.filters, sort: filtersQuery.sort, preferences: filtersQuery.preferences },
    generatedAt: new Date(snapshot).toISOString(),
    items,
    nextCursor: matched.length > limit && visible.length
      ? encodeCommunityFeedCursor(visible.at(-1)!.row.visited_at, visible.at(-1)!.row.visit_id, snapshot, queryScope)
      : null,
  }
}

async function readPublicContent(
  database: D1Database,
  viewerId: string,
  targetUserId: string,
  url: URL,
): Promise<PublicProfileContentPageV1> {
  const section = (url.searchParams.get('section') ?? 'visits') as PublicContentSectionV1
  if (section !== 'visits' && section !== 'want_to_go') {
    throw new CommunityV1RequestError('Public content section is invalid.', 400)
  }
  const access = await profileAccess(database, viewerId, targetUserId)
  if (!access.permitted) throw new CommunityV1RequestError('Public Profile was not found.', 404)
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const snapshot = cursor.snapshot ?? Date.now()
  const snapshotISO = new Date(snapshot).toISOString()
  const visibilityClause = viewerId === targetUserId
    ? "v.visibility IN ('public', 'friends')"
    : access.friend
      ? "v.visibility IN ('public', 'friends')"
      : "v.visibility = 'public'"
  const statistics = await visibleStatistics(database, targetUserId, visibilityClause, access.permitted)
  let items: PublicContentItemV1[]
  let hasMore = false
  let tailEventAt = ''
  let tailID = ''
  if (section === 'visits') {
    const rows = await database.prepare(`SELECT ${visitProjection}
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}
        AND v.visited_at <= ? AND (v.visited_at < ? OR (v.visited_at = ? AND v.id > ?))
      ORDER BY v.visited_at DESC, v.id ASC LIMIT ?`)
      .bind(targetUserId, snapshotISO, cursor.eventAt, cursor.eventAt, cursor.id, limit + 1).all<ContentRow>()
    const visible = rows.results.slice(0, limit)
    items = await hydrateVisits(database, viewerId, visible)
    hasMore = rows.results.length > limit
    tailEventAt = visible.at(-1)?.visited_at ?? ''
    tailID = visible.at(-1)?.visit_id ?? ''
  } else {
    const rows = await database.prepare(`SELECT r.id AS restaurant_id, r.user_id, r.updated_at,
        r.name AS restaurant_name, r.address, r.city, r.latitude, r.longitude,
        r.tags_json, r.price_per_person, r.merchant_image_url, r.marker_emoji,
        up.display_name AS profile_display_name, up.bio AS profile_bio,
        up.city AS profile_city, up.avatar_photo_id AS profile_avatar_photo_id,
        up.avatar_preset_id AS profile_avatar_preset_id, up.visibility AS profile_visibility
      FROM restaurants r JOIN user_profiles up ON up.user_id = r.user_id AND up.deleted_at IS NULL
      WHERE r.user_id = ? AND r.status = 'wantToGo' AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
        AND r.updated_at <= ? AND (r.updated_at < ? OR (r.updated_at = ? AND r.id > ?))
      ORDER BY r.updated_at DESC, r.id ASC LIMIT ?`)
      .bind(targetUserId, snapshotISO, cursor.eventAt, cursor.eventAt, cursor.id, limit + 1).all<WantRow>()
    const visible = rows.results.slice(0, limit)
    items = await hydrateWants(
      database, viewerId, visible,
      access.visibility === 'friends' ? 'friends' : 'public',
    )
    hasMore = rows.results.length > limit
    tailEventAt = visible.at(-1)?.updated_at ?? ''
    tailID = visible.at(-1)?.restaurant_id ?? ''
  }
  return {
    apiVersion: COMMUNITY_API_VERSION,
    targetUserId,
    section,
    generatedAt: new Date(snapshot).toISOString(),
    statistics,
    items,
    nextCursor: hasMore && tailID ? encodeCursor(tailEventAt, tailID, snapshot) : null,
  }
}

const visitProjection = `v.id AS visit_id, v.user_id, v.restaurant_id, v.visited_at,
  v.rating, v.note, v.visibility AS visit_visibility, v.updated_at AS visit_updated_at,
  r.name AS restaurant_name, r.address, r.city, r.latitude, r.longitude,
  r.tags_json, r.price_per_person, r.merchant_image_url, r.marker_emoji,
  up.display_name AS profile_display_name, up.bio AS profile_bio,
  up.city AS profile_city, up.avatar_photo_id AS profile_avatar_photo_id,
  up.avatar_preset_id AS profile_avatar_preset_id, up.visibility AS profile_visibility`

async function hydrateVisits(database: D1Database, viewerId: string, rows: ContentRow[]) {
  if (!rows.length) return []
  const restaurantIDs = unique(rows.map((row) => row.restaurant_id))
  const visitIDs = unique(rows.map((row) => row.visit_id))
  const [identityResult, friendshipResult, followResult, viewerRestaurantResult, viewerIdentityResult] = await database.batch([
    database.prepare(`SELECT restaurant_id, provider, external_id, is_primary FROM restaurant_place_identities
      WHERE restaurant_id IN (${placeholders(restaurantIDs)})`).bind(...restaurantIDs),
    database.prepare(`SELECT id, requester_id, addressee_id, status, deleted_at FROM friendships
      WHERE requester_id = ? OR addressee_id = ?`).bind(viewerId, viewerId),
    database.prepare(`SELECT followed_user_id FROM follows WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT id, status, name, address, city, latitude, longitude FROM restaurants
      WHERE user_id = ? AND deleted_at IS NULL AND COALESCE(is_test_data, 0) = 0`).bind(viewerId),
    database.prepare(`SELECT i.restaurant_id, i.provider, i.external_id, i.is_primary
      FROM restaurant_place_identities i JOIN restaurants r ON r.id = i.restaurant_id
      WHERE r.user_id = ? AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0`).bind(viewerId),
  ])
  const identities = identityMap(identityResult.results as unknown as IdentityRow[])
  const cities = unique(rows.map((row) => row.city))
  const photoResult = await database.prepare(`SELECT p.id, p.restaurant_id, p.visit_id, p.user_id, p.kind,
      p.storage_key, p.thumbnail_storage_key, p.sync_status,
      p.visibility, v.visibility AS visit_visibility, up.visibility AS profile_visibility,
      p.created_at, p.sort_order, r.marker_photo_id, p.deleted_at,
      CASE WHEN EXISTS (
        SELECT 1 FROM content_reports cr WHERE cr.status = 'actioned' AND (
          (cr.content_type = 'visit' AND cr.content_id = p.visit_id) OR
          (cr.content_type = 'user' AND cr.content_id = p.user_id)
        )
      ) THEN 0 ELSE 1 END AS moderation_eligible,
      r.name AS restaurant_name, r.address, r.city, r.latitude, r.longitude
    FROM photos p LEFT JOIN visits v ON v.id = p.visit_id AND v.user_id = p.user_id
    JOIN restaurants r ON r.id = p.restaurant_id AND r.user_id = p.user_id
    JOIN user_profiles up ON up.user_id = p.user_id AND up.deleted_at IS NULL
    WHERE p.kind IN ('visit', 'dish')
      AND p.deleted_at IS NULL AND (p.visit_id IS NULL OR (v.id IS NOT NULL AND v.deleted_at IS NULL))
      AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0 AND p.storage_provider = 'r2'
      AND r.city IN (${placeholders(cities)})
      AND NOT EXISTS (
        SELECT 1 FROM user_blocks pub WHERE pub.deleted_at IS NULL AND (
          (pub.blocker_user_id = ? AND pub.blocked_user_id = p.user_id) OR
          (pub.blocker_user_id = p.user_id AND pub.blocked_user_id = ?)
        )
      ) AND (
        (p.visit_id IN (${placeholders(visitIDs)}) AND (
          (p.visibility = 'public' AND (v.id IS NULL OR v.visibility = 'public')) OR
          (p.visibility = 'friends' AND v.visibility = 'friends')
        )) OR
        (p.visibility = 'public' AND (v.id IS NULL OR v.visibility = 'public') AND up.visibility = 'public')
      )
    AND p.sync_status = 'synced' AND LENGTH(TRIM(COALESCE(p.storage_key, ''))) > 0
    AND LENGTH(TRIM(COALESCE(p.thumbnail_storage_key, ''))) > 0
    AND (v.id IS NULL OR COALESCE(v.is_test_data, 0) = 0)
    ORDER BY p.sort_order ASC, p.created_at DESC, p.id ASC LIMIT ${DISCOVERY_PHOTO_SCAN_LIMIT + 1}`)
    .bind(...cities, viewerId, viewerId, ...visitIDs).all<CommunityPhotoRow>()
  const photoRows = photoResult.results
  assertCompleteDiscoveryPhotos(photoRows.length)
  const photoRestaurantIDs = unique(photoRows.map((photo) => photo.restaurant_id))
  const photoIdentityResult = photoRestaurantIDs.length
    ? await database.prepare(`SELECT restaurant_id, provider, external_id, is_primary
        FROM restaurant_place_identities WHERE restaurant_id IN (SELECT value FROM json_each(?))`)
      .bind(JSON.stringify(photoRestaurantIDs)).all<IdentityRow>()
    : { results: [] as IdentityRow[] }
  const photoIdentities = identityMap(photoIdentityResult.results)
  const imagePool = new RestaurantUGCImagePool(photoRows)
  const activityPool = await loadActivityPhotoPool(database, viewerId, visitIDs)
  const photoGlobalKeys = new Map(photoRows.map((photo) => [
    photo.restaurant_id,
    globalPlaceKey(photoIdentities.get(photo.restaurant_id) ?? [], photo),
  ]))
  const friendships = friendshipMap(friendshipResult.results as unknown as FriendshipRow[], viewerId)
  const follows = new Set((followResult.results as Array<{ followed_user_id: string }>).map((row) => row.followed_user_id))
  const viewerStates = buildViewerStates(
    viewerRestaurantResult.results as Array<{ id: string; status: string; name: string; address: string; city: string; latitude: number; longitude: number }>,
    viewerIdentityResult.results as unknown as IdentityRow[], rows, identities,
  )
  const engagements = await engagementForVisits(database, viewerId, visitIDs)
  return rows.map((row) => {
    // This pool's SQL already verified the viewer's current relationship. Photo
    // visibility can be narrower than its public Visit and must narrow the cache.
    const activityPhotos = activityPool.activityPhotos(row.visit_id, row.user_id, viewerId, true)
    const scope: PublicContentCacheScopeV1 = row.visit_visibility === 'friends' || row.profile_visibility === 'friends'
      || activityPhotos.some(({ photo }) => photo.visibility === 'friends' || photo.visit_visibility === 'friends' || photo.profile_visibility === 'friends')
      ? 'friends' : 'public'
    const targetKey = globalPlaceKey(identities.get(row.restaurant_id) ?? [], row)
    const relatedRestaurantIDs = unique([row.restaurant_id, ...photoRows.filter((photo) => photoGlobalKeys.get(photo.restaurant_id) === targetKey).map((photo) => photo.restaurant_id)])
    const selectedPhoto = resolveRestaurantVisualSelection(imagePool, {
      surface: 'latest',
      restaurantIDs: relatedRestaurantIDs,
      viewerID: viewerId,
      activityVisitID: row.visit_id,
      canSeeFriendsActivity: scope === 'friends',
    })
    const visitPhotos = activityPhotos.map((photo) => publicContentPhoto(photo)!)
    const place = restaurantProjection(row, identities.get(row.restaurant_id) ?? [], publicContentPhoto(selectedPhoto))
    return {
      id: `visit:${row.visit_id}`,
      kind: 'visit',
      eventAt: row.visited_at,
      updatedAt: row.visit_updated_at,
      user: userProjection(row, friendships.get(row.user_id), follows.has(row.user_id), viewerId),
      restaurant: place,
      visit: {
        id: row.visit_id,
        ownerUserId: row.user_id,
        restaurantGlobalKey: place.globalKey,
        visitedAt: row.visited_at,
        rating: row.rating === null ? null : Number(row.rating),
        note: row.note.trim() ? row.note.trim().slice(0, MAX_NOTE_LENGTH) : null,
        visibility: row.visit_visibility,
        photos: visitPhotos,
        updatedAt: row.visit_updated_at,
      },
      viewerState: viewerStates.get(place.globalKey) ?? 'none',
      cacheScope: scope,
      engagement: engagements.get(row.visit_id) ?? { likedByViewer: false, likeCount: 0, commentCount: 0 },
    } satisfies PublicContentItemV1
  })
}

async function hydrateWants(database: D1Database, viewerId: string, rows: WantRow[], cacheScope: PublicContentCacheScopeV1) {
  if (!rows.length) return []
  const ids = unique(rows.map((row) => row.restaurant_id))
  const [identityResult, friendshipResult, followResult, viewerRestaurantResult, viewerIdentityResult] = await database.batch([
    database.prepare(`SELECT restaurant_id, provider, external_id, is_primary FROM restaurant_place_identities
      WHERE restaurant_id IN (${placeholders(ids)})`).bind(...ids),
    database.prepare(`SELECT id, requester_id, addressee_id, status, deleted_at FROM friendships
      WHERE requester_id = ? OR addressee_id = ?`).bind(viewerId, viewerId),
    database.prepare(`SELECT followed_user_id FROM follows WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT id, status, name, address, city, latitude, longitude FROM restaurants
      WHERE user_id = ? AND deleted_at IS NULL AND COALESCE(is_test_data, 0) = 0`).bind(viewerId),
    database.prepare(`SELECT i.restaurant_id, i.provider, i.external_id, i.is_primary
      FROM restaurant_place_identities i JOIN restaurants r ON r.id = i.restaurant_id
      WHERE r.user_id = ? AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0`).bind(viewerId),
  ])
  const identities = identityMap(identityResult.results as unknown as IdentityRow[])
  const friendships = friendshipMap(friendshipResult.results as unknown as FriendshipRow[], viewerId)
  const follows = new Set((followResult.results as Array<{ followed_user_id: string }>).map((row) => row.followed_user_id))
  const asContentRows = rows.map((row) => ({
    restaurant_id: row.restaurant_id, restaurant_name: row.restaurant_name, address: row.address,
    city: row.city, latitude: row.latitude, longitude: row.longitude,
  }))
  const states = buildViewerStates(
    viewerRestaurantResult.results as Array<{ id: string; status: string; name: string; address: string; city: string; latitude: number; longitude: number }>,
    viewerIdentityResult.results as unknown as IdentityRow[], asContentRows, identities,
  )
  return rows.map((row) => {
    const restaurant = restaurantProjection(row, identities.get(row.restaurant_id) ?? [], null)
    return {
      id: `want_to_go:${row.user_id}:${restaurant.globalKey}`,
      kind: 'want_to_go', eventAt: row.updated_at, updatedAt: row.updated_at,
      user: userProjection(row, friendships.get(row.user_id), follows.has(row.user_id), viewerId),
      restaurant, visit: null, viewerState: states.get(restaurant.globalKey) ?? 'none', cacheScope,
      engagement: { likedByViewer: false, likeCount: 0, commentCount: 0 },
    } satisfies PublicContentItemV1
  })
}

async function readPublicOverview(
  database: D1Database,
  viewerId: string,
  targetUserId: string,
): Promise<PublicProfileOverviewV1> {
  const access = await profileAccess(database, viewerId, targetUserId)
  if (!access.permitted) throw new CommunityV1RequestError('Public Profile was not found.', 404)
  const visibilityClause = viewerId === targetUserId || access.friend
    ? "v.visibility IN ('public', 'friends')"
    : "v.visibility = 'public'"
  const [friendResult, followingResult, followerResult, targetWantsResult, viewerWantsResult,
    representativeResult, footprintResult, tasteResult, ratingResult] = await database.batch([
    database.prepare(`SELECT COUNT(*) AS count FROM friendships WHERE status = 'accepted'
      AND deleted_at IS NULL AND (requester_id = ? OR addressee_id = ?)`)
      .bind(targetUserId, targetUserId),
    database.prepare(`SELECT COUNT(*) AS count FROM follows WHERE follower_id = ? AND deleted_at IS NULL`)
      .bind(targetUserId),
    database.prepare(`SELECT COUNT(*) AS count FROM follows WHERE followed_user_id = ? AND deleted_at IS NULL`)
      .bind(targetUserId),
    database.prepare(`SELECT id, user_id, updated_at, name AS restaurant_name, address, city,
        latitude, longitude, tags_json, price_per_person, merchant_image_url, marker_emoji,
        '' AS profile_display_name, '' AS profile_bio, '' AS profile_city,
        NULL AS profile_avatar_photo_id, 'polar-bear' AS profile_avatar_preset_id,
        'public' AS profile_visibility,
        (SELECT provider FROM restaurant_place_identities i WHERE i.restaurant_id = restaurants.id
          ORDER BY is_primary DESC, updated_at ASC LIMIT 1) AS matched_provider,
        (SELECT external_id FROM restaurant_place_identities i WHERE i.restaurant_id = restaurants.id
          ORDER BY is_primary DESC, updated_at ASC LIMIT 1) AS matched_external_id
      FROM restaurants WHERE user_id = ? AND status = 'wantToGo' AND deleted_at IS NULL AND COALESCE(is_test_data, 0) = 0
      ORDER BY updated_at DESC, id ASC LIMIT 100`).bind(targetUserId),
    database.prepare(`SELECT i.provider, i.external_id FROM restaurants r
      JOIN restaurant_place_identities i ON i.restaurant_id = r.id
      WHERE r.user_id = ? AND r.status = 'wantToGo' AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0`)
      .bind(viewerId),
    database.prepare(`SELECT ${visitProjection}, COUNT(*) OVER (PARTITION BY v.restaurant_id) AS visit_count
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}
      ORDER BY visit_count DESC, v.visited_at DESC, v.id ASC LIMIT 6`).bind(targetUserId),
    database.prepare(`SELECT COALESCE(NULLIF(trim(r.city), ''), '未标注城市') AS city,
        COUNT(DISTINCT r.id) AS restaurant_count, COUNT(v.id) AS visit_count
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}
      GROUP BY COALESCE(NULLIF(trim(r.city), ''), '未标注城市')
      ORDER BY visit_count DESC, city ASC LIMIT 8`).bind(targetUserId),
    database.prepare(`SELECT r.tags_json FROM visits v
      JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}`)
      .bind(targetUserId),
    database.prepare(`SELECT AVG(v.rating) AS average_rating,
        SUM(CASE WHEN v.rating IS NOT NULL THEN 1 ELSE 0 END) AS rated_count
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}`).bind(targetUserId),
  ])

  const targetWants = targetWantsResult.results as unknown as Array<WantRow & {
    id: string; matched_provider: string | null; matched_external_id: string | null
  }>
  const viewerWantIdentities = new Set((viewerWantsResult.results as Array<{ provider: string; external_id: string }>)
    .map((row) => `${row.provider}:${row.external_id}`))
  const allCommonRows = targetWants.filter((row) => row.matched_provider && row.matched_external_id &&
    viewerWantIdentities.has(`${row.matched_provider}:${row.matched_external_id}`))
  const commonRows = allCommonRows.slice(0, 6)
  const allRestaurantIDs = unique([
    ...commonRows.map((row) => row.id),
    ...(representativeResult.results as unknown as ContentRow[]).map((row) => row.restaurant_id),
  ])
  const identitiesResult = allRestaurantIDs.length
    ? await database.prepare(`SELECT restaurant_id, provider, external_id, is_primary
        FROM restaurant_place_identities WHERE restaurant_id IN (${placeholders(allRestaurantIDs)})`)
      .bind(...allRestaurantIDs).all<IdentityRow>()
    : { results: [] as IdentityRow[] }
  const identities = identityMap(identitiesResult.results)
  const commonWantToGo = commonRows.map((row) => restaurantProjection({ ...row,
    restaurant_name: row.restaurant_name,
  }, identities.get(row.id) ?? [], null))

  const representativeRows = representativeResult.results as unknown as ContentRow[]
  const representativeRestaurants = uniqueBy(representativeRows, (row) => row.restaurant_id)
    .slice(0, 4)
    .map((row) => restaurantProjection(row, identities.get(row.restaurant_id) ?? [], null))
  const tagCounts = new Map<string, number>()
  for (const row of tasteResult.results as Array<{ tags_json: string }>) {
    for (const tag of parseTags(row.tags_json)) tagCounts.set(tag, (tagCounts.get(tag) ?? 0) + 1)
  }
  const topTags = [...tagCounts.entries()].sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .slice(0, 6).map(([tag]) => tag)
  const ratingRow = ratingResult.results[0] as { average_rating?: number | null; rated_count?: number | string } | undefined
  const ratedVisitCount = Number(ratingRow?.rated_count ?? 0)
  const averageRating = ratedVisitCount ? Number(Number(ratingRow?.average_rating).toFixed(1)) : null
  return {
    apiVersion: COMMUNITY_API_VERSION,
    targetUserId,
    friendCount: count(friendResult), followingCount: count(followingResult), followerCount: count(followerResult),
    commonWantToGoCount: allCommonRows.length, commonWantToGo, representativeRestaurants,
    footprints: (footprintResult.results as Array<{ city: string; restaurant_count: number; visit_count: number }>).map((row) => ({
      city: row.city, restaurantCount: Number(row.restaurant_count), visitCount: Number(row.visit_count),
    })),
    tasteSummary: {
      topTags, averageRating, ratedVisitCount,
      summary: topTags.length ? `常记录 ${topTags.slice(0, 3).join('、')}` : null,
    },
  }
}

async function profileAccess(database: D1Database, viewerId: string, targetUserId: string) {
  const profile = await database.prepare(`SELECT user_id, display_name, bio, city, avatar_photo_id,
      avatar_preset_id, visibility, created_at, deleted_at FROM user_profiles
    WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(targetUserId).first<ProfileRow>()
  if (!profile) return { permitted: false, friend: false, visibility: null as ProfileVisibilityContract | null }
  if (targetUserId !== viewerId && await database.prepare(`SELECT id FROM user_blocks
    WHERE deleted_at IS NULL AND (
      (blocker_user_id = ? AND blocked_user_id = ?) OR
      (blocker_user_id = ? AND blocked_user_id = ?)
    ) LIMIT 1`).bind(viewerId, targetUserId, targetUserId, viewerId).first()) {
    return { permitted: false, friend: false, visibility: profile.visibility }
  }
  const friend = targetUserId === viewerId || Boolean(await database.prepare(`SELECT id FROM friendships
    WHERE status = 'accepted' AND deleted_at IS NULL AND (
      (requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)
    ) LIMIT 1`).bind(viewerId, targetUserId, targetUserId, viewerId).first())
  return {
    permitted: targetUserId === viewerId || profile.visibility === 'public' ||
      (profile.visibility === 'friends' && friend),
    friend,
    visibility: profile.visibility,
  }
}

async function visibleStatistics(
  database: D1Database,
  targetUserId: string,
  visibilityClause: string,
  wantsVisible: boolean,
): Promise<PublicContentStatisticsV1> {
  const [visitResult, restaurantResult, wantResult] = await database.batch([
    database.prepare(`SELECT COUNT(*) AS count FROM visits v
      JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      WHERE v.user_id = ?
      AND v.deleted_at IS NULL AND ${visibilityClause}`).bind(targetUserId),
    database.prepare(`SELECT COUNT(DISTINCT v.restaurant_id) AS count FROM visits v
      JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}`).bind(targetUserId),
    database.prepare(`SELECT COUNT(*) AS count FROM restaurants WHERE user_id = ?
      AND status = 'wantToGo' AND deleted_at IS NULL AND COALESCE(is_test_data, 0) = 0 AND ${wantsVisible ? '1 = 1' : '1 = 0'}`).bind(targetUserId),
  ])
  return {
    visibleVisitCount: count(visitResult),
    visibleRestaurantCount: count(restaurantResult),
    visibleWantToGoCount: count(wantResult),
  }
}

function userProjection(
  row: Pick<ContentRow, 'user_id' | 'profile_display_name' | 'profile_bio' | 'profile_city' | 'profile_avatar_photo_id' | 'profile_avatar_preset_id'>,
  friendship: FriendshipRow | undefined,
  following: boolean,
  viewerId: string,
): PublicContentUserV1 {
  return {
    userId: row.user_id,
    displayName: row.profile_display_name,
    bio: row.profile_bio.trim() || null,
    city: row.profile_city.trim() || null,
    avatarPhotoId: row.profile_avatar_photo_id,
    avatarPresetId: row.profile_avatar_preset_id ?? 'polar-bear',
    friendshipId: friendship?.id ?? null,
    friendshipState: relationshipState(friendship, viewerId),
    isFollowing: following,
  }
}

function restaurantProjection(
  row: Pick<ContentRow, 'restaurant_name' | 'address' | 'city' | 'latitude' | 'longitude' | 'tags_json' | 'price_per_person' | 'merchant_image_url' | 'marker_emoji'>,
  rawIdentities: PublicContentPlaceIdentityV1[],
  photo: PublicContentPhotoV1 | null,
): PublicContentRestaurantV1 {
  const globalKey = globalPlaceKey(rawIdentities, row)
  return {
    globalKey,
    placeIdentities: normalizedIdentities(rawIdentities, globalKey),
    name: row.restaurant_name,
    address: row.address,
    city: row.city,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    tags: parseTags(row.tags_json).slice(0, 12),
    pricePerPerson: row.price_per_person === null ? null : Number(row.price_per_person),
    merchantImageUrl: safeHTTPSURL(row.merchant_image_url),
    markerEmoji: row.marker_emoji || '🍽️',
    photo,
  }
}

function buildViewerStates(
  viewerRestaurants: Array<{ id: string; status: string; name: string; address: string; city: string; latitude: number; longitude: number }>,
  viewerIdentities: IdentityRow[],
  contentRestaurants: Array<{ restaurant_id: string; restaurant_name: string; address: string; city: string; latitude: number; longitude: number }>,
  contentIdentityMap: Map<string, PublicContentPlaceIdentityV1[]>,
) {
  const contentKeys = new Map<string, string>()
  contentRestaurants.forEach((restaurant) => {
    const identities = contentIdentityMap.get(restaurant.restaurant_id) ?? []
    contentKeys.set(restaurant.restaurant_id, globalPlaceKey(identities, restaurant))
  })
  const identityToContent = new Map<string, string>()
  const fingerprintToContent = new Map<string, string>()
  contentIdentityMap.forEach((identities, restaurantID) => identities.forEach((identity) => {
    if (identity.provider !== 'manual') identityToContent.set(`${identity.provider}:${identity.externalId}`, contentKeys.get(restaurantID)!)
  }))
  contentRestaurants.forEach((restaurant) => {
    const fingerprint = placeFingerprint(restaurant)
    if (!fingerprintToContent.has(fingerprint)) {
      fingerprintToContent.set(fingerprint, contentKeys.get(restaurant.restaurant_id)!)
    }
  })
  const viewerIdentityMap = identityMap(viewerIdentities)
  const states = new Map<string, PublicContentViewerStateV1>()
  viewerRestaurants.forEach((restaurant) => {
    const identityMatch = (viewerIdentityMap.get(restaurant.id) ?? [])
      .map((identity) => identityToContent.get(`${identity.provider}:${identity.externalId}`))
      .find(Boolean)
    const fallbackKey = fingerprintToContent.get(placeFingerprint({
      restaurant_name: restaurant.name, address: restaurant.address, city: restaurant.city,
      latitude: restaurant.latitude, longitude: restaurant.longitude,
    }))
    const key = identityMatch ?? fallbackKey
    if (!key) return
    if (restaurant.status === 'visited') states.set(key, 'visited')
    else if (!states.has(key)) states.set(key, 'want_to_go')
  })
  return states
}

function identityMap(rows: IdentityRow[]) {
  const result = new Map<string, PublicContentPlaceIdentityV1[]>()
  rows.forEach((row) => result.set(row.restaurant_id, [...(result.get(row.restaurant_id) ?? []), {
    provider: row.provider, externalId: row.external_id, isPrimary: row.is_primary === 1,
  }]))
  return result
}

function publicContentPhoto(selection: RestaurantUGCPhotoSelection | null): PublicContentPhotoV1 | null
function publicContentPhoto(selection: RestaurantUGCPhotoSelection): PublicContentPhotoV1
function publicContentPhoto(selection: RestaurantUGCPhotoSelection | null): PublicContentPhotoV1 | null {
  if (!selection) return null
  const photo = selection.photo
  return {
    photoId: photo.id,
    photoKind: photo.kind ?? undefined,
    variant: 'thumbnail',
    sourceType: selection.sourceType === 'nonPublic' ? undefined : selection.sourceType,
    restaurantId: photo.restaurant_id,
    visitId: photo.visit_id,
    ownerUserId: photo.user_id,
    visibility: photo.visibility === 'private' ? undefined : photo.visibility,
    createdAt: photo.created_at,
    exportAllowed: selection.exportAllowed,
  }
}

function friendshipMap(rows: FriendshipRow[], viewerId: string) {
  return new Map(rows.filter((row) => !row.deleted_at && ['pending', 'accepted'].includes(row.status)).map((row) => [
    row.requester_id === viewerId ? row.addressee_id : row.requester_id, row,
  ]))
}

function relationshipState(row: FriendshipRow | undefined, viewerId: string) {
  if (!row || row.deleted_at || row.status === 'removed' || row.status === 'rejected') return 'none' as const
  if (row.status === 'accepted') return 'friends' as const
  return row.requester_id === viewerId ? 'outgoing_request' as const : 'incoming_request' as const
}

function normalizedIdentities(identities: PublicContentPlaceIdentityV1[], globalKey: string) {
  const values = uniqueBy(identities.filter((identity) => identity.provider !== 'manual' && identity.externalId.trim()),
    (identity) => `${identity.provider}:${identity.externalId}`)
    .sort((left, right) => `${left.provider}:${left.externalId}`.localeCompare(`${right.provider}:${right.externalId}`))
  if (!values.length) return [{ provider: 'manual' as const, externalId: globalKey, isPrimary: true }]
  const requested = values.find((identity) => identity.isPrimary) ?? values[0]
  return values.map((identity) => ({ ...identity, isPrimary: identity === requested }))
}

function globalPlaceKey(
  identities: PublicContentPlaceIdentityV1[],
  restaurant: { restaurant_name: string; address: string; city: string; latitude: number; longitude: number },
) {
  const source = unique(identities.filter((identity) => identity.provider !== 'manual' && identity.externalId.trim())
    .map((identity) => `${identity.provider}:${identity.externalId.trim()}`)).sort().join('|')
  return source ? `place:${stableHash(source)}` : placeFingerprint(restaurant).replace('fingerprint:', 'place:')
}

function placeFingerprint(restaurant: { restaurant_name: string; address: string; city: string; latitude: number; longitude: number }) {
  const source = `${normalize(restaurant.restaurant_name)}|${normalize(restaurant.city)}|${normalize(restaurant.address)}|${Math.round(Number(restaurant.latitude) * 1000)}|${Math.round(Number(restaurant.longitude) * 1000)}`
  return `fingerprint:${stableHash(source)}`
}

function stableHash(source: string) {
  let hash = 2166136261
  for (let index = 0; index < source.length; index += 1) {
    hash ^= source.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return (hash >>> 0).toString(16).padStart(8, '0')
}

function pageLimit(url: URL) {
  const value = Number(url.searchParams.get('limit') ?? COMMUNITY_DEFAULT_LIMIT)
  return Number.isInteger(value) ? Math.min(COMMUNITY_MAX_LIMIT, Math.max(1, value)) : COMMUNITY_DEFAULT_LIMIT
}

function encodeCursor(eventAt: string, id: string, snapshot: number) {
  const bytes = new TextEncoder().encode(JSON.stringify([eventAt, id, snapshot]))
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

function decodeCursor(raw: string | null) {
  if (!raw) return { eventAt: '9999-12-31T23:59:59.999Z', id: '', snapshot: null as number | null }
  try {
    const normalized = raw.replaceAll('-', '+').replaceAll('_', '/')
    const bytes = Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0))
    const value = JSON.parse(new TextDecoder().decode(bytes))
    if (Array.isArray(value) && value.length === 3 && typeof value[0] === 'string' &&
      typeof value[1] === 'string' && typeof value[2] === 'number' && Number.isFinite(value[2])) {
      return { eventAt: value[0], id: value[1], snapshot: value[2] }
    }
  } catch { /* invalid cursor */ }
  throw new CommunityV1RequestError('Community cursor is invalid.', 400)
}

function placeholders(values: unknown[]) { return values.map(() => '?').join(', ') }
function unique<T>(values: T[]) { return [...new Set(values)] }
function uniqueBy<T>(values: T[], key: (value: T) => string) { return [...new Map(values.map((value) => [key(value), value])).values()] }
function normalize(value: string) { return value.trim().toLocaleLowerCase().replaceAll(/\s+/g, '') }
function count(result: D1Result<unknown>) { return Number((result.results[0] as { count?: number | string } | undefined)?.count ?? 0) }
function parseTags(value: string) {
  try {
    const parsed = JSON.parse(value)
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === 'string' && item.trim().length > 0).map((item) => item.trim()) : []
  } catch { return [] }
}
function safeHTTPSURL(value: string | null) {
  if (!value) return null
  try { const url = new URL(value); return url.protocol === 'https:' ? url.toString() : null } catch { return null }
}
