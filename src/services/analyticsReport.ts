import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { analyticsDataset, analyticsSummary, analyticsRestaurantRanking } from './analyticsReportData'
import { buildAnalyticsTasteReport } from './analyticsTasteReport'
import { buildAnalyticsPeriodReport, analyticsVisitDateLabel } from './analyticsPeriodReport'
import { buildAnalyticsCompanionReport, buildAnalyticsSourceReport, type AnalyticsSocialReportOptions } from './analyticsSocialReport'
import type { AnalyticsMode, AnalyticsSection } from './analyticsReportTypes'
import { analyticsReportVisuals } from './analyticsReportVisuals'
import { analyticsFilterVisits, type AnalyticsExploreFilter } from './analyticsExploreQuery'

export interface AnalyticsReportOptions extends AnalyticsSocialReportOptions {
  mode: AnalyticsMode
  year?: number
  month?: number
  companionID?: string
  sourceID?: string
  filter?: AnalyticsExploreFilter
  excludePrivate?: boolean
}

/** One immutable-in-use, owner/period scoped source for both data and poster.
 * Renderers must project from this result, not recalculate from Profile rows.
 */
export function buildAnalyticsReport(profile: TasteMapProfileDashboardViewModel, options: AnalyticsReportOptions) {
  const now = options.now ?? new Date()
  const year = options.year ?? now.getFullYear()
  const month = options.month ?? now.getMonth() + 1
  const original = analyticsDataset(profile, now)
  const dataset = { ...original, visits: analyticsFilterVisits(original.restaurants, original.visits, options.filter ?? {}, now).filter(visit => !options.excludePrivate || visit.visibility === 'public') }
  const taste = options.mode === 'taste' ? buildAnalyticsTasteReport(dataset.restaurants, dataset.visits, now) : null
  const period = options.mode === 'monthly' || options.mode === 'annual' ? buildAnalyticsPeriodReport(dataset.restaurants, dataset.visits, options.mode, year, month, now) : null
  const socialOptions = { ...options, now,
    selectedCompanionID: options.companionID ?? options.selectedCompanionID,
    selectedSourceID: options.sourceID ?? options.selectedSourceID,
    visitIDs: (period?.visits ?? dataset.visits).map(visit => visit.id) }
  const companion = options.mode === 'companion' || options.mode === 'taste' || period ? buildAnalyticsCompanionReport(profile, socialOptions) : null
  const source = options.mode === 'source' || options.mode === 'taste' || period ? buildAnalyticsSourceReport(profile, socialOptions) : null
  const selected = taste ?? period ?? (options.mode === 'companion' ? companion : source)
  const summary = selected?.summary ?? analyticsSummary([], [])
  const evidenceVisitIDs = new Set(period ? period.visits.map(visit => visit.id) : options.mode === 'companion' ? companion?.visitIDs ?? [] : options.mode === 'source' ? source?.visitIDs ?? [] : dataset.visits.map(visit => visit.id))
  const visualEvidence = analyticsReportVisuals(profile, dataset.restaurants, dataset.visits.filter(visit => evidenceVisitIDs.has(visit.id)))
  const titles: Record<AnalyticsMode, string> = { taste: '我的口味档案', companion: '最佳饭搭子', source: '谁最会种草', monthly: year === now.getFullYear() && month === now.getMonth() + 1 ? '本月回顾' : '月度回顾', annual: '年度回顾' }
  const sections: AnalyticsSection[] = [...(selected?.sections ?? [])]
  if (period) {
    sections.push(...(companion?.sections ?? []).map((section) => ({ ...section, id: `period-companion-${section.id}` })))
    sections.push(...(source?.sections ?? []).map((section) => ({ ...section, id: `period-source-${section.id}` })))
  }
  const revision = reportFingerprint(JSON.stringify({
    restaurants: profile.restaurants.map((item) => [item.id, item.updatedAt, item.deletedAt]).sort(),
    visits: profile.visits.map((item) => [item.id, item.updatedAt, item.deletedAt]).sort(),
    identity: profile.analyticsIdentity, companions: options.companions, sources: options.sources, links: options.visitSourceLinks,
    companion: socialOptions.selectedCompanionID, source: socialOptions.selectedSourceID,
    // Derived projections also change when a bridge refresh corrects fields or
    // image capabilities without bumping the legacy row revision timestamp.
    summary, sections, visualEvidence, filter: options.filter, excludePrivate: options.excludePrivate,
    day: `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`,
  }))
  const dataState = dataset.unavailableVisitCount > 0 && dataset.visits.length === 0 ? 'unavailable' as const : summary.visitCount ? 'ready' as const : 'empty' as const
  return {
    version: 1 as const,
    id: `${dataset.ownerID}:${options.mode}:${period ? `${year}-${options.mode === 'monthly' ? month : 'year'}` : 'all'}:${revision}`,
    mode: options.mode,
    title: titles[options.mode],
    scope: { ownerID: dataset.ownerID, year: period ? year : null, month: options.mode === 'monthly' ? month : null,
      start: period?.start.toISOString() ?? null, endExclusive: period?.end.toISOString() ?? null,
      periodLabel: period?.periodLabel ?? [options.filter?.days ? `最近 ${options.filter.days} 天` : '全部历史', options.filter?.city || '全部城市'].join(' · '), timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone },
    generatedAt: now.toISOString(),
    summary,
    visualEvidence,
    calculationVisits: period?.visits ?? dataset.visits,
    comparisonVisits: period ? dataset.visits.filter(visit => Date.parse(visit.visitedAt) >= period.comparison.window.previousStart.getTime() && Date.parse(visit.visitedAt) < period.comparison.window.previousEnd.getTime()) : [],
    sourceBaselineVisits: original.visits.filter(visit => source?.sections.find(section => section.id === 'source-pitfall-method')?.rows?.some(row => row.id === visit.id)),
    scopedVisits: dataset.visits.filter(visit => evidenceVisitIDs.has(visit.id)),
    scopedRestaurants: dataset.restaurants,
    firstVisitIDs: dataset.visits.filter(visit => original.visits.find(item => item.restaurantId === visit.restaurantId)?.id === visit.id).map(visit => visit.id),
    dataState,
    headline: dataState === 'unavailable' ? '当前记录尚无法用于个人分析' : selected?.headline ?? '记录正在积累',
    insights: selected?.insights ?? [],
    sections,
    topRestaurants: selected?.topRestaurants ?? [],
    evidenceRestaurants: analyticsRestaurantRanking(dataset.restaurants, dataset.visits.filter(visit => evidenceVisitIDs.has(visit.id))),
    recordEvidence: dataset.visits.filter(visit => evidenceVisitIDs.has(visit.id)).slice().reverse().map(visit => ({
      id: visit.id, restaurantID: visit.restaurantId,
      label: dataset.restaurants.find(item => item.id === visit.restaurantId)?.name ?? '餐厅',
      value: analyticsVisitDateLabel(visit.visitedAt), scoreOutOfTen: visit.rating == null ? null : visit.rating * 2,
      detail: visit.note || undefined,
    })),
    taste,
    period,
    companion,
    source,
    excludedVisitCount: dataset.excludedVisitCount,
    dataNote: `${dataState === 'unavailable' ? '现有记录缺少可核验归属、有效日期或可用餐厅关联；不是从未记录过。' : ''}仅分析当前用户可用的个人记录，包含尚未同步的本机记录；未评分和未记录消费不填零。到访时间按当前设备时区解释。`,
  }
}

export type AnalyticsReport = ReturnType<typeof buildAnalyticsReport>

/** Non-security cache identity, never a score or probability. */
function reportFingerprint(value: string) {
  let hash = 2166136261
  for (let index = 0; index < value.length; index += 1) hash = Math.imul(hash ^ value.charCodeAt(index), 16777619)
  return (hash >>> 0).toString(16)
}
