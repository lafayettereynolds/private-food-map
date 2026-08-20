import { useState, type FormEvent } from 'react'
import { CalendarClock, LoaderCircle, UserRound, Users, WalletCards } from 'lucide-react'
import { DishEditor } from './DishEditor'
import { ModalShell } from './ModalShell'
import { QueueDurationPicker } from './QueueDurationPicker'
import { StarRating } from './StarRating'
import { VisitPhotoPicker } from './VisitPhotoPicker'
import type { AddVisitInput } from '../db/restaurants'
import {
  calculatePricePerPerson,
  nearestStar,
  type QueueDuration,
  type RestaurantSummary,
  type StarRating as StarRatingValue,
  type VisitDish,
} from '../types/domain'
import { currentDateAndTime, localDateTimeToIso } from '../utils/date'

interface AddVisitModalProps {
  restaurant: RestaurantSummary
  onClose: () => void
  onSave: (input: AddVisitInput) => Promise<void>
}

function splitCompanions(value: string) {
  return [...new Set(value.split(/[,，、/]/).map((item) => item.trim()).filter(Boolean))]
}

export function AddVisitModal({ restaurant, onClose, onSave }: AddVisitModalProps) {
  const initialTime = currentDateAndTime()
  const [date, setDate] = useState(initialTime.date)
  const [time, setTime] = useState(initialTime.time)
  const [rating, setRating] = useState<StarRatingValue>(nearestStar(restaurant.averageRating) ?? 5)
  const [price, setPrice] = useState('')
  const [companions, setCompanions] = useState('')
  const [partySize, setPartySize] = useState('1')
  const [queueDuration, setQueueDuration] = useState<QueueDuration>('none')
  const [dishes, setDishes] = useState<VisitDish[]>([])
  const [feeling, setFeeling] = useState('')
  const [photos, setPhotos] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    const numericPrice = price ? Number(price) : null
    if (numericPrice !== null && (!Number.isFinite(numericPrice) || numericPrice < 0)) {
      setError('请输入正确的消费总价。')
      return
    }
    const numericPartySize = Number(partySize)
    if (!Number.isInteger(numericPartySize) || numericPartySize < 1) {
      setError('用餐人数至少为 1 人。')
      return
    }
    setSaving(true)
    setError('')
    try {
      await onSave({
        visitedAt: localDateTimeToIso(date, time),
        rating,
        totalPrice: numericPrice,
        partySize: numericPartySize,
        queueDuration,
        companions: splitCompanions(companions),
        dishes,
        note: feeling,
        photos,
      })
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : '保存失败，请稍后重试。')
    } finally {
      setSaving(false)
    }
  }

  return (
    <ModalShell title="记录一次到访" description={`为 ${restaurant.name} 增加一条真实到访记录。`} onClose={onClose}>
      <form className="editor-form" onSubmit={handleSubmit}>
        <label className="field"><span>本次个人评价</span><StarRating onChange={setRating} value={rating} /></label>
        <div className="field-grid visit-time-grid">
          <label className="field field-with-leading-icon"><span>日期</span><div><CalendarClock size={16} /><input onChange={(event) => setDate(event.target.value)} required type="date" value={date} /></div></label>
          <label className="field"><span>时间</span><input onChange={(event) => setTime(event.target.value)} required type="time" value={time} /></label>
        </div>
        <label className="field field-with-leading-icon"><span>本次消费总价（元）</span><div><WalletCards size={16} /><input min="0" onChange={(event) => setPrice(event.target.value)} placeholder="例如 193" step="1" type="number" value={price} /></div>{calculatePricePerPerson(price ? Number(price) : null, Number(partySize)) !== null ? <small className="price-calculation">按 {partySize} 人计算，约 ¥{calculatePricePerPerson(Number(price), Number(partySize))}/人</small> : null}</label>
        <div className="field-grid party-grid">
          <label className="field field-with-leading-icon"><span>用餐人数</span><div><Users size={16} /><input min="1" onChange={(event) => setPartySize(event.target.value)} required step="1" type="number" value={partySize} /></div></label>
          <label className="field field-with-leading-icon"><span>饭搭子</span><div><UserRound size={16} /><input onChange={(event) => setCompanions(event.target.value)} placeholder="小王、妈妈" value={companions} /></div></label>
        </div>
        <QueueDurationPicker onChange={setQueueDuration} value={queueDuration} />
        <label className="field visit-feeling-field"><span>这次的感受 <small>可选</small></span><textarea maxLength={1000} onChange={(event) => setFeeling(event.target.value)} placeholder="味道、氛围、当时的心情……想记多少都可以" rows={3} value={feeling} /></label>
        <VisitPhotoPicker onChange={setPhotos} value={photos} />
        <DishEditor onChange={setDishes} value={dishes} />
        {error ? <p className="form-error">{error}</p> : null}
        <footer className="modal-actions"><button className="secondary-button" onClick={onClose} type="button">取消</button><button className="primary-button" disabled={saving} type="submit">{saving ? <LoaderCircle className="spin" size={17} /> : null} 保存到访</button></footer>
      </form>
    </ModalShell>
  )
}
