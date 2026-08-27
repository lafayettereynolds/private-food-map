import type { StarRating } from '../types/domain'

interface RatingPointerRect {
  left: number
  width: number
}

export function ratingFromPointerPosition(star: number, clientX: number, rect: RatingPointerRect): StarRating {
  const boundedStar = Math.min(5, Math.max(1, Math.round(star)))
  const relativeX = Number.isFinite(clientX) && rect.width > 0 ? clientX - rect.left : rect.width
  return (relativeX < rect.width / 2 ? boundedStar - 0.5 : boundedStar) as StarRating
}

export function stepHalfStarRating(value: StarRating | null, direction: -1 | 1): StarRating {
  const current = value ?? (direction > 0 ? 0 : 1)
  return Math.min(5, Math.max(0.5, current + direction * 0.5)) as StarRating
}
