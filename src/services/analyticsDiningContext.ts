import type { Visit } from '../types/domain'

/** Missing time is not midnight; contradictory context is not a social fact. */
export const analyticsHasMealTime = (visit: Visit) => /[T ]\d{2}:\d{2}/.test(visit.visitedAt)
export function analyticsDiningContext(visit: Visit): 'solo' | 'together' | 'conflict' | 'unknown' {
  const linked = visit.companionIds.some(id => id.trim()) || visit.companions.some(name => name.trim())
  const solo = visit.diningOccasions.includes('solo')
  const social = visit.diningOccasions.some(value => ['friends', 'date', 'family', 'business', 'celebration'].includes(value))
  if (solo && (linked || social)) return 'conflict'
  return solo ? 'solo' : linked || social ? 'together' : 'unknown'
}
