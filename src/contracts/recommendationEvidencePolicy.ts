/** Shared initial evidence gates, on the ten-point rating scale. */
export const RECOMMENDATION_EVIDENCE_POLICY = {
  forming: { minimumSharedRestaurants: 5, minimumCorrelation: 0.5 },
  sufficient: { minimumSharedRestaurants: 10, minimumCorrelation: 0.6 },
  minimumStandardDeviationOutOfTen: 0.1,
  similarityShrinkageRestaurants: 10,
  minimumAggregateUsers: 3,
} as const
export type TasteEvidenceState = 'insufficient' | 'forming' | 'sufficient'
export function tasteEvidenceState(shared: number, correlation: number): TasteEvidenceState {
  const { forming, sufficient } = RECOMMENDATION_EVIDENCE_POLICY
  if (shared >= sufficient.minimumSharedRestaurants && correlation >= sufficient.minimumCorrelation) return 'sufficient'
  if (shared >= forming.minimumSharedRestaurants && correlation >= forming.minimumCorrelation) return 'forming'
  return 'insufficient'
}
