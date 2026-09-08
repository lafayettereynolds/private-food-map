import { describe, expect, it } from 'vitest'
import { similarTasteAvailability, type DiscoveryEvidenceAvailability } from './discoveryAvailability'

const sufficient: DiscoveryEvidenceAvailability = { personalRatedRestaurantCount: 10, personalScoreStandardDeviationOutOfTen: 1, personalEvidence: 'eligible', localDirectRestaurantCount: 0 }
describe('membership does not replace recommendation evidence', () => {
  it('explains actual membership and data requirements without guaranteeing results', () => {
    const state = similarTasteAvailability('free', sufficient)
    expect(state.state).toBe('membership_required')
    expect(state.actions).toContain('premium')
    expect(state.message).toContain('开通会员不会补足缺失的数据')
  })
  it('tells a member the actual number of missing distinct restaurant ratings', () => {
    const state = similarTasteAvailability('member', { ...sufficient, personalRatedRestaurantCount: 2, personalEvidence: 'insufficient' })
    expect(state.state).toBe('personal_records_needed')
    expect(state.message).toContain('还需至少 3 家')
    expect(state.actions).toContain('record')
    expect(state.actions).not.toContain('premium')
  })
  it('does not ask flat-rating users to manufacture scoring variation', () => {
    const state = similarTasteAvailability('member', { ...sufficient, personalScoreStandardDeviationOutOfTen: 0, personalEvidence: 'insufficient' })
    expect(state.state).toBe('personal_variation_needed')
    expect(state.message).toContain('不需要为了匹配而刻意改分')
  })
  it('routes personal-ready / city-empty users to city and For You, never purchase', () => {
    const state = similarTasteAvailability('member', sufficient)
    expect(state.state).toBe('city_coverage_needed')
    expect(state.actions).toEqual(['city', 'forYou'])
  })
  it.each([undefined, { ...sufficient, personalRatedRestaurantCount: NaN }, { ...sufficient, personalRatedRestaurantCount: 0 }, { ...sufficient, localDirectRestaurantCount: -1 }])('missing or corrupt evidence is unknown, not zero', (evidence) => {
    expect(similarTasteAvailability('member', evidence).state).toBe('unknown')
  })
  it('does not infer membership from absent profile data', () => {
    expect(similarTasteAvailability(undefined).actions).not.toContain('premium')
  })
  it('does not call positive local coverage insufficient', () => {
    expect(similarTasteAvailability('member', { ...sufficient, localDirectRestaurantCount: 2 }).state).toBe('unknown')
  })
  it('contradictory sufficient statistics do not invent flat scores', () => {
    expect(similarTasteAvailability('member', { ...sufficient, personalEvidence: 'insufficient' }).state).toBe('unknown')
  })
})
