/** Personal source outcomes, on the public 10-point scale. No rounding before classification. */
export const SOURCE_QUALITY_MINIMUM = 5
export const SOURCE_HIGH_SCORE = 8
export const SOURCE_PITFALL_DELTA = 1
export const sourcePitfall = (score: number | null, baseline: number | null) =>
  score != null && baseline != null && baseline - score >= SOURCE_PITFALL_DELTA - 1e-10
export const sourcePositiveRank = (highCount: number, sample: number, baselineHighRate: number) =>
  (highCount + 5 * baselineHighRate) / (sample + 5)
export function compareSourcePitfalls(a: { id: string; pitfallRate: number; firstAverage: number }, b: { id: string; pitfallRate: number; firstAverage: number }) {
  return b.pitfallRate - a.pitfallRate || a.firstAverage - b.firstAverage || a.id.localeCompare(b.id)
}
