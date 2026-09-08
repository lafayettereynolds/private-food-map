import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import { KeyRound, LoaderCircle, MapPin } from 'lucide-react'
import type { TasteMapNativeMapViewport } from '../platform/TasteMapPlatform'
import { type AMapInstance, type AMapMarkerInstance, type AMapNamespace } from '../services/amap'
import { mapService } from '../services/mapService'
import { resolvePhotoSource } from '../services/photoAssets'
import { scoreColor, type Coordinates, type RestaurantSummary, type UserProfile } from '../types/domain'
import { avatarPresetPosition } from '../utils/avatarPresets'
import { isUnvisitedMapMarker } from '../utils/mapMarkers'
import { markerCoincidentGroups, markerCoincidentStackMembers, markerIsCoincidentGroup, markerLayerPriorities, markerRegionalGroupingDistance, markerRegionalGroups, markerUsesRegionalGrouping } from './mapMarkerPriority'
import { recordMapInstanceCreation, recordMarkerReconciliation } from './mapScopePerformance'
import { MapMarkerViewportScale, mapMarkerZoomDimensions } from './mapMarkerSizing'
import { createTreasureChestDecoration, MAP_MARKER_CHEST, MAP_MARKER_CHEST_MASK, mapMarkerShape } from './mapMarkerShape'
import { resolveRestaurantFoodEmoji } from '../visuals/FoodCategoryVisualContract'
import { RestaurantFoodEmoji } from '../visuals/RestaurantFoodEmoji'

export type TasteMapMapViewport = TasteMapNativeMapViewport

interface RestaurantMarkerRecord {
  anchor: HTMLElement
  element: HTMLElement
  marker: AMapMarkerInstance
  signature: string
  accessibilityLabel: string
  stackSignature?: string
}

export interface RestaurantMarkerReconciliationPlan {
  added: RestaurantSummary[]
  changed: RestaurantSummary[]
  removed: string[]
  reused: RestaurantSummary[]
}

const markerImageSourceCache = new Map<string, Promise<string | null>>()
const maximumRetainedRestaurantMarkers = 500

interface MapViewProps {
  restaurants: RestaurantSummary[]
  selectedRestaurant?: RestaurantSummary
  onSelect: (restaurant: RestaurantSummary) => void
  onSelectGroup: (restaurantIDs: string[]) => void
  onClearSelection: () => void
  currentUser?: UserProfile
  currentCoordinates?: Coordinates | null
  initialViewport?: TasteMapMapViewport | null
  onViewportChange?: (viewport: TasteMapMapViewport) => void
  cameraFitKey?: string
  unvisitedMarkerStyle?: boolean
}

/** Canonical Browser map renderer. iOS Hybrid uses the Native MapKit surface. */
export function MapView({
  restaurants, selectedRestaurant, onSelect, onSelectGroup, onClearSelection, currentUser,
  currentCoordinates: injectedCoordinates, initialViewport, onViewportChange, cameraFitKey,
  unvisitedMarkerStyle = false,
}: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<AMapInstance | null>(null)
  const amapRef = useRef<AMapNamespace | null>(null)
  const restaurantMarkerRecordsRef = useRef(new Map<string, RestaurantMarkerRecord>())
  const regionalGroupsRef = useRef(new Map<string, RestaurantSummary[]>())
  const regionalGroupingRef = useRef(false)
  const markerViewportScaleRef = useRef(new MapMarkerViewportScale())
  const activeRestaurantIDsRef = useRef(new Set<string>())
  const locationMarkerRef = useRef<AMapMarkerInstance | null>(null)
  const selectedIdRef = useRef(selectedRestaurant?.id)
  const suppressMapClearUntilRef = useRef(0)
  const selectRef = useRef(onSelect)
  const selectGroupRef = useRef(onSelectGroup)
  const clearSelectionRef = useRef(onClearSelection)
  const viewportRef = useRef(onViewportChange)
  const didFitRef = useRef(false)
  const lastCameraFitKeyRef = useRef(cameraFitKey)
  const markerVisibilityRef = useRef<() => void>(() => undefined)
  const [loading, setLoading] = useState(mapService.isConfigured)
  const [mapReady, setMapReady] = useState(false)
  const [error, setError] = useState('')
  const [browserCoordinates, setBrowserCoordinates] = useState<Coordinates | null>(null)
  const currentCoordinates = injectedCoordinates === undefined ? browserCoordinates : injectedCoordinates

  selectedIdRef.current = selectedRestaurant?.id
  selectRef.current = onSelect
  selectGroupRef.current = onSelectGroup
  clearSelectionRef.current = onClearSelection
  viewportRef.current = onViewportChange

  useEffect(() => {
    if (!mapService.isConfigured || !containerRef.current) return
    const restaurantRecords = restaurantMarkerRecordsRef.current
    const activeRestaurantIDs = activeRestaurantIDsRef.current
    let disposed = false
    const detach: Array<() => void> = []
    mapService.loadWebMapSdk().then((AMap) => {
      if (disposed || !containerRef.current) return
      amapRef.current = AMap
      const map = new AMap.Map(containerRef.current, {
        zoom: initialViewport?.zoom ?? 12,
        center: initialViewport ? [initialViewport.center.longitude, initialViewport.center.latitude] : [120.1551, 30.2741],
        viewMode: '2D', mapStyle: 'amap://styles/normal', showLabel: true,
        features: ['bg', 'road', 'building'],
      })
      recordMapInstanceCreation()
      map.addControl(new AMap.ToolBar({ position: 'RT' }))
      map.addControl(new AMap.Scale())
      const handleMapClick = () => {
        if (Date.now() >= suppressMapClearUntilRef.current) clearSelectionRef.current()
      }
      const publishViewport = () => {
        markerVisibilityRef.current()
        viewportRef.current?.(readViewport(map))
      }
      const updateMarkerVisibility = () => markerVisibilityRef.current()
      map.on('click', handleMapClick)
      map.on('moveend', publishViewport)
      map.on('zoomend', publishViewport)
      map.on('zoomchange', updateMarkerVisibility)
      detach.push(
        () => map.off('click', handleMapClick),
        () => map.off('moveend', publishViewport),
        () => map.off('zoomend', publishViewport),
        () => map.off('zoomchange', updateMarkerVisibility),
      )
      mapRef.current = map
      setMapReady(true)
      setLoading(false)
    }).catch((mapError) => {
      if (!disposed) {
        setLoading(false)
        setError(mapError instanceof Error ? mapError.message : '地图加载失败。')
      }
    })
    return () => {
      disposed = true
      detach.forEach((value) => value())
      restaurantRecords.forEach((record) => record.marker.setMap(null))
      restaurantRecords.clear()
      activeRestaurantIDs.clear()
      locationMarkerRef.current?.setMap(null)
      locationMarkerRef.current = null
      mapRef.current?.destroy()
      mapRef.current = null
      amapRef.current = null
      markerVisibilityRef.current = () => undefined
      regionalGroupsRef.current.clear()
    }
  }, [])

  useEffect(() => {
    if (injectedCoordinates !== undefined || !mapReady) return
    let active = true
    void mapService.detectCurrentLocation()
      .then((location) => { if (active) setBrowserCoordinates({ longitude: location.longitude, latitude: location.latitude }) })
      .catch(() => { if (active) setBrowserCoordinates(null) })
    return () => { active = false }
  }, [injectedCoordinates, mapReady])

  useEffect(() => {
    const map = mapRef.current
    const AMap = amapRef.current
    locationMarkerRef.current?.setMap(null)
    locationMarkerRef.current = null
    if (!map || !AMap || !currentUser || !currentCoordinates) return
    locationMarkerRef.current = new AMap.Marker({
      map, position: [currentCoordinates.longitude, currentCoordinates.latitude],
      content: createUserLocationContent(currentUser), anchor: 'bottom-center',
      zIndex: 2_000_000_000, title: '我的当前位置',
    })
    return () => {
      locationMarkerRef.current?.setMap(null)
      locationMarkerRef.current = null
    }
  }, [currentCoordinates, currentUser, mapReady])

  useEffect(() => {
    const map = mapRef.current
    const AMap = amapRef.current
    if (!map || !AMap) return
    const records = restaurantMarkerRecordsRef.current
    const activeIDs = activeRestaurantIDsRef.current
    const layerPriorities = markerLayerPriorities(restaurants, selectedIdRef.current)
    const plan = restaurantMarkerReconciliationPlan(activeIDs, records, restaurants, currentCoordinates, unvisitedMarkerStyle)
    let added = 0
    const removed = plan.removed.length
    const changed = plan.changed.length
    const reused = plan.reused.length

    plan.removed.forEach((restaurantID) => {
      records.get(restaurantID)?.marker.setMap(null)
      activeIDs.delete(restaurantID)
    })

    restaurants.forEach((restaurant) => {
      const signature = restaurantMarkerSignature(restaurant, currentCoordinates, unvisitedMarkerStyle)
      const existing = records.get(restaurant.id)
      if (existing?.signature === signature) {
        if (!activeIDs.has(restaurant.id)) {
          existing.marker.setMap(map)
          activeIDs.add(restaurant.id)
          added += 1
        }
        return
      }
      if (existing) {
        existing.marker.setMap(null)
        records.delete(restaurant.id)
        activeIDs.delete(restaurant.id)
      }
      const content = createRestaurantImageMarkerContent(restaurant, currentCoordinates, unvisitedMarkerStyle)
      const isSelected = restaurant.id === selectedIdRef.current
      content.classList.toggle('is-selected', isSelected)
      // Keep the provider's anchor box fixed while the circle changes size.
      // Its center always represents the Restaurant's actual coordinate.
      const anchor = document.createElement('div')
      anchor.className = 'private-image-marker-anchor'
      anchor.append(content)
      const marker = new AMap.Marker({
        map, position: [restaurant.longitude, restaurant.latitude], content: anchor,
        anchor: 'center', offset: new AMap.Pixel(0, 0),
        zIndex: layerPriorities.get(restaurant.id), title: restaurant.name,
      })
      const select = (event?: Event) => {
        event?.preventDefault()
        event?.stopPropagation()
        suppressMapClearUntilRef.current = Date.now() + 450
        const group = regionalGroupsRef.current.get(restaurant.id)
        if (group && group.length > 1) {
          if (regionalGroupingRef.current && !markerIsCoincidentGroup(group)) fitRestaurantsOnMap(map, group, containerRef.current)
          else selectGroupRef.current(group.map((member) => member.id))
          return
        }
        selectRef.current(restaurant)
      }
      content.addEventListener('click', select)
      anchor.addEventListener('click', select)
      marker.on('click', () => select())
      records.set(restaurant.id, { anchor, element: content, marker, signature, accessibilityLabel: content.getAttribute('aria-label') ?? restaurant.name })
      activeIDs.add(restaurant.id)
      added += 1
    })
    trimInactiveRestaurantMarkerPool(records, activeIDs)
    recordMarkerReconciliation({ added, removed, changed, reused, active: activeIDs.size })
    let lastVisibilityKey = ''
    const updateMarkerVisibility = () => {
      const container = containerRef.current
      const visibilityKey = `${map.getZoom()}:${container?.clientWidth ?? 0}:${container?.clientHeight ?? 0}`
      if (lastVisibilityKey === visibilityKey) return
      lastVisibilityKey = visibilityKey
      const bounds = map.getBounds()
      const latitudeDelta = markerViewportScaleRef.current.resolve(
        map.getZoom(), container?.clientWidth ?? 0, container?.clientHeight ?? 0,
        bounds.getNorthEast().getLat() - bounds.getSouthWest().getLat(),
      )
      const regionalGrouping = markerUsesRegionalGrouping(latitudeDelta)
      regionalGroupingRef.current = regionalGrouping
      const baselineStyle = container ? getComputedStyle(container) : null
      const markerDiameter = Number.parseFloat(baselineStyle?.getPropertyValue('--map-marker-size') ?? '') || 32
      const dimensions = mapMarkerZoomDimensions(latitudeDelta, {
        diameter: markerDiameter,
        selectedDiameter: Number.parseFloat(baselineStyle?.getPropertyValue('--map-marker-selected-size') ?? '') || 36,
        unvisitedIncrease: Number.parseFloat(baselineStyle?.getPropertyValue('--map-marker-unvisited-increase') ?? '') || 4,
      })
      const screenPoints = new Map(restaurants.map((restaurant) => {
        const point = map.lngLatToContainer([restaurant.longitude, restaurant.latitude])
        return [restaurant.id, { x: point.getX(), y: point.getY() }] as const
      }))
      const groupingDistance = markerRegionalGroupingDistance(latitudeDelta, markerDiameter)
      const groups = regionalGrouping && groupingDistance > 0
        ? markerRegionalGroups(restaurants, screenPoints, groupingDistance)
        : markerCoincidentGroups(restaurants)
      regionalGroupsRef.current = new Map(groups.flatMap((group) =>
        (regionalGrouping ? group.slice(0, 1) : group).map((member) => [member.id, group] as const),
      ))
      // Distinct city coordinates stay independent, including overlapping circles.
      // Only exact-coordinate members share a small real-image stack.
      const visibleIDs = new Set(groups.map((group) => group[0].id))
      restaurants.forEach((restaurant) => {
        const record = records.get(restaurant.id)
        if (!record) return
        // Override only centered content sizes. The provider's 44px anchor,
        // coordinate and the independent grouping baseline remain untouched.
        record.anchor.style.setProperty('--map-marker-size', `${dimensions.diameter}px`)
        record.anchor.style.setProperty('--map-marker-selected-size', `${dimensions.selectedDiameter}px`)
        record.anchor.style.setProperty('--map-marker-unvisited-increase', `${dimensions.unvisitedIncrease}px`)
        record.anchor.style.setProperty('--map-marker-glyph-size', `${dimensions.glyphSize}px`)
        const visible = visibleIDs.has(restaurant.id)
        const group = regionalGroupsRef.current.get(restaurant.id)
        updateCoincidentStackContent(record, visible ? group ?? [] : [], unvisitedMarkerStyle)
        // The real Restaurant visual never becomes a count circle or badge.
        // At city scale all coordinates stay visible, even when they overlap.
        record.element.setAttribute('aria-label', group && group.length > 1
          ? `${record.accessibilityLabel}，${markerIsCoincidentGroup(group) ? '此处有多家餐厅，轻点查看列表' : '轻点放大查看附近餐厅'}`
          : record.accessibilityLabel)
        record.anchor.style.visibility = visible ? 'visible' : 'hidden'
        // A focused tooltip may override inherited visibility. Opacity on the
        // ancestor and inert keep the complete hidden marker out of view/input.
        record.anchor.style.opacity = visible ? '1' : '0'
        record.anchor.inert = !visible
      })
    }
    markerVisibilityRef.current = updateMarkerVisibility
    updateMarkerVisibility()
    const cameraRequested = !didFitRef.current || cameraFitKey !== lastCameraFitKeyRef.current
    if (cameraRequested && restaurants.length) {
      didFitRef.current = true
      lastCameraFitKeyRef.current = cameraFitKey
      fitRestaurantsOnMap(map, restaurants, containerRef.current)
    }
    return () => {
      if (markerVisibilityRef.current === updateMarkerVisibility) markerVisibilityRef.current = () => undefined
    }
  }, [cameraFitKey, currentCoordinates, mapReady, restaurants, unvisitedMarkerStyle])

  useEffect(() => {
    const layerPriorities = markerLayerPriorities(restaurants, selectedRestaurant?.id)
    restaurantMarkerRecordsRef.current.forEach((record, restaurantId) => {
      if (!activeRestaurantIDsRef.current.has(restaurantId)) return
      const restaurant = restaurants.find((value) => value.id === restaurantId)
      const isSelected = restaurantId === selectedRestaurant?.id
      record.element.classList.toggle('is-selected', isSelected)
      if (restaurant) record.marker.setzIndex(layerPriorities.get(restaurant.id) ?? 0)
      record.marker.setTop(isSelected)
    })
  }, [restaurants, selectedRestaurant?.id])

  if (!mapService.isConfigured) {
    return <OfflineRestaurantMap
      currentCoordinates={currentCoordinates}
      currentUser={currentUser}
      message="地图服务配置尚未就绪；本地餐厅仍可浏览。"
      onClearSelection={onClearSelection}
      onSelect={onSelect}
      onSelectGroup={onSelectGroup}
      restaurants={restaurants}
      selectedRestaurant={selectedRestaurant}
      unvisitedMarkerStyle={unvisitedMarkerStyle}
    />
  }
  if (error) return <OfflineRestaurantMap
    currentCoordinates={currentCoordinates}
    currentUser={currentUser}
    message={`地图底图暂时不可用：${error}`}
    onClearSelection={onClearSelection}
    onSelect={onSelect}
    onSelectGroup={onSelectGroup}
    restaurants={restaurants}
    selectedRestaurant={selectedRestaurant}
    unvisitedMarkerStyle={unvisitedMarkerStyle}
  />
  return <>
    <div
      className="amap-container"
      data-map-runtime={mapReady ? 'amap-ready' : 'amap-loading'}
      ref={containerRef}
    />
    {loading ? <div className="map-loading"><LoaderCircle className="spin" size={23} /> 正在加载地图</div> : null}
    {!loading && restaurants.length === 0 ? <div className="map-empty-tip"><MapPin size={18} />当前筛选下没有餐厅</div> : null}
  </>
}

function trimInactiveRestaurantMarkerPool(
  records: Map<string, RestaurantMarkerRecord>,
  activeIDs: ReadonlySet<string>,
) {
  if (records.size <= maximumRetainedRestaurantMarkers) return
  for (const [restaurantID, record] of records) {
    if (records.size <= maximumRetainedRestaurantMarkers) break
    if (activeIDs.has(restaurantID)) continue
    record.marker.setMap(null)
    records.delete(restaurantID)
  }
}

export function restaurantMarkerReconciliationPlan(
  activeIDs: ReadonlySet<string>,
  records: ReadonlyMap<string, Pick<RestaurantMarkerRecord, 'signature'>>,
  restaurants: RestaurantSummary[],
  currentCoordinates: Coordinates | null,
  unvisitedMarkerStyle = false,
): RestaurantMarkerReconciliationPlan {
  const nextIDs = new Set(restaurants.map((restaurant) => restaurant.id))
  const removed = [...activeIDs].filter((restaurantID) => !nextIDs.has(restaurantID))
  const added: RestaurantSummary[] = []
  const changed: RestaurantSummary[] = []
  const reused: RestaurantSummary[] = []
  restaurants.forEach((restaurant) => {
    const existing = records.get(restaurant.id)
    if (!existing) added.push(restaurant)
    else if (existing.signature !== restaurantMarkerSignature(restaurant, currentCoordinates, unvisitedMarkerStyle)) changed.push(restaurant)
    else reused.push(restaurant)
  })
  return { added, changed, removed, reused }
}

function createRestaurantImageMarkerContent(restaurant: RestaurantSummary, currentCoordinates: Coordinates | null, forceUnvisitedStyle = false) {
  const unvisited = isUnvisitedMapMarker(restaurant.status, forceUnvisitedStyle)
  const scoreText = unvisited ? (forceUnvisitedStyle ? '推荐餐厅' : '想去') : restaurant.scoreOutOfTen !== null ? `${restaurant.scoreOutOfTen.toFixed(1)} 分` : '尚未评分'
  const marker = document.createElement('button')
  marker.type = 'button'
  marker.className = `private-image-marker${unvisited ? ' is-unvisited' : ''}`
  marker.dataset.markerShape = mapMarkerShape(restaurant.status, forceUnvisitedStyle)
  marker.style.setProperty('--marker-chest-mask', MAP_MARKER_CHEST_MASK)
  marker.style.setProperty('--marker-color', scoreColor(unvisited ? null : restaurant.scoreOutOfTen))
  const distanceKilometers = currentCoordinates ? distanceBetweenCoordinates(currentCoordinates, restaurant) : null
  if (restaurant.status === 'wantToGo' && distanceKilometers !== null) {
    marker.dataset.distance = `${distanceKilometers.toFixed(distanceKilometers < 10 ? 1 : 0)} 公里`
  }
  marker.setAttribute('aria-label', `${restaurant.name}，${scoreText}，去过 ${restaurant.visitCount} 次`)
  const visual = createRestaurantMarkerVisual(restaurant)
  const tooltip = document.createElement('span')
  tooltip.className = 'private-image-marker__tooltip'
  const name = document.createElement('strong')
  name.textContent = restaurant.name
  const meta = document.createElement('span')
  meta.textContent = restaurant.status === 'wantToGo' && marker.dataset.distance
    ? `${scoreText} · 距你约 ${marker.dataset.distance}`
    : forceUnvisitedStyle ? scoreText : `${scoreText} · 去过 ${restaurant.visitCount} 次`
  tooltip.append(name, meta)
  marker.append(visual, tooltip)
  if (marker.dataset.markerShape === 'treasureChest') marker.append(createTreasureChestDecoration())
  return marker
}

function createRestaurantMarkerVisual(restaurant: RestaurantSummary) {
  const visual = document.createElement('span')
  visual.className = 'private-image-marker__visual'
  visual.dataset.restaurantId = restaurant.id
  renderFoodCategoryFallback(visual, restaurant)
  if (restaurant.markerImageData) {
    const image = document.createElement('img')
    image.alt = ''
    image.dataset.restaurantImage = 'true'
    image.addEventListener('load', () => visual.replaceChildren(image), { once: true })
    image.addEventListener('error', () => image.remove(), { once: true })
    void cachedMarkerImageSource(restaurant.markerImageData, restaurant.markerPhotoId).then((source) => {
      if (source) image.src = source
    }).catch(() => undefined)
  }
  return visual
}

function updateCoincidentStackContent(record: RestaurantMarkerRecord, group: RestaurantSummary[], forceUnvisitedStyle: boolean) {
  const backMembers = markerCoincidentStackMembers(group).slice(1)
  const signature = backMembers.map((member) => restaurantMarkerSignature(member, null, forceUnvisitedStyle)).join('|')
  if (record.stackSignature === signature) return
  record.stackSignature = signature
  record.anchor.querySelectorAll('.private-image-marker__stack-back').forEach((layer) => layer.remove())
  backMembers.forEach((member, index) => {
    const layer = document.createElement('span')
    layer.className = `private-image-marker__stack-back${isUnvisitedMapMarker(member.status, forceUnvisitedStyle) ? ' is-unvisited' : ''}`
    layer.dataset.markerShape = mapMarkerShape(member.status, forceUnvisitedStyle)
    layer.style.setProperty('--marker-chest-mask', MAP_MARKER_CHEST_MASK)
    layer.dataset.stackLayer = String(index)
    layer.setAttribute('aria-hidden', 'true')
    layer.style.setProperty('--marker-color', scoreColor(forceUnvisitedStyle || member.status === 'wantToGo' ? null : member.scoreOutOfTen))
    layer.append(createRestaurantMarkerVisual(member))
    if (layer.dataset.markerShape === 'treasureChest') layer.append(createTreasureChestDecoration())
    record.anchor.insertBefore(layer, record.element)
  })
}

function cachedMarkerImageSource(source: string, photoID?: string | null) {
  const key = `${photoID ?? ''}|${source}`
  const cached = markerImageSourceCache.get(key)
  if (cached) return cached
  const directNativeResource = source.startsWith('tastemap-resource://')
  const value = directNativeResource ? Promise.resolve(source) : resolvePhotoSource(source, photoID)
  markerImageSourceCache.set(key, value)
  while (markerImageSourceCache.size > 500) {
    const oldest = markerImageSourceCache.keys().next().value
    if (oldest === undefined) break
    markerImageSourceCache.delete(oldest)
  }
  return value
}

export function restaurantMarkerSignature(restaurant: RestaurantSummary, currentCoordinates: Coordinates | null, unvisitedMarkerStyle = false) {
  return JSON.stringify({
    id: restaurant.id,
    name: restaurant.name,
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    status: restaurant.status,
    score: restaurant.scoreOutOfTen,
    visits: restaurant.visitCount,
    image: restaurant.markerImageData || null,
    photo: restaurant.markerPhotoId || null,
    emoji: restaurant.markerEmoji || null,
    tags: restaurant.tags,
    location: currentCoordinates ? [currentCoordinates.latitude, currentCoordinates.longitude] : null,
    unvisitedMarkerStyle,
  })
}

function renderFoodCategoryFallback(target: HTMLElement, restaurant: RestaurantSummary) {
  const emoji = document.createElement('span')
  emoji.className = 'tm-restaurant-food-emoji__glyph'
  emoji.setAttribute('aria-hidden', 'true')
  emoji.textContent = resolveRestaurantFoodEmoji(restaurant, restaurant.markerEmoji)
  target.replaceChildren(emoji)
}

function createUserLocationContent(currentUser: UserProfile) {
  const content = document.createElement('div')
  content.className = 'current-user-marker'
  const bubble = document.createElement('div')
  bubble.className = 'current-user-marker__bubble'
  const position = avatarPresetPosition(currentUser.avatarPresetId)
  const preset = document.createElement('span')
  preset.className = 'avatar-preset-sprite'
  preset.style.setProperty('--avatar-x', `${position.x}%`)
  preset.style.setProperty('--avatar-y', `${position.y}%`)
  bubble.appendChild(preset)
  const halo = document.createElement('span')
  halo.className = 'current-user-marker__halo'
  const tail = document.createElement('span')
  tail.className = 'current-user-marker__tail'
  content.append(halo, bubble, tail)
  return content
}

function readViewport(map: AMapInstance): TasteMapMapViewport {
  const bounds = map.getBounds()
  const northEast = bounds.getNorthEast()
  const southWest = bounds.getSouthWest()
  const center = map.getCenter()
  return {
    bounds: { north: northEast.getLat(), east: northEast.getLng(), south: southWest.getLat(), west: southWest.getLng() },
    center: { latitude: center.getLat(), longitude: center.getLng() }, zoom: map.getZoom(),
  }
}

function distanceBetweenCoordinates(from: Coordinates, to: Coordinates) {
  const earthRadiusKilometers = 6371
  const latitudeDelta = toRadians(to.latitude - from.latitude)
  const longitudeDelta = toRadians(to.longitude - from.longitude)
  const fromLatitude = toRadians(from.latitude)
  const toLatitude = toRadians(to.latitude)
  const haversine = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(fromLatitude) * Math.cos(toLatitude) * Math.sin(longitudeDelta / 2) ** 2
  return earthRadiusKilometers * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
}

function toRadians(degrees: number) { return degrees * Math.PI / 180 }

function fitRestaurantsOnMap(map: AMapInstance, restaurants: RestaurantSummary[], container: HTMLElement | null) {
  if (!restaurants.length) return
  if (restaurants.length === 1) {
    map.setZoomAndCenter(15, [restaurants[0].longitude, restaurants[0].latitude], false, 260)
    return
  }
  const longitudes = restaurants.map((restaurant) => restaurant.longitude)
  const latitudes = restaurants.map((restaurant) => restaurant.latitude)
  const minimumLongitude = Math.min(...longitudes)
  const maximumLongitude = Math.max(...longitudes)
  const minimumLatitude = Math.min(...latitudes)
  const maximumLatitude = Math.max(...latitudes)
  const longitudeSpan = Math.max(maximumLongitude - minimumLongitude, 0.0002)
  const latitudeSpan = Math.max(maximumLatitude - minimumLatitude, 0.0002)
  const availableWidth = Math.max(280, (container?.clientWidth ?? 900) - 100)
  const availableHeight = Math.max(280, (container?.clientHeight ?? 700) - 120)
  const longitudeZoom = Math.log2((360 * availableWidth) / (longitudeSpan * 256))
  const latitudeZoom = Math.log2((170 * availableHeight) / (latitudeSpan * 256))
  const zoom = Math.max(5, Math.min(17, Math.floor(Math.min(longitudeZoom, latitudeZoom))))
  map.setZoomAndCenter(zoom, [(minimumLongitude + maximumLongitude) / 2, (minimumLatitude + maximumLatitude) / 2], false, 260)
}

function OfflineRestaurantMap({ restaurants, selectedRestaurant, currentUser, currentCoordinates, onSelect, onSelectGroup, onClearSelection, message, unvisitedMarkerStyle }: {
  restaurants: RestaurantSummary[]
  selectedRestaurant?: RestaurantSummary
  currentUser?: UserProfile
  currentCoordinates: Coordinates | null
  onSelect: (restaurant: RestaurantSummary) => void
  onSelectGroup: (restaurantIDs: string[]) => void
  onClearSelection: () => void
  message: string
  unvisitedMarkerStyle: boolean
}) {
  const projection = useMemo(() => coordinateProjection(restaurants, currentCoordinates), [currentCoordinates, restaurants])
  const layerPriorities = useMemo(() => markerLayerPriorities(restaurants, selectedRestaurant?.id), [restaurants, selectedRestaurant?.id])
  const groupsByMember = useMemo(() => new Map(markerCoincidentGroups(restaurants)
    .flatMap((group) => group.map((member) => [member.id, group] as const))), [restaurants])
  return <div
    aria-label="静态餐厅位置预览，不支持地图平移或缩放"
    className="tm-offline-map"
    data-map-runtime="fallback-static"
    onClick={onClearSelection}
    role="group"
  >
    <div aria-hidden="true" className="map-grid" />
    <p className="tm-offline-map__notice"><KeyRound aria-hidden="true" size={13} />{message}</p>
    {restaurants.map((restaurant) => {
      const point = projection(restaurant)
      const selected = restaurant.id === selectedRestaurant?.id
      const unvisited = isUnvisitedMapMarker(restaurant.status, unvisitedMarkerStyle)
      const group = groupsByMember.get(restaurant.id) ?? [restaurant]
      const stacked = group.length > 1
      const visible = group[0].id === restaurant.id
      const backMembers = visible ? markerCoincidentStackMembers(group).slice(1) : []
      return <div
        className="private-image-marker-anchor tm-offline-map__anchor"
        hidden={!visible}
        key={restaurant.id}
        onClick={(event) => { if (stacked) { event.stopPropagation(); onSelectGroup(group.map((member) => member.id)) } }}
        style={{ left: `${point.x}%`, top: `${point.y}%`, zIndex: layerPriorities.get(restaurant.id) }}
      >
        {backMembers.map((member, index) => <span aria-hidden="true" className={`private-image-marker__stack-back${isUnvisitedMapMarker(member.status, unvisitedMarkerStyle) ? ' is-unvisited' : ''}`} data-marker-shape={mapMarkerShape(member.status, unvisitedMarkerStyle)} data-stack-layer={index} key={member.id} style={{ '--marker-color': scoreColor(unvisitedMarkerStyle || member.status === 'wantToGo' ? null : member.scoreOutOfTen), '--marker-chest-mask': MAP_MARKER_CHEST_MASK } as CSSProperties}><OfflineMarkerVisual restaurant={member} />{mapMarkerShape(member.status, unvisitedMarkerStyle) === 'treasureChest' ? <TreasureChestDecoration /> : null}</span>)}
        <button
        aria-label={`${restaurant.name}，${unvisitedMarkerStyle ? '推荐餐厅' : restaurant.scoreOutOfTen?.toFixed(1) ?? '尚未评分'}${unvisitedMarkerStyle ? '' : `，去过 ${restaurant.visitCount} 次`}${stacked ? '，此处有多家餐厅，轻点查看列表' : ''}`}
        className={`private-image-marker tm-offline-map__marker${selected ? ' is-selected' : ''}${unvisited ? ' is-unvisited' : ''}`}
        data-marker-shape={mapMarkerShape(restaurant.status, unvisitedMarkerStyle)}
        onClick={(event) => { event.stopPropagation(); if (stacked) onSelectGroup(group.map((member) => member.id)); else onSelect(restaurant) }}
        style={{ '--marker-color': scoreColor(unvisited ? null : restaurant.scoreOutOfTen), '--marker-chest-mask': MAP_MARKER_CHEST_MASK } as CSSProperties}
        type="button"
      >
        <OfflineMarkerVisual restaurant={restaurant} />
        {mapMarkerShape(restaurant.status, unvisitedMarkerStyle) === 'treasureChest' ? <TreasureChestDecoration /> : null}
        <span className="private-image-marker__tooltip"><strong>{restaurant.name}</strong><span>{unvisitedMarkerStyle ? '推荐餐厅' : `${restaurant.scoreOutOfTen?.toFixed(1) ?? '想吃'} 分 · ${restaurant.visitCount} 次`}</span></span>
      </button></div>
    })}
    {currentCoordinates && currentUser ? <OfflineUserMarker point={projection(currentCoordinates)} user={currentUser} /> : null}
  </div>
}

function TreasureChestDecoration() {
  return <img aria-hidden="true" alt="" draggable={false} className="private-image-marker__chest-shell" src={MAP_MARKER_CHEST.source} />
}

function OfflineMarkerVisual({ restaurant }: { restaurant: RestaurantSummary }) {
  const [failed, setFailed] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const source = restaurant.markerImageData
  return <span className="private-image-marker__visual" data-restaurant-id={restaurant.id}>
    {!loaded || failed || !source ? <RestaurantFoodEmoji label={`${restaurant.name} 食物表情`} name={restaurant.name} preferredEmoji={restaurant.markerEmoji} tags={restaurant.tags} /> : null}
    {source && !failed
      ? <img alt="" data-restaurant-image="true" hidden={!loaded} onError={() => setFailed(true)} onLoad={() => setLoaded(true)} src={source} />
      : null}
  </span>
}

function OfflineUserMarker({ point, user }: { point: { x: number; y: number }; user: UserProfile }) {
  const position = avatarPresetPosition(user.avatarPresetId)
  return <div aria-label="我的当前位置" className="current-user-marker tm-offline-map__user" role="img" style={{ left: `${point.x}%`, top: `${point.y}%` }}>
    <span className="current-user-marker__halo" />
    <span className="current-user-marker__bubble"><span className="avatar-preset-sprite" style={{ '--avatar-x': `${position.x}%`, '--avatar-y': `${position.y}%` } as CSSProperties} /></span>
    <span className="current-user-marker__tail" />
  </div>
}

function coordinateProjection(restaurants: RestaurantSummary[], currentCoordinates: Coordinates | null) {
  const points = [...restaurants, ...(currentCoordinates ? [currentCoordinates] : [])]
  const longitudes = points.map((value) => value.longitude)
  const latitudes = points.map((value) => value.latitude)
  const minimumLongitude = Math.min(...longitudes, 120.14)
  const maximumLongitude = Math.max(...longitudes, 120.17)
  const minimumLatitude = Math.min(...latitudes, 30.25)
  const maximumLatitude = Math.max(...latitudes, 30.29)
  const longitudeSpan = Math.max(maximumLongitude - minimumLongitude, .002)
  const latitudeSpan = Math.max(maximumLatitude - minimumLatitude, .002)
  return (value: Coordinates) => ({
    x: 8 + ((value.longitude - minimumLongitude) / longitudeSpan) * 84,
    y: 8 + (1 - (value.latitude - minimumLatitude) / latitudeSpan) * 84,
  })
}
