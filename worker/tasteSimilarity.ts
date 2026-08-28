export interface TasteRatingSignal {
  userId: string
  poiId: string
  ratingOutOfTen: number
  tags: string[]
}

interface ProfileValue {
  total: number
  count: number
}

interface TasteProfile {
  pois: Map<string, ProfileValue>
  tags: Map<string, ProfileValue>
}

const MIN_SIGNAL_COUNT = 3
const MIN_SHARED_RESTAURANT_COUNT = 3
export const MIN_TASTE_SIMILARITY = 0.85

export function findSimilarTasteUserIds(signals: TasteRatingSignal[], viewerId: string) {
  return new Set(calculateTasteSimilarities(signals, viewerId).filter((item) => item.similarity >= MIN_TASTE_SIMILARITY).map((item) => item.userId))
}

export function calculateTasteSimilarities(signals: TasteRatingSignal[], viewerId: string) {
  const profiles = buildProfiles(signals)
  const viewer = profiles.get(viewerId)
  if (!viewer) return []
  const similarities: Array<{
    userId: string
    similarity: number
    signalCount: number
    sharedRestaurantCount: number
  }> = []
  profiles.forEach((profile, userId) => {
    if (userId === viewerId) return
    const comparison = compareProfiles(viewer, profile)
    if (
      comparison.signalCount >= MIN_SIGNAL_COUNT &&
      comparison.sharedRestaurantCount >= MIN_SHARED_RESTAURANT_COUNT
    ) similarities.push({ userId, ...comparison })
  })
  return similarities.sort((a, b) => b.similarity - a.similarity || a.userId.localeCompare(b.userId))
}

function buildProfiles(signals: TasteRatingSignal[]) {
  const profiles = new Map<string, TasteProfile>()
  const userMeans = new Map<string, number>()
  const byUser = new Map<string, number[]>()
  signals.forEach((signal) => byUser.set(signal.userId, [...(byUser.get(signal.userId) ?? []), signal.ratingOutOfTen]))
  byUser.forEach((ratings, userId) => userMeans.set(userId, ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length))
  signals.forEach((signal) => {
    const profile = profiles.get(signal.userId) ?? { pois: new Map(), tags: new Map() }
    const centeredRating = signal.ratingOutOfTen - (userMeans.get(signal.userId) ?? signal.ratingOutOfTen)
    addValue(profile.pois, signal.poiId, centeredRating)
    signal.tags.forEach((tag) => addValue(profile.tags, tag.trim().toLocaleLowerCase(), centeredRating))
    profiles.set(signal.userId, profile)
  })
  return profiles
}

function compareProfiles(left: TasteProfile, right: TasteProfile) {
  const differences: number[] = []
  let sharedRestaurantCount = 0
  left.pois.forEach((leftValue, key) => {
    const rightValue = right.pois.get(key)
    if (!rightValue) return
    sharedRestaurantCount += 1
    const difference = Math.min(1, Math.abs(average(leftValue) - average(rightValue)) / 5)
    differences.push(difference, difference)
  })
  left.tags.forEach((leftValue, key) => {
    const rightValue = right.tags.get(key)
    if (!rightValue) return
    differences.push(Math.min(1, Math.abs(average(leftValue) - average(rightValue)) / 5))
  })
  if (!differences.length) return { signalCount: 0, sharedRestaurantCount: 0, similarity: 0 }
  return {
    signalCount: differences.length,
    sharedRestaurantCount,
    similarity: 1 - differences.reduce((sum, value) => sum + value, 0) / differences.length,
  }
}

function addValue(target: Map<string, ProfileValue>, key: string, value: number) {
  if (!key) return
  const current = target.get(key) ?? { total: 0, count: 0 }
  current.total += value
  current.count += 1
  target.set(key, current)
}

function average(value: ProfileValue) {
  return value.total / value.count
}
