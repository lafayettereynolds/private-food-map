import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { AnalysisShareData, AnalysisShareType } from '../types/analysisShare'
import type { AnalyticsReport } from './analyticsReport'
import { filterAnalysisSharePrivacy } from './analysisShare'
import { analyticsResultHighlights } from './analyticsReportHighlights'

const types: Record<AnalyticsReport['mode'], AnalysisShareType> = { taste: 'TASTE_PROFILE', companion: 'COMPANION_ANALYSIS', source: 'RECOMMENDATION_SOURCE', monthly: 'MONTHLY_REVIEW', annual: 'ANNUAL_REVIEW' }
const eyebrows = { taste: 'TASTE PROFILE', companion: 'DINING COMPANION', source: 'RECOMMENDATION SOURCE', monthly: 'MONTHLY REVIEW', annual: 'ANNUAL REVIEW' }

function shareableSections(report: AnalyticsReport) {
  // These companion sections contain only anonymous aggregates, not directory names,
  // private notes, identity keys or spending. Do not broadly bypass privacy tags.
  const anonymous = new Set(['companion-evidence', 'companion-foods', 'companion-pattern', 'companion-cities', 'companion-context', 'companion-ratings'])
  const sources = report.source?.sources ?? []
  const privateSourceName = (name: string) => sources.find(item => item.sourceType === 'friend' && item.displayName === name)
    ? `推荐来源 ${sources.findIndex(item => item.displayName === name) + 1}` : name
  return report.sections.filter(section => !section.privacy || (report.mode === 'companion' && section.privacy === 'companion' && anonymous.has(section.id))).map(section => ({ ...section,
    metrics: section.metrics?.filter(metric => !metric.privacy), rows: section.rows?.filter(row => !row.privacy).map(row => {
      const id = section.id.replace(/^period-source-/, '')
      if (id === 'source-conclusions') return { ...row, value: row.value ? privateSourceName(row.value) : row.value }
      if (id === 'source-comparison') return { ...row, label: privateSourceName(row.label) }
      return row
    }),
  }))
}

/** Safe projection, not a second analyzer. No private notes/identity IDs enter text or pixels. */
export function analyticsReportShareData(report: AnalyticsReport, profile: TasteMapProfileDashboardViewModel): AnalysisShareData {
  if (report.scope.ownerID !== profile.user.id) throw new Error('账户已变化，请重新生成当前账户的分析')
  const sections = shareableSections(report)
  const sourceReport = report.mode === 'source' ? report.source : null
  const best = sourceReport?.sources.find(item => item.id === sourceReport.bestSourceID)
  const worst = sourceReport?.pitfallRanking[0]
  const sourceName = (item: NonNullable<typeof best>) => item.sourceType === 'friend'
    ? `推荐来源 ${sourceReport!.sources.findIndex(source => source.id === item.id) + 1}` : item.displayName
  const exportEvidence = report.topRestaurants
  const restaurants = exportEvidence.map(item => {
    const image = report.visualEvidence[item.restaurantID] ?? { source: null, photoId: null, origin: 'fallback' as const, label: item.label, restaurantId: item.restaurantID }
    return { restaurantId: item.restaurantID, name: item.label, meta: sourceReport ? item.scoreOutOfTen == null ? '首次体验未评分' : `首次体验 ${item.scoreOutOfTen.toFixed(1)} / 10` : `${item.count} 次到访`, score: item.scoreOutOfTen?.toFixed(1), image }
  })
  const summary = report.mode === 'companion' ? `共同记录：${report.summary.visitCount} 次到访，${report.summary.restaurantCount} 家餐厅。` : report.headline
  // Keep poster conclusions on the already privacy-filtered snapshot. Prioritize
  // actual comparison/outcome rows rather than repeating overview counters.
  const insightPriority = ['period-taste-change', 'annual-half-comparison', 'period-comparison', 'period-key-restaurants', 'source-conclusions', 'source-outcomes', 'companion-pattern', 'companion-ratings', 'companion-foods']
  const insightSections = sections.filter(section => !['period-overview', 'companion-evidence'].includes(section.id))
    .map((section, index) => ({ section, index, priority: insightPriority.indexOf(section.id) }))
    .sort((a, b) => (a.priority < 0 ? insightPriority.length : a.priority) - (b.priority < 0 ? insightPriority.length : b.priority) || a.index - b.index)
    .map(item => item.section)
  const data: AnalysisShareData = {
    reportId: report.id, userId: profile.user.id, type: types[report.mode], title: report.title,
    eyebrow: eyebrows[report.mode], subtitle: report.scope.periodLabel, periodLabel: report.taste?.snapshot.periodLabel ?? report.scope.periodLabel,
    summary,
    posterFindings: report.summary.visitCount ? analyticsResultHighlights(report.mode, sections).map(({ section, row }) => ({
      sectionID: section.id, title: section.title,
      text: [row.label + (row.value ? ` · ${row.value}` : ''), row.detail, row.scoreOutOfTen != null && !row.detail?.includes('/ 10') ? `评分 ${row.scoreOutOfTen.toFixed(1)} / 10` : ''].filter(Boolean).join('；'),
    })) : [],
    sourceResults: sourceReport ? { baseline: sourceReport.overallSourceRating, baselineCount: sourceReport.baselineRestaurantCount,
      best: best ? { name: sourceName(best), rate: best.highRatingRate!, count: best.ratedRestaurantCount, outcomeCount: best.highRatingCount, average: best.averageScoreOutOfTen! } : null,
      worst: worst ? { name: sourceName(worst), rate: worst.lowRatingRate!, count: worst.ratedRestaurantCount, outcomeCount: worst.lowRatingCount, average: worst.averageScoreOutOfTen! } : null } : undefined,
    metrics: (report.mode === 'companion' ? sections.find(section => section.id === 'companion-evidence')?.metrics : report.period ? sections.find(section => section.id === 'period-overview')?.metrics : undefined) ?? [
      { label: '餐厅', value: `${report.summary.restaurantCount} 家` },
      { label: '到访', value: `${report.summary.visitCount} 次` },
      { label: '有效评分', value: `${report.summary.ratedVisitCount} 次` },
      { label: '平均评分', value: report.summary.averageScoreOutOfTen?.toFixed(1) ?? '未评分' },
      { label: '城市', value: `${report.summary.cityCount} 个` },
    ],
    insights: [...(report.mode === 'taste' ? report.insights : []), ...insightSections.flatMap(section => [
      ...(section.metrics ?? []).map(metric => `${section.title} · ${metric.label}：${metric.value}${metric.note ? `（${metric.note}）` : ''}`),
      ...(section.rows ?? []).slice(0, 2).map(row => `${section.title} · ${row.label}${row.value ? `：${row.value}` : ''}`),
    ])],
    keywords: [], restaurants, heroCandidates: restaurants.map(item => item.image),
    tasteProfile: report.taste ? { ...report.taste.snapshot, spend: null, spendCategories: [], priceRanges: [], companions: [] } : undefined,
    footer: 'Taste Map · 真实记录 · 已隐藏消费与同行人姓名', logoSource: '/icons/taste-map-icon-192.png',
    privacy: { companionNameIncluded: false, spendIncluded: false, exactLocationIncluded: false },
  }
  return filterAnalysisSharePrivacy(data)
}

export function analyticsReportShareText(report: AnalyticsReport, profile: TasteMapProfileDashboardViewModel) {
  const data = analyticsReportShareData(report, profile)
  // Share the results, not the implementation's calculation commentary.
  const sections = shareableSections(report).filter(section => section.id !== 'source-pitfall-method').map(section => [
    section.title,
    ...(section.metrics ?? []).filter(metric => !metric.privacy).map(metric => `${metric.label}：${metric.value}${metric.note ? `（${metric.note}）` : ''}`),
    ...(section.rows ?? []).filter(row => !row.privacy).map(row => `${row.label}${row.value ? `：${row.value}` : ''}${row.detail ? `（${row.detail}）` : ''}${row.scoreOutOfTen != null && !row.detail?.includes('/ 10') ? ` · 评分 ${row.scoreOutOfTen.toFixed(1)} / 10` : ''}`),
    !section.metrics?.length && !section.rows?.length ? section.emptyMessage : '',
  ].filter(Boolean).join('\n'))
  const clean = filterAnalysisSharePrivacy({ ...data, insights: sections })
  return [data.title, data.subtitle, data.summary, ...clean.insights, report.dataNote, data.footer].filter(Boolean).join('\n\n')
}

/** Owner-only preview. This payload must never be passed to a download/share action.
 * The page switches to analyticsReportShareData and shows that exact safe preview
 * before enabling export. No new statistic or photo permission is introduced.
 */
export function analyticsReportOwnerPosterData(report: AnalyticsReport, profile: TasteMapProfileDashboardViewModel): AnalysisShareData {
  const safe = analyticsReportShareData(report, profile)
  return {
    ...safe,
    summary: report.headline,
    metrics: report.sections.find(section => section.id === (report.period ? 'period-overview' : 'companion-evidence'))?.metrics ?? safe.metrics,
    posterFindings: report.summary.visitCount ? analyticsResultHighlights(report.mode, report.sections).map(({ section, row }) => ({
      sectionID: section.id, title: section.title,
      text: [row.label + (row.value ? ` · ${row.value}` : ''), row.detail, row.scoreOutOfTen != null && !row.detail?.includes('/ 10') ? `评分 ${row.scoreOutOfTen.toFixed(1)} / 10` : ''].filter(Boolean).join('；'),
    })) : [],
    tasteProfile: report.taste?.snapshot,
    footer: 'Taste Map · 本人完整预览 · 分享前隐藏消费与同行信息',
    privacy: { companionNameIncluded: true, spendIncluded: true, exactLocationIncluded: false },
  }
}
