import type { RestaurantSummary, Visit } from '../types/domain'
import type {
  RecommendationContext,
  RecommendationFitLevel,
  RecommendationReason,
  RecommendationReasonCode,
  RestaurantRecommendation,
} from '../types/recommendation'
import { buildTasteProfile } from './profileInsights'
import { budgetAffinity, restaurantPriceInsight } from './priceIntelligence'

export const RECOMMENDATION_CONFIG = {
  tasteMatch: 32, price: 10, quality: 24, distance: 12, repeatAffinity: 8, exploration: 6, fatigue: 8,
  bayesianPriorScore: 7.4, bayesianPriorWeight: 5, mapLimit: 24, discoverLimit: 60,
  minimumQualityScore: 5.5, explorationShare: .2,
} as const

export class RecommendationService {
  generateCandidates(restaurants: RestaurantSummary[], context: RecommendationContext) {
    return restaurants.filter((restaurant) => {
      if (restaurant.deletedAt || restaurant.status === 'visited') return false
      if (context.city && restaurant.city !== context.city) return false
      if (context.viewport && !insideViewport(restaurant, context.viewport)) return false
      return true
    })
  }

  recommend(restaurants: RestaurantSummary[], visits: Visit[], context: RecommendationContext): RestaurantRecommendation[] {
    const profile = buildTasteProfile(restaurants, visits)
    const candidates = this.generateCandidates(restaurants, context)
    const ranked = candidates.map((restaurant) => rankCandidate(restaurant, visits, profile, context))
      .filter((candidate) => candidate.restaurant.scoreOutOfTen == null
        || candidate.restaurant.scoreOutOfTen >= RECOMMENDATION_CONFIG.minimumQualityScore)
      .sort((a, b) => b.score - a.score || a.restaurant.name.localeCompare(b.restaurant.name, 'zh-CN'))
    const diversified: RestaurantRecommendation[] = []
    const tagCounts = new Map<string, number>()
    ranked.forEach((candidate) => {
      const primaryTag = candidate.restaurant.tags[0]?.trim().toLocaleLowerCase('zh-CN')
      const diversityPenalty = primaryTag ? Math.min(10, (tagCounts.get(primaryTag) ?? 0) * 2.5) : 0
      if (primaryTag) tagCounts.set(primaryTag, (tagCounts.get(primaryTag) ?? 0) + 1)
      diversified.push({ ...candidate, score: round2(candidate.score - diversityPenalty), rank: diversified.length + 1 })
    })
    const sorted = diversified.sort((a, b) => b.score - a.score)
    const withExploration = sorted.map((item, index) => {
      const shouldExplore = context.preferExploration && index > 1 && (index + 1) % Math.round(1 / RECOMMENDATION_CONFIG.explorationShare) === 0
      if (!shouldExplore || item.fitLevel === 'STRONG_MATCH') return item
      return asExploration(item)
    })
    return withExploration
      .slice(0, context.surface === 'map' ? RECOMMENDATION_CONFIG.mapLimit : RECOMMENDATION_CONFIG.discoverLimit)
      .map((item, index) => ({ ...item, rank: index + 1 }))
  }
}

function rankCandidate(restaurant: RestaurantSummary, visits: Visit[], profile: ReturnType<typeof buildTasteProfile>, context: RecommendationContext): RestaurantRecommendation {
  const reasons: RecommendationReasonCode[] = []
  const detailedReasons: RecommendationReason[] = []
  const preferredTags = new Set(profile.preferredCuisines.slice(0, 5).map((item) => item.label.toLocaleLowerCase('zh-CN')))
  const matchingTagNames = restaurant.tags.filter((tag) => preferredTags.has(tag.trim().toLocaleLowerCase('zh-CN')))
  const matchingTags = matchingTagNames.length
  const tasteMatch = preferredTags.size ? matchingTags / Math.min(3, preferredTags.size) : 0
  if (tasteMatch > 0) {
    reasons.push('TASTE_MATCH', 'HIGH_CUISINE_MATCH')
    detailedReasons.push({
      code: 'HIGH_CUISINE_MATCH',
      text: `与你长期偏好的${matchingTagNames.slice(0, 2).join('、')}口味接近`,
      evidence: { cuisine: matchingTagNames.slice(0, 2).join('、') },
    })
  }
  const price = restaurantPriceInsight(restaurant, restaurant.visits)
  const priceMatch = budgetAffinity(price, context.budget)
  if (priceMatch > 0) {
    reasons.push('PRICE_MATCH', 'PRICE_RANGE_MATCH')
    detailedReasons.push({ code: 'PRICE_RANGE_MATCH', text: '人均价格落在你常用的预算区间内' })
  }
  const quality = bayesianQuality(restaurant.scoreOutOfTen, Math.max(restaurant.visitCount, 0))
  if (restaurant.scoreOutOfTen != null) {
    reasons.push('QUALITY', 'HIGH_RATING_TRAIT_MATCH')
    detailedReasons.push({ code: 'HIGH_RATING_TRAIT_MATCH', text: `餐厅参考评分 ${restaurant.scoreOutOfTen.toFixed(1)}，质量信号较稳定` })
  }
  const distance = context.location ? haversineKilometers(context.location, restaurant) : null
  const distanceScore = distance == null ? 0 : Math.max(0, 1 - distance / (context.surface === 'map' ? 8 : 25))
  if (distanceScore > .55) {
    reasons.push('NEARBY', 'NEARBY_AND_OPEN')
    detailedReasons.push({
      code: 'NEARBY_AND_OPEN',
      text: distance == null ? '距离适合这次就餐' : `距离约 ${formatDistance(distance)}，适合就近选择`,
      evidence: { distanceKilometers: distance ?? undefined },
    })
  }
  const repeatAffinity = profile.repeatVisit.tendency === '复购型' && restaurant.tags.some((tag) => preferredTags.has(tag.toLocaleLowerCase('zh-CN'))) ? 1 : 0
  if (repeatAffinity) {
    reasons.push('REPEAT_AFFINITY', 'REPEAT_VISIT_PATTERN')
    detailedReasons.push({ code: 'REPEAT_VISIT_PATTERN', text: '与那些你会重复到访的餐厅类型相近' })
  }
  const exploration = context.preferExploration && matchingTags === 0 ? 1 : 0
  if (exploration) {
    reasons.push('EXPLORATION', 'SHORT_TERM_DIVERSITY')
    detailedReasons.push({ code: 'SHORT_TERM_DIVERSITY', text: '保留少量不同口味，帮你跳出近期选择惯性' })
  }
  if (!profile.ratedVisitCount) {
    reasons.push('COLD_START')
    detailedReasons.push({ code: 'COLD_START', text: '你的口味正在形成，暂以基础质量和距离作为参考' })
  }
  const fatigue = visits.some((visit) => visit.restaurantId === restaurant.id && Date.now() - Date.parse(visit.visitedAt) < 30 * 86400000) ? 1 : 0
  const confidence = profile.moduleConfidence.cuisines === 'established' ? 'high' : profile.moduleConfidence.cuisines === 'emerging' ? 'medium' : 'low'
  const confidenceFactor = confidence === 'high' ? 1 : confidence === 'medium' ? .82 : .62
  const score = (tasteMatch * RECOMMENDATION_CONFIG.tasteMatch + priceMatch * RECOMMENDATION_CONFIG.price + quality * RECOMMENDATION_CONFIG.quality + distanceScore * RECOMMENDATION_CONFIG.distance + repeatAffinity * RECOMMENDATION_CONFIG.repeatAffinity + exploration * RECOMMENDATION_CONFIG.exploration - fatigue * RECOMMENDATION_CONFIG.fatigue) * confidenceFactor
  const fitLevel = resolveFitLevel(score, confidence, exploration > 0, quality)
  const orderedReasons = prioritizeReasons(detailedReasons, fitLevel)
  const primaryReasons = orderedReasons.filter((reason) => isPersonalEvidence(reason.code)).slice(0, 3)
  const selectedPrimaryReasons = new Set(primaryReasons)
  return {
    restaurant,
    score: round2(score),
    rank: 0,
    reasonCodes: unique(reasons),
    confidence,
    source: context.type,
    surface: context.surface,
    fitLevel,
    primaryReasons,
    secondaryReasons: orderedReasons.filter((reason) => !selectedPrimaryReasons.has(reason)).slice(0, 5),
    isExploration: fitLevel === 'EXPLORATION',
    publicRating: publicRatingForRestaurant(visits, restaurant.id),
  }
}

function resolveFitLevel(score: number, confidence: RestaurantRecommendation['confidence'], isExploration: boolean, quality: number): RecommendationFitLevel {
  if (isExploration || quality < .55) return 'EXPLORATION'
  if (score >= 43 && confidence !== 'low') return 'STRONG_MATCH'
  if (score >= 30 && confidence !== 'low') return 'GOOD_MATCH'
  return 'MODERATE_MATCH'
}

function prioritizeReasons(reasons: RecommendationReason[], fitLevel: RecommendationFitLevel) {
  const order: RecommendationReasonCode[] = fitLevel === 'EXPLORATION'
    ? ['SHORT_TERM_DIVERSITY', 'PRICE_RANGE_MATCH', 'HIGH_RATING_TRAIT_MATCH', 'NEARBY_AND_OPEN']
    : ['HIGH_CUISINE_MATCH', 'REPEAT_VISIT_PATTERN', 'PRICE_RANGE_MATCH', 'NEARBY_AND_OPEN', 'HIGH_RATING_TRAIT_MATCH', 'COLD_START']
  return [...reasons].sort((a, b) => order.indexOf(a.code) - order.indexOf(b.code))
}

function isPersonalEvidence(code: RecommendationReasonCode) {
  return [
    'HIGH_CUISINE_MATCH',
    'PRICE_RANGE_MATCH',
    'REPEAT_VISIT_PATTERN',
    'COMPANION_CONTEXT_MATCH',
    'SOURCE_AFFINITY_MATCH',
    'SHORT_TERM_DIVERSITY',
    'SIMILAR_USERS',
  ].includes(code)
}

function asExploration(item: RestaurantRecommendation): RestaurantRecommendation {
  const explorationReason: RecommendationReason = { code: 'SHORT_TERM_DIVERSITY', text: '换个口味试试，避免推荐过于单一' }
  const reasons = [explorationReason, ...item.primaryReasons, ...item.secondaryReasons]
  const primaryReasons = reasons.filter((reason) => isPersonalEvidence(reason.code)).slice(0, 3)
  const selectedPrimaryReasons = new Set(primaryReasons)
  return {
    ...item,
    fitLevel: 'EXPLORATION',
    isExploration: true,
    reasonCodes: unique([...item.reasonCodes, 'SHORT_TERM_DIVERSITY']),
    primaryReasons,
    secondaryReasons: reasons.filter((reason) => !selectedPrimaryReasons.has(reason)).slice(0, 5),
  }
}

function formatDistance(distance: number) { return distance < 1 ? `${Math.round(distance * 1000)} 米` : `${distance.toFixed(1)} 公里` }
function unique<T>(values: T[]) { return [...new Set(values)] }

function publicRatingForRestaurant(visits: Visit[], restaurantId: string) {
  const ratingsByUser = new Map<string, number[]>()
  visits.forEach((visit) => {
    if (visit.restaurantId !== restaurantId || visit.visibility !== 'public' || visit.deletedAt || visit.rating == null) return
    ratingsByUser.set(visit.userId, [...(ratingsByUser.get(visit.userId) ?? []), visit.rating * 2])
  })
  const userAverages = [...ratingsByUser.values()].map((ratings) => ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length)
  return {
    value: userAverages.length ? Math.round((userAverages.reduce((sum, rating) => sum + rating, 0) / userAverages.length) * 10) / 10 : null,
    sampleCount: userAverages.length,
  }
}

function bayesianQuality(score: number | null, sampleCount: number) { if (score == null) return .5; const adjusted = (score * sampleCount + RECOMMENDATION_CONFIG.bayesianPriorScore * RECOMMENDATION_CONFIG.bayesianPriorWeight) / (sampleCount + RECOMMENDATION_CONFIG.bayesianPriorWeight); return adjusted / 10 }
function insideViewport(restaurant: RestaurantSummary, viewport: NonNullable<RecommendationContext['viewport']>) { return restaurant.latitude <= viewport.north && restaurant.latitude >= viewport.south && restaurant.longitude <= viewport.east && restaurant.longitude >= viewport.west }
function haversineKilometers(left: { latitude: number; longitude: number }, right: { latitude: number; longitude: number }) { const radians = (value: number) => value * Math.PI / 180; const lat = radians(right.latitude - left.latitude); const lng = radians(right.longitude - left.longitude); const value = Math.sin(lat / 2) ** 2 + Math.cos(radians(left.latitude)) * Math.cos(radians(right.latitude)) * Math.sin(lng / 2) ** 2; return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value)) }
function round2(value: number) { return Math.round(value * 100) / 100 }

export const recommendationService = new RecommendationService()
