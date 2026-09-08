import type { AnalyticsReport } from './analyticsReport'
import type { AnalyticsRow, AnalyticsSection } from './analyticsReportTypes'
import { analyticsResultHighlights } from './analyticsReportHighlights'

/** A bounded reading projection of the SAME report used by data and poster. */
export function analyticsReportHome(report: AnalyticsReport) {
  const { mode, summary, taste, period, companion, source } = report
  const person = companion?.companions.find(item => item.id === companion.selectedCompanionID)
  const sourceLeaders = (source?.sources ?? []).filter(item => item.eligible && item.highRatingCount > 0)
    .sort((a, b) => b.reliabilityScore! - a.reliabilityScore! || b.ratedRestaurantCount - a.ratedRestaurantCount || Date.parse(b.latestUsageAt ?? '') - Date.parse(a.latestUsageAt ?? '') || a.id.localeCompare(b.id)).slice(0, 3)
  const leader = sourceLeaders[0]
  let headline = report.headline
  let subtitle = `基于 ${summary.visitCount} 次用餐记录 · ${summary.restaurantCount} 家餐厅`
  const facts: { label: string; value: string }[] = []
  const fact = (label: string, value: number) => facts.push({ label, value: String(value) })
  if (period && summary.visitCount) {
    const firstCount = period.newRestaurants.length
    if (mode === 'monthly') {
      headline = firstCount ? `这个月，首次记录了 ${firstCount} 家餐厅。` : `这个月，又回到了熟悉的餐厅。`
    } else {
      const active = period.monthlySnapshots.filter(item => item.visitCount).map(item => item.month)
      headline = `这一年，在 ${summary.restaurantCount} 家餐厅留下了用餐记忆。`
      subtitle = `${report.scope.year} 年 · 记录覆盖 ${active.length} 个月${active.length ? `（${active[0]}—${active[active.length - 1]} 月）` : ''}`
    }
    fact('用餐记录', summary.visitCount); fact('不同餐厅', summary.restaurantCount)
    if (mode === 'annual') fact('城市', summary.cityCount)
    fact('首次记录餐厅', firstCount)
    if (mode === 'monthly') fact('回访次数', summary.visitCount - firstCount)
  } else if (mode === 'companion' && person && person.sharedVisitCount > 0) {
    headline = `和${person.displayName}，一起吃过 ${person.sharedVisitCount} 顿饭。`
    subtitle = person.ratingAverage == null ? '这里记录共同经历，不衡量关系亲疏。' : `你给这些共同用餐的平均分 ${person.ratingAverage.toFixed(1)} / 10 · ${person.ratedVisitCount} 次评分`
    fact('共同用餐', person.sharedVisitCount); fact('不同餐厅', person.restaurantCount)
    fact('首次探索时同行', person.firstTogetherRestaurantCount); fact('共同回访次数', person.repeatVisitCount)
  } else if (mode === 'source') {
    headline = leader ? `${leader.displayName}带来的推荐，更符合你已记录的体验。` : '推荐结果还在积累，先不选出冠军。'
    subtitle = '按已验证体验比较；不是人气榜，也不是一次高分定胜负。'
  }
  const top = report.topRestaurants[0]
  const finding = analyticsResultHighlights(mode, report.sections)[0]
  let feature: { title: string; row: AnalyticsRow; sectionID: string } | null = finding ? { title: finding.section.title, row: finding.row, sectionID: finding.section.id } : null
  if (period && top) feature = { title: mode === 'annual' ? top.count > 1 ? '年度最常回去' : '年度记忆餐厅' : '本月值得记住的餐厅', row: { ...top, detail: `${period.periodLabel}记录了 ${top.count} 次用餐${top.scoreOutOfTen == null ? '' : ` · 你给的平均分 ${top.scoreOutOfTen.toFixed(1)} / 10`}` }, sectionID: 'period-restaurants' }
  if (mode === 'source') {
    const restaurant = leader?.restaurants.filter(item => (item.scoreOutOfTen ?? -1) >= 8).sort((a, b) => b.scoreOutOfTen! - a.scoreOutOfTen! || a.id.localeCompare(b.id))[0]
    feature = restaurant ? { title: '这个来源带来的高分餐厅', row: { ...restaurant, detail: `来自${leader!.displayName} · 你的首次体验 ${restaurant.scoreOutOfTen!.toFixed(1)} / 10` }, sectionID: 'source-detail' } : null
  }
  const habits: { kind: 'time' | 'price' | 'companion' | 'city'; label: string; value: string; sectionID: string }[] = []
  if (taste) {
    const highest = (values: { label: string; value: number }[]) => [...values].filter(item => item.value > 0).sort((a, b) => b.value - a.value)[0]
    const time = highest(taste.snapshot.diningTimes), price = highest(taste.snapshot.priceRanges)
    const context = highest(taste.snapshot.companions.filter(item => !['未记录', '场景冲突待确认'].includes(item.label))), city = highest(taste.snapshot.cities)
    if (time) habits.push({ kind: 'time', label: '常见时段', value: time.label, sectionID: 'dining-times' })
    if (price) habits.push({ kind: 'price', label: '常见参考价位', value: price.label, sectionID: 'reference-price' })
    if (context) habits.push({ kind: 'companion', label: '常见同行场景', value: context.label, sectionID: 'companion-context' })
    if (city) habits.push({ kind: 'city', label: '主要城市', value: city.label, sectionID: 'cities' })
  }
  const memories = person?.restaurants.slice(0, 3) ?? []
  return { headline, subtitle, facts, feature, habits, sourceLeaders, memories, person,
    frequent: taste?.frequent ?? [], highlyRated: taste?.highlyRated ?? [],
    cta: mode === 'monthly' ? '查看本月完整回顾' : mode === 'annual' ? '查看完整年鉴' : mode === 'companion' ? '查看完整共同回忆' : '查看完整分析' }
}

/** Every section appears once; details expose one theme/section at a time. */
export function analyticsDetailTopics(sections: AnalyticsSection[]) {
  const definitions = [
    { id: 'preference', title: '偏好与发现', pattern: /cuisine|taste|dish|trait|pitfall|hidden|recent-history|half-comparison/ },
    { id: 'spend', title: '消费与价位', pattern: /spend|price/ },
    { id: 'time', title: '时间与变化', pattern: /time|month|journey|comparison|highlight/ },
    { id: 'places', title: '餐厅与足迹', pattern: /restaurant|cit|repeat|memor/ },
    { id: 'people', title: '饭搭子与来源', pattern: /companion|source|scene|context/ },
    { id: 'ratings', title: '评分与样本', pattern: /rating|overview|evidence/ },
  ]
  const topics = definitions.map(({ id, title }) => ({ id, title, sections: [] as AnalyticsSection[] }))
  for (const section of sections) {
    // Social-specific sections remain with their person/source, not a taste duplicate.
    const index = /companion|source/.test(section.id) ? 4 : definitions.findIndex(item => item.pattern.test(section.id))
    topics[index < 0 ? 0 : index].sections.push(section)
  }
  return topics.filter(topic => topic.sections.length)
}
