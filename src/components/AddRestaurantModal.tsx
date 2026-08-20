import { useEffect, useRef, useState, type FormEvent } from 'react'
import {
  ArrowLeft,
  CalendarClock,
  Check,
  LoaderCircle,
  LocateFixed,
  MapPin,
  Plus,
  Search,
  Store,
  Tag,
  TriangleAlert,
  Users,
  WalletCards,
} from 'lucide-react'
import { CompanionPicker } from './CompanionPicker'
import { ModalShell } from './ModalShell'
import { DishEditor } from './DishEditor'
import { MarkerStyleField } from './MarkerStyleField'
import { QueueDurationPicker } from './QueueDurationPicker'
import { StarRating } from './StarRating'
import { VisitPhotoPicker } from './VisitPhotoPicker'
import type { AddRestaurantInput } from '../db/restaurants'
import {
  detectCurrentCity,
  detectCurrentLocation,
  isAmapConfigured,
  resolveAddressLocation,
  searchRestaurantPois,
} from '../services/amap'
import { calculatePricePerPerson } from '../types/domain'
import type {
  MarkerType,
  PoiSearchResult,
  QueueDuration,
  RestaurantStatus,
  RestaurantSummary,
  StarRating as StarRatingValue,
  VisitDish,
} from '../types/domain'
import { currentDateAndTime, localDateTimeToIso } from '../utils/date'

interface AddRestaurantModalProps {
  companionOptions: string[]
  existingRestaurantsByPoiId: Map<string, RestaurantSummary>
  onAdd: (input: AddRestaurantInput) => Promise<void>
  onRecordExisting: (restaurant: RestaurantSummary) => void
  onClose: () => void
}

function splitValues(value: string) {
  return [...new Set(value.split(/[,，、/]/).map((item) => item.trim()).filter(Boolean))]
}

export function AddRestaurantModal({
  companionOptions,
  existingRestaurantsByPoiId,
  onAdd,
  onRecordExisting,
  onClose,
}: AddRestaurantModalProps) {
  const initialTime = currentDateAndTime()
  const [keyword, setKeyword] = useState('')
  const [city, setCity] = useState(() => localStorage.getItem('private-food-map-last-city') ?? '')
  const [locatingCity, setLocatingCity] = useState(isAmapConfigured)
  const cityEditedRef = useRef(false)
  const [results, setResults] = useState<PoiSearchResult[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [hasSearched, setHasSearched] = useState(false)
  const [selectedPoi, setSelectedPoi] = useState<PoiSearchResult | null>(null)
  const [manualMode, setManualMode] = useState(false)
  const [address, setAddress] = useState('')
  const [status, setStatus] = useState<RestaurantStatus>('visited')
  const [price, setPrice] = useState('')
  const [companions, setCompanions] = useState('')
  const [partySize, setPartySize] = useState('1')
  const [queueDuration, setQueueDuration] = useState<QueueDuration>('none')
  const [dishes, setDishes] = useState<VisitDish[]>([])
  const [feeling, setFeeling] = useState('')
  const [photos, setPhotos] = useState<string[]>([])
  const [rating, setRating] = useState<StarRatingValue>(5)
  const [visitDate, setVisitDate] = useState(initialTime.date)
  const [visitTime, setVisitTime] = useState(initialTime.time)
  const [tags, setTags] = useState('')
  const [markerType, setMarkerType] = useState<MarkerType>('emoji')
  const [markerImageData, setMarkerImageData] = useState<string | null>(null)
  const [markerEmoji, setMarkerEmoji] = useState('🍽️')

  useEffect(() => {
    if (!isAmapConfigured) return
    let active = true
    detectCurrentCity()
      .then((detectedCity) => {
        localStorage.setItem('private-food-map-last-city', detectedCity)
        if (active && !cityEditedRef.current) setCity(detectedCity)
      })
      .catch(() => undefined)
      .finally(() => {
        if (active) setLocatingCity(false)
      })
    return () => {
      active = false
    }
  }, [])

  async function handleSearch(event: FormEvent) {
    event.preventDefault()
    if (!keyword.trim()) return
    setLoading(true)
    setError('')
    setHasSearched(true)
    try {
      setResults(await searchRestaurantPois(keyword, city))
    } catch (searchError) {
      setResults([])
      setError(searchError instanceof Error ? searchError.message : '搜索失败，请稍后重试。')
    } finally {
      setLoading(false)
    }
  }

  function choosePoi(poi: PoiSearchResult) {
    const existingRestaurant = existingRestaurantsByPoiId.get(poi.amapPoiId)
    if (existingRestaurant) {
      onRecordExisting(existingRestaurant)
      return
    }
    setSelectedPoi(poi)
    setAddress(poi.address)
    setMarkerType(poi.merchantImageUrl ? 'image' : 'emoji')
    setError('')
  }

  async function handleAdd(event: FormEvent) {
    event.preventDefault()
    if (!selectedPoi || !address.trim()) return
    const numericPrice = price ? Number(price) : null
    if (numericPrice !== null && (!Number.isFinite(numericPrice) || numericPrice < 0)) {
      setError(status === 'visited' ? '请输入正确的消费总价。' : '请输入正确的预计人均价格。')
      return
    }
    const numericPartySize = Number(partySize)
    if (status === 'visited' && (!Number.isInteger(numericPartySize) || numericPartySize < 1)) {
      setError('用餐人数至少为 1 人。')
      return
    }

    setSaving(true)
    setError('')
    try {
      await onAdd({
        poi: selectedPoi,
        address,
        status,
        tags: splitValues(tags),
        pricePerPerson:
          status === 'visited'
            ? calculatePricePerPerson(numericPrice, numericPartySize)
            : numericPrice,
        markerType,
        markerImageData,
        markerEmoji,
        initialVisit:
          status === 'visited'
            ? {
                visitedAt: localDateTimeToIso(visitDate, visitTime),
                rating,
                totalPrice: numericPrice,
                partySize: numericPartySize,
                queueDuration,
                companions: splitValues(companions),
                dishes,
                note: feeling,
                photos,
              }
            : null,
      })
    } catch (addError) {
      setError(addError instanceof Error ? addError.message : '添加失败，请稍后重试。')
    } finally {
      setSaving(false)
    }
  }

  return (
    <ModalShell
      title={selectedPoi ? '写下这家餐厅' : '添加餐厅'}
      description={selectedPoi ? '这些内容只属于你，并保存在当前浏览器中。' : manualMode ? '为地图上搜不到的小摊或私房店标记位置。' : '从高德选择餐厅，或手动添加地图上搜不到的小店。'}
      onClose={onClose}
      size="large"
    >
      {!selectedPoi ? (
        manualMode ? <ManualRestaurantStep
          city={city}
          initialName={keyword}
          onBack={() => setManualMode(false)}
          onChoose={choosePoi}
          onCityChange={(value) => {
            cityEditedRef.current = true
            setCity(value)
          }}
        /> : <SearchStep
          city={city}
          error={error}
          existingRestaurantsByPoiId={existingRestaurantsByPoiId}
          hasSearched={hasSearched}
          keyword={keyword}
          locatingCity={locatingCity}
          loading={loading}
          onChoose={choosePoi}
          onCityChange={(value) => {
            cityEditedRef.current = true
            setCity(value)
          }}
          onKeywordChange={setKeyword}
          onManualAdd={() => setManualMode(true)}
          onRecordExisting={onRecordExisting}
          onSearch={handleSearch}
          results={results}
        />
      ) : (
        <form className="personalize-form" onSubmit={handleAdd}>
          <button className="back-button" onClick={() => setSelectedPoi(null)} type="button"><ArrowLeft size={15} /> 返回搜索结果</button>

          <div className="selected-poi-card">
            {selectedPoi.merchantImageUrl ? <img alt="" src={selectedPoi.merchantImageUrl} /> : <span><MapPin size={18} /></span>}
            <div><strong>{selectedPoi.name}</strong><p>{selectedPoi.city}{selectedPoi.district ? ` · ${selectedPoi.district}` : ''}</p></div>
          </div>

          <div className="collection-choice" aria-label="餐厅状态">
            <button className={status === 'visited' ? 'is-active' : ''} onClick={() => setStatus('visited')} type="button"><Check size={15} /> 我去过</button>
            <button className={status === 'wantToGo' ? 'is-active' : ''} onClick={() => setStatus('wantToGo')} type="button"><MapPin size={15} /> 我想去</button>
          </div>

          <div className="form-section">
            <h3>基本信息</h3>
            <label className="field field-with-leading-icon">
              <span>地址</span>
              <div><MapPin size={16} /><input onChange={(event) => setAddress(event.target.value)} required value={address} /></div>
            </label>
            <label className="field field-with-leading-icon">
              <span>{status === 'visited' ? '本次消费总价（元）' : '预计人均价格（元）'}</span>
              <div><WalletCards size={16} /><input inputMode="decimal" min="0" onChange={(event) => setPrice(event.target.value)} placeholder={status === 'visited' ? '例如 193' : '例如 180'} step="1" type="number" value={price} /></div>
              {status === 'visited' && calculatePricePerPerson(price ? Number(price) : null, Number(partySize)) !== null ? <small className="price-calculation">按 {partySize} 人计算，约 ¥{calculatePricePerPerson(Number(price), Number(partySize))}/人</small> : null}
            </label>
          </div>

          {status === 'visited' ? (
            <div className="form-section">
              <h3>这次体验</h3>
              <label className="field">
                <span>个人评价</span>
                <StarRating onChange={setRating} value={rating} />
              </label>
              <div className="field-grid visit-time-grid">
                <label className="field field-with-leading-icon"><span>日期</span><div><CalendarClock size={16} /><input max="9999-12-31" onChange={(event) => setVisitDate(event.target.value)} required type="date" value={visitDate} /></div></label>
                <label className="field"><span>时间</span><input onChange={(event) => setVisitTime(event.target.value)} required type="time" value={visitTime} /></label>
              </div>
              <div className="field-grid party-grid">
                <label className="field field-with-leading-icon"><span>用餐人数</span><div><Users size={16} /><input inputMode="numeric" min="1" onChange={(event) => setPartySize(event.target.value)} required step="1" type="number" value={partySize} /></div></label>
                <CompanionPicker onChange={setCompanions} options={companionOptions} value={companions} />
              </div>
              <QueueDurationPicker onChange={setQueueDuration} value={queueDuration} />
              <label className="field visit-feeling-field"><span>这次的感受 <small>可选</small></span><textarea maxLength={1000} onChange={(event) => setFeeling(event.target.value)} placeholder="味道、氛围、当时的心情……想记多少都可以" rows={3} value={feeling} /></label>
              <VisitPhotoPicker onChange={setPhotos} value={photos} />
              <DishEditor onChange={setDishes} value={dishes} />
            </div>
          ) : null}

          <div className="form-section">
            <h3>整理与显示</h3>
            <label className="field field-with-leading-icon"><span>标签</span><div><Tag size={16} /><input onChange={(event) => setTags(event.target.value)} placeholder="例如：日料、约会、会再去" value={tags} /></div></label>
            <MarkerStyleField
              markerEmoji={markerEmoji}
              markerImageData={markerImageData}
              markerType={markerType}
              merchantImageUrl={selectedPoi.merchantImageUrl}
              onEmojiChange={setMarkerEmoji}
              onImageChange={setMarkerImageData}
              onTypeChange={setMarkerType}
            />
          </div>

          {error ? <p className="form-error">{error}</p> : null}
          <footer className="modal-actions sticky-modal-actions">
            <button className="secondary-button" onClick={onClose} type="button">取消</button>
            <button className="primary-button" disabled={saving || !address.trim()} type="submit">
              {saving ? <LoaderCircle className="spin" size={17} /> : null} 保存到我的地图
            </button>
          </footer>
        </form>
      )}
    </ModalShell>
  )
}

interface SearchStepProps {
  city: string
  error: string
  existingRestaurantsByPoiId: Map<string, RestaurantSummary>
  hasSearched: boolean
  keyword: string
  locatingCity: boolean
  loading: boolean
  results: PoiSearchResult[]
  onCityChange: (value: string) => void
  onKeywordChange: (value: string) => void
  onManualAdd: () => void
  onChoose: (poi: PoiSearchResult) => void
  onRecordExisting: (restaurant: RestaurantSummary) => void
  onSearch: (event: FormEvent) => void
}

function SearchStep({
  city,
  error,
  existingRestaurantsByPoiId,
  hasSearched,
  keyword,
  locatingCity,
  loading,
  results,
  onCityChange,
  onKeywordChange,
  onManualAdd,
  onChoose,
  onRecordExisting,
  onSearch,
}: SearchStepProps) {
  return (
    <>
      {!isAmapConfigured ? (
        <div className="config-notice"><TriangleAlert size={19} /><div><strong>还需要配置高德地图</strong><p>填入高德 Key 和安全密钥后，餐厅搜索就会启用。</p></div></div>
      ) : null}
      <form className="poi-search-form" onSubmit={onSearch}>
        <label className="field field--grow"><span>餐厅名称</span><div className="input-with-icon"><Search size={17} /><input autoFocus onChange={(event) => onKeywordChange(event.target.value)} placeholder="例如：寿喜烧" value={keyword} /></div></label>
        <label className="field field--city"><span>城市 {locatingCity ? '· 正在定位' : '· GPS 优先'}</span><input onChange={(event) => onCityChange(event.target.value)} placeholder="杭州" value={city} /></label>
        <button className="primary-button search-submit" disabled={!isAmapConfigured || loading || !keyword.trim()} type="submit">{loading ? <LoaderCircle className="spin" size={17} /> : <Search size={17} />}搜索</button>
      </form>
      {error ? <p className="form-error">{error}</p> : null}
      <div className="poi-results" aria-live="polite">
        {results.map((poi) => {
          const existingRestaurant = existingRestaurantsByPoiId.get(poi.amapPoiId)
          return (
            <article className="poi-result" key={poi.amapPoiId}>
              {poi.merchantImageUrl ? <img className="poi-result__image" alt="" src={poi.merchantImageUrl} /> : <span className="poi-result__pin"><MapPin size={17} /></span>}
              <div className="poi-result__body"><strong>{poi.name}</strong><p>{poi.address}</p><span>{poi.city}{poi.district ? ` · ${poi.district}` : ''}</span></div>
              <button
                className={existingRestaurant ? 'repeat-visit-button' : 'secondary-button'}
                onClick={() => existingRestaurant ? onRecordExisting(existingRestaurant) : onChoose(poi)}
                type="button"
              >
                {existingRestaurant ? <><Plus size={15} /> 再去一次</> : '选择'}
              </button>
            </article>
          )
        })}
        {hasSearched && !loading && !error && results.length === 0 ? <div className="empty-results"><Search size={21} /><strong>没有找到匹配的餐厅</strong><p>换一个名称，或填写城市后再试。</p></div> : null}
        {!hasSearched ? <div className="search-hint"><span>搜索建议</span><p>名称太常见时，加上城市会更准确，例如“杭州 寿喜烧”。</p></div> : null}
      </div>
      <button className="manual-restaurant-entry" onClick={onManualAdd} type="button">
        <Store size={18} />
        <span><strong>地图上搜不到？手动添加</strong><small>适合路边小摊、快闪店和私房店</small></span>
      </button>
    </>
  )
}

function ManualRestaurantStep({
  initialName,
  city,
  onBack,
  onCityChange,
  onChoose,
}: {
  initialName: string
  city: string
  onBack: () => void
  onCityChange: (value: string) => void
  onChoose: (poi: PoiSearchResult) => void
}) {
  const [name, setName] = useState(initialName)
  const [address, setAddress] = useState('')
  const [location, setLocation] = useState<{ longitude: number; latitude: number; district: string } | null>(null)
  const [locating, setLocating] = useState(false)
  const [resolving, setResolving] = useState(false)
  const [error, setError] = useState('')

  async function useCurrentLocation() {
    setLocating(true)
    setError('')
    try {
      const current = await detectCurrentLocation()
      setAddress(current.address)
      onCityChange(current.city)
      setLocation(current)
    } catch (locationError) {
      setError(locationError instanceof Error ? locationError.message : '当前位置获取失败。')
    } finally {
      setLocating(false)
    }
  }

  async function continueWithManualRestaurant(event: FormEvent) {
    event.preventDefault()
    if (!name.trim() || !address.trim() || !city.trim()) return
    setResolving(true)
    setError('')
    try {
      const resolved = location ?? await resolveAddressLocation(address, city)
      onChoose({
        amapPoiId: createManualPoiId(name, city, resolved.longitude, resolved.latitude),
        name: name.trim(),
        address: address.trim(),
        city: city.trim(),
        district: resolved.district,
        longitude: resolved.longitude,
        latitude: resolved.latitude,
        merchantImageUrl: null,
      })
    } catch (locationError) {
      setError(locationError instanceof Error ? locationError.message : '这个地址暂时无法定位。')
    } finally {
      setResolving(false)
    }
  }

  return (
    <form className="manual-restaurant-form" onSubmit={continueWithManualRestaurant}>
      <button className="back-button" onClick={onBack} type="button"><ArrowLeft size={15} /> 返回餐厅搜索</button>
      <div className="manual-restaurant-intro"><Store size={20} /><div><strong>手动添加小店</strong><p>只需名称和位置，其他记录下一步再补充。</p></div></div>
      <div className="field-grid">
        <label className="field"><span>小店 / 摊位名称</span><input autoFocus onChange={(event) => setName(event.target.value)} placeholder="例如：阿婆葱包桧小摊" required value={name} /></label>
        <label className="field"><span>城市</span><input onChange={(event) => onCityChange(event.target.value)} placeholder="杭州" required value={city} /></label>
      </div>
      <label className="field field-with-leading-icon"><span>地址或附近地标</span><div><MapPin size={16} /><input onChange={(event) => { setAddress(event.target.value); setLocation(null) }} placeholder="例如：武林路 32 号门口" required value={address} /></div></label>
      <button className="location-helper-button" disabled={locating} onClick={useCurrentLocation} type="button">
        {locating ? <LoaderCircle className="spin" size={16} /> : <LocateFixed size={16} />}
        {locating ? '正在读取位置' : '使用我现在的位置'}
      </button>
      {location ? <p className="location-success"><Check size={14} /> 已定位到当前位置</p> : null}
      {error ? <p className="form-error">{error}</p> : null}
      <footer className="modal-actions sticky-modal-actions">
        <button className="secondary-button" onClick={onBack} type="button">取消</button>
        <button className="primary-button" disabled={resolving || !name.trim() || !address.trim() || !city.trim()} type="submit">
          {resolving ? <LoaderCircle className="spin" size={17} /> : null} 确认位置并继续
        </button>
      </footer>
    </form>
  )
}

function createManualPoiId(name: string, city: string, longitude: number, latitude: number) {
  const source = `${name.trim().toLocaleLowerCase('zh-CN')}|${city.trim()}|${longitude.toFixed(5)}|${latitude.toFixed(5)}`
  let hash = 2166136261
  for (let index = 0; index < source.length; index += 1) {
    hash ^= source.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return `custom-${(hash >>> 0).toString(36)}`
}
