import type { RestaurantSocialStats } from '../src/types/restaurantStats'
import { findSimilarTasteUserIds, type TasteRatingSignal } from './tasteSimilarity'

interface TargetVisitRow {
  id: string
  user_id: string
  rating: number
  visibility: 'private' | 'friends' | 'public'
}

interface FriendshipUserRow {
  user_id: string
}

interface TasteSignalRow {
  user_id: string
  amap_poi_id: string
  rating: number
  tags_json: string
}

export async function readRestaurantSocialStats(database: D1Database, viewerId: string, amapPoiId: string): Promise<RestaurantSocialStats> {
  const [targetResult, friendResult, signalResult] = await database.batch([
    database.prepare(`SELECT DISTINCT v.id, v.user_id, v.rating, v.visibility
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
      WHERE r.amap_poi_id = ? AND r.deleted_at IS NULL AND v.deleted_at IS NULL AND v.rating IS NOT NULL`)
      .bind(amapPoiId),
    database.prepare(`SELECT CASE WHEN requester_id = ? THEN addressee_id ELSE requester_id END AS user_id
      FROM friendships WHERE status = 'accepted' AND (requester_id = ? OR addressee_id = ?)`)
      .bind(viewerId, viewerId, viewerId),
    database.prepare(`SELECT DISTINCT v.id, v.user_id, r.amap_poi_id, v.rating, r.tags_json
      FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
      WHERE v.deleted_at IS NULL AND r.deleted_at IS NULL AND v.rating IS NOT NULL
        AND (v.user_id = ? OR v.visibility = 'public')`)
      .bind(viewerId),
  ])

  const targetVisits = targetResult.results as unknown as TargetVisitRow[]
  const friendIds = new Set((friendResult.results as unknown as FriendshipUserRow[]).map((row) => row.user_id))
  const publicOtherVisits = targetVisits.filter((visit) => visit.user_id !== viewerId && visit.visibility === 'public')
  const friendVisits = targetVisits.filter((visit) => visit.user_id !== viewerId && friendIds.has(visit.user_id) && visit.visibility !== 'private')
  const signals = (signalResult.results as unknown as TasteSignalRow[]).map<TasteRatingSignal>((row) => ({
    userId: row.user_id,
    poiId: row.amap_poi_id,
    ratingOutOfTen: row.rating * 2,
    tags: readStringArray(row.tags_json),
  }))
  const similarUserIds = findSimilarTasteUserIds(signals, viewerId)
  const similarVisits = publicOtherVisits.filter((visit) => similarUserIds.has(visit.user_id))
  const publicVisitsByUser = groupRatingsByUser(publicOtherVisits)
  const repeatVisitors = [...publicVisitsByUser.values()].filter((ratings) => ratings.length >= 2).length

  return {
    overallUserRating: averageUserRatings(publicOtherVisits),
    friendAverageRating: averageUserRatings(friendVisits),
    similarTasteAverageRating: averageUserRatings(similarVisits),
    repeatVisitRate: publicVisitsByUser.size ? Math.round((repeatVisitors / publicVisitsByUser.size) * 100) : null,
  }
}

function averageUserRatings(visits: TargetVisitRow[]) {
  const grouped = groupRatingsByUser(visits)
  if (!grouped.size) return null
  const userAverages = [...grouped.values()].map((ratings) => ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length * 2)
  return roundOne(userAverages.reduce((sum, rating) => sum + rating, 0) / userAverages.length)
}

function groupRatingsByUser(visits: TargetVisitRow[]) {
  const grouped = new Map<string, number[]>()
  visits.forEach((visit) => {
    const ratings = grouped.get(visit.user_id) ?? []
    ratings.push(visit.rating)
    grouped.set(visit.user_id, ratings)
  })
  return grouped
}

function readStringArray(value: string) {
  try {
    const parsed: unknown = JSON.parse(value)
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === 'string') : []
  } catch {
    return []
  }
}

function roundOne(value: number) {
  return Math.round(value * 10) / 10
}
