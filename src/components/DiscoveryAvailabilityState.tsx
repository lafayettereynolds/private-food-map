import { similarTasteAvailability, type DiscoveryEvidenceAvailability } from '../contracts/discoveryAvailability'
import { HybridState } from './TasteMapHybridShared'

export function DiscoveryAvailabilityState({ membership, evidence, onPremium, onRecord, onCity, onForYou, onRetry }: {
  membership?: 'free' | 'member'
  evidence?: DiscoveryEvidenceAvailability | null
  onPremium?: () => void
  onRecord?: () => void
  onCity: () => void
  onForYou: () => void
  onRetry?: () => void
}) {
  const state = similarTasteAvailability(membership, evidence)
  const actions = {
    premium: { label: '查看会员权益', run: onPremium }, record: { label: '补充到访与评分', run: onRecord },
    city: { label: '切换城市', run: onCity }, forYou: { label: '查看为你推荐', run: onForYou }, retry: { label: '重新核对', run: onRetry },
  }
  return <div data-discovery-availability={state.state}>
    <HybridState kind="empty" title={state.title} message={state.message} action={<div className="tm-discovery-availability-actions">{state.actions.map((key) => {
      const action = actions[key]
      return action.run ? <button key={key} type="button" onClick={action.run}>{action.label}</button> : null
    })}</div>} />
  </div>
}
