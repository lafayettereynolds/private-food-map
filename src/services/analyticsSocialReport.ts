import type { TasteMapAnalyticsDirectoryEntryDTO, TasteMapAnalyticsSourceEntryDTO, TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { DINING_OCCASION_OPTIONS, type RestaurantSummary, type Visit } from '../types/domain'
import { analyticsAverage, analyticsCities, analyticsConfidence, analyticsDataset, analyticsRatings, analyticsRestaurantRanking, analyticsSpend, analyticsSummary, latestAnalyticsRecords } from './analyticsReportData'
import type { AnalyticsRestaurantEvidence, AnalyticsRow, AnalyticsSection } from './analyticsReportTypes'
import { normalizedPrivateDirectoryName } from '../contracts/companionSourceContract'
import { NON_CUISINE_TAG } from './tasteProfileSnapshot'
import { restaurantCityComparisonKey } from './restaurantCity'
import { SOURCE_QUALITY_MINIMUM, sourcePitfall, sourcePositiveRank, compareSourcePitfalls } from './sourceQualityPolicy'
import { analyticsDiningContext, analyticsHasMealTime } from './analyticsDiningContext'
import { analyticsRepresentativeRatings } from './analyticsEvidenceRules'

export interface AnalyticsSocialReportOptions {
  companions?: readonly TasteMapAnalyticsDirectoryEntryDTO[] | null
  sources?: readonly TasteMapAnalyticsSourceEntryDTO[] | null
  visitSourceLinks?: readonly { visitID: string; sourceID: string | null }[] | null
  now?: Date
  timeZone?: string
  visitIDs?: readonly string[]
  selectedCompanionID?: string
  selectedSourceID?: string
  excludePrivate?: boolean
}
export type AnalyticsIdentityAvailability = 'available' | 'partial' | 'unavailable'
export const ANALYTICS_SOCIAL_THRESHOLDS = {
  companionEmergingVisits: 3, companionEstablishedVisits: 8,
  sourceAverageRatedRestaurants: 2, sourceRankingRatedRestaurants: SOURCE_QUALITY_MINIMUM,
  sourceComparableSources: 2, sourceStableRatedRestaurants: 10,
} as const

const normalize = (value: string) => normalizedPrivateDirectoryName(value).toLocaleLowerCase('zh-CN')
const mean = analyticsAverage
const ratio = (count: number, total: number) => total ? count / total : null
const percent = (value: number | null) => value == null ? '记录还在积累' : `${Math.round(value * 100)}%`
const score = (value: number | null) => value == null ? '暂无评分' : `${value.toFixed(1)} / 10`
const displayDate = (value: string | null, timeZone?: string) => value == null ? null : new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).format(new Date(value))
const compareID = (a: { id: string }, b: { id: string }) => a.id.localeCompare(b.id)
const latest = (visits: Visit[]) => visits.reduce<string | null>((result, visit) => !result || Date.parse(visit.visitedAt) > Date.parse(result) ? visit.visitedAt : result, null)
const cuisineLabels = (restaurant: RestaurantSummary) => [...new Set(restaurant.tags.map(value => value.trim()).filter(value => value && !NON_CUISINE_TAG.test(value)))]

/** Never infer identity from a label or linked social account. An ID collision is unresolved. */
function directory<T extends TasteMapAnalyticsDirectoryEntryDTO>(entries: readonly T[], ownerID: string) {
  const active = latestAnalyticsRecords(entries.filter(item => item.ownerUserID === ownerID && item.id.trim()))
    .filter(item => !item.deletedAt && item.displayName.trim()).sort(compareID)
  const identifiers = new Map<string, Set<string>>()
  const names = new Map<string, Set<string>>()
  const add = (map: Map<string, Set<string>>, key: string, id: string) => {
    if (!key) return
    const ids = map.get(key) ?? new Set<string>(); ids.add(id); map.set(key, ids)
  }
  for (const item of active) {
    for (const identifier of [item.id, ...item.identifiers]) add(identifiers, normalize(identifier), item.id)
    add(names, normalize(item.displayName), item.id)
  }
  const unique = (map: Map<string, Set<string>>, value: string) => {
    const ids = map.get(normalize(value)); return ids?.size === 1 ? [...ids][0] : null
  }
  return { entries: active, byID: (value: string) => unique(identifiers, value), byName: (value: string) => unique(names, value) }
}

function scopeVisits(visits: Visit[], ids?: readonly string[]) {
  if (!ids) return visits
  const allowed = new Set(ids); return visits.filter(visit => allowed.has(visit.id))
}
function groupVisits(visits: Visit[]) {
  const groups = new Map<string, Visit[]>()
  for (const visit of visits) { const values = groups.get(visit.restaurantId) ?? []; values.push(visit); groups.set(visit.restaurantId, values) }
  return groups
}
function frequency(visits: Visit[], labels: (visit: Visit) => string[]): AnalyticsRow[] {
  const groups = new Map<string, { label: string; count: number; ratings: number[] }>()
  for (const visit of visits) for (const label of new Map(labels(visit).filter(Boolean).map(value => [normalize(value), value])).values()) {
    const key = normalize(label); const group = groups.get(key) ?? { label, count: 0, ratings: [] }
    group.count++; group.ratings.push(...analyticsRatings([visit])); groups.set(key, group)
  }
  return [...groups].map(([id, item]) => ({ id, label: item.label, count: item.count, share: ratio(item.count, visits.length) ?? 0,
    value: `${item.count} 次`, scoreOutOfTen: mean(item.ratings) })).sort((a, b) => b.count - a.count || compareID(a, b))
}
function dimensionRatings(visits: Visit[]) {
  return (['valueRating', 'environmentRating', 'serviceRating'] as const).map((key, index) => {
    const values = visits.flatMap(visit => typeof visit[key] === 'number' && Number.isFinite(visit[key]) && visit[key]! >= 0.5 && visit[key]! <= 5 ? [visit[key]! * 2] : [])
    return { id: key, label: ['性价比', '环境', '服务'][index], scoreOutOfTen: mean(values), count: values.length, value: score(mean(values)), detail: `${values.length} 条我的评分` }
  })
}
function identityProof(profile: TasteMapProfileDashboardViewModel) {
  return profile.analyticsIdentity?.ownerUserID === profile.user.id ? profile.analyticsIdentity : null
}

export function buildAnalyticsCompanionReport(profile: TasteMapProfileDashboardViewModel, options: AnalyticsSocialReportOptions = {}) {
  const now = options.now ?? new Date()
  const data = analyticsDataset(profile, now)
  const visits = scopeVisits(data.visits, options.visitIDs)
  const entries = options.companions === undefined ? identityProof(profile)?.companions : options.companions
  const resolver = directory(entries ?? [], data.ownerID)
  const byCompanion = new Map<string, Visit[]>()
  const matchedVisits = new Set<string>()
  let unresolvedVisitCount = 0
  for (const visit of visits) {
    if (analyticsDiningContext(visit) === 'conflict') { unresolvedVisitCount += 1; continue }
    const ids = [...new Set(visit.companionIds.filter(value => value.trim()))]
    const names = [...new Set(visit.companions.filter(value => value.trim()))]
    const tokens = ids.length ? ids : names
    const resolved = new Set<string>(); let unresolved = false
    for (const token of tokens) {
      const id = ids.length ? resolver.byID(token) : resolver.byName(token)
      if (id) resolved.add(id); else unresolved = true
    }
    if (unresolved) unresolvedVisitCount++
    for (const id of resolved) { const values = byCompanion.get(id) ?? []; values.push(visit); byCompanion.set(id, values); matchedVisits.add(visit.id) }
  }
  const restaurantByID = new Map(data.restaurants.map(item => [item.id, item]))
  const baseline = analyticsRepresentativeRatings(visits).map(value => value.scoreOutOfTen)
  const formatter = new Intl.DateTimeFormat('en-US', { timeZone: options.timeZone, weekday: 'short', hour: 'numeric', hourCycle: 'h23' })
  const companions = resolver.entries.map(entry => {
    const shared = byCompanion.get(entry.id) ?? []
    const groups = groupVisits(shared)
    const restaurants = analyticsRestaurantRanking(data.restaurants, shared)
    const repeated = [...groups.values()].filter(items => items.length >= 2).length
    const repeatRate = ratio(repeated, groups.size)
    const ratings = analyticsRepresentativeRatings(shared).map(value => value.scoreOutOfTen)
    const ratingAverage = mean(ratings)
    const baselineAverage = mean(baseline)
    const summaryEligible = shared.length >= 3 && groups.size >= 2
    const comparisonEligible = shared.length >= 8 && groups.size >= 4
    const ratingDelta = comparisonEligible && ratings.length >= 5 && new Set(visits.filter(visit => visit.rating != null).map(visit => visit.restaurantId)).size >= 5 && ratingAverage != null && baselineAverage != null ? ratingAverage - baselineAverage : null
    const cuisines = frequency(shared, visit => cuisineLabels(restaurantByID.get(visit.restaurantId)!))
    const foodGroups = new Map<string, { label: string; visits: Set<string>; ratings: number[] }>()
    for (const visit of shared) for (const dish of visit.dishes) {
      if (!dish.id || !dish.name.trim()) continue
      // A Dish ID is only reusable within its original Restaurant, never by matching name.
      const key = `${visit.restaurantId}:${dish.id}`
      const group = foodGroups.get(key) ?? { label: dish.name, visits: new Set<string>(), ratings: [] }
      if (!group.visits.has(visit.id)) { group.visits.add(visit.id); group.ratings.push(...analyticsRatings([visit])) }
      foodGroups.set(key, group)
    }
    const dishes = [...foodGroups].map(([id, item]) => ({ id, label: item.label, count: item.visits.size, share: ratio(item.visits.size, shared.length) ?? 0,
      value: `${item.visits.size} 次`, scoreOutOfTen: mean(item.ratings) })).sort((a, b) => b.count - a.count || compareID(a, b))
    const foods = shared.length < 2 ? [] : dishes.some(item => item.count >= 2) ? dishes.slice(0, 6) : cuisines.slice(0, 6)
    const cities = analyticsCities(data.restaurants, shared)
    const timing = shared.map(visit => Object.fromEntries(formatter.formatToParts(new Date(visit.visitedAt)).map(part => [part.type, part.value])))
    const weekendShare = ratio(timing.filter(item => item.weekday === 'Sat' || item.weekday === 'Sun').length, shared.length)
    const timed = shared.filter(analyticsHasMealTime).map(visit => Object.fromEntries(formatter.formatToParts(new Date(visit.visitedAt)).map(part => [part.type, part.value])))
    const lateMealShare = ratio(timed.filter(item => Number(item.hour) >= 21 || Number(item.hour) < 5).length, timed.length)
    const keywords: string[] = []
    if (summaryEligible) {
      if ((repeatRate ?? 0) >= .5) keywords.push('常去熟店')
      else if (groups.size === shared.length || (repeatRate ?? 0) <= .2) keywords.push('探店型')
      if (foods[0]?.count && foods[0].count >= 2 && (foods[0].share ?? 0) >= .45) keywords.push(`${foods[0].label}搭子`)
      if ((weekendShare ?? 0) >= .6) keywords.push('周末饭友')
      if ((lateMealShare ?? 0) >= .5) keywords.push('深夜饭搭子')
      if (ratings.length >= 3 && (ratingAverage ?? 0) >= 8.6) keywords.push('高分组合')
    }
    const geographicScope = cities[0]?.label || profile.user.city.trim() || null
    const recommendations = companionRecommendations(data.restaurants, data.visits, groups, cuisines.slice(0, 3).map(item => item.label), geographicScope, repeatRate, now)
    const confidence = !summaryEligible ? 'insufficient' as const : comparisonEligible ? 'established' as const : 'emerging' as const
    const spend = analyticsSpend(shared)
    const diningModes = frequency(shared, visit => [visit.diningMode === 'takeout' ? '外卖' : '到店'])
    const occasions = frequency(shared, visit => visit.diningOccasions.map(value => DINING_OCCASION_OPTIONS.find(item => item.value === value)?.label ?? '').filter(Boolean))
    const latestVisitedAt = latest(shared)
    const sections: AnalyticsSection[] = [
      { id: 'companion-evidence', title: '一起吃过的日子', privacy: 'companion', confidence, metrics: [
        { id: 'shared', label: '一起吃次数', value: `${shared.length} 次` }, { id: 'restaurants', label: '不同餐厅', value: `${groups.size} 家` },
        { id: 'repeat', label: '回头餐厅比例', value: percent(repeatRate), note: `${repeated} 家一起去过不止一次` },
        { id: 'rating', label: '我的共同到访评分', value: score(ratingAverage), note: `${ratings.length} 家已评分餐厅` },
      ], description: !summaryEligible ? '共同经历还在积累。' : !comparisonEligible ? '已经有了一些共同用餐回忆。' : '共同用餐记录比较丰富。' },
      { id: 'companion-foods', title: '最常一起吃什么', privacy: 'companion', rows: foods, emptyMessage: '共同的菜品和菜系记录还在积累。' },
      { id: 'companion-pattern', title: '共同用餐模式', privacy: 'companion', rows: keywords.slice(0, 4).map((label, index) => ({ id: `keyword:${index}`, label })),
        metrics: [{ id: 'latest', label: '最近一起吃', value: displayDate(latestVisitedAt, options.timeZone) ?? '暂无共同到访' },
          { id: 'weekend', label: '周末共同到访', value: percent(weekendShare) }, { id: 'late', label: '夜间共同到访', value: percent(lateMealShare) }], emptyMessage: '你们的用餐习惯还在慢慢显现。' },
      { id: 'companion-cities', title: '共同用餐城市', privacy: 'companion', rows: cities.map(item => ({ ...item, value: `${item.count} 次 · ${item.restaurantCount} 家餐厅` })) },
      { id: 'companion-context', title: '用餐方式与场景', privacy: 'companion', rows: [...diningModes.map(item => ({ ...item, id: `mode:${item.id}` })), ...occasions.map(item => ({ ...item, id: `occasion:${item.id}` }))] },
      { id: 'companion-ratings', title: '我的详细评分', privacy: 'companion', rows: dimensionRatings(shared), description: ratingDelta == null ? '评分记录还在积累。' : `比个人全部有效记录${ratingDelta >= 0 ? '高' : '低'} ${Math.abs(ratingDelta).toFixed(1)} 分。` },
      { id: 'companion-spend', title: '我实际支付的消费', privacy: 'spend', metrics: spend.display === 'hidden' ? [] : [{ id: 'median', label: '个人实付中位数', value: spend.median == null ? '未记录' : `¥${spend.median.toFixed(0)}`, privacy: 'spend', note: `${spend.recordedVisitCount} 条实付记录` }], emptyMessage: '消费记录还不完整，暂时看不出日常花费。' },
      { id: 'companion-memories', title: '共同回忆餐厅', privacy: 'companion', rows: restaurants, emptyMessage: '还没有一起到访餐厅的记录。' },
      { id: 'companion-next', title: '下一顿可以一起吃', privacy: 'companion', rows: recommendations, emptyMessage: '当前同城收藏与共同记录不足，暂不作推荐。' },
    ]
    const firstTogetherRestaurantCount = [...groups].filter(([id, meals]) => !data.visits.some(visit => visit.restaurantId === id && Date.parse(visit.visitedAt) < Date.parse(meals[0].visitedAt))).length
    return { id: entry.id, displayName: entry.displayName, sharedVisitCount: shared.length, restaurantCount: groups.size, repeatedRestaurantCount: repeated,
      firstTogetherRestaurantCount, repeatVisitCount: shared.length - groups.size, visitIDs: shared.map(visit => visit.id),
      repeatRate, latestVisitedAt, firstVisitedAt: shared[0]?.visitedAt ?? null, confidence, ratingAverage, ratedVisitCount: analyticsRatings(shared).length,
      summaryEligible, comparisonEligible, ratingDelta, spend, foods, cuisines, diningModes, occasions, cities, weekendShare, lateMealShare, keywords: keywords.slice(0, 4),
      restaurants, recommendations, sections, historical: shared.length >= 3 && latestVisitedAt != null && Date.parse(latestVisitedAt) < now.getTime() - 90 * 86400000 }
  }).sort((a, b) => b.sharedVisitCount - a.sharedVisitCount || Date.parse(b.latestVisitedAt ?? '1970-01-01') - Date.parse(a.latestVisitedAt ?? '1970-01-01') || compareID(a, b))
  const selected = options.selectedCompanionID != null
    ? companions.find(item => item.id === options.selectedCompanionID) ?? null : companions[0] ?? null
  const resolvedVisits = visits.filter(visit => matchedVisits.has(visit.id))
  const selectedVisits = selected ? byCompanion.get(selected.id) ?? [] : []
  const identityAvailability: AnalyticsIdentityAvailability = entries == null ? 'unavailable' : unresolvedVisitCount ? 'partial' : 'available'
  const identityMessage = identityAvailability === 'unavailable' ? '饭搭子资料暂未读到，请稍后重试。'
    : unresolvedVisitCount ? `${unresolvedVisitCount} 条同行记录还需确认饭搭子。` : '一起吃过的每一顿，都留在这些记录里。'
  return {
    visitIDs: selectedVisits.map(visit => visit.id), summary: analyticsSummary(data.restaurants, selectedVisits), headline: selectedVisits.length ? `与选中饭搭子记录了 ${selectedVisits.length} 次共同用餐` : '共同用餐记录还在积累',
    insights: [identityMessage, '这里的评分来自你对共同用餐的记录。'],
    identityAvailability, unresolvedVisitCount, companions, selectedCompanionID: selected?.id ?? null, allCompanionsSharedVisitCount: resolvedVisits.length,
    topRestaurants: analyticsRestaurantRanking(data.restaurants, selectedVisits).slice(0, 3).map(item => ({ ...item, privacy: 'companion' as const })),
    sections: [{ id: 'companion-directory', title: '全部饭搭子比较', privacy: 'companion', description: identityMessage,
      rows: companions.map(item => ({ id: item.id, label: item.displayName, value: `${item.sharedVisitCount} 次`, count: item.sharedVisitCount, detail: `${item.restaurantCount} 家餐厅 · ${item.ratedVisitCount} 次我的评分` })),
      emptyMessage: '还没有可查看的饭搭子记录。' } as AnalyticsSection, ...(selected?.sections ?? [])],
  }
}

function companionRecommendations(restaurants: RestaurantSummary[], visits: Visit[], shared: Map<string, Visit[]>, cuisines: string[], city: string | null, repeatRate: number | null, now: Date): AnalyticsRow[] {
  if (!city || !shared.size) return []
  const all = groupVisits(visits); const tastes = new Set(cuisines.map(normalize)); const familiar = (repeatRate ?? 0) >= .4
  return restaurants.flatMap(restaurant => {
    if (restaurant.preferenceLevel === 'avoid' || restaurantCityComparisonKey(restaurant.city) !== restaurantCityComparisonKey(city)) return []
    const sharedVisits = shared.get(restaurant.id) ?? []; const average = mean(analyticsRatings(all.get(restaurant.id) ?? []))
    if (average != null && average < 6 || sharedVisits.length && !familiar) return []
    const lastShared = latest(sharedVisits)
    if (sharedVisits.length >= 2 && lastShared && Date.parse(lastShared) >= now.getTime() - 14 * 86400000 && !((repeatRate ?? 0) >= .6 && (average ?? 0) >= 9)) return []
    const matches = cuisineLabels(restaurant).filter(value => tastes.has(normalize(value))).length
    const wanted = restaurant.status === 'wantToGo'
    const rank = (wanted ? 5 : 0) + (!sharedVisits.length ? 2.2 : 1.4) + Math.min(2, matches) * 1.8 + (average == null ? 0 : Math.max(0, average / 2 - 3) * 1.2)
      + (restaurant.preferenceLevel === 'favorite' ? 1.2 : restaurant.preferenceLevel === 'like' ? .6 : 0)
    return [{ id: restaurant.id, restaurantID: restaurant.id, label: restaurant.name, scoreOutOfTen: average,
      detail: wanted ? matches ? '同城想吃清单，符合共同记录的口味' : '同城想吃清单里的下一站' : !sharedVisits.length ? '你去过、还没与 TA 一起去的同城餐厅' : '可以一起再去的熟店', rank, wanted }]
  }).sort((a, b) => b.rank - a.rank || Number(b.wanted) - Number(a.wanted) || a.label.localeCompare(b.label, 'zh-CN') || compareID(a, b)).slice(0, 3)
    .map(({ rank: _rank, wanted: _wanted, ...row }) => row)
}

interface SourceRestaurant extends AnalyticsRestaurantEvidence { visitIDs: string[]; acquisitionVisitID: string; acquisitionAt: string; isNewDiscovery: boolean; repeatAverage: number | null; valueAverage: number | null; environmentAverage: number | null; serviceAverage: number | null }

export function buildAnalyticsSourceReport(profile: TasteMapProfileDashboardViewModel, options: AnalyticsSocialReportOptions = {}) {
  const reportNow = options.now ?? new Date()
  const data = analyticsDataset(profile, reportNow)
  const scoped = scopeVisits(data.visits, options.visitIDs); const scopeIDs = new Set(scoped.map(visit => visit.id))
  const proof = identityProof(profile)
  const entries = options.sources === undefined ? proof?.sources : options.sources
  const links = options.visitSourceLinks === undefined ? proof?.visitSourceLinks : options.visitSourceLinks
  const resolver = directory(entries ?? [], data.ownerID)
  const linkGroups = new Map<string, Set<string | null>>()
  for (const link of links ?? []) { const values = linkGroups.get(link.visitID) ?? new Set(); values.add(link.sourceID?.trim() || null); linkGroups.set(link.visitID, values) }
  const bySource = new Map<string, SourceRestaurant[]>()
  const restaurantByID = new Map(data.restaurants.map(item => [item.id, item]))
  const history = groupVisits(data.visits)
  // The personal baseline includes first Visits without an external source too.
  // A missing first score is not replaced by a later repeat score.
  const baselineVisits = [...history.values()].map(visits => visits[0]).filter(visit => visit.rating != null && (!options.excludePrivate || visit.visibility === 'public'))
  const baselineRatings = analyticsRatings(baselineVisits)
  const baseline = mean(baselineRatings)
  const baselineHighRate = ratio(baselineRatings.filter(value => value >= 8).length, baselineRatings.length) ?? 0
  const ambiguousRestaurantIDs: string[] = []
  let unresolvedVisitCount = 0
  const resolveSource = (visit: Visit) => {
    const values = linkGroups.get(visit.id)
    if (!values || values.size !== 1) return null // Missing field is not proof of a legacy name-only association.
    const sourceID = [...values][0]
    return sourceID == null ? resolver.byName(visit.recommendationSourceText) : resolver.byID(sourceID)
  }
  for (const visit of scoped) if ((visit.recommendationSourceText.trim() || visit.recommendationSourceType || [...(linkGroups.get(visit.id) ?? [])].some(value => value != null)) && !resolveSource(visit)) unresolvedVisitCount++
  for (const [restaurantID, allVisits] of history) {
    const sourceIDs = new Set(allVisits.flatMap(visit => [...(linkGroups.get(visit.id) ?? [])].filter((id): id is string => id != null).map(id => resolver.byID(id) ?? `unresolved:${id}`)))
    for (const visit of allVisits) { const id = resolveSource(visit); if (id) sourceIDs.add(id) }
    if (sourceIDs.size > 1 || allVisits.some(visit => (linkGroups.get(visit.id)?.size ?? 0) > 1)) {
      if (allVisits.some(visit => scopeIDs.has(visit.id))) ambiguousRestaurantIDs.push(restaurantID)
      continue
    }
    const acquisition = allVisits.find(visit => resolveSource(visit) != null)
    if (!acquisition || !scopeIDs.has(acquisition.id)) continue
    const sourceID = resolveSource(acquisition)!
    const visits = allVisits.filter(visit => scopeIDs.has(visit.id) && Date.parse(visit.visitedAt) >= Date.parse(acquisition.visitedAt))
    const evidence = analyticsRestaurantRanking([restaurantByID.get(restaurantID)!], visits)[0]
    const dimensions = dimensionRatings(visits)
    const firstScore = analyticsRatings([acquisition])[0] ?? null
    const item: SourceRestaurant = { ...evidence, visitIDs: visits.map(visit => visit.id), scoreOutOfTen: firstScore,
      detail: firstScore == null ? '首次体验未评分' : `首次体验 ${firstScore.toFixed(1)} / 10`,
      repeatAverage: mean(analyticsRatings(visits.filter(visit => visit.id !== acquisition.id))), acquisitionVisitID: acquisition.id, acquisitionAt: acquisition.visitedAt,
      isNewDiscovery: acquisition.id === allVisits[0].id, valueAverage: dimensions[0].scoreOutOfTen, environmentAverage: dimensions[1].scoreOutOfTen, serviceAverage: dimensions[2].scoreOutOfTen }
    const values = bySource.get(sourceID) ?? []; values.push(item); bySource.set(sourceID, values)
  }
  const now = reportNow.getTime()
  const sources = resolver.entries.map(entry => {
    const restaurants = (bySource.get(entry.id) ?? []).sort((a, b) => (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1) || b.count - a.count || Date.parse(b.acquisitionAt) - Date.parse(a.acquisitionAt) || compareID(a, b))
    const ratings = restaurants.flatMap(item => item.scoreOutOfTen == null ? [] : [item.scoreOutOfTen])
    const average = mean(ratings)
    const deviation = ratings.length >= 2 && average != null ? Math.sqrt(ratings.reduce((sum, value) => sum + (value - average) ** 2, 0) / ratings.length) : null
    const highCount = ratings.filter(value => value >= 8).length; const lowCount = ratings.filter(value => sourcePitfall(value, baseline)).length
    const highRate = ratio(highCount, ratings.length); const lowRate = ratio(lowCount, ratings.length)
    const repeatCount = restaurants.filter(item => item.count >= 2).length
    const observed = restaurants.filter(item => Date.parse(item.acquisitionAt) + 90 * 86400000 <= now)
    const repeatedWithin90Days = observed.filter(item => (history.get(item.restaurantID) ?? []).some(visit => {
      const elapsed = Date.parse(visit.visitedAt) - Date.parse(item.acquisitionAt)
      return visit.id !== item.acquisitionVisitID && elapsed > 0 && elapsed <= 90 * 86400000
    }))
    const repeatRate = ratio(repeatedWithin90Days.length, observed.length)
    const recentCount = restaurants.filter(item => Date.parse(item.acquisitionAt) >= now - 90 * 86400000 && Date.parse(item.acquisitionAt) <= now).length
    const previousCount = restaurants.filter(item => Date.parse(item.acquisitionAt) >= now - 180 * 86400000 && Date.parse(item.acquisitionAt) < now - 90 * 86400000).length
    const trend = recentCount > 0 && !previousCount ? 'new' : recentCount > previousCount ? 'rising' : recentCount === previousCount && recentCount > 0 ? 'steady' : recentCount > 0 ? 'cooling' : 'inactive'
    const stable = ratings.length < 3 ? 'insufficient' : (deviation ?? 0) <= 1 ? 'stable' : (deviation ?? 0) >= 2 ? 'volatile' : 'forming'
    const eligible = entry.sourceType !== 'self' && ratings.length >= SOURCE_QUALITY_MINIMUM
    const reliabilityScore = eligible ? sourcePositiveRank(highCount, ratings.length, baselineHighRate) : null
    const pitfallScore = eligible && baseline != null ? lowRate : null
    const pitfallRestaurants = restaurants.filter(item => sourcePitfall(item.scoreOutOfTen, baseline))
      .sort((a, b) => a.scoreOutOfTen! - b.scoreOutOfTen! || compareID(a, b))
    const latestUsageAt = restaurants.reduce<string | null>((result, item) => !result || Date.parse(item.acquisitionAt) > Date.parse(result) ? item.acquisitionAt : result, null)
    const sourceVisitIDs = new Set(restaurants.flatMap(item => item.visitIDs))
    const spend = analyticsSpend(scoped.filter(visit => sourceVisitIDs.has(visit.id)))
    const cuisineGroups = new Map<string, { label: string; restaurantIDs: Set<string>; ratings: number[] }>()
    for (const item of restaurants) for (const label of cuisineLabels(restaurantByID.get(item.restaurantID)!)) {
      const key = normalize(label); const group = cuisineGroups.get(key) ?? { label, restaurantIDs: new Set<string>(), ratings: [] }
      if (!group.restaurantIDs.has(item.restaurantID)) { group.restaurantIDs.add(item.restaurantID); if (item.scoreOutOfTen != null) group.ratings.push(item.scoreOutOfTen) }
      cuisineGroups.set(key, group)
    }
    const cuisines = [...cuisineGroups].map(([id, item]) => ({ id, label: item.label, count: item.restaurantIDs.size, value: `${item.restaurantIDs.size} 家`, scoreOutOfTen: mean(item.ratings) }))
      .sort((a, b) => b.count - a.count || compareID(a, b))
    const latestRatedRestaurants = [...restaurants].filter(item => item.scoreOutOfTen != null).sort((a, b) => Date.parse(b.acquisitionAt) - Date.parse(a.acquisitionAt) || compareID(a, b)).slice(0, 3)
    return { id: entry.id, displayName: entry.displayName, sourceType: entry.sourceType, restaurantCount: restaurants.length, ratedRestaurantCount: ratings.length,
      averageScoreOutOfTen: average, highRatingCount: highCount, lowRatingCount: lowCount, highRatingRate: highRate, lowRatingRate: lowRate,
      repeatRestaurantCount: repeatCount, repeatRestaurantRate: repeatRate,
      repeatObservation: { days: 90, observedRestaurantCount: observed.length, pendingRestaurantCount: restaurants.length - observed.length,
        repeatedRestaurantCount: repeatedWithin90Days.length, rate: repeatRate,
        restaurantIDs: observed.map(item => item.restaurantID), repeatedRestaurantIDs: repeatedWithin90Days.map(item => item.restaurantID) },
      newDiscoveryCount: restaurants.filter(item => item.isNewDiscovery).length,
      ratingStandardDeviation: deviation, ratingStability: stable, recentRestaurantCount: recentCount, previousRestaurantCount: previousCount, trend,
      confidence: analyticsConfidence(ratings.length, 2, 10), eligible, reliabilityScore, pitfallScore, latestUsageAt, restaurants, pitfallRestaurants,
      cuisines, spend, recentAverageScoreOutOfTen: mean(latestRatedRestaurants.map(item => item.scoreOutOfTen!)), recentRatedRestaurantCount: latestRatedRestaurants.length,
      ratingDeltaFromBaseline: average != null && baseline != null ? average - baseline : null,
      valueAverage: mean(restaurants.flatMap(item => item.valueAverage == null ? [] : [item.valueAverage])),
      environmentAverage: mean(restaurants.flatMap(item => item.environmentAverage == null ? [] : [item.environmentAverage])),
      serviceAverage: mean(restaurants.flatMap(item => item.serviceAverage == null ? [] : [item.serviceAverage])),
    }
  }).sort((a, b) => b.restaurantCount - a.restaurantCount || b.ratedRestaurantCount - a.ratedRestaurantCount || Date.parse(b.latestUsageAt ?? '1970-01-01') - Date.parse(a.latestUsageAt ?? '1970-01-01') || compareID(a, b))
  const mostUsed = sources.find(item => item.restaurantCount > 0) ?? null
  const highestAverage = sources.filter(item => item.eligible).sort((a, b) => (b.averageScoreOutOfTen ?? -1) - (a.averageScoreOutOfTen ?? -1) || b.ratedRestaurantCount - a.ratedRestaurantCount || compareID(a, b))[0] ?? null
  const eligible = sources.filter(item => item.eligible)
  const positiveRanking = [...eligible].filter(item => item.highRatingCount > 0).sort((a, b) => b.reliabilityScore! - a.reliabilityScore! || b.ratedRestaurantCount - a.ratedRestaurantCount || Date.parse(b.latestUsageAt ?? '') - Date.parse(a.latestUsageAt ?? '') || compareID(a, b))
  const best = positiveRanking[0] ?? null
  const pitfallRanking = eligible.filter(item => item.pitfallScore != null && item.lowRatingCount > 0).sort((a, b) => compareSourcePitfalls(
    { id: a.id, pitfallRate: a.pitfallScore!, firstAverage: a.averageScoreOutOfTen! },
    { id: b.id, pitfallRate: b.pitfallScore!, firstAverage: b.averageScoreOutOfTen! }))
  const worst = pitfallRanking[0] ?? null
  const selected = options.selectedSourceID != null
    ? sources.find(item => item.id === options.selectedSourceID) ?? null : mostUsed ?? sources[0] ?? null
  const identityAvailability: AnalyticsIdentityAvailability = entries == null || links == null ? 'unavailable' : unresolvedVisitCount ? 'partial' : 'available'
  const identityMessage = identityAvailability === 'unavailable' ? '推荐来源资料暂未读到，请稍后重试。'
    : unresolvedVisitCount || ambiguousRestaurantIDs.length ? `${unresolvedVisitCount} 条推荐记录、${ambiguousRestaurantIDs.length} 家餐厅的主要来源还需确认。` : '看看哪些推荐带来了你喜欢的餐厅。'
  const conclusions = [
    ...(mostUsed ? [{ id: 'most-used', title: '最常使用来源', sourceID: mostUsed.id, label: mostUsed.displayName, explanation: `跟着推荐吃过 ${mostUsed.restaurantCount} 家餐厅。` }] : []),
    ...(highestAverage ? [{ id: 'highest-average', title: '平均分更高', sourceID: highestAverage.id, label: highestAverage.displayName, explanation: `${highestAverage.ratedRestaurantCount} 家有评分餐厅，平均 ${score(highestAverage.averageScoreOutOfTen)}。` }] : []),
    ...(best ? [{ id: 'best', title: '最会种草', sourceID: best.id, label: best.displayName, explanation: `${best.ratedRestaurantCount} 家首次体验已评分，${best.highRatingCount} 家达到 8 分，高分占比 ${percent(best.highRatingRate)}。` }] : []),
    ...(worst ? [{ id: 'worst', title: '最坑推荐来源', sourceID: worst.id, label: worst.displayName, explanation: `${worst.ratedRestaurantCount} 家已评分餐厅中，${worst.lowRatingCount} 家体验不如平时，踩坑占比 ${percent(worst.lowRatingRate)}。首次体验平均 ${score(worst.averageScoreOutOfTen)}。` }] : []),
  ]
  const topRestaurants: AnalyticsRestaurantEvidence[] = []
  const append = (item: SourceRestaurant | undefined, role: string) => { if (item && !topRestaurants.some(existing => existing.id === item.id)) topRestaurants.push({ ...item, detail: role }) }
  append(mostUsed ? [...mostUsed.restaurants].sort((a, b) => Date.parse(b.acquisitionAt) - Date.parse(a.acquisitionAt) || compareID(a, b))[0] : undefined, '近期来源故事')
  append(best?.restaurants.find(item => item.scoreOutOfTen != null && item.scoreOutOfTen >= 8), '靠谱来源代表')
  append(worst?.pitfallRestaurants[0], '踩坑餐厅')
  const attributedIDs = new Set(selected?.restaurants.map(item => item.restaurantID) ?? [])
  const attributedVisitIDs = new Set(selected?.restaurants.flatMap(item => item.visitIDs) ?? [])
  const selectedVisits = scoped.filter(visit => attributedVisitIDs.has(visit.id))
  const sections: AnalyticsSection[] = [
    { id: 'source-conclusions', title: '全部来源体验对比', description: identityMessage, rows: conclusions.map(item => ({ id: item.id, label: item.title, value: item.label, detail: item.explanation })), emptyMessage: '推荐记录还在积累，暂时没有比较结果。' },
    { id: 'source-comparison', title: '各个来源带来的餐厅', description: `${eligible.length} 个外部来源达到 5 家首次体验已评分餐厅门槛；不足门槛的来源仍保留事实，不参与排名。`,
      rows: sources.map(item => ({ id: item.id, label: item.displayName, count: item.restaurantCount, value: `${item.restaurantCount} 家`, scoreOutOfTen: item.averageScoreOutOfTen, detail: `${item.ratedRestaurantCount} 家有评分 · 高分 ${percent(item.highRatingRate)} · 低分 ${percent(item.lowRatingRate)}` })) },
    { id: 'source-comparison-evidence', title: '全部来源的代表餐厅', rows: topRestaurants },
    { id: 'source-pitfall-method', title: '首次体验记录', description: `你给 ${baselineRatings.length} 家餐厅的首次体验打过分，平均 ${score(baseline)}。`, rows: baselineVisits.map(visit => ({ id: visit.id, restaurantID: visit.restaurantId, label: restaurantByID.get(visit.restaurantId)!.name, scoreOutOfTen: visit.rating! * 2, detail: `${displayDate(visit.visitedAt, options.timeZone)} · 首次到访` })) },
    ...(selected ? [{ id: 'source-evidence', title: '跟着这个推荐吃过的餐厅', rows: selected.restaurants, emptyMessage: '还没有通过这个来源到访餐厅的记录。', description: '每家餐厅取该来源首次归因到访的评分作为一份样本；后续回访不替代首次评分，也不补全首次未评分。' },
      { id: 'source-outcomes', title: '这个来源带来的体验', metrics: [
        { id: 'repeat', label: '90 天内回访比例', value: percent(selected.repeatRestaurantRate), note: `${selected.repeatObservation.observedRestaurantCount} 家已满观察期 · ${selected.repeatObservation.pendingRestaurantCount} 家仍在观察` },
        { id: 'high', label: '8 分及以上占比', value: percent(selected.highRatingRate), note: `${selected.highRatingCount} 家获得高分` },
        { id: 'low', label: '体验不如平时的占比', value: percent(selected.lowRatingRate), note: `${selected.lowRatingCount} 家体验不如平时` },
        { id: 'latest', label: '最近发现餐厅', value: displayDate(selected.latestUsageAt, options.timeZone) ?? '暂无记录' },
      ] },
      { id: 'source-cuisines', title: '来源带来的菜系', rows: selected.cuisines, emptyMessage: '还没有记录这些餐厅的菜系。' },
      { id: 'source-spend', title: '这些餐厅的个人实付', privacy: 'spend' as const,
        metrics: selected.spend.display === 'hidden' ? [] : [{ id: 'median', label: '我的实付中位数', value: selected.spend.median == null ? '未记录' : `¥${selected.spend.median.toFixed(0)}`, privacy: 'spend' as const, note: `${selected.spend.recordedVisitCount} 条实付记录` }],
        emptyMessage: '消费记录还不完整，暂时看不出日常花费。' },
      { id: 'source-detail', title: '稳定性与变化', metrics: [{ id: 'stability', label: '评分稳定性', value: ({ insufficient: '记录还在积累', stable: '稳定', volatile: '波动较大', forming: '逐渐形成' })[selected.ratingStability] ?? '记录还在积累' },
        { id: 'recent', label: '近 90 天跟着推荐去过', value: `${selected.recentRestaurantCount} 家` }, { id: 'previous', label: '此前 90 天', value: `${selected.previousRestaurantCount} 家` }],
        rows: [{ id: 'value', label: '性价比', value: score(selected.valueAverage) }, { id: 'environment', label: '环境', value: score(selected.environmentAverage) }, { id: 'service', label: '服务', value: score(selected.serviceAverage) }] }] : []),
  ]
  return { visitIDs: selectedVisits.map(visit => visit.id), summary: analyticsSummary(data.restaurants, selectedVisits), headline: attributedIDs.size ? `${attributedIDs.size} 家餐厅有明确的发现来源` : '推荐来源记录还在积累',
    insights: [identityMessage, ...(selected?.restaurantCount ? [`通过这个来源，你去过 ${selected.restaurantCount} 家餐厅，其中 ${selected.repeatRestaurantCount} 家又去了。`] : ['还没有足够记录看出推荐带来的体验。'])],
    identityAvailability, unresolvedVisitCount, sources, selectedSourceID: selected?.id ?? null, eligibleSourceCount: eligible.length,
    mostUsedSourceID: mostUsed?.id ?? null, highestAverageSourceID: highestAverage?.id ?? null, bestSourceID: best?.id ?? null, worstSourceID: worst?.id ?? null,
    overallSourceRating: baseline, baselineRestaurantCount: baselineRatings.length, ambiguousRestaurantIDs, pitfallRanking, positiveRanking,
    conclusions, sections, comparisonTopRestaurants: topRestaurants, topRestaurants: selected?.restaurants.slice(0, 3) ?? [] }
}
