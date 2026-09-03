import { useState, type FormEvent } from 'react'
import { CalendarClock, Users, WalletCards } from 'lucide-react'
import { CompanionPicker } from './CompanionPicker'
import { DishEditor } from './DishEditor'
import { ModalShell } from './ModalShell'
import { StickyFormActionBar } from './StickyFormActionBar'
import { QueueDurationPicker } from './QueueDurationPicker'
import { StarRatingField } from './StarRating'
import { VisitPhotoPicker } from './VisitPhotoPicker'
import { VisitExtraFields } from './VisitExtraFields'
import { RestaurantSummarySection } from './RestaurantRecordSummary'
import { createDefaultVisitExtraFields, type VisitExtraFieldsValue } from '../types/visitExtras'
import type { AddVisitInput } from '../db/restaurants'
import {
  calculatePricePerPerson,
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
  maxPhotos?: number
  photoUpgradeAvailable?: boolean
  restaurant: RestaurantSummary
  onClose: () => void
  onDelete?: () => Promise<void>
  onSave: (input: AddVisitInput) => Promise<void>
  onPickNativePhotos?: (availableSlots: number) => Promise<Array<{ source: string; photoID: string }>>
  onCaptureNativePhoto?: () => Promise<{ source: string; photoID: string } | null>
  onRemoveNativePhoto?: (photoID: string) => Promise<void>
}

export function AddVisitModal({ companionOptions, friendOptions = [], initialVisit, maxPhotos = 20, photoUpgradeAvailable = false, restaurant, onClose, onDelete, onSave, onPickNativePhotos, onCaptureNativePhoto, onRemoveNativePhoto }: AddVisitModalProps) {
  const initialTime = initialVisit ? dateAndTimeFromIso(initialVisit.visitedAt) : currentDateAndTime()
  const [date, setDate] = useState(initialTime.date)
  const [time, setTime] = useState(initialTime.time)
  const [rating, setRating] = useState<StarRatingValue | null>(initialVisit?.rating ?? null)
  const [price, setPrice] = useState((initialVisit?.paymentMode === 'separate' ? initialVisit.myActualSpend : initialVisit?.totalPrice)?.toString() ?? '')
  const [companions, setCompanions] = useState(initialVisit?.companions.join('、') ?? '')
  const [partySize, setPartySize] = useState(initialVisit?.partySize?.toString() ?? '1')
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
    setDirty(true)
  }
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [dirty, setDirty] = useState(false)
  const [nativeDraftPhotoIDs, setNativeDraftPhotoIDs] = useState<string[]>([])

  async function pickNativePhotos(availableSlots: number) {
    if (!onPickNativePhotos) return []
    const selected = await onPickNativePhotos(availableSlots)
    setNativeDraftPhotoIDs((current) => [...new Set([...current, ...selected.map((photo) => photo.photoID)])])
    setDirty(true)
    return selected
  }

  async function removeNativePhoto(photoID: string) {
    if (!onRemoveNativePhoto) return
    await onRemoveNativePhoto(photoID)
    setNativeDraftPhotoIDs((current) => current.filter((value) => value !== photoID))
    setDirty(true)
  }

  async function captureNativePhoto() {
    if (!onCaptureNativePhoto) return null
    const selected = await onCaptureNativePhoto()
    if (selected) {
      setNativeDraftPhotoIDs((current) => [...new Set([...current, selected.photoID])])
      setDirty(true)
    }
    return selected
  }

  async function closeEditor() {
    if (dirty && !window.confirm('放弃尚未保存的修改？')) return
    if (onRemoveNativePhoto) {
      await Promise.allSettled(nativeDraftPhotoIDs.map((photoID) => onRemoveNativePhoto(photoID)))
    }
    onClose()
  }

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
        pendingNativePhotos: [
          ...photoIds.flatMap((photoID) => photoID ? [{ photoID, dishDraftID: null }] : []),
          ...dishes.flatMap((dish) => dish.photoId ? [{ photoID: dish.photoId, dishDraftID: dish.id }] : []),
        ],
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
      onClose={() => { void closeEditor() }}
    >
      <form className="sticky-action-form" onChange={() => setDirty(true)} onSubmit={handleSubmit}>
        <div className="editor-form sticky-action-form__content">
        <RestaurantSummarySection
          additionalUserPhotos={photos.map((source, index) => ({ source, photoId: photoIds[index] }))}
          className="is-form-summary"
          historyRestaurants={[restaurant]}
          restaurant={restaurant}
        />
        <div className="restaurant-record-form-divider"><span>{initialVisit ? '修改这次到访' : '这次到访'}</span></div>
        <label className="field visit-feeling-field visit-note-primary"><span>笔记 <small>可选</small></span><textarea aria-label="到访笔记" maxLength={1000} onChange={(event) => setFeeling(event.target.value)} placeholder="味道、氛围、当时的心情……想记多少都可以" rows={3} value={feeling} /></label>
        <StarRatingField onChange={(value) => { setRating(value); setDirty(true) }} value={rating} />
        <VisitExtraFields friendOptions={friendOptions} onChange={(value) => { setExtraFields(value); setDirty(true) }} section="primary" value={extraFields} />
        <div className="field-grid visit-time-grid">
          <label className="field field-with-leading-icon"><span>日期</span><div><CalendarClock size={16} /><input onChange={(event) => setDate(event.target.value)} required type="date" value={date} /></div></label>
          <label className="field"><span>时间</span><input onChange={(event) => setTime(event.target.value)} required type="time" value={time} /></label>
        </div>
        <label className="field field-with-leading-icon"><span>{extraFields.paymentMode === 'separate' ? '我的消费金额（元）' : '本次消费总价（元）'}</span><div><WalletCards size={16} /><input inputMode="decimal" min="0" onChange={(event) => setPrice(event.target.value)} placeholder="例如 193.50" step="0.01" type="number" value={price} /></div>{extraFields.paymentMode !== 'separate' && calculatePricePerPerson(price ? Number(price) : null, Number(partySize)) !== null ? <small className="price-calculation">{partySize} 人 · 约 ¥{calculatePricePerPerson(Number(price), Number(partySize))}/人</small> : null}</label>
        <div className="field-grid party-grid">
          <label className="field field-with-leading-icon"><span>用餐人数</span><div><Users size={16} /><input min="1" onChange={(event) => setPartySize(event.target.value)} required step="1" type="number" value={partySize} /></div></label>
          <CompanionPicker onChange={updateCompanions} options={companionOptions} value={companions} />
        </div>
        <QueueDurationPicker onChange={(value) => { setQueueDuration(value); setDirty(true) }} value={queueDuration} />
        <VisitPhotoPicker maxPhotos={maxPhotos} onCaptureNative={onCaptureNativePhoto ? captureNativePhoto : undefined} onChange={(nextPhotos, nextPhotoIds) => { setPhotos(nextPhotos); setPhotoIds(nextPhotoIds); setDirty(true) }} onPickNative={onPickNativePhotos ? pickNativePhotos : undefined} onRemoveNative={onRemoveNativePhoto ? removeNativePhoto : undefined} photoIds={photoIds} upgradeAvailable={photoUpgradeAvailable} value={photos} />
        <DishEditor onChange={(value) => { setDishes(value); setDirty(true) }} onPickNativePhoto={onPickNativePhotos ? async () => (await pickNativePhotos(1))[0] ?? null : undefined} onRemoveNativePhoto={onRemoveNativePhoto ? removeNativePhoto : undefined} value={dishes} />
        <VisitExtraFields friendOptions={friendOptions} onChange={(value) => { setExtraFields(value); setDirty(true) }} section="details" value={extraFields} />
        {initialVisit && onDelete ? <button className="danger-ghost-button visit-delete-action" disabled={saving} onClick={() => {
          if (!window.confirm('删除这次到访记录？这不会删除餐厅。')) return
          setSaving(true)
          setError('')
          void onDelete().catch((reason) => {
            setError(reason instanceof Error ? reason.message : '删除失败，请稍后重试。')
          }).finally(() => setSaving(false))
        }} type="button">删除这次到访</button> : null}
        </div>
        <StickyFormActionBar
          primaryLabel={initialVisit ? '保存修改' : '保存到我的地图'}
          primaryLoading={saving}
          secondaryAction={() => { void closeEditor() }}
          statusMessage={error}
          statusTone="error"
        />
      </form>
    </ModalShell>
  )
}
