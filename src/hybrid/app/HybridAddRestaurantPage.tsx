import { type FormEvent, useCallback, useEffect, useRef, useState } from 'react'
import { Building2, MapPin, Store, X } from 'lucide-react'
import type { TasteMapAcquisitionCandidateDTO, TasteMapAcquisitionResultsDTO, TasteMapPlatform } from '../../platform/TasteMapPlatform'
import { HybridBackButton, HybridRestaurantImage } from '../../components/TasteMapHybridShared'
import {
  TasteMapRestaurantAcquisitionResults,
  TasteMapRestaurantAcquisitionScaffold,
  TasteMapRestaurantAcquisitionSearch,
  TasteMapRestaurantAcquisitionStatus,
} from '../../components/TasteMapRestaurantAcquisitionShared'

type LoadState = 'idle' | 'loading' | 'ready' | 'error'

export function HybridAddRestaurantPage({ platform, onOpenRestaurant, onBack }: { platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void; onBack?: () => void }) {
  const [query, setQuery] = useState('')
  const [city, setCity] = useState('')
  const [searchState, setSearchState] = useState<LoadState>('idle')
  const [searchResult, setSearchResult] = useState<TasteMapAcquisitionResultsDTO | null>(null)
  const [nearbyState, setNearbyState] = useState<LoadState>('loading')
  const [nearbyResult, setNearbyResult] = useState<TasteMapAcquisitionResultsDTO | null>(null)
  const [shareOpen, setShareOpen] = useState(false)
  const [shareState, setShareState] = useState<LoadState>('idle')
  const [shareResult, setShareResult] = useState<TasteMapAcquisitionResultsDTO | null>(null)
  const [manualOpen, setManualOpen] = useState(false)
  const [manualState, setManualState] = useState<LoadState>('idle')
  const [manualError, setManualError] = useState('')
  const cityEditedRef = useRef(false)
  const nearbyRequestRef = useRef(0)
  const searchRequestRef = useRef(0)
  const shareRequestRef = useRef(0)
  const submittedSearchRef = useRef({ query: '', city: '' })
  const [nearbyError, setNearbyError] = useState('')
  const nearbyLocationRef = useRef<TasteMapAcquisitionResultsDTO['location']>(null)
  const latestLocationRef = useRef<TasteMapAcquisitionResultsDTO['location']>(null)

  const invalidateNearby = useCallback(() => {
    ++nearbyRequestRef.current
    nearbyLocationRef.current = null
    setNearbyResult(null)
    setNearbyError('附近结果已失效，请重新查找。')
    setNearbyState('error')
  }, [])

  const loadNearby = useCallback(() => {
    const requestID = ++nearbyRequestRef.current
    setNearbyState('loading')
    setNearbyResult(null)
    setNearbyError('')
    nearbyLocationRef.current = null
    latestLocationRef.current = null
    void platform.acquisition.nearby()
      .then((value) => {
        if (requestID !== nearbyRequestRef.current) return
        const latest = latestLocationRef.current
        if (value.location && latest && Date.parse(latest.timestamp) >= Date.parse(value.location.timestamp)
          && (latest.latitude !== value.location.latitude || latest.longitude !== value.location.longitude)) {
          invalidateNearby()
          return
        }
        if (!cityEditedRef.current && value.detectedCity?.trim()) {
          setCity(normalizeDetectedCity(value.detectedCity))
        }
        setNearbyResult(value)
        nearbyLocationRef.current = value.location
        setNearbyState('ready')
      })
      .catch((error: unknown) => {
        if (requestID !== nearbyRequestRef.current) return
        setNearbyError((error as { code?: string })?.code === 'location_precise_required'
          ? '请在系统设置中为味图开启精确位置，再重新查找。城市搜索仍可使用。' : '')
        setNearbyState('error')
      })
  }, [invalidateNearby, platform])

  const loadShared = useCallback((showPanel = false) => {
    const requestID = ++shareRequestRef.current
    if (showPanel) setShareOpen(true)
    setShareState('loading')
    void platform.acquisition.shared()
      .then((value) => {
        if (requestID !== shareRequestRef.current) return
        setShareResult(value); setShareState('ready')
      })
      .catch(() => { if (requestID === shareRequestRef.current) setShareState('error') })
  }, [platform])

  useEffect(() => {
    loadNearby(); loadShared(false)
    return () => {
      ++nearbyRequestRef.current
      ++searchRequestRef.current
      ++shareRequestRef.current
    }
  }, [loadNearby, loadShared])
  useEffect(() => {
    let disposed = false
    let remove: (() => Promise<void>) | undefined
    void platform.events.subscribe((event) => {
      if (disposed) return
      if (event.name === 'shareExtension.received') loadShared(true)
      if (event.name === 'app.lifecycle' && event.payload.state === 'resume') loadNearby()
      if (event.name === 'app.lifecycle' && event.payload.state === 'background') invalidateNearby()
      if (event.name === 'auth.changed') invalidateNearby()
      if (event.name === 'location.changed') {
        const accepted = nearbyLocationRef.current
        const updated = event.payload
        if (!latestLocationRef.current || Date.parse(updated.timestamp) >= Date.parse(latestLocationRef.current.timestamp)) latestLocationRef.current = updated
        if (accepted && Date.parse(updated.timestamp) >= Date.parse(accepted.timestamp)
          && (updated.latitude !== accepted.latitude || updated.longitude !== accepted.longitude)) invalidateNearby()
      }
    }).then((subscription) => {
      if (disposed) void subscription.remove()
      else remove = () => subscription.remove()
    }).catch(() => { /* Initial and manual retry remain available without lifecycle events. */ })
    return () => { disposed = true; void remove?.() }
  }, [invalidateNearby, loadNearby, loadShared, platform])

  async function submitSearch(event: FormEvent) {
    event.preventDefault()
    const normalized = query.trim()
    if (!normalized) return
    submittedSearchRef.current = { query: normalized, city: city.trim() }
    setSearchResult(null)
    await loadSearch()
  }

  async function loadSearch(cursor?: string | null) {
    const requestID = ++searchRequestRef.current
    setSearchState('loading')
    try {
      const submitted = submittedSearchRef.current
      const result = await platform.acquisition.search(submitted.query, submitted.city, { cursor })
      if (requestID !== searchRequestRef.current) return
      setSearchResult((previous) => cursor && previous ? {
        ...result,
        candidates: [...previous.candidates, ...result.candidates.filter((item) => !previous.candidates.some((old) => old.id === item.id))],
      } : result)
      setSearchState('ready')
    } catch {
      if (requestID === searchRequestRef.current) setSearchState('error')
    }
  }

  function invalidateSearch() {
    ++searchRequestRef.current
    setSearchResult(null)
    setSearchState('idle')
  }

  async function openCandidate(candidate: TasteMapAcquisitionCandidateDTO) {
    const confirmedProbable = candidate.duplicateKind === 'probableCrossProvider'
      ? window.confirm(`“${candidate.name}”可能与地图中的现有餐厅重复。确认这是同一家餐厅并继续？`)
      : false
    if (candidate.duplicateKind === 'probableCrossProvider' && !confirmedProbable) return
    const selected = await platform.acquisition.select(candidate.id, confirmedProbable)
    onOpenRestaurant(selected.restaurantID)
  }

  async function submitManual(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setManualState('loading')
    setManualError('')
    const values = new FormData(event.currentTarget)
    try {
      const result = await platform.acquisition.manual({
        name: String(values.get('name') ?? ''),
        city: String(values.get('city') ?? ''),
        address: String(values.get('address') ?? ''),
      })
      const candidate = result.candidates[0]
      if (!candidate) throw new Error(result.message || '无法确认这个地址。')
      setManualState('ready')
      await openCandidate(candidate)
    } catch (error) {
      setManualState('error')
      setManualError(error instanceof Error ? error.message : '手动添加暂时不可用。')
    }
  }

  return <main className="tm-hybrid-page tm-hybrid-add">
    <HybridBackButton onBack={onBack} />
    <TasteMapRestaurantAcquisitionScaffold
      pageHeader
      onOpenManual={() => setManualOpen((value) => !value)}
      onOpenShare={() => { setShareOpen((value) => !value); if (!shareResult) loadShared(true) }}
      search={<>
        <TasteMapRestaurantAcquisitionSearch
          city={city}
          loading={searchState === 'loading'}
          onCityChange={(value) => {
            cityEditedRef.current = true
            invalidateSearch()
            setCity(value)
          }}
          onQueryChange={(value) => { invalidateSearch(); setQuery(value) }}
          onSubmit={(event) => void submitSearch(event)}
          query={query}
        />
        {searchState === 'error' ? <InlineState>搜索失败，请检查网络后重试；附近和手动添加仍可使用。</InlineState> : null}
        {searchResult ? <CandidateResults result={searchResult} onOpen={openCandidate} /> : null}
        {searchResult?.nextCursor ? <button className="tm-acquisition-load-more" disabled={searchState === 'loading'} onClick={() => void loadSearch(searchResult.nextCursor)} type="button">{searchState === 'loading' ? '正在加载…' : '继续加载餐厅'}</button> : null}
      </>}
      nearby={<>
        <LocationState state={nearbyState} onRetry={loadNearby} detail={nearbyError} />
        {nearbyResult?.candidates.length ? <CandidateResults result={nearbyResult} onOpen={openCandidate} nearbySnapshot={nearbyResult} /> : null}
        {nearbyState === 'ready' && nearbyResult?.message ? <TasteMapRestaurantAcquisitionStatus
          detail={nearbyResult.message}
          onRetry={loadNearby}
          retryLabel="重新查找"
          state="empty"
          title="附近结果暂时为空"
        /> : null}
      </>}
      sharePanel={shareOpen ? <section className="tm-acquisition__expansion is-share">
        <button aria-label="关闭外部分享结果" className="tm-acquisition__expansion-close" onClick={() => setShareOpen(false)} type="button"><X size={16} /></button>
        <h3>外部分享识别结果</h3>
        {shareState === 'loading' ? <InlineState>正在读取 Apple 地图、高德地图、URL 或分享文字…</InlineState> : null}
        {shareState === 'error' ? <InlineState>分享内容暂时无法识别；仍可按名称搜索或手动添加。</InlineState> : null}
        {shareResult ? <CandidateResults result={shareResult} onOpen={openCandidate} /> : null}
      </section> : null}
      manualPanel={manualOpen ? <section className="tm-acquisition__expansion is-manual" aria-label="手动添加餐厅表单">
        <button aria-label="关闭手动添加" className="tm-acquisition__expansion-close" onClick={() => setManualOpen(false)} type="button"><X size={17} /></button>
        <h3>补充地图上没有的餐厅</h3>
        <form className="tm-acquisition__manual-form" onSubmit={(event) => void submitManual(event)}>
          <label className="tm-acquisition-field"><span className="tm-acquisition-field__icon"><Store aria-hidden="true" size={17} /></span><span className="tm-acquisition-field__body"><small>餐厅名称</small><input aria-label="手动添加餐厅名称" name="name" placeholder="例如：巷口小摊" required /></span></label>
          <label className="tm-acquisition-field" data-location-semantic="city-not-gps"><span className="tm-acquisition-field__icon"><Building2 aria-hidden="true" size={17} /></span><span className="tm-acquisition-field__body"><small>城市</small><input aria-label="手动添加城市" name="city" placeholder="例如：杭州" required /></span></label>
          <label className="tm-acquisition-field"><span className="tm-acquisition-field__icon"><MapPin aria-hidden="true" size={17} /></span><span className="tm-acquisition-field__body"><small>地址或附近地标</small><input aria-label="手动添加地址" name="address" placeholder="例如：武林路 32 号门口" required /></span></label>
          {manualError ? <p role="alert">{manualError}</p> : null}
          <button className="tm-acquisition__manual-submit" disabled={manualState === 'loading'} type="submit">{manualState === 'loading' ? '正在定位地址…' : '确认餐厅位置'}</button>
        </form>
      </section> : null}
    />
  </main>
}

function CandidateResults({ result, onOpen, nearbySnapshot }: { result: TasteMapAcquisitionResultsDTO; onOpen: (candidate: TasteMapAcquisitionCandidateDTO) => Promise<void>; nearbySnapshot?: object }) {
  return <>{result.candidates.length ? <TasteMapRestaurantAcquisitionResults nearbySnapshot={nearbySnapshot} items={result.candidates.map((item) => ({
    id: item.id,
    name: item.name,
    meta: `${item.city}${item.city && item.address ? ' · ' : ''}${item.address}`,
    supportingText: item.distanceMeters != null ? distanceText(item.distanceMeters) : null,
    badge: item.duplicateKind === 'none' ? null : item.duplicateKind === 'exactProvider' ? '已在地图' : '可能重复',
    image: <HybridRestaurantImage image={item.image} name={item.name} resolution={item.imageResolution} />,
    onOpen: () => void onOpen(item),
  }))} /> : result.message ? <InlineState>{result.message}</InlineState> : null}</>
}

function LocationState({ state, onRetry, detail }: { state: LoadState; onRetry: () => void; detail?: string }) {
  if (state === 'ready') return null
  return <TasteMapRestaurantAcquisitionStatus
    detail={detail || (state === 'error' ? '搜索和手动添加仍可使用，不采用城市中心兜底' : '只接受足够新鲜、精度合理的当前位置')}
    onRetry={onRetry}
    state={state}
    title={state === 'loading' ? '正在取得新鲜位置' : '暂时无法取得精确位置'}
  />
}

function InlineState({ children }: { children: string }) { return <p className="tm-acquisition__inline-state">{children}</p> }

function distanceText(distance: number) { return distance < 1_000 ? `${Math.round(distance)} 米` : `${(distance / 1_000).toFixed(1)} 公里` }

function normalizeDetectedCity(value: string) { return value.trim().replace(/市$/, '') }
