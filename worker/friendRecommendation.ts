export type FriendRecommendationReasonCode = 'mutual_friends' | 'linked_companion' | 'taste_similarity' | 'shared_restaurants' | 'same_city'
export type FriendRecommendationStrength = 'priority' | 'recommended' | 'discovery'

export interface FriendCandidateSignals {
  userId: string
  mutualFriendCount: number
  linkedCompanion: boolean
  tasteSimilarity: number | null
  tasteSignalCount: number
  sharedRestaurantCount: number
  sameCity: boolean
}

export interface RankedFriendCandidate {
  userId: string
  score: number
  strength: FriendRecommendationStrength
  primaryReason: {
    code: FriendRecommendationReasonCode
    text: string
    evidence: number | null
  }
}

const MIN_TASTE_SIGNAL_COUNT = 3
const MIN_TASTE_SIMILARITY = 0.72

export function rankFriendRecommendations(candidates: FriendCandidateSignals[]): RankedFriendCandidate[] {
  return candidates.flatMap((candidate) => {
    const reasons = candidateReasons(candidate)
    if (!reasons.length) return []
    return [{
      userId: candidate.userId,
      score: reasons.reduce((total, reason) => total + reason.weight, 0),
      strength: candidateStrength(candidate),
      primaryReason: reasons[0],
    }]
  }).sort((left, right) => right.score - left.score || left.userId.localeCompare(right.userId))
}

function candidateStrength(candidate: FriendCandidateSignals): FriendRecommendationStrength {
  if (candidate.mutualFriendCount > 0 || candidate.linkedCompanion) return 'priority'
  if (
    (candidate.tasteSignalCount >= MIN_TASTE_SIGNAL_COUNT && (candidate.tasteSimilarity ?? 0) >= MIN_TASTE_SIMILARITY)
    || candidate.sharedRestaurantCount > 0
  ) return 'recommended'
  return 'discovery'
}

function candidateReasons(candidate: FriendCandidateSignals) {
  const reasons: Array<RankedFriendCandidate['primaryReason'] & { weight: number }> = []
  if (candidate.mutualFriendCount > 0) reasons.push({
    code: 'mutual_friends',
    text: `${candidate.mutualFriendCount} 位共同好友`,
    evidence: candidate.mutualFriendCount,
    weight: 60 + Math.min(candidate.mutualFriendCount, 5) * 6,
  })
  if (candidate.linkedCompanion) reasons.push({
    code: 'linked_companion',
    text: '你曾记录过和 TA 一起吃饭',
    evidence: 1,
    weight: 58,
  })
  if (candidate.tasteSignalCount >= MIN_TASTE_SIGNAL_COUNT && (candidate.tasteSimilarity ?? 0) >= MIN_TASTE_SIMILARITY) reasons.push({
    code: 'taste_similarity',
    text: '你们口味比较接近',
    evidence: candidate.tasteSignalCount,
    weight: Math.round((candidate.tasteSimilarity ?? 0) * 45),
  })
  if (candidate.sharedRestaurantCount > 0) reasons.push({
    code: 'shared_restaurants',
    text: `都去过 ${candidate.sharedRestaurantCount} 家相同餐厅`,
    evidence: candidate.sharedRestaurantCount,
    weight: 16 + Math.min(candidate.sharedRestaurantCount, 8) * 4,
  })
  if (candidate.sameCity) reasons.push({
    code: 'same_city',
    text: '你们在同一座城市生活',
    evidence: null,
    weight: 5,
  })
  return reasons
}
