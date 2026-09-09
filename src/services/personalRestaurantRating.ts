/** Personal, same-owner Restaurant Visits only. Callers own eligibility filtering.
 * Raw ratings are contract half-stars. Preserve the precise mean for consumers;
 * round only the ten-point output, using positive half-up (Math.round) semantics.
 */
export function projectPersonalRestaurantRating(ratings: readonly number[]) {
  if (!ratings.length) return { averageRating: null, scoreOutOfTen: null }
  const sum = ratings.reduce((total, rating) => total + rating, 0)
  const averageRating = sum / ratings.length
  // Half-star sums are exactly representable. Divide integer tenth-score units
  // with a remainder so a repeating binary mean cannot perturb a .05 tie.
  const numerator = sum * 20
  const quotient = Math.floor(numerator / ratings.length)
  const remainder = numerator % ratings.length
  const scoreOutOfTen = (quotient + (remainder * 2 >= ratings.length ? 1 : 0)) / 10
  return { averageRating, scoreOutOfTen }
}
