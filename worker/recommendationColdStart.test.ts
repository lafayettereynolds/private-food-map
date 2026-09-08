import { describe, expect, it } from 'vitest'
import { recommendationColdStartReasons } from '../src/services/recommendationColdStart'
import { recommendationHistoryReasons, recommendationReasonParticipants, type RecommendationHistoryPlace } from '../src/services/recommendationHistoryReasons'
const place = (id: string, rating: number, tags = ['日料']): RecommendationHistoryPlace => ({
  canonicalID: id, ownerRestaurantIDs: [`owner-${id}`], name: id, tags, ratingCount: rating ? 1 : 0, ratingSumOutOfFive: rating,
  visitCount: rating ? 1 : 0, pricePerPerson: null, representativeVisitIDs: rating ? [`visit-${id}`] : [],
})
const candidate = { canonicalID: 'candidate', tags: ['日料'] }
describe('For You cold start and owner evidence details', () => {
  it('has no fallback when no explicit signal exists', () => {
    expect(recommendationColdStartReasons(candidate, [], [])).toEqual([])
    expect(recommendationColdStartReasons(candidate, [place('negative', 1)], [])).toEqual([])
    expect(recommendationColdStartReasons(candidate, [place('positive', 4), place('negative', 1)], [place('want', 0)])).toEqual([])
  })
  it('labels 1–4 positive distinct restaurants as preliminary, never validated preference', () => {
    const result = recommendationColdStartReasons(candidate, [place('one', 4), place('one', 4)], [])
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({ code: 'INITIAL_HISTORY_MATCH', evidence: { sampleCount: 1, source: 'owner_history' } })
    expect(result[0].text).toContain('初步匹配')
    expect(result[0].evidence.participants?.[0]).toMatchObject({ restaurantRecordIDs: ['owner-one'], visitIDs: ['visit-one'] })
    expect(recommendationColdStartReasons(candidate, Array.from({ length: 5 }, (_, index) => place(`${index}`, 4)), [])).toEqual([])
  })
  it('treats wants as intentions without inventing ratings or visits, and excludes self evidence', () => {
    const result = recommendationColdStartReasons(candidate, [], [place('want', 0), place('candidate', 0), place('want', 0)])
    expect(result[0]).toMatchObject({ code: 'WANT_TO_GO_MATCH', evidence: { sampleCount: 1, source: 'owner_want_to_go' } })
    expect(result[0].text).toContain('尚无评分验证')
    expect(result[0].evidence.participants?.[0].visitIDs).toEqual([])
    expect(result[0].evidence.participants?.[0].fields.meanOutOfTen).toBeNull()
  })
  it('does not pad established evidence with initial or wish claims', () => {
    const history = Array.from({ length: 5 }, (_, index) => place(`${index}`, 4))
    expect(recommendationHistoryReasons({ tags: ['日料'], pricePerPerson: null }, history)[0].code).toBe('HIGH_CUISINE_MATCH')
    expect(recommendationColdStartReasons(candidate, history, [place('want', 0)])).toEqual([])
  })
  it('marks limited participant previews and missing complete Visit lists honestly', () => {
    const history = Array.from({ length: 25 }, (_, index) => ({ ...place(`${index}`, 4), visitCount: 10 }))
    const details = recommendationReasonParticipants(history)
    expect(details.participantCount).toBe(25)
    expect(details.participants).toHaveLength(20)
    expect(details.participantsTruncated).toBe(true)
    expect(details.missingFields).toContain('complete_visit_list')
    expect(details.participants?.every(participant => participant.visitIDs.length === 1)).toBe(true)
  })
})
