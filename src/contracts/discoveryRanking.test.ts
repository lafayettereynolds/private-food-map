import { describe, expect, it } from 'vitest'
import { discoveryPublicRatingRank } from './discoveryRanking'

describe('public rating ordering evidence', () => {
  it('does not give one perfect rating priority over strong supported evidence', () => {
    expect(discoveryPublicRatingRank(4.5, 30)).toBeGreaterThan(discoveryPublicRatingRank(5, 1))
  })
  it('orders equal sample sizes by their real means', () => {
    expect(discoveryPublicRatingRank(4.8, 10)).toBeGreaterThan(discoveryPublicRatingRank(4, 10))
  })
  it('keeps missing or invalid evidence last', () => {
    for (const [mean, users] of [[null, 10], [5, 0], [NaN, 5], [6, 10], [4, 1.5]] as const) expect(discoveryPublicRatingRank(mean, users)).toBe(-1)
  })
})
