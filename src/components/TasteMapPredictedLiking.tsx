import { useState } from 'react'
import type { PredictedLiking } from '../contracts/predictedLiking'
import { ModalShell } from './ModalShell'

/** A predicted rating has its own label/unit; never relabel match as likelihood. */
export function TasteMapPredictedLiking({ value }: { value?: PredictedLiking | null }) {
  const [open, setOpen] = useState(false)
  const score = value?.method === 'owner_history_weighted_rating_v1'
    && Number.isInteger(value.ratedRestaurantCount) && value.ratedRestaurantCount > 0
    && value.scoreOutOfTen != null && Number.isFinite(value.scoreOutOfTen)
    && value.scoreOutOfTen >= 0 && value.scoreOutOfTen <= 10 ? value.scoreOutOfTen : null
  const label = `预计喜欢度 ${score == null ? '积累中' : `${score.toFixed(1)} / 10`}`
  return <><button className="tm-predicted-liking" aria-label={`${label}，查看说明`} aria-haspopup="dialog" type="button" onClick={() => setOpen(true)}>{label}</button>
    {open ? <ModalShell title="预计喜欢度" eyebrow={null} size="small" onClose={() => setOpen(false)}>
      <p>{score == null ? '目前没有足够的历史评分可供推算。' : `基于你自己的 ${value!.ratedRestaurantCount} 家餐厅评分，结合相近菜系、价位和城市推算。`}</p>
      <p>这是预计你会给出的评分，不是你已经打过的分数，也不是喜欢概率。口味匹配度单独表示匹配程度。</p>
    </ModalShell> : null}</>
}
