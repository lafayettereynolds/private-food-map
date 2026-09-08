import { startTransition, useCallback, useEffect, useMemo, useReducer, useRef, useState, type ComponentType, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { useRecommendationPreferences } from './RecommendationNotInterested'
import { usePremiumAccess, useResolvedPremiumAccess } from './PremiumAccess'
import { openPremiumPaywall } from '../services/premiumPaywall'
import { LockKeyhole } from 'lucide-react'
import { applyRecommendationIntent, recommendationIsDismissed } from '../services/recommendationIntent'
import {
  ArrowDownUp, Bookmark, Building2, CalendarDays, ChevronRight, Footprints, List, Map as MapIcon, MapPin, Plus,
  ReceiptText, RotateCcw, Search, SlidersHorizontal, Star, Users, Utensils, WalletCards, X,
} from 'lucide-react'
import type {
  TasteMapImageDescriptor, TasteMapMapBrowseOptions, TasteMapMapBrowseRequest,
  TasteMapMapFilters, TasteMapMapScope, TasteMapMapScopeCounts, TasteMapMapSort, TasteMapPlatform,
  TasteMapProfileDashboardViewModel, TasteMapNativeMapViewport, TasteMapHybridDiscoveryItemDTO,
  TasteMapNativeTasteDataProgressDTO,
} from '../platform/TasteMapPlatform'
import { projectBridgeRestaurant } from '../platform/TasteMapBridgeProjection'
import { HYBRID_MAP_PRIMARY_SCOPES } from '../hybrid/app/HybridProductContracts'
import {
  DINING_MODE_OPTIONS, DINING_OCCASION_OPTIONS, QUEUE_DURATION_OPTIONS,
  RECOMMENDATION_SOURCE_OPTIONS, SCORE_BAND_META, SCORE_BAND_ORDER, scoreColor,
} from '../types/domain'
import type { Coordinates, RestaurantSummary, UserProfile } from '../types/domain'
import { initialMapBrowseState, mapBrowseReducer, mapScopeQuery } from './mapBrowseState'
import { MapLocationDeliveryGate } from './mapLocationLifecycle'
import {
  MapBrowseSnapshotCache,
  LatestMapRequestGate,
  LatestMapViewportCommitScheduler,
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
import { TasteMapFilterSelect, TasteMapPrimaryTabBar, type TasteMapPrimaryTab } from './TasteMapDiscoveryShared'
import { HybridRestaurantImage } from './TasteMapHybridShared'
import { TasteMapVisitedIcon } from './TasteMapStatusIcons'
import { tasteDataProgress, type TasteDataProgress } from './tasteDataProgress'
import { compareMarkerLayerPriority } from './mapMarkerPriority'
import {
  canonicalForYouRecommendations,
  filterForYouMapRecommendations,
  forYouRecommendationDataVersion,
  projectForYouRecommendationsToMap,
  recommendationMapOptions,
} from './mapRecommendationSnapshot'
import './myMapBrowsePage.css'
import { minimumRatingFilterLabel, RATING_FILTER_THRESHOLDS } from '../utils/ratingFilterOptions'

export interface MyMapSurfaceProps {
  active: boolean
  interactionBlocked: boolean
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
  tasteDataProgress: TasteMapNativeTasteDataProgressDTO | null
  overlayRevision: string
  onClearSelection: () => void
  onSelect: (restaurant: RestaurantSummary) => void
  onSelectGroup: (restaurantIDs: string[]) => void
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
  controlOverlayRevision?: string
  forYouRecommendations?: readonly TasteMapHybridDiscoveryItemDTO[]
  recommendationSnapshotGeneratedAt?: string
}

const emptyOptions: TasteMapMapBrowseOptions = { cities: [], companions: [], cuisines: [], recommendationSources: [] }
const snapshotFreshnessMilliseconds = 30_000
const tasteDataCompletionDisplayMilliseconds = 6_000

export function MyMapBrowsePage({
  platform, profile, active, onOpenRestaurant, onAddRestaurant, MapSurface, controlOverlayRevision = '',
  forYouRecommendations, recommendationSnapshotGeneratedAt = new Date(0).toISOString(),
}: MyMapBrowsePageProps) {
  const recommendationPreferences = useRecommendationPreferences(platform)
  const resolvedPremium = useResolvedPremiumAccess()
  const [browseState, dispatch] = useReducer(mapBrowseReducer, initialMapBrowseState)
  const { mode, scope, filters, sort, search, viewport, selectedRestaurantID, revision, cameraFitRevision } = browseState
  useEffect(() => {
    if (resolvedPremium === false && (filters.companion || filters.recommendationSource || filters.recommendationSourceType)) {
      dispatch({ type: 'filters', value: { ...filters, companion: undefined, recommendationSource: undefined, recommendationSourceType: undefined } })
    }
  }, [resolvedPremium, filters])
  const [cameraFitKey, setCameraFitKey] = useState('0')
  const [coordinates, setCoordinates] = useState<Coordinates | null>(null)
  const locationDeliveryGate = useRef(new MapLocationDeliveryGate())
  const locationContext = useRef({ active, owner: profile.user.id, foreground: true })
  locationContext.current.active = active
  locationContext.current.owner = profile.user.id
  const [locationMessage, setLocationMessage] = useState<string | null>(null)
  const [items, setItems] = useState<RestaurantSummary[]>([])
  const [images, setImages] = useState<Record<string, TasteMapImageDescriptor>>({})
  const [options, setOptions] = useState<TasteMapMapBrowseOptions>(emptyOptions)
  const canonicalRecommendations = useMemo(
    () => forYouRecommendations ? recommendationPreferences.ready ? applyRecommendationIntent(canonicalForYouRecommendations(forYouRecommendations), recommendationPreferences) : [] : null,
    [forYouRecommendations, recommendationPreferences.excludedIDs, recommendationPreferences.intentFeedback, recommendationPreferences.ready],
  )
  // Apply exclusions synchronously to the displayed snapshot too: an old map
  // request/cache or a late pan must never briefly resurrect a dismissed place.
  const visibleItems = useMemo(() => scope !== 'recommended' ? items : !recommendationPreferences.ready ? []
    : items.filter(item => !recommendationIsDismissed(item, recommendationPreferences)),
  [items, scope, recommendationPreferences.ready, recommendationPreferences.excludedIDs, recommendationPreferences.intentFeedback])
  const profileScopeCounts = useMemo<TasteMapMapScopeCounts>(() => ({
    visited: profile.restaurants.filter((restaurant) => !restaurant.deletedAt && restaurant.status === 'visited' && restaurant.visitCount > 0).length,
    wantToGo: profile.restaurants.filter((restaurant) => restaurant.status === 'wantToGo').length,
    recommended: canonicalRecommendations?.length ?? 0,
  }), [canonicalRecommendations, profile.restaurants])
  const [scopeCounts, setScopeCounts] = useState<TasteMapMapScopeCounts>(profileScopeCounts)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [nativeMapError, setNativeMapError] = useState<string | null>(null)
  const [fullFilterOpen, setFullFilterOpen] = useState(false)
  const [companionOnly, setCompanionOnly] = useState(false)
  const [selectedMapGroupIDs, setSelectedMapGroupIDs] = useState<string[]>([])
  const selectedMapGroup = useMemo(() => resolveMapGroupRestaurants(visibleItems, selectedMapGroupIDs), [visibleItems, selectedMapGroupIDs])
  const progress = useMemo(() => tasteDataProgress(profile.restaurants), [profile.restaurants])
  const showsTasteDataProgress = useTasteDataProgressVisibility(
    progress,
    profile.user.id,
    active && mode === 'map',
  )
  const requestGate = useRef(new LatestMapRequestGate())
  const viewportCommitScheduler = useRef(new LatestMapViewportCommitScheduler())
  const rootRef = useRef<HTMLElement>(null)
  const snapshotCache = useRef(new MapBrowseSnapshotCache())
  const activeMeasurement = useRef<{ id: string | null; scope: TasteMapMapScope } | null>(null)
  const dataVersion = useMemo(() => {
    const profileVersion = mapBrowseDataVersion(profile.restaurants)
    if (!canonicalRecommendations) return profileVersion
    return `${profileVersion}:for-you:${forYouRecommendationDataVersion(recommendationSnapshotGeneratedAt, canonicalRecommendations)}`
  }, [canonicalRecommendations, profile.restaurants, recommendationSnapshotGeneratedAt])
  const snapshotKeyFor = useCallback((nextScope: TasteMapMapScope) => mapBrowseSnapshotKey({
    ownerUserID: profile.user.id,
    dataVersion,
    mode,
    scope: nextScope,
    filters,
    sort,
    search,
    currentLocation: coordinates,
  }), [coordinates, dataVersion, filters, mode, profile.user.id, search, sort])

  const applySnapshot = useCallback((snapshot: MapBrowsePresentationSnapshot, fitRevision: number, urgent = false) => {
    const update = () => {
      setItems(snapshot.items)
      setImages(snapshot.images)
      setOptions(snapshot.options)
      setScopeCounts(snapshot.scopeCounts)
      // Commit a user-requested fit with its actual result, not the previous
      // scope's markers while the async query is still in flight.
      setCameraFitKey(String(fitRevision))
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
    const nextQuery = mapScopeQuery(browseState, nextScope)
    const cached = snapshotCache.current.get(mapBrowseSnapshotKey({
      ownerUserID: profile.user.id, dataVersion, mode, scope: nextScope,
      ...nextQuery, currentLocation: coordinates,
    }))
    const appliedCameraFitRevision = Number(cameraFitKey)
    dispatch({ type: 'scope', value: nextScope, appliedCameraFitRevision })
    setSelectedMapGroupIDs([])
    if (cached) {
      applySnapshot(cached, appliedCameraFitRevision, true)
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

  const refreshMapLocation = useCallback(() => {
    const context = locationContext.current
    if (!context.active || !context.foreground || !platform.runtime) return
    const owner = context.owner
    const sequence = locationDeliveryGate.current.begin()
    const isCurrent = () => locationDeliveryGate.current.isCurrent(sequence)
      && locationContext.current.active && locationContext.current.foreground && locationContext.current.owner === owner
    // An expired origin must not keep influencing distance filters while the
    // fresh request is pending. This never changes cameraFitRevision/viewport.
    setCoordinates(null)
    platform.runtime.info().then((runtime) => {
      if (!isCurrent() || !runtime.supportedCapabilities.location) return
      return platform.location.current()
    }).then((location) => {
      if (!isCurrent() || !location) return
      if (!locationDeliveryGate.current.accept(location, sequence)) {
        setCoordinates(null)
        setLocationMessage('暂时无法取得足够新鲜且准确的位置。')
        return
      }
      setCoordinates((current) => current?.latitude === location.latitude && current.longitude === location.longitude
        ? current : { latitude: location.latitude, longitude: location.longitude })
      setLocationMessage(location.accuracyMode === 'reduced' ? '当前为大致位置，地图不会冒充精确定位。' : null)
    }).catch(() => {
      if (!isCurrent()) return
      // Missing or denied GPS is a quiet capability state on the Map surface.
      // The map remains browsable and location-dependent actions can explain
      // the requirement when the user explicitly invokes them.
      setLocationMessage(null)
    })
  }, [platform])

  useEffect(() => {
    refreshMapLocation()
    return () => { locationDeliveryGate.current.invalidate() }
  }, [active, profile.user.id, refreshMapLocation])

  useEffect(() => {
    if (!active) return
    const snapshotKey = snapshotKeyFor(scope)
    const cached = snapshotCache.current.get(snapshotKey)
    if (cached) {
      applySnapshot(cached, cameraFitRevision)
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
      currentLocation: coordinates ?? undefined,
    }
    // Hybrid Map must not independently regenerate “推荐”. It reads the
    // ordinary viewport metadata, then renders the exact For You snapshot
    // already supplied to Discovery.
    const platformRequest = canonicalRecommendations && scope === 'recommended'
      ? { ...request, scope: 'visited' as const }
      : request
    const measurement = activeMeasurement.current?.scope === scope ? activeMeasurement.current.id : null
    const bridgeStartedAt = performance.now()
    if (!cached) setLoading(true)
    setError(null)
    platform.map.viewport(platformRequest).then((response) => {
        if (!requestGate.current.accepts(requestID, response.requestID)) {
          markMapScopeStaleResponse(measurement)
          return
        }
        const projected = canonicalRecommendations && scope === 'recommended'
          ? filterForYouMapRecommendations(
              projectForYouRecommendationsToMap(canonicalRecommendations, profile.user.id, recommendationSnapshotGeneratedAt),
              request,
            ).map(({ restaurant, image }) => ({ restaurant, image }))
          : response.items.map((restaurant) => projectBridgeRestaurant({
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
          options: canonicalRecommendations && scope === 'recommended'
            ? recommendationMapOptions(response.options, canonicalRecommendations)
            : response.options,
          scopeCounts: canonicalRecommendations
            ? { ...response.scopeCounts, recommended: canonicalRecommendations.length }
            : response.scopeCounts,
          capturedAt: Date.now(),
        }
        snapshotCache.current.set(snapshotKey, snapshot)
        markMapScopeDataReady(measurement, {
          itemCount: snapshot.items.length,
          cacheHit: false,
          bridgeDurationMs: performance.now() - bridgeStartedAt,
        })
        applySnapshot(snapshot, cameraFitRevision)
      }).catch((reason: unknown) => {
        if (!requestGate.current.accepts(requestID)) return
        setError(reason instanceof Error ? reason.message : '无法读取地图餐厅。')
        setLoading(false)
      })
  }, [active, applySnapshot, cameraFitRevision, canonicalRecommendations, coordinates, filters, mode, platform, profile.user.id, recommendationSnapshotGeneratedAt, revision, scope, search, snapshotKeyFor, sort])

  const openRestaurant = useCallback((restaurant: RestaurantSummary, requestHaptic = true) => {
    setSelectedMapGroupIDs([])
    if (requestHaptic) void platform.haptics.selection()
    onOpenRestaurant(restaurant.id)
  }, [onOpenRestaurant, platform])

  const commitViewport = useCallback((value: TasteMapNativeMapViewport) => {
    viewportCommitScheduler.current.schedule(value, (settledViewport) => {
      dispatch({ type: 'viewport', value: settledViewport })
    })
  }, [])

  const itemsRef = useRef(items)
  itemsRef.current = visibleItems

  useEffect(() => {
    let remove: (() => Promise<void>) | undefined
    let disposed = false
    void platform.events.subscribe((event) => {
      if (disposed) return
      if (event.name === 'data.changed') {
        snapshotCache.current.clear()
        requestGate.current.invalidate('data-changed')
        setSelectedMapGroupIDs([])
        if (event.payload.reason === 'restaurantDeleted' || event.payload.reason === 'localDataCleared') {
          setItems([])
          setImages({})
          setLoading(true)
        }
        dispatch({ type: 'retry' })
      } else if (event.name === 'location.changed') {
        if (!locationContext.current.active || !locationContext.current.foreground
          || !locationDeliveryGate.current.accept(event.payload)) return
        snapshotCache.current.clear()
        setCoordinates((current) => current?.latitude === event.payload.latitude && current.longitude === event.payload.longitude
          ? current : { latitude: event.payload.latitude, longitude: event.payload.longitude })
        setLocationMessage(event.payload.accuracyMode === 'reduced' ? '当前为大致位置，地图不会冒充精确定位。' : null)
      } else if (event.name === 'map.viewport.changed') {
        commitViewport(event.payload)
      } else if (event.name === 'map.restaurant.selected') {
        if (!event.payload.restaurantID) dispatch({ type: 'selection', value: null })
        else {
          const restaurant = itemsRef.current.find((item) => item.id === event.payload.restaurantID)
          if (restaurant) openRestaurant(restaurant, false)
        }
      } else if (event.name === 'map.restaurant.groupSelected') {
        setSelectedMapGroupIDs(resolveMapGroupRestaurants(itemsRef.current, event.payload.restaurantIDs).map((restaurant) => restaurant.id))
      } else if (event.name === 'app.lifecycle' && event.payload.state === 'background') {
        locationContext.current.foreground = false
        locationDeliveryGate.current.invalidate()
      } else if (event.name === 'auth.changed' || (event.name === 'app.lifecycle' && ['foreground', 'resume'].includes(event.payload.state))) {
        locationDeliveryGate.current.invalidate()
        if (event.name === 'auth.changed') setCoordinates(null)
        else {
          locationContext.current.foreground = true
          refreshMapLocation()
        }
        snapshotCache.current.clear()
        dispatch({ type: 'retry' })
      }
    }).then((subscription) => {
      if (disposed) void subscription.remove()
      else remove = () => subscription.remove()
    }).catch(() => undefined)
    return () => { disposed = true; void remove?.() }
  }, [commitViewport, openRestaurant, platform, refreshMapLocation])

  useEffect(() => () => viewportCommitScheduler.current.cancel(), [])

  const mapScopeTabs = useMemo<ReadonlyArray<TasteMapPrimaryTab<TasteMapMapScope>>>(() => HYBRID_MAP_PRIMARY_SCOPES.map(([value, label]) => ({
    value,
    label,
    count: value === 'recommended' && canonicalRecommendations ? canonicalRecommendations.length : scopeCounts[value],
    icon: value === 'visited'
      ? <TasteMapVisitedIcon />
      : value === 'wantToGo'
        ? <Bookmark />
        : <Star />,
  })), [scopeCounts, canonicalRecommendations])
  const activeFilterCount = activeMapFilterCount(filters)

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
        onOpenAll={() => { setCompanionOnly(false); setFullFilterOpen(true) }}
        onOpenCompanion={() => { setCompanionOnly(true); setFullFilterOpen(true) }}
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
          interactionBlocked={fullFilterOpen || selectedMapGroup.length > 0}
          onClearSelection={() => dispatch({ type: 'selection', value: null })}
          onError={setNativeMapError}
          onSelect={openRestaurant}
          onSelectGroup={setSelectedMapGroupIDs}
          onViewportChange={commitViewport}
          overlayRevision={`${selectedRestaurantID ?? ''}|${error ?? ''}|${locationMessage ?? ''}|filter:${fullFilterOpen}|group:${selectedMapGroupIDs.join(',')}|taste-progress:${showsTasteDataProgress}|controls:${controlOverlayRevision}`}
          platform={platform}
          restaurants={visibleItems}
          scope={scope}
          search={search}
          selectedRestaurantID={selectedRestaurantID}
          sort={sort}
          tasteDataProgress={showsTasteDataProgress ? progress : null}
        />
      </div>
      <div className="tm-my-map__list-layer">
        <MyRestaurantList
          images={images}
          items={visibleItems}
          loading={loading}
          onOpen={openRestaurant}
          scope={scope}
        />
      </div>
      {showsTasteDataProgress && platform.kind !== 'native' ? <TasteDataProgressNotice progress={progress} /> : null}
      {scope === 'recommended' && recommendationPreferences.error ? <MapState title="推荐偏好暂时不可用" message={recommendationPreferences.error} action={() => void recommendationPreferences.retry()} /> : null}
      {error ? <MapState title="餐厅数据暂时不可用" message={error} action={() => dispatch({ type: 'retry' })} /> : null}
      {!error && nativeMapError ? <MapState title="原生地图暂时不可用" message={nativeMapError} action={() => dispatch({ type: 'retry' })} /> : null}
      {locationMessage ? <p className="tm-my-map__location-note" role="status">{locationMessage}</p> : null}
      <button aria-label="添加餐厅" className="tm-my-map__add" data-product-contract="add-restaurant-primary-entry" onClick={onAddRestaurant} type="button"><Plus aria-hidden="true" size={17} />添加餐厅</button>
    </section>

    {fullFilterOpen ? createPortal(
      <FullFilterSheet
        companionOnly={companionOnly}
        filters={filters}
        hasCurrentLocation={coordinates != null}
        onChange={(value) => dispatch({ type: 'filters', value })}
        onClose={() => setFullFilterOpen(false)}
        options={options}
        scope={scope}
      />,
      document.body,
    ) : null}
    {active && selectedMapGroup.length > 0 ? createPortal(
      <MapRestaurantGroupSheet
        images={images}
        items={selectedMapGroup}
        onClose={() => setSelectedMapGroupIDs([])}
        onOpen={openRestaurant}
        scope={scope}
      />,
      document.body,
    ) : null}
  </main>
}

export function resolveMapGroupRestaurants(items: readonly RestaurantSummary[], restaurantIDs: readonly string[]) {
  const byID = new Map(items.map((restaurant) => [restaurant.id.toLowerCase(), restaurant]))
  const seen = new Set<string>()
  return restaurantIDs.slice(0, 300).flatMap((id) => {
    const key = id.trim().toLowerCase()
    if (seen.has(key)) return []
    seen.add(key)
    const restaurant = byID.get(key)
    return restaurant ? [restaurant] : []
  }).sort((left, right) => compareMarkerLayerPriority(right, left))
}

export function MapRestaurantGroupSheet({ items, images, scope, onClose, onOpen }: {
  items: RestaurantSummary[]
  images: Record<string, TasteMapImageDescriptor>
  scope: TasteMapMapScope
  onClose: () => void
  onOpen: (restaurant: RestaurantSummary) => void
}) {
  const dialogRef = useRef<HTMLElement>(null)
  useEffect(() => {
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    dialogRef.current?.querySelector<HTMLButtonElement>('button')?.focus()
    return () => previousFocus?.focus()
  }, [])
  return <div className="tm-map-filter-sheet tm-map-group-sheet" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose() }}>
    <section
      aria-label={`此处的 ${items.length} 家餐厅`}
      aria-modal="true"
      ref={dialogRef}
      role="dialog"
      onKeyDown={(event) => {
        if (event.key === 'Escape') { event.preventDefault(); onClose() }
        if (event.key !== 'Tab') return
        const buttons = Array.from(dialogRef.current?.querySelectorAll<HTMLButtonElement>('button') ?? [])
        const first = buttons[0]
        const last = buttons[buttons.length - 1]
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus() }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus() }
      }}
    >
      <header><strong>此处的餐厅 · {items.length} 家</strong><button aria-label="关闭餐厅列表" onClick={onClose} type="button"><X aria-hidden="true" size={19} /></button></header>
      <MyRestaurantList images={images} items={items} loading={false} onOpen={onOpen} scope={scope} showsContext={false} />
    </section>
  </div>
}

function TasteDataProgressNotice({ progress }: { progress: TasteDataProgress }) {
  return <aside
    aria-label={`口味数据进度，${progress.displayCount} / ${progress.target}，${progress.message}`}
    aria-live="polite"
    className="tm-taste-data-progress"
    role="status"
  >
    <strong>（{progress.displayCount} / {progress.target} · {progress.message}）</strong>
  </aside>
}

function useTasteDataProgressVisibility(progress: TasteDataProgress, userID: string, canPresent: boolean): boolean {
  const storageKey = tasteDataCompletionStorageKey(userID)
  const [showsCompletion, setShowsCompletion] = useState(() => progress.isComplete && !hasSeenTasteDataCompletion(storageKey))

  useEffect(() => {
    if (!progress.isComplete) {
      removeTasteDataCompletion(storageKey)
      setShowsCompletion(false)
      return
    }
    setShowsCompletion(!hasSeenTasteDataCompletion(storageKey))
  }, [progress.isComplete, storageKey])

  useEffect(() => {
    if (!progress.isComplete || !canPresent || !showsCompletion) return
    const timer = window.setTimeout(() => {
      storeTasteDataCompletion(storageKey)
      setShowsCompletion(false)
    }, tasteDataCompletionDisplayMilliseconds)
    return () => window.clearTimeout(timer)
  }, [canPresent, progress.isComplete, showsCompletion, storageKey])

  return canPresent && (!progress.isComplete || showsCompletion)
}

function tasteDataCompletionStorageKey(userID: string): string {
  return `taste-map:taste-data-progress-complete:${encodeURIComponent(userID.trim().toLowerCase() || 'local')}`
}

function hasSeenTasteDataCompletion(key: string): boolean {
  try { return typeof window !== 'undefined' && window.localStorage.getItem(key) === '1' } catch { return false }
}

function storeTasteDataCompletion(key: string) {
  try { window.localStorage.setItem(key, '1') } catch { /* Storage may be unavailable; the in-memory timeout still hides the card. */ }
}

function removeTasteDataCompletion(key: string) {
  try { if (typeof window !== 'undefined') window.localStorage.removeItem(key) } catch { /* Keep the live progress usable without storage. */ }
}

export function MapFilterBar({ activeCount, filters, onChange, onOpenAll, onOpenCompanion, options, search, setSearch, sort, setSort }: {
  onOpenCompanion?: () => void
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
  const premium = usePremiumAccess()
  return <div className="tm-browse-filter-bar tm-map-filter-bar" aria-label="地图筛选">
    <button className={activeCount ? 'is-active' : ''} onClick={onOpenAll} type="button"><SlidersHorizontal size={14} />筛选{activeCount ? <b>{activeCount}</b> : null}</button>
    <FilterSelect icon={<Building2 size={14} />} label="城市" value={filters.city ?? ''} options={options.cities} onChange={(value) => onChange({ ...filters, city: value || undefined })} />
    <FilterSelect icon={<Star size={14} />} label="评分" emptyOptionLabel="不限评分" value={String(filters.minimumScoreOutOfTen ?? '')} options={RATING_FILTER_THRESHOLDS.map(String)} optionLabel={(value) => minimumRatingFilterLabel(Number(value))} onChange={(value) => onChange({ ...filters, minimumScoreOutOfTen: value ? Number(value) : undefined })} />
    <FilterSelect icon={<ReceiptText size={14} />} label="消费" value={String(filters.maximumSpend ?? '')} options={['100', '200', '300', '500']} optionLabel={(value) => `¥${value} 内`} onChange={(value) => onChange({ ...filters, maximumSpend: value ? Number(value) : undefined })} />
    <FilterSelect icon={<Footprints size={14} />} label="到访次数" value={String(filters.minimumVisitCount ?? '')} options={['1', '2', '3', '5', '10']} optionLabel={(value) => `${value}+ 次`} onChange={(value) => onChange({ ...filters, minimumVisitCount: value ? Number(value) : undefined })} />
    <button onClick={() => premium ? (onOpenCompanion ?? onOpenAll)() : openPremiumPaywall('advanced_recommendation_filters')} type="button"><Users size={14} />{filters.companion || '饭搭子'}{!premium ? <LockKeyhole size={12} /> : null}</button>
    <FilterSelect icon={<Utensils size={14} />} label="菜系" value={filters.cuisine ?? ''} options={options.cuisines} onChange={(value) => onChange({ ...filters, cuisine: value || undefined })} />
    <label className="tm-map-filter-search"><Search size={14} /><input aria-label="搜索餐厅" onChange={(event) => setSearch(event.target.value)} placeholder="搜索" value={search} /></label>
    <FilterSelect icon={<ArrowDownUp size={14} />} label="排序" value={sort} options={['recent', 'rating', 'visits', 'distance']} optionLabel={(value) => ({ recent: '最近', rating: '评分', visits: '次数', distance: '距离' })[value] ?? value} onChange={(value) => setSort(value as TasteMapMapSort)} />
  </div>
}

function FilterSelect({ icon, label, emptyOptionLabel = label, value, options, optionLabel = (value) => value, onChange, compact = true }: {
  icon: ReactNode; label: string; emptyOptionLabel?: string; value: string; options: string[]; optionLabel?: (value: string) => string; onChange: (value: string) => void; compact?: boolean
}) {
  if (compact) return <TasteMapFilterSelect icon={icon} label={label} active={Boolean(value)} value={value} onChange={onChange} options={[{ value: '', label: emptyOptionLabel }, ...options.map((option) => ({ value: option, label: optionLabel(option) }))]} />
  return <label className={value ? 'is-active' : ''}>{icon}<select aria-label={label} onChange={(event) => onChange(event.target.value)} value={value}><option value="">{emptyOptionLabel}</option>{options.map((option) => <option key={option} value={option}>{optionLabel(option)}</option>)}</select></label>
}

export function MyRestaurantList({ items, images, loading, scope, onOpen, showsContext = true }: { items: RestaurantSummary[]; images: Record<string, TasteMapImageDescriptor>; loading: boolean; scope: TasteMapMapScope; onOpen: (item: RestaurantSummary) => void; showsContext?: boolean }) {
  if (loading && !items.length) return <div className="tm-map-list-state" role="status"><span className="tm-map-list-state__loader" />正在读取本地餐厅…</div>
  if (!items.length) return <div className="tm-map-list-state"><Utensils size={28} /><strong>{scope === 'recommended' ? '暂无推荐结果' : '当前没有符合条件的餐厅'}</strong><p>{scope === 'recommended' ? '推荐使用真实发现数据；更多推荐可在发现页查看。' : '可以调整筛选或切换范围。'}</p></div>
  const scopeLabel = scope === 'visited' ? '去过的餐厅' : scope === 'wantToGo' ? '想吃的餐厅' : '为你推荐的餐厅'
  return <section aria-label={scopeLabel} className="tm-my-restaurant-list-shell">
    {showsContext ? <header className="tm-my-restaurant-list__context"><span><small>MY TASTE MAP</small><strong>{scopeLabel}</strong></span><b>{items.length} 家</b></header> : null}
    <div className="tm-my-restaurant-list">{items.map((item) => {
      const price = item.averagePricePerPerson ?? item.pricePerPerson
      const latestDate = scope === 'visited' ? formatRestaurantListDate(item.latestVisitDate) : ''
      const note = (scope === 'recommended' ? item.recommendationReason : item.longTermNote || item.latestVisit?.note)?.trim()
      const tags = item.tags.map((tag) => tag.trim()).filter(Boolean).slice(0, 3)
      const statusLabel = scope === 'visited' ? `${item.visitCount} 次到访` : scope === 'wantToGo' ? '已加入想吃' : `推荐第 ${item.recommendationRank ?? '—'} 位`
      const accessibilityLabel = [`查看餐厅 ${item.name}`, item.scoreOutOfTen == null ? '未评分' : `${item.scoreOutOfTen.toFixed(1)} 分`, statusLabel, price == null ? '' : `人均 ${Math.round(price)} 元`, latestDate ? `最近到访 ${latestDate}` : ''].filter(Boolean).join('，')
      return <button aria-label={accessibilityLabel} key={item.id} onClick={() => onOpen(item)} type="button">
        <RestaurantImage descriptor={images[item.id]} restaurantName={item.name} />
        <span className="tm-my-restaurant-list__copy">
          <span className="tm-my-restaurant-list__heading"><strong>{item.name}</strong><ChevronRight aria-hidden="true" size={17} /></span>
          <span className="tm-my-restaurant-list__metrics">
            <span className={item.scoreOutOfTen == null ? 'is-unrated' : 'is-rated'} style={item.scoreOutOfTen == null ? undefined : { '--tm-list-score': scoreColor(item.scoreOutOfTen) } as React.CSSProperties}><Star aria-hidden="true" fill={item.scoreOutOfTen == null ? 'none' : 'currentColor'} size={13} /><b>{item.scoreOutOfTen == null ? '未评分' : item.scoreOutOfTen.toFixed(1)}</b>{item.scoreOutOfTen == null ? null : ' 分'}</span>
            <span><Footprints aria-hidden="true" size={13} />{statusLabel}</span>
            {price == null ? null : <span><WalletCards aria-hidden="true" size={13} />人均 ¥{Math.round(price)}</span>}
          </span>
          <em><MapPin aria-hidden="true" size={12} /><span>{[item.city, item.address].filter(Boolean).join(' · ') || '地址待补充'}</span></em>
          {latestDate || tags.length ? <span className="tm-my-restaurant-list__facts">{latestDate ? <span><CalendarDays aria-hidden="true" size={12} />最近到访 {latestDate}</span> : null}{tags.map((tag) => <i key={tag}>{tag}</i>)}</span> : null}
          {note ? <span className="tm-my-restaurant-list__note">{scope === 'recommended' ? '推荐理由' : '我的印象'} · {note}</span> : null}
        </span>
      </button>
    })}</div>
  </section>
}

function formatRestaurantListDate(value: string | null) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const now = new Date()
  return date.getFullYear() === now.getFullYear()
    ? `${date.getMonth() + 1}月${date.getDate()}日`
    : `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`
}

function RestaurantImage({ descriptor, restaurantName }: { descriptor?: TasteMapImageDescriptor; restaurantName: string }) {
  return <span className="tm-restaurant-image"><HybridRestaurantImage image={descriptor} name={restaurantName} /></span>
}

function FullFilterSheet({ filters, hasCurrentLocation, onChange, onClose, options, scope, companionOnly = false }: {
  companionOnly?: boolean
  filters: TasteMapMapFilters
  hasCurrentLocation: boolean
  onChange: (value: TasteMapMapFilters) => void
  onClose: () => void
  options: TasteMapMapBrowseOptions
  scope: TasteMapMapScope
}) {
  const hasVisitData = scope !== 'wantToGo'
  const scoreBands = filters.scoreBands ?? []
  const diningOccasions = filters.diningOccasions ?? []
  if (companionOnly) return <div className="tm-map-filter-sheet" role="presentation" onMouseDown={event => { if (event.currentTarget === event.target) onClose() }}><section role="dialog" aria-label="饭搭子筛选"><header><strong>饭搭子</strong><button onClick={() => onChange({ ...filters, companion: undefined })} type="button">重置</button></header><FilterChoiceGroup premiumOnly label="饭搭子" value={filters.companion ?? ''} options={options.companions.map(value => [value, value])} onSelect={value => onChange({ ...filters, companion: value || undefined })} /><button className="tm-map-filter-sheet__done" onClick={onClose} type="button">查看结果</button></section></div>
  return <div className="tm-map-filter-sheet" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose() }}><section aria-label="全部筛选" role="dialog">
    <header><strong>筛选餐厅</strong><button disabled={!activeMapFilterCount(filters)} onClick={() => onChange({})} type="button">重置</button></header>
    <div className="tm-map-filter-sheet__groups">
      {hasVisitData ? <FilterChoiceGroup
        label="用餐方式"
        onSelect={(value) => onChange({ ...filters, diningMode: value ? value as TasteMapMapFilters['diningMode'] : undefined })}
        options={DINING_MODE_OPTIONS.map((option) => [option.value, option.label])}
        value={filters.diningMode ?? ''}
      /> : null}
      {hasVisitData ? <FilterChoiceGroup
        label="到访次数"
        onSelect={(value) => onChange({ ...filters, minimumVisitCount: value ? Number(value) : undefined })}
        options={['1', '2', '3', '5', '10'].map((value) => [value, `${value}+`])}
        value={String(filters.minimumVisitCount ?? '')}
      /> : null}
      <FilterMultiChoiceGroup
        label="评分区间 · 可多选"
        onToggle={(value) => {
          const band = Number(value) as 1 | 2 | 3 | 4 | 5
          onChange({ ...filters, scoreBands: scoreBands.includes(band) ? scoreBands.filter((item) => item !== band) : [...scoreBands, band] })
        }}
        onClear={() => onChange({ ...filters, scoreBands: undefined })}
        options={SCORE_BAND_ORDER.map((value) => [String(value), SCORE_BAND_META[value].label, SCORE_BAND_META[value].color])}
        values={scoreBands.map(String)}
      />
      {hasVisitData ? <FilterChoiceGroup
        label="等待时长"
        onSelect={(value) => onChange({ ...filters, queueDuration: value ? value as TasteMapMapFilters['queueDuration'] : undefined })}
        options={[...QUEUE_DURATION_OPTIONS.map((option) => [option.value, option.label]), ['unrecorded', '未记录']]}
        value={filters.queueDuration ?? ''}
      /> : null}
      {hasVisitData ? <FilterMultiChoiceGroup
        label="适合场景 · 可多选"
        onToggle={(value) => onChange({
          ...filters,
          diningOccasions: diningOccasions.includes(value as typeof diningOccasions[number])
            ? diningOccasions.filter((item) => item !== value)
            : [...diningOccasions, value as typeof diningOccasions[number]],
        })}
        onClear={() => onChange({ ...filters, diningOccasions: undefined })}
        options={DINING_OCCASION_OPTIONS.map((option) => [option.value, option.value === 'other' ? '其他' : option.label])}
        values={diningOccasions}
      /> : null}
      {hasVisitData ? <FilterChoiceGroup
        label="推荐来源"
        onSelect={(value) => onChange({ ...filters, recommendationSourceType: value ? value as TasteMapMapFilters['recommendationSourceType'] : undefined })}
        premiumOnly
        options={RECOMMENDATION_SOURCE_OPTIONS.filter(option => option.value !== 'other').map((option) => [option.value, option.label])}
        value={filters.recommendationSourceType ?? ''}
      /> : null}
      {hasVisitData ? <FilterChoiceGroup
        label="人均价格"
        onSelect={(value) => onChange({ ...filters, priceRange: value ? value as TasteMapMapFilters['priceRange'] : undefined })}
        options={[["under100", "¥100 以下"], ["100to200", "¥100–200"], ["over200", "¥200 以上"]]}
        value={filters.priceRange ?? ''}
      /> : null}
      {hasVisitData ? <FilterChoiceGroup
        allLabel="不限"
        label="到访时间"
        onSelect={(value) => onChange({ ...filters, visitPeriod: value ? value as TasteMapMapFilters['visitPeriod'] : undefined })}
        options={[["sixMonths", "最近半年"], ["year", "最近一年"]]}
        value={filters.visitPeriod ?? ''}
      /> : null}
      <FilterChoiceGroup
        allLabel="不限"
        disabled={!hasCurrentLocation}
        hint={hasCurrentLocation ? '以当前设备位置计算' : '取得定位后可以使用距离筛选'}
        label="距离"
        onSelect={(value) => onChange({ ...filters, distanceKilometers: value ? Number(value) as 1 | 3 | 5 | 10 : undefined })}
        options={['1', '3', '5', '10'].map((value) => [value, `${value} km 内`])}
        value={String(filters.distanceKilometers ?? '')}
      />
    </div>
    <div className="tm-map-filter-sheet__grid" aria-label="更多精确条件">
      <FilterSelect compact={false} icon={<Building2 size={14} />} label="城市" value={filters.city ?? ''} options={options.cities} onChange={(value) => onChange({ ...filters, city: value || undefined })} />
      <FilterChoiceGroup premiumOnly label="饭搭子" value={filters.companion ?? ''} options={options.companions.map(value => [value, value])} onSelect={(value) => onChange({ ...filters, companion: value || undefined })} />
      <FilterSelect compact={false} icon={<Utensils size={14} />} label="菜系" value={filters.cuisine ?? ''} options={options.cuisines} onChange={(value) => onChange({ ...filters, cuisine: value || undefined })} />
      {hasVisitData ? <FilterChoiceGroup premiumOnly label="具体推荐人或来源" value={filters.recommendationSource ?? ''} options={options.recommendationSources.map(value => [value, value])} onSelect={(value) => onChange({ ...filters, recommendationSource: value || undefined })} /> : null}
    </div>
    <button className="tm-map-filter-sheet__done" onClick={onClose} type="button">查看结果</button>
  </section></div>
}

export function FilterChoiceGroup({ allLabel = '全部', disabled = false, hint, label, onSelect, options, value, premiumOnly = false }: {
  premiumOnly?: boolean
  allLabel?: string
  disabled?: boolean
  hint?: string
  label: string
  onSelect: (value: string) => void
  options: string[][]
  value: string
}) {
  const premium = usePremiumAccess()
  const locked = premiumOnly && !premium
  const [expanded, setExpanded] = useState(false)
  const visibleOptions = expanded ? options : options.filter(([key], index) => index < 6 || key === value)
  const select = (next: string) => locked ? openPremiumPaywall('advanced_recommendation_filters') : onSelect(next)
  return <fieldset className="tm-map-filter-group" disabled={disabled}>
    <legend>{label}{locked ? <LockKeyhole aria-label="会员专享" size={12} /> : null}</legend>
    <div>
      <button className={!value && !locked ? 'is-active' : ''} onClick={() => select('')} type="button">{allLabel}</button>
      {visibleOptions.map(([optionValue, optionLabel]) => <button aria-pressed={!locked && value === optionValue} className={!locked && value === optionValue ? 'is-active' : ''} key={optionValue} onClick={() => select(value === optionValue ? '' : optionValue)} type="button">{optionLabel}</button>)}
      {options.length > 6 ? <button aria-expanded={expanded} onClick={() => locked ? openPremiumPaywall('advanced_recommendation_filters') : setExpanded(!expanded)} type="button">{expanded ? '收起' : '更多'}</button> : null}
    </div>
    {hint ? <small>{hint}</small> : null}
  </fieldset>
}

function FilterMultiChoiceGroup({ label, onClear, onToggle, options, values }: {
  label: string
  onClear: () => void
  onToggle: (value: string) => void
  options: string[][]
  values: string[]
}) {
  return <fieldset className="tm-map-filter-group">
    <legend>{label}</legend>
    <div>
      <button className={!values.length ? 'is-active' : ''} onClick={onClear} type="button">全部</button>
      {options.map(([value, label, color]) => <button className={values.includes(value) ? 'is-active' : ''} key={value} onClick={() => onToggle(value)} type="button">{color ? <i style={{ background: color }} /> : null}{label}</button>)}
    </div>
  </fieldset>
}

function activeMapFilterCount(filters: TasteMapMapFilters) {
  return Object.values(filters).filter((value) => Array.isArray(value) ? value.length > 0 : value !== undefined && value !== '').length
}

function MapState({ title, message, action }: { title: string; message: string; action: () => void }) {
  return <div className="tm-map-error"><strong>{title}</strong><p>{message}</p><button onClick={action} type="button"><RotateCcw size={14} />重试</button></div>
}
