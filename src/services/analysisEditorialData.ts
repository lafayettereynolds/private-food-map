import type { AnalysisEditorialPoster, AnalysisEditorialRow, AnalysisEditorialSection, AnalysisShareData, AnalysisVisualRef } from '../types/analysisShare'
import type { AnalyticsReport } from './analyticsReport'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { RestaurantSummary, Visit } from '../types/domain'
import { analyticsCities, analyticsRestaurantRanking, analyticsSummary } from './analyticsReportData'
import { analyticsCuisineShares, buildAnalyticsTasteReport } from './analyticsTasteReport'
import { analyticsReportVisuals } from './analyticsReportVisuals'
import { analyticsVisitDateLabel } from './analyticsPeriodReport'

const percent = (v: number) => `${Math.round(v * 100)}%`
const score = (v: number | null) => v == null ? '未评分' : `${v.toFixed(1)} / 10`
const fallback = (label: string, tags: string[] = []): AnalysisVisualRef => ({ label, tags, source: null, photoId: null, origin: 'fallback' })
const section = (id: string, title: string, rows: AnalysisEditorialRow[], note?: string, empty = '记录还在积累'): AnalysisEditorialSection => ({ id, title, rows, note, empty })
const cuisineRows = (restaurants: RestaurantSummary[], visits: Visit[]) => analyticsCuisineShares(restaurants, visits).sort((a, b) => b.count - a.count || a.label.localeCompare(b.label)).slice(0, 6).map(item => ({ id: item.label, label: item.label, value: percent(item.share), amount: item.count, detail: `${item.count} 次`, visual: fallback(item.label, [item.label]) }))

/** Projection only: shared calculators own all statistics and sample policies. */
export function buildEditorialReport(report: AnalyticsReport, profile: TasteMapProfileDashboardViewModel, audience: 'owner' | 'share'): AnalysisEditorialPoster {
  const owner = audience === 'owner'
  const attributed = new Set(report.source?.sources.flatMap(item => item.restaurants.map(row => row.acquisitionVisitID)) ?? [])
  const visits = report.mode === 'source' ? report.calculationVisits.filter(item => attributed.has(item.id)) : report.mode === 'companion' ? report.scopedVisits : report.calculationVisits
  const restaurants = report.scopedRestaurants
  const summary = report.mode === 'source' ? analyticsSummary(restaurants, visits) : report.summary
  const taste = buildAnalyticsTasteReport(restaurants, visits, new Date(report.generatedAt)).snapshot
  const scopedVisuals = report.mode === 'source' ? analyticsReportVisuals(profile, restaurants, visits) : report.visualEvidence
  const visual = (id: string) => scopedVisuals[id] ?? fallback(restaurants.find(item => item.id === id)?.name ?? '餐厅')
  const restaurantRows = (items: ReturnType<typeof analyticsRestaurantRanking>) => items.slice(0, 5).map(item => ({ id: item.restaurantID, label: item.label, value: `${item.count} 次`, detail: score(item.scoreOutOfTen), amount: item.count, visual: visual(item.restaurantID) }))
  const ranking = analyticsRestaurantRanking(restaurants, visits)
  const first = new Set(report.firstVisitIDs)
  const newIDs = new Set(visits.filter(item => first.has(item.id)).map(item => item.restaurantId))
  const source = report.source
  const sourceName = (id: string, label: string) => owner ? label : `来源 ${Math.max(0, source?.sources.findIndex(item => item.id === id) ?? 0) + 1}`
  const positive = (source?.positiveRanking ?? []).slice(0, 5).map(item => ({ id: item.id, label: sourceName(item.id, item.displayName), value: percent(item.highRatingRate ?? 0), amount: (item.highRatingRate ?? 0) * 100, detail: `高分 ${item.highRatingCount}/${item.ratedRestaurantCount} 家 · ${score(item.averageScoreOutOfTen)}` }))
  const negative = owner ? (source?.pitfallRanking ?? []).slice(0, 5).map(item => ({ id: item.id, label: item.displayName, value: percent(item.lowRatingRate ?? 0), amount: (item.lowRatingRate ?? 0) * 100, detail: `踩坑 ${item.lowRatingCount}/${item.ratedRestaurantCount} 家 · 首次 ${score(item.averageScoreOutOfTen)}` })) : []
  const people = owner ? (report.companion?.companions ?? []).slice(0, 3).map(item => ({ id: item.id, label: item.displayName, value: `${item.sharedVisitCount} 次`, amount: item.sharedVisitCount, detail: `${item.restaurantCount} 家餐厅 · 你的评分 ${score(item.ratingAverage)}` })) : []
  const sections = [
    section('frequent', '最常去的餐厅 TOP 3', restaurantRows(ranking).slice(0, 3), '按本期实际到访次数，不等同最喜欢'),
    section('new', '本期新发现', restaurantRows(ranking.filter(item => newIDs.has(item.restaurantID))).slice(0, 3), '首次有效记录落在本期'),
    section('repeat', '本期再次到访', restaurantRows(analyticsRestaurantRanking(restaurants, visits.filter(item => !first.has(item.id)))).slice(0, 3), '不含每家餐厅的首次有效记录'),
    section('people', '常见饭搭子', people, owner ? '同行次数可重叠；不代表关系排名' : '同行姓名不进入分享版', owner ? '尚无可核验的同行关联' : '完整同行记录仅本人可见'),
    section('positive', '最会种草推荐来源', positive, '首次体验 ≥ 8 / 10；至少 5 家已评分'),
    section('negative', '最坑推荐来源', negative, owner ? `首次评分 ≤ ${source?.overallSourceRating == null ? '待计算' : (source.overallSourceRating - 1).toFixed(1)} / 10；仅代表你的体验` : '负向来源榜仅本人可见', owner ? '没有达到比较门槛的来源' : '分享版不展示负向来源榜'),
    section('cities', '城市足迹 TOP 5', analyticsCities(restaurants, visits).slice(0, 5).map(item => ({ id: item.id, label: item.label, value: `${item.restaurantCount} 家`, amount: item.count, detail: `${item.count} 次到访` })), '按实际记录城市汇总，不补造地点'),
    section('times', '用餐时间分布', taste.diningTimes.map(item => ({ id: item.label, label: item.label, value: `${item.value}%`, amount: item.value })), taste.diningTimeNote, '尚无可靠用餐时刻'),
    section('prices', '参考人均区间', owner ? taste.priceRanges.map(item => ({ id: item.label, label: item.label, value: `${item.value}%`, amount: item.value })) : [], owner ? '与个人实际支出分开统计' : '金额与价位不进入分享版', owner ? '尚无可靠人均记录' : '消费信息仅本人可见'),
    section('insight', '本期值得记住', report.insights.filter(Boolean).slice(0, 2).map((text, index) => ({ id: String(index), label: text, value: '' })), '由当前周期的真实记录生成'),
  ]
  // Use shared section findings, never period report legacy source/name summaries.
  const changes = report.sections.find(item => item.id === 'period-taste-change')
  sections.find(item => item.id === 'insight')!.rows = (changes?.rows ?? []).slice(0, 2).map(item => ({ id: item.id, label: item.label, value: item.value ?? '' }))
  const comparison = report.period?.comparison
  sections.push(section('comparison', '与上一周期相比', comparison?.statistics ? [
    { id: 'visits', label: '用餐记录', value: `${comparison.statistics.visitDelta >= 0 ? '+' : ''}${comparison.statistics.visitDelta} 次` },
    { id: 'restaurants', label: '不同餐厅', value: `${comparison.statistics.restaurantDelta >= 0 ? '+' : ''}${comparison.statistics.restaurantDelta} 家` },
  ] : [], comparison?.previousLabel, '可比记录不足，不补同比箭头'))
  if (report.mode === 'annual') {
    sections.push(section('annual-cuisines', '年度常吃菜系 TOP 5', cuisineRows(restaurants, visits).slice(0, 5), '多菜系可重复计入'))
    sections.push(section('quarters', '四季食味', Array.from({ length: 4 }, (_, index) => {
      const scoped = visits.filter(item => Math.floor(new Date(item.visitedAt).getMonth() / 3) === index)
      const leading = cuisineRows(restaurants, scoped)[0]
      const future = new Date(report.scope.year!, index * 3, 1) > new Date(report.generatedAt)
      return { id: String(index), label: `第 ${index + 1} 季度`, value: future ? '未开始' : `${scoped.length} 次`, detail: future ? '不提前计算未来记录' : leading ? `常吃 ${leading.label}` : '暂无记录', amount: future ? undefined : scoped.length, visual: leading?.visual }
    }), '按日历季度记录，不虚构季节偏好'))
    sections.push(section('journey', '年度用餐记录轨迹', (report.period?.monthlySnapshots ?? []).map(item => ({ id: String(item.month), label: `${item.month}月`, value: item.observationState === 'future' ? '未开始' : `${item.visitCount} 次`, amount: item.observationState === 'future' ? undefined : item.visitCount, detail: item.dominantCuisine ?? undefined })), '实际记录次数；不是推测的口味强度'))
    const bestRated = [...ranking].filter(item => item.scoreOutOfTen != null).sort((a, b) => b.scoreOutOfTen! - a.scoreOutOfTen! || b.count - a.count || a.id.localeCompare(b.id))
    sections.push(section('rated', '年度高分餐厅', restaurantRows(bestRated).slice(0, 1), '按本年度你的实际平均评分'))
  }
  if (report.mode === 'companion') {
    const selected = report.companion?.companions.find(item => item.id === report.companion?.selectedCompanionID)
    sections.push(section('partner', '这份共同用餐档案', selected ? [{ id: selected.id, label: owner ? selected.displayName : '一位饭搭子', value: `${selected.sharedVisitCount} 次共同用餐`, detail: '评分与口味来自你的记录，不代表双方共同评价' }] : [], undefined, '请选择有共同记录的饭搭子'))
    sections.push(section('preferences', '共同用餐中的口味', taste.preferences.map(item => ({ id: item.label, label: item.label, value: `${item.value}%`, amount: item.value, visual: fallback(item.label) })), '仅使用你记录的真实口味标签'))
    sections.push(section('occasions', '一起用餐场景', (selected?.occasions ?? []).slice(0, 4).map(item => ({ id: item.id, label: item.label, value: item.value ?? `${item.count} 次`, amount: item.count })), '场景可以重叠，不推断关系类型'))
    sections.find(item => item.id === 'insight')!.rows = (selected?.keywords ?? []).slice(0, 3).map((label, index) => ({ id: String(index), label, value: '' }))
  }
  if (report.mode === 'source') {
    const all = source?.sources ?? []
    sections.push(section('pending', '待验证来源', all.filter(item => item.ratedRestaurantCount < 5).slice(0, 5).map(item => ({ id: item.id, label: sourceName(item.id, item.displayName), value: `${item.ratedRestaurantCount} 家`, detail: '首次体验已评分；尚未入榜' })), '不足样本门槛，不参与高低榜'))
    sections.push(section('source-cuisines', '来源带来的菜系', all.filter(item => item.restaurantCount > 0).slice(0, 4).map(item => ({ id: item.id, label: sourceName(item.id, item.displayName), value: '', detail: item.cuisines.slice(0, 3).map(cuisine => `${cuisine.label} ${cuisine.count}家`).join(' · '), visual: item.cuisines[0] ? fallback(item.cuisines[0].label) : undefined })), '样本事实，不直接称为擅长'))
    sections.push(section('source-cities', '来源带来的城市', all.filter(item => item.restaurantCount > 0).slice(0, 4).map(item => ({ id: item.id, label: sourceName(item.id, item.displayName), value: '', detail: analyticsCities(restaurants, visits.filter(visit => item.restaurants.some(restaurant => restaurant.restaurantID === visit.restaurantId))).slice(0, 3).map(city => city.label).join(' · ') || '城市未记录' }))))
    sections.push(section('method', '如何读懂这份来源档案', [{ id: 'baseline', label: '个人首次体验基准', value: score(source?.overallSourceRating ?? null), detail: `${source?.baselineRestaurantCount ?? 0} 家首次已评分餐厅；回访不替换首次评分` }, { id: 'missing', label: '未去过不等于推荐失败', value: '', detail: '当前记录尚无完整收藏—来源关联，不能统计总推荐数或采纳率。' }]))
  }
  const overview = [
    { label: '用餐记录', value: `${summary.visitCount} 次` },
    { label: '记录餐厅', value: `${summary.restaurantCount} 家` },
    { label: owner ? '已记录个人支出' : '个人支出', value: owner ? summary.spend.recordedVisitCount ? `¥${Math.round(summary.spend.total).toLocaleString('zh-CN')}` : '未记录' : '未分享', note: owner ? `${summary.spend.recordedVisitCount}/${summary.visitCount} 次有金额` : undefined },
    { label: '你的平均评分', value: score(summary.averageScoreOutOfTen), note: `${summary.ratedVisitCount} 次评分` },
    { label: report.mode === 'source' ? '已归因餐厅' : '首次记录餐厅', value: `${report.mode === 'source' ? new Set(source?.sources.flatMap(item => item.restaurants.map(row => row.restaurantID)) ?? []).size : newIDs.size} 家` },
  ]
  if (report.mode === 'companion') {
    const selected = report.companion?.companions.find(item => item.id === report.companion?.selectedCompanionID)
    overview.splice(0, overview.length, { label: '一起用餐', value: `${summary.visitCount} 次` }, { label: '一起去过餐厅', value: `${summary.restaurantCount} 家` }, { label: '你的共同用餐评分', value: score(summary.averageScoreOutOfTen) }, { label: '首次探索时有 TA', value: `${selected?.firstTogetherRestaurantCount ?? 0} 家` }, { label: '共同城市足迹', value: `${summary.cityCount} 个` })
  }
  return { audience, overview, cuisines: cuisineRows(restaurants, visits), sections }
}

/** Exact-day inputs come from the existing review service, not timestamp guesses. */
export function buildDayEditorial(data: AnalysisShareData, profile: TasteMapProfileDashboardViewModel | undefined, restaurants: RestaurantSummary[], visits: Visit[], audience: 'owner' | 'share', now: Date): AnalysisShareData {
  const owner = audience === 'owner'
  const scoped = visits.filter(item => owner || item.visibility === 'public')
  const summary = analyticsSummary(restaurants, scoped)
  const visuals = profile ? analyticsReportVisuals(profile, restaurants, scoped) : {}
  const memoryRows = [...scoped].sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt)).map(item => ({ id: item.id, label: restaurants.find(restaurant => restaurant.id === item.restaurantId)?.name ?? '餐厅', value: analyticsVisitDateLabel(item.visitedAt), detail: [score(item.rating == null ? null : item.rating * 2), owner ? item.note : ''].filter(Boolean).join(' · '), visual: profile ? analyticsReportVisuals(profile, restaurants, [item])[item.restaurantId] : undefined }))
  const taste = buildAnalyticsTasteReport(restaurants, scoped, now).snapshot
  const years = [...new Set(scoped.map(item => new Date(item.visitedAt).getFullYear()))].sort((a, b) => a - b)
  const sections = [
    section('memories', '同日回忆', memoryRows.slice(0, 4), `${scoped.length} 条实际记录；完整记录保留在数据模式`),
    section('cuisines', '那天你记录过什么', cuisineRows(restaurants, scoped), '菜系可以多选，占比不相加'),
    section('cities', '同日城市足迹', analyticsCities(restaurants, scoped).slice(0, 5).map(item => ({ id: item.id, label: item.label, value: `${item.count} 次`, amount: item.count, detail: `${item.restaurantCount} 家餐厅` })), '仅实际记录城市，不生成虚构路线'),
    section('years', '这些年的同一天', years.slice(-4).map(year => { const rows = scoped.filter(item => new Date(item.visitedAt).getFullYear() === year); const common = cuisineRows(restaurants, rows)[0]; return { id: String(year), label: `${year} 年`, value: `${rows.length} 次`, detail: common ? `常见菜系：${common.label}` : '菜系未记录', visual: common?.visual } }), '心情没有结构化记录，不推测情绪'),
    section('remember', '那天的高分记忆', [...memoryRows].filter(item => scoped.find(visit => visit.id === item.id)?.rating != null).sort((a, b) => scoped.find(item => item.id === b.id)!.rating! - scoped.find(item => item.id === a.id)!.rating!).slice(0, 1), '按当次实际评分；不预测下次体验'),
    section('keywords', '回忆里的食味', taste.cuisines.slice(0, 5).map(item => ({ id: item.label, label: item.label, value: `${item.value}%`, visual: fallback(item.label) })), '来自已记录菜系，而非自动生成情绪标签'),
  ]
  const evidence = analyticsRestaurantRanking(restaurants, scoped).slice(0, 3).map(item => ({ restaurantId: item.restaurantID, name: item.label, meta: `${item.count} 次同日记录`, score: item.scoreOutOfTen?.toFixed(1), image: visuals[item.restaurantID] ?? fallback(item.label) }))
  return { ...data, memoryCard: false, editorial: { audience, overview: [{ label: '同日用餐', value: `${scoped.length} 次` }, { label: '不同年份', value: `${years.length} 年` }, { label: '餐厅', value: `${summary.restaurantCount} 家` }, { label: '城市', value: `${summary.cityCount} 个` }], cuisines: cuisineRows(restaurants, scoped), sections }, restaurants: evidence, heroCandidates: evidence.map(item => item.image), privacy: { companionNameIncluded: owner, spendIncluded: owner, exactLocationIncluded: false } }
}
