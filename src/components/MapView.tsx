import { useEffect, useRef, useState, type ReactNode } from 'react'
import { KeyRound, LoaderCircle, MapPin, RotateCcw } from 'lucide-react'
import {
  isAmapConfigured,
  loadAmap,
  type AMapInstance,
  type AMapLngLat,
  type AMapMarkerInstance,
  type AMapMarkerClusterInstance,
  type AMapMarkerClusterPoint,
  type AMapMarkerClusterRenderContext,
  type AMapNamespace,
} from '../services/amap'
import { PREFERENCE_META, type RestaurantSummary } from '../types/domain'

interface MapViewProps {
  restaurants: RestaurantSummary[]
  selectedRestaurant?: RestaurantSummary
  onSelect: (restaurant: RestaurantSummary) => void
  onClearSelection: () => void
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
}: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<AMapInstance | null>(null)
  const amapRef = useRef<AMapNamespace | null>(null)
  const clusterRef = useRef<AMapMarkerClusterInstance | null>(null)
  const restaurantElementsRef = useRef(new Map<string, HTMLElement>())
  const restaurantMarkersRef = useRef(new Map<string, AMapMarkerInstance>())
  const selectedIdRef = useRef(selectedRestaurant?.id)
  const selectRef = useRef(onSelect)
  const clearSelectionRef = useRef(onClearSelection)
  const [loading, setLoading] = useState(isAmapConfigured)
  const [mapReady, setMapReady] = useState(false)
  const [error, setError] = useState('')

  selectedIdRef.current = selectedRestaurant?.id
  selectRef.current = onSelect
  clearSelectionRef.current = onClearSelection

  useEffect(() => {
    if (!isAmapConfigured || !containerRef.current) return
    let disposed = false
    let detachMapClick: (() => void) | undefined

    loadAmap()
      .then((AMap) => {
        if (disposed || !containerRef.current) return
        amapRef.current = AMap
        const map = new AMap.Map(containerRef.current, {
          zoom: 5,
          center: [120.1551, 30.2741],
          viewMode: '2D',
          mapStyle: 'amap://styles/whitesmoke',
          showLabel: true,
          features: ['bg', 'road', 'building'],
        })
        map.addControl(new AMap.ToolBar({ position: 'RT' }))
        map.addControl(new AMap.Scale())

        const handleMapClick = () => {
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
      restaurantElementsRef.current.clear()
      restaurantMarkersRef.current.clear()
      mapRef.current?.destroy()
      mapRef.current = null
      amapRef.current = null
    }
  }, [])

  useEffect(() => {
    const map = mapRef.current
    const AMap = amapRef.current
    if (!map || !AMap) return

    clusterRef.current?.setMap(null)
    clusterRef.current = null
    restaurantElementsRef.current.clear()
    restaurantMarkersRef.current.clear()
    if (restaurants.length === 0) return

    const { points, coordinateMap } = createClusterData(restaurants)

    const renderMarker = (context: AMapMarkerClusterRenderContext) => {
      const position = context.marker.getPosition()
      const restaurant = coordinateMap.get(coordinateKey(position.getLng(), position.getLat()))?.[0]
      if (!restaurant) return

      const content = createRestaurantImageMarkerContent(restaurant)
      content.classList.toggle('is-selected', restaurant.id === selectedIdRef.current)
      content.addEventListener('click', (event) => {
        event.stopPropagation()
        selectRef.current(restaurant)
      })
      restaurantElementsRef.current.set(restaurant.id, content)
      restaurantMarkersRef.current.set(restaurant.id, context.marker)
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

    cluster.on('click', (rawEvent) => {
      const clickPosition = readEventPosition(rawEvent)
      if (!clickPosition) return
      const currentZoom = map.getZoom()
      if (currentZoom < MAP_MAX_ZOOM) {
        map.setZoomAndCenter(
          Math.min(MAP_MAX_ZOOM, currentZoom + 2),
          clickPosition,
          false,
          280,
        )
      }
    })

    clusterRef.current = cluster
    fitRestaurantsOnMap(map, restaurants, containerRef.current)

    return () => {
      cluster.setMap(null)
      if (clusterRef.current === cluster) clusterRef.current = null
      restaurantElementsRef.current.clear()
      restaurantMarkersRef.current.clear()
    }
  }, [mapReady, restaurants])

  useEffect(() => {
    restaurantElementsRef.current.forEach((element, restaurantId) => {
      const isSelected = restaurantId === selectedRestaurant?.id
      element.classList.toggle('is-selected', isSelected)
      restaurantMarkersRef.current.get(restaurantId)?.setTop(isSelected)
    })
  }, [selectedRestaurant?.id])

  if (!isAmapConfigured) {
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

function createRestaurantImageMarkerContent(restaurant: RestaurantSummary) {
  const preference = PREFERENCE_META[restaurant.preferenceLevel]
  const imageSource = restaurant.markerImageData || restaurant.merchantImageUrl
  const useImage = restaurant.markerType === 'image' && imageSource
  const marker = document.createElement('button')
  marker.type = 'button'
  marker.className = [
    'private-image-marker',
    restaurant.status === 'wantToGo' ? 'is-wanted' : '',
  ].filter(Boolean).join(' ')
  marker.style.setProperty('--marker-color', preference.color)
  marker.setAttribute(
    'aria-label',
    `${restaurant.name}，${preference.label}，去过 ${restaurant.visitCount} 次`,
  )

  const visual = document.createElement('span')
  visual.className = 'private-image-marker__visual'
  if (useImage) {
    const image = document.createElement('img')
    image.src = imageSource
    image.alt = ''
    visual.appendChild(image)
  } else {
    visual.textContent = restaurant.markerEmoji || '🍽️'
  }

  const tooltip = document.createElement('span')
  tooltip.className = 'private-image-marker__tooltip'
  const tooltipName = document.createElement('strong')
  tooltipName.textContent = restaurant.name
  const tooltipMeta = document.createElement('span')
  tooltipMeta.textContent = `${preference.label} · 去过 ${restaurant.visitCount} 次`
  tooltip.append(tooltipName, tooltipMeta)

  marker.append(visual, tooltip)
  return marker
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
  const preferencePriority = {
    favorite: 4,
    like: 3,
    normal: 2,
    avoid: 1,
  }[restaurant.preferenceLevel]
  const ratingPriority = Math.round((restaurant.scoreOutOfTen ?? 0) * 10)
  return preferencePriority * 1000 + ratingPriority * 2 + Math.min(restaurant.visitCount, 99)
}

function readEventPosition(rawEvent: unknown): [number, number] | null {
  const event = rawEvent as {
    lnglat?: AMapLngLat
    target?: { getPosition?: () => AMapLngLat }
  }
  const position = event.lnglat ?? event.target?.getPosition?.()
  return position ? [position.getLng(), position.getLat()] : null
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
