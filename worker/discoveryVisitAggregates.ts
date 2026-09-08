import { DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE } from '../src/contracts/discoveryContract'
import type { TasteRatingSignal } from './tasteSimilarity'
import type { ProfileAvatarPresetContract } from '../src/contracts/profileContract'

// Bound aggregate cohorts, never individual Visits. An over-capacity query
// fails closed through the HTTP envelope instead of ranking a partial prefix.
export const DISCOVERY_AGGREGATE_CAPACITY = 900

export class DiscoveryAggregateCapacityError extends Error {
  readonly status = 503
  readonly code = 'DISCOVERY_AGGREGATE_CAPACITY'
  constructor() {
    super('当前城市的发现数据超出完整统计容量，请稍后重试。未返回不完整榜单。')
    this.name = 'DiscoveryAggregateCapacityError'
  }
}

export interface DiscoveryAggregateVisitSource {
  id: string
  visitedAt: string
  rating: number | null
}

/** Current Restaurant/Profile fields used by the existing identity and source
 * projections. No private Visit text or extra profile data enters this reader. */
export interface DiscoveryVisitMetadata {
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
}

export interface DiscoveryVisitAggregate {
  userID: string
  restaurantID: string
  visibility: 'private' | 'friends' | 'public'
  profileVisibility: 'private' | 'friends' | 'public' | null
  visitCount: number
  firstVisitedAt?: string
  reliablePriceCount?: number
  reliablePriceSum?: number
  ratingCount: number
  ratingSum: number
  qualifiedRatingCount: number
  qualifiedRatingSum: number
  latestVisit: DiscoveryAggregateVisitSource
  latestQualifiedVisit: DiscoveryAggregateVisitSource | null
  metadata: DiscoveryVisitMetadata
}

interface AggregateRow extends DiscoveryVisitMetadata {
  user_id: string
  restaurant_id: string
  visibility: DiscoveryVisitAggregate['visibility']
  profile_visibility: DiscoveryVisitAggregate['profileVisibility']
  visit_count: number
  first_visited_at: string
  reliable_price_count: number
  reliable_price_sum: number
  rating_count: number
  rating_sum: number
  qualified_rating_count: number
  qualified_rating_sum: number
  visit_id: string
  visited_at: string
  rating: number | null
  qualified_visit_id: string | null
  qualified_visited_at: string | null
  qualified_rating: number | null
}

/**
 * Scan eligible Visits inside SQLite, returning sufficient statistics rather
 * than raw history. The response is at most capacity + 1 rows. A capacity hit
 * rejects the entire result: callers must never rank or cache its partial prefix.
 *
 * Keep visibility partitions until authorization/public-cohort selection; keep
 * sum AND count through provider-alias merging. AVG(AVG(...)) changes the existing
 * per-user weighting. Actual activity IDs/ratings are separate from means.
 */
export async function readDiscoveryVisitAggregates(
  database: D1Database,
  scope: { viewerID: string; city: string; now: number; candidateUserIDs?: string[] },
): Promise<DiscoveryVisitAggregate[]> {
  const snapshot = new Date(scope.now).toISOString()
  const requestedCity = scope.city.trim().slice(0, 80)
  const city = requestedCity.length > 2 && requestedCity.endsWith('市') ? requestedCity.slice(0, -1) : requestedCity
  const candidateScope = scope.candidateUserIDs
  const locationPredicate = candidateScope ? 'v.user_id IN (SELECT value FROM json_each(?))' : 'TRIM(r.city) IN (?, ?)'
  const locationBindings = candidateScope ? [JSON.stringify(candidateScope)] : [city, `${city}市`]
  const rows = await database.prepare(`WITH eligible AS (
    SELECT v.id AS visit_id, v.user_id, v.restaurant_id, v.visibility,
      v.visited_at, CASE WHEN v.rating > 0 AND v.rating <= 5 THEN v.rating ELSE NULL END AS rating, up.visibility AS profile_visibility,
      CASE WHEN v.total_price > 0 AND v.party_size_optional > 0
        AND v.party_size_optional = CAST(v.party_size_optional AS INTEGER)
        THEN v.total_price / CAST(v.party_size_optional AS REAL) ELSE NULL END AS reliable_price,
      r.name AS restaurant_name, r.address, r.city, r.latitude, r.longitude,
      r.tags_json, r.price_per_person, r.merchant_image_url, r.marker_emoji,
      up.display_name AS profile_display_name, up.bio AS profile_bio,
      up.city AS profile_city, up.avatar_photo_id AS profile_avatar_photo_id,
      up.avatar_preset_id AS profile_avatar_preset_id
    FROM visits v
    JOIN restaurants r ON r.id = v.restaurant_id AND r.deleted_at IS NULL
      AND COALESCE(r.is_test_data, 0) = 0
    LEFT JOIN user_profiles up ON up.user_id = v.user_id AND up.deleted_at IS NULL
    WHERE v.deleted_at IS NULL AND COALESCE(v.is_test_data, 0) = 0
    AND NOT EXISTS (SELECT 1 FROM content_reports cr WHERE cr.status = 'actioned' AND (
      (cr.content_type = 'visit' AND cr.content_id = v.id) OR (cr.content_type = 'user' AND cr.content_id = v.user_id)))
    AND julianday(v.visited_at) <= julianday(?) AND (
      v.user_id = ? OR (
        ${locationPredicate} AND (
          (v.visibility = 'public' AND up.visibility = 'public') OR (
            v.visibility IN ('public', 'friends') AND up.visibility IN ('public', 'friends')
            AND EXISTS (SELECT 1 FROM friendships f WHERE f.deleted_at IS NULL
              AND f.status = 'accepted' AND (
                (f.requester_id = ? AND f.addressee_id = v.user_id) OR
                (f.requester_id = v.user_id AND f.addressee_id = ?)
              ))
          )
        ) AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE b.deleted_at IS NULL AND (
          (b.blocker_user_id = ? AND b.blocked_user_id = v.user_id) OR
          (b.blocker_user_id = v.user_id AND b.blocked_user_id = ?)
        ))
      )
    )
  ), ordered AS (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY user_id, restaurant_id, visibility
        ORDER BY visited_at DESC, visit_id ASC) AS latest_position,
      ROW_NUMBER() OVER (PARTITION BY user_id, restaurant_id, visibility
        ORDER BY CASE WHEN rating >= ${DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE} THEN 0 ELSE 1 END,
          visited_at DESC, visit_id ASC) AS qualified_position
    FROM eligible
  ), aggregates AS (
    SELECT user_id, restaurant_id, visibility,
      COUNT(*) AS visit_count, COUNT(rating) AS rating_count,
      MIN(visited_at) AS first_visited_at,
      COUNT(reliable_price) AS reliable_price_count,
      COALESCE(SUM(reliable_price), 0) AS reliable_price_sum,
      COALESCE(SUM(rating), 0) AS rating_sum,
      SUM(CASE WHEN rating >= ${DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE} THEN 1 ELSE 0 END) AS qualified_rating_count,
      SUM(CASE WHEN rating >= ${DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE} THEN rating ELSE 0 END) AS qualified_rating_sum
    FROM eligible GROUP BY user_id, restaurant_id, visibility
  ) SELECT a.*, latest.profile_visibility, latest.visit_id, latest.visited_at, latest.rating,
      latest.restaurant_name, latest.address, latest.city, latest.latitude, latest.longitude,
      latest.tags_json, latest.price_per_person, latest.merchant_image_url, latest.marker_emoji,
      latest.profile_display_name, latest.profile_bio, latest.profile_city,
      latest.profile_avatar_photo_id, latest.profile_avatar_preset_id,
      qualified.visit_id AS qualified_visit_id, qualified.visited_at AS qualified_visited_at,
      qualified.rating AS qualified_rating
    FROM aggregates a
    JOIN ordered latest ON latest.user_id = a.user_id AND latest.restaurant_id = a.restaurant_id
      AND latest.visibility = a.visibility AND latest.latest_position = 1
    LEFT JOIN ordered qualified ON qualified.user_id = a.user_id AND qualified.restaurant_id = a.restaurant_id
      AND qualified.visibility = a.visibility AND qualified.qualified_position = 1
      AND qualified.rating >= ${DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE}
    ORDER BY a.user_id, a.restaurant_id, a.visibility LIMIT ?`)
    .bind(snapshot, scope.viewerID, ...locationBindings, scope.viewerID, scope.viewerID,
      scope.viewerID, scope.viewerID, DISCOVERY_AGGREGATE_CAPACITY + 1).all<AggregateRow>()
  if (rows.results.length > DISCOVERY_AGGREGATE_CAPACITY) throw new DiscoveryAggregateCapacityError()
  return rows.results.map((row) => ({
    userID: row.user_id, restaurantID: row.restaurant_id, visibility: row.visibility,
    profileVisibility: row.profile_visibility, visitCount: Number(row.visit_count),
    firstVisitedAt: row.first_visited_at,
    reliablePriceCount: Number(row.reliable_price_count), reliablePriceSum: Number(row.reliable_price_sum),
    ratingCount: Number(row.rating_count), ratingSum: Number(row.rating_sum),
    qualifiedRatingCount: Number(row.qualified_rating_count), qualifiedRatingSum: Number(row.qualified_rating_sum),
    latestVisit: { id: row.visit_id, visitedAt: row.visited_at, rating: row.rating },
    latestQualifiedVisit: row.qualified_visit_id && row.qualified_visited_at ? {
      id: row.qualified_visit_id, visitedAt: row.qualified_visited_at, rating: row.qualified_rating,
    } : null,
    metadata: {
      restaurant_name: row.restaurant_name, address: row.address, city: row.city,
      latitude: row.latitude, longitude: row.longitude, tags_json: row.tags_json,
      price_per_person: row.price_per_person, merchant_image_url: row.merchant_image_url,
      marker_emoji: row.marker_emoji, profile_display_name: row.profile_display_name,
      profile_bio: row.profile_bio, profile_city: row.profile_city,
      profile_avatar_photo_id: row.profile_avatar_photo_id,
      profile_avatar_preset_id: row.profile_avatar_preset_id,
    },
  }))
}

/** Call after the unchanged provider/fingerprint graph selects one place/cohort. */
export function ratingFromDiscoveryAggregates(aggregates: DiscoveryVisitAggregate[]) {
  const users = new Map<string, { sum: number; count: number }>()
  for (const row of aggregates) {
    if (!row.ratingCount) continue
    const current = users.get(row.userID) ?? { sum: 0, count: 0 }
    current.sum += row.ratingSum
    current.count += row.ratingCount
    users.set(row.userID, current)
  }
  const means = [...users.values()].map((value) => value.sum / value.count)
  return { value: means.length ? Math.round(means.reduce((sum, value) => sum + value, 0) / means.length * 100) / 100 : null,
    sampleCount: means.length }
}

export function tasteSignalsFromDiscoveryAggregates(
  aggregates: DiscoveryVisitAggregate[],
  placeForRestaurant: (restaurantID: string) => { key: string; tags: string[] },
): TasteRatingSignal[] {
  return aggregates.flatMap((row) => {
    if (!row.ratingCount) return []
    const place = placeForRestaurant(row.restaurantID)
    return [{ userId: row.userID, poiId: place.key, tags: place.tags,
      ratingOutOfTen: row.ratingSum / row.ratingCount * 2, sampleCount: row.ratingCount }]
  })
}

export function trendFromDiscoveryAggregates(aggregates: DiscoveryVisitAggregate[], now: number, days: 7 | 30) {
  const eligible = aggregates.filter((row) => row.visibility === 'public' && row.profileVisibility === 'public')
  const recent = (source: DiscoveryAggregateVisitSource | null) => {
    const age = source ? now - Date.parse(source.visitedAt) : NaN
    return Number.isFinite(age) && age >= 0 && age <= days * 86_400_000
  }
  return {
    uniqueVisitorCount: new Set(eligible.filter((row) => recent(row.latestVisit)).map((row) => row.userID)).size,
    highRatingUserCount: new Set(eligible.filter((row) => recent(row.latestQualifiedVisit)).map((row) => row.userID)).size,
  }
}
