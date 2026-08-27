import type { RestaurantSummary, Visit } from '../types/domain'

export type ReviewPhoto = {
  source: string | null
  photoId: string | null
  origin: 'visit' | 'restaurant' | 'provider' | 'placeholder'
}

export type ReviewMemory = {
  visitId: string
  restaurantId: string
  restaurantName: string
  city: string
  visitedAt: string
  scoreOutOfTen: number | null
  companions: string[]
  actualSpend: number | null
  note: string
  photo: ReviewPhoto
  highlightScore: number
  visitCount: number
}

export type ReviewCompanion = {
  name: string
  count: number
  restaurantCount: number
  topMeal: ReviewMemory | null
}

export type ReviewSource = {
  type: string
  label: string
  count: number
  averageScore: number | null
  repeatRestaurantCount: number
}

export type ReviewChange = {
  label: string
  value: string
  tone: 'up' | 'down' | 'neutral'
}

export type PeriodReview = {
  kind: 'month' | 'year'
  year: number
  month: number | null
  visitCount: number
  restaurantCount: number
  newRestaurantCount: number
  revisitCount: number
  actualSpend: number
  visitsWithSpend: number
  spendCoverage: number
  spendDisplay: 'hidden' | 'recorded' | 'total'
  cityCount: number
  firstVisit: ReviewMemory | null
  favorite: ReviewMemory | null
  mostVisited: ReviewMemory | null
  highlightVisit: ReviewMemory | null
  memories: ReviewMemory[]
  heroPhotos: ReviewPhoto[]
  photoMemories: Array<ReviewPhoto & { visitId: string }>
  companions: ReviewCompanion[]
  recommendationSources: ReviewSource[]
  diningPatterns: string[]
  companionInsight: ReviewCompanion | null
  sourceInsight: { title: string; body: string; source: ReviewSource } | null
  changes: ReviewChange[]
  keyRestaurants: Array<{ kind: 'first' | 'highest' | 'revisited'; label: string; memory: ReviewMemory }>
  tasteChanges: string[]
  mapFootprint: Array<{ city: string; count: number }>
  timeDistribution: Array<{ label: string; count: number }>
  comparison: { visitDelta: number; restaurantDelta: number; spendDelta: number | null } | null
  milestones: string[]
  highlights: string[]
  summary: string
}

export type OnThisDayReview = {
  month: number
  day: number
  memories: Array<ReviewMemory & { yearsAgo: number }>
}

const SOURCE_LABELS: Record<string, string> = {
  friend: '朋友推荐',
  xiaohongshu: '小红书',
  douyin: '抖音',
  dianping: '大众点评',
  blogger: '美食博主',
  self: '自己发现',
  other: '其他来源',
}

function validVisits(visits: Visit[]) {
  return visits.filter((visit) => !visit.deletedAt)
}

function dateAt(value: string) {
  return new Date(value)
}

function rating10(visit: Visit) {
  return visit.rating === null ? null : visit.rating * 2
}

function visitSpend(visit: Visit) {
  return typeof visit.myActualSpend === 'number' && Number.isFinite(visit.myActualSpend) && visit.myActualSpend >= 0
    ? visit.myActualSpend
    : null
}

function restaurantPhoto(restaurant: RestaurantSummary | undefined): ReviewPhoto {
  if (restaurant?.markerImageData || restaurant?.markerPhotoId) {
    return { source: restaurant.markerImageData, photoId: restaurant.markerPhotoId, origin: 'restaurant' }
  }
  if (restaurant?.merchantImageUrl) return { source: restaurant.merchantImageUrl, photoId: null, origin: 'provider' }
  return { source: null, photoId: null, origin: 'placeholder' }
}

function visitPhoto(visit: Visit, restaurant: RestaurantSummary | undefined): ReviewPhoto {
  const index = visit.photos.findIndex((source, photoIndex) => Boolean(source || visit.photoIds[photoIndex]))
  if (index >= 0) return { source: visit.photos[index] || null, photoId: visit.photoIds[index] || null, origin: 'visit' }
  const photoIdIndex = visit.photoIds.findIndex(Boolean)
  if (photoIdIndex >= 0) return { source: visit.photos[photoIdIndex] || null, photoId: visit.photoIds[photoIdIndex], origin: 'visit' }
  return restaurantPhoto(restaurant)
}

function unique(values: string[]) {
  return [...new Set(values.filter(Boolean))]
}

function periodBounds(year: number, month: number | null) {
  const start = month === null ? new Date(year, 0, 1) : new Date(year, month - 1, 1)
  const end = month === null ? new Date(year + 1, 0, 1) : new Date(year, month, 1)
  return { start, end }
}

function inBounds(visit: Visit, start: Date, end: Date) {
  const date = dateAt(visit.visitedAt)
  return date >= start && date < end
}

function byRestaurant(visits: Visit[]) {
  const groups = new Map<string, Visit[]>()
  visits.forEach((visit) => groups.set(visit.restaurantId, [...(groups.get(visit.restaurantId) || []), visit]))
  return groups
}

function buildMemories(restaurants: RestaurantSummary[], periodVisits: Visit[], allVisits: Visit[], periodStart: Date) {
  const restaurantMap = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const periodGroups = byRestaurant(periodVisits)
  const priorRestaurantIds = new Set(allVisits.filter((visit) => dateAt(visit.visitedAt) < periodStart).map((visit) => visit.restaurantId))
  const chronologically = [...periodVisits].sort((a, b) => dateAt(a.visitedAt).getTime() - dateAt(b.visitedAt).getTime())
  return chronologically.map((visit, index) => {
    const restaurant = restaurantMap.get(visit.restaurantId)
    const scoreOutOfTen = rating10(visit)
    const photo = visitPhoto(visit, restaurant)
    const visitCount = periodGroups.get(visit.restaurantId)?.length || 1
    const firstInPeriod = periodGroups.get(visit.restaurantId)?.[0]?.id === visit.id
    const firstEver = firstInPeriod && !priorRestaurantIds.has(visit.restaurantId)
    const highlightScore = (scoreOutOfTen ?? 0) * 4
      + (photo.origin === 'visit' ? 6 : photo.origin !== 'placeholder' ? 2 : 0)
      + (visit.note.trim() ? 5 : 0)
      + Math.min(visitCount - 1, 4) * 2
      + (firstEver ? 3 : 0)
      + (visit.companions.length ? 2 : 0)
      + index / Math.max(1, chronologically.length)
    return {
      visitId: visit.id,
      restaurantId: visit.restaurantId,
      restaurantName: restaurant?.name || '未命名餐厅',
      city: restaurant?.city || '',
      visitedAt: visit.visitedAt,
      scoreOutOfTen,
      companions: unique(visit.companions),
      actualSpend: visitSpend(visit),
      note: visit.note.trim(),
      photo,
      highlightScore,
      visitCount,
    } satisfies ReviewMemory
  })
}

function summarizeCompanions(memories: ReviewMemory[]) {
  const data = new Map<string, ReviewMemory[]>()
  memories.forEach((memory) => memory.companions.forEach((name) => data.set(name, [...(data.get(name) || []), memory])))
  return [...data.entries()].map(([name, items]) => ({
    name,
    count: items.length,
    restaurantCount: new Set(items.map((item) => item.restaurantId)).size,
    topMeal: [...items].sort((a, b) => (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1))[0] || null,
  })).sort((a, b) => b.count - a.count || b.restaurantCount - a.restaurantCount)
}

function summarizeSources(visits: Visit[]) {
  const grouped = new Map<string, Visit[]>()
  visits.forEach((visit) => {
    const key = visit.recommendationSourceType || visit.recommendationSourceText.trim()
    if (key) grouped.set(key, [...(grouped.get(key) || []), visit])
  })
  return [...grouped.entries()].map(([type, items]) => {
    const ratings = items.map(rating10).filter((value): value is number => value !== null)
    const restaurantCounts = byRestaurant(items)
    return {
      type,
      label: SOURCE_LABELS[type] || items[0]?.recommendationSourceText.trim() || type,
      count: items.length,
      averageScore: ratings.length ? ratings.reduce((sum, value) => sum + value, 0) / ratings.length : null,
      repeatRestaurantCount: [...restaurantCounts.values()].filter((group) => group.length > 1).length,
    } satisfies ReviewSource
  }).sort((a, b) => b.count - a.count || (b.averageScore ?? 0) - (a.averageScore ?? 0))
}

function periodDistribution(kind: 'month' | 'year', visits: Visit[]) {
  if (kind === 'year') {
    return Array.from({ length: 12 }, (_, index) => ({ label: `${index + 1}月`, count: visits.filter((visit) => dateAt(visit.visitedAt).getMonth() === index).length }))
  }
  return ['周一', '周二', '周三', '周四', '周五', '周六', '周日'].map((label, index) => ({
    label,
    count: visits.filter((visit) => (dateAt(visit.visitedAt).getDay() + 6) % 7 === index).length,
  }))
}

function topTags(restaurants: RestaurantSummary[], restaurantIds: Set<string>) {
  const counts = new Map<string, number>()
  restaurants.filter((restaurant) => restaurantIds.has(restaurant.id)).forEach((restaurant) => restaurant.tags.forEach((tag) => counts.set(tag, (counts.get(tag) || 0) + 1)))
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
}

function buildReview(kind: 'month' | 'year', restaurants: RestaurantSummary[], allInputVisits: Visit[], year: number, month: number | null): PeriodReview {
  const allVisits = validVisits(allInputVisits)
  const { start, end } = periodBounds(year, month)
  const periodVisits = allVisits.filter((visit) => inBounds(visit, start, end))
  const groups = byRestaurant(periodVisits)
  const memories = buildMemories(restaurants, periodVisits, allVisits, start)
  const previousStart = kind === 'month' ? new Date(year, (month || 1) - 2, 1) : new Date(year - 1, 0, 1)
  const previousEnd = start
  const previousVisits = allVisits.filter((visit) => inBounds(visit, previousStart, previousEnd))
  const previousGroups = byRestaurant(previousVisits)
  const priorRestaurantIds = new Set(allVisits.filter((visit) => dateAt(visit.visitedAt) < start).map((visit) => visit.restaurantId))
  const newRestaurantCount = [...groups.keys()].filter((id) => !priorRestaurantIds.has(id)).length
  const revisitCount = [...groups.entries()].filter(([id, visits]) => visits.length > 1 || priorRestaurantIds.has(id)).length
  const spends = periodVisits.map(visitSpend).filter((value): value is number => value !== null)
  const spendCoverage = periodVisits.length ? spends.length / periodVisits.length : 0
  const actualSpend = spends.reduce((sum, value) => sum + value, 0)
  const spendDisplay = spendCoverage === 1 && periodVisits.length ? 'total' : spendCoverage >= .6 ? 'recorded' : 'hidden'
  const favorite = [...memories].filter((memory) => memory.scoreOutOfTen !== null).sort((a, b) => (b.scoreOutOfTen ?? 0) - (a.scoreOutOfTen ?? 0) || b.highlightScore - a.highlightScore)[0] || null
  const mostVisitedGroup = [...groups.entries()].sort((a, b) => b[1].length - a[1].length)[0]
  const mostVisited = mostVisitedGroup ? memories.find((memory) => memory.restaurantId === mostVisitedGroup[0]) || null : null
  const firstVisit = memories[0] || null
  const highlightVisit = [...memories].sort((a, b) => b.highlightScore - a.highlightScore)[0] || null
  const companions = summarizeCompanions(memories)
  const recommendationSources = summarizeSources(periodVisits)
  const companionInsight = companions[0] || null
  const bestSource = [...recommendationSources].sort((a, b) => (b.averageScore ?? 0) - (a.averageScore ?? 0) || b.count - a.count)[0] || null
  const sourceInsight = bestSource ? {
    title: `${bestSource.label}在这段时间最懂你`,
    body: `验证了 ${bestSource.count} 次${bestSource.averageScore !== null ? `，到访评分平均 ${bestSource.averageScore.toFixed(1)} 分` : ''}${bestSource.repeatRestaurantCount ? `，其中 ${bestSource.repeatRestaurantCount} 家后来再次到访` : ''}。`,
    source: bestSource,
  } : null
  const restaurantIds = new Set(groups.keys())
  const tags = topTags(restaurants, restaurantIds)
  const weekendCount = periodVisits.filter((visit) => [0, 6].includes(dateAt(visit.visitedAt).getDay())).length
  const diningPatterns: string[] = []
  if (periodVisits.length >= 2) {
    if (newRestaurantCount > revisitCount) diningPatterns.push(`更常探索新店：${newRestaurantCount} 家第一次记录`)
    else if (revisitCount) diningPatterns.push(`更常回到熟悉的店：${revisitCount} 家有重复到访`)
    if (tags[0]) diningPatterns.push(`${tags[0][0]}是这段时间出现最多的口味线索`)
    if (weekendCount / periodVisits.length >= .6) diningPatterns.push('多数用餐发生在周末')
  }
  const previousSpendValues = previousVisits.map(visitSpend).filter((value): value is number => value !== null)
  const previousCoverage = previousVisits.length ? previousSpendValues.length / previousVisits.length : 0
  const comparison = periodVisits.length >= 2 && previousVisits.length >= 2 ? {
    visitDelta: periodVisits.length - previousVisits.length,
    restaurantDelta: groups.size - previousGroups.size,
    spendDelta: spendCoverage >= .6 && previousCoverage >= .6 ? actualSpend - previousSpendValues.reduce((sum, value) => sum + value, 0) : null,
  } : null
  const changes: ReviewChange[] = []
  if (comparison && comparison.visitDelta) changes.push({ label: kind === 'month' ? '比上月' : '比去年', value: `${comparison.visitDelta > 0 ? '多' : '少'} ${Math.abs(comparison.visitDelta)} 次用餐`, tone: comparison.visitDelta > 0 ? 'up' : 'down' })
  if (comparison && comparison.restaurantDelta) changes.push({ label: '餐厅变化', value: `${comparison.restaurantDelta > 0 ? '多探索' : '少探索'} ${Math.abs(comparison.restaurantDelta)} 家`, tone: comparison.restaurantDelta > 0 ? 'up' : 'down' })
  const previousTags = topTags(restaurants, new Set(previousGroups.keys())).map(([tag]) => tag)
  const tasteChanges = tags.slice(0, 3).map(([tag]) => tag).filter((tag) => !previousTags.includes(tag)).map((tag) => `更常吃 ${tag}`)
  const mapFootprint = [...new Set(memories.map((memory) => memory.city).filter(Boolean))].map((city) => ({ city, count: memories.filter((memory) => memory.city === city).length })).sort((a, b) => b.count - a.count)
  const keyRestaurants: PeriodReview['keyRestaurants'] = []
  if (firstVisit) keyRestaurants.push({ kind: 'first', label: '这一年的第一家', memory: firstVisit })
  if (favorite && favorite.visitId !== firstVisit?.visitId) keyRestaurants.push({ kind: 'highest', label: '年度最高分', memory: favorite })
  if (mostVisited && mostVisited.visitCount > 1 && !keyRestaurants.some((item) => item.memory.restaurantId === mostVisited.restaurantId)) keyRestaurants.push({ kind: 'revisited', label: '最常回去', memory: mostVisited })
  const heroPhotos = unique(memories.filter((memory) => memory.photo.origin !== 'placeholder').map((memory) => `${memory.photo.source || ''}|${memory.photo.photoId || ''}`)).slice(0, kind === 'year' ? 8 : 4).map((key) => {
    const [source, photoId] = key.split('|')
    const matched = memories.find((memory) => (memory.photo.source || '') === source && (memory.photo.photoId || '') === photoId)
    return matched?.photo || { source: null, photoId: null, origin: 'placeholder' as const }
  })
  const highlights = highlightVisit ? [`${highlightVisit.restaurantName}${highlightVisit.scoreOutOfTen !== null ? `得到 ${highlightVisit.scoreOutOfTen.toFixed(1)} 分` : ''}${highlightVisit.note ? `：“${highlightVisit.note}”` : ''}`] : []
  const milestones = [periodVisits.length >= 10 ? `记录达到 ${periodVisits.length} 次` : '', groups.size >= 10 ? `吃过 ${groups.size} 家餐厅` : '', mapFootprint.length >= 2 ? `足迹覆盖 ${mapFootprint.length} 个城市` : ''].filter(Boolean)
  const summary = periodVisits.length
    ? `${kind === 'month' ? `${month} 月` : `${year} 年`}记录了 ${periodVisits.length} 次用餐、${groups.size} 家餐厅${highlightVisit ? `，最值得记住的是 ${highlightVisit.restaurantName}` : ''}。`
    : `${kind === 'month' ? `${month} 月` : `${year} 年`}还没有可回顾的到访记录。`
  return {
    kind, year, month, visitCount: periodVisits.length, restaurantCount: groups.size, newRestaurantCount, revisitCount,
    actualSpend, visitsWithSpend: spends.length, spendCoverage, spendDisplay, cityCount: mapFootprint.length,
    firstVisit, favorite, mostVisited, highlightVisit, memories, heroPhotos,
    photoMemories: memories.filter((memory) => memory.photo.origin !== 'placeholder').map((memory) => ({ ...memory.photo, visitId: memory.visitId })),
    companions, recommendationSources, diningPatterns, companionInsight, sourceInsight, changes, keyRestaurants,
    tasteChanges, mapFootprint, timeDistribution: periodDistribution(kind, periodVisits), comparison, milestones, highlights, summary,
  }
}

export const reviewService = {
  monthly(restaurants: RestaurantSummary[], visits: Visit[], year: number, month: number) {
    return buildReview('month', restaurants, visits, year, month)
  },
  annual(restaurants: RestaurantSummary[], visits: Visit[], year: number) {
    return buildReview('year', restaurants, visits, year, null)
  },
  onThisDay(restaurants: RestaurantSummary[], visits: Visit[], now = new Date()): OnThisDayReview {
    const restaurantMap = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
    const matches = validVisits(visits).filter((visit) => {
      const date = dateAt(visit.visitedAt)
      return date.getFullYear() < now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
    })
    const groups = byRestaurant(validVisits(visits))
    const memories = matches.map((visit) => {
      const restaurant = restaurantMap.get(visit.restaurantId)
      const scoreOutOfTen = rating10(visit)
      const photo = visitPhoto(visit, restaurant)
      return {
        visitId: visit.id,
        restaurantId: visit.restaurantId,
        restaurantName: restaurant?.name || '未命名餐厅',
        city: restaurant?.city || '',
        visitedAt: visit.visitedAt,
        scoreOutOfTen,
        companions: unique(visit.companions),
        actualSpend: visitSpend(visit),
        note: visit.note.trim(),
        photo,
        highlightScore: (scoreOutOfTen ?? 0) * 4 + (photo.origin === 'visit' ? 6 : 0) + (visit.note.trim() ? 5 : 0),
        visitCount: groups.get(visit.restaurantId)?.length || 1,
        yearsAgo: now.getFullYear() - dateAt(visit.visitedAt).getFullYear(),
      }
    }).sort((a, b) => dateAt(b.visitedAt).getTime() - dateAt(a.visitedAt).getTime())
    return { month: now.getMonth() + 1, day: now.getDate(), memories }
  },
}
