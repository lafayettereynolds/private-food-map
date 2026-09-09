import type { Visit } from '../types/domain'
import { projectPersonalRestaurantRating } from './personalRestaurantRating'

export type RatingConfidence = 'NO_DATA' | 'INSUFFICIENT' | 'LOW' | 'NORMAL'

export interface RatingDisplay {
  confidence: RatingConfidence
  displayScore: number | null
  sampleLabel: string | null
}

export function ratingConfidence(sampleCount: number): RatingConfidence {
  if (sampleCount <= 0) return 'NO_DATA'
  if (sampleCount < 5) return 'INSUFFICIENT'
  if (sampleCount < 10) return 'LOW'
  return 'NORMAL'
}

export function groupRatingDisplay(score: number | null, sampleCount: number): RatingDisplay {
  const hasScore = typeof score === 'number' && Number.isFinite(score)
  const confidence = hasScore ? ratingConfidence(sampleCount) : 'NO_DATA'
  return {
    confidence,
    displayScore: confidence === 'INSUFFICIENT' || confidence === 'NO_DATA' ? null : score,
    sampleLabel: confidence === 'INSUFFICIENT' ? '样本不足' : confidence === 'LOW' ? '样本较少' : null,
  }
}

export function personalRestaurantRating(visits: Visit[], userId?: string) {
  const ratings = visits
    .filter((visit) => !visit.deletedAt && (!userId || visit.userId === userId) && visit.rating !== null)
    .map((visit) => visit.rating)
    .filter((rating): rating is NonNullable<Visit['rating']> => rating !== null)
  if (!ratings.length) return { score: null, ratedVisitCount: 0 }
  return {
    score: projectPersonalRestaurantRating(ratings).scoreOutOfTen,
    ratedVisitCount: ratings.length,
  }
}
