/** Optional server attestation; no current production producer emits this field.
 * A heuristic score, record-count milestone or unvalidated model is never a probability.
 */
export interface CalibratedLikeProbability {
  value: number
  modelVersion: string
  calibrationVersion: string
  calibrationStatus: 'validated'
  evidenceStatus: 'sufficient'
  /** Approved target definition supplied by the evaluated model, never inferred from feed eligibility. */
  positiveFeedbackDefinition: string
  definitionVersion: string
  definitionStatus: 'approved'
  validationSampleCount: number
  validUntil: string
}

export interface RecommendationSignalInput {
  /** Historical field name: a similarity/matching index, never a probability. */
  personalTastePercent?: number | null
  calibratedLikeProbability?: CalibratedLikeProbability | null
}

export interface RecommendationSignal {
  mode: 'probability' | 'match'
  percent: number | null
  label: '喜欢概率' | '口味匹配度'
  explanation: string
}

/** Fail closed, including malformed/expired cached payloads. Sufficiency is a
 * model-service decision, not a client threshold over the owner's record count. */
export function recommendationSignal(input: RecommendationSignalInput, now = Date.now()): RecommendationSignal {
  const hasText = (value: unknown): value is string => typeof value === 'string' && Boolean(value.trim())
  const probability = input.calibratedLikeProbability
  if (probability && Number.isFinite(probability.value) && probability.value >= 0 && probability.value <= 1
    && hasText(probability.modelVersion) && hasText(probability.calibrationVersion)
    && probability.calibrationStatus === 'validated' && probability.evidenceStatus === 'sufficient'
    && hasText(probability.positiveFeedbackDefinition) && hasText(probability.definitionVersion)
    && probability.definitionStatus === 'approved'
    && Number.isInteger(probability.validationSampleCount) && probability.validationSampleCount > 0
    && hasText(probability.validUntil) && Date.parse(probability.validUntil) > now) {
    return { mode: 'probability', percent: Math.round(probability.value * 100), label: '喜欢概率',
      explanation: `经校准模型估计的正反馈概率。正反馈定义：${probability.positiveFeedbackDefinition}。` }
  }
  const match = input.personalTastePercent
  const percent = match != null && Number.isFinite(match) && match >= 0 && match <= 100 ? Math.round(match) : null
  return { mode: 'match', percent, label: '口味匹配度', explanation: percent == null
    ? '匹配数据仍在积累；有足够口味依据后显示匹配度。'
    : '根据已有口味记录计算的匹配指数，不代表喜欢这家餐厅的概率。' }
}
