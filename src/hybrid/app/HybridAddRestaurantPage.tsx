import { type FormEvent, useCallback, useEffect, useState } from 'react'
import { Building2, MapPin, Store, X } from 'lucide-react'
import type { TasteMapAcquisitionCandidateDTO, TasteMapAcquisitionResultsDTO, TasteMapPlatform } from '../../platform/TasteMapPlatform'
import { HybridRestaurantImage } from '../../components/TasteMapHybridShared'
import {
  TasteMapRestaurantAcquisitionResults,
  TasteMapRestaurantAcquisitionScaffold,
  TasteMapRestaurantAcquisitionSearch,
  TasteMapRestaurantAcquisitionStatus,
} from '../../components/TasteMapRestaurantAcquisitionShared'

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
        <TasteMapRestaurantAcquisitionSearch
          city={city}
          loading={searchState === 'loading'}
          onCityChange={setCity}
          onQueryChange={setQuery}
          onSubmit={(event) => void submitSearch(event)}
          query={query}
        />
        {searchState === 'error' ? <InlineState>搜索失败，请检查网络后重试；附近和手动添加仍可使用。</InlineState> : null}
        {searchResult ? <CandidateResults result={searchResult} onOpen={openCandidate} /> : null}
      </>}
      nearby={<>
        <LocationState state={nearbyState} onRetry={loadNearby} />
        {nearbyResult ? <CandidateResults result={nearbyResult} onOpen={openCandidate} /> : null}
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

function CandidateResults({ result, onOpen }: { result: TasteMapAcquisitionResultsDTO; onOpen: (candidate: TasteMapAcquisitionCandidateDTO) => Promise<void> }) {
  return <>{result.candidates.length ? <TasteMapRestaurantAcquisitionResults items={result.candidates.map((item) => ({
    id: item.id,
    name: item.name,
    meta: `${item.city}${item.city && item.address ? ' · ' : ''}${item.address}`,
    supportingText: item.distanceMeters != null ? distanceText(item.distanceMeters) : null,
    badge: item.duplicateKind === 'none' ? null : item.duplicateKind === 'exactProvider' ? '已在地图' : '可能重复',
    image: <HybridRestaurantImage image={item.image} name={item.name} resolution={item.imageResolution} />,
    onOpen: () => void onOpen(item),
  }))} /> : result.message ? <InlineState>{result.message}</InlineState> : null}</>
}

function LocationState({ state, onRetry }: { state: LoadState; onRetry: () => void }) {
  if (state === 'ready') return null
  return <TasteMapRestaurantAcquisitionStatus
    detail={state === 'error' ? '搜索和手动添加仍可使用，不采用城市中心兜底' : '只接受足够新鲜、精度合理的当前位置'}
    onRetry={onRetry}
    state={state}
    title={state === 'loading' ? '正在取得新鲜位置' : '暂时无法取得精确位置'}
  />
}

function InlineState({ children }: { children: string }) { return <p className="tm-acquisition__inline-state">{children}</p> }

function distanceText(distance: number) { return distance < 1_000 ? `${Math.round(distance)} 米` : `${(distance / 1_000).toFixed(1)} 公里` }
