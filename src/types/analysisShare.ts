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
  /** Restaurant classification for the supplied illustration fallback, not a photo claim. */
  tags?: string[]
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

export interface AnalysisTasteProfileSlice {
  label: string
  value: number
  symbol: string
}

export interface AnalysisTasteProfileSnapshot {
  periodLabel: string
  restaurantCount: number
  dishCount: number
  visitCount: number
  spend: number | null
  cityCount: number
  averageScoreOutOfTen: number | null
  cuisines: AnalysisTasteProfileSlice[]
  preferences: AnalysisTasteProfileSlice[]
  spendCategories: AnalysisTasteProfileSlice[]
  priceRanges: AnalysisTasteProfileSlice[]
  cities: AnalysisTasteProfileSlice[]
  companions: AnalysisTasteProfileSlice[]
  diningTimes: AnalysisTasteProfileSlice[]
  cuisineNote?: string
  diningTimeNote?: string
}

export interface AnalysisShareData {
  /** Complete scrapbook composition, derived from the same scoped analysis. */
  editorial?: AnalysisEditorialPoster
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
  /** Same supported findings as the data module, after share-privacy filtering. */
  posterFindings?: Array<{ sectionID: string; title: string; text: string }>
  keywords: string[]
  restaurants: AnalysisRestaurantEvidence[]
  heroCandidates: AnalysisVisualRef[]
  /** Present only for the editorial 2:3 Taste Profile composition. */
  tasteProfile?: AnalysisTasteProfileSnapshot
  /** Dedicated F24 card; older editorial consumers remain backward compatible. */
  tasteCard?: { cuisines: Array<{ label: string; count: number }>; recordCount: number; restaurantCount: number }
  /** V2 memory cover: one headline, scoped hero and bounded facts. */
  memoryCard?: boolean
  sourceResults?: {
    baseline: number | null
    baselineCount: number
    best: { name: string; rate: number; count: number; outcomeCount: number; average: number } | null
    worst: { name: string; rate: number; count: number; outcomeCount: number; average: number } | null
  }
  footer: string
  logoSource: string
  privacy: {
    companionNameIncluded: boolean
    spendIncluded: boolean
    exactLocationIncluded: false
  }
}

export interface AnalysisEditorialRow {
  id: string
  label: string
  value: string
  detail?: string
  amount?: number
  visual?: AnalysisVisualRef
}
export interface AnalysisEditorialSection {
  id: string
  title: string
  note?: string
  empty?: string
  rows: AnalysisEditorialRow[]
}
export interface AnalysisEditorialPoster {
  audience: 'owner' | 'share'
  overview: AnalysisMetric[]
  cuisines: AnalysisEditorialRow[]
  sections: AnalysisEditorialSection[]
}
