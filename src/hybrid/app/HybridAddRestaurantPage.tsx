import { type FormEvent, useCallback, useEffect, useState } from 'react'
import { ChevronRight, LoaderCircle, MapPin, Search, X } from 'lucide-react'
import type { TasteMapAcquisitionCandidateDTO, TasteMapAcquisitionResultsDTO, TasteMapPlatform } from '../../platform/TasteMapPlatform'
import { HybridRestaurantImage } from '../../components/TasteMapHybridShared'
import { TasteMapRestaurantAcquisitionScaffold } from '../../components/TasteMapRestaurantAcquisitionShared'

type LoadState = 'idle' | 'loading' | 'ready' | 'error'

export function HybridAddRestaurantPage({ platform, onOpenRestaurant }: { platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void }) {
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

  const loadNearby = useCallback(() => {
    setNearbyState('loading')
    void platform.acquisition.nearby()
      .then((value) => { setNearbyResult(value); setNearbyState('ready') })
      .catch(() => setNearbyState('error'))
  }, [platform])

  const loadShared = useCallback((showPanel = false) => {
    if (showPanel) setShareOpen(true)
    setShareState('loading')
    void platform.acquisition.shared()
      .then((value) => { setShareResult(value); setShareState('ready') })
      .catch(() => setShareState('error'))
  }, [platform])

  useEffect(() => { loadNearby(); loadShared(false) }, [loadNearby, loadShared])
  useEffect(() => {
    let remove: (() => Promise<void>) | undefined
    void platform.events.subscribe((event) => {
      if (event.name === 'shareExtension.received') loadShared(true)
      if (event.name === 'app.lifecycle' && event.payload.state === 'resume') loadNearby()
    }).then((subscription) => { remove = () => subscription.remove() })
    return () => { void remove?.() }
  }, [loadNearby, loadShared, platform])

  async function submitSearch(event: FormEvent) {
    event.preventDefault()
    const normalized = query.trim()
    if (!normalized) return
    setSearchState('loading')
    try {
      setSearchResult(await platform.acquisition.search(normalized, city.trim()))
      setSearchState('ready')
    } catch {
      setSearchState('error')
    }
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
    <TasteMapRestaurantAcquisitionScaffold
      pageHeader
      onOpenManual={() => setManualOpen((value) => !value)}
      onOpenShare={() => { setShareOpen((value) => !value); if (!shareResult) loadShared(true) }}
      search={<>
        <form className="tm-hybrid-add-search-form" onSubmit={(event) => void submitSearch(event)}>
          <div className="tm-hybrid-add-search-row">
            <label className="tm-hybrid-add-search"><Search aria-hidden="true" size={17} /><input autoComplete="off" onChange={(event) => setQuery(event.target.value)} placeholder="例如：寿喜烧、南京西路" value={query} /></label>
            <button disabled={searchState === 'loading' || !query.trim()} type="submit">{searchState === 'loading' ? <LoaderCircle className="spin" size={16} /> : '搜索'}</button>
          </div>
          <label className="tm-hybrid-add-city"><span>城市</span><input onChange={(event) => setCity(event.target.value)} placeholder="例如：杭州" value={city} /></label>
        </form>
        {searchState === 'error' ? <InlineState>搜索失败，请检查网络后重试；附近和手动添加仍可使用。</InlineState> : null}
        {searchResult ? <CandidateResults result={searchResult} onOpen={openCandidate} /> : null}
      </>}
      nearby={<>
        <LocationState result={nearbyResult} state={nearbyState} onRetry={loadNearby} />
        {nearbyResult ? <CandidateResults result={nearbyResult} onOpen={openCandidate} /> : null}
      </>}
      sharePanel={shareOpen ? <section className="tm-hybrid-acquisition-panel is-share">
        <button aria-label="关闭外部分享结果" className="tm-hybrid-acquisition-panel__close" onClick={() => setShareOpen(false)} type="button"><X size={16} /></button>
        <h3>外部分享识别结果</h3>
        {shareState === 'loading' ? <InlineState>正在读取 Apple 地图、高德地图、URL 或分享文字…</InlineState> : null}
        {shareState === 'error' ? <InlineState>分享内容暂时无法识别；仍可按名称搜索或手动添加。</InlineState> : null}
        {shareResult ? <CandidateResults result={shareResult} onOpen={openCandidate} /> : null}
      </section> : null}
    />
    {manualOpen ? <section className="tm-hybrid-manual-panel" aria-label="手动添加餐厅">
      <header><div><strong>手动添加餐厅</strong><small>适用于地图上搜不到的餐厅；地址将由正式地图服务定位。</small></div><button aria-label="关闭手动添加" onClick={() => setManualOpen(false)} type="button"><X size={17} /></button></header>
      <form onSubmit={(event) => void submitManual(event)}>
        <label><span>餐厅名称</span><input name="name" required /></label>
        <label><span>城市</span><input name="city" required /></label>
        <label><span>地址</span><input name="address" required /></label>
        {manualError ? <p role="alert">{manualError}</p> : null}
        <button disabled={manualState === 'loading'} type="submit">{manualState === 'loading' ? '正在定位地址…' : '确认餐厅位置'}</button>
      </form>
    </section> : null}
  </main>
}

function CandidateResults({ result, onOpen }: { result: TasteMapAcquisitionResultsDTO; onOpen: (candidate: TasteMapAcquisitionCandidateDTO) => Promise<void> }) {
  return <>{result.candidates.length ? <div className="tm-hybrid-search-results">{result.candidates.map((item) => <button key={item.id} onClick={() => void onOpen(item)} type="button"><HybridRestaurantImage image={item.image} name={item.name} resolution={item.imageResolution} /><span><strong>{item.name}{item.duplicateKind !== 'none' ? <b>{item.duplicateKind === 'exactProvider' ? '已在地图' : '可能重复'}</b> : null}</strong><small>{item.city}{item.city && item.address ? ' · ' : ''}{item.address}</small>{item.distanceMeters != null ? <em>{distanceText(item.distanceMeters)}</em> : null}</span><ChevronRight aria-hidden="true" size={17} /></button>)}</div> : result.message ? <InlineState>{result.message}</InlineState> : null}</>
}

function LocationState({ result, state, onRetry }: { result: TasteMapAcquisitionResultsDTO | null; state: LoadState; onRetry: () => void }) {
  const location = result?.location
  return <div className={`tm-hybrid-location-status is-${state}`}><MapPin aria-hidden="true" size={16} /><span><strong>{state === 'ready' ? location ? '当前位置已更新' : '附近搜索已完成' : state === 'loading' ? '正在取得新鲜位置' : '暂时无法取得精确位置'}</strong><small>{location ? `精度约 ${Math.round(location.horizontalAccuracy)} 米 · ${location.accuracyMode === 'reduced' ? '约略位置' : '精确位置'}` : state === 'error' ? '搜索和手动添加仍可使用，不采用城市中心兜底' : '只接受足够新鲜、精度合理的 CLLocation'}</small></span>{state === 'error' ? <button onClick={onRetry} type="button">重试</button> : null}</div>
}

function InlineState({ children }: { children: string }) { return <p className="tm-acquisition__inline-state">{children}</p> }

function distanceText(distance: number) { return distance < 1_000 ? `${Math.round(distance)} 米` : `${(distance / 1_000).toFixed(1)} 公里` }
