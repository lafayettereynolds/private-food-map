import { recommendationReasonParticipants, type RecommendationHistoryPlace, type RecommendationReasonEvidence } from './recommendationHistoryReasons'

export interface RecommendationColdStartReason {
  code: 'INITIAL_HISTORY_MATCH' | 'WANT_TO_GO_MATCH'
  text: string
  evidence: RecommendationReasonEvidence
}
const matchingTags = (candidate: string[], place: RecommendationHistoryPlace) => candidate.filter(tag =>
  tag.trim() && place.tags.some(value => value.trim().toLowerCase() === tag.trim().toLowerCase()))

/** Missing active-preference storage is not filled using popularity, hard
 * filters, a profile bio, or the rating-derived Restaurant.preferenceLevel. */
export function recommendationColdStartReasons(candidate: { canonicalID: string; tags: string[] }, history: RecommendationHistoryPlace[], wants: RecommendationHistoryPlace[]): RecommendationColdStartReason[] {
  const distinctHistory = [...new Map(history.filter(place => !!place.canonicalID).map(place => [place.canonicalID, place])).values()]
  const rated = distinctHistory.filter(place => Number.isInteger(place.ratingCount) && place.ratingCount > 0 && Number.isFinite(place.ratingSumOutOfFive) && place.ratingSumOutOfFive > 0 && place.ratingSumOutOfFive <= place.ratingCount * 5)
  if (rated.length >= 5) return []
  const related = rated.filter(place => matchingTags(candidate.tags, place).length)
  // Existing negative experience outranks an unvalidated want signal. Do not
  // cherry-pick one positive Restaurant from otherwise negative sparse data.
  if (related.length && related.reduce((sum, place) => sum + place.ratingSumOutOfFive / place.ratingCount, 0) / related.length < 3.5) return []
  const positive = rated.filter(place => place.ratingSumOutOfFive / place.ratingCount >= 3.5 && matchingTags(candidate.tags, place).length)
  if (positive.length) {
    const tags = [...new Set(positive.flatMap(place => matchingTags(candidate.tags, place)))].slice(0, 2)
    return [{ code: 'INITIAL_HISTORY_MATCH', text: `根据你已有的 ${positive.length} 家${tags.join('、')}正面评分做初步匹配，记录较少，尚未形成稳定偏好`,
      evidence: { sampleCount: positive.length, source: 'owner_history', dimensions: ['餐厅类型'], ...recommendationReasonParticipants(positive) } }]
  }
  const matching = [...new Map(wants.filter(place => place.canonicalID && place.canonicalID !== candidate.canonicalID && matchingTags(candidate.tags, place).length)
    .map(place => [place.canonicalID, place])).values()]
  if (!matching.length) return []
  const tags = [...new Set(matching.flatMap(place => matchingTags(candidate.tags, place)))].slice(0, 2)
  return [{ code: 'WANT_TO_GO_MATCH', text: `与你标记想吃的 ${matching.length} 家餐厅在${tags.join('、')}类型上接近，仅代表想吃意向，尚无评分验证`,
    evidence: { sampleCount: matching.length, source: 'owner_want_to_go', dimensions: ['餐厅类型'], ...recommendationReasonParticipants(matching) } }]
}
