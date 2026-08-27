export type AnalysisShareType =
  | 'TASTE_PROFILE'
  | 'COMPANION_ANALYSIS'
  | 'RECOMMENDATION_SOURCE'
  | 'MONTHLY_REVIEW'
  | 'ANNUAL_REVIEW'
  | 'ON_THIS_DAY'

export type AnalysisVisualOrigin = 'visit' | 'restaurant' | 'provider' | 'fallback'

export interface AnalysisVisualRef {
  source: string | null
  photoId: string | null
  origin: AnalysisVisualOrigin
  label: string
  restaurantId?: string
}

export interface AnalysisMetric {
  label: string
  value: string
  note?: string
}

export interface AnalysisRestaurantEvidence {
  restaurantId: string
  name: string
  meta: string
  score?: string
  image: AnalysisVisualRef
}

export interface AnalysisShareData {
  reportId: string
  type: AnalysisShareType
  userId: string
  title: string
  eyebrow: string
  subtitle: string
  summary: string
  periodLabel?: string
  metrics: AnalysisMetric[]
  insights: string[]
  keywords: string[]
  restaurants: AnalysisRestaurantEvidence[]
  heroCandidates: AnalysisVisualRef[]
  footer: string
  logoSource: string
  privacy: {
    companionNameIncluded: boolean
    spendIncluded: boolean
    exactLocationIncluded: false
  }
}
