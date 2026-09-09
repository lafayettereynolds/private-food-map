/** Historical weighted rating estimate, NOT a calibrated liking probability.
 * The caller must supply only the authenticated owner's authorized history.
 * Shared by the existing detail estimate and server Discovery before pagination.
 */
export interface LikingRestaurantEvidence {
  id: string
  tags: readonly string[]
  city?: string
  price: number | null
  scoreOutOfTen?: number | null
  visitCount?: number
  ratedVisitCount?: number
}
export interface PredictedLiking {
  scoreOutOfTen: number | null
  ratedRestaurantCount: number
  ratedVisitCount: number
  matchedRestaurantCount: number
  method: 'owner_history_weighted_rating_v1'
}
export function predictLiking(target: LikingRestaurantEvidence, history: readonly LikingRestaurantEvidence[]): PredictedLiking {
  const tags = (values: readonly string[]) => new Set(values.map(value => value.trim().toLocaleLowerCase('zh-CN')).filter(Boolean))
  const targetTags = tags(target.tags)
  const finite = (value: number | null | undefined): value is number => typeof value === 'number' && Number.isFinite(value)
  const weighted = history.filter(item => item.id !== target.id && finite(item.scoreOutOfTen) && item.scoreOutOfTen >= 0 && item.scoreOutOfTen <= 10).map(item => {
    const itemTags = tags(item.tags)
    const tagSimilarity = targetTags.size && itemTags.size
      ? [...targetTags].filter(tag => itemTags.has(tag)).length / new Set([...targetTags, ...itemTags]).size : 0
    const priceSimilarity = finite(target.price) && finite(item.price)
      ? Math.max(0, 1 - Math.abs(target.price - item.price) / Math.max(160, target.price, item.price)) : 0
    const sameCity = Boolean(target.city && target.city === item.city)
    return { score: item.scoreOutOfTen!, isMatch: tagSimilarity > 0 || priceSimilarity >= 0.65 || sameCity,
      weight: 0.35 + tagSimilarity * 1.2 + priceSimilarity * 0.3 + (sameCity ? 0.15 : 0) + Math.min(Math.max(0, item.visitCount ?? 0), 4) * 0.04,
      ratedVisits: Math.max(0, item.ratedVisitCount ?? 0) }
  })
  const strongest = weighted.filter(item => item.isMatch)
  const samples = strongest.length ? strongest : weighted
  const weight = samples.reduce((sum, item) => sum + item.weight, 0)
  return { scoreOutOfTen: weight ? Math.round(Math.min(10, Math.max(1, samples.reduce((sum, item) => sum + item.score * item.weight, 0) / weight)) * 10) / 10 : null,
    ratedRestaurantCount: samples.length, ratedVisitCount: samples.reduce((sum, item) => sum + item.ratedVisits, 0),
    matchedRestaurantCount: strongest.length, method: 'owner_history_weighted_rating_v1' }
}
