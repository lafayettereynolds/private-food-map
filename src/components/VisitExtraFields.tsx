import { useState } from 'react'
import { Check, ChevronDown, Plus, Store, Truck, X } from 'lucide-react'
import {
  DINING_MODE_OPTIONS,
  DINING_OCCASION_OPTIONS,
  PAYMENT_MODE_OPTIONS,
  RECOMMENDATION_SOURCE_OPTIONS,
  type DiningDuration,
  type DiningOccasion,
  type NoiseLevel,
  type PaymentMode,
  type PortionLevel,
  type RecommendationSourceType,
  type TransportConvenience,
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
  section = 'all',
}: {
  value: VisitExtraFieldsValue
  onChange: (value: VisitExtraFieldsValue) => void
  friendOptions?: FriendOption[]
  section?: 'all' | 'primary' | 'details'
}) {
  const update = <Key extends keyof VisitExtraFieldsValue>(key: Key, next: VisitExtraFieldsValue[Key]) => {
    onChange({ ...value, [key]: next })
  }

  return (
    <>
      {section !== 'details' ? <section className="visit-essential-fields">
        <div className="visit-choice-row visit-choice-row--single">
          <div className="visit-primary-choice">
            <span>用餐方式</span>
            <div className="segmented-choice" aria-label="用餐方式">
              {DINING_MODE_OPTIONS.map((option) => (
                <button className={value.diningMode === option.value ? 'is-active' : ''} key={option.value} onClick={() => update('diningMode', option.value)} type="button">
                  {option.value === 'dine_in' ? <Store size={14} /> : <Truck size={14} />}{option.label}
                </button>
              ))}
            </div>
          </div>
        </div>
        <ChoiceField allowEmpty emptyLabel="单人消费" label="消费方式" value={value.paymentMode ?? ''} onChange={(next) => update('paymentMode', (next || null) as PaymentMode | null)} options={PAYMENT_MODE_OPTIONS} />
        <TagChoiceField label="性价比" onChange={(next) => update('valueTags', next)} options={['偏贵', '合理', '划算', '超值']} value={value.valueTags} />
        <ChoiceField allowEmpty label="菜量" value={value.portionLevel ?? ''} onChange={(next) => update('portionLevel', (next || null) as PortionLevel | null)} options={[
          { value: 'small', label: '偏少' }, { value: 'normal', label: '正常' }, { value: 'generous', label: '很足' },
        ]} />
        <ChoiceField
          allowEmpty
          label="推荐来源"
          value={value.recommendationSourceType ?? ''}
          onChange={(next) => onChange({
            ...value,
            recommendationSourceType: (next || null) as RecommendationSourceType | null,
            recommendationSourceUserId: next === 'friend' ? value.recommendationSourceUserId : null,
            recommendationSourceText: next === 'other' ? value.recommendationSourceText : '',
          })}
          options={RECOMMENDATION_SOURCE_OPTIONS.map((option) => option.value === 'other' ? { ...option, label: '自定义' } : option)}
        />
        {value.recommendationSourceType === 'friend' && friendOptions.length ? (
          <label className="field"><span>哪位好友推荐</span><select onChange={(event) => update('recommendationSourceUserId', event.target.value || null)} value={value.recommendationSourceUserId ?? ''}><option value="">暂不关联</option>{friendOptions.map((friend) => <option key={friend.id} value={friend.id}>{friend.nickname}</option>)}</select></label>
        ) : null}
        {value.recommendationSourceType === 'other' ? <label className="field"><span>自定义来源</span><input autoFocus maxLength={100} onChange={(event) => update('recommendationSourceText', event.target.value)} placeholder="输入来源名称" value={value.recommendationSourceText} /></label> : null}
      </section> : null}

      {section !== 'primary' ? <details className="more-visit-fields">
        <summary><span>更多记录 <small>全部可选</small></span><ChevronDown size={16} /></summary>
        <div className="more-visit-fields__body">
          <div className="field-grid">
            <div><MultiChoiceField label="适合场景" value={value.diningOccasions} onChange={(next) => onChange({ ...value, diningOccasions: next, diningOccasionText: next.includes('other') ? value.diningOccasionText : '' })} options={DINING_OCCASION_OPTIONS.map((option) => option.value === 'other' ? { ...option, label: '自定义' } : option)} />{value.diningOccasions.includes('other') ? <label className="field inline-custom-field"><span>自定义场景</span><input autoFocus maxLength={30} onChange={(event) => update('diningOccasionText', event.target.value)} placeholder="例如：工作简餐" value={value.diningOccasionText} /></label> : null}</div>
            <ChoiceField allowEmpty label="嘈杂程度" value={value.noiseLevel ?? ''} onChange={(next) => update('noiseLevel', (next || null) as NoiseLevel | null)} options={[
              { value: 'quiet', label: '安静' }, { value: 'normal', label: '正常' }, { value: 'loud', label: '较吵' }, { value: 'very_loud', label: '很吵' },
            ]} />
          </div>
          <TagChoiceField label="服务" onChange={(next) => update('serviceTags', next)} options={['热情', '周到', '主动', '专业', '高效', '冷淡', '缓慢', '打扰过多']} value={value.serviceTags} />
          <TagChoiceField label="环境" onChange={(next) => update('environmentTags', next)} options={['安静', '热闹', '舒适', '拥挤', '宽敞', '精致', '有氛围', '景观好']} value={value.environmentTags} />
          <ChoiceField allowEmpty label="上餐时长" value={value.diningDuration ?? ''} onChange={(next) => update('diningDuration', (next || null) as DiningDuration | null)} options={[
            { value: 'under15', label: '15 分钟以内' }, { value: 'under30', label: '30 分钟以内' }, { value: 'under45', label: '45 分钟以内' }, { value: 'under60', label: '1 小时以内' }, { value: 'under90', label: '1.5 小时以内' }, { value: 'under120', label: '2 小时以内' }, { value: 'over120', label: '超过 2 小时' },
          ]} />
          <ChoiceField allowEmpty label="交通便利度" value={value.transportConvenience ?? ''} onChange={(next) => update('transportConvenience', (next || null) as TransportConvenience | null)} options={[
            { value: 'very_convenient', label: '很方便' }, { value: 'convenient', label: '比较方便' }, { value: 'normal', label: '一般' }, { value: 'inconvenient', label: '不方便' },
          ]} />
          {friendOptions.length ? (
            <fieldset className="friend-meal-picker"><legend>共同饭局 <small>可通知好友补充自己的 Visit</small></legend><div>{friendOptions.map((friend) => {
              const checked = value.sharedParticipantUserIds.includes(friend.id)
              return <label key={friend.id}><input checked={checked} onChange={() => update('sharedParticipantUserIds', checked ? value.sharedParticipantUserIds.filter((id) => id !== friend.id) : [...value.sharedParticipantUserIds, friend.id])} type="checkbox" />{friend.nickname}</label>
            })}</div></fieldset>
          ) : null}
          <label className="field"><span>特殊注意事项</span><textarea maxLength={1000} onChange={(event) => update('specialNotes', event.target.value)} placeholder="最低消费、现场取号、用餐限时或特殊营业规则……" rows={3} value={value.specialNotes} /></label>
        </div>
      </details> : null}
    </>
  )
}

function ChoiceField({ label, value, options, allowEmpty = false, emptyLabel = '不记录', onChange }: { label: string; value: string; options: ReadonlyArray<{ value: string; label: string }>; allowEmpty?: boolean; emptyLabel?: string; onChange: (value: string) => void }) {
  return <fieldset className="direct-choice-field"><legend>{label}</legend><div>{allowEmpty ? <button className={!value ? 'is-active' : ''} onClick={() => onChange('')} type="button">{emptyLabel}</button> : null}{options.map((option) => <button className={value === option.value ? 'is-active' : ''} key={option.value} onClick={() => onChange(option.value)} type="button">{option.label}</button>)}</div></fieldset>
}

function MultiChoiceField({ label, value, options, onChange }: { label: string; value: DiningOccasion[]; options: ReadonlyArray<{ value: DiningOccasion; label: string }>; onChange: (value: DiningOccasion[]) => void }) {
  const toggle = (item: DiningOccasion) => onChange(value.includes(item) ? value.filter((current) => current !== item) : [...value, item])
  return <fieldset className="direct-choice-field multi-choice-field"><legend>{label} <small>可多选</small></legend><div><button className={!value.length ? 'is-active' : ''} onClick={() => onChange([])} type="button">不记录</button>{options.map((option) => <button aria-pressed={value.includes(option.value)} className={value.includes(option.value) ? 'is-active' : ''} key={option.value} onClick={() => toggle(option.value)} type="button">{option.label}</button>)}</div></fieldset>
}

function TagChoiceField({ label, value, options, onChange }: { label: string; value: string[]; options: string[]; onChange: (value: string[]) => void }) {
  const [adding, setAdding] = useState(false)
  const [customValue, setCustomValue] = useState('')
  const customOptions = value.filter((item) => !options.includes(item))
  const toggle = (item: string) => onChange(value.includes(item) ? value.filter((current) => current !== item) : [...value, item])
  const addCustom = () => {
    const normalized = customValue.trim().slice(0, 12)
    if (!normalized) return
    if (!value.includes(normalized)) onChange([...value, normalized])
    setCustomValue('')
    setAdding(false)
  }

  return <fieldset className="experience-tag-field"><legend>{label}</legend><div className="experience-tag-list">{[...options, ...customOptions].map((option) => {
    const selected = value.includes(option)
    return <button className={selected ? 'is-active' : ''} key={option} onClick={() => toggle(option)} type="button">{selected ? <Check size={12} /> : null}{option}{customOptions.includes(option) && selected ? <X size={11} /> : null}</button>
  })}<button className="add-experience-tag" onClick={() => setAdding(true)} type="button"><Plus size={12} /> 自定义</button></div>{adding ? <div className="experience-tag-input"><input autoFocus maxLength={12} onChange={(event) => setCustomValue(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') { event.preventDefault(); addCustom() } }} placeholder={`添加${label}标签`} value={customValue} /><button disabled={!customValue.trim()} onClick={addCustom} type="button">添加</button><button aria-label="取消自定义标签" onClick={() => { setAdding(false); setCustomValue('') }} type="button"><X size={14} /></button></div> : null}</fieldset>
}
