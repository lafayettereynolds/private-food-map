import { predictLiking } from '../src/contracts/predictedLiking'
import {
  DISCOVERY_API_VERSION,
  DISCOVERY_DEFAULT_LIMIT,
  DISCOVERY_MAX_LIMIT,
  DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE,
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
import type { RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { DISCOVERY_FILTER_TAXONOMY } from '../src/contracts/discoveryFilterTaxonomy'
import { discoveryExplorationPages, discoverySessionPreferenceBonus } from '../src/contracts/discoverySessionPreferences'
import { readDiscoveryRecommendationFeedback, applyDiscoveryRecommendationFeedback } from './discoveryRecommendationFeedback'
import { discoveryRestaurantCandidates } from './discoveryCandidates'
import { LEGACY_AMOUNT_CURRENCY, resolveRecordedMoney } from '../src/contracts/legacyMoney'
import { discoveryPublicRatingRank } from '../src/contracts/discoveryRanking'
import { readDiscoveryQuery, matchesDiscoveryHardFilters, discoveryDistanceMeters, DISCOVERY_FILTER_CAPABILITIES,
  DISCOVERY_PHOTO_SCAN_LIMIT, assertCompleteDiscoveryPhotos, type DiscoveryQuery } from './discoveryHardFilters'
import { calculateTasteSimilarities, tastePersonalEvidence } from './tasteSimilarity'
import { RECOMMENDATION_EVIDENCE_POLICY } from '../src/contracts/recommendationEvidencePolicy'
import { recommendationHistoryReasons, recommendationHistoryReference, type RecommendationHistoryPlace } from '../src/services/recommendationHistoryReasons'
import { recommendationColdStartReasons } from '../src/services/recommendationColdStart'
import {
  readDiscoveryVisitAggregates,
  ratingFromDiscoveryAggregates,
  tasteSignalsFromDiscoveryAggregates,
  trendFromDiscoveryAggregates,
  type DiscoveryVisitAggregate,
  type DiscoveryVisitMetadata,
} from './discoveryVisitAggregates'
import {
  RestaurantUGCImagePool,
  loadActivityPhotoPool,
  resolveRestaurantVisualSelection,
  type RestaurantUGCPhotoRecord,
  type RestaurantUGCPhotoSelection,
} from './restaurantUGCImagePool'

const MAX_DISCOVERY_REQUESTS_PER_MINUTE = 120
const DAY = 86_400_000

/** One visibility-partitioned cohort, with its actual latest Visit for source
 * selection. Ranking statistics always come from the complete aggregate. */
interface DiscoveryVisitRow extends DiscoveryVisitMetadata {
  visit_id: string
  user_id: string
  restaurant_id: string
  visited_at: string
  rating: number | null
  visibility: 'private' | 'friends' | 'public'
  profile_visibility: 'private' | 'friends' | 'public' | null
  aggregate: DiscoveryVisitAggregate
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
  profile_visibility: 'private' | 'friends' | 'public'
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
  photos: RestaurantUGCPhotoRecord[]
  friendships: FriendshipRow[]
  following: Set<string>
  viewerRestaurants: ViewerRestaurantRow[]
  wants: WantRow[]
  ownerWants?: WantRow[]
}

export class DiscoveryV1RequestError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string) { super(message) }
}

export async function handleDiscoveryV1(
  request: Request,
  database: D1Database,
  viewerId: string,
  access: { isPremium: boolean } = { isPremium: true },
): Promise<DiscoveryPageV1> {
  if (request.method !== 'GET') throw new DiscoveryV1RequestError('Discovery method is not supported.', 405)
  const url = new URL(request.url)
  const mode = modeFromPath(url.pathname)
  if (mode === 'similar_taste' && !access.isPremium) {
    throw new DiscoveryV1RequestError('Taste-similar discovery requires Premium.', 403, 'membership_required')
  }
  await consumeDiscoveryQuota(database, viewerId)
  const limit = pageLimit(url)
  const query = readDiscoveryQuery(url, mode)
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const windowDays = url.searchParams.get('window') === '30' ? 30 : 7
  // Freeze ranking time inside the cursor so recency scores cannot shift
  // between page requests and make the tail item reappear.
  const now = cursor.snapshot ?? Date.now()
  const city = await geographicScope(database, viewerId, (url.searchParams.get('city') ?? '').trim(), now)
  const feedback = mode === 'for_you' ? await readDiscoveryRecommendationFeedback(database, viewerId) : null
  const cursorScope: DiscoveryCursorScope = { viewerId, mode, city, windowDays, query: JSON.stringify([query.fingerprint, feedback?.revision ?? 0]), limit }
  if (cursor.scope && discoveryCursorScopeKey(cursor.scope) !== discoveryCursorScopeKey(cursorScope)) {
    throw new DiscoveryV1RequestError('Discovery cursor does not match this account or query. Refresh and retry.', 400)
  }
  if (!city) return { ...emptyPage(mode, '', now), appliedQuery: { filters: query.filters, sort: query.sort, preferences: query.preferences } }

  const data = await readDiscoveryData(database, viewerId, city, now)
  const candidates = rankDiscovery(mode, data, windowDays, query)
  const ranked = feedback ? applyDiscoveryRecommendationFeedback(candidates, feedback, query.sort === 'recommended') : candidates
  const pages = mode === 'trending'
    ? Array.from({ length: Math.ceil(ranked.length / limit) }, (_, index) => ranked.slice(index * limit, (index + 1) * limit))
    : discoveryExplorationPages(ranked, item => item.card.reasons.some(reason => reason.code === 'SHORT_TERM_DIVERSITY'), limit, query.preferences)
  const visible = pages[cursor.page] ?? []
  const firstRank = pages.slice(0, cursor.page).reduce((total, page) => total + page.length, 1)
  const items = visible.map(({ card }, index) => ({
    ...freeOrPremiumCard(card, access.isPremium),
    rank: firstRank + index,
  }))
  if (mode === 'similar_taste') {
    const activityPool = await loadActivityPhotoPool(database, viewerId, items.flatMap((item) => item.activity ? [item.activity.visitId] : []))
    for (const item of items) {
      if (!item.activity || !item.sourceUser) continue
      // This dedicated pool already checked the viewer's real friendship in SQL.
      // A public Visit can still contain an authorized friends-only photo.
      const photos = activityPool.activityPhotos(item.activity.visitId, item.sourceUser.userId, viewerId, true)
      item.activity = { ...item.activity, photos: photos.map((selection) => photoProjection(selection)!) }
      if (photos.some(({ photo }) => photo.visibility === 'friends' || photo.visit_visibility === 'friends' || photo.profile_visibility === 'friends')) {
        item.cacheScope = 'friends'
      }
    }
  }
  return {
    apiVersion: DISCOVERY_API_VERSION,
    mode,
    city,
    filterCapabilities: DISCOVERY_FILTER_CAPABILITIES,
    filterTaxonomy: DISCOVERY_FILTER_TAXONOMY,
    appliedQuery: { filters: query.filters, sort: query.sort, preferences: query.preferences },
    personalizationConfidence: confidence(mode, data, ranked),
    generatedAt: new Date(now).toISOString(),
    ...(mode === 'similar_taste' ? { evidenceAvailability: {
      ...tastePersonalEvidence(similaritySignals(new Map(), groupPlaces(data.ownVisits, data.identitiesByRestaurant, true), new Set()), viewerId),
      localDirectRestaurantCount: ranked.length,
    } } : {}),
    items,
    nextCursor: cursor.page + 1 < pages.length
      ? encodeCursor(cursor.page + 1, now, cursorScope)
      : null,
  }
}

function freeOrPremiumCard(
  card: Omit<DiscoveryCardV1, 'rank'>,
  isPremium: boolean,
): Omit<DiscoveryCardV1, 'rank'> {
  if (isPremium) return card
  return {
    ...card,
    reasons: card.reasons.slice(0, 1),
    ratings: {
      ...card.ratings,
      similarTaste: { value: null, sampleCount: 0 },
    },
    similarity: null,
  }
}

export function rankDiscovery(
  mode: DiscoveryModeV1,
  data: DiscoveryData,
  trendWindow: 7 | 30,
  query?: DiscoveryQuery,
): RankedCard[] {
  const friendIDs = acceptedFriendIDs(data.friendships, data.viewerId)
  const relationshipByUser = relationshipMap(data.friendships, data.viewerId)
  const allGroups = groupPlaces([...data.visits, ...data.ownVisits], data.identitiesByRestaurant, mode === 'similar_taste')
  const imagePool = new RestaurantUGCImagePool(data.photos)
  const groups = subsetGroups(allGroups, (visit) => visit.user_id !== data.viewerId && canonicalDiscoveryCity(visit.city) === data.city)
  addWantOnlyGroups(groups, data.wants, data.identitiesByRestaurant)
  const ownGroups = subsetGroups(allGroups, (visit) => visit.user_id === data.viewerId)
  const ownRatings = userRatingByPlace(ownGroups, data.viewerId)
  const ownVisited = new Set([...ownGroups.values()]
    .filter((group) => group.visits.some((visit) => visit.user_id === data.viewerId))
    .map((group) => group.globalKey))
  const viewerState = viewerStates(data, groups, ownVisited)
  const stableGroups = groupPlaces([...data.visits, ...data.ownVisits], data.identitiesByRestaurant, true)
  const tasteSignals = similaritySignals(subsetGroups(stableGroups, visit => visit.user_id !== data.viewerId), subsetGroups(stableGroups, visit => visit.user_id === data.viewerId), friendIDs)
  const similarities = new Map(calculateTasteSimilarities(tasteSignals, data.viewerId)
    .map((item) => [item.userId, item]))
  const preferredTags = tasteTagScores(data.ownVisits)
  // A public city leaderboard is not personalized by friendship or by omitting
  // the viewer's own public activity. Only blocks remain viewer-dependent.
  const trendData = { ...data, wants: data.wants.filter((want) => want.profile_visibility === 'public') }
  const trendGroups = subsetGroups(allGroups, (visit) => isPublicVisit(visit) &&
    canonicalDiscoveryCity(visit.city) === data.city)
  addWantOnlyGroups(trendGroups, trendData.wants, data.identitiesByRestaurant)

  // Full owner history remains intact. Apply hard conditions only to merged
  // candidate entities, before recommendation eligibility and ranking.
  if (query) {
    for (const candidates of [groups, trendGroups]) {
      for (const [key, group] of candidates) {
        const publicVisits = (allGroups.get(key)?.visits ?? group.visits).filter(isPublicVisit)
        const actualPhoto = !!resolveRestaurantVisualSelection(imagePool, {
          surface: mode, restaurantIDs: group.restaurantIDs, viewerID: data.viewerId,
        }) || (mode === 'similar_taste' && group.visits.some(visit => isViewerVisibleVisit(visit, friendIDs) &&
          !!resolveRestaurantVisualSelection(imagePool, { surface: mode, restaurantIDs: group.restaurantIDs,
            viewerID: data.viewerId, activityVisitID: visit.visit_id, canSeeFriendsActivity: friendIDs.has(visit.user_id) })))
        const rating = ratingFor(publicVisits)
        if (!matchesDiscoveryHardFilters({ ...group.restaurant,
          publicScoreOutOfTen: rating.value === null ? null : rating.value * 2,
          publicRatingUsers: new Set(publicVisits.filter(visit => visit.aggregate.ratingCount > 0).map(visit => visit.user_id)).size,
          viewerState: viewerState.get(key) ?? 'none', actualPhoto,
        }, query.filters)) candidates.delete(key)
      }
    }
  }

  let ranked: RankedCard[]
  const includeVisited = query?.viewerStateFilterExplicit === true &&
    (query.filters.viewerStates.length === 0 || query.filters.viewerStates.includes('visited'))
  if (mode === 'similar_taste') {
    ranked = similarTasteCards(
      data, groups, ownVisited, viewerState, friendIDs, relationshipByUser,
      similarities, ownRatings, imagePool,
      ownGroups, includeVisited,
    )
  } else if (mode === 'trending') {
    ranked = trendingCards(
      trendData, trendGroups, viewerState, friendIDs, relationshipByUser,
      similarities, ownRatings, trendWindow, imagePool,
    )
  } else {
    ranked = forYouCards(
      data, groups, ownVisited, viewerState, friendIDs, relationshipByUser,
      similarities, ownRatings, preferredTags, ownGroups, imagePool, includeVisited,
    )
    // Missing personal evidence is an honest empty result. Trends belong to
    // their own surface, not a filler for a paid or under-sampled For You feed.
  }
  if (query) ranked = ranked.filter(({ card }) => {
    const predicted = card.predictedLiking?.scoreOutOfTen
    const match = card.personalTastePercent
    return (query.filters.minimumPredictedLikingOutOfTen == null || (predicted != null && predicted >= query.filters.minimumPredictedLikingOutOfTen))
      && (query.filters.minimumTasteMatchPercent == null || (match != null && match >= query.filters.minimumTasteMatchPercent))
  }).map(item => {
    const projection = item.card
    let score = item.score
    if (query.sort === 'taste') score = projection.personalTastePercent ?? -1
    else if (query.sort === 'predicted_liking') score = projection.predictedLiking?.scoreOutOfTen ?? -1
    else if (query.sort === 'public_rating') score = discoveryPublicRatingRank(projection.ratings.community.value, projection.ratings.community.sampleCount)
    else if (query.sort === 'similar_rating') score = projection.ratings.similarTaste.value ?? -1
    else if (query.sort === 'distance') score = -(discoveryDistanceMeters(projection.restaurant, query.filters.distance!.reference) ?? Number.MAX_SAFE_INTEGER)
    else if (query.sort === 'recommended') score += discoverySessionPreferenceBonus({
      distanceMeters: query.preferences.reference ? discoveryDistanceMeters(projection.restaurant, query.preferences.reference) : null,
      reliablePrice: groups.has(projection.restaurant.globalKey)
        ? resolveRecordedMoney(groupPriceEvidence(groups.get(projection.restaurant.globalKey)!).pricePerPerson) : null,
      // Occasion eligibility still requires real occasion provenance.
    }, query.preferences)
    return { card: { ...projection, score: rounded(score) }, score }
  })
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
  // Read complete sufficient statistics first. Capacity errors must escape
  // before any ranking or successful-page projection can be produced.
  const cityAggregates = await readDiscoveryVisitAggregates(database, { viewerID: viewerId, city, now })
  const candidateUserIDs = unique(cityAggregates.filter(row => row.userID !== viewerId).map(row => row.userID))
  // Cross-city relationships are bounded to users with visible local activity.
  // Authorization and capacity checks remain identical; target cards stay local.
  const aggregates = candidateUserIDs.length ? await readDiscoveryVisitAggregates(database, { viewerID: viewerId, city, now, candidateUserIDs }) : cityAggregates
  const visits: DiscoveryVisitRow[] = aggregates.map((aggregate) => ({
    ...aggregate.metadata,
    visit_id: aggregate.latestVisit.id,
    user_id: aggregate.userID,
    restaurant_id: aggregate.restaurantID,
    visited_at: aggregate.latestVisit.visitedAt,
    rating: aggregate.latestVisit.rating,
    visibility: aggregate.visibility,
    profile_visibility: aggregate.profileVisibility,
    aggregate,
  })).sort((left, right) => right.visited_at.localeCompare(left.visited_at) || left.visit_id.localeCompare(right.visit_id))
  const snapshot = new Date(now).toISOString()
  const identityCandidates = JSON.stringify(await discoveryRestaurantCandidates(database, viewerId, city, {
    restaurantOwners: [viewerId, ...candidateUserIDs],
  }))
  const cityOwnerCandidates = JSON.stringify(await discoveryRestaurantCandidates(database, viewerId, city, { includeOwnWants: true }))
  const cityClause = "TRIM(r.city) IN (?, ?)"
  const cityBindings = [city, `${city}市`]
  const unblocked = (owner: string) => `NOT EXISTS (
    SELECT 1 FROM user_blocks ub WHERE ub.deleted_at IS NULL AND (
      (ub.blocker_user_id = ? AND ub.blocked_user_id = ${owner}) OR
      (ub.blocker_user_id = ${owner} AND ub.blocked_user_id = ?)
    )
  )`
  const statements = [
    database.prepare(`SELECT DISTINCT i.restaurant_id, i.provider, i.external_id, i.is_primary
      FROM json_each(?) candidates CROSS JOIN restaurants r ON r.id = candidates.value
      CROSS JOIN restaurant_place_identities i ON i.restaurant_id = r.id
      WHERE r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
        AND (${cityClause} OR r.user_id = ? OR r.user_id IN (SELECT value FROM json_each(?)))`)
      .bind(identityCandidates, ...cityBindings, viewerId, JSON.stringify(candidateUserIDs)),
    database.prepare(`SELECT id, requester_id, addressee_id, status, deleted_at
      FROM friendships WHERE requester_id = ? OR addressee_id = ?`)
      .bind(viewerId, viewerId),
    database.prepare(`SELECT followed_user_id FROM follows
      WHERE follower_id = ? AND deleted_at IS NULL`).bind(viewerId),
    database.prepare(`SELECT id, status, name, address, city, latitude, longitude
      FROM restaurants WHERE user_id = ? AND deleted_at IS NULL
        AND COALESCE(is_test_data, 0) = 0`).bind(viewerId),
    database.prepare(`SELECT w.user_id, w.restaurant_id, w.created_at,
        r.name AS restaurant_name, r.address, r.city, r.latitude, r.longitude,
        r.tags_json, r.price_per_person, r.merchant_image_url, r.marker_emoji,
        up.visibility AS profile_visibility
      FROM json_each(?) candidates CROSS JOIN restaurants r ON r.id = candidates.value
      CROSS JOIN want_to_go w ON w.restaurant_id = r.id
      JOIN user_profiles up ON up.user_id = w.user_id AND up.deleted_at IS NULL
      WHERE w.deleted_at IS NULL AND COALESCE(w.is_test_data, 0) = 0 AND r.deleted_at IS NULL
        AND COALESCE(r.is_test_data, 0) = 0 AND (${cityClause} OR w.user_id = ?)
        AND (up.visibility = 'public' OR w.user_id = ?)
        AND ${unblocked('w.user_id')} AND julianday(w.created_at) <= julianday(?)
      UNION ALL
      SELECT r.user_id, r.id, r.created_at, r.name, r.address, r.city,
        r.latitude, r.longitude, r.tags_json, r.price_per_person,
        r.merchant_image_url, r.marker_emoji, up.visibility AS profile_visibility
      FROM json_each(?) candidates CROSS JOIN restaurants r ON r.id = candidates.value
      JOIN user_profiles up ON up.user_id = r.user_id AND up.deleted_at IS NULL
      WHERE r.deleted_at IS NULL AND COALESCE(r.is_test_data, 0) = 0
        AND (${cityClause} OR r.user_id = ?) AND r.status = 'wantToGo'
        AND (up.visibility = 'public' OR r.user_id = ?)
        AND ${unblocked('r.user_id')} AND julianday(r.created_at) <= julianday(?)
      LIMIT 5001`)
      .bind(cityOwnerCandidates, ...cityBindings, viewerId, viewerId, viewerId, viewerId, snapshot,
        cityOwnerCandidates, ...cityBindings, viewerId, viewerId, viewerId, viewerId, snapshot),
    database.prepare(`SELECT p.id, p.restaurant_id, p.visit_id, p.user_id, p.kind, p.visibility,
        p.storage_key, p.thumbnail_storage_key, p.sync_status,
        v.visibility AS visit_visibility, up.visibility AS profile_visibility,
        p.created_at, p.sort_order, r.marker_photo_id, p.deleted_at,
        CASE WHEN EXISTS (
          SELECT 1 FROM content_reports cr WHERE cr.status = 'actioned' AND (
            (cr.content_type = 'visit' AND cr.content_id = p.visit_id) OR
            (cr.content_type = 'user' AND cr.content_id = p.user_id)
          )
        ) THEN 0 ELSE 1 END AS moderation_eligible
      FROM photos p
      LEFT JOIN visits v ON v.id = p.visit_id AND v.user_id = p.user_id
      JOIN restaurants r ON r.id = p.restaurant_id AND r.user_id = p.user_id
      JOIN user_profiles up ON up.user_id = p.user_id AND up.deleted_at IS NULL
      WHERE p.kind IN ('visit', 'dish')
        AND p.deleted_at IS NULL AND (p.visit_id IS NULL OR (v.id IS NOT NULL AND v.deleted_at IS NULL)) AND r.deleted_at IS NULL
        AND COALESCE(r.is_test_data, 0) = 0
        AND ${cityClause} AND p.storage_provider = 'r2'
        AND (p.user_id = ? OR NOT EXISTS (
          SELECT 1 FROM user_blocks pub WHERE pub.deleted_at IS NULL AND (
            (pub.blocker_user_id = ? AND pub.blocked_user_id = p.user_id) OR
            (pub.blocker_user_id = p.user_id AND pub.blocked_user_id = ?)
          )
        )) AND (
          p.user_id = ? OR
          (p.visibility = 'public' AND (v.id IS NULL OR v.visibility = 'public') AND up.visibility = 'public') OR (
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
      AND p.sync_status = 'synced' AND LENGTH(TRIM(COALESCE(p.storage_key, ''))) > 0
      AND LENGTH(TRIM(COALESCE(p.thumbnail_storage_key, ''))) > 0
      AND (v.id IS NULL OR COALESCE(v.is_test_data, 0) = 0)
      ORDER BY p.sort_order ASC, p.created_at DESC, p.id ASC LIMIT ${DISCOVERY_PHOTO_SCAN_LIMIT + 1}`)
      .bind(...cityBindings, viewerId, viewerId, viewerId, viewerId, viewerId, viewerId),
  ]
  const results = await database.batch(statements)
  assertCompleteDiscoveryPhotos(results[5].results.length)
  if (results[4].results.length > 5_000) throw new DiscoveryV1RequestError('Saved-intent data exceeds the supported complete-query capacity.', 503, 'discovery_capacity_exceeded')
  return {
    viewerId,
    city,
    now,
    visits: visits.filter((visit) => visit.user_id !== viewerId),
    ownVisits: visits.filter((visit) => visit.user_id === viewerId),
    identitiesByRestaurant: identityMap(results[0].results as unknown as RestaurantIdentityRow[]),
    friendships: results[1].results as unknown as FriendshipRow[],
    following: new Set((results[2].results as Array<{ followed_user_id: string }>).map((row) => row.followed_user_id)),
    viewerRestaurants: results[3].results as unknown as ViewerRestaurantRow[],
    wants: (results[4].results as unknown as WantRow[]).filter(want => canonicalDiscoveryCity(want.city) === city),
    ownerWants: (results[4].results as unknown as WantRow[]).filter(want => want.user_id === viewerId),
    photos: results[5].results as unknown as RestaurantUGCPhotoRecord[],
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
  ownGroups: Map<string, PlaceGroup>,
  imagePool: RestaurantUGCImagePool,
  includeVisited = false,
) {
  const history = historyPlaces(ownGroups)
  const likingHistory = [...ownGroups.values()].map(group => {
    const own = group.visits.filter(visit => visit.user_id === data.viewerId)
    const ratedVisitCount = own.reduce((sum, visit) => sum + visit.aggregate.ratingCount, 0)
    return { id: group.globalKey, tags: group.restaurant.tags, city: group.restaurant.city,
      price: groupPriceEvidence(group).pricePerPerson,
      scoreOutOfTen: ratedVisitCount ? own.reduce((sum, visit) => sum + visit.aggregate.ratingSum, 0) * 2 / ratedVisitCount : null,
      visitCount: own.reduce((sum, visit) => sum + visit.aggregate.visitCount, 0), ratedVisitCount }
  })
  const wantGroups = new Map<string, PlaceGroup>()
  addWantOnlyGroups(wantGroups, (data.ownerWants ?? data.wants).filter(want => want.user_id === data.viewerId), data.identitiesByRestaurant)
  const wantHistory = [...wantGroups.values()].map(group => ({
    canonicalID: group.globalKey, name: group.restaurant.name, tags: group.restaurant.tags,
    ownerRestaurantIDs: group.restaurantIDs,
    ratingCount: 0, ratingSumOutOfFive: 0, visitCount: 0, pricePerPerson: null,
  }))
  return [...groups.values()].flatMap((group): RankedCard[] => {
    if (!includeVisited && ownVisited.has(group.globalKey)) return []
    const publicVisits = group.visits.filter(isPublicVisit)
    const qualityVisits = group.visits.flatMap(qualifiedVisitSource)
    if (!qualityVisits.length) return []
    const source = [...qualityVisits].sort((left, right) =>
      right.visited_at.localeCompare(left.visited_at) || left.visit_id.localeCompare(right.visit_id),
    )[0]
    const matchedTags = group.restaurant.tags
      .map((tag) => ({ tag, score: preferredTags.get(normalize(tag)) ?? 0 }))
      .filter((item) => item.score > 0).sort((a, b) => b.score - a.score)
    const community = ratingFor(publicVisits)
    const personalReference = closestPersonalRestaurant(
      group,
      ownGroups,
      ownRatings,
    )
    const establishedReasons: DiscoveryReasonV1[] = recommendationHistoryReasons({
      tags: group.restaurant.tags, ...groupPriceEvidence(group),
      explorationEligible: community.value != null && community.value >= 3.5,
    }, history, { now: data.now })
    const reasons: DiscoveryReasonV1[] = establishedReasons.length ? establishedReasons
      : recommendationColdStartReasons({ canonicalID: group.globalKey, tags: group.restaurant.tags }, history, wantHistory)
    // A For You placement must have personal evidence. Public quality remains
    // a minimum-quality gate and tie-break, never the recommendation author.
    if (!reasons.length) return []
    const preliminary = reasons.some(reason => reason.code === 'INITIAL_HISTORY_MATCH' || reason.code === 'WANT_TO_GO_MATCH')
    const personalTastePercent = preliminary || reasons[0]?.code === 'SHORT_TERM_DIVERSITY' ? null : personalReference?.percent
      ?? personalTastePredictionFromTagScore(matchedTags[0]?.score)
    const score = (personalReference?.similarity ?? 0) * 100 +
      (matchedTags[0]?.score ?? 0) * 10 + (community.value ?? 0) * 2 +
      recencyScore(source.visited_at, data.now) * 3
    return [{
      score,
      card: { ...card(
        'for_you', group, states, friendIDs, relationships, data.following,
        similarities, ownRatings, reasons, source, score,
        personalTastePercent, null, imagePool, data.viewerId,
      ), predictedLiking: predictLiking({ id: group.globalKey, tags: group.restaurant.tags,
        city: group.restaurant.city, price: groupPriceEvidence(group).pricePerPerson }, likingHistory) },
    }]
  })
}

function personalTastePredictionFromTagScore(score: number | undefined) {
  if (!score || score <= 0) return null
  // This signal comes only from tags on the viewer's qualifying high-rated
  // Visits. Keep it below the concrete Restaurant-similarity ceiling.
  return Math.round(65 + Math.min(1, score / 4) * 25)
}

/**
 * Restores the established Web explanation: compare a candidate with one
 * concrete Restaurant from the viewer's own high-rated history. The displayed
 * percentage is Restaurant-feature similarity (tags + price), not a rating,
 * user-similarity score, or opaque ranking score.
 */
function closestPersonalRestaurant(
  candidate: PlaceGroup,
  ownGroups: Map<string, PlaceGroup>,
  _ownRatings: Map<string, number>,
) {
  const reference = recommendationHistoryReference({ tags: candidate.restaurant.tags, ...groupPriceEvidence(candidate) }, historyPlaces(ownGroups))
  if (!reference) return null
  const tags = new Set([...candidate.restaurant.tags, ...reference.place.tags].map(normalize))
  const common = new Set(candidate.restaurant.tags.map(normalize).filter(tag => reference.place.tags.some(other => normalize(other) === tag)))
  const candidatePrice = groupPriceEvidence(candidate).pricePerPerson
  const historyPrice = reference.place.pricePerPerson
  const priceSimilarity = candidatePrice && historyPrice ? Math.max(0, 1 - Math.abs(candidatePrice - historyPrice) / Math.max(candidatePrice, historyPrice)) : 0
  const similarity = Math.min(.97, .55 + (tags.size ? common.size / tags.size : 0) * .30 + priceSimilarity * .09 + reference.ratingOutOfTen / 10 * .03)
  return { name: reference.place.name, percent: Math.round(similarity * 100), similarity }
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
  imagePool: RestaurantUGCImagePool,
  _ownGroups: Map<string, PlaceGroup>,
  includeVisited = false,
) {
  const ranked = [...groups.values()].flatMap(group => {
    if ((!includeVisited && ownVisited.has(group.globalKey)) || canonicalDiscoveryCity(group.restaurant.city) !== data.city) return []
    const eligible = group.visits.filter(visit => qualifiesAsSimilarTasteUser(similarities.get(visit.user_id)) && isViewerVisibleVisit(visit, friendIDs))
    const candidates = eligible.flatMap(qualifiedVisitSource)
    if (!candidates.length) return []
    const userIDs = unique(eligible.filter(visit => visit.aggregate.ratingCount > 0).map(visit => visit.user_id))
    const supporters = userIDs.map(userID => {
      const rows = eligible.filter(visit => visit.user_id === userID)
      const totals = rows.reduce((sum, visit) => ({ rating: sum.rating + visit.aggregate.ratingSum, count: sum.count + visit.aggregate.ratingCount, visits: sum.visits + visit.aggregate.visitCount }), { rating: 0, count: 0, visits: 0 })
      const similarity = similarities.get(userID)!
      const ratingOutOfTen = totals.rating / totals.count * 2
      return { userID, similarity, ratingOutOfTen, strength: ratingOutOfTen + Math.max(0, ratingOutOfTen - similarity.userMeanOutOfTen), visits: totals.visits }
    })
    const source = [...candidates].sort((left, right) => {
      const a = supporters.find(item => item.userID === left.user_id)!
      const b = supporters.find(item => item.userID === right.user_id)!
      return b.strength - a.strength || b.similarity.weightedSimilarity - a.similarity.weightedSimilarity || right.visited_at.localeCompare(left.visited_at) || left.visit_id.localeCompare(right.visit_id)
    })[0]
    const similar = similarities.get(source.user_id)!
    const average = supporters.reduce((sum, item) => sum + item.ratingOutOfTen, 0) / supporters.length
    const name = source.profile_display_name?.trim() || '这位用户'
    const repeated = supporters.filter(item => item.visits >= 2).length
    const reasons: DiscoveryReasonV1[] = [
      { code: 'SIMILAR_USERS', text: `与你共同评过${similar.sharedRestaurantCount}家餐厅，双方对高低分的判断较接近。` },
      { code: 'SOURCE_VISIT_RATING', text: supporters.length === 1
        ? `${name}给过${Number(source.rating) * 2}分。`
        : supporters.length >= RECOMMENDATION_EVIDENCE_POLICY.minimumAggregateUsers
          ? `${supporters.length}位同味用户评过这家店，平均${average.toFixed(1)}分（每人代表评分的普通均分）。`
          : `${supporters.length}位同味用户评过这家店，尚不足3人，不展示同味均分。` },
    ]
    if (repeated) reasons.push({ code: 'REPEAT_VISIT_PATTERN', text: `支持这家店的同味用户中，有${repeated}位留下过再次到访记录。` })
    const weight = supporters.reduce((sum, item) => sum + item.similarity.weightedSimilarity, 0)
    const strength = supporters.reduce((sum, item) => sum + item.strength * item.similarity.weightedSimilarity, 0) / weight
    const similarity = similar.evidenceState === 'sufficient' ? {
      percent: Math.round(similar.similarity * 100), sharedRestaurantCount: similar.sharedRestaurantCount,
      evidenceState: similar.evidenceState, weightedSimilarity: similar.weightedSimilarity, userMeanOutOfTen: similar.userMeanOutOfTen,
    } : null
    const result = card('similar_taste', group, states, friendIDs, relationships, data.following, similarities, ownRatings, reasons, source, 0, null, similarity, imagePool, data.viewerId)
    result.tasteEvidence = { evidenceState: similar.evidenceState, sharedRestaurantCount: similar.sharedRestaurantCount,
      supporterCount: supporters.length, aggregation: 'equal_user_mean', latestVisibleVisitAt: [...eligible].sort((a,b) => b.visited_at.localeCompare(a.visited_at))[0].visited_at,
      records: eligible.flatMap(visit => {
        const user = publicUser(visit, friendIDs, relationships, data.following)
        return user ? [{ user, visitId: visit.visit_id, visitedAt: visit.visited_at, rating: visit.rating }] : []
      }),
    }
    if (eligible.some(visit => visit.visibility === 'friends' || visit.profile_visibility === 'friends')) result.cacheScope = 'friends'
    return [{ card: result, strength, weight: weight / supporters.length, supporters: supporters.length, recency: Date.parse(result.tasteEvidence!.latestVisibleVisitAt) }]
  })
  // Lexicographic policy is not an opaque weighted sum. Ordinal scores retain
  // the existing stable snapshot/cursor contract without pretending probability.
  ranked.sort((a,b) => b.strength - a.strength || b.weight - a.weight || b.supporters - a.supporters || b.recency - a.recency || a.card.restaurant.globalKey.localeCompare(b.card.restaurant.globalKey))
  return ranked.map((item, index): RankedCard => ({ score: ranked.length - index, card: { ...item.card, score: ranked.length - index } }))
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
  imagePool: RestaurantUGCImagePool,
  coldStart = false,
) {
  const wantPlaceKeys = new Map<string, Set<string>>()
  const mostRecentWantByPlace = new Map<string, WantRow>()
  const restaurantToPlace = new Map<string, string>()
  groups.forEach((group) => group.restaurantIDs.forEach((restaurantID) => restaurantToPlace.set(restaurantID, group.globalKey)))
  data.wants.forEach((want) => {
    const key = restaurantToPlace.get(want.restaurant_id)
    if (!key || !isWithinWindow(want.created_at, data.now, 30)) return
    wantPlaceKeys.set(key, new Set([...(wantPlaceKeys.get(key) ?? []), want.user_id]))
  })
  data.wants.forEach((want) => {
    const key = restaurantToPlace.get(want.restaurant_id)
    if (!key || !isWithinWindow(want.created_at, data.now, 30)) return
    const current = mostRecentWantByPlace.get(key)
    if (!current || want.created_at > current.created_at) mostRecentWantByPlace.set(key, want)
  })
  return [...groups.values()].flatMap((group): RankedCard[] => {
    const publicVisits = group.visits.filter(isPublicVisit)
    const recent = publicVisits.filter((visit) => isWithinWindow(visit.visited_at, data.now, windowDays))
    const { uniqueVisitorCount, highRatingUserCount } = trendFromDiscoveryAggregates(
      publicVisits.map((visit) => visit.aggregate), data.now, windowDays,
    )
    const rawWants = wantPlaceKeys.get(group.globalKey)?.size ?? 0
    // Want-to-go records do not yet carry a visibility contract. Treat an
    // isolated save as private and expose only a small aggregate cohort.
    const wants = rawWants >= 2 ? rawWants : 0
    if (!uniqueVisitorCount && !wants) return []
    const source = [...recent].sort((left, right) =>
      right.visited_at.localeCompare(left.visited_at) || left.user_id.localeCompare(right.user_id),
    )[0] ?? publicVisits[0]
    const mostRecentWant = mostRecentWantByPlace.get(group.globalKey)
    const reasons: DiscoveryReasonV1[] = [{
      code: coldStart ? 'COLD_START_TRENDING' : 'TRENDING_UNIQUE_USERS',
      text: coldStart
        ? `你的口味数据还不够，先看看${data.city}近期热门`
        : `近 ${windowDays} 天有 ${uniqueVisitorCount} 位用户到访`,
    }]
    if (wants > 0) reasons.push({ code: 'RECENT_WANT_TO_GO', text: `近期有 ${wants} 位用户加入想吃` })
    const score = uniqueVisitorCount * (windowDays === 7 ? 12 : 7) + wants * 4 + highRatingUserCount * 3 +
      recencyScore(source?.visited_at ?? mostRecentWant?.created_at ?? new Date(0).toISOString(), data.now) * 2
    const base = card(
      coldStart ? 'for_you' : 'trending', group, states, friendIDs,
      relationships, data.following, similarities, ownRatings, reasons, source, score,
      null, null, imagePool, data.viewerId,
    )
    return [{
      score,
      card: {
        ...base,
        trend: { windowDays, uniqueVisitorCount, wantToGoCount: wants },
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
  personalTastePercent: number | null,
  similarity: { percent: number; sharedRestaurantCount: number } | null,
  imagePool: RestaurantUGCImagePool,
  viewerID: string,
): Omit<DiscoveryCardV1, 'rank'> {
  const publicVisits = group.visits.filter(isPublicVisit)
  const friendVisits = group.visits.filter((visit) => friendIDs.has(visit.user_id))
  const similarVisits = group.visits.filter((visit) => qualifiesAsSimilarTasteUser(similarities.get(visit.user_id)) && isViewerVisibleVisit(visit, friendIDs))
  const identifiesActivity = mode === 'similar_taste'
  const selectedPhoto = resolveRestaurantVisualSelection(imagePool, {
    surface: mode,
    restaurantIDs: group.restaurantIDs,
    viewerID,
    activityVisitID: source?.visit_id,
    canSeeFriendsActivity: source?.visibility === 'friends',
  })
  // A For You card may be ranked by a friends-only Visit even though the UI
  // intentionally does not expose that Visit as an attribution source.
  const cacheScope: DiscoveryCacheScopeV1 = source?.visibility === 'friends' || source?.profile_visibility === 'friends'
    ? 'friends' : 'public'
  return {
    id: `${mode}:${group.globalKey}`,
    mode,
    restaurant: { ...group.restaurant, photo: photoProjection(selectedPhoto) },
    viewerState: states.get(group.globalKey) ?? 'none',
    ratings: {
      mine: ratingProjection(ownRatings.get(group.globalKey)),
      community: ratingFor(publicVisits),
      friends: ratingFor(friendVisits),
      similarTaste: similarTasteRatingFor(similarVisits),
    },
    reasons: reasons.slice(0, 3),
    sourceUser: identifiesActivity && source ? publicUser(source, friendIDs, relationships, following) : null,
    activity: identifiesActivity && source ? {
      visitId: source.visit_id,
      visitedAt: source.visited_at,
      rating: source.rating,
    } : null,
    similarity,
    trend: null,
    cacheScope,
    score: rounded(score),
    personalTastePercent,
  }
}

function groupPlaces(
  visits: DiscoveryVisitRow[],
  identitiesByRestaurant: Map<string, DiscoveryPlaceIdentityV1[]>,
  stableIdentityOnly = false,
) {
  // Identity-only Restaurant rows can supply a legitimate dish photo without
  // an attached Visit. Include their explicit provider aliases in the entity
  // graph, but never create recommendation evidence from those metadata rows.
  const restaurantIDs = unique([...visits.map((visit) => visit.restaurant_id), ...identitiesByRestaurant.keys()])
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
  const firstVisitByRestaurant = new Map<string, DiscoveryVisitRow>()
  visits.forEach((visit) => {
    if (!firstVisitByRestaurant.has(visit.restaurant_id)) firstVisitByRestaurant.set(visit.restaurant_id, visit)
  })
  restaurantIDs.forEach((restaurantID) => {
    for (const identity of identitiesByRestaurant.get(restaurantID) ?? []) {
      if (identity.provider === 'manual' || !identity.externalId.trim()) continue
      const identityKey = `${identity.provider}:${identity.externalId.trim()}`
      const owner = identityOwner.get(identityKey)
      if (owner) union(owner, restaurantID)
      else identityOwner.set(identityKey, restaurantID)
    }
    const visit = firstVisitByRestaurant.get(restaurantID)
    if (!visit || stableIdentityOnly) return
    const fingerprint = placeFingerprint(visit)
    const owner = fingerprintOwner.get(fingerprint)
    if (owner) union(owner, restaurantID)
    else fingerprintOwner.set(fingerprint, restaurantID)
  })

  const byRoot = new Map<string, DiscoveryVisitRow[]>()
  const aliasesByRoot = new Map<string, string[]>()
  restaurantIDs.forEach(id => {
    const root = find(id)
    aliasesByRoot.set(root, [...(aliasesByRoot.get(root) ?? []), id])
  })
  visits.forEach((visit) => {
    const root = find(visit.restaurant_id)
    const group = byRoot.get(root)
    if (group) group.push(visit)
    else byRoot.set(root, [visit])
  })
  const result = new Map<string, PlaceGroup>()
  byRoot.forEach((groupVisits) => {
    const representative = [...groupVisits].sort((left, right) =>
      completeness(right) - completeness(left) || right.visited_at.localeCompare(left.visited_at),
    )[0]
    const externalIdentities = groupVisits.flatMap((visit) =>
      identitiesByRestaurant.get(visit.restaurant_id) ?? [],
    )
    const globalKey = stableIdentityOnly && !externalIdentities.some(identity => identity.provider !== 'manual')
      ? `restaurant:${representative.restaurant_id}` : globalPlaceKey(externalIdentities, representative)
    const identities = normalizeIdentities(externalIdentities, globalKey)
    result.set(globalKey, {
      globalKey,
      restaurantIDs: aliasesByRoot.get(find(representative.restaurant_id)) ?? unique(groupVisits.map((visit) => visit.restaurant_id)),
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
        photo: null,
      },
    })
  })
  return result
}

function photoProjection(selection: RestaurantUGCPhotoSelection | null): DiscoveryRestaurantProjectionV1['photo'] {
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
    visibility: photo.visibility,
    createdAt: photo.created_at,
    exportAllowed: selection.exportAllowed,
  }
}

function addWantOnlyGroups(
  groups: Map<string, PlaceGroup>,
  wants: WantRow[],
  identitiesByRestaurant: Map<string, DiscoveryPlaceIdentityV1[]>,
) {
  const identityToKey = new Map<string, string>()
  const restaurantToKey = new Map<string, string>()
  const fingerprintToKey = new Map<string, string>()
  groups.forEach((group) => group.identities.forEach((identity) => {
    if (identity.provider !== 'manual') identityToKey.set(`${identity.provider}:${identity.externalId}`, group.globalKey)
  }))
  groups.forEach((group) => {
    group.restaurantIDs.forEach((restaurantID) => restaurantToKey.set(restaurantID, group.globalKey))
    const visit = group.visits[0]
    if (visit) {
      const fingerprint = placeFingerprint(visit)
      if (!fingerprintToKey.has(fingerprint)) fingerprintToKey.set(fingerprint, group.globalKey)
    }
  })
  wants.forEach((want) => {
    if (restaurantToKey.has(want.restaurant_id)) return
    const identities = identitiesByRestaurant.get(want.restaurant_id) ?? []
    const matched = identities.filter((identity) => identity.provider !== 'manual')
      .map((identity) => identityToKey.get(`${identity.provider}:${identity.externalId}`))
      .find((value): value is string => Boolean(value))
    const row = { restaurant_name: want.restaurant_name, address: want.address, city: want.city,
      latitude: want.latitude, longitude: want.longitude }
    const fingerprint = placeFingerprint(row)
    const fingerprintMatch = fingerprintToKey.get(fingerprint)
    const globalKey = matched ?? fingerprintMatch ?? globalPlaceKey(identities, row)
    const existing = groups.get(globalKey)
    if (existing) {
      existing.restaurantIDs = unique([...existing.restaurantIDs, want.restaurant_id])
      existing.identities = normalizeIdentities([...existing.identities, ...identities], globalKey)
      restaurantToKey.set(want.restaurant_id, globalKey)
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
    restaurantToKey.set(want.restaurant_id, globalKey)
    if (!fingerprintToKey.has(fingerprint)) fingerprintToKey.set(fingerprint, globalKey)
    normalizedIdentities.forEach((identity) => {
      if (identity.provider !== 'manual') identityToKey.set(`${identity.provider}:${identity.externalId}`, globalKey)
    })
  })
}

function viewerStates(data: DiscoveryData, groups: Map<string, PlaceGroup>, visited: Set<string>) {
  const states = new Map<string, DiscoveryViewerRestaurantStateV1>()
  visited.forEach((key) => states.set(key, 'visited'))
  const restaurantKey = new Map<string, string>()
  const identityKey = new Map<string, string>()
  const fingerprintKey = new Map<string, string>()
  groups.forEach((group) => group.restaurantIDs.forEach((restaurantID) => restaurantKey.set(restaurantID, group.globalKey)))
  groups.forEach((group) => group.identities.forEach((identity) => {
    if (identity.provider !== 'manual') identityKey.set(`${identity.provider}:${identity.externalId}`, group.globalKey)
  }))
  groups.forEach((group) => {
    const visit = group.visits[0]
    if (!visit) return
    const fingerprint = placeFingerprint(visit)
    if (!fingerprintKey.has(fingerprint)) fingerprintKey.set(fingerprint, group.globalKey)
  })
  data.viewerRestaurants.forEach((restaurant) => {
    const ownIdentities = data.identitiesByRestaurant.get(restaurant.id) ?? []
    const matchedIdentityKey = ownIdentities
      .filter((identity) => identity.provider !== 'manual')
      .map((identity) => identityKey.get(`${identity.provider}:${identity.externalId}`))
      .find((value): value is string => Boolean(value))
    const fingerprint = placeFingerprint({ restaurant_name: restaurant.name, address: restaurant.address,
      city: restaurant.city, latitude: restaurant.latitude, longitude: restaurant.longitude })
    const key = matchedIdentityKey ?? (fingerprintKey.get(fingerprint) ?? globalPlaceKey(ownIdentities, {
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
  groups: Map<string, PlaceGroup>,
  ownGroups: Map<string, PlaceGroup>,
  friendIDs: Set<string>,
) {
  const signalsFor = (group: PlaceGroup, visits: DiscoveryVisitRow[]) => tasteSignalsFromDiscoveryAggregates(
    visits.map((visit) => visit.aggregate),
    () => ({ key: group.globalKey, tags: group.restaurant.tags }),
  )
  return [
    ...[...ownGroups.values()].flatMap((group) => signalsFor(group, group.visits)),
    ...[...groups.values()].flatMap((group) => signalsFor(group, group.visits.filter((visit) =>
      isViewerVisibleVisit(visit, friendIDs)))),
  ]
}

function historyPlaces(groups: Map<string, PlaceGroup>): RecommendationHistoryPlace[] {
  return [...groups.values()].map((group) => ({
    canonicalID: group.globalKey,
    ownerRestaurantIDs: unique(group.visits.map(visit => visit.restaurant_id)),
    representativeVisitIDs: unique(group.visits.flatMap(visit => [visit.aggregate.latestVisit.id, visit.aggregate.latestQualifiedVisit?.id].filter((id): id is string => !!id))),
    name: group.restaurant.name,
    tags: group.restaurant.tags,
    ...groupPriceEvidence(group),
    referenceRatingOutOfFive: group.visits.flatMap((visit) => [visit.aggregate.latestQualifiedVisit, visit.aggregate.latestVisit])
      .filter((source) => source?.rating != null && source.rating >= 4 && source.rating <= 5)
      .sort((left, right) => right!.visitedAt.localeCompare(left!.visitedAt))[0]?.rating ?? null,
    firstVisitedAt: group.visits.every((visit) => visit.aggregate.firstVisitedAt)
      ? group.visits.map((visit) => visit.aggregate.firstVisitedAt!).sort()[0] : null,
    lastVisitedAt: group.visits.map((visit) => visit.aggregate.latestVisit.visitedAt).sort().reverse()[0] ?? null,
    ratingCount: group.visits.reduce((sum, visit) => sum + visit.aggregate.ratingCount, 0),
    ratingSumOutOfFive: group.visits.reduce((sum, visit) => sum + visit.aggregate.ratingSum, 0),
    visitCount: group.visits.reduce((sum, visit) => sum + visit.aggregate.visitCount, 0),
  }))
}

function groupPriceEvidence(group: PlaceGroup) {
  const count = group.visits.reduce((sum, visit) => sum + (visit.aggregate.reliablePriceCount ?? 0), 0)
  const sum = group.visits.reduce((sum, visit) => sum + (visit.aggregate.reliablePriceSum ?? 0), 0)
  return { pricePerPerson: count > 0 && Number.isFinite(sum) ? sum / count : null,
    priceCurrency: LEGACY_AMOUNT_CURRENCY,
    priceReliable: count > 0 && Number.isFinite(sum) && sum > 0 }
}

function userRatingByPlace(groups: Map<string, PlaceGroup>, userId: string) {
  const result = new Map<string, number>()
  groups.forEach((group) => {
    const totals = group.visits.filter((visit) => visit.user_id === userId)
      .reduce((sum, visit) => ({
        count: sum.count + visit.aggregate.ratingCount,
        sum: sum.sum + visit.aggregate.ratingSum,
      }), { count: 0, sum: 0 })
    if (totals.count) result.set(group.globalKey, totals.sum / totals.count)
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

function isPublicVisit(visit: DiscoveryVisitRow) {
  return visit.visibility === 'public' && visit.profile_visibility === 'public'
}
function isViewerVisibleVisit(visit: DiscoveryVisitRow, friendIDs: Set<string>) {
  return isPublicVisit(visit) || (friendIDs.has(visit.user_id) && visit.visibility !== 'private' && canIdentifyProfile(visit, friendIDs))
}

function qualifiesAsSimilarTasteUser(similarity: ReturnType<typeof calculateTasteSimilarities>[number] | undefined) {
  return similarity !== undefined &&
    similarity.sharedRestaurantCount >= DISCOVERY_SIMILAR_TASTE_MINIMUM_SHARED_RESTAURANTS &&
    similarity.evidenceState !== 'insufficient'
}

function ratingFor(visits: DiscoveryVisitRow[]): DiscoveryRatingProjectionV1 {
  return ratingFromDiscoveryAggregates(visits.map((visit) => visit.aggregate))
}
function similarTasteRatingFor(visits: DiscoveryVisitRow[]): DiscoveryRatingProjectionV1 {
  const projection = ratingFor(visits)
  return { ...projection, value: projection.sampleCount >= RECOMMENDATION_EVIDENCE_POLICY.minimumAggregateUsers ? projection.value : null }
}

/** Keep one real qualifying activity per cohort; never expose its mean as a
 * Visit's rating or use a more recent low/unrated Visit as a high-score source. */
function qualifiedVisitSource(visit: DiscoveryVisitRow): DiscoveryVisitRow[] {
  const source = visit.aggregate.latestQualifiedVisit
  return source ? [{ ...visit, visit_id: source.id, visited_at: source.visitedAt, rating: source.rating }] : []
}

function ratingProjection(value: number | undefined): DiscoveryRatingProjectionV1 {
  return { value: value === undefined ? null : rounded(value), sampleCount: value === undefined ? 0 : 1 }
}

function tasteTagScores(visits: DiscoveryVisitRow[]) {
  const scores = new Map<string, number>()
  visits.forEach((visit) => {
    const { qualifiedRatingCount, qualifiedRatingSum } = visit.aggregate
    if (!qualifiedRatingCount) return
    const weight = qualifiedRatingSum - 3.5 * qualifiedRatingCount
    parseTags(visit.tags_json).forEach((tag) => scores.set(normalize(tag), (scores.get(normalize(tag)) ?? 0) + weight))
  })
  return scores
}

function ratedOwnVisitCount(visits: DiscoveryVisitRow[]) {
  return visits.reduce((count, visit) => count + visit.aggregate.ratingCount, 0)
}

function confidence(mode: DiscoveryModeV1, data: DiscoveryData, ranked: RankedCard[]): DiscoveryConfidenceV1 {
  if (!ranked.length) return 'insufficient'
  if (mode === 'trending') return ranked.length >= 5 ? 'medium' : 'low'
  if (mode === 'for_you' && ranked.every(item => item.card.reasons.some(reason => reason.code === 'INITIAL_HISTORY_MATCH' || reason.code === 'WANT_TO_GO_MATCH'))) return 'low'
  const rated = ratedOwnVisitCount(data.ownVisits)
  if (rated < 3) return 'insufficient'
  if (rated < 8) return 'medium'
  return 'high'
}

async function geographicScope(database: D1Database, viewerId: string, requested: string, now: number) {
  if (requested) return canonicalDiscoveryCity(requested)
  const profile = await database.prepare(`SELECT city FROM user_profiles
    WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(viewerId).first<{ city: string }>()
  if (profile?.city.trim()) return canonicalDiscoveryCity(profile.city)
  const recent = await database.prepare(`SELECT r.city FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
    WHERE v.user_id = ? AND v.deleted_at IS NULL AND r.deleted_at IS NULL
      AND COALESCE(r.is_test_data, 0) = 0 AND TRIM(r.city) <> ''
      AND julianday(v.visited_at) <= julianday(?)
    ORDER BY v.visited_at DESC LIMIT 1`).bind(viewerId, new Date(now).toISOString()).first<{ city: string }>()
  return canonicalDiscoveryCity(recent?.city ?? '')
}

function canonicalDiscoveryCity(value: string) {
  const city = value.trim().slice(0, 80)
  return city.length > 2 && city.endsWith('市') ? city.slice(0, -1) : city
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

interface DiscoveryCursorScope {
  viewerId: string
  mode: DiscoveryModeV1
  city: string
  windowDays: 7 | 30
  query: string
  limit: number
}

function discoveryCursorScopeKey(scope: DiscoveryCursorScope) {
  return JSON.stringify([scope.viewerId, scope.mode, scope.city, scope.windowDays, scope.query, scope.limit])
}

// Version 2 rejects legacy unscoped cursors. This is a query-consistency token,
// not an authorization grant or signature: every page rechecks viewer access.
// Future hard filters/sort must extend this scope before becoming query inputs.
function encodeCursor(page: number, snapshot: number, scope: DiscoveryCursorScope) {
  const bytes = new TextEncoder().encode(JSON.stringify([3, page, snapshot, scope]))
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

function decodeCursor(raw: string | null) {
  if (raw === null) return { page: 0, snapshot: null as number | null, scope: null as DiscoveryCursorScope | null }
  try {
    if (!raw || raw.length > 4096 || !/^[A-Za-z0-9_-]+$/.test(raw)) throw new Error('Invalid cursor encoding')
    const normalized = raw.replaceAll('-', '+').replaceAll('_', '/')
    const bytes = Uint8Array.from(atob(normalized), (value) => value.charCodeAt(0))
    const value = JSON.parse(new TextDecoder().decode(bytes))
    if (Array.isArray(value) && value.length === 4 && value[0] === 3 &&
      Number.isSafeInteger(value[1]) && value[1] >= 0 &&
      Number.isSafeInteger(value[2]) && value[2] >= 0 && value[2] <= 8_640_000_000_000_000 &&
      value[3] && typeof value[3] === 'object' && typeof value[3].viewerId === 'string' &&
      ['for_you', 'similar_taste', 'trending'].includes(value[3].mode) &&
      typeof value[3].city === 'string' && typeof value[3].query === 'string' &&
      Number.isSafeInteger(value[3].limit) && (value[3].windowDays === 7 || value[3].windowDays === 30)) {
      return { page: value[1] as number, snapshot: value[2] as number, scope: value[3] as DiscoveryCursorScope }
    }
  } catch { /* invalid cursor */ }
  throw new DiscoveryV1RequestError('Discovery cursor is invalid or outdated. Refresh and retry.', 400)
}

function emptyPage(mode: DiscoveryModeV1, city: string, now: number): DiscoveryPageV1 {
  return {
    apiVersion: DISCOVERY_API_VERSION, mode, city,
    filterCapabilities: DISCOVERY_FILTER_CAPABILITIES, filterTaxonomy: DISCOVERY_FILTER_TAXONOMY,
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
  const source = `${normalize(restaurant.restaurant_name)}|${normalize(canonicalDiscoveryCity(restaurant.city))}|${normalize(restaurant.address)}|${Math.round(restaurant.latitude * 1000)}|${Math.round(restaurant.longitude * 1000)}`
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
  const age = now - Date.parse(value)
  return Number.isFinite(age) && age >= 0 ? Math.max(0, 1 - age / (120 * DAY)) : 0
}

function isWithinWindow(value: string, now: number, days: number) {
  const age = now - Date.parse(value)
  return Number.isFinite(age) && age >= 0 && age <= days * DAY
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

function rounded(value: number) { return Math.round(value * 100) / 100 }
function unique<T>(values: T[]) { return [...new Set(values)] }
function uniqueBy<T>(values: T[], key: (value: T) => string) { return [...new Map(values.map((value) => [key(value), value])).values()] }
