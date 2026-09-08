import { SCORE_BAND_ORDER, scoreBandFromScore, type Coordinates, type ScoreBand } from '../types/domain'
import { restaurantCityComparisonKey } from './restaurantCity'

export type EmptyResultReason =
  | 'FILTER_EMPTY'
  | 'DISTANCE_TOO_STRICT'
  | 'RATING_TOO_STRICT'
  | 'CITY_TOO_STRICT'
  | 'LOCATION_UNAVAILABLE'
  | 'NO_LOCAL_CANDIDATES'

export type ActiveRecommendationFilter =
  | { type: 'distance'; value: number; unit: 'km' }
  | { type: 'rating'; value: number; unit: 'score' }
  | { type: 'scoreBands'; value: ScoreBand[] }
  | { type: 'city'; value: string }

export type RelaxationSuggestion =
  | { type: 'distance'; from: number; to: number | null; estimatedResultCount: number }
  | { type: 'rating'; from: number; to: number | null; estimatedResultCount: number }
  | { type: 'scoreBands'; from: ScoreBand[]; to: ScoreBand[]; estimatedResultCount: number }
  | { type: 'city'; from: string; to: null; estimatedResultCount: number }

export interface RecommendationFilterState {
  distanceKm?: number | null
  ratingMinimum?: number | null
  scoreBands?: ScoreBand[]
  city?: string | null
}

export interface RecommendationFilterCandidate {
  latitude: number
  longitude: number
  city: string
  scoreOutOfTen: number | null
}

export interface RecommendationFilterResolution<T> {
  results: T[]
  activeFilters: ActiveRecommendationFilter[]
  emptyReason: EmptyResultReason | null
  relaxationSuggestion: RelaxationSuggestion | null
}

export interface RecommendationEmptyState {
  title: string
  message: string
  actionLabel?: string
}

const DISTANCE_STEPS = [1, 3, 5, 10] as const
const RATING_STEPS = [9, 8, 7] as const

export function resolveRecommendationFilters<T extends RecommendationFilterCandidate>(
  candidates: T[],
  state: RecommendationFilterState,
  anchor: Coordinates | null,
): RecommendationFilterResolution<T> {
  const activeFilters = buildActiveFilters(state)
  if (state.distanceKm && !anchor) return { results: [], activeFilters, emptyReason: 'LOCATION_UNAVAILABLE', relaxationSuggestion: null }
  const results = applyFilters(candidates, state, anchor)
  if (results.length) return { results, activeFilters, emptyReason: null, relaxationSuggestion: null }
  if (!candidates.length) return { results, activeFilters, emptyReason: 'NO_LOCAL_CANDIDATES', relaxationSuggestion: null }
  if (!activeFilters.length) return { results, activeFilters, emptyReason: 'NO_LOCAL_CANDIDATES', relaxationSuggestion: null }

  const suggestions = buildRelaxationSuggestions(candidates, state, anchor)
  const suggestion = suggestions.find((item) => item.estimatedResultCount > 0) ?? null
  const emptyReason = suggestion?.type === 'distance'
    ? 'DISTANCE_TOO_STRICT'
    : suggestion?.type === 'rating' || suggestion?.type === 'scoreBands'
      ? 'RATING_TOO_STRICT'
      : suggestion?.type === 'city'
        ? 'CITY_TOO_STRICT'
        : 'FILTER_EMPTY'
  return { results, activeFilters, emptyReason, relaxationSuggestion: suggestion }
}

export function distanceKilometers(origin: Coordinates, target: Pick<RecommendationFilterCandidate, 'latitude' | 'longitude'>) {
  const radians = (degrees: number) => degrees * Math.PI / 180
  const latitudeDelta = radians(target.latitude - origin.latitude)
  const longitudeDelta = radians(target.longitude - origin.longitude)
  const startLatitude = radians(origin.latitude)
  const endLatitude = radians(target.latitude)
  const value = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(startLatitude) * Math.cos(endLatitude) * Math.sin(longitudeDelta / 2) ** 2
  return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value))
}

export function candidateCentroid<T extends Pick<RecommendationFilterCandidate, 'latitude' | 'longitude'>>(candidates: T[]): Coordinates | null {
  if (!candidates.length) return null
  return {
    latitude: candidates.reduce((sum, item) => sum + item.latitude, 0) / candidates.length,
    longitude: candidates.reduce((sum, item) => sum + item.longitude, 0) / candidates.length,
  }
}

export function sameCity(left: string, right: string) {
  const key = restaurantCityComparisonKey(left)
  return Boolean(key) && key === restaurantCityComparisonKey(right)
}

export function buildRecommendationEmptyState(
  suggestion: RelaxationSuggestion | null,
  reason: EmptyResultReason | null,
  fallbackMessage = '',
): RecommendationEmptyState {
  if (suggestion?.type === 'distance') {
    const destination = suggestion.to === null ? '不限距离' : `${suggestion.to} km 内`
    return {
      title: `${suggestion.from} km 内暂时没有合适的推荐`,
      message: `${destination}有 ${suggestion.estimatedResultCount} 家`,
      actionLabel: suggestion.to === null ? '取消距离限制' : `扩大到 ${suggestion.to} km`,
    }
  }
  if (suggestion?.type === 'rating') return {
    title: `暂时没有 ${suggestion.from} 分以上的推荐`,
    message: `${suggestion.to === null ? '不限评分' : `${suggestion.to} 分以上`}有 ${suggestion.estimatedResultCount} 家`,
    actionLabel: suggestion.to === null ? '取消评分限制' : `调整为 ${suggestion.to} 分以上`,
  }
  if (suggestion?.type === 'scoreBands') return {
    title: '当前评分范围暂时没有合适的推荐',
    message: `放宽一个评分区间后有 ${suggestion.estimatedResultCount} 家`,
    actionLabel: '放宽评分范围',
  }
  if (suggestion?.type === 'city') return {
    title: `${suggestion.from}暂时没有合适的推荐`,
    message: `查看全部城市可找到 ${suggestion.estimatedResultCount} 家`,
    actionLabel: '查看全部城市',
  }
  if (reason === 'LOCATION_UNAVAILABLE') return { title: '暂时无法计算距离', message: '请选择浏览城市或允许定位后重试。' }
  if (reason === 'FILTER_EMPTY') return { title: '当前筛选组合暂时没有结果', message: '可重置筛选后继续查看推荐。' }
  return { title: '还没有足够信息推荐', message: fallbackMessage || '多记录几家餐厅后，推荐会越来越贴合你的口味。' }
}

function applyFilters<T extends RecommendationFilterCandidate>(candidates: T[], state: RecommendationFilterState, anchor: Coordinates | null) {
  return candidates.filter((candidate) => {
    if (state.city && !sameCity(candidate.city, state.city)) return false
    if (state.ratingMinimum && (candidate.scoreOutOfTen === null || candidate.scoreOutOfTen < state.ratingMinimum)) return false
    const scoreBand = scoreBandFromScore(candidate.scoreOutOfTen)
    if (state.scoreBands?.length && (!scoreBand || !state.scoreBands.includes(scoreBand))) return false
    if (state.distanceKm && anchor && distanceKilometers(anchor, candidate) > state.distanceKm) return false
    return true
  })
}

function buildActiveFilters(state: RecommendationFilterState): ActiveRecommendationFilter[] {
  const filters: ActiveRecommendationFilter[] = []
  if (state.distanceKm) filters.push({ type: 'distance', value: state.distanceKm, unit: 'km' })
  if (state.ratingMinimum) filters.push({ type: 'rating', value: state.ratingMinimum, unit: 'score' })
  if (state.scoreBands?.length) filters.push({ type: 'scoreBands', value: state.scoreBands })
  if (state.city) filters.push({ type: 'city', value: state.city })
  return filters
}

function buildRelaxationSuggestions<T extends RecommendationFilterCandidate>(candidates: T[], state: RecommendationFilterState, anchor: Coordinates | null) {
  const suggestions: RelaxationSuggestion[] = []
  if (state.distanceKm && anchor) {
    const nextDistances = DISTANCE_STEPS.filter((step) => step > state.distanceKm!)
    for (const to of [...nextDistances, null]) {
      const estimatedResultCount = applyFilters(candidates, { ...state, distanceKm: to }, anchor).length
      if (estimatedResultCount) {
        suggestions.push({ type: 'distance', from: state.distanceKm, to, estimatedResultCount })
        break
      }
    }
  }
  if (state.ratingMinimum) {
    const nextRatings = RATING_STEPS.filter((step) => step < state.ratingMinimum!)
    for (const to of [...nextRatings, null]) {
      const estimatedResultCount = applyFilters(candidates, { ...state, ratingMinimum: to }, anchor).length
      if (estimatedResultCount) {
        suggestions.push({ type: 'rating', from: state.ratingMinimum, to, estimatedResultCount })
        break
      }
    }
  }
  if (state.scoreBands?.length) {
    for (const band of SCORE_BAND_ORDER) {
      if (state.scoreBands.includes(band)) continue
      const to = [...state.scoreBands, band]
      const estimatedResultCount = applyFilters(candidates, { ...state, scoreBands: to }, anchor).length
      if (estimatedResultCount) {
        suggestions.push({ type: 'scoreBands', from: state.scoreBands, to, estimatedResultCount })
        break
      }
    }
  }
  if (state.city) {
    const estimatedResultCount = applyFilters(candidates, { ...state, city: null }, anchor).length
    if (estimatedResultCount) suggestions.push({ type: 'city', from: state.city, to: null, estimatedResultCount })
  }
  return suggestions
}
