import { useState, type FormEvent, type ReactNode } from 'react'
import { Building2, ChevronRight, LoaderCircle, LocateFixed, Search, Share2, Store } from 'lucide-react'
import './tasteMapRestaurantAcquisitionShared.css'

interface TasteMapRestaurantAcquisitionScaffoldProps {
  pageHeader?: boolean
  search: ReactNode
  nearby: ReactNode
  onOpenShare: () => void
  onOpenManual: () => void
  sharePanel?: ReactNode
  manualPanel?: ReactNode
}

interface TasteMapRestaurantAcquisitionSearchProps {
  query: string
  city: string
  loading: boolean
  disabled?: boolean
  autoFocus?: boolean
  queryPlaceholder?: string
  cityPlaceholder?: string
  locationDetail?: ReactNode
  onQueryChange: (value: string) => void
  onCityChange: (value: string) => void
  onSubmit: (event: FormEvent<HTMLFormElement>) => void
}

interface TasteMapRestaurantAcquisitionStatusProps {
  state: 'idle' | 'loading' | 'error' | 'empty'
  title: string
  detail: string
  onRetry?: () => void
  retryLabel?: string
}

export interface TasteMapRestaurantAcquisitionResultItem {
  id: string
  name: string
  meta: string
  supportingText?: string | null
  badge?: string | null
  image: ReactNode
  actionLabel?: string
  onOpen: () => void
}

/**
 * Canonical Add Restaurant product skeleton shared by formal Web and Hybrid.
 * Adapters provide data/capability behavior; they do not redraw the hierarchy.
 */
export function TasteMapRestaurantAcquisitionScaffold({
  pageHeader = false,
  search,
  nearby,
  onOpenShare,
  onOpenManual,
  sharePanel,
  manualPanel,
}: TasteMapRestaurantAcquisitionScaffoldProps) {
  return <div className="tm-acquisition" data-product-contract="restaurant-acquisition">
    {pageHeader ? <header className="tm-acquisition__page-header">
      <h1>添加餐厅</h1>
      <p>搜索、定位、分享，或补充地图上没有的餐厅</p>
    </header> : null}
    <section className="tm-acquisition__section" data-acquisition-capability="search">
      <header><span className="tm-acquisition__section-icon"><Search aria-hidden="true" size={17} /></span><span><strong>搜索餐厅</strong><small>名称、地址与城市范围</small></span></header>
      {search}
    </section>
    <section className="tm-acquisition__section" data-acquisition-capability="nearby">
      <header><span className="tm-acquisition__section-icon"><LocateFixed aria-hidden="true" size={17} /></span><span><strong>附近餐厅</strong><small>当前位置 3 公里内，按直线距离排序</small></span></header>
      {nearby}
    </section>
    <div className="tm-acquisition__secondary-actions">
      <button aria-label="从外部分享添加" data-acquisition-capability="share" onClick={onOpenShare} type="button">
        <span className="tm-acquisition__section-icon"><Share2 aria-hidden="true" size={17} /></span><span><strong>从外部分享添加</strong><small>Apple 地图、高德地图、网页 URL 或分享文字</small></span><ChevronRight aria-hidden="true" size={17} />
      </button>
      {sharePanel}
      <button aria-label="手动添加餐厅" data-acquisition-capability="manual" onClick={onOpenManual} type="button">
        <span className="tm-acquisition__section-icon"><Store aria-hidden="true" size={17} /></span><span><strong>手动添加餐厅</strong><small>适合地图上搜不到的小摊、快闪店、私房店和新开门店</small></span><ChevronRight aria-hidden="true" size={17} />
      </button>
      {manualPanel}
    </div>
  </div>
}

/**
 * Canonical Search + City controls for Restaurant acquisition.
 * Both inputs deliberately render at 16px so focusing them in WKWebView never
 * invokes WebKit's accessibility-hostile automatic page zoom.
 */
export function TasteMapRestaurantAcquisitionSearch({
  query,
  city,
  loading,
  disabled = false,
  autoFocus = false,
  queryPlaceholder = '例如：寿喜烧、南京西路',
  cityPlaceholder = '例如：杭州',
  locationDetail,
  onQueryChange,
  onCityChange,
  onSubmit,
}: TasteMapRestaurantAcquisitionSearchProps) {
  return <form className="tm-acquisition-search" data-shared-acquisition-component="search-city" onSubmit={onSubmit}>
    <label className="tm-acquisition-field is-query">
      <span className="tm-acquisition-field__icon"><Search aria-hidden="true" size={17} /></span>
      <span className="tm-acquisition-field__body"><small>餐厅名称或地址</small><input
        aria-label="餐厅名称或地址"
        autoComplete="off"
        autoFocus={autoFocus}
        data-acquisition-input="query"
        onChange={(event) => onQueryChange(event.target.value)}
        placeholder={queryPlaceholder}
        value={query}
      /></span>
    </label>
    <div className="tm-acquisition-search__secondary-row">
      <label className="tm-acquisition-field is-city" data-location-semantic="city-not-gps">
        <span className="tm-acquisition-field__icon"><Building2 aria-hidden="true" size={17} /></span>
        <span className="tm-acquisition-field__body"><small>城市</small><input
          aria-label="城市"
          autoComplete="address-level2"
          data-acquisition-input="city"
          onChange={(event) => onCityChange(event.target.value)}
          placeholder={cityPlaceholder}
          value={city}
        /></span>
      </label>
      <button
        aria-label="搜索餐厅"
        className="tm-acquisition-search__submit"
        data-search-action="compact-icon"
        disabled={disabled || loading || !query.trim()}
        title="搜索餐厅"
        type="submit"
      >
        {loading ? <LoaderCircle aria-hidden="true" className="spin" size={17} /> : <Search aria-hidden="true" size={17} />}
      </button>
    </div>
    {locationDetail ? <div className="tm-acquisition-search__location-detail">{locationDetail}</div> : null}
  </form>
}

export function TasteMapRestaurantAcquisitionStatus({
  state,
  title,
  detail,
  onRetry,
  retryLabel = '重试',
}: TasteMapRestaurantAcquisitionStatusProps) {
  return <div className={`tm-acquisition-status is-${state}`} data-acquisition-state={state} data-shared-acquisition-component="nearby-status">
    <span className="tm-acquisition-status__icon">{state === 'loading'
      ? <LoaderCircle aria-hidden="true" className="spin" size={17} />
      : <LocateFixed aria-hidden="true" size={17} />}</span>
    <span className="tm-acquisition-status__body"><strong>{title}</strong><small>{detail}</small></span>
    {(state === 'error' || state === 'empty') && onRetry ? <button onClick={onRetry} type="button">{retryLabel}</button> : null}
  </div>
}

/** Nearby is one immutable, complete provider snapshot. Expanding it is local
 * presentation only: no location/provider callback belongs in this control. */
export function TasteMapRestaurantAcquisitionResults({ items, nearbySnapshot }: {
  items: TasteMapRestaurantAcquisitionResultItem[]
  nearbySnapshot?: object
}) {
  const [expanded, setExpanded] = useState<{ snapshot?: object; count: number }>({ count: 12 })
  const visibleCount = nearbySnapshot ? Math.min(items.length, expanded.snapshot === nearbySnapshot ? expanded.count : 12) : items.length
  return <><div className="tm-acquisition-results" data-shared-acquisition-component="candidate-results" data-nearby-total={nearbySnapshot ? items.length : undefined} data-nearby-visible={nearbySnapshot ? visibleCount : undefined}>{items.slice(0, visibleCount).map((item) => <button
    aria-label={`${item.actionLabel ?? '查看'} ${item.name}`}
    key={item.id}
    onClick={item.onOpen}
    type="button"
  >
    <span className="tm-acquisition-result__image">{item.image}</span>
    <span className="tm-acquisition-result__body"><strong>{item.name}{item.badge ? <b>{item.badge}</b> : null}</strong><small>{item.meta}</small>{item.supportingText ? <em>{item.supportingText}</em> : null}</span>
    <span className="tm-acquisition-result__action">{item.actionLabel ?? '查看'}<ChevronRight aria-hidden="true" size={15} /></span>
  </button>)}</div>{nearbySnapshot && visibleCount < items.length ? <button
    className="tm-acquisition-load-more"
    onClick={() => setExpanded((previous) => ({ snapshot: nearbySnapshot, count: Math.min(items.length, (previous.snapshot === nearbySnapshot ? previous.count : 12) + 12) }))}
    type="button"
  >继续加载附近餐厅<span>（已显示 {visibleCount} / {items.length} 家）</span></button> : null}</>
}
