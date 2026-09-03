import { startTransition, useCallback, useEffect, useMemo, useReducer, useRef, useState, type ComponentType, type ReactNode } from 'react'
import {
  ArrowDownUp, Bookmark, Building2, Footprints, List, Map as MapIcon, MapPin, Plus,
  ReceiptText, RotateCcw, Search, SlidersHorizontal, Star, Users, Utensils,
} from 'lucide-react'
import type {
  TasteMapImageDescriptor, TasteMapMapBrowseOptions, TasteMapMapBrowseRequest,
  TasteMapMapFilters, TasteMapMapScope, TasteMapMapScopeCounts, TasteMapMapSort, TasteMapPlatform,
  TasteMapProfileDashboardViewModel, TasteMapNativeMapViewport,
} from '../platform/TasteMapPlatform'
import { projectBridgeRestaurant } from '../platform/TasteMapBridgeProjection'
import { HYBRID_MAP_PRIMARY_SCOPES } from '../hybrid/app/HybridProductContracts'
import type { Coordinates, RestaurantSummary, UserProfile } from '../types/domain'
import { initialMapBrowseState, mapBrowseReducer } from './mapBrowseState'
import {
  MapBrowseSnapshotCache,
  LatestMapRequestGate,
  mapBrowseCameraFitKey,
  mapBrowseDataVersion,
  mapBrowseSnapshotKey,
  type MapBrowsePresentationSnapshot,
} from './mapBrowseSnapshot'
import {
  beginMapScopeMeasurement,
  markMapScopeContentCommitted,
  markMapScopeDataReady,
  markMapScopeSelected,
  markMapScopeStaleResponse,
} from './mapScopePerformance'
import { TasteMapPrimaryTabBar, type TasteMapPrimaryTab } from './TasteMapDiscoveryShared'
import { HybridRestaurantImage } from './TasteMapHybridShared'
import { TasteMapVisitedIcon } from './TasteMapStatusIcons'
import './myMapBrowsePage.css'

export interface MyMapSurfaceProps {
  active: boolean
  platform: TasteMapPlatform
  restaurants: RestaurantSummary[]
  images: Record<string, TasteMapImageDescriptor>
  selectedRestaurantID: string | null
  selectedRestaurant?: RestaurantSummary
  scope: TasteMapMapScope
  filters: TasteMapMapFilters
  sort: TasteMapMapSort
  search: string
  cameraFitKey: string
  currentUser: UserProfile
  currentCoordinates: Coordinates | null
  initialViewport: TasteMapNativeMapViewport | null
  overlayRevision: string
  onClearSelection: () => void
  onSelect: (restaurant: RestaurantSummary) => void
  onViewportChange: (viewport: TasteMapNativeMapViewport) => void
  onError: (message: string | null) => void
}

interface MyMapBrowsePageProps {
  platform: TasteMapPlatform
  profile: TasteMapProfileDashboardViewModel
  active: boolean
  onOpenRestaurant: (restaurantID: string) => void
  onAddRestaurant: () => void
  MapSurface: ComponentType<MyMapSurfaceProps>
}

const emptyOptions: TasteMapMapBrowseOptions = { cities: [], companions: [], cuisines: [], recommendationSources: [] }
const snapshotFreshnessMilliseconds = 30_000

export function MyMapBrowsePage({ platform, profile, active, onOpenRestaurant, onAddRestaurant, MapSurface }: MyMapBrowsePageProps) {
  const [browseState, dispatch] = useReducer(mapBrowseReducer, initialMapBrowseState)
  const { mode, scope, filters, sort, search, viewport, selectedRestaurantID, revision } = browseState
  const [coordinates, setCoordinates] = useState<Coordinates | null>(null)
  const [locationMessage, setLocationMessage] = useState<string | null>(null)
  const [items, setItems] = useState<RestaurantSummary[]>([])
  const [images, setImages] = useState<Record<string, TasteMapImageDescriptor>>({})
  const [options, setOptions] = useState<TasteMapMapBrowseOptions>(emptyOptions)
  const profileScopeCounts = useMemo<TasteMapMapScopeCounts>(() => ({
    visited: profile.restaurants.filter((restaurant) => restaurant.status === 'visited').length,
    wantToGo: profile.restaurants.filter((restaurant) => restaurant.status === 'wantToGo').length,
    recommended: 0,
  }), [profile.restaurants])
  const [scopeCounts, setScopeCounts] = useState<TasteMapMapScopeCounts>(profileScopeCounts)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [nativeMapError, setNativeMapError] = useState<string | null>(null)
  const [fullFilterOpen, setFullFilterOpen] = useState(false)
  const requestGate = useRef(new LatestMapRequestGate())
  const rootRef = useRef<HTMLElement>(null)
  const snapshotCache = useRef(new MapBrowseSnapshotCache())
  const activeMeasurement = useRef<{ id: string | null; scope: TasteMapMapScope } | null>(null)
  const dataVersion = useMemo(() => mapBrowseDataVersion(profile.restaurants), [profile.restaurants])
  const cameraFitKey = mapBrowseCameraFitKey(filters, search)
  const snapshotKeyFor = useCallback((nextScope: TasteMapMapScope) => mapBrowseSnapshotKey({
    ownerUserID: profile.user.id,
    dataVersion,
    mode,
    scope: nextScope,
    filters,
    sort,
    search,
    viewport,
    currentLocation: coordinates,
  }), [coordinates, dataVersion, filters, mode, profile.user.id, search, sort, viewport])

  const applySnapshot = useCallback((snapshot: MapBrowsePresentationSnapshot, urgent = false) => {
    const update = () => {
      setItems(snapshot.items)
      setImages(snapshot.images)
      setOptions(snapshot.options)
      setScopeCounts(snapshot.scopeCounts)
      setLoading(false)
      setError(null)
    }
    if (urgent) update()
    else startTransition(update)
  }, [])

  const selectScope = (nextScope: TasteMapMapScope) => {
    if (nextScope === scope) return
    const measurementID = beginMapScopeMeasurement(platform.kind, scope, nextScope)
    activeMeasurement.current = { id: measurementID, scope: nextScope }
    // Invalidate any older request before React runs the next effect. A slow
    // Native response can therefore never flash the previous scope back in.
    requestGate.current.invalidate('scope-invalidated')
    const cached = snapshotCache.current.get(snapshotKeyFor(nextScope))
    dispatch({ type: 'scope', value: nextScope })
    if (cached) {
      applySnapshot(cached, true)
      markMapScopeDataReady(measurementID, { itemCount: cached.items.length, cacheHit: true, bridgeDurationMs: 0 })
    } else {
      setItems([])
      setImages({})
      setLoading(true)
    }
    void platform.haptics.selection()
  }

  useEffect(() => {
    const measurement = activeMeasurement.current
    if (!measurement || measurement.scope !== scope) return
    requestAnimationFrame(() => markMapScopeSelected(measurement.id))
  }, [scope])

  useEffect(() => {
    const measurement = activeMeasurement.current
    if (!measurement || measurement.scope !== scope) return
    markMapScopeContentCommitted(measurement.id, rootRef.current)
  }, [images, items, scope])

  useEffect(() => {
    snapshotCache.current.clear()
    setScopeCounts(profileScopeCounts)
  }, [dataVersion, profile.user.id, profileScopeCounts])

  useEffect(() => {
    if (!active || !platform.runtime) return
    let alive = true
    platform.runtime.info().then((runtime) => {
      if (!runtime.supportedCapabilities.location) return
      return platform.location.current()
    }).then((location) => {
      if (!alive || !location) return
      setCoordinates({ latitude: location.latitude, longitude: location.longitude })
      setLocationMessage(location.accuracyMode === 'reduced' ? '当前为大致位置，地图不会冒充精确定位。' : null)
    }).catch((reason: unknown) => {
      if (!alive) return
      const code = typeof reason === 'object' && reason && 'code' in reason ? String(reason.code) : ''
      setLocationMessage(code === 'location_permission_denied'
        ? '定位权限未开启；餐厅数据仍可浏览，距离排序暂不可用。'
        : '暂时无法取得新鲜位置；未使用城市中心或地图中心代替。')
    })
    return () => { alive = false }
  }, [active, platform])

  useEffect(() => {
    if (!active) return
    const snapshotKey = snapshotKeyFor(scope)
    const cached = snapshotCache.current.get(snapshotKey)
    if (cached) {
      applySnapshot(cached)
      const measurement = activeMeasurement.current?.scope === scope ? activeMeasurement.current.id : null
      markMapScopeDataReady(measurement, { itemCount: cached.items.length, cacheHit: true, bridgeDurationMs: 0 })
      if (Date.now() - cached.capturedAt < snapshotFreshnessMilliseconds) {
        requestGate.current.invalidate('cache-served')
        return
      }
    }
    const requestID = globalThis.crypto?.randomUUID?.() ?? `map-${Date.now()}-${Math.random()}`
    requestGate.current.activate(requestID)
    const request: TasteMapMapBrowseRequest = {
      requestID, scope, filters, sort, search, limit: 300,
      bounds: mode === 'map' ? viewport?.bounds : undefined,
      currentLocation: coordinates ?? undefined,
    }
    const measurement = activeMeasurement.current?.scope === scope ? activeMeasurement.current.id : null
    const bridgeStartedAt = performance.now()
    if (!cached) setLoading(true)
    setError(null)
    platform.map.viewport(request).then((response) => {
        if (!requestGate.current.accepts(requestID, response.requestID)) {
          markMapScopeStaleResponse(measurement)
          return
        }
        const projected = response.items.map((restaurant) => projectBridgeRestaurant({
          restaurant,
          viewerState: restaurant.status === 'visited' ? 'visited' : 'want_to_go',
          editableVisitIDs: [],
          capabilities: {
            canEditRestaurant: false,
            canDeleteRestaurant: false,
            canRecordVisit: true,
            canAddToWantToGo: true,
            canAddToList: true,
            canAddToRoulette: true,
            canShare: true,
          },
        }))
        const snapshot: MapBrowsePresentationSnapshot = {
          scope,
          items: projected.map((value) => value.restaurant),
          images: Object.fromEntries(projected.map((value) => [value.restaurant.id, value.image])),
          options: response.options,
          scopeCounts: response.scopeCounts,
          capturedAt: Date.now(),
        }
        snapshotCache.current.set(snapshotKey, snapshot)
        markMapScopeDataReady(measurement, {
          itemCount: snapshot.items.length,
          cacheHit: false,
          bridgeDurationMs: performance.now() - bridgeStartedAt,
        })
        applySnapshot(snapshot)
      }).catch((reason: unknown) => {
        if (!requestGate.current.accepts(requestID)) return
        setError(reason instanceof Error ? reason.message : '无法读取地图餐厅。')
        setLoading(false)
      })
  }, [active, applySnapshot, coordinates, filters, mode, platform, revision, scope, search, snapshotKeyFor, sort, viewport])

  const openRestaurant = useCallback((restaurant: RestaurantSummary) => {
    dispatch({ type: 'selection', value: restaurant.id })
    void platform.haptics.selection()
    onOpenRestaurant(restaurant.id)
  }, [onOpenRestaurant, platform])

  useEffect(() => {
    let remove: (() => Promise<void>) | undefined
    void platform.events.subscribe((event) => {
      if (event.name === 'location.changed') {
        snapshotCache.current.clear()
        setCoordinates({ latitude: event.payload.latitude, longitude: event.payload.longitude })
      } else if (event.name === 'map.viewport.changed') {
        dispatch({ type: 'viewport', value: event.payload })
      } else if (event.name === 'map.restaurant.selected') {
        if (!event.payload.restaurantID) dispatch({ type: 'selection', value: null })
        else {
          const restaurant = items.find((item) => item.id === event.payload.restaurantID)
          if (restaurant) openRestaurant(restaurant)
        }
      } else if (event.name === 'auth.changed' || (event.name === 'app.lifecycle' && ['foreground', 'resume'].includes(event.payload.state))) {
        snapshotCache.current.clear()
        dispatch({ type: 'retry' })
      }
    }).then((subscription) => { remove = () => subscription.remove() }).catch(() => undefined)
    return () => { void remove?.() }
  }, [items, openRestaurant, platform])

  const mapScopeTabs = useMemo<ReadonlyArray<TasteMapPrimaryTab<TasteMapMapScope>>>(() => HYBRID_MAP_PRIMARY_SCOPES.map(([value, label]) => ({
    value,
    label,
    count: scopeCounts[value],
    icon: value === 'visited'
      ? <TasteMapVisitedIcon />
      : value === 'wantToGo'
        ? <Bookmark />
        : <Star />,
  })), [scopeCounts])
  const activeFilterCount = Object.values(filters).filter((value) => value !== undefined && value !== '').length

  return <main
    aria-hidden={!active}
    className={`tm-my-map ${active ? 'is-active' : 'is-inactive'} is-${mode}`}
    data-map-scope={scope}
    data-scope-item-count={items.length}
    ref={rootRef}
  >
    <header className="tm-my-map__controls">
      <button
        aria-label={mode === 'map' ? '切换到我的列表' : '切换到我的地图'}
        className="tm-my-map__title-switch"
        onClick={() => { void platform.haptics.selection(); dispatch({ type: 'toggleMode' }) }}
        type="button"
      >
        <span>{mode === 'map' ? '我的地图' : '我的列表'}</span>
        {mode === 'map' ? <MapIcon aria-hidden="true" size={19} /> : <List aria-hidden="true" size={19} />}
      </button>
      <TasteMapPrimaryTabBar ariaLabel="地图范围" className="tm-my-map__scopes" items={mapScopeTabs} onChange={selectScope} value={scope} />
      <MapFilterBar
        activeCount={activeFilterCount}
        filters={filters}
        onChange={(value) => dispatch({ type: 'filters', value })}
        onOpenAll={() => setFullFilterOpen(true)}
        options={options}
        search={search}
        setSearch={(value) => dispatch({ type: 'search', value })}
        setSort={(value) => dispatch({ type: 'sort', value })}
        sort={sort}
      />
    </header>

    <section className="tm-my-map__stage">
      <div className="tm-my-map__map-layer">
        <MapSurface
          active={active && mode === 'map'}
          cameraFitKey={cameraFitKey}
          currentCoordinates={coordinates}
          currentUser={profile.user}
          filters={filters}
          images={images}
          initialViewport={viewport}
          onClearSelection={() => dispatch({ type: 'selection', value: null })}
          onError={setNativeMapError}
          onSelect={openRestaurant}
          onViewportChange={(value) => dispatch({ type: 'viewport', value })}
          overlayRevision={`${selectedRestaurantID ?? ''}|${error ?? ''}|${locationMessage ?? ''}`}
          platform={platform}
          restaurants={items}
          scope={scope}
          search={search}
          selectedRestaurantID={selectedRestaurantID}
          sort={sort}
        />
      </div>
      <div className="tm-my-map__list-layer">
        <MyRestaurantList
          images={images}
          items={items}
          loading={loading}
          onOpen={openRestaurant}
          scope={scope}
        />
      </div>
      {error ? <MapState title="餐厅数据暂时不可用" message={error} action={() => dispatch({ type: 'retry' })} /> : null}
      {!error && nativeMapError ? <MapState title="原生地图暂时不可用" message={nativeMapError} action={() => dispatch({ type: 'retry' })} /> : null}
      {locationMessage ? <p className="tm-my-map__location-note" role="status">{locationMessage}</p> : null}
      <button aria-label="添加餐厅" className="tm-my-map__add" data-product-contract="add-restaurant-primary-entry" onClick={onAddRestaurant} type="button"><Plus aria-hidden="true" size={17} />添加餐厅</button>
    </section>

    {fullFilterOpen ? <FullFilterSheet filters={filters} onChange={(value) => dispatch({ type: 'filters', value })} onClose={() => setFullFilterOpen(false)} options={options} /> : null}
  </main>
}

function MapFilterBar({ activeCount, filters, onChange, onOpenAll, options, search, setSearch, sort, setSort }: {
  activeCount: number
  filters: TasteMapMapFilters
  onChange: (value: TasteMapMapFilters) => void
  onOpenAll: () => void
  options: TasteMapMapBrowseOptions
  search: string
  setSearch: (value: string) => void
  sort: TasteMapMapSort
  setSort: (value: TasteMapMapSort) => void
}) {
  return <div className="tm-map-filter-bar" aria-label="地图筛选">
    <button className={activeCount ? 'is-active' : ''} onClick={onOpenAll} type="button"><SlidersHorizontal size={14} />筛选{activeCount ? <b>{activeCount}</b> : null}</button>
    <FilterSelect icon={<Building2 size={14} />} label="城市" value={filters.city ?? ''} options={options.cities} onChange={(value) => onChange({ ...filters, city: value || undefined })} />
    <FilterSelect icon={<Star size={14} />} label="评分" value={String(filters.minimumScoreOutOfTen ?? '')} options={['6', '7', '8', '9']} optionLabel={(value) => `${value}+ 分`} onChange={(value) => onChange({ ...filters, minimumScoreOutOfTen: value ? Number(value) : undefined })} />
    <FilterSelect icon={<ReceiptText size={14} />} label="消费" value={String(filters.maximumSpend ?? '')} options={['100', '200', '300', '500']} optionLabel={(value) => `¥${value} 内`} onChange={(value) => onChange({ ...filters, maximumSpend: value ? Number(value) : undefined })} />
    <FilterSelect icon={<Footprints size={14} />} label="到访次数" value={String(filters.minimumVisitCount ?? '')} options={['1', '2', '3', '5', '10']} optionLabel={(value) => `${value}+ 次`} onChange={(value) => onChange({ ...filters, minimumVisitCount: value ? Number(value) : undefined })} />
    <FilterSelect icon={<Users size={14} />} label="饭搭子" value={filters.companion ?? ''} options={options.companions} onChange={(value) => onChange({ ...filters, companion: value || undefined })} />
    <FilterSelect icon={<Utensils size={14} />} label="菜系" value={filters.cuisine ?? ''} options={options.cuisines} onChange={(value) => onChange({ ...filters, cuisine: value || undefined })} />
    <label className="tm-map-filter-search"><Search size={14} /><input aria-label="搜索餐厅" onChange={(event) => setSearch(event.target.value)} placeholder="搜索" value={search} /></label>
    <FilterSelect icon={<ArrowDownUp size={14} />} label="排序" value={sort} options={['recent', 'rating', 'visits', 'distance']} optionLabel={(value) => ({ recent: '最近', rating: '评分', visits: '次数', distance: '距离' })[value] ?? value} onChange={(value) => setSort(value as TasteMapMapSort)} />
  </div>
}

function FilterSelect({ icon, label, value, options, optionLabel = (value) => value, onChange }: {
  icon: ReactNode; label: string; value: string; options: string[]; optionLabel?: (value: string) => string; onChange: (value: string) => void
}) {
  return <label className={value ? 'is-active' : ''}>{icon}<select aria-label={label} onChange={(event) => onChange(event.target.value)} value={value}><option value="">{label}</option>{options.map((option) => <option key={option} value={option}>{optionLabel(option)}</option>)}</select></label>
}

function MyRestaurantList({ items, images, loading, scope, onOpen }: { items: RestaurantSummary[]; images: Record<string, TasteMapImageDescriptor>; loading: boolean; scope: TasteMapMapScope; onOpen: (item: RestaurantSummary) => void }) {
  if (loading && !items.length) return <div className="tm-map-list-state" role="status"><span className="tm-map-list-state__loader" />正在读取本地餐厅…</div>
  if (!items.length) return <div className="tm-map-list-state"><Utensils size={28} /><strong>{scope === 'recommended' ? '暂无推荐结果' : '当前没有符合条件的餐厅'}</strong><p>{scope === 'recommended' ? '推荐使用真实发现数据；更多推荐可在发现页查看。' : '可以调整筛选或切换范围。'}</p></div>
  return <div className="tm-my-restaurant-list">{items.map((item) => <button key={item.id} onClick={() => onOpen(item)} type="button">
    <RestaurantImage descriptor={images[item.id]} restaurantName={item.name} />
    <span><strong>{item.name}</strong><small>{item.scoreOutOfTen == null ? '尚未评分' : `${item.scoreOutOfTen.toFixed(1)} 分`} · {item.status === 'visited' ? `${item.visitCount} 次到访` : '想吃'}</small><em><MapPin size={11} />{[item.city, item.address].filter(Boolean).join(' · ')}</em></span>
  </button>)}</div>
}

function RestaurantImage({ descriptor, restaurantName }: { descriptor?: TasteMapImageDescriptor; restaurantName: string }) {
  return <span className="tm-restaurant-image"><HybridRestaurantImage image={descriptor} name={restaurantName} /></span>
}

function FullFilterSheet({ filters, onChange, onClose, options }: { filters: TasteMapMapFilters; onChange: (value: TasteMapMapFilters) => void; onClose: () => void; options: TasteMapMapBrowseOptions }) {
  return <div className="tm-map-filter-sheet" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose() }}><section aria-label="全部筛选" role="dialog">
    <header><strong>筛选餐厅</strong><button onClick={() => onChange({})} type="button">重置</button></header>
    <div className="tm-map-filter-sheet__grid">
      <FilterSelect icon={<Building2 size={14} />} label="城市" value={filters.city ?? ''} options={options.cities} onChange={(value) => onChange({ ...filters, city: value || undefined })} />
      <FilterSelect icon={<Users size={14} />} label="饭搭子" value={filters.companion ?? ''} options={options.companions} onChange={(value) => onChange({ ...filters, companion: value || undefined })} />
      <FilterSelect icon={<Utensils size={14} />} label="菜系" value={filters.cuisine ?? ''} options={options.cuisines} onChange={(value) => onChange({ ...filters, cuisine: value || undefined })} />
      <FilterSelect icon={<ReceiptText size={14} />} label="推荐来源" value={filters.recommendationSource ?? ''} options={options.recommendationSources} onChange={(value) => onChange({ ...filters, recommendationSource: value || undefined })} />
    </div>
    <button className="tm-map-filter-sheet__done" onClick={onClose} type="button">查看结果</button>
  </section></div>
}

function MapState({ title, message, action }: { title: string; message: string; action: () => void }) {
  return <div className="tm-map-error"><strong>{title}</strong><p>{message}</p><button onClick={action} type="button"><RotateCcw size={14} />重试</button></div>
}
