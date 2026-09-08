import type { AnalysisTasteProfileSnapshot } from '../types/analysisShare'
import { DINING_OCCASION_OPTIONS, RECOMMENDATION_SOURCE_OPTIONS, type RestaurantSummary, type Visit } from '../types/domain'
import { buildTasteProfile } from './profileInsights'
import { buildTasteProfileSnapshot, NON_CUISINE_TAG } from './tasteProfileSnapshot'
import { resolveVisitActualSpend, visitReferencePrice } from './visitSpend'
import { analyticsAverage, analyticsCities, analyticsConfidence, analyticsPercentile, analyticsRatings, analyticsRestaurantRanking, analyticsSummary } from './analyticsReportData'
import type { AnalyticsSection } from './analyticsReportTypes'
import { analyticsDiningContext, analyticsHasMealTime } from './analyticsDiningContext'
import { ANALYTICS_EVIDENCE_RULES as evidenceRules, analyticsFrequencyEvidence, analyticsRepresentativeRatings } from './analyticsEvidenceRules'

const priceRanges = [0, 50, 100, 200, 300, 500, 800].map((minimum, index, values) => ({
  id: `price-${minimum}`, label: values[index + 1] ? `¥${minimum}–${values[index + 1]}` : '¥800+', minimum, maximum: values[index + 1] ?? Infinity,
}))
const share = (count: number, total: number) => total ? count / total : 0
const percent = (value: number) => `${Math.round(value * 100)}%`
const money = (value: number | null) => value == null ? '未记录' : `¥${Number(value.toFixed(2))}`
const cuisineTags = (restaurant: RestaurantSummary | undefined) => [...new Set((restaurant?.tags ?? []).map((item) => item.trim()).filter((item) => item && !NON_CUISINE_TAG.test(item)))]

/** P4-A weighting: unrated meals count as frequency, never as a made-up 5/10. */
export function analyticsCuisineRanking(restaurants: RestaurantSummary[], visits: Visit[], now: Date) {
  const byID = new Map(restaurants.map((item) => [item.id, item]))
  const groups = new Map<string, Visit[]>()
  for (const visit of visits) for (const tag of cuisineTags(byID.get(visit.restaurantId))) groups.set(tag, [...(groups.get(tag) ?? []), visit])
  return [...groups].map(([label, values]) => {
    const ratings = analyticsRatings(values)
    const restaurantCount = new Set(values.map((visit) => visit.restaurantId)).size
    const repeatVisitCount = values.length - restaurantCount
    const representativeRatings = analyticsRepresentativeRatings(values).map(item => item.scoreOutOfTen)
    const averageScoreOutOfTen = analyticsAverage(representativeRatings)
    const highRatingShare = share(representativeRatings.filter((value) => value >= 8).length, representativeRatings.length)
    const latestVisitAt = Math.max(...values.map((visit) => Date.parse(visit.visitedAt)))
    const ageDays = (now.getTime() - latestVisitAt) / 86400000
    const score = ((averageScoreOutOfTen ?? 0) * 0.48 + highRatingShare * 3) * Math.min(1, representativeRatings.length / 3)
      + Math.log2(values.length + 1) * 1.15 + Math.log2(repeatVisitCount + 1) * 0.75 + Math.min(3, restaurantCount) * 0.2
      + (ageDays <= 90 ? 0.45 : ageDays <= 180 ? 0.2 : 0)
    const spanDays = (latestVisitAt - Math.min(...values.map(visit => Date.parse(visit.visitedAt)))) / 86400000
    const confidence = representativeRatings.length >= 10 && spanDays >= 30 ? 'established' as const : representativeRatings.length >= 5 ? 'emerging' as const : 'insufficient' as const
    return { label, score, visitCount: values.length, restaurantCount, repeatVisitCount, ratedVisitCount: ratings.length, ratedRestaurantCount: representativeRatings.length, averageScoreOutOfTen, highRatingShare, spanDays, confidence, share: share(values.length, visits.length) }
  }).sort((a, b) => b.score - a.score || b.visitCount - a.visitCount || b.restaurantCount - a.restaurantCount || a.label.localeCompare(b.label, 'zh-CN'))
}

export function analyticsCuisineShares(restaurants: RestaurantSummary[], visits: Visit[]) {
  return analyticsCuisineRanking(restaurants, visits, new Date(0)).map(({ label, share: value, visitCount }) => ({ label, share: value, count: visitCount }))
}

export function spendCategory(restaurant: RestaurantSummary | undefined) {
  const tags = (restaurant?.tags ?? []).join(' ')
  if (/饮品|奶茶|酒吧|果汁/.test(tags)) return '饮品'
  if (/咖啡|甜|蛋糕|烘焙|面包|茶/.test(tags)) return '咖啡与甜点'
  if (/小吃|快餐|汉堡|炸|串|面点/.test(tags)) return '小吃与快餐'
  if (/早餐|早午餐/.test(tags)) return '早餐'
  return '正餐'
}

export function buildAnalyticsTasteReport(restaurants: RestaurantSummary[], visits: Visit[], now: Date) {
  const summary = analyticsSummary(restaurants, visits)
  const historical = buildTasteProfile(restaurants, visits, now)
  const cuisines = analyticsCuisineRanking(restaurants, visits, now)
  const topRestaurants = analyticsRestaurantRanking(restaurants, visits)
  const byID = new Map(restaurants.map((item) => [item.id, item]))
  const references = visits.flatMap((visit) => { const value = visitReferencePrice(visit); return value == null ? [] : [{ visit, value }] })
  const referenceDistribution = priceRanges.map((range) => {
    const samples = references.filter((item) => item.value >= range.minimum && item.value < range.maximum)
    const ratings = analyticsRepresentativeRatings(samples.map((item) => item.visit)).map(item => item.scoreOutOfTen)
    return { ...range, count: samples.length, share: share(samples.length, references.length), ratedCount: ratings.length, highRatingShare: share(ratings.filter((value) => value >= 8).length, ratings.length) }
  })
  const leadingPrice = [...referenceDistribution].sort((a, b) => b.count - a.count)[0]
  const comparablePrices = referenceDistribution.filter((item) => item.ratedCount >= 5)
  const sweetPrice = comparablePrices.length >= 2 ? comparablePrices.sort((a, b) => b.highRatingShare - a.highRatingShare || b.ratedCount - a.ratedCount)[0] : undefined
  const spending = new Map<string, { amount: number; count: number }>()
  for (const visit of visits) {
    const amount = resolveVisitActualSpend(visit)
    if (amount == null) continue
    const category = spendCategory(byID.get(visit.restaurantId))
    const previous = spending.get(category) ?? { amount: 0, count: 0 }
    spending.set(category, { amount: previous.amount + amount, count: previous.count + 1 })
  }
  const spendCategories = [...spending].map(([label, item]) => ({ label, ...item, share: share(item.amount, summary.spend.total) })).sort((a, b) => b.amount - a.amount || a.label.localeCompare(b.label))
  const actualPayments = visits.flatMap((visit) => { const value = resolveVisitActualSpend(visit); return value == null ? [] : [value] })
  const personalSpendDistribution = priceRanges.map((range) => ({ ...range,
    count: actualPayments.filter((value) => value >= range.minimum && value < range.maximum).length,
    share: share(actualPayments.filter((value) => value >= range.minimum && value < range.maximum).length, actualPayments.length),
  }))
  const repeated = topRestaurants.filter((item) => item.count >= 2)
  const repeat = { repeatedRestaurantCount: repeated.length, visitedRestaurantCount: topRestaurants.length, rate: share(repeated.length, topRestaurants.length), confidence: analyticsConfidence(topRestaurants.length, 2, 10) }
  const ratings = analyticsRatings(visits)
  const average = analyticsAverage(ratings)
  const deviation = average == null ? null : Math.sqrt(analyticsAverage(ratings.map((value) => (value - average) ** 2))!)
  const ratingConfidence = analyticsConfidence(ratings.length)
  const ratingBehavior = { sampleCount: ratings.length, average, median: analyticsPercentile(ratings, 0.5), standardDeviation: deviation,
    highShare: share(ratings.filter((value) => value >= 8).length, ratings.length), aboveNineShare: share(ratings.filter((value) => value >= 9).length, ratings.length), lowShare: share(ratings.filter((value) => value < 6).length, ratings.length),
    label: ratingConfidence === 'insufficient' ? ratings.length ? '评分仍在形成' : '未评分' : average! >= 8.6 && deviation! < 1.1 ? '高分稳定型' : average! < 7.2 ? '打分比较克制' : deviation! >= 1.8 ? '好坏分得很清楚' : '温和稳定型' }
  const togetherVisits = visits.filter(visit => analyticsDiningContext(visit) === 'together')
  const soloVisits = visits.filter(visit => analyticsDiningContext(visit) === 'solo')
  const conflictCount = visits.filter(visit => analyticsDiningContext(visit) === 'conflict').length
  const withRatings = analyticsRepresentativeRatings(togetherVisits).map(item => item.scoreOutOfTen)
  const soloRatings = analyticsRepresentativeRatings(soloVisits).map(item => item.scoreOutOfTen)
  const companionImpact = { withCount: withRatings.length, soloCount: soloRatings.length, withAverage: analyticsAverage(withRatings), soloAverage: analyticsAverage(soloRatings),
    difference: withRatings.length >= 5 && soloRatings.length >= 5 ? analyticsAverage(withRatings)! - analyticsAverage(soloRatings)! : null }
  const recentStart = new Date(now); recentStart.setDate(recentStart.getDate() - 90)
  const previousStart = new Date(recentStart); previousStart.setDate(previousStart.getDate() - 90)
  const recent = visits.filter((visit) => Date.parse(visit.visitedAt) >= recentStart.getTime() && Date.parse(visit.visitedAt) <= now.getTime())
  const previous = visits.filter((visit) => Date.parse(visit.visitedAt) >= previousStart.getTime() && Date.parse(visit.visitedAt) < recentStart.getTime())
  const recentCuisines = analyticsCuisineRanking(restaurants, recent, now)
  const previousCuisines = analyticsCuisineRanking(restaurants, previous, now)
  const frequencyAvailable = analyticsFrequencyEvidence(recent) && analyticsFrequencyEvidence(previous)
  const recentRatings = analyticsRepresentativeRatings(recent)
  const previousRatings = analyticsRepresentativeRatings(previous)
  const ratingAvailable = recentRatings.length >= evidenceRules.comparisonRatedRestaurants && previousRatings.length >= evidenceRules.comparisonRatedRestaurants
  const scoreDelta = ratingAvailable ? analyticsAverage(recentRatings.map(item => item.scoreOutOfTen))! - analyticsAverage(previousRatings.map(item => item.scoreOutOfTen))! : null
  const frequencyChanges = frequencyAvailable ? [...new Set([...recentCuisines, ...previousCuisines].map(item => item.label))].flatMap(label => {
    const currentShare = recentCuisines.find(item => item.label === label)?.share ?? 0
    const previousShare = previousCuisines.find(item => item.label === label)?.share ?? 0
    const delta = currentShare - previousShare
    return Math.abs(delta) + Number.EPSILON < evidenceRules.frequencyChange ? [] : [{ label, currentShare, previousShare, delta }]
  }).sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta) || a.label.localeCompare(b.label)) : []
  const recentComparison = { currentVisitCount: recent.length, previousVisitCount: previous.length,
    currentRatedRestaurantCount: recentRatings.length, previousRatedRestaurantCount: previousRatings.length,
    currentStart: recentStart.toISOString(), previousStart: previousStart.toISOString(), available: frequencyAvailable || ratingAvailable,
    frequencyAvailable, ratingAvailable, scoreDelta, frequencyChanges,
    changes: [...frequencyChanges.map(item => `${item.label}到访占比${item.delta > 0 ? '提高' : '下降'} ${Math.round(Math.abs(item.delta) * 100)} 个百分点`),
      ...(scoreDelta != null && Math.abs(scoreDelta) >= evidenceRules.ratingChangeOutOfTen ? [`餐厅平均评分${scoreDelta > 0 ? '提高' : '下降'} ${Math.abs(scoreDelta).toFixed(1)} 分`] : [])] }
  const cities = analyticsCities(restaurants, visits)
  const representativeRestaurants: typeof topRestaurants = []
  const appendRepresentative = (item: typeof topRestaurants[number] | undefined, role: string) => {
    if (item && !representativeRestaurants.some((existing) => existing.restaurantID === item.restaurantID)) representativeRestaurants.push({ ...item, detail: role })
  }
  appendRepresentative(topRestaurants[0], '最常到访')
  appendRepresentative([...topRestaurants].filter((item) => item.scoreOutOfTen != null).sort((a, b) => b.scoreOutOfTen! - a.scoreOutOfTen! || b.count - a.count || Date.parse(b.latestVisitAt) - Date.parse(a.latestVisitAt) || a.id.localeCompare(b.id))[0], '个人到访平均分最高')
  const recentTop = analyticsRestaurantRanking(restaurants, recent)[0]
  appendRepresentative(topRestaurants.find((item) => item.restaurantID === recentTop?.restaurantID), '近 90 天最常到访')
  const representativeCuisine = cuisines[0]?.label
  appendRepresentative([...topRestaurants].sort((a, b) => {
    const value = (item: typeof a) => (cuisineTags(byID.get(item.restaurantID)).includes(representativeCuisine ?? '') ? 2.5 : 0) + (item.scoreOutOfTen ?? 0) * 0.4 + Math.log2(item.count + 1) * 1.2
    return value(b) - value(a) || a.id.localeCompare(b.id)
  })[0], '综合偏好代表餐厅')
  const recordedTasteVisits = visits.filter((visit) => visit.dishes.some((dish) => dish.taste.trim()))
  const rawSnapshot = buildTasteProfileSnapshot(restaurants.filter((restaurant) => topRestaurants.some((item) => item.restaurantID === restaurant.id)), visits, [])
  const timeLabels = ['早餐', '午餐', '下午茶', '晚餐', '夜宵']
  const timeCounts = timeLabels.map((label) => ({ label, count: 0 }))
  // Date-only historical records are valid meals, not midnight/late-night evidence.
  const timedVisits = visits.filter(analyticsHasMealTime)
  const diningTimeNote = `${timedVisits.length}/${visits.length} 次有用餐时刻；按当前时区统计`
  for (const visit of timedVisits) {
    const hour = new Date(visit.visitedAt).getHours()
    timeCounts[hour >= 5 && hour < 10 ? 0 : hour >= 10 && hour < 14 ? 1 : hour >= 14 && hour < 17 ? 2 : hour >= 17 && hour < 22 ? 3 : 4].count += 1
  }
  const snapshot: AnalysisTasteProfileSnapshot = { ...rawSnapshot,
    restaurantCount: summary.restaurantCount, cityCount: summary.cityCount, averageScoreOutOfTen: summary.averageScoreOutOfTen,
    spend: summary.spend.recordedVisitCount ? summary.spend.total : null,
    cuisines: cuisines.slice(0, 7).map((item) => ({ label: item.label, value: Math.round(item.share * 100), symbol: '' })),
    preferences: recordedTasteVisits.length ? rawSnapshot.preferences.map((item) => ({ ...item, symbol: '' })) : [],
    spendCategories: summary.spend.total > 0 ? spendCategories.map((item) => ({ label: item.label, value: item.share * 100, symbol: '' })) : [],
    priceRanges: referenceDistribution.map((item) => ({ label: item.label, value: Math.round(item.share * 100), symbol: '' })),
    cities: cities.map((item) => ({ label: item.label, value: item.restaurantCount, symbol: '' })),
    diningTimes: timedVisits.length ? timeCounts.map((item) => ({ label: item.label, value: Math.round(share(item.count, timedVisits.length) * 100), symbol: '' })) : [],
    cuisineNote: `占 ${visits.length} 次到访；菜系可多选，占比不相加`,
    diningTimeNote,
  }
  const dishGroups = new Map<string, { id: string; label: string; restaurantID: string; visits: Set<string>; ratings: number[] }>()
  for (const visit of visits) for (const dish of visit.dishes) {
    if (!dish.name.trim()) continue
    // Stable dish IDs are evidence. A missing ID cannot merge names across visits.
    const id = dish.id ? `${visit.restaurantId}:${dish.id}` : `${visit.id}:${dish.name.trim()}`
    const item = dishGroups.get(id) ?? { id, label: dish.name.trim(), restaurantID: visit.restaurantId, visits: new Set(), ratings: [] }
    item.visits.add(visit.id)
    if (dish.rating != null && Number.isFinite(dish.rating) && dish.rating >= 0.5 && dish.rating <= 5) item.ratings.push(dish.rating * 2)
    dishGroups.set(id, item)
  }
  const dishes = [...dishGroups.values()].map((item) => ({ id: item.id, label: item.label, restaurantID: item.restaurantID, count: item.visits.size, scoreOutOfTen: analyticsAverage(item.ratings), value: `${item.visits.size} 次` })).sort((a, b) => b.count - a.count || (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1) || a.id.localeCompare(b.id))
  snapshot.dishCount = dishes.length
  const companionCategories = new Map<string, number>()
  for (const visit of visits) {
    const context = analyticsDiningContext(visit)
    const category = context === 'conflict' ? '场景冲突待确认' : context === 'solo' ? '一个人' : visit.diningOccasions.includes('friends') ? '朋友聚餐' : visit.diningOccasions.includes('date') ? '约会' : visit.diningOccasions.includes('family') ? '家庭聚餐' : context === 'together' ? '有同行记录' : '未记录'
    companionCategories.set(category, (companionCategories.get(category) ?? 0) + 1)
  }
  snapshot.companions = [...companionCategories].map(([label, count]) => ({ label, value: Math.round(share(count, visits.length) * 100), symbol: '' }))
  const confidence = analyticsConfidence(visits.length)
  const frequent = [...cuisines].sort((a, b) => b.visitCount - a.visitCount || a.label.localeCompare(b.label))
  const highlyRated = cuisines.filter(item => item.ratedRestaurantCount >= 5 && item.averageScoreOutOfTen != null).sort((a, b) => b.averageScoreOutOfTen! - a.averageScoreOutOfTen! || b.ratedRestaurantCount - a.ratedRestaurantCount || a.label.localeCompare(b.label))
  const common = frequent[0]
  const rated = highlyRated[0]
  const frequentButLowerRated = cuisines.filter(item => {
    if (item.ratedRestaurantCount < 5 || item.averageScoreOutOfTen == null) return false
    const otherRatings = analyticsRepresentativeRatings(visits.filter(visit => !cuisineTags(byID.get(visit.restaurantId)).includes(item.label)))
    const otherAverage = analyticsAverage(otherRatings.map(value => value.scoreOutOfTen))
    return otherRatings.length >= 5 && otherAverage != null && item.averageScoreOutOfTen < otherAverage - .6
  })
  const frequentText = common ? `常吃${common.label}` : ''
  const ratingText = !rated ? '评分偏好还在形成。' : common?.label === rated.label ? `你给它的餐厅平均 ${rated.averageScoreOutOfTen!.toFixed(1)} 分。` : common?.ratedRestaurantCount && common.ratedRestaurantCount >= 5 && common.averageScoreOutOfTen != null && rated.averageScoreOutOfTen! > common.averageScoreOutOfTen ? `却给${rated.label}更高的评分。` : `${rated.label}的 ${rated.ratedRestaurantCount} 家餐厅，平均 ${rated.averageScoreOutOfTen!.toFixed(1)} 分。`
  const headline = !visits.length ? '从第一条真实到访开始' : confidence === 'insufficient' ? '口味档案正在形成' : common ? `${frequentText}，${ratingText}` : '每次真实到访都在丰富你的档案'
  const insights = [summary.visitCount ? `${summary.visitCount} 次到访、${summary.restaurantCount} 家餐厅，${summary.ratedVisitCount} 次有效评分。` : '尚无可分析的个人到访记录。',
    repeat.visitedRestaurantCount ? `${repeat.visitedRestaurantCount} 家餐厅中，${repeat.repeatedRestaurantCount} 家有至少两次到访。` : '',
    recentComparison.available ? recentComparison.changes.length ? `最近 90 天相比此前 90 天：${recentComparison.changes.join('；')}。` : '最近 90 天与此前 90 天相比，暂未发现明显变化。' : '近期与历史记录尚不足以形成口味变化结论。'].filter(Boolean)
  const sections: AnalyticsSection[] = [
    { id: 'cuisines', title: '偏好菜系', confidence, description: '综合评分可靠度、频次、回访、餐厅广度与近期记录；未评分不填补评分。占比按到访计，可多选。', rows: cuisines.map((item) => ({ id: item.label, label: item.label, count: item.visitCount, value: `${item.visitCount} 次 · ${percent(item.share)}`, scoreOutOfTen: item.averageScoreOutOfTen, detail: `${item.ratedVisitCount} 次评分 · ${item.restaurantCount} 家餐厅` })), emptyMessage: '还没有记录到访餐厅的菜系。' },
    { id: 'dish-tastes', title: '菜品口味', description: '仅使用实际菜品口味记录，不用菜系代替；占全部到访的比例，可多选。', rows: snapshot.preferences.map((item) => ({ id: item.label, label: item.label, value: `${item.value}%`, share: item.value / 100 })), emptyMessage: '还没有记录菜品口味。' },
    { id: 'dishes', title: dishes.some(item => item.count > 1) ? '常吃与吃过的菜品' : '吃过的菜品', rows: dishes, emptyMessage: '还没有菜品记录。' },
    { id: 'top-restaurants', title: '最常吃的餐厅', description: '按当前报告范围内的真实到访频次排序，评分仅用于同频次排序。', rows: topRestaurants, emptyMessage: '还没有餐厅到访记录。' },
    { id: 'personal-spend', title: '个人消费', privacy: 'spend', description: `按付款方式计算个人支出；已记录 ${summary.spend.recordedVisitCount}/${visits.length} 次，未记录不算零。`, metrics: [
      { id: 'spend-total', label: summary.spend.display === 'total' ? '总消费' : '已记录消费', value: summary.spend.recordedVisitCount ? money(summary.spend.total) : '未记录', privacy: 'spend' },
      { id: 'spend-median', label: '单次个人支出中位数', value: money(summary.spend.median), privacy: 'spend' },
      { id: 'spend-quartiles', label: '中间一半个人支出', value: summary.spend.lowerQuartile == null ? '未记录' : `${money(summary.spend.lowerQuartile)}–${money(summary.spend.upperQuartile)}`, privacy: 'spend' },
    ], rows: spendCategories.map((item) => ({ id: item.label, label: item.label, value: `${money(item.amount)} · ${percent(item.share)}`, count: item.count, share: item.share, privacy: 'spend' })) },
    { id: 'personal-spend-distribution', title: '单次个人支出分布', privacy: 'spend', confidence: analyticsConfidence(actualPayments.length, 2, 8), description: '按每次实际个人支出落入的区间统计次数；这是个人付款分布，不是下面的用餐参考人均。', rows: personalSpendDistribution.map((item) => ({ id: item.id, label: item.label, count: item.count, share: item.share, value: `${item.count} 次 · ${percent(item.share)}`, privacy: 'spend' })) },
    { id: 'reference-price', title: '参考人均分布', privacy: 'spend', description: '以餐费／人数或各付各的个人金额计算；不是个人支出，不把被请客的零支出当作免费用餐。', metrics: [
      { id: 'reference-median', label: '参考人均中位数', value: money(analyticsPercentile(references.map((item) => item.value), 0.5)), privacy: 'spend' },
      { id: 'reference-typical', label: '常见参考价位', value: leadingPrice?.count ? leadingPrice.label : '未记录', privacy: 'spend' },
      { id: 'reference-sweet', label: '高分较多的参考价位', value: sweetPrice?.label ?? '记录还在积累', note: '已有多次评分', privacy: 'spend' },
    ], rows: referenceDistribution.map((item) => ({ id: item.id, label: item.label, count: item.count, share: item.share, value: `${item.count} 次 · ${percent(item.share)}`, privacy: 'spend' })) },
    { id: 'repeat', title: '回头偏好', confidence: repeat.confidence, description: '有至少两次到访的不同餐厅 ÷ 去过的不同餐厅。', metrics: [{ id: 'repeat-rate', label: '回头餐厅占比', value: topRestaurants.length ? percent(repeat.rate) : '尚无记录' }], rows: repeated, emptyMessage: '还没有重复到访的餐厅。' },
    { id: 'high-traits', title: '高分体验线索', confidence: historical.moduleConfidence.traits, description: '来自有效评分至少 8/10 的实际场景、环境、服务和性价比标签，不是喜欢概率。', rows: historical.highRatingTraits.map((item) => ({ id: item.label, ...item, value: `${item.count} 次` })), emptyMessage: '高分标签仍在积累。' },
    { id: 'pitfalls', title: '低分体验线索', confidence: historical.moduleConfidence.traits, description: '来自低于 6/10 的记录；描述关联，不推断原因。', rows: historical.pitfallTraits.map((item) => ({ id: item.label, ...item, value: `${item.count} 次` })), emptyMessage: '低分体验记录还在积累。' },
    { id: 'hidden-preferences', title: '常吃但未必高分', description: '记录较丰富的菜系与其他餐厅评分相比，常吃不一定代表更喜欢。', rows: frequentButLowerRated.map((item) => ({ id: item.label, label: item.label, count: item.visitCount, value: `${item.visitCount} 次`, scoreOutOfTen: item.averageScoreOutOfTen })), emptyMessage: '暂时没有常吃却评分偏低的菜系。' },
    { id: 'scenes', title: '用餐场景与方式', rows: [...DINING_OCCASION_OPTIONS.map((option) => ({ id: option.value, label: option.label, count: visits.filter((visit) => visit.diningOccasions.includes(option.value)).length })), { id: 'dine-in', label: '到店', count: visits.filter((visit) => visit.diningMode === 'dine_in').length }, { id: 'takeout', label: '外卖', count: visits.filter((visit) => visit.diningMode === 'takeout').length }].filter((item) => item.count).map((item) => ({ ...item, value: `${item.count} 次`, share: share(item.count, visits.length) })), emptyMessage: '还没有场景记录。' },
    { id: 'ratings', title: '评分习惯', confidence: ratingConfidence, description: `${ratings.length} 次有效评分，所有分值均为十分制；未评分不填零。`, metrics: [{ id: 'rating-style', label: '评分风格', value: ratingBehavior.label }, { id: 'rating-average', label: '平均评分', value: average == null ? '未评分' : average.toFixed(1) }, { id: 'rating-median', label: '评分中位数', value: ratingBehavior.median?.toFixed(1) ?? '未评分' }, { id: 'rating-deviation', label: '评分波动', value: ratings.length >= 3 ? deviation!.toFixed(1) : '记录还在积累' }, { id: 'rating-high', label: '8 分及以上', value: ratings.length ? percent(ratingBehavior.highShare) : '未评分' }, { id: 'rating-nine', label: '9 分及以上', value: ratings.length ? percent(ratingBehavior.aboveNineShare) : '未评分' }, { id: 'rating-low', label: '低于 6 分', value: ratings.length ? percent(ratingBehavior.lowShare) : '未评分' }], rows: (['valueRating', 'environmentRating', 'serviceRating'] as const).map((key, index) => ({ id: key, label: ['性价比', '环境', '服务'][index], value: analyticsAverage(visits.flatMap((visit) => visit[key] == null ? [] : [visit[key]! * 2]))?.toFixed(1) ?? '未评分' })) },
    { id: 'companion-context', title: '同行与独自用餐', description: '只比较明确的同行记录与明确“一个人”场景，不把未记录同行人当作独自用餐。两组各三次有效评分才比较差异，不推断因果。', metrics: [{ id: 'with-average', label: '同行时平均评分', value: companionImpact.withAverage?.toFixed(1) ?? '未评分', note: `${companionImpact.withCount} 次评分` }, { id: 'solo-average', label: '独自用餐平均评分', value: companionImpact.soloAverage?.toFixed(1) ?? '未评分', note: `${companionImpact.soloCount} 次评分` }, { id: 'companion-difference', label: '评分差异', value: companionImpact.difference?.toFixed(1) ?? '记录还在积累' }], rows: [{ id: 'with', label: '有同行记录', count: visits.filter((visit) => visit.companionIds.length || visit.companions.length).length }, { id: 'solo', label: '独自用餐', count: visits.filter((visit) => visit.diningOccasions.includes('solo') && !visit.companionIds.length && !visit.companions.length).length }].map((item) => ({ ...item, value: `${item.count} 次` })) },
    { id: 'source-context', title: '推荐来源记录', description: '此处只统计来源类型的记录次数；具体来源比较使用独立来源分析和稳定身份。', rows: RECOMMENDATION_SOURCE_OPTIONS.map((option) => ({ id: option.value, label: option.label, count: visits.filter((visit) => visit.recommendationSourceType === option.value).length })).filter((item) => item.count).map((item) => ({ ...item, value: `${item.count} 次` })), emptyMessage: '尚未记录推荐来源。' },
    { id: 'recent-history', title: '近期与长期口味', description: '最近 90 天与此前 90 天的实际记录比较。', confidence: recentComparison.available ? 'emerging' : 'insufficient', rows: recentComparison.changes.map((label) => ({ id: label, label })), emptyMessage: recentComparison.available ? '暂未发现明显变化。' : '近期和过去的记录还在积累。' },
    { id: 'dining-times', title: '用餐时段', description: diningTimeNote, rows: timedVisits.length ? timeCounts.map((item) => ({ id: item.label, ...item, value: `${item.count} 次 · ${percent(share(item.count, timedVisits.length))}`, share: share(item.count, timedVisits.length) })) : [], emptyMessage: '已有日期可用于回顾；补充真实用餐时刻后才分析时段。' },
    { id: 'cities', title: '城市足迹', rows: cities.map((item) => ({ ...item, value: `${item.restaurantCount} 家 · ${item.count} 次` })), emptyMessage: '尚无明确城市记录。' },
    { id: 'restaurant-roles', title: '代表你的餐厅', description: '最常去、平均分最高、近期常去、综合偏好分别取真实证据，重复餐厅合并；与频次排行是不同维度。', rows: representativeRestaurants, emptyMessage: '记录还在积累，你的代表餐厅会逐渐清晰。' },
  ]
  const companionSection = sections.find(section => section.id === 'companion-context')!
  companionSection.description += ` ${conflictCount} 条独食与同行信息冲突的记录不参与比较。`
  companionSection.rows = [{ id: 'with', label: '明确共同用餐', count: togetherVisits.length }, { id: 'solo', label: '明确独自用餐', count: soloVisits.length }, { id: 'conflict', label: '场景冲突待确认', count: conflictCount }].map(item => ({ ...item, value: `${item.count} 次` }))
  return { summary, confidence, headline, insights, sections, topRestaurants, representativeRestaurants, snapshot, cuisines, frequent, highlyRated, dishes, repeat, referenceDistribution, personalSpendDistribution, spendCategories, recentComparison, ratingBehavior, companionImpact }
}
