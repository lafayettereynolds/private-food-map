import { describe, expect, it } from 'vitest'
import { renderToStaticMarkup } from 'react-dom/server'
import { AnalyticsReportDataView } from './AnalyticsReportDataView'
import type { AnalyticsMode, AnalyticsReportSummary } from '../services/analyticsReportTypes'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'

describe('analysis starts with one story, not an expanded database report', () => {
  it.each<AnalyticsMode>(['taste', 'companion', 'source', 'monthly', 'annual'])('%s keeps detailed results behind the complete analysis entry', mode => {
    const html = renderToStaticMarkup(<AnalyticsReportDataView
      mode={mode} title="报告" headline="你留下了真实用餐记录" period="本月"
      summary={{ visitCount: 10, restaurantCount: 6, ratedVisitCount: 8, averageScoreOutOfTen: 8 } as AnalyticsReportSummary}
      sections={[
        { id: 'result', title: '常去餐厅', description: '内部计算方法与分母', rows: [{ id: 'r', label: '小满食堂', value: '3 次' }] },
        { id: 'source-pitfall-method', title: '计算依据', rows: [{ id: 'internal', label: '内部基线' }] },
      ]}
      evidence={[]} profile={{ restaurants: [] } as unknown as TasteMapProfileDashboardViewModel}
      onOpenRestaurant={() => {}}
    />)
    expect(html).toContain('你留下了真实用餐记录')
    expect(html).toContain('查看完整分析')
    expect(html).toContain('data-analysis-view="home"')
    expect(html).not.toContain('小满食堂')
    expect(html).not.toContain('data-analysis-section=')
    expect(html).not.toMatch(/<details|<summary|计算依据|内部基线|内部计算方法|为什么得出这个结果/)
  })
})
