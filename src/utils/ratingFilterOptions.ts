import { DISCOVERY_MINIMUM_QUALIFIED_SCORE_OUT_OF_TEN } from '../contracts/discoveryContract'

/** Public scores use 1–10; null/unset, never zero, means no rating. */
export const RATING_FILTER_THRESHOLDS = Array.from({ length: 10 }, (_, index) => index + 1)

// Keep the existing qualified-evidence shortcut without omitting any score.
// These are viewing filters, not changes to Discovery's eligibility policy.
export const DISCOVERY_RATING_FILTER_THRESHOLDS = [...new Set([
  ...RATING_FILTER_THRESHOLDS,
  DISCOVERY_MINIMUM_QUALIFIED_SCORE_OUT_OF_TEN,
])].sort((left, right) => left - right)

export function minimumRatingFilterLabel(score: number): string {
  return score === 10 ? '10 分' : `${score} 分以上`
}
