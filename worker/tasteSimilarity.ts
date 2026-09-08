import { RECOMMENDATION_EVIDENCE_POLICY as policy, tasteEvidenceState } from '../src/contracts/recommendationEvidencePolicy'

export interface TasteRatingSignal {
  userId: string
  /** Stable restaurant identity, never a name, tag or geographic fingerprint. */
  poiId: string
  ratingOutOfTen: number
  tags: string[]
  sampleCount?: number
}
interface ProfileValue { total: number; count: number }
interface TasteProfile { pois: Map<string, ProfileValue>; mean: number }
export const MIN_TASTE_SIMILARITY = policy.forming.minimumCorrelation
export function tasteSimilarityForDisplay(evidence: { evidenceState: string; similarity: number } | undefined) {
  return evidence?.evidenceState === 'sufficient' ? evidence.similarity : null
}
export function tastePersonalEvidence(signals: TasteRatingSignal[], viewerId: string) {
  const profile = buildProfiles(signals).get(viewerId)
  const values = profile ? [...profile.pois.values()].map(average) : []
  const deviation = values.length ? Math.sqrt(mean(values.map(value => (value - profile!.mean) ** 2))) : 0
  return { personalRatedRestaurantCount: values.length, personalScoreStandardDeviationOutOfTen: deviation,
    personalEvidence: values.length >= policy.forming.minimumSharedRestaurants && deviation >= policy.minimumStandardDeviationOutOfTen ? 'eligible' as const : 'insufficient' as const }
}

export function findSimilarTasteUserIds(signals: TasteRatingSignal[], viewerId: string) {
  return new Set(calculateTasteSimilarities(signals, viewerId).filter(item => item.evidenceState !== 'insufficient').map(item => item.userId))
}
export function calculateTasteSimilarities(signals: TasteRatingSignal[], viewerId: string) {
  const profiles = buildProfiles(signals)
  const viewer = profiles.get(viewerId)
  if (!viewer) return []
  return [...profiles.entries()].flatMap(([userId, profile]) => {
    if (userId === viewerId) return []
    const shared = [...viewer.pois.keys()].filter(key => profile.pois.has(key))
    if (shared.length < policy.forming.minimumSharedRestaurants) return []
    const left = shared.map(key => average(viewer.pois.get(key)!) - viewer.mean)
    const right = shared.map(key => average(profile.pois.get(key)!) - profile.mean)
    const leftMean = mean(left); const rightMean = mean(right)
    const a = left.map(value => value - leftMean); const b = right.map(value => value - rightMean)
    const leftVariance = mean(a.map(value => value * value)); const rightVariance = mean(b.map(value => value * value))
    if (Math.sqrt(leftVariance) < policy.minimumStandardDeviationOutOfTen || Math.sqrt(rightVariance) < policy.minimumStandardDeviationOutOfTen) return []
    const similarity = Math.max(-1, Math.min(1, mean(a.map((value, index) => value * b[index])) / Math.sqrt(leftVariance * rightVariance)))
    return [{ userId, similarity, signalCount: shared.length, sharedRestaurantCount: shared.length,
      weightedSimilarity: similarity * shared.length / (shared.length + policy.similarityShrinkageRestaurants),
      evidenceState: tasteEvidenceState(shared.length, similarity), userMeanOutOfTen: profile.mean,
      viewerMeanOutOfTen: viewer.mean, sharedRestaurantIDs: shared,
    }]
  }).sort((a, b) => b.weightedSimilarity - a.weightedSimilarity || a.userId.localeCompare(b.userId))
}
function buildProfiles(signals: TasteRatingSignal[]) {
  const profiles = new Map<string, TasteProfile>()
  for (const signal of signals) {
    const count = signal.sampleCount ?? 1
    if (!signal.userId || !signal.poiId || !Number.isFinite(signal.ratingOutOfTen) || signal.ratingOutOfTen <= 0 || signal.ratingOutOfTen > 10 || !Number.isFinite(count) || count <= 0) continue
    const profile = profiles.get(signal.userId) ?? { pois: new Map<string, ProfileValue>(), mean: 0 }
    const value = profile.pois.get(signal.poiId) ?? { total: 0, count: 0 }
    value.total += signal.ratingOutOfTen * count; value.count += count
    profile.pois.set(signal.poiId, value); profiles.set(signal.userId, profile)
  }
  // Repeated Visits weight only that restaurant's representative score. Each
  // distinct restaurant then contributes once to the person's baseline.
  for (const profile of profiles.values()) profile.mean = mean([...profile.pois.values()].map(average))
  return profiles
}
function average(value: ProfileValue) { return value.total / value.count }
function mean(values: number[]) { return values.reduce((sum, value) => sum + value, 0) / values.length }
