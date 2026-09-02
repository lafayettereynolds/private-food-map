import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import { KeyRound, LoaderCircle, MapPin } from 'lucide-react'
import type { TasteMapMapBounds } from '../platform/TasteMapPlatform'
import { type AMapInstance, type AMapMarkerInstance, type AMapNamespace } from '../services/amap'
import { mapService } from '../services/mapService'
import { resolvePhotoSource } from '../services/photoAssets'
import { scoreColor, type Coordinates, type RestaurantSummary, type UserProfile } from '../types/domain'
import { avatarPresetPosition } from '../utils/avatarPresets'
import { wantedMarkerScale } from '../utils/mapMarkers'
import { markerLayerPriority } from './mapMarkerPriority'

export { markerLayerPriority } from './mapMarkerPriority'

export interface TasteMapMapViewport {
  bounds: TasteMapMapBounds
  center: Coordinates
  zoom: number
}

interface MapViewProps {
  restaurants: RestaurantSummary[]
  selectedRestaurant?: RestaurantSummary
  onSelect: (restaurant: RestaurantSummary) => void
  onClearSelection: () => void
  currentUser?: UserProfile
  currentCoordinates?: Coordinates | null
  initialViewport?: TasteMapMapViewport | null
  onViewportChange?: (viewport: TasteMapMapViewport) => void
  cameraFitKey?: string
}

/** Canonical Web/Hybrid renderer: independent markers at real coordinates. */
export function MapView({
  restaurants, selectedRestaurant, onSelect, onClearSelection, currentUser,
  currentCoordinates: injectedCoordinates, initialViewport, onViewportChange, cameraFitKey,
}: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<AMapInstance | null>(null)
  const amapRef = useRef<AMapNamespace | null>(null)
  const restaurantElementsRef = useRef(new Map<string, HTMLElement>())
  const restaurantMarkersRef = useRef(new Map<string, AMapMarkerInstance>())
  const locationMarkerRef = useRef<AMapMarkerInstance | null>(null)
  const selectedIdRef = useRef(selectedRestaurant?.id)
  const suppressMapClearUntilRef = useRef(0)
  const selectRef = useRef(onSelect)
  const clearSelectionRef = useRef(onClearSelection)
  const viewportRef = useRef(onViewportChange)
  const didFitRef = useRef(false)
  const lastCameraFitKeyRef = useRef(cameraFitKey)
  const [loading, setLoading] = useState(mapService.isConfigured)
  const [mapReady, setMapReady] = useState(false)
  const [error, setError] = useState('')
  const [browserCoordinates, setBrowserCoordinates] = useState<Coordinates | null>(null)
  const currentCoordinates = injectedCoordinates === undefined ? browserCoordinates : injectedCoordinates

  selectedIdRef.current = selectedRestaurant?.id
  selectRef.current = onSelect
  clearSelectionRef.current = onClearSelection
  viewportRef.current = onViewportChange

  useEffect(() => {
    if (!mapService.isConfigured || !containerRef.current) return
    const restaurantElements = restaurantElementsRef.current
    const restaurantMarkers = restaurantMarkersRef.current
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
      map.addControl(new AMap.ToolBar({ position: 'RT' }))
      map.addControl(new AMap.Scale())
      const handleMapClick = () => {
        if (Date.now() >= suppressMapClearUntilRef.current) clearSelectionRef.current()
      }
      const publishViewport = () => viewportRef.current?.(readViewport(map))
      map.on('click', handleMapClick)
      map.on('moveend', publishViewport)
      map.on('zoomend', publishViewport)
      detach.push(
        () => map.off('click', handleMapClick),
        () => map.off('moveend', publishViewport),
        () => map.off('zoomend', publishViewport),
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
      restaurantMarkers.forEach((marker) => marker.setMap(null))
      restaurantElements.clear()
      restaurantMarkers.clear()
      locationMarkerRef.current?.setMap(null)
      locationMarkerRef.current = null
      mapRef.current?.destroy()
      mapRef.current = null
      amapRef.current = null
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
    const elements = restaurantElementsRef.current
    const markers = restaurantMarkersRef.current
    markers.forEach((marker) => marker.setMap(null))
    elements.clear()
    markers.clear()
    restaurants.forEach((restaurant) => {
      const content = createRestaurantImageMarkerContent(restaurant, currentCoordinates)
      const isSelected = restaurant.id === selectedIdRef.current
      content.classList.toggle('is-selected', isSelected)
      const marker = new AMap.Marker({
        map, position: [restaurant.longitude, restaurant.latitude], content,
        anchor: 'center', zIndex: markerLayerPriority(restaurant, isSelected), title: restaurant.name,
      })
      const select = (event?: Event) => {
        event?.preventDefault()
        event?.stopPropagation()
        suppressMapClearUntilRef.current = Date.now() + 450
        selectRef.current(restaurant)
      }
      content.addEventListener('click', select)
      marker.on('click', () => select())
      elements.set(restaurant.id, content)
      markers.set(restaurant.id, marker)
    })
    const cameraRequested = !didFitRef.current || cameraFitKey !== lastCameraFitKeyRef.current
    if (cameraRequested && restaurants.length) {
      didFitRef.current = true
      lastCameraFitKeyRef.current = cameraFitKey
      fitRestaurantsOnMap(map, restaurants, containerRef.current)
    }
    return () => {
      markers.forEach((marker) => marker.setMap(null))
      elements.clear()
      markers.clear()
    }
  }, [cameraFitKey, currentCoordinates, mapReady, restaurants])

  useEffect(() => {
    restaurantElementsRef.current.forEach((element, restaurantId) => {
      const marker = restaurantMarkersRef.current.get(restaurantId)
      const restaurant = restaurants.find((value) => value.id === restaurantId)
      const isSelected = restaurantId === selectedRestaurant?.id
      element.classList.toggle('is-selected', isSelected)
      if (marker && restaurant) marker.setzIndex(markerLayerPriority(restaurant, isSelected))
      marker?.setTop(isSelected)
    })
  }, [restaurants, selectedRestaurant?.id])

  if (!mapService.isConfigured) {
    return <OfflineRestaurantMap
      currentCoordinates={currentCoordinates}
      currentUser={currentUser}
      message="地图服务配置尚未就绪；本地餐厅仍可浏览。"
      onClearSelection={onClearSelection}
      onSelect={onSelect}
      restaurants={restaurants}
      selectedRestaurant={selectedRestaurant}
    />
  }
  if (error) return <OfflineRestaurantMap
    currentCoordinates={currentCoordinates}
    currentUser={currentUser}
    message={`地图底图暂时不可用：${error}`}
    onClearSelection={onClearSelection}
    onSelect={onSelect}
    restaurants={restaurants}
    selectedRestaurant={selectedRestaurant}
  />
  return <>
    <div className="amap-container" ref={containerRef} />
    {loading ? <div className="map-loading"><LoaderCircle className="spin" size={23} /> 正在加载地图</div> : null}
    {!loading && restaurants.length === 0 ? <div className="map-empty-tip"><MapPin size={18} />当前筛选下没有餐厅</div> : null}
  </>
}

function createRestaurantImageMarkerContent(restaurant: RestaurantSummary, currentCoordinates: Coordinates | null) {
  const imageSource = restaurant.markerImageData || restaurant.merchantImageUrl
  const scoreText = restaurant.scoreOutOfTen !== null ? `${restaurant.scoreOutOfTen.toFixed(1)} 分` : '想去'
  const marker = document.createElement('button')
  marker.type = 'button'
  marker.className = `private-image-marker${restaurant.status === 'wantToGo' ? ' is-wanted' : ''}`
  marker.style.setProperty('--marker-color', scoreColor(restaurant.scoreOutOfTen))
  const distanceKilometers = currentCoordinates ? distanceBetweenCoordinates(currentCoordinates, restaurant) : null
  if (restaurant.status === 'wantToGo' && distanceKilometers !== null) {
    marker.style.setProperty('--marker-scale', wantedMarkerScale(distanceKilometers).toFixed(3))
    marker.dataset.distance = `${distanceKilometers.toFixed(distanceKilometers < 10 ? 1 : 0)} 公里`
  }
  marker.setAttribute('aria-label', `${restaurant.name}，${scoreText}，去过 ${restaurant.visitCount} 次`)
  const visual = document.createElement('span')
  visual.className = 'private-image-marker__visual'
  renderFoodDiningFallback(visual)
  if (imageSource) {
    const image = document.createElement('img')
    image.alt = ''
    image.addEventListener('load', () => visual.replaceChildren(image), { once: true })
    image.addEventListener('error', () => image.remove(), { once: true })
    const directNativeResource = imageSource.startsWith('tastemap-resource://')
    const resolved = directNativeResource ? Promise.resolve(imageSource) : resolvePhotoSource(imageSource, restaurant.markerPhotoId)
    void resolved.then((source) => {
      if (!source) return
      image.src = source
    }).catch(() => undefined)
  }
  const tooltip = document.createElement('span')
  tooltip.className = 'private-image-marker__tooltip'
  const name = document.createElement('strong')
  name.textContent = restaurant.name
  const meta = document.createElement('span')
  meta.textContent = restaurant.status === 'wantToGo' && marker.dataset.distance
    ? `${scoreText} · 距你约 ${marker.dataset.distance}`
    : `${scoreText} · 去过 ${restaurant.visitCount} 次`
  tooltip.append(name, meta)
  marker.append(visual, tooltip)
  return marker
}

function renderFoodDiningFallback(target: HTMLElement) {
  target.innerHTML = '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="M7 3v8M4.5 3v5.5A2.5 2.5 0 0 0 7 11M9.5 3v5.5A2.5 2.5 0 0 1 7 11v10M16 3c-2 2.2-3 5-3 8h4v10M16 3c2 2.2 3 5 3 8h-2" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.6"/></svg>'
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
  content.append(halo, bubble)
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

function OfflineRestaurantMap({ restaurants, selectedRestaurant, currentUser, currentCoordinates, onSelect, onClearSelection, message }: {
  restaurants: RestaurantSummary[]
  selectedRestaurant?: RestaurantSummary
  currentUser?: UserProfile
  currentCoordinates: Coordinates | null
  onSelect: (restaurant: RestaurantSummary) => void
  onClearSelection: () => void
  message: string
}) {
  const projection = useMemo(() => coordinateProjection(restaurants, currentCoordinates), [currentCoordinates, restaurants])
  return <div className="tm-offline-map" onClick={onClearSelection} role="group" aria-label="离线餐厅地图">
    <div aria-hidden="true" className="map-grid" />
    <p className="tm-offline-map__notice"><KeyRound aria-hidden="true" size={13} />{message}</p>
    {restaurants.map((restaurant) => {
      const point = projection(restaurant)
      const selected = restaurant.id === selectedRestaurant?.id
      return <button
        aria-label={`${restaurant.name}，${restaurant.scoreOutOfTen?.toFixed(1) ?? '尚未评分'}，去过 ${restaurant.visitCount} 次`}
        className={`private-image-marker tm-offline-map__marker${selected ? ' is-selected' : ''}${restaurant.status === 'wantToGo' ? ' is-wanted' : ''}`}
        key={restaurant.id}
        onClick={(event) => { event.stopPropagation(); onSelect(restaurant) }}
        style={{ '--marker-color': scoreColor(restaurant.scoreOutOfTen), left: `${point.x}%`, top: `${point.y}%`, zIndex: markerLayerPriority(restaurant, selected) } as CSSProperties}
        type="button"
      >
        <OfflineMarkerVisual restaurant={restaurant} />
        <span className="private-image-marker__tooltip"><strong>{restaurant.name}</strong><span>{restaurant.scoreOutOfTen?.toFixed(1) ?? '想吃'} 分 · {restaurant.visitCount} 次</span></span>
      </button>
    })}
    {currentCoordinates && currentUser ? <OfflineUserMarker point={projection(currentCoordinates)} user={currentUser} /> : null}
  </div>
}

function OfflineMarkerVisual({ restaurant }: { restaurant: RestaurantSummary }) {
  const [failed, setFailed] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const source = restaurant.markerImageData || restaurant.merchantImageUrl
  return <span className="private-image-marker__visual">
    {!loaded || failed || !source ? <FoodDiningFallbackIcon /> : null}
    {source && !failed
      ? <img alt="" hidden={!loaded} onError={() => setFailed(true)} onLoad={() => setLoaded(true)} src={source} />
      : null}
  </span>
}

function FoodDiningFallbackIcon() {
  return <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M7 3v8M4.5 3v5.5A2.5 2.5 0 0 0 7 11M9.5 3v5.5A2.5 2.5 0 0 1 7 11v10M16 3c-2 2.2-3 5-3 8h4v10M16 3c2 2.2 3 5 3 8h-2" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.6" /></svg>
}

function OfflineUserMarker({ point, user }: { point: { x: number; y: number }; user: UserProfile }) {
  const position = avatarPresetPosition(user.avatarPresetId)
  return <div aria-label="我的当前位置" className="current-user-marker tm-offline-map__user" role="img" style={{ left: `${point.x}%`, top: `${point.y}%` }}>
    <span className="current-user-marker__halo" />
    <span className="current-user-marker__bubble"><span className="avatar-preset-sprite" style={{ '--avatar-x': `${position.x}%`, '--avatar-y': `${position.y}%` } as CSSProperties} /></span>
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
