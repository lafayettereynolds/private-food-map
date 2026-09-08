/** One current-owner canonical Restaurant, never raw Visit or visibility rows.
 * Missing provenance never becomes positive evidence. */
export interface RecommendationHistoryPlace {
  canonicalID?: string
  /** Owner-scoped representative records only, not a complete Visit list. */
  representativeVisitIDs?: string[]
  ownerRestaurantIDs?: string[]
  name?: string
  tags: string[]
  ratingCount: number
  ratingSumOutOfFive: number
  /** One actual owner rating, never a mean presented as a rating they gave. */
  referenceRatingOutOfFive?: number | null
  visitCount: number
  pricePerPerson: number | null
  priceReliable?: boolean
  priceCurrency?: string | null
  firstVisitedAt?: string | null
  lastVisitedAt?: string | null
  verifiedDimensions?: Partial<Record<'dish' | 'flavor' | 'cooking' | 'setting', string[]>>
}
export interface RecommendationCandidateEvidence {
  tags: string[]
  pricePerPerson: number | null
  priceReliable?: boolean
  priceCurrency?: string | null
  verifiedDimensions?: RecommendationHistoryPlace['verifiedDimensions']
  explorationEligible?: boolean
}
export interface RecommendationHistoryReason {
  code: 'TASTE_TAG_MATCH' | 'HIGH_CUISINE_MATCH' | 'REPEAT_VISIT_PATTERN' | 'PRICE_RANGE_MATCH' | 'SHORT_TERM_DIVERSITY'
  text: string
  evidence: RecommendationReasonEvidence
}
export interface RecommendationReasonParticipant {
  restaurantID: string
  restaurantName: string | null
  restaurantRecordIDs: string[]
  visitIDs: string[]
  fields: { tags: string[]; ratingCount: number; meanOutOfTen: number | null; referenceRatingOutOfTen: number | null; visitCount: number; firstVisitedAt: string | null; lastVisitedAt: string | null; recordedPricePerPerson: number | null; priceCurrency: string | null }
}
export interface RecommendationReasonEvidence {
  sampleCount: number
  referenceRestaurantID?: string
  dimensions?: string[]
  meanOutOfTen?: number
  windowDays?: number
  source?: 'owner_history' | 'owner_want_to_go' | 'explicit_preference'
  participants?: RecommendationReasonParticipant[]
  participantCount?: number
  participantsTruncated?: boolean
  missingFields?: string[]
}

/** Only the authenticated owner's records may be passed here. A preview
 * exposes real IDs and sufficient statistics, never invented Visit rows. */
export function recommendationReasonParticipants(history: RecommendationHistoryPlace[]): Pick<RecommendationReasonEvidence, 'participants' | 'participantCount' | 'participantsTruncated' | 'missingFields'> {
  const places = distinct(history)
  const identifiable = places.filter(place => !!place.canonicalID)
  return {
    participants: identifiable.slice(0, 20).map(place => ({ restaurantID: place.canonicalID!, restaurantName: place.name ?? null,
      restaurantRecordIDs: [...new Set(place.ownerRestaurantIDs ?? [])],
      visitIDs: [...new Set(place.representativeVisitIDs ?? [])], fields: {
        tags: place.tags, ratingCount: place.ratingCount, meanOutOfTen: rated(place) ? mean(place) * 2 : null,
        referenceRatingOutOfTen: place.referenceRatingOutOfFive != null && place.referenceRatingOutOfFive > 0 && place.referenceRatingOutOfFive <= 5 ? place.referenceRatingOutOfFive * 2 : null,
        visitCount: place.visitCount, firstVisitedAt: place.firstVisitedAt ?? null, lastVisitedAt: place.lastVisitedAt ?? null,
        recordedPricePerPerson: place.priceReliable === true ? place.pricePerPerson : null, priceCurrency: place.priceCurrency ?? null,
      } })),
    participantCount: places.length, participantsTruncated: identifiable.length > 20,
    missingFields: [...(places.some(place => !place.canonicalID) ? ['restaurant_identity'] : []),
      ...(places.some(place => !place.ownerRestaurantIDs?.length) ? ['restaurant_record_ids'] : []),
      ...(places.some(place => place.priceReliable && !place.priceCurrency) ? ['price_currency'] : []),
      ...(places.some(place => place.visitCount > new Set(place.representativeVisitIDs ?? []).size) ? ['complete_visit_list'] : [])],
  }
}
export const FOR_YOU_REASON_POLICY = {
  maximumReasons: 3, highRatingOutOfFive: 4, positiveMeanOutOfFive: 3.5,
  minimumCategoryRestaurants: 5, minimumRepeatCategoryRestaurants: 3,
  minimumCrossDateRepeatedRestaurants: 2, minimumPriceRestaurants: 5,
  minimumReferenceDimensions: 2, explorationWindowDays: 365, maximumExplorationCategoryRestaurants: 1,
} as const
const normalize = (value: string) => value.trim().toLocaleLowerCase()
const matches = (a: string[] = [], b: string[] = []) => a.some(value => normalize(value) && b.some(other => normalize(value) === normalize(other)))
const mean = (p: RecommendationHistoryPlace) => p.ratingSumOutOfFive / p.ratingCount
const rated = (p: RecommendationHistoryPlace) => Number.isInteger(p.ratingCount) && p.ratingCount > 0 && Number.isFinite(p.ratingSumOutOfFive) && p.ratingSumOutOfFive > 0 && p.ratingSumOutOfFive <= p.ratingCount * 5
const priced = (p: Pick<RecommendationCandidateEvidence, 'priceReliable' | 'pricePerPerson' | 'priceCurrency'>) => p.priceReliable === true && p.pricePerPerson != null && Number.isFinite(p.pricePerPerson) && p.pricePerPerson > 0 && typeof p.priceCurrency === 'string' && /^[A-Z]{3}$/.test(p.priceCurrency)
const distinct = (history: RecommendationHistoryPlace[]) => history.filter((p, i) => !p.canonicalID || history.findIndex(other => other.canonicalID === p.canonicalID) === i)
const date = (value: string | null | undefined) => value ? Date.parse(value) : NaN

export function recommendationHistoryReference(candidate: RecommendationCandidateEvidence, history: RecommendationHistoryPlace[]) {
  return distinct(history).flatMap(place => {
    if (!rated(place) || mean(place) < FOR_YOU_REASON_POLICY.highRatingOutOfFive || !place.name?.trim() || place.referenceRatingOutOfFive == null || !Number.isFinite(place.referenceRatingOutOfFive) || place.referenceRatingOutOfFive < 4 || place.referenceRatingOutOfFive > 5) return []
    const dimensions: string[] = []
    // Multiple matching category tags are still ONE dimension.
    if (matches(candidate.tags, place.tags)) dimensions.push('餐厅类型')
    for (const [key, label] of [['dish', '菜品'], ['flavor', '风味'], ['cooking', '烹饪方式'], ['setting', '用餐环境']] as const) {
      if (matches(candidate.verifiedDimensions?.[key], place.verifiedDimensions?.[key])) dimensions.push(label)
    }
    if (priced(candidate) && priced(place) && candidate.priceCurrency === place.priceCurrency && Math.abs(candidate.pricePerPerson! - place.pricePerPerson!) / Math.max(candidate.pricePerPerson!, place.pricePerPerson!) <= .2) dimensions.push('人均消费')
    return dimensions.length >= 2 ? [{ place, dimensions, ratingOutOfTen: place.referenceRatingOutOfFive * 2 }] : []
  }).sort((a, b) => b.dimensions.length - a.dimensions.length || b.ratingOutOfTen - a.ratingOutOfTen || (a.place.canonicalID ?? a.place.name!).localeCompare(b.place.canonicalID ?? b.place.name!))[0] ?? null
}

/** At most three distinct statements; never pad an incomplete explanation. */
export function recommendationHistoryReasons(candidate: RecommendationCandidateEvidence, history: RecommendationHistoryPlace[], options: { now?: number } = {}): RecommendationHistoryReason[] {
  const places = distinct(history), valid = places.filter(rated), related = valid.filter(p => matches(candidate.tags, p.tags))
  const label = [...new Map(candidate.tags.filter(tag => related.some(p => matches([tag], p.tags))).map(tag => [normalize(tag), tag.trim()])).values()].slice(0, 2).join('、')
  const reasons: RecommendationHistoryReason[] = [], now = options.now
  // Unknown/future latest dates cannot establish a last-year absence.
  if (candidate.explorationEligible === true && now != null && Number.isFinite(now) && places.length && places.every(p => Number.isFinite(date(p.lastVisitedAt)) && date(p.lastVisitedAt) <= now)) {
    const recent = places.filter(p => now - date(p.lastVisitedAt) <= 365 * 86_400_000)
    const count = recent.filter(p => matches(candidate.tags, p.tags)).length
    if (candidate.tags.some(tag => normalize(tag)) && recent.length >= 5 && count <= 1) {
      // Exploration is not a validated preference; do not combine it with favorite/repeat claims.
      return [{ code: 'SHORT_TERM_DIVERSITY', text: '过去一年你记录过的这类餐厅较少，可作为一次新口味探索', evidence: { sampleCount: count, windowDays: 365,
        source: 'owner_history', ...recommendationReasonParticipants(recent) } }]
    }
  }
  const reference = recommendationHistoryReference(candidate, valid)
  if (reference) reasons.push({ code: 'TASTE_TAG_MATCH', text: `与你给过${Number(reference.ratingOutOfTen.toFixed(1))}分的「${reference.place.name}」在${reference.dimensions.join('、')}上接近`, evidence: { sampleCount: 1, referenceRestaurantID: reference.place.canonicalID, dimensions: reference.dimensions,
    source: 'owner_history', ...recommendationReasonParticipants([reference.place]) } })
  const average = related.length ? related.reduce((sum, p) => sum + mean(p), 0) / related.length : 0
  if (related.length >= 5 && average >= 3.5) reasons.push({ code: 'HIGH_CUISINE_MATCH', text: `你过去 ${related.length} 家${label}相关餐厅的平均评分为 ${(average * 2).toFixed(1)}/10`, evidence: { sampleCount: related.length, meanOutOfTen: average * 2,
    source: 'owner_history', ...recommendationReasonParticipants(related) } })
  const repeated = related.filter(p => p.visitCount >= 2 && mean(p) >= 3.5 && Number.isFinite(date(p.firstVisitedAt)) && Number.isFinite(date(p.lastVisitedAt)) && date(p.firstVisitedAt) < date(p.lastVisitedAt) && p.firstVisitedAt!.slice(0, 10) !== p.lastVisitedAt!.slice(0, 10) && (now == null || date(p.lastVisitedAt) <= now))
  if (related.length >= 3 && average >= 3.5 && repeated.length >= 2) reasons.push({ code: 'REPEAT_VISIT_PATTERN', text: `${label}是你会重复到访的类型，${repeated.length} 家同类餐厅曾在不同日期再次到访`, evidence: { sampleCount: repeated.length,
    source: 'owner_history', ...recommendationReasonParticipants(repeated) } })
  const comparablePrices = valid.filter(p => mean(p) >= 4 && priced(p) && p.priceCurrency === candidate.priceCurrency)
  const prices = comparablePrices.map(p => p.pricePerPerson!).sort((a, b) => a - b)
  if (prices.length >= 5 && priced(candidate)) {
    const low = prices[Math.floor((prices.length - 1) * .2)], high = prices[Math.ceil((prices.length - 1) * .8)]
    if (candidate.pricePerPerson! >= low && candidate.pricePerPerson! <= high) {
      const format = (value: number) => Number(value.toFixed(2)).toString()
      reasons.push({ code: 'PRICE_RANGE_MATCH', text: `这家人均约 ${candidate.priceCurrency} ${format(candidate.pricePerPerson!)}，落在你 ${prices.length} 家高分餐厅实录人均的 ${candidate.priceCurrency} ${format(low)}–${format(high)} 区间`, evidence: { sampleCount: prices.length,
        source: 'owner_history', ...recommendationReasonParticipants(comparablePrices) } })
    }
  }
  return reasons.slice(0, 3)
}
