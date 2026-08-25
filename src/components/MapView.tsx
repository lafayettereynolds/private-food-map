import { useEffect, useRef, useState, type ReactNode } from 'react'
import { KeyRound, LoaderCircle, MapPin, RotateCcw } from 'lucide-react'
import {
  type AMapInstance,
  type AMapMarkerInstance,
  type AMapMarkerClusterInstance,
  type AMapMarkerClusterPoint,
  type AMapMarkerClusterRenderContext,
  type AMapNamespace,
} from '../services/amap'
import { mapService } from '../services/mapService'
import { scoreColor, type Coordinates, type RestaurantSummary, type UserProfile } from '../types/domain'
import { resolvePhotoSource } from '../services/photoAssets'
import { wantedMarkerScale } from '../utils/mapMarkers'
import { avatarPresetPosition } from '../utils/avatarPresets'

interface MapViewProps {
  restaurants: RestaurantSummary[]
  selectedRestaurant?: RestaurantSummary
  onSelect: (restaurant: RestaurantSummary) => void
  onClearSelection: () => void
  currentUser?: UserProfile
}

// City-level views should feel full, like Beli: restaurants render individually.
// Clustering is reserved for province/country-level zooms only.
const CLUSTER_MAX_ZOOM = 9
const MAP_MAX_ZOOM = 20

export function MapView({
  restaurants,
  selectedRestaurant,
  onSelect,
  onClearSelection,
  currentUser,
}: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<AMapInstance | null>(null)
  const amapRef = useRef<AMapNamespace | null>(null)
  const clusterRef = useRef<AMapMarkerClusterInstance | null>(null)
  const restaurantElementsRef = useRef(new Map<string, HTMLElement>())
  const restaurantMarkersRef = useRef(new Map<string, AMapMarkerInstance>())
  const locationMarkerRef = useRef<AMapMarkerInstance | null>(null)
  const selectedIdRef = useRef(selectedRestaurant?.id)
  const suppressMapClearUntilRef = useRef(0)
  const selectRef = useRef(onSelect)
  const clearSelectionRef = useRef(onClearSelection)
  const [loading, setLoading] = useState(mapService.isConfigured)
  const [mapReady, setMapReady] = useState(false)
  const [error, setError] = useState('')
  const [currentCoordinates, setCurrentCoordinates] = useState<Coordinates | null>(null)

  selectedIdRef.current = selectedRestaurant?.id
  selectRef.current = onSelect
  clearSelectionRef.current = onClearSelection

  useEffect(() => {
    if (!mapService.isConfigured || !containerRef.current) return
    const restaurantElements = restaurantElementsRef.current
    const restaurantMarkers = restaurantMarkersRef.current
    let disposed = false
    let detachMapClick: (() => void) | undefined

    mapService.loadWebMapSdk()
      .then((AMap) => {
        if (disposed || !containerRef.current) return
        amapRef.current = AMap
        const map = new AMap.Map(containerRef.current, {
          zoom: 5,
          center: [120.1551, 30.2741],
          viewMode: '2D',
          mapStyle: 'amap://styles/normal',
          showLabel: true,
          features: ['bg', 'road', 'building'],
        })
        map.addControl(new AMap.ToolBar({ position: 'RT' }))
        map.addControl(new AMap.Scale())

        const handleMapClick = () => {
          if (Date.now() < suppressMapClearUntilRef.current) return
          clearSelectionRef.current()
        }
        map.on('click', handleMapClick)
        detachMapClick = () => map.off('click', handleMapClick)
        mapRef.current = map
        setMapReady(true)
        setLoading(false)
      })
      .catch((mapError) => {
        if (disposed) return
        setLoading(false)
        setError(mapError instanceof Error ? mapError.message : '地图加载失败。')
      })

    return () => {
      disposed = true
      detachMapClick?.()
      clusterRef.current?.setMap(null)
      clusterRef.current = null
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
    if (!mapRef.current || !amapRef.current) return
    let disposed = false
    void mapService.detectCurrentLocation().then((location) => {
      if (!disposed) setCurrentCoordinates({ longitude: location.longitude, latitude: location.latitude })
    }).catch(() => {
      if (!disposed) setCurrentCoordinates(null)
    })
    return () => {
      disposed = true
    }
  }, [mapReady])

  useEffect(() => {
    const map = mapRef.current
    const AMap = amapRef.current
    locationMarkerRef.current?.setMap(null)
    locationMarkerRef.current = null
    if (!map || !AMap || !currentUser || !currentCoordinates) return
    let disposed = false
    void (async () => {
      const content = document.createElement('div')
      content.className = 'current-user-marker'
      const bubble = document.createElement('div')
      bubble.className = 'current-user-marker__bubble'
      const avatar = currentUser.membershipTier === 'member'
        ? await resolvePhotoSource(currentUser.avatarImageData, currentUser.avatarPhotoId).catch(() => null)
        : null
      if (disposed) return
      if (avatar) {
        const image = document.createElement('img')
        image.alt = ''
        image.src = avatar
        bubble.appendChild(image)
      } else {
        const position = avatarPresetPosition(currentUser.avatarPresetId)
        const preset = document.createElement('span')
        preset.className = 'avatar-preset-sprite'
        preset.style.setProperty('--avatar-x', `${position.x}%`)
        preset.style.setProperty('--avatar-y', `${position.y}%`)
        bubble.appendChild(preset)
      }
      content.appendChild(bubble)
      const tail = document.createElement('span')
      tail.className = 'current-user-marker__tail'
      content.appendChild(tail)
      locationMarkerRef.current = new AMap.Marker({
        map,
        position: [currentCoordinates.longitude, currentCoordinates.latitude],
        content,
        anchor: 'bottom-center',
        zIndex: 3000,
        title: '我的当前位置',
      })
    })()
    return () => {
      disposed = true
      locationMarkerRef.current?.setMap(null)
      locationMarkerRef.current = null
    }
  }, [currentCoordinates, currentUser, mapReady])

  useEffect(() => {
    const map = mapRef.current
    const AMap = amapRef.current
    if (!map || !AMap) return
    const restaurantElements = restaurantElementsRef.current
    const restaurantMarkers = restaurantMarkersRef.current

    clusterRef.current?.setMap(null)
    clusterRef.current = null
    restaurantElements.clear()
    restaurantMarkers.clear()
    if (restaurants.length === 0) return

    const { points, coordinateMap } = createClusterData(restaurants)

    const renderMarker = (context: AMapMarkerClusterRenderContext) => {
      const position = context.marker.getPosition()
      const restaurant = coordinateMap.get(coordinateKey(position.getLng(), position.getLat()))?.[0]
      if (!restaurant) return

      const content = createRestaurantImageMarkerContent(restaurant, currentCoordinates)
      content.classList.toggle('is-selected', restaurant.id === selectedIdRef.current)
      content.addEventListener('click', (event) => {
        event.preventDefault()
        event.stopPropagation()
        event.stopImmediatePropagation()
        suppressMapClearUntilRef.current = Date.now() + 450
        selectRef.current(restaurant)
      })
      context.marker.on('click', () => {
        suppressMapClearUntilRef.current = Date.now() + 450
        selectRef.current(restaurant)
      })
      restaurantElements.set(restaurant.id, content)
      restaurantMarkers.set(restaurant.id, context.marker)
      context.marker.setContent(content)
      context.marker.setAnchor('center')
      context.marker.setOffset(new AMap.Pixel(0, 0))
      context.marker.setzIndex(markerLayerPriority(restaurant))
      context.marker.setTop(restaurant.id === selectedIdRef.current)
    }

    const renderClusterMarker = (context: AMapMarkerClusterRenderContext) => {
      const content = document.createElement('button')
      content.type = 'button'
      content.className = 'private-cluster-marker'
      content.setAttribute('aria-label', `附近 ${context.count} 家餐厅`)
      content.textContent = String(context.count)
      content.addEventListener('click', (event) => {
        event.preventDefault()
        event.stopPropagation()
        event.stopImmediatePropagation()
        const currentZoom = map.getZoom()
        if (currentZoom >= MAP_MAX_ZOOM) return
        const position = context.marker.getPosition()
        map.setZoomAndCenter(
          Math.min(MAP_MAX_ZOOM, currentZoom + 2),
          [position.getLng(), position.getLat()],
          false,
          280,
        )
      })
      context.marker.setContent(content)
      context.marker.setAnchor('center')
      context.marker.setOffset(new AMap.Pixel(0, 0))
    }

    const cluster = new AMap.MarkerCluster(map, points, {
      gridSize: 60,
      maxZoom: CLUSTER_MAX_ZOOM,
      averageCenter: true,
      clusterByZoomChange: true,
      zoomOnClick: false,
      renderMarker,
      renderClusterMarker,
    })

    clusterRef.current = cluster
    fitRestaurantsOnMap(map, restaurants, containerRef.current)

    return () => {
      cluster.setMap(null)
      if (clusterRef.current === cluster) clusterRef.current = null
      restaurantElements.clear()
      restaurantMarkers.clear()
    }
  }, [currentCoordinates, mapReady, restaurants])

  useEffect(() => {
    restaurantElementsRef.current.forEach((element, restaurantId) => {
      const isSelected = restaurantId === selectedRestaurant?.id
      element.classList.toggle('is-selected', isSelected)
      restaurantMarkersRef.current.get(restaurantId)?.setTop(isSelected)
    })
  }, [selectedRestaurant?.id])

  if (!mapService.isConfigured) {
    return (
      <MapFallback
        icon={<KeyRound size={22} />}
        title="配置高德地图后开始探索"
        description="你的餐厅数据已经可以保存在本地；补充 Key 后，地图和餐厅搜索就会启用。"
      />
    )
  }

  if (error) {
    return (
      <MapFallback
        icon={<RotateCcw size={22} />}
        title="地图暂时没有加载出来"
        description={error}
      />
    )
  }

  return (
    <>
      <div className="amap-container" ref={containerRef} />
      {loading ? (
        <div className="map-loading"><LoaderCircle className="spin" size={23} /> 正在加载地图</div>
      ) : null}
      {!loading && restaurants.length === 0 ? (
        <div className="map-empty-tip">
          <MapPin size={18} />
          当前筛选下没有餐厅
        </div>
      ) : null}
    </>
  )
}

function createRestaurantImageMarkerContent(restaurant: RestaurantSummary, currentCoordinates: Coordinates | null) {
  const imageSource = restaurant.markerImageData || restaurant.merchantImageUrl
  const useImage = restaurant.markerType === 'image' && Boolean(imageSource || restaurant.markerPhotoId)
  const scoreText = restaurant.scoreOutOfTen !== null
    ? `${restaurant.scoreOutOfTen.toFixed(1)} 分`
    : '想去'
  const marker = document.createElement('button')
  marker.type = 'button'
  marker.className = [
    'private-image-marker',
    restaurant.status === 'wantToGo' ? 'is-wanted' : '',
  ].filter(Boolean).join(' ')
  marker.style.setProperty('--marker-color', scoreColor(restaurant.scoreOutOfTen))
  const distanceKilometers = currentCoordinates
    ? distanceBetweenCoordinates(currentCoordinates, restaurant)
    : null
  if (restaurant.status === 'wantToGo' && distanceKilometers !== null) {
    marker.style.setProperty('--marker-scale', wantedMarkerScale(distanceKilometers).toFixed(3))
    marker.dataset.distance = `${distanceKilometers.toFixed(distanceKilometers < 10 ? 1 : 0)} 公里`
  }
  marker.setAttribute(
    'aria-label',
    `${restaurant.name}，${scoreText}，去过 ${restaurant.visitCount} 次`,
  )

  const visual = document.createElement('span')
  visual.className = 'private-image-marker__visual'
  if (useImage) {
    visual.textContent = restaurant.markerEmoji || '🍽️'
    const image = document.createElement('img')
    image.alt = ''
    void resolvePhotoSource(imageSource, restaurant.markerPhotoId)
      .then((resolvedSource) => {
        if (!resolvedSource) return
        image.src = resolvedSource
        visual.textContent = ''
        visual.appendChild(image)
      })
      .catch(() => undefined)
  } else {
    visual.textContent = restaurant.markerEmoji || '🍽️'
  }

  const tooltip = document.createElement('span')
  tooltip.className = 'private-image-marker__tooltip'
  const tooltipName = document.createElement('strong')
  tooltipName.textContent = restaurant.name
  const tooltipMeta = document.createElement('span')
  tooltipMeta.textContent = restaurant.status === 'wantToGo' && marker.dataset.distance
    ? `${scoreText} · 距你约 ${marker.dataset.distance}`
    : `${scoreText} · 去过 ${restaurant.visitCount} 次`
  tooltip.append(tooltipName, tooltipMeta)

  marker.append(visual, tooltip)
  return marker
}

function distanceBetweenCoordinates(from: Coordinates, to: Coordinates) {
  const earthRadiusKilometers = 6371
  const latitudeDelta = toRadians(to.latitude - from.latitude)
  const longitudeDelta = toRadians(to.longitude - from.longitude)
  const fromLatitude = toRadians(from.latitude)
  const toLatitude = toRadians(to.latitude)
  const haversine = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(fromLatitude) * Math.cos(toLatitude) * Math.sin(longitudeDelta / 2) ** 2
  return earthRadiusKilometers * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
}

function toRadians(degrees: number) {
  return degrees * Math.PI / 180
}

function createClusterData(restaurants: RestaurantSummary[]) {
  const restaurantsByOriginalPosition = new Map<string, RestaurantSummary[]>()
  restaurants.forEach((restaurant) => {
    const key = coordinateKey(restaurant.longitude, restaurant.latitude)
    const matches = restaurantsByOriginalPosition.get(key) ?? []
    matches.push(restaurant)
    restaurantsByOriginalPosition.set(key, matches)
  })

  const coordinateMap = new Map<string, RestaurantSummary[]>()
  const points: AMapMarkerClusterPoint[] = []
  restaurantsByOriginalPosition.forEach((matches) => {
    matches.forEach((restaurant, index) => {
      const angle = matches.length > 1 ? (Math.PI * 2 * index) / matches.length : 0
      const spreadInMeters = matches.length > 1 ? Math.min(10, 4 + matches.length * 0.45) : 0
      const latitudeOffset = Math.sin(angle) * spreadInMeters / 111320
      const longitudeOffset = Math.cos(angle) * spreadInMeters /
        (111320 * Math.max(0.2, Math.cos(restaurant.latitude * Math.PI / 180)))
      const lnglat: [number, number] = [
        restaurant.longitude + longitudeOffset,
        restaurant.latitude + latitudeOffset,
      ]
      const key = coordinateKey(lnglat[0], lnglat[1])
      coordinateMap.set(key, [restaurant])
      points.push({ lnglat, restaurantId: restaurant.id, weight: restaurant.visitCount })
    })
  })

  return { points, coordinateMap }
}

function fitRestaurantsOnMap(
  map: AMapInstance,
  restaurants: RestaurantSummary[],
  container: HTMLElement | null,
) {
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
  const availableWidth = Math.max(280, (container?.clientWidth ?? 900) - 140)
  const availableHeight = Math.max(280, (container?.clientHeight ?? 700) - 160)
  const longitudeZoom = Math.log2((360 * availableWidth) / (longitudeSpan * 256))
  const latitudeZoom = Math.log2((170 * availableHeight) / (latitudeSpan * 256))
  const zoom = Math.max(5, Math.min(17, Math.floor(Math.min(longitudeZoom, latitudeZoom))))

  map.setZoomAndCenter(
    zoom,
    [(minimumLongitude + maximumLongitude) / 2, (minimumLatitude + maximumLatitude) / 2],
    false,
    260,
  )
}

function coordinateKey(longitude: number, latitude: number) {
  return `${longitude.toFixed(6)},${latitude.toFixed(6)}`
}

function markerLayerPriority(restaurant: RestaurantSummary) {
  const ratingPriority = Math.round((restaurant.scoreOutOfTen ?? 0) * 10)
  return ratingPriority * 10 + Math.min(restaurant.visitCount, 99)
}

function MapFallback({
  icon,
  title,
  description,
}: {
  icon: ReactNode
  title: string
  description: string
}) {
  return (
    <div className="map-fallback">
      <div className="map-grid" />
      <div className="map-placeholder">
        <span className="fallback-icon">{icon}</span>
        <strong>{title}</strong>
        <p>{description}</p>
        <code>.env</code>
      </div>
    </div>
  )
}
