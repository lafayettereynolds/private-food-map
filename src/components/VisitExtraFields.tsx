import { ChevronDown, Eye, Store, Truck } from 'lucide-react'
import {
  DINING_MODE_OPTIONS,
  DINING_OCCASION_OPTIONS,
  PAYMENT_MODE_OPTIONS,
  RECOMMENDATION_SOURCE_OPTIONS,
  VISIBILITY_OPTIONS,
  type DiningDuration,
  type DiningOccasion,
  type NoiseLevel,
  type PaymentMode,
  type PortionLevel,
  type RecommendationSourceType,
  type StarRating,
  type TransportConvenience,
  type Visibility,
} from '../types/domain'
import type { VisitExtraFieldsValue } from '../types/visitExtras'

interface FriendOption {
  id: string
  nickname: string
}

export function VisitExtraFields({
  value,
  onChange,
  friendOptions = [],
}: {
  value: VisitExtraFieldsValue
  onChange: (value: VisitExtraFieldsValue) => void
  friendOptions?: FriendOption[]
}) {
  const update = <Key extends keyof VisitExtraFieldsValue>(key: Key, next: VisitExtraFieldsValue[Key]) => {
    onChange({ ...value, [key]: next })
  }

  return (
    <>
      <div className="visit-choice-row">
        <div>
          <span>用餐方式</span>
          <div className="segmented-choice" aria-label="用餐方式">
            {DINING_MODE_OPTIONS.map((option) => (
              <button className={value.diningMode === option.value ? 'is-active' : ''} key={option.value} onClick={() => update('diningMode', option.value)} type="button">
                {option.value === 'dine_in' ? <Store size={14} /> : <Truck size={14} />}{option.label}
              </button>
            ))}
          </div>
        </div>
        <div>
          <span>谁可以看</span>
          <label className="compact-select-with-icon"><Eye size={14} /><select aria-label="记录可见范围" onChange={(event) => update('visibility', event.target.value as Visibility)} value={value.visibility}>
            {VISIBILITY_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select></label>
        </div>
      </div>

      <details className="more-visit-fields">
        <summary><span>更多记录 <small>全部可选</small></span><ChevronDown size={16} /></summary>
        <div className="more-visit-fields__body">
          <div className="field-grid">
            <SelectField label="消费方式" value={value.paymentMode ?? ''} onChange={(next) => update('paymentMode', (next || null) as PaymentMode | null)} options={PAYMENT_MODE_OPTIONS} />
            <label className="field"><span>我的实际消费（元）</span><input inputMode="decimal" min="0" onChange={(event) => update('myActualSpend', event.target.value)} placeholder="可独立于总价填写" step="0.01" type="number" value={value.myActualSpend} /></label>
          </div>
          <div className="field-grid">
            <SelectField label="用餐场景" value={value.diningOccasion ?? ''} onChange={(next) => update('diningOccasion', (next || null) as DiningOccasion | null)} options={DINING_OCCASION_OPTIONS} />
            <SelectField label="嘈杂程度" value={value.noiseLevel ?? ''} onChange={(next) => update('noiseLevel', (next || null) as NoiseLevel | null)} options={[
              { value: 'quiet', label: '安静' }, { value: 'normal', label: '正常' }, { value: 'loud', label: '较吵' }, { value: 'very_loud', label: '很吵' },
            ]} />
          </div>
          <div className="optional-rating-grid">
            <OptionalRating label="性价比" value={value.valueRating} onChange={(next) => update('valueRating', next)} />
            <OptionalRating label="环境" value={value.environmentRating} onChange={(next) => update('environmentRating', next)} />
            <OptionalRating label="服务" value={value.serviceRating} onChange={(next) => update('serviceRating', next)} />
          </div>
          <div className="field-grid">
            <SelectField label="实际用餐时长" value={value.diningDuration ?? ''} onChange={(next) => update('diningDuration', (next || null) as DiningDuration | null)} options={[
              { value: 'under30', label: '30 分钟以内' }, { value: 'under60', label: '1 小时以内' }, { value: 'under90', label: '1.5 小时以内' }, { value: 'under120', label: '2 小时以内' }, { value: 'over120', label: '超过 2 小时' },
            ]} />
            <SelectField label="菜量 / 饱腹程度" value={value.portionLevel ?? ''} onChange={(next) => update('portionLevel', (next || null) as PortionLevel | null)} options={[
              { value: 'small', label: '偏少' }, { value: 'normal', label: '正常' }, { value: 'generous', label: '很足' },
            ]} />
          </div>
          <SelectField label="交通便利度" value={value.transportConvenience ?? ''} onChange={(next) => update('transportConvenience', (next || null) as TransportConvenience | null)} options={[
            { value: 'very_convenient', label: '很方便' }, { value: 'convenient', label: '比较方便' }, { value: 'normal', label: '一般' }, { value: 'inconvenient', label: '不方便' },
          ]} />
          <div className="field-grid">
            <SelectField label="我是怎么知道的" value={value.recommendationSourceType ?? ''} onChange={(next) => update('recommendationSourceType', (next || null) as RecommendationSourceType | null)} options={RECOMMENDATION_SOURCE_OPTIONS} />
            {value.recommendationSourceType === 'friend' && friendOptions.length ? (
              <label className="field"><span>哪位好友推荐</span><select onChange={(event) => update('recommendationSourceUserId', event.target.value || null)} value={value.recommendationSourceUserId ?? ''}><option value="">暂不关联</option>{friendOptions.map((friend) => <option key={friend.id} value={friend.id}>{friend.nickname}</option>)}</select></label>
            ) : <label className="field"><span>来源补充</span><input maxLength={100} onChange={(event) => update('recommendationSourceText', event.target.value)} placeholder="账号、链接或其他说明" value={value.recommendationSourceText} /></label>}
          </div>
          {friendOptions.length ? (
            <fieldset className="friend-meal-picker"><legend>共同饭局 <small>可通知好友补充自己的 Visit</small></legend><div>{friendOptions.map((friend) => {
              const checked = value.sharedParticipantUserIds.includes(friend.id)
              return <label key={friend.id}><input checked={checked} onChange={() => update('sharedParticipantUserIds', checked ? value.sharedParticipantUserIds.filter((id) => id !== friend.id) : [...value.sharedParticipantUserIds, friend.id])} type="checkbox" />{friend.nickname}</label>
            })}</div></fieldset>
          ) : null}
          <label className="field"><span>特殊注意事项</span><textarea maxLength={1000} onChange={(event) => update('specialNotes', event.target.value)} placeholder="最低消费、现场取号、用餐限时或特殊营业规则……" rows={3} value={value.specialNotes} /></label>
        </div>
      </details>
    </>
  )
}

function OptionalRating({ label, value, onChange }: { label: string; value: StarRating | null; onChange: (value: StarRating | null) => void }) {
  return <div className="optional-rating"><span>{label}</span><div><button className={value === null ? 'is-active' : ''} onClick={() => onChange(null)} type="button">—</button>{([1, 2, 3, 4, 5] as StarRating[]).map((rating) => <button className={value === rating ? 'is-active' : ''} key={rating} onClick={() => onChange(rating)} type="button">{rating}</button>)}</div></div>
}

function SelectField({ label, value, options, onChange }: { label: string; value: string; options: Array<{ value: string; label: string }>; onChange: (value: string) => void }) {
  return <label className="field"><span>{label}</span><select onChange={(event) => onChange(event.target.value)} value={value}><option value="">未记录</option>{options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
}
