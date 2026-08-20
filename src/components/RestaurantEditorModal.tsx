import { useState, type FormEvent } from 'react'
import { LoaderCircle, MapPin, Tag, WalletCards } from 'lucide-react'
import { MarkerStyleField } from './MarkerStyleField'
import { ModalShell } from './ModalShell'
import { PreferencePicker } from './PreferencePicker'
import type { RestaurantBasicsUpdate } from '../db/restaurants'
import type { MarkerType, PreferenceLevel, Restaurant, RestaurantStatus } from '../types/domain'

interface RestaurantEditorModalProps {
  restaurant: Restaurant
  onClose: () => void
  onSave: (changes: RestaurantBasicsUpdate) => Promise<void>
}

function splitTags(value: string) {
  return [...new Set(value.split(/[,，、/]/).map((item) => item.trim()).filter(Boolean))]
}

export function RestaurantEditorModal({
  restaurant,
  onClose,
  onSave,
}: RestaurantEditorModalProps) {
  const [name, setName] = useState(restaurant.name)
  const [address, setAddress] = useState(restaurant.address)
  const [city, setCity] = useState(restaurant.city)
  const [status, setStatus] = useState<RestaurantStatus>(restaurant.status)
  const [preferenceLevel, setPreferenceLevel] = useState<PreferenceLevel>(restaurant.preferenceLevel)
  const [price, setPrice] = useState(restaurant.pricePerPerson?.toString() ?? '')
  const [tags, setTags] = useState(restaurant.tags.join('、'))
  const [markerType, setMarkerType] = useState<MarkerType>(restaurant.markerType)
  const [markerImageData, setMarkerImageData] = useState(restaurant.markerImageData)
  const [markerEmoji, setMarkerEmoji] = useState(restaurant.markerEmoji)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    if (!name.trim()) return
    const numericPrice = price ? Number(price) : null
    if (numericPrice !== null && (!Number.isFinite(numericPrice) || numericPrice < 0)) {
      setError('请输入正确的人均价格。')
      return
    }
    setSaving(true)
    setError('')
    try {
      await onSave({
        name,
        address,
        city,
        status,
        preferenceLevel,
        pricePerPerson: numericPrice,
        tags: splitTags(tags),
        markerType,
        markerImageData,
        markerEmoji,
      })
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : '保存失败，请稍后重试。')
    } finally {
      setSaving(false)
    }
  }

  return (
    <ModalShell title="编辑餐厅" description="修改地址、标签和地图上的显示方式。" onClose={onClose}>
      <form className="editor-form" onSubmit={handleSubmit}>
        <label className="field"><span>餐厅名称</span><input autoFocus onChange={(event) => setName(event.target.value)} required value={name} /></label>
        <div className="field-grid">
          <label className="field"><span>城市</span><input onChange={(event) => setCity(event.target.value)} value={city} /></label>
          <label className="field"><span>所属列表</span><select onChange={(event) => setStatus(event.target.value as RestaurantStatus)} value={status}><option value="visited">我去过</option><option value="wantToGo">我想去</option></select></label>
        </div>
        <label className="field field-with-leading-icon"><span>地址</span><div><MapPin size={16} /><input onChange={(event) => setAddress(event.target.value)} value={address} /></div></label>
        <label className="field field-with-leading-icon"><span>参考人均价格（元）</span><div><WalletCards size={16} /><input min="0" onChange={(event) => setPrice(event.target.value)} step="1" type="number" value={price} /></div>{status === 'visited' ? <small className="price-calculation">去过的餐厅会优先显示到访记录自动计算的人均。</small> : null}</label>
        <label className="field field-with-leading-icon"><span>标签</span><div><Tag size={16} /><input onChange={(event) => setTags(event.target.value)} placeholder="日料、约会、会再去" value={tags} /></div></label>
        <PreferencePicker onChange={setPreferenceLevel} value={preferenceLevel} />
        <MarkerStyleField
          markerEmoji={markerEmoji}
          markerImageData={markerImageData}
          markerType={markerType}
          merchantImageUrl={restaurant.merchantImageUrl}
          onEmojiChange={setMarkerEmoji}
          onImageChange={setMarkerImageData}
          onTypeChange={setMarkerType}
        />
        {error ? <p className="form-error">{error}</p> : null}
        <footer className="modal-actions"><button className="secondary-button" onClick={onClose} type="button">取消</button><button className="primary-button" disabled={saving || !name.trim()} type="submit">{saving ? <LoaderCircle className="spin" size={17} /> : null} 保存修改</button></footer>
      </form>
    </ModalShell>
  )
}
