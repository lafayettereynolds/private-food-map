import type { RestaurantSummary, Visit } from '../types/domain'

export type AnalyticsMode = 'taste' | 'companion' | 'source' | 'monthly' | 'annual'
export type AnalyticsConfidence = 'insufficient' | 'emerging' | 'established'
export interface AnalyticsMetric { id: string; label: string; value: string; note?: string; privacy?: 'spend' | 'companion' }
export interface AnalyticsRow {
  id: string
  label: string
  value?: string
  detail?: string
  restaurantID?: string
  count?: number
  share?: number
  scoreOutOfTen?: number | null
  privacy?: 'spend' | 'companion'
}
export interface AnalyticsSection {
  id: string
  title: string
  description?: string
  emptyMessage?: string
  confidence?: AnalyticsConfidence
  metrics?: AnalyticsMetric[]
  rows?: AnalyticsRow[]
  privacy?: 'spend' | 'companion'
}
export interface AnalyticsRestaurantEvidence extends AnalyticsRow {
  restaurantID: string
  count: number
  scoreOutOfTen: number | null
  latestVisitAt: string
}
export interface AnalyticsDataset { ownerID: string; restaurants: RestaurantSummary[]; visits: Visit[]; excludedVisitCount: number; unavailableVisitCount: number }
export interface AnalyticsSpend {
  total: number
  recordedVisitCount: number
  unrecordedVisitCount: number
  coverage: number
  display: 'hidden' | 'recorded' | 'total'
  median: number | null
  lowerQuartile: number | null
  upperQuartile: number | null
}
export interface AnalyticsReportSummary {
  visitCount: number
  restaurantCount: number
  ratedVisitCount: number
  averageScoreOutOfTen: number | null
  cityCount: number
  spend: AnalyticsSpend
}
