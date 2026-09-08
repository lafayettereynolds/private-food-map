import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { AnalyticsReport } from './analyticsReport'
import { analyticsReportShareData, analyticsReportOwnerPosterData } from './analyticsReportShare'
import { buildEditorialReport } from './analysisEditorialData'
import { analyticsReportHome } from './analyticsReportHome'

/** Caller rebuilds from public Visits first. Negative named rankings NEVER enter this export. */
export function analyticsMemoryShareData(report: AnalyticsReport, profile: TasteMapProfileDashboardViewModel, audience: 'owner' | 'share' = 'share') {
  const data = audience === 'owner' ? analyticsReportOwnerPosterData(report, profile) : analyticsReportShareData(report, profile)
  const editorial = buildEditorialReport(report, profile, audience)
  const home = analyticsReportHome(report)
  if (report.mode === 'source') {
    const best = home.sourceLeaders[0]
    const restaurants = (best?.restaurants.filter(item => item.scoreOutOfTen != null && item.scoreOutOfTen >= 8) ?? []).slice(0, 3).map(item => ({ restaurantId: item.restaurantID, name: item.label, meta: '首次体验', score: item.scoreOutOfTen?.toFixed(1), image: report.visualEvidence[item.restaurantID] ?? { source: null, photoId: null, origin: 'fallback' as const, label: item.label } }))
    return { ...data, memoryCard: false, editorial, sourceResults: undefined, summary: best ? `一个推荐来源，带来了 ${best.highRatingCount} 家高分餐厅。` : '记录仍在积累，暂不生成来源冠军。', metrics: best ? [{ label: '首次已评分', value: `${best.ratedRestaurantCount} 家` }, { label: '高分餐厅', value: `${best.highRatingCount} 家` }, { label: '高分占比', value: `${Number(((best.highRatingRate ?? 0) * 100).toFixed(1))}%` }] : [], insights: [], posterFindings: [], restaurants, heroCandidates: restaurants.map(item => item.image), footer: audience === 'owner' ? 'Taste Map · 本人完整预览 · 仅代表你的体验' : 'Taste Map · 仅公开记录 · 来源匿名 · 不导出负向榜' }
  }
  return { ...data, memoryCard: false, editorial, summary: audience === 'share' && report.mode === 'companion' ? data.summary : home.headline, metrics: home.facts.slice(0, 4), insights: [], posterFindings: [], sourceResults: undefined, footer: audience === 'owner' ? 'Taste Map · 本人完整预览 · 来自真实用餐记录' : 'Taste Map · 仅公开记录 · 已隐藏金额、同行姓名与备注' }
}
