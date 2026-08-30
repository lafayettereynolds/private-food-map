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
import type { ProfileAvatarPresetContract, ProfileVisibilityContract } from '../src/contracts/profileContract'
import type { RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { consumePublicAPIQuota } from './publicAPIRateLimit'
import { engagementForVisits } from './communityInteractionsV1'

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

interface PhotoRow { id: string; visit_id: string; visibility: 'public' | 'friends' }
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
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const snapshot = cursor.snapshot ?? Date.now()
  const snapshotISO = new Date(snapshot).toISOString()
  const relationClause = scope === 'following' ? `AND (
    EXISTS (SELECT 1 FROM follows ff WHERE ff.follower_id = ? AND ff.followed_user_id = v.user_id AND ff.deleted_at IS NULL)
    OR EXISTS (SELECT 1 FROM friendships fc WHERE fc.status = 'accepted' AND fc.deleted_at IS NULL AND (
      (fc.requester_id = ? AND fc.addressee_id = v.user_id) OR
      (fc.requester_id = v.user_id AND fc.addressee_id = ?)
    ))
  )` : ''
  const bindings: unknown[] = [viewerId, viewerId, viewerId, viewerId, viewerId]
  if (scope === 'following') bindings.push(viewerId, viewerId, viewerId)
  bindings.push(snapshotISO, cursor.eventAt, cursor.eventAt, cursor.id, limit + 1)
  const query = `SELECT ${visitProjection}
    FROM visits v
    JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
    JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
    WHERE v.user_id <> ? AND v.deleted_at IS NULL AND (
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
    ) ${relationClause}
      AND v.visited_at <= ?
      AND (v.visited_at < ? OR (v.visited_at = ? AND v.id > ?))
    ORDER BY v.visited_at DESC, v.id ASC LIMIT ?`
  const rows = await database.prepare(query).bind(...bindings).all<ContentRow>()
  const visible = rows.results.slice(0, limit)
  const items = await hydrateVisits(database, viewerId, visible)
  return {
    apiVersion: COMMUNITY_API_VERSION,
    scope,
    generatedAt: new Date(snapshot).toISOString(),
    items,
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.visited_at, visible.at(-1)!.visit_id, snapshot)
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
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
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
      WHERE r.user_id = ? AND r.status = 'wantToGo' AND r.deleted_at IS NULL
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
  const [identityResult, photoResult, friendshipResult, followResult, viewerRestaurantResult, viewerIdentityResult] = await database.batch([
    database.prepare(`SELECT restaurant_id, provider, external_id, is_primary FROM restaurant_place_identities
      WHERE restaurant_id IN (${placeholders(restaurantIDs)})`).bind(...restaurantIDs),
    database.prepare(`SELECT p.id, p.visit_id, p.visibility FROM photos p JOIN visits v ON v.id = p.visit_id
      WHERE p.visit_id IN (${placeholders(visitIDs)}) AND p.deleted_at IS NULL AND p.storage_provider = 'r2'
        AND ((p.visibility = 'public' AND v.visibility = 'public') OR
          (p.visibility = 'friends' AND v.visibility = 'friends'))
      ORDER BY p.sort_order ASC, p.created_at DESC`).bind(...visitIDs),
    database.prepare(`SELECT id, requester_id, addressee_id, status, deleted_at FROM friendships
      WHERE requester_id = ? OR addressee_id = ?`).bind(viewerId, viewerId),
    database.prepare(`SELECT followed_user_id FROM follows WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT id, status, name, address, city, latitude, longitude FROM restaurants
      WHERE user_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT i.restaurant_id, i.provider, i.external_id, i.is_primary
      FROM restaurant_place_identities i JOIN restaurants r ON r.id = i.restaurant_id
      WHERE r.user_id = ? AND r.deleted_at IS NULL`).bind(viewerId),
  ])
  const identities = identityMap(identityResult.results as unknown as IdentityRow[])
  const photos = photoMap(photoResult.results as unknown as PhotoRow[])
  const friendships = friendshipMap(friendshipResult.results as unknown as FriendshipRow[], viewerId)
  const follows = new Set((followResult.results as Array<{ followed_user_id: string }>).map((row) => row.followed_user_id))
  const viewerStates = buildViewerStates(
    viewerRestaurantResult.results as Array<{ id: string; status: string; name: string; address: string; city: string; latitude: number; longitude: number }>,
    viewerIdentityResult.results as unknown as IdentityRow[], rows, identities,
  )
  const engagements = await engagementForVisits(database, viewerId, visitIDs)
  return rows.map((row) => {
    const place = restaurantProjection(row, identities.get(row.restaurant_id) ?? [], photos.get(row.visit_id)?.[0] ?? null)
    const scope: PublicContentCacheScopeV1 = row.visit_visibility === 'friends' || row.profile_visibility === 'friends' ? 'friends' : 'public'
    const visitPhotos = (photos.get(row.visit_id) ?? []).slice(0, 4)
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
      WHERE user_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT i.restaurant_id, i.provider, i.external_id, i.is_primary
      FROM restaurant_place_identities i JOIN restaurants r ON r.id = i.restaurant_id
      WHERE r.user_id = ? AND r.deleted_at IS NULL`).bind(viewerId),
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
      FROM restaurants WHERE user_id = ? AND status = 'wantToGo' AND deleted_at IS NULL
      ORDER BY updated_at DESC, id ASC LIMIT 100`).bind(targetUserId),
    database.prepare(`SELECT i.provider, i.external_id FROM restaurants r
      JOIN restaurant_place_identities i ON i.restaurant_id = r.id
      WHERE r.user_id = ? AND r.status = 'wantToGo' AND r.deleted_at IS NULL`)
      .bind(viewerId),
    database.prepare(`SELECT ${visitProjection}, COUNT(*) OVER (PARTITION BY v.restaurant_id) AS visit_count
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
      JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}
      ORDER BY visit_count DESC, v.visited_at DESC, v.id ASC LIMIT 6`).bind(targetUserId),
    database.prepare(`SELECT COALESCE(NULLIF(trim(r.city), ''), '未标注城市') AS city,
        COUNT(DISTINCT r.id) AS restaurant_count, COUNT(v.id) AS visit_count
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}
      GROUP BY COALESCE(NULLIF(trim(r.city), ''), '未标注城市')
      ORDER BY visit_count DESC, city ASC LIMIT 8`).bind(targetUserId),
    database.prepare(`SELECT r.tags_json FROM visits v
      JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}`)
      .bind(targetUserId),
    database.prepare(`SELECT AVG(v.rating) AS average_rating,
        SUM(CASE WHEN v.rating IS NOT NULL THEN 1 ELSE 0 END) AS rated_count
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
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
    database.prepare(`SELECT COUNT(*) AS count FROM visits v WHERE v.user_id = ?
      AND v.deleted_at IS NULL AND ${visibilityClause}`).bind(targetUserId),
    database.prepare(`SELECT COUNT(DISTINCT v.restaurant_id) AS count FROM visits v
      JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND ${visibilityClause}`).bind(targetUserId),
    database.prepare(`SELECT COUNT(*) AS count FROM restaurants WHERE user_id = ?
      AND status = 'wantToGo' AND deleted_at IS NULL AND ${wantsVisible ? '1 = 1' : '1 = 0'}`).bind(targetUserId),
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

function photoMap(rows: PhotoRow[]) {
  const result = new Map<string, PublicContentPhotoV1[]>()
  rows.forEach((row) => result.set(row.visit_id, [...(result.get(row.visit_id) ?? []), { photoId: row.id, variant: 'thumbnail' }]))
  return result
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
