import { describe, expect, it } from 'vitest'
import { recommendationSignal, type CalibratedLikeProbability } from './recommendationSignal'

const now = Date.parse('2026-09-06T00:00:00Z')
// Explicit test-only attestation exercises the reserved channel, not a production model.
const probability: CalibratedLikeProbability = { value: .82, modelVersion: 'test-model', calibrationVersion: 'test-calibration', calibrationStatus: 'validated', evidenceStatus: 'sufficient', positiveFeedbackDefinition: '用户在到访后明确选择喜欢', definitionVersion: 'test-definition', definitionStatus: 'approved', validationSampleCount: 800, validUntil: '2026-09-07T00:00:00Z' }
describe('honest recommendation signals', () => {
  it('always treats a heuristic percentage as match even at 100', () => {
    for (const value of [0, 20, 88, 100]) expect(recommendationSignal({ personalTastePercent: value }, now)).toMatchObject({ mode: 'match', percent: value, label: '口味匹配度' })
    expect(recommendationSignal({}, now)).toMatchObject({ mode: 'match', percent: null })
  })
  it('prioritizes a validated, sufficiently supported, unexpired probability with an approved explicit target', () => {
    expect(recommendationSignal({ personalTastePercent: 96, calibratedLikeProbability: probability }, now)).toMatchObject({ mode: 'probability', percent: 82, label: '喜欢概率' })
    expect(recommendationSignal({ calibratedLikeProbability: probability }, now).explanation).toContain(probability.positiveFeedbackDefinition)
  })
  it.each([
    { value: NaN }, { value: -0.1 }, { value: 1.1 }, { calibrationStatus: 'unvalidated' }, { evidenceStatus: 'insufficient' },
    { modelVersion: '' }, { calibrationVersion: '' }, { definitionStatus: 'draft' }, { definitionVersion: '' }, { positiveFeedbackDefinition: '' },
    { validationSampleCount: 0 }, { validationSampleCount: 3.5 }, { validUntil: 'invalid' }, { validUntil: '2026-09-06T00:00:00Z' },
  ])('falls back on incomplete or invalid attestation %j', patch => {
    const untrusted = { ...probability, ...patch } as CalibratedLikeProbability
    expect(recommendationSignal({ personalTastePercent: 67, calibratedLikeProbability: untrusted }, now)).toMatchObject({ mode: 'match', percent: 67 })
  })
  it('does not clamp invalid matching scores or infer a missing percentage', () => {
    for (const value of [-1, 101, NaN, Infinity]) expect(recommendationSignal({ personalTastePercent: value }, now).percent).toBeNull()
  })
})
