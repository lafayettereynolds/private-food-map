import type { Visit } from '../types/domain'
import { analyticsAverage, analyticsRatings } from './analyticsReportData'

export const ANALYTICS_EVIDENCE_RULES = {
  comparisonRatedRestaurants: 5,
  frequencyVisits: 10,
  frequencyRestaurants: 5,
  frequencyChange: .15,
  ratingChangeOutOfTen: 1,
  companionVisits: 3,
  companionRestaurants: 2,
  companionComparisonVisits: 8,
  companionComparisonRestaurants: 4,
  spendComparisonCoverage: .8,
} as const

/** Repeated meals refine one restaurant's score, never give it more votes. */
export function analyticsRepresentativeRatings(visits: Visit[]) {
  const groups = new Map<string, Visit[]>()
  for (const visit of visits) groups.set(visit.restaurantId, [...(groups.get(visit.restaurantId) ?? []), visit])
  return [...groups].flatMap(([restaurantID, values]) => {
    const scoreOutOfTen = analyticsAverage(analyticsRatings(values))
    return scoreOutOfTen == null ? [] : [{ restaurantID, scoreOutOfTen }]
  })
}
export function analyticsFrequencyEvidence(visits: Visit[]) {
  return visits.length >= ANALYTICS_EVIDENCE_RULES.frequencyVisits
    && new Set(visits.map(visit => visit.restaurantId)).size >= ANALYTICS_EVIDENCE_RULES.frequencyRestaurants
}

/** Calendar-aligned comparison; the displayed current total still includes all
 * records up to now, even when a shorter previous month limits comparison. */
export function analyticsComparableWindow(mode: 'monthly' | 'annual', year: number, month: number, now: Date) {
  const start = new Date(year, mode === 'monthly' ? month - 1 : 0, 1)
  const end = new Date(year + (mode === 'annual' ? 1 : 0), mode === 'monthly' ? month : 0, 1)
  const previousStart = new Date(mode === 'annual' ? year - 1 : year, mode === 'monthly' ? month - 2 : 0, 1)
  const isCurrent = now >= start && now < end
  let currentEnd = end
  let previousEnd = start
  if (isCurrent) {
    const targetMonth = mode === 'monthly' ? previousStart.getMonth() : now.getMonth()
    const targetYear = previousStart.getFullYear()
    const previousDays = new Date(targetYear, targetMonth + 1, 0).getDate()
    const day = Math.min(now.getDate(), previousDays)
    // Include today's date, but never a future Visit in the actual dataset.
    currentEnd = new Date(year, now.getMonth(), day + 1)
    previousEnd = new Date(targetYear, targetMonth, day + 1)
  }
  return { isCurrent, start, end, previousStart, currentEnd, previousEnd,
    asOf: isCurrent ? new Date(now) : null }
}
