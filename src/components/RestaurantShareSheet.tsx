import { Copy, ExternalLink, ImageOff, Share2 } from 'lucide-react'
import type { RestaurantShareModel } from '../services/restaurantShare'
import { ModalShell } from './ModalShell'

export function RestaurantShareSheet({ model, canSystemShare, busy, message, onClose, onCopy, onSystemShare }: {
  model: RestaurantShareModel
  canSystemShare: boolean
  busy: boolean
  message: string
  onClose: () => void
  onCopy: () => void
  onSystemShare: () => void
}) {
  const details = [model.cuisines.join(' · '), model.pricePerPerson ? `参考人均 ¥${Math.round(model.pricePerPerson)}` : '', model.city].filter(Boolean)
  return <ModalShell description="分享的是餐厅公开信息，不包含你的到访、好友或个性化推荐依据。" onClose={onClose} size="small" title="分享餐厅">
    <div className="restaurant-share-sheet">
      <section className="restaurant-share-preview" aria-label="分享预览">
        {model.coverImageUrl ? <img alt="" src={model.coverImageUrl} /> : <div className="restaurant-share-preview__placeholder"><ImageOff size={25} /><span>暂无餐厅封面</span></div>}
        <div><strong>{model.name}</strong>{details.length ? <p>{details.join(' · ')}</p> : null}<span>{model.address}</span>{model.publicRating ? <small>全部用户 {model.publicRating.value.toFixed(1)} · {model.publicRating.sampleCount} 人{model.publicRating.confidence === 'low' ? ' · 样本较少' : ''}</small> : null}</div>
      </section>
      <div className="restaurant-share-actions">
        {canSystemShare ? <button disabled={busy} onClick={onSystemShare} type="button"><Share2 size={18} /><span>系统分享</span></button> : null}
        <button disabled={busy} onClick={onCopy} type="button"><Copy size={18} /><span>复制链接</span></button>
      </div>
      <a className="restaurant-share-link" href={model.url} rel="noreferrer" target="_blank"><ExternalLink size={14} />预览公开餐厅页</a>
      {message ? <p aria-live="polite" className="restaurant-share-status">{message}</p> : null}
    </div>
  </ModalShell>
}
