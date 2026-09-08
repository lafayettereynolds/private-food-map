import { describe, expect, it } from 'vitest'
import { recommendationHistoryReasons, type RecommendationHistoryPlace } from '../src/services/recommendationHistoryReasons'
const now = Date.parse('2026-09-07T12:00:00Z')
const candidate = { tags: ['日料'], pricePerPerson: null }
const place = (i: number, extra: Partial<RecommendationHistoryPlace> = {}): RecommendationHistoryPlace => ({
  canonicalID: 'r' + i, name: '店' + i, tags: ['日料'], ratingCount: 1, ratingSumOutOfFive: 4.5,
  visitCount: 1, pricePerPerson: 100, firstVisitedAt: '2026-07-01T12:00:00Z', lastVisitedAt: '2026-07-01T12:00:00Z', ...extra,
  referenceRatingOutOfFive: extra.referenceRatingOutOfFive === undefined ? 4.5 : extra.referenceRatingOutOfFive,
})
const history = (count: number, extra: Partial<RecommendationHistoryPlace> = {}) => Array.from({ length: count }, (_, i) => place(i, extra))
const codes = (reasons: ReturnType<typeof recommendationHistoryReasons>) => reasons.map(r => r.code)

describe('strict For You evidence reasons', () => {
  it('requires five distinct related rated Restaurants, uses unweighted restaurant means, and rejects negative averages', () => {
    expect(recommendationHistoryReasons(candidate, history(4))).toEqual([])
    const input = history(5); input[0] = place(0, { ratingCount: 10, ratingSumOutOfFive: 50 })
    const result = recommendationHistoryReasons(candidate, input)
    expect(result[0]).toMatchObject({ code: 'HIGH_CUISINE_MATCH', evidence: { sampleCount: 5, meanOutOfTen: 9.2 } })
    expect(recommendationHistoryReasons(candidate, Array(5).fill(place(1)))).toEqual([])
    expect(recommendationHistoryReasons(candidate, history(5, { ratingSumOutOfFive: 2 }))).toEqual([])
  })
  it('never treats two category tags as two reliable dimensions or an unverified price as evidence', () => {
    const input = [place(1, { tags: ['日料', '寿司'] })]
    expect(recommendationHistoryReasons({ tags: ['日料', '寿司'], pricePerPerson: 100 }, input)).toEqual([])
    const result = recommendationHistoryReasons({ ...candidate, verifiedDimensions: { cooking: ['炭烤'] } }, [place(1, { verifiedDimensions: { cooking: ['炭烤'] } })])
    expect(result[0]).toMatchObject({ code: 'TASTE_TAG_MATCH', text: '与你给过9分的「店1」在餐厅类型、烹饪方式上接近', evidence: { dimensions: ['餐厅类型', '烹饪方式'] } })
    const exactRating = recommendationHistoryReasons({ ...candidate, verifiedDimensions: { cooking: ['炭烤'] } }, [place(1, { ratingCount: 2, ratingSumOutOfFive: 9, referenceRatingOutOfFive: 5, verifiedDimensions: { cooking: ['炭烤'] } })])
    expect(exactRating[0].text).toContain('给过10分')
    expect(recommendationHistoryReasons({ ...candidate, verifiedDimensions: { cooking: ['炭烤'] } }, [place(1, { referenceRatingOutOfFive: null, verifiedDimensions: { cooking: ['炭烤'] } })])).toEqual([])
    expect(recommendationHistoryReasons({ ...candidate, verifiedDimensions: { cooking: ['炭烤'] } }, [place(1, { ratingSumOutOfFive: 3, verifiedDimensions: { cooking: ['炭烤'] } })])).toEqual([])
  })
  it('requires three same-type places and at least two nonnegative cross-date repeated places', () => {
    const repeated = { visitCount: 2, lastVisitedAt: '2026-07-03T12:00:00Z' }
    expect(recommendationHistoryReasons(candidate, history(2, repeated))).toEqual([])
    expect(recommendationHistoryReasons(candidate, [place(0, repeated), place(1), place(2)])).toEqual([])
    expect(codes(recommendationHistoryReasons(candidate, [place(0, repeated), place(1, repeated), place(2)]))).toEqual(['REPEAT_VISIT_PATTERN'])
    expect(recommendationHistoryReasons(candidate, history(3, { visitCount: 20, lastVisitedAt: '2026-07-01T15:00:00Z' }))).toEqual([])
    expect(recommendationHistoryReasons(candidate, history(3, { ...repeated, firstVisitedAt: null }))).toEqual([])
    expect(recommendationHistoryReasons(candidate, history(3, { ...repeated, ratingSumOutOfFive: 2 }))).toEqual([])
  })
  it('requires five high-rated reliable recorded per-person prices and a reliable candidate price', () => {
    const input = history(5, { priceReliable: true, priceCurrency: 'CNY' })
    expect(recommendationHistoryReasons({ tags: [], pricePerPerson: 100 }, input)).toEqual([])
    expect(recommendationHistoryReasons({ tags: [], pricePerPerson: 100, priceReliable: true }, input.slice(0, 4))).toEqual([])
    expect(recommendationHistoryReasons({ tags: [], pricePerPerson: 100, priceReliable: true }, input)).toEqual([])
    expect(recommendationHistoryReasons({ tags: [], pricePerPerson: 100, priceReliable: true, priceCurrency: 'USD' }, input)).toEqual([])
    expect(codes(recommendationHistoryReasons({ tags: [], pricePerPerson: 100, priceReliable: true, priceCurrency: 'CNY' }, input))).toEqual(['PRICE_RANGE_MATCH'])
    expect(recommendationHistoryReasons({ tags: [], pricePerPerson: 100.001, priceReliable: true }, input)).toEqual([])
    expect(recommendationHistoryReasons({ tags: [], pricePerPerson: 100, priceReliable: true }, history(5))).toEqual([])
  })
  it('caps independent verified reasons at three without requiring a minimum count', () => {
    const result = recommendationHistoryReasons({ ...candidate, pricePerPerson: 100, priceReliable: true, priceCurrency: 'CNY' }, history(5, { priceReliable: true, priceCurrency: 'CNY', visitCount: 2, lastVisitedAt: '2026-07-02T12:00:00Z' }))
    expect(codes(result)).toEqual(['TASTE_TAG_MATCH', 'HIGH_CUISINE_MATCH', 'REPEAT_VISIT_PATTERN'])
    expect(new Set(result.map(r => r.code)).size).toBe(result.length)
    expect(recommendationHistoryReasons(candidate, history(1))).toEqual([])
  })
  it('puts eligible sparse-last-year exploration first without validated-preference claims', () => {
    const input = history(5, { tags: ['咖啡'] })
    const get = (places = input, eligible = true) => recommendationHistoryReasons({ ...candidate, explorationEligible: eligible }, places, { now })
    expect(codes(get())).toEqual(['SHORT_TERM_DIVERSITY'])
    expect(get()[0].evidence).toMatchObject({ sampleCount: 0, windowDays: 365 })
    expect(get(input, false)).toEqual([])
    expect(get([...input, place(8), place(9)])).toEqual([])
    expect(get([...input, place(9, { lastVisitedAt: null })])).toEqual([])
    expect(get(history(5, { tags: ['咖啡'], lastVisitedAt: '2024-01-01T12:00:00Z' }))).toEqual([])
    expect(get([...input, place(9, { lastVisitedAt: '2027-01-01T12:00:00Z' })])).toEqual([])
  })
  it('rejects invalid ratings instead of inventing evidence', () => {
    for (const bad of [NaN, Infinity, 0, -1, 6]) expect(recommendationHistoryReasons(candidate, history(5, { ratingSumOutOfFive: bad }))).toEqual([])
  })
})
