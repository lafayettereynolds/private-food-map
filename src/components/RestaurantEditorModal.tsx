import { useState, type FormEvent } from 'react'
import { Check, LoaderCircle, LocateFixed, MapPin, RefreshCw, WalletCards } from 'lucide-react'
import { MarkerStyleField } from './MarkerStyleField'
import { ModalShell } from './ModalShell'
import { RestaurantSummarySection } from './RestaurantRecordSummary'
import { StickyFormActionBar } from './StickyFormActionBar'
import type { RestaurantBasicsUpdate } from '../db/restaurants'
import type { MarkerType, RestaurantStatus, RestaurantSummary } from '../types/domain'
import { mapService } from '../services/mapService'

interface RestaurantEditorModalProps {
  restaurant: RestaurantSummary
  onClose: () => void
  onSave: (changes: RestaurantBasicsUpdate) => Promise<void>
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
  const [price, setPrice] = useState(restaurant.pricePerPerson?.toString() ?? '')
  const [phone, setPhone] = useState(restaurant.phone ?? '')
  const [openingHours, setOpeningHours] = useState(restaurant.openingHours ?? '')
  const [markerType, setMarkerType] = useState<MarkerType>(restaurant.markerType)
  const [markerImageData, setMarkerImageData] = useState(restaurant.markerImageData)
  const [markerPhotoId, setMarkerPhotoId] = useState(restaurant.markerPhotoId)
  const [markerEmoji, setMarkerEmoji] = useState(restaurant.markerEmoji)
  const [latitude, setLatitude] = useState(restaurant.latitude)
  const [longitude, setLongitude] = useState(restaurant.longitude)
  const [locating, setLocating] = useState(false)
  const [locationMessage, setLocationMessage] = useState('')
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
        pricePerPerson: numericPrice,
        phone: phone.trim() || null,
        openingHours: openingHours.trim() || null,
        tags: restaurant.tags,
        markerType,
        markerImageData,
        markerPhotoId,
        markerEmoji,
        latitude,
        longitude,
      })
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : '保存失败，请稍后重试。')
    } finally {
      setSaving(false)
    }
  }

  async function recalibrateFromRestaurant() {
    setLocating(true)
    setError('')
    setLocationMessage('')
    try {
      const matches = await mapService.searchRestaurantPois(name, city, { timeoutMs: 8_000 })
      const exact = matches.find((item) => item.amapPoiId === restaurant.amapPoiId) ?? matches[0]
      const resolved = exact ?? await mapService.resolveAddressLocation(address, city)
      setLatitude(resolved.latitude)
      setLongitude(resolved.longitude)
      if ('address' in resolved && resolved.address) setAddress(resolved.address)
      setLocationMessage('地图位置已重新校准，保存后生效。')
    } catch (locationError) {
      setError(locationError instanceof Error ? locationError.message : '地图位置校准失败。')
    } finally {
      setLocating(false)
    }
  }

  async function handleUseCurrentLocation() {
    setLocating(true)
    setError('')
    setLocationMessage('')
    try {
      const current = await mapService.detectCurrentLocation()
      setLatitude(current.latitude)
      setLongitude(current.longitude)
      setAddress(current.address)
      setCity(current.city)
      setLocationMessage('已使用你现在的位置，保存后生效。')
    } catch (locationError) {
      setError(locationError instanceof Error ? locationError.message : '当前位置获取失败。')
    } finally {
      setLocating(false)
    }
  }

  const numericPreviewPrice = price && Number.isFinite(Number(price)) ? Number(price) : null
  const previewRestaurant: RestaurantSummary = {
    ...restaurant,
    name,
    address,
    city,
    status,
    pricePerPerson: numericPreviewPrice,
    phone: phone.trim() || null,
    openingHours: openingHours.trim() || null,
    latitude,
    longitude,
  }

  return (
    <ModalShell title="编辑餐厅" description="更新餐厅资料和地图上的显示方式。" onClose={onClose}>
      <form className="sticky-action-form" onSubmit={handleSubmit}>
        <div className="editor-form sticky-action-form__content">
        <RestaurantSummarySection
          className="is-form-summary"
          historyRestaurants={[restaurant]}
          referencePrice={numericPreviewPrice}
          restaurant={previewRestaurant}
        />
        <div className="restaurant-record-form-divider"><span>餐厅资料</span></div>
        <label className="field"><span>餐厅名称</span><input autoFocus onChange={(event) => setName(event.target.value)} required value={name} /></label>
        <div className="field-grid">
          <label className="field"><span>城市</span><input onChange={(event) => setCity(event.target.value)} value={city} /></label>
          <label className="field"><span>所属列表</span><select onChange={(event) => setStatus(event.target.value as RestaurantStatus)} value={status}><option value="visited">我去过</option><option value="wantToGo">我想去</option></select></label>
        </div>
        <label className="field field-with-leading-icon"><span>地址</span><div><MapPin size={16} /><input onChange={(event) => setAddress(event.target.value)} value={address} /></div></label>
        <div className="location-calibration">
          <div><strong>地图位置</strong><span>{longitude.toFixed(6)}, {latitude.toFixed(6)}</span></div>
          <button className="secondary-button" disabled={locating || !name.trim()} onClick={() => void recalibrateFromRestaurant()} type="button">{locating ? <LoaderCircle className="spin" size={14} /> : <RefreshCw size={14} />} 按餐厅重新定位</button>
          <button className="text-button" disabled={locating} onClick={() => void handleUseCurrentLocation()} type="button"><LocateFixed size={14} /> 我就在店里</button>
        </div>
        {locationMessage ? <p className="location-success"><Check size={14} /> {locationMessage}</p> : null}
        <label className="field field-with-leading-icon"><span>参考人均价格（元）</span><div><WalletCards size={16} /><input inputMode="decimal" min="0" onChange={(event) => setPrice(event.target.value)} step="0.01" type="number" value={price} /></div>{status === 'visited' ? <small className="price-calculation">去过的餐厅会优先显示到访记录自动计算的人均。</small> : null}</label>
        <div className="field-grid">
          <label className="field"><span>联系电话</span><input inputMode="tel" onChange={(event) => setPhone(event.target.value)} placeholder="例如：0571-88888888" value={phone} /></label>
          <label className="field"><span>营业时间</span><input onChange={(event) => setOpeningHours(event.target.value)} placeholder="例如：11:00–22:00" value={openingHours} /></label>
        </div>
        <MarkerStyleField
          markerEmoji={markerEmoji}
          markerImageData={markerImageData}
          markerPhotoId={markerPhotoId}
          markerType={markerType}
          merchantImageUrl={restaurant.merchantImageUrl}
          onEmojiChange={setMarkerEmoji}
          onImageChange={(value) => { setMarkerImageData(value); setMarkerPhotoId(value === restaurant.markerImageData ? restaurant.markerPhotoId : null) }}
          onTypeChange={setMarkerType}
        />
        </div>
        <StickyFormActionBar primaryDisabled={!name.trim()} primaryLabel="保存修改" primaryLoading={saving} secondaryAction={onClose} statusMessage={error} statusTone="error" />
      </form>
    </ModalShell>
  )
}
