import {
  DISCOVERY_API_VERSION,
  DISCOVERY_DEFAULT_LIMIT,
  DISCOVERY_MAX_LIMIT,
  DISCOVERY_SIMILAR_TASTE_MINIMUM_SHARED_RESTAURANTS,
  type DiscoveryCacheScopeV1,
  type DiscoveryCardV1,
  type DiscoveryConfidenceV1,
  type DiscoveryModeV1,
  type DiscoveryPageV1,
  type DiscoveryPlaceIdentityV1,
  type DiscoveryPublicUserProjectionV1,
  type DiscoveryRatingProjectionV1,
  type DiscoveryReasonV1,
  type DiscoveryRestaurantProjectionV1,
  type DiscoveryViewerRestaurantStateV1,
} from '../src/contracts/discoveryContract'
import type { ProfileAvatarPresetContract } from '../src/contracts/profileContract'
import type { RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { calculateTasteSimilarities, MIN_TASTE_SIMILARITY, type TasteRatingSignal } from './tasteSimilarity'

const MAX_CANDIDATE_VISITS = 900
const MAX_OWN_VISITS = 600
const MAX_DISCOVERY_REQUESTS_PER_MINUTE = 120
const DAY = 86_400_000

interface DiscoveryVisitRow {
  visit_id: string
  user_id: string
  restaurant_id: string
  visited_at: string
  rating: number | null
  visibility: 'private' | 'friends' | 'public'
  restaurant_name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags_json: string
  price_per_person: number | null
  merchant_image_url: string | null
  marker_emoji: string
  profile_display_name: string | null
  profile_bio: string | null
  profile_city: string | null
  profile_avatar_photo_id: string | null
  profile_avatar_preset_id: ProfileAvatarPresetContract | null
  profile_visibility: 'private' | 'friends' | 'public' | null
}

interface RestaurantIdentityRow {
  restaurant_id: string
  provider: RestaurantPlaceProvider
  external_id: string
  is_primary: number
}

interface FriendshipRow {
  id: string
  requester_id: string
  addressee_id: string
  status: 'pending' | 'accepted' | 'rejected' | 'removed'
  deleted_at: string | null
}

interface ViewerRestaurantRow {
  id: string
  status: 'visited' | 'wantToGo'
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
}

interface WantRow {
  user_id: string
  restaurant_id: string
  created_at: string
  restaurant_name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags_json: string
  price_per_person: number | null
  merchant_image_url: string | null
  marker_emoji: string
}

interface PhotoRow {
  id: string
  visit_id: string
}

interface PlaceGroup {
  globalKey: string
  restaurantIDs: string[]
  visits: DiscoveryVisitRow[]
  identities: DiscoveryPlaceIdentityV1[]
  restaurant: DiscoveryRestaurantProjectionV1
}

interface RankedCard {
  card: Omit<DiscoveryCardV1, 'rank'>
  score: number
}

export interface DiscoveryData {
  viewerId: string
  city: string
  now: number
  visits: DiscoveryVisitRow[]
  ownVisits: DiscoveryVisitRow[]
  identitiesByRestaurant: Map<string, DiscoveryPlaceIdentityV1[]>
  photosByVisit: Map<string, string>
  friendships: FriendshipRow[]
  following: Set<string>
  viewerRestaurants: ViewerRestaurantRow[]
  wants: WantRow[]
}

export class DiscoveryV1RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

export async function handleDiscoveryV1(
  request: Request,
  database: D1Database,
  viewerId: string,
): Promise<DiscoveryPageV1> {
  if (request.method !== 'GET') throw new DiscoveryV1RequestError('Discovery method is not supported.', 405)
  const url = new URL(request.url)
  const mode = modeFromPath(url.pathname)
  await consumeDiscoveryQuota(database, viewerId)
  const city = await geographicScope(database, viewerId, (url.searchParams.get('city') ?? '').trim())
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const windowDays = url.searchParams.get('window') === '30' ? 30 : 7
  // Freeze ranking time inside the cursor so recency scores cannot shift
  // between page requests and make the tail item reappear.
  const now = cursor.snapshot ?? Date.now()
  if (!city) return emptyPage(mode, '', now)

  const data = await readDiscoveryData(database, viewerId, city, now)
  const ranked = rankDiscovery(mode, data, windowDays)
  const remaining = ranked.filter(({ score, card }) =>
    score < cursor.score || (score === cursor.score && card.restaurant.globalKey > cursor.key),
  )
  const visible = remaining.slice(0, limit)
  const items = visible.map(({ card }, index) => ({ ...card, rank: index + 1 }))
  const tail = visible.at(-1)
  return {
    apiVersion: DISCOVERY_API_VERSION,
    mode,
    city,
    personalizationConfidence: confidence(mode, data, ranked),
    generatedAt: new Date(now).toISOString(),
    items,
    nextCursor: remaining.length > limit && tail
      ? encodeCursor(tail.score, tail.card.restaurant.globalKey, now)
      : null,
  }
}

export function rankDiscovery(
  mode: DiscoveryModeV1,
  data: DiscoveryData,
  trendWindow: 7 | 30,
): RankedCard[] {
  const friendIDs = acceptedFriendIDs(data.friendships, data.viewerId)
  const relationshipByUser = relationshipMap(data.friendships, data.viewerId)
  const allGroups = groupPlaces([...data.visits, ...data.ownVisits], data.identitiesByRestaurant, data.photosByVisit)
  const groups = subsetGroups(allGroups, (visit) => visit.user_id !== data.viewerId)
  addWantOnlyGroups(groups, data.wants, data.identitiesByRestaurant)
  const ownGroups = subsetGroups(allGroups, (visit) => visit.user_id === data.viewerId)
  const ownRatings = userRatingByPlace(data.ownVisits, ownGroups, data.viewerId)
  const ownVisited = new Set([...ownGroups.values()]
    .filter((group) => group.visits.some((visit) => visit.user_id === data.viewerId))
    .map((group) => group.globalKey))
  const viewerState = viewerStates(data, groups, ownVisited)
  const tasteSignals = similaritySignals(data, groups, ownGroups, friendIDs)
  const similarities = new Map(calculateTasteSimilarities(tasteSignals, data.viewerId)
    .map((item) => [item.userId, item]))
  const preferredTags = tasteTagScores(data.ownVisits)

  let ranked: RankedCard[]
  if (mode === 'similar_taste') {
    ranked = similarTasteCards(
      data, groups, ownVisited, viewerState, friendIDs, relationshipByUser,
      similarities, ownRatings,
    )
  } else if (mode === 'trending') {
    ranked = trendingCards(
      data, groups, viewerState, friendIDs, relationshipByUser,
      similarities, ownRatings, trendWindow,
    )
  } else {
    ranked = forYouCards(
      data, groups, ownVisited, viewerState, friendIDs, relationshipByUser,
      similarities, ownRatings, preferredTags,
    )
    if (!ranked.length || ratedOwnVisitCount(data.ownVisits) < 3) {
      ranked = trendingCards(
        data, groups, viewerState, friendIDs, relationshipByUser,
        similarities, ownRatings, 30, true,
      )
    }
  }
  return ranked.sort((left, right) =>
    right.score - left.score || left.card.restaurant.globalKey.localeCompare(right.card.restaurant.globalKey),
  )
}

function subsetGroups(
  groups: Map<string, PlaceGroup>,
  include: (visit: DiscoveryVisitRow) => boolean,
) {
  const result = new Map<string, PlaceGroup>()
  groups.forEach((group, key) => {
    const visits = group.visits.filter(include)
    if (visits.length) result.set(key, { ...group, visits })
  })
  return result
}

async function readDiscoveryData(
  database: D1Database,
  viewerId: string,
  city: string,
  now: number,
): Promise<DiscoveryData> {
  const visibleClause = `(
    (v.visibility = 'public' AND up.visibility = 'public') OR (
    v.visibility IN ('public', 'friends') AND up.visibility IN ('public', 'friends') AND EXISTS (
      SELECT 1 FROM friendships vf WHERE vf.status = 'accepted' AND vf.deleted_at IS NULL AND (
        (vf.requester_id = ? AND vf.addressee_id = v.user_id) OR
        (vf.requester_id = v.user_id AND vf.addressee_id = ?)
      )
    )
  ))`
  const visitProjection = `v.id AS visit_id, v.user_id, v.restaurant_id,
    v.visited_at, v.rating, v.visibility, r.name AS restaurant_name,
    r.address, r.city, r.latitude, r.longitude, r.tags_json,
    r.price_per_person, r.merchant_image_url, r.marker_emoji,
    up.display_name AS profile_display_name, up.bio AS profile_bio,
    up.city AS profile_city, up.avatar_photo_id AS profile_avatar_photo_id,
    up.avatar_preset_id AS profile_avatar_preset_id,
    up.visibility AS profile_visibility`
  const statements = [
    database.prepare(`SELECT ${visitProjection}
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
      JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      WHERE v.user_id <> ? AND v.deleted_at IS NULL AND r.deleted_at IS NULL
        AND r.city = ? AND ${visibleClause}
      ORDER BY v.visited_at DESC, v.id ASC LIMIT ?`)
      .bind(viewerId, city, viewerId, viewerId, MAX_CANDIDATE_VISITS),
    database.prepare(`SELECT ${visitProjection}
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
      LEFT JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      WHERE v.user_id = ? AND v.deleted_at IS NULL AND r.deleted_at IS NULL
      ORDER BY v.visited_at DESC, v.id ASC LIMIT ?`).bind(viewerId, MAX_OWN_VISITS),
    database.prepare(`SELECT DISTINCT i.restaurant_id, i.provider, i.external_id, i.is_primary
      FROM restaurant_place_identities i JOIN restaurants r ON r.id = i.restaurant_id
      WHERE r.deleted_at IS NULL AND (r.city = ? OR r.user_id = ?)`)
      .bind(city, viewerId),
    database.prepare(`SELECT id, requester_id, addressee_id, status, deleted_at
      FROM friendships WHERE requester_id = ? OR addressee_id = ?`)
      .bind(viewerId, viewerId),
    database.prepare(`SELECT followed_user_id FROM follows
      WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT id, status, name, address, city, latitude, longitude
      FROM restaurants WHERE user_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT w.user_id, w.restaurant_id, w.created_at,
        r.name AS restaurant_name, r.address, r.city, r.latitude, r.longitude,
        r.tags_json, r.price_per_person, r.merchant_image_url, r.marker_emoji
      FROM want_to_go w
      JOIN restaurants r ON r.id = w.restaurant_id
      JOIN user_profiles up ON up.user_id = w.user_id AND up.deleted_at IS NULL
      WHERE w.deleted_at IS NULL AND r.deleted_at IS NULL AND r.city = ?
        AND (up.visibility = 'public' OR w.user_id = ?)
      UNION ALL
      SELECT r.user_id, r.id, r.created_at, r.name, r.address, r.city,
        r.latitude, r.longitude, r.tags_json, r.price_per_person,
        r.merchant_image_url, r.marker_emoji FROM restaurants r
      JOIN user_profiles up ON up.user_id = r.user_id AND up.deleted_at IS NULL
      WHERE r.deleted_at IS NULL AND r.city = ? AND r.status = 'wantToGo'
        AND (up.visibility = 'public' OR r.user_id = ?)`)
      .bind(city, viewerId, city, viewerId),
    database.prepare(`SELECT p.id, p.visit_id FROM photos p
      JOIN visits v ON v.id = p.visit_id AND v.user_id = p.user_id
      JOIN restaurants r ON r.id = v.restaurant_id
      JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
      WHERE p.deleted_at IS NULL AND v.deleted_at IS NULL AND r.deleted_at IS NULL
        AND r.city = ? AND p.storage_provider = 'r2' AND (
          (p.visibility = 'public' AND v.visibility = 'public' AND up.visibility = 'public') OR (
            p.visibility IN ('public', 'friends') AND v.visibility IN ('public', 'friends')
            AND up.visibility IN ('public', 'friends') AND EXISTS (
              SELECT 1 FROM friendships pf WHERE pf.status = 'accepted'
                AND pf.deleted_at IS NULL AND (
                  (pf.requester_id = ? AND pf.addressee_id = p.user_id) OR
                  (pf.requester_id = p.user_id AND pf.addressee_id = ?)
                )
            )
          )
        )
      ORDER BY p.sort_order ASC, p.created_at DESC LIMIT 1800`).bind(city, viewerId, viewerId),
  ]
  const results = await database.batch(statements)
  return {
    viewerId,
    city,
    now,
    visits: results[0].results as unknown as DiscoveryVisitRow[],
    ownVisits: results[1].results as unknown as DiscoveryVisitRow[],
    identitiesByRestaurant: identityMap(results[2].results as unknown as RestaurantIdentityRow[]),
    friendships: results[3].results as unknown as FriendshipRow[],
    following: new Set((results[4].results as Array<{ followed_user_id: string }>).map((row) => row.followed_user_id)),
    viewerRestaurants: results[5].results as unknown as ViewerRestaurantRow[],
    wants: results[6].results as unknown as WantRow[],
    photosByVisit: new Map((results[7].results as unknown as PhotoRow[]).map((row) => [row.visit_id, row.id])),
  }
}

function forYouCards(
  data: DiscoveryData,
  groups: Map<string, PlaceGroup>,
  ownVisited: Set<string>,
  states: Map<string, DiscoveryViewerRestaurantStateV1>,
  friendIDs: Set<string>,
  relationships: Map<string, FriendshipRow>,
  similarities: Map<string, ReturnType<typeof calculateTasteSimilarities>[number]>,
  ownRatings: Map<string, number>,
  preferredTags: Map<string, number>,
) {
  return [...groups.values()].flatMap((group): RankedCard[] => {
    if (ownVisited.has(group.globalKey)) return []
    const publicVisits = group.visits.filter((visit) => visit.visibility === 'public')
    const qualityVisits = group.visits.filter((visit) => visit.rating !== null && visit.rating >= 4)
    if (!qualityVisits.length) return []
    const source = [...qualityVisits].sort((left, right) =>
      sourceSignalScore(right, friendIDs, data.following, similarities) -
      sourceSignalScore(left, friendIDs, data.following, similarities) ||
      right.visited_at.localeCompare(left.visited_at),
    )[0]
    const matchedTags = group.restaurant.tags
      .map((tag) => ({ tag, score: preferredTags.get(normalize(tag)) ?? 0 }))
      .filter((item) => item.score > 0).sort((a, b) => b.score - a.score)
    const similar = similarities.get(source.user_id)
    const reasons: DiscoveryReasonV1[] = []
    if (friendIDs.has(source.user_id)) reasons.push({ code: 'FRIEND_HIGH_RATING', text: '好友最近给过高分' })
    else if (similar) reasons.push({ code: 'SIMILAR_USERS', text: '和你口味相近的人喜欢' })
    else if (data.following.has(source.user_id)) reasons.push({ code: 'FOLLOWING_HIGH_RATING', text: '你关注的人最近给过高分' })
    if (matchedTags[0]) reasons.push({ code: 'TASTE_TAG_MATCH', text: `符合你常给高分的${matchedTags[0].tag}口味` })
    if (!reasons.length) reasons.push({ code: 'COMMUNITY_QUALITY', text: '当前城市有稳定的公开高分记录' })
    const community = ratingFor(publicVisits)
    const score = (matchedTags[0]?.score ?? 0) * 10 + (community.value ?? 0) * 4 +
      Number(friendIDs.has(source.user_id)) * 16 + Number(Boolean(similar)) * 12 +
      Number(data.following.has(source.user_id)) * 5 + recencyScore(source.visited_at, data.now) * 8
    return [{
      score,
      card: card(
        'for_you', group, states, friendIDs, relationships, data.following,
        similarities, ownRatings, reasons, source, score,
        null,
      ),
    }]
  })
}

function similarTasteCards(
  data: DiscoveryData,
  groups: Map<string, PlaceGroup>,
  ownVisited: Set<string>,
  states: Map<string, DiscoveryViewerRestaurantStateV1>,
  friendIDs: Set<string>,
  relationships: Map<string, FriendshipRow>,
  similarities: Map<string, ReturnType<typeof calculateTasteSimilarities>[number]>,
  ownRatings: Map<string, number>,
) {
  return [...groups.values()].flatMap((group): RankedCard[] => {
    if (ownVisited.has(group.globalKey)) return []
    const candidates = group.visits.filter((visit) => {
      const similarity = similarities.get(visit.user_id)
      return similarity && similarity.sharedRestaurantCount >= DISCOVERY_SIMILAR_TASTE_MINIMUM_SHARED_RESTAURANTS &&
        similarity.similarity >= MIN_TASTE_SIMILARITY && visit.rating !== null && visit.rating >= 4 &&
        canIdentifyProfile(visit, friendIDs)
    })
    if (!candidates.length) return []
    const source = [...candidates].sort((left, right) => {
      const leftSimilarity = similarities.get(left.user_id)!
      const rightSimilarity = similarities.get(right.user_id)!
      return rightSimilarity.similarity - leftSimilarity.similarity ||
        rightSimilarity.sharedRestaurantCount - leftSimilarity.sharedRestaurantCount ||
        right.visited_at.localeCompare(left.visited_at) || left.user_id.localeCompare(right.user_id)
    })[0]
    const similar = similarities.get(source.user_id)!
    const percent = Math.round(similar.similarity * 100)
    const reasons: DiscoveryReasonV1[] = [{
      code: 'SIMILAR_USERS',
      text: `基于 ${similar.sharedRestaurantCount} 家共同评分餐厅，同味用户给过高分`,
    }]
    const score = similar.similarity * 100 + Number(source.rating ?? 0) * 4 + recencyScore(source.visited_at, data.now) * 5
    return [{
      score,
      card: card(
        'similar_taste', group, states, friendIDs, relationships, data.following,
        similarities, ownRatings, reasons, source, score,
        { percent, sharedRestaurantCount: similar.sharedRestaurantCount },
      ),
    }]
  })
}

function trendingCards(
  data: DiscoveryData,
  groups: Map<string, PlaceGroup>,
  states: Map<string, DiscoveryViewerRestaurantStateV1>,
  friendIDs: Set<string>,
  relationships: Map<string, FriendshipRow>,
  similarities: Map<string, ReturnType<typeof calculateTasteSimilarities>[number]>,
  ownRatings: Map<string, number>,
  windowDays: 7 | 30,
  coldStart = false,
) {
  const wantPlaceKeys = new Map<string, Set<string>>()
  const restaurantToPlace = new Map<string, string>()
  groups.forEach((group) => group.restaurantIDs.forEach((restaurantID) => restaurantToPlace.set(restaurantID, group.globalKey)))
  data.wants.filter((want) => want.user_id !== data.viewerId).forEach((want) => {
    const key = restaurantToPlace.get(want.restaurant_id)
    if (!key || data.now - Date.parse(want.created_at) > 30 * DAY) return
    wantPlaceKeys.set(key, new Set([...(wantPlaceKeys.get(key) ?? []), want.user_id]))
  })
  return [...groups.values()].flatMap((group): RankedCard[] => {
    const publicVisits = group.visits.filter((visit) => visit.visibility === 'public')
    const recent = publicVisits.filter((visit) => data.now - Date.parse(visit.visited_at) <= windowDays * DAY)
    const users = new Set(recent.map((visit) => visit.user_id))
    const rawWants = wantPlaceKeys.get(group.globalKey)?.size ?? 0
    // Want-to-go records do not yet carry a visibility contract. Treat an
    // isolated save as private and expose only a small aggregate cohort.
    const wants = rawWants >= 2 ? rawWants : 0
    if (!users.size && !wants) return []
    const highRatingUsers = new Set(recent.filter((visit) => visit.rating !== null && visit.rating >= 4).map((visit) => visit.user_id)).size
    const source = [...recent].sort((left, right) =>
      right.visited_at.localeCompare(left.visited_at) || left.user_id.localeCompare(right.user_id),
    )[0] ?? publicVisits[0]
    const mostRecentWant = data.wants.filter((want) => restaurantToPlace.get(want.restaurant_id) === group.globalKey)
      .sort((left, right) => right.created_at.localeCompare(left.created_at))[0]
    const reasons: DiscoveryReasonV1[] = [{
      code: coldStart ? 'COLD_START_TRENDING' : 'TRENDING_UNIQUE_USERS',
      text: coldStart
        ? `你的口味数据还不够，先看看${data.city}近期热门`
        : `近 ${windowDays} 天有 ${users.size} 位用户到访`,
    }]
    if (wants > 0) reasons.push({ code: 'RECENT_WANT_TO_GO', text: `近期有 ${wants} 位用户加入想吃` })
    const score = users.size * (windowDays === 7 ? 12 : 7) + wants * 4 + highRatingUsers * 3 +
      recencyScore(source?.visited_at ?? mostRecentWant?.created_at ?? new Date(0).toISOString(), data.now) * 2
    const base = card(
      coldStart ? 'for_you' : 'trending', group, states, friendIDs,
      relationships, data.following, similarities, ownRatings, reasons, source, score, null,
    )
    return [{
      score,
      card: {
        ...base,
        trend: { windowDays, uniqueVisitorCount: users.size, wantToGoCount: wants },
        cacheScope: 'public',
      },
    }]
  })
}

function card(
  mode: DiscoveryModeV1,
  group: PlaceGroup,
  states: Map<string, DiscoveryViewerRestaurantStateV1>,
  friendIDs: Set<string>,
  relationships: Map<string, FriendshipRow>,
  following: Set<string>,
  similarities: Map<string, ReturnType<typeof calculateTasteSimilarities>[number]>,
  ownRatings: Map<string, number>,
  reasons: DiscoveryReasonV1[],
  source: DiscoveryVisitRow | null,
  score: number,
  similarity: { percent: number; sharedRestaurantCount: number } | null,
): Omit<DiscoveryCardV1, 'rank'> {
  const publicVisits = group.visits.filter((visit) => visit.visibility === 'public')
  const friendVisits = group.visits.filter((visit) => friendIDs.has(visit.user_id))
  const similarVisits = group.visits.filter((visit) => similarities.has(visit.user_id))
  const cacheScope: DiscoveryCacheScopeV1 = source?.visibility === 'friends' ? 'friends' : 'public'
  return {
    id: `${mode}:${group.globalKey}`,
    mode,
    restaurant: group.restaurant,
    viewerState: states.get(group.globalKey) ?? 'none',
    ratings: {
      mine: ratingProjection(ownRatings.get(group.globalKey)),
      community: ratingFor(publicVisits),
      friends: ratingFor(friendVisits),
      similarTaste: ratingFor(similarVisits),
    },
    reasons: reasons.slice(0, 3),
    sourceUser: source ? publicUser(source, friendIDs, relationships, following) : null,
    similarity,
    trend: null,
    cacheScope,
    score: rounded(score),
  }
}

function groupPlaces(
  visits: DiscoveryVisitRow[],
  identitiesByRestaurant: Map<string, DiscoveryPlaceIdentityV1[]>,
  photosByVisit: Map<string, string>,
) {
  const restaurantIDs = unique(visits.map((visit) => visit.restaurant_id))
  const parent = new Map(restaurantIDs.map((id) => [id, id]))
  const find = (id: string): string => {
    const current = parent.get(id) ?? id
    if (current === id) return id
    const root = find(current)
    parent.set(id, root)
    return root
  }
  const union = (left: string, right: string) => {
    const leftRoot = find(left)
    const rightRoot = find(right)
    if (leftRoot === rightRoot) return
    parent.set(leftRoot < rightRoot ? rightRoot : leftRoot, leftRoot < rightRoot ? leftRoot : rightRoot)
  }
  const identityOwner = new Map<string, string>()
  const fingerprintOwner = new Map<string, string>()
  restaurantIDs.forEach((restaurantID) => {
    for (const identity of identitiesByRestaurant.get(restaurantID) ?? []) {
      if (identity.provider === 'manual') continue
      const identityKey = `${identity.provider}:${identity.externalId.trim()}`
      const owner = identityOwner.get(identityKey)
      if (owner) union(owner, restaurantID)
      else identityOwner.set(identityKey, restaurantID)
    }
    const visit = visits.find((item) => item.restaurant_id === restaurantID)
    if (!visit) return
    const fingerprint = placeFingerprint(visit)
    const owner = fingerprintOwner.get(fingerprint)
    if (owner) union(owner, restaurantID)
    else fingerprintOwner.set(fingerprint, restaurantID)
  })

  const byRoot = new Map<string, DiscoveryVisitRow[]>()
  visits.forEach((visit) => {
    const root = find(visit.restaurant_id)
    byRoot.set(root, [...(byRoot.get(root) ?? []), visit])
  })
  const result = new Map<string, PlaceGroup>()
  byRoot.forEach((groupVisits) => {
    const representative = [...groupVisits].sort((left, right) =>
      completeness(right) - completeness(left) || right.visited_at.localeCompare(left.visited_at),
    )[0]
    const externalIdentities = groupVisits.flatMap((visit) =>
      identitiesByRestaurant.get(visit.restaurant_id) ?? [],
    )
    const globalKey = globalPlaceKey(externalIdentities, representative)
    const identities = normalizeIdentities(externalIdentities, globalKey)
    const photoVisit = [...groupVisits].find((visit) => photosByVisit.has(visit.visit_id))
    result.set(globalKey, {
      globalKey,
      restaurantIDs: unique(groupVisits.map((visit) => visit.restaurant_id)),
      visits: groupVisits,
      identities,
      restaurant: {
        globalKey,
        placeIdentities: identities,
        name: representative.restaurant_name,
        address: representative.address,
        city: representative.city,
        latitude: representative.latitude,
        longitude: representative.longitude,
        tags: unique(groupVisits.flatMap((visit) => parseTags(visit.tags_json))).slice(0, 12),
        pricePerPerson: representative.price_per_person,
        merchantImageUrl: safeHTTPSURL(representative.merchant_image_url),
        markerEmoji: representative.marker_emoji || '🍽️',
        photo: photoVisit ? { photoId: photosByVisit.get(photoVisit.visit_id)!, variant: 'thumbnail' } : null,
      },
    })
  })
  return result
}

function addWantOnlyGroups(
  groups: Map<string, PlaceGroup>,
  wants: WantRow[],
  identitiesByRestaurant: Map<string, DiscoveryPlaceIdentityV1[]>,
) {
  const identityToKey = new Map<string, string>()
  groups.forEach((group) => group.identities.forEach((identity) => {
    if (identity.provider !== 'manual') identityToKey.set(`${identity.provider}:${identity.externalId}`, group.globalKey)
  }))
  wants.forEach((want) => {
    if ([...groups.values()].some((group) => group.restaurantIDs.includes(want.restaurant_id))) return
    const identities = identitiesByRestaurant.get(want.restaurant_id) ?? []
    const matched = identities.filter((identity) => identity.provider !== 'manual')
      .map((identity) => identityToKey.get(`${identity.provider}:${identity.externalId}`))
      .find((value): value is string => Boolean(value))
    const row = { restaurant_name: want.restaurant_name, address: want.address, city: want.city,
      latitude: want.latitude, longitude: want.longitude }
    const fingerprint = placeFingerprint(row)
    const fingerprintMatch = [...groups.values()].find((group) =>
      group.visits[0] && placeFingerprint(group.visits[0]) === fingerprint)?.globalKey
    const globalKey = matched ?? fingerprintMatch ?? globalPlaceKey(identities, row)
    const existing = groups.get(globalKey)
    if (existing) {
      existing.restaurantIDs = unique([...existing.restaurantIDs, want.restaurant_id])
      existing.identities = normalizeIdentities([...existing.identities, ...identities], globalKey)
      return
    }
    const normalizedIdentities = normalizeIdentities(identities, globalKey)
    groups.set(globalKey, {
      globalKey, restaurantIDs: [want.restaurant_id], visits: [], identities: normalizedIdentities,
      restaurant: {
        globalKey, placeIdentities: normalizedIdentities, name: want.restaurant_name,
        address: want.address, city: want.city, latitude: want.latitude, longitude: want.longitude,
        tags: parseTags(want.tags_json), pricePerPerson: want.price_per_person,
        merchantImageUrl: safeHTTPSURL(want.merchant_image_url), markerEmoji: want.marker_emoji || '🍽️', photo: null,
      },
    })
  })
}

function viewerStates(data: DiscoveryData, groups: Map<string, PlaceGroup>, visited: Set<string>) {
  const states = new Map<string, DiscoveryViewerRestaurantStateV1>()
  visited.forEach((key) => states.set(key, 'visited'))
  const restaurantKey = new Map<string, string>()
  const identityKey = new Map<string, string>()
  groups.forEach((group) => group.restaurantIDs.forEach((restaurantID) => restaurantKey.set(restaurantID, group.globalKey)))
  groups.forEach((group) => group.identities.forEach((identity) => {
    if (identity.provider !== 'manual') identityKey.set(`${identity.provider}:${identity.externalId}`, group.globalKey)
  }))
  data.viewerRestaurants.forEach((restaurant) => {
    const ownIdentities = data.identitiesByRestaurant.get(restaurant.id) ?? []
    const matchedIdentityKey = ownIdentities
      .filter((identity) => identity.provider !== 'manual')
      .map((identity) => identityKey.get(`${identity.provider}:${identity.externalId}`))
      .find((value): value is string => Boolean(value))
    const fingerprint = placeFingerprint({ restaurant_name: restaurant.name, address: restaurant.address,
      city: restaurant.city, latitude: restaurant.latitude, longitude: restaurant.longitude })
    const key = matchedIdentityKey ?? ([...groups.values()].find((group) =>
      placeFingerprint(group.visits[0]) === fingerprint)?.globalKey ?? globalPlaceKey(ownIdentities, {
        restaurant_name: restaurant.name, address: restaurant.address, city: restaurant.city,
        latitude: restaurant.latitude, longitude: restaurant.longitude,
      }))
    if (restaurant.status === 'visited') states.set(key, 'visited')
    else if (!states.has(key)) states.set(key, 'want_to_go')
    restaurantKey.set(restaurant.id, key)
  })
  data.wants.filter((want) => want.user_id === data.viewerId).forEach((want) => {
    const key = restaurantKey.get(want.restaurant_id)
    if (key && !states.has(key)) states.set(key, 'want_to_go')
  })
  return states
}

function similaritySignals(
  data: DiscoveryData,
  groups: Map<string, PlaceGroup>,
  ownGroups: Map<string, PlaceGroup>,
  friendIDs: Set<string>,
) {
  const signals: TasteRatingSignal[] = []
  ownGroups.forEach((group) => group.visits.forEach((visit) => {
    if (visit.rating === null) return
    signals.push({ userId: data.viewerId, poiId: group.globalKey, ratingOutOfTen: visit.rating * 2, tags: group.restaurant.tags })
  }))
  groups.forEach((group) => group.visits.forEach((visit) => {
    if (visit.rating === null || (visit.visibility !== 'public' && !friendIDs.has(visit.user_id))) return
    signals.push({ userId: visit.user_id, poiId: group.globalKey, ratingOutOfTen: visit.rating * 2, tags: group.restaurant.tags })
  }))
  return signals
}

function userRatingByPlace(visits: DiscoveryVisitRow[], groups: Map<string, PlaceGroup>, userId: string) {
  const result = new Map<string, number>()
  groups.forEach((group) => {
    const ratings = group.visits.filter((visit) => visit.user_id === userId && visit.rating !== null)
      .map((visit) => Number(visit.rating))
    if (ratings.length) result.set(group.globalKey, average(ratings))
  })
  return result
}

function publicUser(
  visit: DiscoveryVisitRow,
  friendIDs: Set<string>,
  relationships: Map<string, FriendshipRow>,
  following: Set<string>,
): DiscoveryPublicUserProjectionV1 | null {
  if (!canIdentifyProfile(visit, friendIDs) || !visit.profile_display_name) return null
  const relationship = relationships.get(visit.user_id)
  return {
    userId: visit.user_id,
    displayName: visit.profile_display_name,
    bio: visit.profile_bio?.trim() || null,
    city: visit.profile_city?.trim() || null,
    avatarPhotoId: visit.profile_avatar_photo_id,
    avatarPresetId: visit.profile_avatar_preset_id ?? 'polar-bear',
    friendshipId: relationship?.id ?? null,
    friendshipState: relationshipState(relationship, visit.user_id),
    isFollowing: following.has(visit.user_id),
  }
}

function relationshipMap(friendships: FriendshipRow[], viewerId: string) {
  return new Map(friendships.filter((row) => !row.deleted_at && ['pending', 'accepted'].includes(row.status))
    .map((row) => [row.requester_id === viewerId ? row.addressee_id : row.requester_id, row]))
}

function relationshipState(row: FriendshipRow | undefined, targetUserId: string) {
  if (!row || row.deleted_at || row.status === 'rejected' || row.status === 'removed') return 'none' as const
  if (row.status === 'accepted') return 'friends' as const
  return row.requester_id === targetUserId ? 'incoming_request' as const : 'outgoing_request' as const
}

function acceptedFriendIDs(friendships: FriendshipRow[], viewerId: string) {
  return new Set(friendships.filter((row) => row.status === 'accepted' && !row.deleted_at)
    .map((row) => row.requester_id === viewerId ? row.addressee_id : row.requester_id))
}

function canIdentifyProfile(visit: DiscoveryVisitRow, friendIDs: Set<string>) {
  return visit.profile_visibility === 'public' ||
    (visit.profile_visibility === 'friends' && friendIDs.has(visit.user_id))
}

function ratingFor(visits: DiscoveryVisitRow[]): DiscoveryRatingProjectionV1 {
  const byUser = new Map<string, number[]>()
  visits.forEach((visit) => {
    if (visit.rating === null) return
    byUser.set(visit.user_id, [...(byUser.get(visit.user_id) ?? []), visit.rating])
  })
  const values = [...byUser.values()].map(average)
  return { value: values.length ? rounded(average(values)) : null, sampleCount: values.length }
}

function ratingProjection(value: number | undefined): DiscoveryRatingProjectionV1 {
  return { value: value === undefined ? null : rounded(value), sampleCount: value === undefined ? 0 : 1 }
}

function tasteTagScores(visits: DiscoveryVisitRow[]) {
  const scores = new Map<string, number>()
  visits.forEach((visit) => {
    if (visit.rating === null || visit.rating < 4) return
    const rating = visit.rating
    parseTags(visit.tags_json).forEach((tag) => scores.set(normalize(tag), (scores.get(normalize(tag)) ?? 0) + rating - 3.5))
  })
  return scores
}

function ratedOwnVisitCount(visits: DiscoveryVisitRow[]) {
  return visits.filter((visit) => visit.rating !== null).length
}

function sourceSignalScore(
  visit: DiscoveryVisitRow,
  friends: Set<string>,
  following: Set<string>,
  similarities: Map<string, ReturnType<typeof calculateTasteSimilarities>[number]>,
) {
  return Number(friends.has(visit.user_id)) * 100 + Number(Boolean(similarities.get(visit.user_id))) * 70 +
    Number(following.has(visit.user_id)) * 30 + Number(visit.rating ?? 0) * 5
}

function confidence(mode: DiscoveryModeV1, data: DiscoveryData, ranked: RankedCard[]): DiscoveryConfidenceV1 {
  if (!ranked.length) return 'insufficient'
  if (mode === 'trending') return ranked.length >= 5 ? 'medium' : 'low'
  const rated = ratedOwnVisitCount(data.ownVisits)
  if (rated < 3) return 'insufficient'
  if (rated < 8) return 'medium'
  return 'high'
}

async function geographicScope(database: D1Database, viewerId: string, requested: string) {
  if (requested) return requested.slice(0, 80)
  const profile = await database.prepare(`SELECT city FROM user_profiles
    WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(viewerId).first<{ city: string }>()
  if (profile?.city.trim()) return profile.city.trim().slice(0, 80)
  const recent = await database.prepare(`SELECT r.city FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
    WHERE v.user_id = ? AND v.deleted_at IS NULL AND r.deleted_at IS NULL AND TRIM(r.city) <> ''
    ORDER BY v.visited_at DESC LIMIT 1`).bind(viewerId).first<{ city: string }>()
  return recent?.city.trim().slice(0, 80) ?? ''
}

async function consumeDiscoveryQuota(database: D1Database, viewerId: string) {
  const window = new Date().toISOString().slice(0, 16)
  // Keep the rate-limit ledger bounded without a global maintenance job. Each
  // actor only removes its own expired buckets, so this cannot affect another
  // user's active quota.
  await database.prepare(`DELETE FROM discovery_rate_limits
    WHERE user_id = ? AND window_started_at < ?`).bind(
    viewerId,
    new Date(Date.now() - DAY).toISOString().slice(0, 16),
  ).run()
  await database.prepare(`INSERT INTO discovery_rate_limits (user_id, window_started_at, request_count)
    VALUES (?, ?, 1) ON CONFLICT(user_id, window_started_at)
    DO UPDATE SET request_count = request_count + 1`).bind(viewerId, window).run()
  const row = await database.prepare(`SELECT request_count FROM discovery_rate_limits
    WHERE user_id = ? AND window_started_at = ?`).bind(viewerId, window)
    .first<{ request_count: number }>()
  if (Number(row?.request_count ?? 0) > MAX_DISCOVERY_REQUESTS_PER_MINUTE) {
    throw new DiscoveryV1RequestError('发现页刷新过于频繁，请稍后再试。', 429)
  }
}

function modeFromPath(path: string): DiscoveryModeV1 {
  if (path === '/api/v1/discovery/for-you') return 'for_you'
  if (path === '/api/v1/discovery/similar-taste') return 'similar_taste'
  if (path === '/api/v1/discovery/trending') return 'trending'
  throw new DiscoveryV1RequestError('Discovery route was not found.', 404)
}

function pageLimit(url: URL) {
  const value = Number(url.searchParams.get('limit') ?? DISCOVERY_DEFAULT_LIMIT)
  return Number.isInteger(value) ? Math.min(DISCOVERY_MAX_LIMIT, Math.max(1, value)) : DISCOVERY_DEFAULT_LIMIT
}

function encodeCursor(score: number, key: string, snapshot: number) {
  const bytes = new TextEncoder().encode(JSON.stringify([score, key, snapshot]))
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

function decodeCursor(raw: string | null) {
  if (!raw) return { score: Number.POSITIVE_INFINITY, key: '', snapshot: null as number | null }
  try {
    const normalized = raw.replaceAll('-', '+').replaceAll('_', '/')
    const bytes = Uint8Array.from(atob(normalized), (value) => value.charCodeAt(0))
    const value = JSON.parse(new TextDecoder().decode(bytes))
    if (Array.isArray(value) && value.length === 3 && typeof value[0] === 'number' &&
      typeof value[1] === 'string' && typeof value[2] === 'number' && Number.isFinite(value[2])) {
      return { score: value[0], key: value[1], snapshot: value[2] }
    }
  } catch { /* invalid cursor */ }
  throw new DiscoveryV1RequestError('Discovery cursor is invalid.', 400)
}

function emptyPage(mode: DiscoveryModeV1, city: string, now: number): DiscoveryPageV1 {
  return {
    apiVersion: DISCOVERY_API_VERSION, mode, city,
    personalizationConfidence: 'insufficient', generatedAt: new Date(now).toISOString(),
    items: [], nextCursor: null,
  }
}

function identityMap(rows: RestaurantIdentityRow[]) {
  const map = new Map<string, DiscoveryPlaceIdentityV1[]>()
  rows.forEach((row) => map.set(row.restaurant_id, [...(map.get(row.restaurant_id) ?? []), {
    provider: row.provider, externalId: row.external_id, isPrimary: row.is_primary === 1,
  }]))
  return map
}

function normalizeIdentities(identities: DiscoveryPlaceIdentityV1[], globalKey: string) {
  const deduplicated = uniqueBy(identities.filter((item) => item.provider !== 'manual' && item.externalId.trim()),
    (item) => `${item.provider}:${item.externalId}`)
  const values: DiscoveryPlaceIdentityV1[] = deduplicated.length
    ? deduplicated
    : [{ provider: 'manual', externalId: globalKey, isPrimary: true }]
  const primaryKey = `${values[0].provider}:${values[0].externalId}`
  return values.sort((left, right) => `${left.provider}:${left.externalId}`.localeCompare(`${right.provider}:${right.externalId}`))
    .map((item) => ({ ...item, isPrimary: `${item.provider}:${item.externalId}` === primaryKey }))
}

function placeFingerprint(restaurant: Pick<DiscoveryVisitRow, 'restaurant_name' | 'address' | 'city' | 'latitude' | 'longitude'>) {
  const source = `${normalize(restaurant.restaurant_name)}|${normalize(restaurant.city)}|${normalize(restaurant.address)}|${Math.round(restaurant.latitude * 1000)}|${Math.round(restaurant.longitude * 1000)}`
  return `fingerprint:${stableHash(source)}`
}

function globalPlaceKey(
  identities: DiscoveryPlaceIdentityV1[],
  restaurant: Pick<DiscoveryVisitRow, 'restaurant_name' | 'address' | 'city' | 'latitude' | 'longitude'>,
) {
  const identitySource = unique(identities
    .filter((item) => item.provider !== 'manual' && item.externalId.trim())
    .map((item) => `${item.provider}:${item.externalId.trim()}`))
    .sort().join('|')
  return identitySource ? `place:${stableHash(identitySource)}` : placeFingerprint(restaurant).replace('fingerprint:', 'place:')
}

function stableHash(source: string) {
  let hash = 2166136261
  for (let index = 0; index < source.length; index += 1) {
    hash ^= source.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return (hash >>> 0).toString(16).padStart(8, '0')
}

function completeness(row: DiscoveryVisitRow) {
  return Number(Boolean(row.merchant_image_url)) * 8 + Number(Boolean(row.address)) * 4 +
    Number(Boolean(row.price_per_person)) * 2 + parseTags(row.tags_json).length
}

function recencyScore(value: string, now: number) {
  return Math.max(0, 1 - (now - Date.parse(value)) / (120 * DAY))
}

function parseTags(value: string) {
  try {
    const parsed = JSON.parse(value)
    return Array.isArray(parsed)
      ? parsed.filter((item): item is string => typeof item === 'string' && item.trim().length > 0).map((item) => item.trim())
      : []
  } catch { return [] }
}

function safeHTTPSURL(value: string | null) {
  if (!value) return null
  try { return new URL(value).protocol === 'https:' ? value : null }
  catch { return null }
}

function normalize(value: string) {
  return value.trim().toLocaleLowerCase('zh-CN').replace(/[\s\p{P}\p{S}]+/gu, '')
}

function average(values: number[]) { return values.reduce((sum, value) => sum + value, 0) / values.length }
function rounded(value: number) { return Math.round(value * 100) / 100 }
function unique<T>(values: T[]) { return [...new Set(values)] }
function uniqueBy<T>(values: T[], key: (value: T) => string) { return [...new Map(values.map((value) => [key(value), value])).values()] }
