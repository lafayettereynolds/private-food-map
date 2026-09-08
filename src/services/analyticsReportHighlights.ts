import type { AnalyticsMode, AnalyticsSection } from './analyticsReportTypes'

/** One presentation priority for readable reports and their independent posters.
 * Values, sample gates and ranking remain owned by the report builder.
 */
export function analyticsResultHighlights(mode: AnalyticsMode, sections: AnalyticsSection[]) {
  const priorities: Record<AnalyticsMode, string[]> = {
    taste: ['recent-history', 'restaurant-roles', 'hidden-preferences', 'repeat', 'high-traits', 'top-restaurants'],
    companion: ['companion-foods', 'companion-pattern', 'companion-next', 'companion-memories'],
    source: ['source-conclusions', 'source-detail', 'source-outcomes', 'source-cuisines'],
    monthly: ['period-taste-change', 'period-key-restaurants', 'period-new-restaurants', 'period-restaurants'],
    annual: ['annual-half-comparison', 'period-taste-change', 'annual-highlights', 'period-key-restaurants', 'annual-journey'],
  }
  const restaurantIDs = new Set<string>()
  return priorities[mode].flatMap(id => {
    const section = sections.find(item => item.id === id)
    if (!section || section.confidence === 'insufficient') return []
    const rows = section.rows?.filter(row => row.count == null || row.count > 0) ?? []
    if (!rows.length) return []
    const row = id === 'source-conclusions' ? rows.find(item => item.id === 'best') ?? rows[0] : rows[0]
    if (row.restaurantID && restaurantIDs.has(row.restaurantID)) return []
    if (row.restaurantID) restaurantIDs.add(row.restaurantID)
    return [{ section, row }]
  }).slice(0, 3)
}
