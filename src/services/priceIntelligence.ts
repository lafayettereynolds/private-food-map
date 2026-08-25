import type { Restaurant, Visit } from '../types/domain'

export type PriceConfidence = 'unknown' | 'low' | 'medium' | 'high'
export type PriceSource = 'unknown' | 'manual' | 'visit_median'
export type RecommendationBudget = 'under50' | '50to100' | '100to200' | '200to400' | 'over400'

export interface RestaurantPriceInsight {
  referencePrice: number | null
  confidence: PriceConfidence
  source: PriceSource
  sampleCount: number
}

export interface RecommendationContext {
  city?: string | null
  budget?: RecommendationBudget | null
}

export const RECOMMENDATION_BUDGET_OPTIONS: Array<{ value: RecommendationBudget; label: string }> = [
  { value: 'under50', label: '¥50 以下' },
  { value: '50to100', label: '¥50–100' },
  { value: '100to200', label: '¥100–200' },
  { value: '200to400', label: '¥200–400' },
  { value: 'over400', label: '¥400+' },
]

/** Only a known table total divided by the diner count is a reliable per-person sample. */
export function visitPriceSample(visit: Visit): number | null {
  if (visit.paymentMode === 'separate') return null
  if (visit.totalPrice == null || !Number.isFinite(visit.totalPrice) || visit.totalPrice <= 0) return null
  if (!Number.isFinite(visit.partySize) || visit.partySize < 1) return null
  return visit.totalPrice / visit.partySize
}

export function restaurantPriceInsight(restaurant: Restaurant, visits: Visit[]): RestaurantPriceInsight {
  const samples = visits
    .map(visitPriceSample)
    .filter((sample): sample is number => sample !== null)
    .sort((a, b) => a - b)

  if (samples.length) {
    return {
      referencePrice: Math.round(median(samples)),
      confidence: samples.length >= 4 ? 'high' : samples.length >= 2 ? 'medium' : 'low',
      source: 'visit_median',
      sampleCount: samples.length,
    }
  }

  if (restaurant.pricePerPerson != null && restaurant.pricePerPerson > 0) {
    return {
      referencePrice: Math.round(restaurant.pricePerPerson),
      confidence: 'medium',
      source: 'manual',
      sampleCount: 0,
    }
  }

  return { referencePrice: null, confidence: 'unknown', source: 'unknown', sampleCount: 0 }
}

/** A soft ranking signal: unknown prices stay neutral and are never filtered out. */
export function budgetAffinity(price: RestaurantPriceInsight, budget: RecommendationBudget | null | undefined) {
  if (!budget || price.referencePrice == null || price.confidence === 'unknown') return 0
  const requestedIndex = budgetOrder.indexOf(budget)
  const actualIndex = budgetOrder.indexOf(priceBucket(price.referencePrice))
  const distance = Math.abs(requestedIndex - actualIndex)
  const rawAffinity = distance === 0 ? 1 : distance === 1 ? 0.25 : -Math.min(1, distance * 0.35)
  return rawAffinity * confidenceWeight[price.confidence]
}

export function priceBucket(price: number): RecommendationBudget {
  if (price < 50) return 'under50'
  if (price < 100) return '50to100'
  if (price < 200) return '100to200'
  if (price < 400) return '200to400'
  return 'over400'
}

function median(sortedValues: number[]) {
  const middle = Math.floor(sortedValues.length / 2)
  return sortedValues.length % 2
    ? sortedValues[middle]
    : (sortedValues[middle - 1] + sortedValues[middle]) / 2
}

const budgetOrder: RecommendationBudget[] = ['under50', '50to100', '100to200', '200to400', 'over400']
const confidenceWeight: Record<PriceConfidence, number> = { unknown: 0, low: 0.35, medium: 0.65, high: 1 }
