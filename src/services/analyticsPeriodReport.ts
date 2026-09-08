import { DINING_OCCASION_OPTIONS, type RestaurantSummary, type Visit } from '../types/domain'
import { reviewService } from './reviewService'
import { analyticsCities, analyticsConfidence, analyticsRestaurantRanking, analyticsSummary } from './analyticsReportData'
import { analyticsCuisineShares } from './analyticsTasteReport'
import type { AnalyticsSection } from './analyticsReportTypes'
import { ANALYTICS_EVIDENCE_RULES, analyticsComparableWindow, analyticsFrequencyEvidence } from './analyticsEvidenceRules'
import { LEGACY_AMOUNT_CURRENCY } from '../contracts/legacyMoney'

export function analyticsPeriodBounds(mode: 'monthly' | 'annual', year: number, month: number) {
  if (!Number.isInteger(year) || year < 1900 || year > 9999 || !Number.isInteger(month) || month < 1 || month > 12) throw new RangeError('分析周期无效')
  const start = new Date(year, mode === 'monthly' ? month - 1 : 0, 1)
  const end = new Date(year + (mode === 'annual' ? 1 : 0), mode === 'monthly' ? month : 0, 1)
  return { start, end }
}
const within = (visits: Visit[], start: Date, end: Date) => visits.filter((visit) => Date.parse(visit.visitedAt) >= start.getTime() && Date.parse(visit.visitedAt) < end.getTime())
const ratio = (value: number, total: number) => total ? value / total : 0
export function analyticsVisitDateLabel(value: string) {
  const date = new Date(value)
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function tasteComparison(restaurants: RestaurantSummary[], current: Visit[], previous: Visit[]) {
  const available = analyticsFrequencyEvidence(current) && analyticsFrequencyEvidence(previous)
  const tagShares = (visits: Visit[]) => analyticsCuisineShares(restaurants, visits)
  const currentShares = tagShares(current)
  const previousShares = tagShares(previous)
  const labels = [...new Set([...currentShares, ...previousShares].map((item) => item.label))]
  const changes = available ? labels.map((label) => ({ label,
    currentShare: currentShares.find((item) => item.label === label)?.share ?? 0,
    previousShare: previousShares.find((item) => item.label === label)?.share ?? 0,
  })).map((item) => ({ ...item, delta: item.currentShare - item.previousShare })).filter((item) => Math.abs(item.delta) + Number.EPSILON >= ANALYTICS_EVIDENCE_RULES.frequencyChange)
    .sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta) || a.label.localeCompare(b.label)) : []
  return { available, currentVisitCount: current.length, previousVisitCount: previous.length, changes }
}

export function buildAnalyticsPeriodReport(restaurants: RestaurantSummary[], allVisits: Visit[], mode: 'monthly' | 'annual', year: number, month: number, now = new Date()) {
  analyticsPeriodBounds(mode, year, month) // Validate before creating comparison dates.
  allVisits = allVisits.filter(visit => !visit.deletedAt && Date.parse(visit.visitedAt) <= now.getTime())
  const comparisonWindow = analyticsComparableWindow(mode, year, month, now)
  const { start, end, previousStart } = comparisonWindow
  const visits = within(allVisits, start, end)
  const comparisonVisits = within(allVisits, start, comparisonWindow.currentEnd)
  const previousVisits = within(allVisits, previousStart, comparisonWindow.previousEnd)
  // Reuse the complete historical period pipeline: first ever / repeats / memories /
  // period comparisons / coverage. No all-time Restaurant average/count substitution.
  const legacyReview = mode === 'monthly' ? reviewService.monthly(restaurants, allVisits, year, month) : reviewService.annual(restaurants, allVisits, year)
  const summary = analyticsSummary(restaurants, visits)
  const comparisonSummary = analyticsSummary(restaurants, comparisonVisits)
  const previousSummary = analyticsSummary(restaurants, previousVisits)
  const topRestaurants = analyticsRestaurantRanking(restaurants, visits)
  const cities = analyticsCities(restaurants, visits)
  const taste = tasteComparison(restaurants, comparisonVisits, previousVisits)
  const newCount = (scoped: Visit[], boundary: Date) => new Set(scoped.filter(visit => !allVisits.some(old => old.restaurantId === visit.restaurantId && Date.parse(old.visitedAt) < boundary.getTime())).map(visit => visit.restaurantId)).size
  const repeatCount = (scoped: Visit[], boundary: Date) => new Set(scoped.filter(visit => scoped.filter(other => other.restaurantId === visit.restaurantId).length > 1 || allVisits.some(old => old.restaurantId === visit.restaurantId && Date.parse(old.visitedAt) < boundary.getTime())).map(visit => visit.restaurantId)).size
  const explorationDelta = ratio(newCount(comparisonVisits, start), comparisonSummary.restaurantCount) - ratio(newCount(previousVisits, previousStart), previousSummary.restaurantCount)
  const repeatDelta = ratio(repeatCount(comparisonVisits, start), comparisonSummary.restaurantCount) - ratio(repeatCount(previousVisits, previousStart), previousSummary.restaurantCount)
  const behaviorChanges = taste.available ? [
    ...(explorationDelta >= 0.2 ? [`新店占比提高 ${Math.round(explorationDelta * 100)} 个百分点`] : []),
    ...(repeatDelta >= 0.2 ? [`熟店或周期内重复到访占比提高 ${Math.round(repeatDelta * 100)} 个百分点`] : []),
  ] : []
  const spendCoverageEligible = comparisonSummary.spend.coverage >= ANALYTICS_EVIDENCE_RULES.spendComparisonCoverage
    && previousSummary.spend.coverage >= ANALYTICS_EVIDENCE_RULES.spendComparisonCoverage
  const statistics = comparisonVisits.length && previousVisits.length ? {
    visitDelta: comparisonVisits.length - previousVisits.length,
    restaurantDelta: comparisonSummary.restaurantCount - previousSummary.restaurantCount,
    // Historical amounts share the explicitly approved CNY compatibility rule.
    // Missing amounts still require sufficient coverage in both matched windows.
    spendDelta: spendCoverageEligible ? comparisonSummary.spend.total - previousSummary.spend.total : null,
  } : null
  const review = { ...legacyReview, comparison: statistics, changes: [], cityCount: cities.length, mapFootprint: cities.map((item) => ({ city: item.label, count: item.count })),
    // Entity-specific modules below use the new stable-identity reports. Legacy
    // name merging / one-sample "best source" must never leak into this report.
    companions: [], recommendationSources: [], companionInsight: null, sourceInsight: null,
    tasteChanges: taste.changes.map((item) => `${item.label}占比${item.delta > 0 ? '提高' : '下降'} ${Math.round(Math.abs(item.delta) * 100)} 个百分点`),
    keyRestaurants: legacyReview.keyRestaurants.map((item) => ({ ...item, label: item.kind === 'first' ? '本期第一家' : item.kind === 'highest' ? '本期最高分' : item.label })),
  }
  const periodLabel = (mode === 'monthly' ? `${year} 年 ${month} 月` : `${year} 年`) + (comparisonWindow.isCurrent ? `（截至 ${now.getMonth() + 1} 月 ${now.getDate()} 日）` : '')
  const previousLabel = (mode === 'monthly' ? `${previousStart.getFullYear()} 年 ${previousStart.getMonth() + 1} 月` : `${year - 1} 年`) + (comparisonWindow.isCurrent ? '同期' : '')
  const monthlySnapshots = mode === 'annual' ? Array.from({ length: 12 }, (_, index) => {
    const bounds = analyticsPeriodBounds('monthly', year, index + 1)
    const scoped = within(allVisits, bounds.start, bounds.end)
    const monthly = reviewService.monthly(restaurants, allVisits, year, index + 1)
    const monthSummary = analyticsSummary(restaurants, scoped)
    return { month: index + 1, observationState: bounds.start > now ? 'future' as const : bounds.end > now ? 'inProgress' as const : 'complete' as const, visitCount: scoped.length, restaurantCount: monthly.restaurantCount,
      newRestaurantCount: monthly.newRestaurantCount, repeatRestaurantCount: monthly.revisitCount,
      explorationRate: ratio(monthly.newRestaurantCount, monthly.restaurantCount), repeatRate: ratio(monthly.revisitCount, monthly.restaurantCount),
      dominantCuisine: [...analyticsCuisineShares(restaurants, scoped)].sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))[0]?.label ?? null,
      representative: analyticsRestaurantRanking(restaurants, scoped)[0] ?? null, spend: monthSummary.spend,
      ratedVisitCount: monthSummary.ratedVisitCount, averageScoreOutOfTen: monthSummary.averageScoreOutOfTen }
  }) : []
  const activeMonths = monthlySnapshots.filter((item) => item.visitCount)
  const activeQuarters = new Set(visits.map((visit) => Math.floor(new Date(visit.visitedAt).getMonth() / 3))).size
  const journeyGranularity = mode !== 'annual' ? 'insufficient' : visits.length >= 12 && activeMonths.length >= 4 ? 'monthly' : visits.length >= 6 && activeQuarters >= 2 ? 'quarterly' : 'insufficient'
  const journey = journeyGranularity === 'monthly' ? activeMonths.map((item) => ({ id: `month-${item.month}`, label: `${item.month} 月`, month: item.month, visitCount: item.visitCount, dominantCuisine: item.dominantCuisine, representative: item.representative }))
    : journeyGranularity === 'quarterly' ? Array.from({ length: 4 }, (_, index) => {
      const scoped = visits.filter((visit) => Math.floor(new Date(visit.visitedAt).getMonth() / 3) === index)
      return { id: `quarter-${index + 1}`, label: `第 ${index + 1} 季度`, month: index * 3 + 1, visitCount: scoped.length,
        dominantCuisine: [...analyticsCuisineShares(restaurants, scoped)].sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))[0]?.label ?? null,
        representative: analyticsRestaurantRanking(restaurants, scoped)[0] ?? null }
    }).filter((item) => item.visitCount) : []
  const firstHalf = visits.filter((visit) => new Date(visit.visitedAt).getMonth() < 6)
  const secondHalf = visits.filter((visit) => new Date(visit.visitedAt).getMonth() >= 6)
  // Do not compare a partial second half to a completed first half.
  const halfYearComparison = mode === 'annual' ? tasteComparison(restaurants, comparisonWindow.isCurrent ? [] : secondHalf, firstHalf) : null
  const annualNewIDs = new Set(visits.filter((visit) => !allVisits.some((old) => old.restaurantId === visit.restaurantId && Date.parse(old.visitedAt) < start.getTime())).map((visit) => visit.restaurantId))
  const firstHalfIDs = new Set(firstHalf.map((visit) => visit.restaurantId))
  const secondHalfIDs = new Set(secondHalf.map((visit) => visit.restaurantId))
  const halfExplorationDelta = ratio([...secondHalfIDs].filter((id) => annualNewIDs.has(id)).length, secondHalfIDs.size) - ratio([...firstHalfIDs].filter((id) => annualNewIDs.has(id)).length, firstHalfIDs.size)
  const sceneRanking = (scoped: Visit[]) => DINING_OCCASION_OPTIONS.map((option) => ({ label: option.label, count: scoped.filter((visit) => visit.diningOccasions.includes(option.value)).length })).filter((item) => item.count).sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
  const firstScene = sceneRanking(firstHalf)[0]
  const secondScene = sceneRanking(secondHalf)[0]
  const halfBehaviorChanges = halfYearComparison?.available ? [
    ...(Math.abs(halfExplorationDelta) >= 0.2 ? [`下半年新店占比${halfExplorationDelta > 0 ? '提高' : '下降'} ${Math.round(Math.abs(halfExplorationDelta) * 100)} 个百分点（相对全年新店）。`] : []),
    ...(secondScene && secondScene.label !== firstScene?.label && ratio(secondScene.count, secondHalf.length) >= 0.4 ? [`下半年更常记录“${secondScene.label}”场景。`] : []),
  ] : []
  const monthlyHighlights: NonNullable<AnalyticsSection['rows']> = mode === 'annual' ? [
    [...activeMonths].sort((a, b) => b.visitCount - a.visitCount || a.month - b.month)[0],
    [...activeMonths].filter((item) => item.newRestaurantCount).sort((a, b) => b.newRestaurantCount - a.newRestaurantCount || a.month - b.month)[0],
  ].flatMap((item, index) => item ? [{ id: index === 0 ? 'busiest' : 'exploration', label: index === 0 ? '到访最多的月份' : '新店最多的月份', value: `${item.month} 月 · ${index === 0 ? `${item.visitCount} 次` : `${item.newRestaurantCount} 家`}`, restaurantID: item.representative?.restaurantID }] : []) : []
  const bestRatedMonth = [...activeMonths].filter((item) => item.ratedVisitCount >= 2).sort((a, b) => b.averageScoreOutOfTen! - a.averageScoreOutOfTen! || a.month - b.month)[0]
  if (bestRatedMonth) monthlyHighlights.push({ id: 'rating', label: '评分更高的月份', value: `${bestRatedMonth.month} 月 · ${bestRatedMonth.averageScoreOutOfTen!.toFixed(1)} / 10`, detail: `${bestRatedMonth.ratedVisitCount} 次评分`, restaurantID: bestRatedMonth.representative?.restaurantID })
  const highSpendMonth = [...activeMonths].filter((item) => item.spend.coverage >= 0.6).sort((a, b) => b.spend.total - a.spend.total || a.month - b.month)[0]
  if (highSpendMonth) monthlyHighlights.push({ id: 'spend', label: '已记录消费较高的月份', value: `${highSpendMonth.month} 月 · ¥${highSpendMonth.spend.total}`, detail: `该月支出记录覆盖 ${Math.round(highSpendMonth.spend.coverage * 100)}%`, privacy: 'spend' })
  const newRestaurants = topRestaurants.filter((item) => !allVisits.some((visit) => visit.restaurantId === item.restaurantID && Date.parse(visit.visitedAt) < start.getTime()))
  const headline = visits.length ? `${periodLabel}留下了 ${visits.length} 次真实到访` : `${periodLabel}尚无到访记录`
  const insights = [review.summary, ...review.tasteChanges, ...behaviorChanges]
  const comparison = { ...taste, previousLabel, currentSummary: comparisonSummary, previousSummary, statistics: review.comparison, behaviorChanges,
    window: comparisonWindow, spendCurrency: LEGACY_AMOUNT_CURRENCY,
    spendAvailability: spendCoverageEligible ? 'available' as const : 'insufficientCoverage' as const,
    spendCoverageEligible }
  // A Restaurant creation date or its current bookmark state is not a saved-event history.
  const wishlistRedemption = { availability: 'historyUnavailable' as const, redeemedRestaurantCount: null, newSavedRestaurantCount: null, medianWaitingDays: null }
  const cuisineFrequency = [...analyticsCuisineShares(restaurants, visits)].sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
  const sections: AnalyticsSection[] = [
    { id: 'period-overview', title: `${periodLabel}数据`, description: '只统计选定周期；第一家新店按全部历史中的第一次有效到访判断。', metrics: [
      { id: 'period-visits', label: '到访', value: `${summary.visitCount} 次` }, { id: 'period-restaurants', label: '餐厅', value: `${summary.restaurantCount} 家` },
      { id: 'period-new', label: '首次到访餐厅', value: `${review.newRestaurantCount} 家` }, { id: 'period-repeat', label: '熟店与重复到访', value: `${review.revisitCount} 家` },
      { id: 'period-score', label: '本期平均评分', value: summary.averageScoreOutOfTen?.toFixed(1) ?? '未评分', note: `${summary.ratedVisitCount} 次评分 · 十分制` },
    ] },
    { id: 'period-spend', title: '个人消费', privacy: 'spend', description: `已记录 ${summary.spend.recordedVisitCount}/${visits.length} 次；个人支出与参考人均分开。`, metrics: [{ id: 'period-spend-amount', label: summary.spend.display === 'total' ? '总消费' : '已记录消费', value: summary.spend.recordedVisitCount ? `¥${summary.spend.total}` : '未记录', note: summary.spend.display === 'hidden' ? '仍有用餐支出未记录' : undefined, privacy: 'spend' }] },
    { id: 'period-restaurants', title: '本期最常吃', rows: topRestaurants, emptyMessage: '本期还没有餐厅到访记录。' },
    { id: 'period-new-restaurants', title: '本期新发现', description: '每家都以全部历史中第一次有效到访落在本期为依据。', rows: newRestaurants, emptyMessage: '本期没有首次到访的新餐厅。' },
    { id: 'period-key-restaurants', title: '值得记住的餐厅', rows: review.keyRestaurants.map((item) => ({ id: item.kind, label: `${item.label} · ${item.memory.restaurantName}`, restaurantID: item.memory.restaurantId, scoreOutOfTen: item.memory.scoreOutOfTen, value: analyticsVisitDateLabel(item.memory.visitedAt) })), emptyMessage: '本期还没有可回顾的餐厅。' },
    { id: 'period-cuisines', title: '本期常见菜系', description: '按本期实际到访频次，不用全档案评分替代。多菜系可重复计入。', rows: cuisineFrequency.map((item) => ({ id: item.label, ...item, value: `${item.count} 次` })), emptyMessage: '本期尚无菜系记录。' },
    { id: 'period-comparison', title: `对比 ${previousLabel}`, confidence: review.comparison ? 'emerging' : 'insufficient', description: comparisonWindow.isCurrent ? '按相邻周期可对应的日期比较。' : '比较相邻完整周期的实际记录。', metrics: review.comparison ? [
      { id: 'visit-delta', label: '到访变化', value: `${review.comparison.visitDelta > 0 ? '+' : ''}${review.comparison.visitDelta} 次` },
      { id: 'restaurant-delta', label: '餐厅变化', value: `${review.comparison.restaurantDelta > 0 ? '+' : ''}${review.comparison.restaurantDelta} 家` },
      { id: 'spend-delta', label: '已记录支出变化', value: review.comparison.spendDelta == null ? '记录不足，不比较' : `${review.comparison.spendDelta > 0 ? '+' : ''}¥${Number(review.comparison.spendDelta.toFixed(2))}`, privacy: 'spend' },
    ] : [], emptyMessage: '当前或上一周期记录不足，暂不比较。' },
    { id: 'period-taste-change', title: '口味与探索变化', confidence: taste.available ? 'emerging' : 'insufficient', description: '比较两段时间的实际用餐频率；记录不足时不推断偏好变化。', rows: [...review.tasteChanges, ...behaviorChanges].map((label) => ({ id: label, label })), emptyMessage: taste.available ? '暂未发现明显变化。' : '这两段时间的记录还在积累。' },
    { id: 'period-memories', title: '真实味觉记忆', description: '保留真实到访证据；私人笔记不直接进入默认分享。', rows: review.memories.map((item) => ({ id: item.visitId, label: item.restaurantName, restaurantID: item.restaurantId, value: analyticsVisitDateLabel(item.visitedAt), scoreOutOfTen: item.scoreOutOfTen, detail: [item.note ? '有到访笔记' : '', item.photo.origin === 'visit' ? '有到访照片' : ''].filter(Boolean).join(' · ') })), emptyMessage: '本期还没有用餐回忆。' },
    { id: 'period-cities', title: '城市足迹', rows: cities.map((item) => ({ ...item, value: `${item.restaurantCount} 家 · ${item.count} 次` })), emptyMessage: '本期还没有记录用餐城市。' },
    { id: 'period-time', title: mode === 'monthly' ? '一周用餐分布' : '全年用餐分布', rows: review.timeDistribution.map((item) => ({ id: item.label, ...item, value: `${item.count} 次` })) },
  ]
  if (mode === 'annual') sections.push(
    { id: 'annual-months', title: '十二个月', description: '每月的实际记录；未来月份尚未开始。', rows: monthlySnapshots.map((item) => ({ id: String(item.month), label: `${item.month} 月`, value: item.observationState === 'future' ? '尚未开始' : `${item.visitCount} 次 · ${item.restaurantCount} 家`, detail: item.observationState === 'future' ? undefined : `新店 ${item.newRestaurantCount} 家 · 熟店 ${item.repeatRestaurantCount} 家${item.dominantCuisine ? ` · ${item.dominantCuisine}` : ''}`, restaurantID: item.representative?.restaurantID })) },
    { id: 'annual-journey', title: '年度味觉旅程', confidence: journey.length ? analyticsConfidence(visits.length, 6, 18) : 'insufficient', description: '至少 12 次且覆盖 4 个月使用月度；否则至少 6 次且覆盖 2 季度使用季度。', rows: journey.map((item) => ({ id: item.id, label: item.label, value: `${item.visitCount} 次`, detail: item.dominantCuisine ?? '菜系未记录', restaurantID: item.representative?.restaurantID })), emptyMessage: '年度用餐记录还在积累。' },
    { id: 'annual-half-comparison', title: '上下半年口味比较', confidence: halfYearComparison?.available ? 'emerging' : 'insufficient', description: '比较两个完整半年的实际用餐频率。', rows: [...(halfYearComparison?.changes ?? []).map((item) => ({ id: item.label, label: item.label, value: `${item.delta > 0 ? '+' : ''}${Math.round(item.delta * 100)} 个百分点` })), ...halfBehaviorChanges.map((label) => ({ id: label, label }))], emptyMessage: halfYearComparison?.available ? '暂未发现明显变化。' : '上下半年的记录还在积累。' },
    { id: 'annual-highlights', title: '年度记录亮点', rows: monthlyHighlights, emptyMessage: '年度用餐记录还在积累。' },
  )
  return { summary, headline, insights, sections, topRestaurants, newRestaurants, confidence: analyticsConfidence(visits.length, mode === 'monthly' ? 3 : 4, mode === 'monthly' ? 8 : 16), periodLabel, previousLabel, start, end, visits, review, comparison, wishlistRedemption, monthlySnapshots, journeyGranularity, journey, halfYearComparison, halfBehaviorChanges, monthlyHighlights }
}
