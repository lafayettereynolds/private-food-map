import type { DiningCompanion, RestaurantSummary, Visit } from '../types/domain'

export type CompanionInsightConfidence = 'INSUFFICIENT' | 'EMERGING' | 'STABLE'

export interface CompanionInsights {
  companion: DiningCompanion
  confidence: CompanionInsightConfidence
  sharedVisitCount: number
  restaurantCount: number
  repeatRestaurantCount: number
  repeatRate: number | null
  firstVisitedAt: string | null
  latestVisitedAt: string | null
  spanDays: number
  spend: { total: number | null; average: number | null; maximum: number | null; sampleCount: number }
  rating: { average: number | null; ratedVisitCount: number; highScoreCount: number }
  topCuisines: Array<{ label: string; visitCount: number; averageRating: number | null; ratedVisitCount: number }>
  topRestaurants: Array<{ restaurantId: string; name: string; visitCount: number; averageRating: number | null }>
  diningModes: Array<{ label: string; count: number }>
  occasions: Array<{ label: string; count: number }>
  cities: Array<{ label: string; count: number }>
  memories: Array<{ visitId: string; restaurantId: string; restaurantName: string; visitedAt: string; note: string; photos: string[] }>
  linkedUserStatus: 'UNLINKED' | 'LINKED_RESTRICTED'
}

export function companionInsightConfidence(sharedVisitCount: number): CompanionInsightConfidence {
  if (sharedVisitCount < 3) return 'INSUFFICIENT'
  if (sharedVisitCount < 6) return 'EMERGING'
  return 'STABLE'
}

export function buildCompanionInsights(companion: DiningCompanion, restaurants: RestaurantSummary[], visits: Visit[]): CompanionInsights {
  const normalizedName = normalize(companion.displayName)
  const sharedVisits = visits.filter((visit) => !visit.deletedAt && (
    visit.companionIds.includes(companion.id) || visit.companions.some((name) => normalize(name) === normalizedName)
  )).sort((left, right) => left.visitedAt.localeCompare(right.visitedAt))
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const restaurantGroups = groupBy(sharedVisits, (visit) => visit.restaurantId)
  const spendValues = sharedVisits.flatMap((visit) => visit.myActualSpend === null ? [] : [visit.myActualSpend])
  const ratedValues = sharedVisits.flatMap((visit) => visit.rating === null ? [] : [visit.rating * 2])
  const cuisineGroups = new Map<string, Visit[]>()
  sharedVisits.forEach((visit) => {
    const restaurant = restaurantById.get(visit.restaurantId)
    const cuisines = restaurant?.tags.slice(0, 2).filter(Boolean) ?? []
    ;(cuisines.length ? cuisines : ['未分类']).forEach((label) => cuisineGroups.set(label, [...(cuisineGroups.get(label) ?? []), visit]))
  })
  const topCuisines = [...cuisineGroups].map(([label, entries]) => {
    const ratings = entries.flatMap((visit) => visit.rating === null ? [] : [visit.rating * 2])
    return { label, visitCount: entries.length, averageRating: averageOrNull(ratings), ratedVisitCount: ratings.length }
  }).sort((a, b) => b.visitCount - a.visitCount || (b.averageRating ?? 0) - (a.averageRating ?? 0)).slice(0, 6)
  const topRestaurants = [...restaurantGroups].map(([restaurantId, entries]) => {
    const ratings = entries.flatMap((visit) => visit.rating === null ? [] : [visit.rating * 2])
    return { restaurantId, name: restaurantById.get(restaurantId)?.name ?? '已删除餐厅', visitCount: entries.length, averageRating: averageOrNull(ratings) }
  }).sort((a, b) => b.visitCount - a.visitCount || (b.averageRating ?? 0) - (a.averageRating ?? 0)).slice(0, 6)
  const repeatRestaurantCount = [...restaurantGroups.values()].filter((entries) => entries.length >= 2).length
  return {
    companion,
    confidence: companionInsightConfidence(sharedVisits.length),
    sharedVisitCount: sharedVisits.length,
    restaurantCount: restaurantGroups.size,
    repeatRestaurantCount,
    repeatRate: restaurantGroups.size ? repeatRestaurantCount / restaurantGroups.size : null,
    firstVisitedAt: sharedVisits[0]?.visitedAt ?? null,
    latestVisitedAt: sharedVisits[sharedVisits.length - 1]?.visitedAt ?? null,
    spanDays: sharedVisits.length >= 2 ? Math.max(0, Math.round((Date.parse(sharedVisits[sharedVisits.length - 1].visitedAt) - Date.parse(sharedVisits[0].visitedAt)) / 86400000)) : 0,
    spend: { total: spendValues.length ? sum(spendValues) : null, average: averageOrNull(spendValues), maximum: spendValues.length ? Math.max(...spendValues) : null, sampleCount: spendValues.length },
    rating: { average: averageOrNull(ratedValues), ratedVisitCount: ratedValues.length, highScoreCount: ratedValues.filter((value) => value >= 8).length },
    topCuisines,
    topRestaurants,
    diningModes: rankLabels(sharedVisits.map((visit) => visit.diningMode === 'takeout' ? '外卖' : '到店')),
    occasions: rankLabels(sharedVisits.flatMap((visit) => visit.diningOccasions.length ? visit.diningOccasions.map(occasionLabel) : [])),
    cities: rankLabels(sharedVisits.map((visit) => restaurantById.get(visit.restaurantId)?.city ?? '').filter(Boolean)),
    memories: [...sharedVisits].reverse().filter((visit) => visit.note || visit.photos.length).slice(0, 8).map((visit) => ({ visitId: visit.id, restaurantId: visit.restaurantId, restaurantName: restaurantById.get(visit.restaurantId)?.name ?? '一次用餐', visitedAt: visit.visitedAt, note: visit.note, photos: visit.photos })),
    linkedUserStatus: companion.linkedUserId ? 'LINKED_RESTRICTED' : 'UNLINKED',
  }
}

export function buildCompanionDirectory(companions: DiningCompanion[], visits: Visit[], ownerUserId: string) {
  const byName = new Map(companions.filter((item) => !item.deletedAt).map((item) => [normalize(item.displayName), item]))
  visits.flatMap((visit) => visit.companions).map((name) => name.trim()).filter(Boolean).forEach((displayName) => {
    if (!byName.has(normalize(displayName))) byName.set(normalize(displayName), { id: `derived-${normalize(displayName)}`, ownerUserId, displayName, linkedUserId: null, createdAt: '', updatedAt: '', deletedAt: null })
  })
  return [...byName.values()]
}

function normalize(value: string) { return value.trim().toLocaleLowerCase('zh-CN') }
function groupBy<T, K>(values: T[], key: (value: T) => K) { const result = new Map<K, T[]>(); values.forEach((value) => result.set(key(value), [...(result.get(key(value)) ?? []), value])); return result }
function sum(values: number[]) { return values.reduce((total, value) => total + value, 0) }
function averageOrNull(values: number[]) { return values.length ? Math.round(sum(values) / values.length * 10) / 10 : null }
function rankLabels(values: string[]) { const counts = new Map<string, number>(); values.forEach((value) => counts.set(value, (counts.get(value) ?? 0) + 1)); return [...counts].map(([label, count]) => ({ label, count })).sort((a, b) => b.count - a.count) }
function occasionLabel(value: Visit['diningOccasions'][number]) { return ({ solo: '一个人', date: '约会', friends: '朋友聚餐', family: '家庭聚餐', business: '商务', celebration: '庆祝', other: '其他' })[value] }
