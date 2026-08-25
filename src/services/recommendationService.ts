import type { RestaurantSummary, Visit } from '../types/domain'
import type { RecommendationContext, RecommendationReasonCode, RestaurantRecommendation } from '../types/recommendation'
import { buildTasteProfile } from './profileInsights'
import { budgetAffinity, restaurantPriceInsight } from './priceIntelligence'

export const RECOMMENDATION_CONFIG = {
  tasteMatch: 32, price: 10, quality: 24, distance: 12, repeatAffinity: 8, exploration: 6, fatigue: 8,
  bayesianPriorScore: 7.4, bayesianPriorWeight: 5, mapLimit: 24, discoverLimit: 60,
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
      .sort((a, b) => b.score - a.score || a.restaurant.name.localeCompare(b.restaurant.name, 'zh-CN'))
    const diversified: RestaurantRecommendation[] = []
    const tagCounts = new Map<string, number>()
    ranked.forEach((candidate) => {
      const primaryTag = candidate.restaurant.tags[0]?.trim().toLocaleLowerCase('zh-CN')
      const diversityPenalty = primaryTag ? Math.min(10, (tagCounts.get(primaryTag) ?? 0) * 2.5) : 0
      if (primaryTag) tagCounts.set(primaryTag, (tagCounts.get(primaryTag) ?? 0) + 1)
      diversified.push({ ...candidate, score: round2(candidate.score - diversityPenalty), rank: diversified.length + 1 })
    })
    return diversified.sort((a, b) => b.score - a.score).slice(0, context.surface === 'map' ? RECOMMENDATION_CONFIG.mapLimit : RECOMMENDATION_CONFIG.discoverLimit).map((item, index) => ({ ...item, rank: index + 1 }))
  }
}

function rankCandidate(restaurant: RestaurantSummary, visits: Visit[], profile: ReturnType<typeof buildTasteProfile>, context: RecommendationContext): RestaurantRecommendation {
  const reasons: RecommendationReasonCode[] = []
  const preferredTags = new Set(profile.preferredCuisines.slice(0, 5).map((item) => item.label.toLocaleLowerCase('zh-CN')))
  const matchingTags = restaurant.tags.filter((tag) => preferredTags.has(tag.trim().toLocaleLowerCase('zh-CN'))).length
  const tasteMatch = preferredTags.size ? matchingTags / Math.min(3, preferredTags.size) : 0
  if (tasteMatch > 0) reasons.push('TASTE_MATCH')
  const price = restaurantPriceInsight(restaurant, restaurant.visits)
  const priceMatch = budgetAffinity(price, context.budget)
  if (priceMatch > 0) reasons.push('PRICE_MATCH')
  const quality = bayesianQuality(restaurant.scoreOutOfTen, Math.max(restaurant.visitCount, 0))
  if (restaurant.scoreOutOfTen != null) reasons.push('QUALITY')
  const distance = context.location ? haversineKilometers(context.location, restaurant) : null
  const distanceScore = distance == null ? 0 : Math.max(0, 1 - distance / (context.surface === 'map' ? 8 : 25))
  if (distanceScore > .55) reasons.push('NEARBY')
  const repeatAffinity = profile.repeatVisit.tendency === '复购型' && restaurant.tags.some((tag) => preferredTags.has(tag.toLocaleLowerCase('zh-CN'))) ? 1 : 0
  if (repeatAffinity) reasons.push('REPEAT_AFFINITY')
  const exploration = context.preferExploration && matchingTags === 0 ? 1 : 0
  if (exploration) reasons.push('EXPLORATION')
  if (!profile.ratedVisitCount) reasons.push('COLD_START')
  const fatigue = visits.some((visit) => visit.restaurantId === restaurant.id && Date.now() - Date.parse(visit.visitedAt) < 30 * 86400000) ? 1 : 0
  const confidence = profile.moduleConfidence.cuisines === 'established' ? 'high' : profile.moduleConfidence.cuisines === 'emerging' ? 'medium' : 'low'
  const confidenceFactor = confidence === 'high' ? 1 : confidence === 'medium' ? .82 : .62
  const score = (tasteMatch * RECOMMENDATION_CONFIG.tasteMatch + priceMatch * RECOMMENDATION_CONFIG.price + quality * RECOMMENDATION_CONFIG.quality + distanceScore * RECOMMENDATION_CONFIG.distance + repeatAffinity * RECOMMENDATION_CONFIG.repeatAffinity + exploration * RECOMMENDATION_CONFIG.exploration - fatigue * RECOMMENDATION_CONFIG.fatigue) * confidenceFactor
  return { restaurant, score: round2(score), rank: 0, reasonCodes: reasons, confidence, source: context.type, surface: context.surface }
}

function bayesianQuality(score: number | null, sampleCount: number) { if (score == null) return .5; const adjusted = (score * sampleCount + RECOMMENDATION_CONFIG.bayesianPriorScore * RECOMMENDATION_CONFIG.bayesianPriorWeight) / (sampleCount + RECOMMENDATION_CONFIG.bayesianPriorWeight); return adjusted / 10 }
function insideViewport(restaurant: RestaurantSummary, viewport: NonNullable<RecommendationContext['viewport']>) { return restaurant.latitude <= viewport.north && restaurant.latitude >= viewport.south && restaurant.longitude <= viewport.east && restaurant.longitude >= viewport.west }
function haversineKilometers(left: { latitude: number; longitude: number }, right: { latitude: number; longitude: number }) { const radians = (value: number) => value * Math.PI / 180; const lat = radians(right.latitude - left.latitude); const lng = radians(right.longitude - left.longitude); const value = Math.sin(lat / 2) ** 2 + Math.cos(radians(left.latitude)) * Math.cos(radians(right.latitude)) * Math.sin(lng / 2) ** 2; return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value)) }
function round2(value: number) { return Math.round(value * 100) / 100 }

export const recommendationService = new RecommendationService()
