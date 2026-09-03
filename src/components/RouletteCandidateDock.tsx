import { Dices, X } from 'lucide-react'

export interface RouletteDockCandidate {
  id: string
  name: string
}

export function RouletteCandidateDock({ candidates, expanded, onExpandedChange, onRemove, onClear, onOpen }: {
  candidates: RouletteDockCandidate[]
  expanded: boolean
  onExpandedChange: (expanded: boolean) => void
  onRemove: (id: string) => void
  onClear: () => void
  onOpen: () => void
}) {
  if (!candidates.length) return null

  return <aside className="wheel-candidate-bar" aria-label="抽签候选" data-product-contract="map-roulette-candidate-dock">
    <strong>已选 {candidates.length}/10</strong>
    <button aria-expanded={expanded} onClick={() => onExpandedChange(!expanded)} type="button">查看</button>
    <button
      className="is-primary"
      disabled={candidates.length < 2}
      onClick={onOpen}
      title={candidates.length < 2 ? '至少选择 2 家餐厅' : '开始抽'}
      type="button"
    ><Dices aria-hidden="true" size={15} /> 开始抽</button>
    {expanded ? <div className="wheel-candidate-popover">
      <header><strong>当前候选</strong><button onClick={onClear} type="button">清空</button></header>
      <div>{candidates.map((item) => <span key={item.id}>{item.name}<button aria-label={`移除 ${item.name}`} onClick={() => onRemove(item.id)} type="button"><X aria-hidden="true" size={12} /></button></span>)}</div>
      {candidates.length < 2 ? <p>至少再选 1 家餐厅才能开始抽</p> : null}
    </div> : null}
  </aside>
}
