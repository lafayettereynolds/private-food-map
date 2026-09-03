import { useEffect, useRef, useState, type FormEvent } from 'react'
import {
  ArrowLeft,
  CalendarClock,
  Check,
  LoaderCircle,
  Link2,
  LocateFixed,
  MapPin,
  Search,
  Store,
  TriangleAlert,
  Users,
  WalletCards,
} from 'lucide-react'
import { CompanionPicker } from './CompanionPicker'
import { ModalShell } from './ModalShell'
import { StickyFormActionBar } from './StickyFormActionBar'
import { TasteMapVisitedIcon } from './TasteMapStatusIcons'
import { DishEditor } from './DishEditor'
import { MarkerStyleField } from './MarkerStyleField'
import { QueueDurationPicker } from './QueueDurationPicker'
import { StarRatingField } from './StarRating'
import { VisitPhotoPicker } from './VisitPhotoPicker'
import { VisitExtraFields } from './VisitExtraFields'
import { RestaurantSummarySection } from './RestaurantRecordSummary'
import { createDefaultVisitExtraFields, type VisitExtraFieldsValue } from '../types/visitExtras'
import type { AddRestaurantInput } from '../db/restaurants'
import { mapService } from '../services/mapService'
import { calculatePricePerPerson, starToTenScore } from '../types/domain'
import type {
  MarkerType,
  Coordinates,
  PoiSearchResult,
  QueueDuration,
  RestaurantStatus,
  RestaurantSummary,
  StarRating as StarRatingValue,
  VisitDish,
} from '../types/domain'
import { currentDateAndTime, localDateTimeToIso } from '../utils/date'
import { CURRENT_USER_ID } from '../db/social'
import { resolveExternalRestaurantLink, type ExternalLinkResolveResult } from '../services/externalRestaurantLink'
import {
  TasteMapRestaurantAcquisitionResults,
  TasteMapRestaurantAcquisitionScaffold,
  TasteMapRestaurantAcquisitionSearch,
  TasteMapRestaurantAcquisitionStatus,
} from './TasteMapRestaurantAcquisitionShared'

interface AddRestaurantModalProps {
  companionOptions: string[]
  friendOptions?: Array<{ id: string; nickname: string }>
  maxPhotos?: number
  photoUpgradeAvailable?: boolean
  existingRestaurantsByPoiId: Map<string, RestaurantSummary>
  historyRestaurants: RestaurantSummary[]
  isRouletteCandidate: (poi: PoiSearchResult) => boolean
  onAdd: (input: AddRestaurantInput) => Promise<void>
  onToggleRoulette: (poi: PoiSearchResult) => void
  onRecordExisting: (restaurant: RestaurantSummary) => void
  onClose: () => void
}

function splitValues(value: string) {
  return [...new Set(value.split(/[,，、/]/).map((item) => item.trim()).filter(Boolean))]
}

export function AddRestaurantModal({
  companionOptions,
  friendOptions = [],
  maxPhotos = 20,
  photoUpgradeAvailable = false,
  existingRestaurantsByPoiId,
  historyRestaurants,
  isRouletteCandidate,
  onAdd,
  onToggleRoulette,
  onRecordExisting,
  onClose,
}: AddRestaurantModalProps) {
  const initialTime = currentDateAndTime()
  const [keyword, setKeyword] = useState('')
  const [city, setCity] = useState(() => localStorage.getItem('private-food-map-last-city') ?? '')
  const [locatingCity, setLocatingCity] = useState(mapService.isConfigured)
  const cityEditedRef = useRef(false)
  const searchRequestIdRef = useRef(0)
  const [currentLocation, setCurrentLocation] = useState<Coordinates | null>(null)
  const [nearbyResults, setNearbyResults] = useState<PoiSearchResult[]>([])
  const [nearbyLoading, setNearbyLoading] = useState(mapService.isConfigured)
  const [nearbyMessage, setNearbyMessage] = useState('')
  const [locationLabel, setLocationLabel] = useState('')
  const [locationAttempt, setLocationAttempt] = useState(0)
  const [results, setResults] = useState<PoiSearchResult[]>([])
  const [externalLink, setExternalLink] = useState('')
  const [externalLinkLoading, setExternalLinkLoading] = useState(false)
  const [externalLinkResult, setExternalLinkResult] = useState<ExternalLinkResolveResult | null>(null)
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
  const [rating, setRating] = useState<StarRatingValue | null>(null)
  const [visitDate, setVisitDate] = useState(initialTime.date)
  const [visitTime, setVisitTime] = useState(initialTime.time)
  const [markerType, setMarkerType] = useState<MarkerType>('emoji')
  const [markerImageData, setMarkerImageData] = useState<string | null>(null)
  const [markerEmoji, setMarkerEmoji] = useState('🍽️')
  const [extraFields, setExtraFields] = useState<VisitExtraFieldsValue>(() => createDefaultVisitExtraFields())

  const referencePrice = status === 'visited'
    ? calculatePricePerPerson(price ? Number(price) : null, Number(partySize))
    : price && Number.isFinite(Number(price)) ? Number(price) : null

  function updateCompanions(next: string) {
    const previousCount = splitValues(companions).length
    const nextCount = splitValues(next).length
    setCompanions(next)
    setPartySize((current) => String(Math.max(1, (Number(current) || 1) + nextCount - previousCount)))
  }

  useEffect(() => {
    if (!mapService.isConfigured) {
      setLocatingCity(false)
      setNearbyLoading(false)
      return
    }
    let active = true
    let completed = false
    setLocatingCity(true)
    setNearbyLoading(true)
    setNearbyResults([])
    setNearbyMessage('')
    setLocationLabel('')
    const watchdog = window.setTimeout(() => {
      if (!active) return
      setLocatingCity(false)
      setNearbyLoading(false)
      if (!completed) setNearbyMessage('高精度定位超时，没有展示城市兜底结果。请开启精确定位后重试。')
    }, 12_000)
    void (async () => {
      try {
        const coordinates = await mapService.detectCurrentCoordinates()
        if (!active) return
        setCurrentLocation(coordinates)
        const [nearby, detected] = await Promise.all([
          mapService.searchNearbyRestaurantPois(coordinates, undefined, { timeoutMs: 5_000, radiusMeters: 3_000 }),
          mapService.resolveCoordinatesLocation(coordinates).catch(() => null),
        ])
        if (active && detected) {
          localStorage.setItem('private-food-map-last-city', detected.city)
          if (!cityEditedRef.current) setCity(detected.city)
          setLocationLabel(detected.address || [detected.city, detected.district].filter(Boolean).join(' · '))
        }
        if (!active) return
        setNearbyResults(nearby.slice(0, 8))
        setNearbyMessage(nearby.length ? '以下餐厅按 GPS 坐标 3 公里内检索。' : '已获得精确位置，但 3 公里内没有找到餐厅。')
      } catch (locationError) {
        if (active) setNearbyMessage(locationError instanceof Error ? locationError.message : '高精度定位失败，请重新尝试。')
      } finally {
        completed = true
        window.clearTimeout(watchdog)
        if (active) {
          setLocatingCity(false)
          setNearbyLoading(false)
        }
      }
    })()
    return () => {
      active = false
      window.clearTimeout(watchdog)
    }
  }, [locationAttempt])

  async function handleSearch(event: FormEvent) {
    event.preventDefault()
    const trimmedKeyword = keyword.trim()
    if (!trimmedKeyword) {
      setResults([])
      setHasSearched(false)
      setLoading(false)
      return
    }
    const requestId = ++searchRequestIdRef.current
    setLoading(true)
    setError('')
    setHasSearched(true)
    try {
      const matches = await mapService.searchRestaurantPois(trimmedKeyword, city, {
        center: currentLocation ?? undefined,
        radiusMeters: 20_000,
        timeoutMs: 8_000,
      })
      if (requestId !== searchRequestIdRef.current) return
      setResults(matches)
    } catch (searchError) {
      if (requestId !== searchRequestIdRef.current) return
      setResults([])
      setError(searchError instanceof Error ? searchError.message : '搜索失败，请重新尝试。')
    } finally {
      if (requestId === searchRequestIdRef.current) setLoading(false)
    }
  }

  async function handleExternalLinkResolve(event: FormEvent) {
    event.preventDefault()
    const value = externalLink.trim()
    if (!value) return
    setExternalLinkLoading(true)
    setExternalLinkResult(null)
    setError('')
    try {
      const resolved = await resolveExternalRestaurantLink(value, city)
      setExternalLinkResult(resolved)
      const sourceType = resolved.sourceSuggestion === '小红书' ? 'xiaohongshu'
        : resolved.sourceSuggestion === '大众点评' ? 'dianping'
          : resolved.sourceSuggestion === '抖音' ? 'douyin'
            : 'other'
      setExtraFields((current) => ({
        ...current,
        recommendationSourceType: sourceType,
        recommendationSourceText: resolved.sourceSuggestion,
      }))
      if (resolved.candidates.length === 0 && resolved.searchFallback?.keyword) {
        const fallback = resolved.searchFallback
        setKeyword(fallback.keyword)
        if (fallback.city) {
          cityEditedRef.current = true
          setCity(fallback.city)
        }
        setHasSearched(true)
        setLoading(true)
        const matches = await mapService.searchRestaurantPois(fallback.keyword, fallback.city || city, {
          center: fallback.latitude !== null && fallback.longitude !== null
            ? { latitude: fallback.latitude, longitude: fallback.longitude }
            : currentLocation ?? undefined,
          radiusMeters: 20_000,
          timeoutMs: 8_000,
        })
        setResults(matches)
      }
    } catch (resolveError) {
      setError(resolveError instanceof Error ? resolveError.message : '餐厅链接暂时无法解析。')
    } finally {
      setExternalLinkLoading(false)
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
    const isSeparatePayment = extraFields.paymentMode === 'separate'

    setSaving(true)
    setError('')
    try {
      await onAdd({
        poi: selectedPoi,
        address,
        status,
        tags: [],
        pricePerPerson:
          status === 'visited'
            ? calculatePricePerPerson(isSeparatePayment ? null : numericPrice, numericPartySize)
            : numericPrice,
        markerType,
        markerImageData,
        markerEmoji,
        initialVisit:
          status === 'visited'
            ? {
                visitedAt: localDateTimeToIso(visitDate, visitTime),
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
      backdropClassName="add-restaurant-modal-backdrop"
      title={selectedPoi ? '写下这家餐厅' : '添加餐厅'}
      description={selectedPoi ? '记录这家餐厅，留住这次味觉记忆。' : manualMode ? '为地图上搜不到的小摊或私房店标记位置。' : '从高德选择餐厅，或手动添加地图上搜不到的小店。'}
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
          nearbyLoading={nearbyLoading}
          locationLabel={locationLabel}
          nearbyMessage={nearbyMessage}
          nearbyResults={nearbyResults}
          externalLink={externalLink}
          externalLinkLoading={externalLinkLoading}
          externalLinkResult={externalLinkResult}
          onChoose={choosePoi}
          onCityChange={(value) => {
            cityEditedRef.current = true
            setCity(value)
          }}
          onKeywordChange={(value) => {
            searchRequestIdRef.current += 1
            setKeyword(value)
            setLoading(false)
            setError('')
            if (!value.trim()) {
              setResults([])
              setHasSearched(false)
            }
          }}
          onExternalLinkChange={(value) => {
            setExternalLink(value)
            setExternalLinkResult(null)
            setError('')
          }}
          onExternalLinkResolve={handleExternalLinkResolve}
          onManualAdd={() => setManualMode(true)}
          onRetryLocation={() => setLocationAttempt((attempt) => attempt + 1)}
          onRecordExisting={onRecordExisting}
          onSearch={handleSearch}
          results={results}
        />
      ) : (
        <form className="sticky-action-form" data-record-flow="restaurant-record" onSubmit={handleAdd}>
          <div className="personalize-form sticky-action-form__content">
          <button className="back-button" onClick={() => setSelectedPoi(null)} type="button"><ArrowLeft size={15} /> 返回搜索结果</button>

          <RestaurantSummarySection
            actions={{
              isInRoulette: isRouletteCandidate(selectedPoi),
              onAddToWant: () => setStatus('wantToGo'),
              onMarkVisited: () => setStatus('visited'),
              onToggleRoulette: () => onToggleRoulette(selectedPoi),
              visitedActive: status === 'visited',
              wantActive: status === 'wantToGo',
            }}
            additionalUserPhotos={photos.map((source) => ({ source }))}
            addressEditor={{ required: true, value: address, onChange: (event) => setAddress(event.target.value) }}
            className="is-form-summary"
            historyRestaurants={historyRestaurants}
            personalRatingOverride={status === 'visited' ? { score: starToTenScore(rating), count: rating ? 1 : 0, label: '我的评分' } : undefined}
            referencePrice={referencePrice}
            restaurant={createPoiPreviewRestaurant(selectedPoi, status, price, partySize)}
          />

          <div className="collection-choice" aria-label="餐厅状态" data-record-section="visit-mode-selector">
            <button className={status === 'visited' ? 'is-active' : ''} onClick={() => setStatus('visited')} type="button"><TasteMapVisitedIcon size={15} /> 我去过</button>
            <button className={status === 'wantToGo' ? 'is-active' : ''} onClick={() => setStatus('wantToGo')} type="button"><MapPin size={15} /> 我想去</button>
          </div>

          {status === 'visited' ? (
            <div className="form-section" data-record-section="visited-form">
              <h3>这次体验</h3>
              <StarRatingField onChange={setRating} value={rating} />
              <label className="field visit-feeling-field visit-note-primary"><span>笔记 <small>可选</small></span><textarea maxLength={1000} onChange={(event) => setFeeling(event.target.value)} placeholder="味道、氛围、当时的心情……想记多少都可以" rows={3} value={feeling} /></label>
              <label className="field field-with-leading-icon">
                <span>{extraFields.paymentMode === 'separate' ? '我的消费金额（元）' : '本次消费总价（元）'}</span>
                <div><WalletCards size={16} /><input inputMode="decimal" min="0" onChange={(event) => setPrice(event.target.value)} placeholder="例如 193.50" step="0.01" type="number" value={price} /></div>
                {extraFields.paymentMode !== 'separate' && calculatePricePerPerson(price ? Number(price) : null, Number(partySize)) !== null ? <small className="price-calculation">{partySize} 人 · 约 ¥{calculatePricePerPerson(Number(price), Number(partySize))}/人</small> : null}
              </label>
              <VisitExtraFields friendOptions={friendOptions} onChange={setExtraFields} section="primary" value={extraFields} />
              <div className="field-grid visit-time-grid">
                <label className="field field-with-leading-icon"><span>日期</span><div><CalendarClock size={16} /><input max="9999-12-31" onChange={(event) => setVisitDate(event.target.value)} required type="date" value={visitDate} /></div></label>
                <label className="field"><span>时间</span><input onChange={(event) => setVisitTime(event.target.value)} required type="time" value={visitTime} /></label>
              </div>
              <div className="field-grid party-grid">
                <label className="field field-with-leading-icon"><span>用餐人数</span><div><Users size={16} /><input inputMode="numeric" min="1" onChange={(event) => setPartySize(event.target.value)} required step="1" type="number" value={partySize} /></div></label>
                <CompanionPicker onChange={updateCompanions} options={companionOptions} value={companions} />
              </div>
              <QueueDurationPicker onChange={setQueueDuration} value={queueDuration} />
              <VisitPhotoPicker maxPhotos={maxPhotos} onChange={(nextPhotos) => setPhotos(nextPhotos)} photoIds={photos.map(() => null)} upgradeAvailable={photoUpgradeAvailable} value={photos} />
              <DishEditor onChange={setDishes} value={dishes} />
              <VisitExtraFields friendOptions={friendOptions} onChange={setExtraFields} section="details" value={extraFields} />
            </div>
          ) : <div className="form-section want-to-go-details" data-record-section="want-to-go-form">
            <h3><MapPin size={15} /> 想吃计划</h3>
            <p>记录预计消费，方便下次决定去哪家。</p>
            <label className="field field-with-leading-icon"><span>预计人均价格（元）</span><div><WalletCards size={16} /><input inputMode="decimal" min="0" onChange={(event) => setPrice(event.target.value)} placeholder="例如 180.00" step="0.01" type="number" value={price} /></div></label>
          </div>}

          <div className="form-section" data-record-section="restaurant-display-settings">
            <h3>整理与显示</h3>
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

          </div>
          <StickyFormActionBar primaryDisabled={!address.trim()} primaryLabel="保存到我的地图" primaryLoading={saving} secondaryAction={onClose} statusMessage={error} statusTone="error" />
        </form>
      )}
    </ModalShell>
  )
}

function createPoiPreviewRestaurant(poi: PoiSearchResult, status: RestaurantStatus, price: string, partySize: string): RestaurantSummary {
  const numericPrice = price ? Number(price) : null
  const referencePrice = status === 'visited'
    ? calculatePricePerPerson(numericPrice, Number(partySize))
    : numericPrice
  const now = new Date().toISOString()
  return {
    id: `preview-${poi.amapPoiId}`,
    userId: CURRENT_USER_ID,
    amapPoiId: poi.amapPoiId,
    name: poi.name,
    address: poi.address,
    city: poi.city,
    latitude: poi.latitude,
    longitude: poi.longitude,
    status,
    preferenceLevel: 'normal',
    overallRating: null,
    foodRating: null,
    environmentRating: null,
    serviceRating: null,
    valueRating: null,
    tags: [],
    longTermNote: '',
    pricePerPerson: referencePrice,
    phone: poi.phone ?? null,
    openingHours: poi.openingHours ?? null,
    markerType: poi.merchantImageUrl ? 'image' : 'emoji',
    markerImageData: null,
    markerPhotoId: null,
    merchantImageUrl: poi.merchantImageUrl,
    markerEmoji: '🍽️',
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    visitCount: 0,
    averageRating: null,
    scoreOutOfTen: null,
    latestVisitDate: null,
    latestVisit: null,
    visits: [],
    averagePricePerPerson: referencePrice,
    averageQueueMinutes: null,
    isRecommendation: status === 'wantToGo',
  }
}

interface SearchStepProps {
  city: string
  error: string
  existingRestaurantsByPoiId: Map<string, RestaurantSummary>
  hasSearched: boolean
  keyword: string
  locatingCity: boolean
  loading: boolean
  nearbyLoading: boolean
  locationLabel: string
  nearbyMessage: string
  nearbyResults: PoiSearchResult[]
  externalLink: string
  externalLinkLoading: boolean
  externalLinkResult: ExternalLinkResolveResult | null
  results: PoiSearchResult[]
  onCityChange: (value: string) => void
  onKeywordChange: (value: string) => void
  onExternalLinkChange: (value: string) => void
  onExternalLinkResolve: (event: FormEvent) => void
  onManualAdd: () => void
  onRetryLocation: () => void
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
  nearbyLoading,
  locationLabel,
  nearbyMessage,
  nearbyResults,
  externalLink,
  externalLinkLoading,
  externalLinkResult,
  results,
  onCityChange,
  onKeywordChange,
  onExternalLinkChange,
  onExternalLinkResolve,
  onManualAdd,
  onRetryLocation,
  onChoose,
  onRecordExisting,
  onSearch,
}: SearchStepProps) {
  const [shareIngestionOpen, setShareIngestionOpen] = useState(false)
  return (
    <>
      {!mapService.isConfigured ? (
        <div className="config-notice"><TriangleAlert size={19} /><div><strong>还需要配置高德地图</strong><p>填入高德 Key 和安全密钥后，餐厅搜索就会启用。</p></div></div>
      ) : null}
      <TasteMapRestaurantAcquisitionScaffold
        nearby={<>
          <TasteMapRestaurantAcquisitionStatus
            detail={nearbyLoading
              ? '只接受足够新鲜、精度合理的当前位置'
              : nearbyMessage || (locationLabel ? `${locationLabel} · 3 公里内按实际距离排序` : '附近搜索已完成')}
            onRetry={onRetryLocation}
            retryLabel="重新定位"
            state={nearbyLoading ? 'loading' : nearbyMessage ? 'error' : 'ready'}
            title={nearbyLoading ? '正在取得新鲜位置' : nearbyMessage ? '暂时无法取得精确位置' : '当前位置已更新'}
          />
          {!nearbyLoading ? <PoiResultList existingRestaurantsByPoiId={existingRestaurantsByPoiId} onChoose={onChoose} onRecordExisting={onRecordExisting} results={nearbyResults} /> : null}
        </>}
        onOpenManual={onManualAdd}
        onOpenShare={() => setShareIngestionOpen((value) => !value)}
        search={<>
          <TasteMapRestaurantAcquisitionSearch
            autoFocus
            city={city}
            cityPlaceholder="杭州"
            disabled={!mapService.isConfigured}
            loading={loading}
            locationDetail={locatingCity
              ? <><LocateFixed aria-hidden="true" size={13} />正在取得精确位置</>
              : locationLabel ? <><LocateFixed aria-hidden="true" size={13} />已定位：{locationLabel}</> : null}
            onCityChange={onCityChange}
            onQueryChange={onKeywordChange}
            onSubmit={onSearch}
            query={keyword}
            queryPlaceholder="例如：寿喜烧、南京西路"
          />
          {error ? <p className="form-error">{error}</p> : null}
          <div className="poi-results" aria-live="polite">
            <PoiResultList existingRestaurantsByPoiId={existingRestaurantsByPoiId} onChoose={onChoose} onRecordExisting={onRecordExisting} results={results} />
            {hasSearched && !loading && !error && results.length === 0 ? <div className="empty-results"><Search size={21} /><strong>没有找到匹配的餐厅或地点，请尝试其他关键词。</strong></div> : null}
            {!hasSearched ? <div className="search-hint"><span>搜索建议</span><p>名称太常见时，加上城市会更准确，例如“杭州 寿喜烧”。</p></div> : null}
          </div>
        </>}
        sharePanel={shareIngestionOpen ? <section className="tm-acquisition__share-panel" data-secondary-share-ingestion="true">
          <form className="external-link-import__form" onSubmit={onExternalLinkResolve}>
            <div className="input-with-icon"><Link2 size={16} /><input onChange={(event) => onExternalLinkChange(event.target.value)} placeholder="粘贴来自地图或网页的分享内容" value={externalLink} /></div>
            <button className="secondary-button" disabled={externalLinkLoading || !externalLink.trim()} type="submit">{externalLinkLoading ? <LoaderCircle className="spin" size={16} /> : '识别'}</button>
          </form>
          {externalLinkResult ? <div className={`external-link-import__result is-${externalLinkResult.confidence.toLowerCase()}`}>
            <p><strong>{externalLinkResult.message}</strong><span>推荐来源建议：{externalLinkResult.sourceSuggestion}（保存前可修改）</span></p>
            {externalLinkResult.candidates.length ? <PoiResultList existingRestaurantsByPoiId={existingRestaurantsByPoiId} onChoose={onChoose} onRecordExisting={onRecordExisting} results={externalLinkResult.candidates} /> : null}
          </div> : null}
        </section> : undefined}
      />
    </>
  )
}

function PoiResultList({
  existingRestaurantsByPoiId,
  results,
  onChoose,
  onRecordExisting,
}: Pick<SearchStepProps, 'existingRestaurantsByPoiId' | 'results' | 'onChoose' | 'onRecordExisting'>) {
  return <TasteMapRestaurantAcquisitionResults items={results.map((poi) => {
    const existingRestaurant = existingRestaurantsByPoiId.get(poi.amapPoiId)
    return {
      id: poi.amapPoiId,
      name: poi.name,
      meta: `${poi.city}${poi.district ? ` · ${poi.district}` : ''}${poi.address ? ` · ${poi.address}` : ''}`,
      image: poi.merchantImageUrl
        ? <img alt="" src={poi.merchantImageUrl} />
        : <span className="tm-acquisition-result__fallback"><MapPin aria-hidden="true" size={18} /></span>,
      actionLabel: existingRestaurant ? '再次记录' : '查看',
      onOpen: existingRestaurant ? () => onRecordExisting(existingRestaurant) : () => onChoose(poi),
    }
  })} />
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
      const current = await mapService.detectCurrentLocation()
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
      const resolved = location ?? await mapService.resolveAddressLocation(address, city)
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
    <form className="sticky-action-form" onSubmit={continueWithManualRestaurant}>
      <div className="manual-restaurant-form sticky-action-form__content">
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
      </div>
      <StickyFormActionBar
        primaryDisabled={!name.trim() || !address.trim() || !city.trim()}
        primaryLabel="确认位置并继续"
        primaryLoading={resolving}
        secondaryAction={onBack}
      />
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
