import { RECOMMENDATION_EVIDENCE_POLICY } from './recommendationEvidencePolicy'

const minimumRatings = RECOMMENDATION_EVIDENCE_POLICY.forming.minimumSharedRestaurants
/** Successful, viewer-authorized query evidence. Absence means unknown, never zero. */
export interface DiscoveryEvidenceAvailability {
  personalRatedRestaurantCount: number
  personalScoreStandardDeviationOutOfTen: number
  personalEvidence: 'insufficient' | 'eligible'
  localDirectRestaurantCount: number
}

export type DiscoveryAvailabilityState = 'membership_required' | 'personal_records_needed' | 'personal_variation_needed' | 'city_coverage_needed' | 'unknown'

export interface DiscoveryAvailabilityPresentation {
  state: DiscoveryAvailabilityState
  title: string
  message: string
  actions: Array<'premium' | 'record' | 'city' | 'forYou' | 'retry'>
}

/** Entitlement and evidence are independent axes. Never offer payment as a data repair. */
export function similarTasteAvailability(membership: 'free' | 'member' | undefined, evidence?: DiscoveryEvidenceAvailability | null): DiscoveryAvailabilityPresentation {
  if (membership === 'free') return {
    state: 'membership_required', title: '同味之选需要会员权限',
    message: '会员可查看基于共同餐厅真实评分的同味推荐与依据。推荐仍需要足够的评分记录和当前城市的可见到访；开通会员不会补足缺失的数据。',
    actions: ['premium', 'forYou'],
  }
  if (evidence && validEvidence(evidence)) {
    if (evidence.personalEvidence === 'insufficient') {
      if (evidence.personalRatedRestaurantCount < minimumRatings) return {
        state: 'personal_records_needed', title: '还需要更多餐厅评分',
        message: `目前有 ${evidence.personalRatedRestaurantCount} 家不同餐厅的有效评分，还需至少 ${minimumRatings - evidence.personalRatedRestaurantCount} 家，才能开始寻找共同评分的同味用户。请补充真实到访和评分；达到数量也不保证已有合格同味用户。`,
        actions: ['record', 'forYou'],
      }
      return {
        state: 'personal_variation_needed', title: '现有评分还不能区分口味偏好',
        message: `你已评过 ${evidence.personalRatedRestaurantCount} 家不同餐厅，但代表评分几乎没有变化，暂时无法计算可靠同味度。可以继续补充真实体验，不需要为了匹配而刻意改分。`,
        actions: ['record', 'forYou'],
      }
    }
    if (evidence.localDirectRestaurantCount === 0) return {
      state: 'city_coverage_needed', title: '当前城市尚无足够的直接同味记录',
      message: '你的个人评分已达到初始样本要求，但当前城市尚无可推荐的直接同味到访记录。可以主动切换城市；你的长期口味仍可用于“为你推荐”。',
      actions: ['city', 'forYou'],
    }
  }
  return {
    state: 'unknown', title: '暂未找到可展示的同味推荐',
    message: '当前结果尚不能确认是个人记录不足，还是当地同味覆盖不足。可重试核对、切换城市，或先查看“为你推荐”；不会用普通热门餐厅冒充同味推荐。',
    actions: ['retry', 'city', 'forYou'],
  }
}

function validEvidence(value: DiscoveryEvidenceAvailability) {
  return Number.isSafeInteger(value.personalRatedRestaurantCount) && value.personalRatedRestaurantCount >= 0
    && Number.isFinite(value.personalScoreStandardDeviationOutOfTen) && value.personalScoreStandardDeviationOutOfTen >= 0
    && Number.isSafeInteger(value.localDirectRestaurantCount) && value.localDirectRestaurantCount >= 0
    && (value.personalEvidence === 'eligible' || value.personalEvidence === 'insufficient')
    && (value.personalEvidence !== 'eligible' || (value.personalRatedRestaurantCount >= minimumRatings && value.personalScoreStandardDeviationOutOfTen >= RECOMMENDATION_EVIDENCE_POLICY.minimumStandardDeviationOutOfTen))
    && (value.personalEvidence !== 'insufficient' || value.personalRatedRestaurantCount < minimumRatings || value.personalScoreStandardDeviationOutOfTen < RECOMMENDATION_EVIDENCE_POLICY.minimumStandardDeviationOutOfTen)
}
