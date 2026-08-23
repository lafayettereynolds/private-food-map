import { useState, type FormEvent } from 'react'
import { CalendarClock, LoaderCircle, Users, WalletCards } from 'lucide-react'
import { CompanionPicker } from './CompanionPicker'
import { DishEditor } from './DishEditor'
import { ModalShell } from './ModalShell'
import { QueueDurationPicker } from './QueueDurationPicker'
import { StarRating } from './StarRating'
import { VisitPhotoPicker } from './VisitPhotoPicker'
import { VisitExtraFields } from './VisitExtraFields'
import { createDefaultVisitExtraFields, type VisitExtraFieldsValue } from '../types/visitExtras'
import type { AddVisitInput } from '../db/restaurants'
import {
  calculatePricePerPerson,
  nearestStar,
  type QueueDuration,
  type RestaurantSummary,
  type StarRating as StarRatingValue,
  type Visit,
  type VisitDish,
} from '../types/domain'
import { currentDateAndTime, dateAndTimeFromIso, localDateTimeToIso } from '../utils/date'
import { splitCompanions } from '../utils/companions'

interface AddVisitModalProps {
  companionOptions: string[]
  friendOptions?: Array<{ id: string; nickname: string }>
  initialVisit?: Visit
  restaurant: RestaurantSummary
  onClose: () => void
  onSave: (input: AddVisitInput) => Promise<void>
}

export function AddVisitModal({ companionOptions, friendOptions = [], initialVisit, restaurant, onClose, onSave }: AddVisitModalProps) {
  const initialTime = initialVisit ? dateAndTimeFromIso(initialVisit.visitedAt) : currentDateAndTime()
  const [date, setDate] = useState(initialTime.date)
  const [time, setTime] = useState(initialTime.time)
  const [rating, setRating] = useState<StarRatingValue>(initialVisit?.rating ?? nearestStar(restaurant.averageRating) ?? 5)
  const [price, setPrice] = useState((initialVisit?.paymentMode === 'separate' ? initialVisit.myActualSpend : initialVisit?.totalPrice)?.toString() ?? '')
  const [companions, setCompanions] = useState(initialVisit?.companions.join('、') ?? '')
  const [partySize, setPartySize] = useState(initialVisit?.partySize.toString() ?? '1')
  const [queueDuration, setQueueDuration] = useState<QueueDuration>(initialVisit?.queueDuration ?? 'none')
  const [dishes, setDishes] = useState<VisitDish[]>(() => initialVisit?.dishes.map((dish) => ({ ...dish })) ?? [])
  const [feeling, setFeeling] = useState(initialVisit?.note ?? '')
  const [photos, setPhotos] = useState<string[]>(() => [...(initialVisit?.photos ?? [])])
  const [photoIds, setPhotoIds] = useState<Array<string | null>>(() => [...(initialVisit?.photoIds ?? [])])
  const [extraFields, setExtraFields] = useState<VisitExtraFieldsValue>(() => initialVisit ? {
    visibility: initialVisit.visibility ?? 'private',
    diningMode: initialVisit.diningMode ?? 'dine_in',
    myActualSpend: initialVisit.myActualSpend?.toString() ?? '',
    paymentMode: initialVisit.paymentMode ?? null,
    diningOccasions: initialVisit.diningOccasions?.length ? initialVisit.diningOccasions : initialVisit.diningOccasion ? [initialVisit.diningOccasion] : [],
    diningOccasionText: initialVisit.diningOccasionText ?? '',
    valueRating: initialVisit.valueRating ?? null,
    environmentRating: initialVisit.environmentRating ?? null,
    serviceRating: initialVisit.serviceRating ?? null,
    valueTags: initialVisit.valueTags ?? [],
    environmentTags: initialVisit.environmentTags ?? [],
    serviceTags: initialVisit.serviceTags ?? [],
    noiseLevel: initialVisit.noiseLevel ?? null,
    diningDuration: initialVisit.diningDuration ?? null,
    portionLevel: initialVisit.portionLevel ?? null,
    transportConvenience: initialVisit.transportConvenience ?? null,
    specialNotes: initialVisit.specialNotes ?? '',
    recommendationSourceType: initialVisit.recommendationSourceType ?? null,
    recommendationSourceUserId: initialVisit.recommendationSourceUserId ?? null,
    recommendationSourceText: initialVisit.recommendationSourceText ?? '',
    sharedParticipantUserIds: [],
  } : createDefaultVisitExtraFields())

  function updateCompanions(next: string) {
    const previousCount = splitCompanions(companions).length
    const nextCount = splitCompanions(next).length
    setCompanions(next)
    setPartySize((current) => String(Math.max(1, (Number(current) || 1) + nextCount - previousCount)))
  }
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    const numericPrice = price ? Number(price) : null
    if (numericPrice !== null && (!Number.isFinite(numericPrice) || numericPrice < 0)) {
      setError(extraFields.paymentMode === 'separate' ? '请输入正确的个人消费金额。' : '请输入正确的消费总价。')
      return
    }
    const numericPartySize = Number(partySize)
    if (!Number.isInteger(numericPartySize) || numericPartySize < 1) {
      setError('用餐人数至少为 1 人。')
      return
    }
    const isSeparatePayment = extraFields.paymentMode === 'separate'
    setSaving(true)
    setError('')
    try {
      await onSave({
        visitedAt: localDateTimeToIso(date, time),
        rating,
        visibility: extraFields.visibility,
        diningMode: extraFields.diningMode,
        totalPrice: isSeparatePayment ? null : numericPrice,
        myActualSpend: isSeparatePayment ? numericPrice : null,
        paymentMode: extraFields.paymentMode,
        partySize: numericPartySize,
        queueDuration,
        diningOccasions: extraFields.diningOccasions,
        diningOccasion: extraFields.diningOccasions[0] ?? null,
        diningOccasionText: extraFields.diningOccasionText,
        valueRating: extraFields.valueRating,
        environmentRating: extraFields.environmentRating,
        serviceRating: extraFields.serviceRating,
        valueTags: extraFields.valueTags,
        environmentTags: extraFields.environmentTags,
        serviceTags: extraFields.serviceTags,
        noiseLevel: extraFields.noiseLevel,
        diningDuration: extraFields.diningDuration,
        portionLevel: extraFields.portionLevel,
        transportConvenience: extraFields.transportConvenience,
        specialNotes: extraFields.specialNotes,
        recommendationSourceType: extraFields.recommendationSourceType,
        recommendationSourceUserId: extraFields.recommendationSourceUserId,
        recommendationSourceText: extraFields.recommendationSourceText,
        sharedParticipantUserIds: extraFields.sharedParticipantUserIds,
        companions: splitCompanions(companions),
        dishes,
        note: feeling,
        photos,
        photoIds,
      })
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : '保存失败，请稍后重试。')
    } finally {
      setSaving(false)
    }
  }

  return (
    <ModalShell
      title={initialVisit ? '编辑到访记录' : '记录一次到访'}
      description={initialVisit ? `修改 ${restaurant.name} 的这次到访，保存后会更新原记录。` : `为 ${restaurant.name} 增加一条真实到访记录。`}
      onClose={onClose}
    >
      <form className="editor-form" onSubmit={handleSubmit}>
        <label className="field visit-feeling-field visit-note-primary"><span>笔记 <small>可选</small></span><textarea maxLength={1000} onChange={(event) => setFeeling(event.target.value)} placeholder="味道、氛围、当时的心情……想记多少都可以" rows={3} value={feeling} /></label>
        <label className="field"><span>本次个人评价</span><StarRating onChange={setRating} value={rating} /></label>
        <VisitExtraFields friendOptions={friendOptions} onChange={setExtraFields} section="primary" value={extraFields} />
        <div className="field-grid visit-time-grid">
          <label className="field field-with-leading-icon"><span>日期</span><div><CalendarClock size={16} /><input onChange={(event) => setDate(event.target.value)} required type="date" value={date} /></div></label>
          <label className="field"><span>时间</span><input onChange={(event) => setTime(event.target.value)} required type="time" value={time} /></label>
        </div>
        <label className="field field-with-leading-icon"><span>{extraFields.paymentMode === 'separate' ? '我的消费金额（元）' : '本次消费总价（元）'}</span><div><WalletCards size={16} /><input inputMode="decimal" min="0" onChange={(event) => setPrice(event.target.value)} placeholder="例如 193.50" step="0.01" type="number" value={price} /></div>{extraFields.paymentMode !== 'separate' && calculatePricePerPerson(price ? Number(price) : null, Number(partySize)) !== null ? <small className="price-calculation">{partySize} 人 · 约 ¥{calculatePricePerPerson(Number(price), Number(partySize))}/人</small> : null}</label>
        <div className="field-grid party-grid">
          <label className="field field-with-leading-icon"><span>用餐人数</span><div><Users size={16} /><input min="1" onChange={(event) => setPartySize(event.target.value)} required step="1" type="number" value={partySize} /></div></label>
          <CompanionPicker onChange={updateCompanions} options={companionOptions} value={companions} />
        </div>
        <QueueDurationPicker onChange={setQueueDuration} value={queueDuration} />
        <VisitPhotoPicker onChange={(nextPhotos, nextPhotoIds) => { setPhotos(nextPhotos); setPhotoIds(nextPhotoIds) }} photoIds={photoIds} value={photos} />
        <DishEditor onChange={setDishes} value={dishes} />
        <VisitExtraFields friendOptions={friendOptions} onChange={setExtraFields} section="details" value={extraFields} />
        {error ? <p className="form-error">{error}</p> : null}
        <footer className="modal-actions"><button className="secondary-button" onClick={onClose} type="button">取消</button><button className="primary-button" disabled={saving} type="submit">{saving ? <LoaderCircle className="spin" size={17} /> : null} {initialVisit ? '保存修改' : '保存到访'}</button></footer>
      </form>
    </ModalShell>
  )
}
