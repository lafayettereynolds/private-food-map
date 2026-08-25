import type { RecommendationSourceType, RestaurantSummary, Visit } from '../types/domain'

export interface ReviewFavorite { restaurantId: string; name: string; scoreOutOfTen: number | null; visitCount: number }
export interface ReviewCompanion { name: string; count: number; restaurantCount: number }
export interface ReviewSource { type: RecommendationSourceType | 'custom'; label: string; count: number; averageScore: number | null }

export interface PeriodReview {
  kind: 'month' | 'year'
  year: number
  month: number | null
  visitCount: number
  restaurantCount: number
  newRestaurantCount: number
  revisitCount: number
  actualSpend: number
  cityCount: number
  favorite: ReviewFavorite | null
  mostVisited: ReviewFavorite | null
  firstVisit: { restaurantId: string; name: string; visitedAt: string } | null
  companions: ReviewCompanion[]
  recommendationSources: ReviewSource[]
  photoMemories: Array<{ visitId: string; photoId: string | null; source: string; visibility: Visit['visibility'] }>
  timeDistribution: Array<{ label: string; count: number }>
  comparison: { visitDelta: number; spendDelta: number } | null
  milestones: string[]
  highlights: string[]
  summary: string
}

export class ReviewService {
  monthly(restaurants: RestaurantSummary[], visits: Visit[], year: number, month: number) {
    const start = new Date(year, month - 1, 1)
    const end = new Date(year, month, 1)
    const previousStart = new Date(year, month - 2, 1)
    const current = validVisits(visits).filter((visit) => inRange(visit, start, end))
    const previous = validVisits(visits).filter((visit) => inRange(visit, previousStart, start))
    return buildReview('month', restaurants, visits, current, year, month, previous)
  }

  annual(restaurants: RestaurantSummary[], visits: Visit[], year: number) {
    const start = new Date(year, 0, 1)
    const end = new Date(year + 1, 0, 1)
    const previousStart = new Date(year - 1, 0, 1)
    const current = validVisits(visits).filter((visit) => inRange(visit, start, end))
    const previous = validVisits(visits).filter((visit) => inRange(visit, previousStart, start))
    return buildReview('year', restaurants, visits, current, year, null, previous)
  }

  shareable(review: PeriodReview): PeriodReview {
    return { ...review, actualSpend: 0, companions: [], recommendationSources: [], photoMemories: [], highlights: review.highlights.filter((item) => !item.includes('消费')) }
  }
}

function buildReview(kind: PeriodReview['kind'], restaurants: RestaurantSummary[], allVisits: Visit[], visits: Visit[], year: number, month: number | null, previous: Visit[]): PeriodReview {
  const byRestaurant = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const grouped = groupBy(visits, (visit) => visit.restaurantId)
  const priorVisits = validVisits(allVisits).filter((visit) => !visits.includes(visit) && Date.parse(visit.visitedAt) < Math.min(...visits.map((item) => Date.parse(item.visitedAt)), Date.now()))
  const priorRestaurantIds = new Set(priorVisits.map((visit) => visit.restaurantId))
  const newRestaurantCount = [...grouped.keys()].filter((id) => !priorRestaurantIds.has(id)).length
  const revisitCount = visits.filter((visit, index) => visits.findIndex((item) => item.restaurantId === visit.restaurantId) !== index || priorRestaurantIds.has(visit.restaurantId)).length
  const favorites = [...grouped].map(([restaurantId, entries]) => {
    const rated = entries.flatMap((visit) => visit.rating === null ? [] : [visit.rating * 2])
    return { restaurantId, name: byRestaurant.get(restaurantId)?.name ?? '已删除餐厅', scoreOutOfTen: rated.length ? average(rated) : null, visitCount: entries.length }
  })
  const favorite = [...favorites].filter((item) => item.scoreOutOfTen !== null).sort((a, b) => (b.scoreOutOfTen ?? 0) - (a.scoreOutOfTen ?? 0) || b.visitCount - a.visitCount)[0] ?? null
  const mostVisited = [...favorites].sort((a, b) => b.visitCount - a.visitCount || (b.scoreOutOfTen ?? 0) - (a.scoreOutOfTen ?? 0))[0] ?? null
  const companions = rankStrings(visits.flatMap((visit) => visit.companions)).map(([name, count]) => ({
    name,
    count,
    restaurantCount: new Set(visits.filter((visit) => visit.companions.includes(name)).map((visit) => visit.restaurantId)).size,
  }))
  const sourceRestaurants = [...grouped].flatMap(([restaurantId, entries]) => {
    const acquisition = [...entries].sort((a, b) => a.visitedAt.localeCompare(b.visitedAt)).find((visit) => visit.recommendationSourceType)
    if (!acquisition?.recommendationSourceType) return []
    return [{ restaurantId, acquisition, entries }]
  })
  const sourceGroups = groupBy(sourceRestaurants, ({ acquisition }) => reviewSourceKey(acquisition))
  const recommendationSources = [...sourceGroups].map(([, records]) => ({
    type: records[0].acquisition.recommendationSourceType as RecommendationSourceType,
    label: reviewSourceLabel(records[0].acquisition),
    count: records.length,
    averageScore: averageOrNull(records.flatMap(({ entries }) => {
      const restaurantRatings = entries.flatMap((visit) => visit.rating === null ? [] : [visit.rating * 2])
      return restaurantRatings.length ? [average(restaurantRatings)] : []
    })),
  })).sort((a, b) => b.count - a.count)
  const photoMemories = visits.flatMap((visit) => visit.photos.map((source, index) => ({ visitId: visit.id, photoId: visit.photoIds[index] ?? null, source, visibility: visit.visibility })))
  const timeDistribution = (kind === 'year' ? Array.from({ length: 12 }, (_, index) => ({ label: `${index + 1}月`, count: visits.filter((visit) => new Date(visit.visitedAt).getMonth() === index).length })) : [
    { label: '工作日', count: visits.filter((visit) => { const day = new Date(visit.visitedAt).getDay(); return day > 0 && day < 6 }).length },
    { label: '周末', count: visits.filter((visit) => { const day = new Date(visit.visitedAt).getDay(); return day === 0 || day === 6 }).length },
  ])
  const actualSpend = sumSpend(visits)
  const comparison = { visitDelta: visits.length - previous.length, spendDelta: actualSpend - sumSpend(previous) }
  const first = [...visits].sort((a, b) => a.visitedAt.localeCompare(b.visitedAt))[0]
  const milestones = [
    visits.length >= 10 ? `${kind === 'year' ? '全年' : '本月'}完成 ${visits.length} 次真实用餐记录` : '',
    grouped.size >= 5 ? `留下了 ${grouped.size} 家不同餐厅的足迹` : '',
    mostVisited && mostVisited.visitCount >= 2 ? `回到「${mostVisited.name}」${mostVisited.visitCount} 次` : '',
    companions[0] ? `和 ${companions[0].name} 一起吃了 ${companions[0].count} 次` : '',
  ].filter(Boolean)
  const highlights = [
    favorite ? `最喜欢的是「${favorite.name}」${favorite.scoreOutOfTen !== null ? `，平均 ${favorite.scoreOutOfTen.toFixed(1)} 分` : ''}` : '',
    newRestaurantCount ? `探索了 ${newRestaurantCount} 家第一次到访的餐厅` : '',
    actualSpend ? `记录的个人实际消费为 ¥${Math.round(actualSpend)}` : '',
  ].filter(Boolean).slice(0, 3)
  return {
    kind, year, month, visitCount: visits.length, restaurantCount: grouped.size, newRestaurantCount, revisitCount, actualSpend,
    cityCount: new Set(visits.map((visit) => byRestaurant.get(visit.restaurantId)?.city).filter(Boolean)).size,
    favorite, mostVisited, firstVisit: first ? { restaurantId: first.restaurantId, name: byRestaurant.get(first.restaurantId)?.name ?? '一次味觉记忆', visitedAt: first.visitedAt } : null,
    companions, recommendationSources, photoMemories, timeDistribution, comparison, milestones, highlights,
    summary: visits.length ? (favorite ? `${year} ${kind === 'month' ? `${month} 月` : '年'}，你用一次次真实到访记住了「${favorite.name}」和这一段生活。` : `${year} ${kind === 'month' ? `${month} 月` : '年'}，你留下了 ${visits.length} 次真实味觉记忆。`) : '这一段时间还没有记录，下一次用餐会成为新的开篇。',
  }
}

function validVisits(visits: Visit[]) { return visits.filter((visit) => !visit.deletedAt) }
function inRange(visit: Visit, start: Date, end: Date) { const value = Date.parse(visit.visitedAt); return value >= start.getTime() && value < end.getTime() }
function groupBy<T, K>(values: T[], key: (value: T) => K) { const result = new Map<K, T[]>(); values.forEach((value) => result.set(key(value), [...(result.get(key(value)) ?? []), value])); return result }
function rankStrings(values: string[]) { const counts = new Map<string, number>(); values.map((value) => value.trim()).filter(Boolean).forEach((value) => counts.set(value, (counts.get(value) ?? 0) + 1)); return [...counts].sort((a, b) => b[1] - a[1]) }
function sumSpend(visits: Visit[]) { return visits.reduce((sum, visit) => sum + (visit.myActualSpend ?? 0), 0) }
function average(values: number[]) { return values.reduce((sum, value) => sum + value, 0) / values.length }
function averageOrNull(values: number[]) { return values.length ? average(values) : null }
function reviewSourceKey(visit: Visit) {
  const type = visit.recommendationSourceType as RecommendationSourceType
  const identity = type === 'friend' ? visit.recommendationSourceUserId ?? 'unlinked' : type === 'other' || type === 'blogger' ? visit.recommendationSourceText.trim().toLocaleLowerCase('zh-CN') || 'unspecified' : 'aggregate'
  return `${type}:${identity}`
}
function reviewSourceLabel(visit: Visit) {
  const type = visit.recommendationSourceType as RecommendationSourceType
  if ((type === 'other' || type === 'blogger') && visit.recommendationSourceText.trim()) return visit.recommendationSourceText.trim()
  return ({ friend: '好友推荐', xiaohongshu: '小红书', douyin: '抖音', dianping: '大众点评', blogger: '美食博主', self: '自己发现', other: '自定义来源' })[type]
}

export const reviewService = new ReviewService()
