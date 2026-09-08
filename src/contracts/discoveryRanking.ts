/** Ordering-only prior. Never replace the displayed real mean or user count. */
export const DISCOVERY_PUBLIC_RATING_PRIOR = { meanOutOfFive: 3.5, users: 5 } as const

export function discoveryPublicRatingRank(meanOutOfFive: number | null, users: number): number {
  if (meanOutOfFive == null || !Number.isFinite(meanOutOfFive) || meanOutOfFive <= 0 || meanOutOfFive > 5
    || !Number.isSafeInteger(users) || users <= 0) return -1
  const prior = DISCOVERY_PUBLIC_RATING_PRIOR
  return (meanOutOfFive * users + prior.meanOutOfFive * prior.users) / (users + prior.users)
}
