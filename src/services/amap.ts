import AMapLoader from '@amap/amap-jsapi-loader'
import { APP_ENVIRONMENT } from '../config/appEnvironment'
import type { Coordinates, PoiSearchResult } from '../types/domain'
import { normalizeRestaurantKeyword } from './restaurantSearch'

export { normalizeRestaurantKeyword } from './restaurantSearch'

export interface AMapLngLat {
  getLng(): number
  getLat(): number
}

interface AMapPoi {
  id?: string
  name?: string
  address?: string | string[]
  cityname?: string | string[]
  adname?: string | string[]
  location?: AMapLngLat
  photos?: { url?: string }[]
}

interface PlaceSearchResult {
  poiList?: { pois?: AMapPoi[] }
  info?: string
}

interface ReGeocodeResult {
  info?: string
  regeocode?: {
    formattedAddress?: string
    addressComponent?: {
      city?: string | string[]
      province?: string | string[]
      district?: string | string[]
    }
  }
}

interface GeocodeResult {
  info?: string
  geocodes?: Array<{
    formattedAddress?: string
    city?: string | string[]
    province?: string | string[]
    district?: string | string[]
    location?: AMapLngLat
  }>
}

interface AMapConvertResult {
  info?: string
  locations?: AMapLngLat[]
}

export interface AMapInstance {
  destroy(): void
  addControl(control: unknown): void
  setFitView(overlays?: unknown[], immediately?: boolean, avoid?: number[]): void
  getZoom(): number
  setZoomAndCenter(
    zoom: number,
    center: [number, number] | AMapLngLat,
    immediately?: boolean,
    duration?: number,
  ): void
  on(event: 'click', handler: (event?: unknown) => void): void
  off(event: 'click', handler: (event?: unknown) => void): void
}

export interface AMapMarkerInstance {
  on(event: 'click', handler: (event?: unknown) => void): void
  setMap(map: AMapInstance | null): void
  getPosition(): AMapLngLat
  setContent(content: HTMLElement | string): void
  setOffset(offset: unknown): void
  setAnchor(anchor: string): void
  setzIndex(zIndex: number): void
  setTop(isTop: boolean): void
}

export interface AMapMarkerClusterPoint {
  lnglat: [number, number]
  restaurantId: string
  weight?: number
}

export interface AMapMarkerClusterRenderContext {
  count: number
  marker: AMapMarkerInstance
}

export interface AMapMarkerClusterInstance {
  setMap(map: AMapInstance | null): void
  setData(points: AMapMarkerClusterPoint[]): void
  on(event: 'click', handler: (event: unknown) => void): void
}

export interface AMapNamespace {
  Map: new (
    container: HTMLElement,
    options: Record<string, unknown>,
  ) => AMapInstance
  Marker: new (options: Record<string, unknown>) => AMapMarkerInstance
  MarkerCluster: new (
    map: AMapInstance,
    points: AMapMarkerClusterPoint[],
    options: {
      gridSize?: number
      maxZoom?: number
      averageCenter?: boolean
      clusterByZoomChange?: boolean
      renderClusterMarker?: (context: AMapMarkerClusterRenderContext) => void
      renderMarker?: (context: AMapMarkerClusterRenderContext) => void
      [key: string]: unknown
    },
  ) => AMapMarkerClusterInstance
  Pixel: new (x: number, y: number) => unknown
  ToolBar: new (options?: Record<string, unknown>) => unknown
  Scale: new (options?: Record<string, unknown>) => unknown
  PlaceSearch: new (options: Record<string, unknown>) => {
    search(
      keyword: string,
      callback: (status: string, result: PlaceSearchResult | string) => void,
    ): void
    searchNearBy(
      keyword: string,
      center: [number, number],
      radius: number,
      callback: (status: string, result: PlaceSearchResult | string) => void,
    ): void
  }
  Geocoder: new (options?: Record<string, unknown>) => {
    getAddress(
      location: [number, number],
      callback: (status: string, result: ReGeocodeResult | string) => void,
    ): void
    getLocation(
      address: string,
      callback: (status: string, result: GeocodeResult | string) => void,
    ): void
  }
  convertFrom(
    location: [number, number],
    type: 'gps',
    callback: (status: string, result: AMapConvertResult | string) => void,
  ): void
}

declare global {
  interface Window {
    _AMapSecurityConfig?: { securityJsCode: string }
  }
}

const environmentAmapKey = APP_ENVIRONMENT === 'production'
  ? import.meta.env.VITE_AMAP_PROD_KEY
  : import.meta.env.VITE_AMAP_DEV_KEY
const environmentSecurityCode = APP_ENVIRONMENT === 'production'
  ? import.meta.env.VITE_AMAP_PROD_SECURITY_CODE || import.meta.env.VITE_AMAP_PROD_SECURITY_KEY
  : import.meta.env.VITE_AMAP_DEV_SECURITY_CODE || import.meta.env.VITE_AMAP_DEV_SECURITY_KEY
const amapKey = (environmentAmapKey || import.meta.env.VITE_AMAP_KEY)?.trim()
const securityCode = (
  environmentSecurityCode
  || import.meta.env.VITE_AMAP_SECURITY_CODE
  || import.meta.env.VITE_AMAP_SECURITY_KEY
)?.trim()

export const isAmapConfigured = Boolean(amapKey && securityCode)

let amapPromise: Promise<AMapNamespace> | null = null

export function loadAmap(): Promise<AMapNamespace> {
  if (!isAmapConfigured || !amapKey || !securityCode) {
    return Promise.reject(new Error('请先配置高德地图 API Key 和安全密钥。'))
  }

  if (!amapPromise) {
    window._AMapSecurityConfig = { securityJsCode: securityCode }
    amapPromise = AMapLoader.load({
      key: amapKey,
      version: '2.0',
      plugins: [
        'AMap.PlaceSearch',
        'AMap.ToolBar',
        'AMap.Scale',
        'AMap.Geocoder',
        'AMap.MarkerCluster',
      ],
    }) as Promise<AMapNamespace>
  }

  return amapPromise
}

export interface ResolvedLocation {
  longitude: number
  latitude: number
  address: string
  city: string
  district: string
}

export async function detectCurrentCoordinates(): Promise<Coordinates> {
  const [AMap, gps] = await Promise.all([
    withTimeout(loadAmap(), 7_000, '地图服务加载超时，请检查网络后重试。'),
    readBrowserGps(),
  ])
  return withTimeout(new Promise<Coordinates>((resolve) => {
    AMap.convertFrom([gps.longitude, gps.latitude], 'gps', (status, result) => {
      const converted = status === 'complete' && typeof result !== 'string' ? result.locations?.[0] : null
      resolve(converted
        ? { longitude: converted.getLng(), latitude: converted.getLat() }
        : { longitude: gps.longitude, latitude: gps.latitude })
    })
  }), 2_500, '坐标转换超时。').catch(() => ({ longitude: gps.longitude, latitude: gps.latitude }))
}

function readBrowserGps(): Promise<Coordinates> {
  if (!navigator.geolocation) return Promise.reject(new Error('当前浏览器不支持定位，请使用地址搜索。'))
  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      (position) => {
        if (position.coords.accuracy > 1_000) {
          reject(new Error('当前只能获得粗略位置，请在系统设置中开启精确定位。'))
          return
        }
        resolve({ longitude: position.coords.longitude, latitude: position.coords.latitude })
      },
      (error) => {
        const message = error.code === error.PERMISSION_DENIED
          ? '定位权限未开启，请允许 Taste Map 使用精确位置后重试。'
          : error.code === error.TIMEOUT
            ? '定位超时，请确认 GPS 已开启后重试。'
            : '无法获取当前位置，请检查设备定位服务。'
        reject(new Error(message))
      },
      { enableHighAccuracy: true, timeout: 8_000, maximumAge: 0 },
    )
  })
}

export async function resolveCoordinatesLocation(coordinates: Coordinates): Promise<ResolvedLocation> {
  const AMap = await withTimeout(loadAmap(), 8_000, '地图服务加载超时，请检查网络后重试。')

  return withTimeout(new Promise((resolve, reject) => {
    const geocoder = new AMap.Geocoder({ radius: 1000 })
    geocoder.getAddress(
      [coordinates.longitude, coordinates.latitude],
      (status, result) => {
        if (status !== 'complete' || typeof result === 'string') {
          reject(new Error(typeof result === 'string' ? result : result.info || '定位城市解析失败。'))
          return
        }
        const component = result.regeocode?.addressComponent
        const city = textValue(component?.city) || textValue(component?.province)
        if (!city) {
          reject(new Error('没有识别到当前城市。'))
          return
        }
        resolve({
          longitude: coordinates.longitude,
          latitude: coordinates.latitude,
          address: result.regeocode?.formattedAddress || '当前位置',
          city,
          district: textValue(component?.district),
        })
      },
    )
  }), 6_000, '位置解析超时，请稍后重试。')
}

export async function detectCurrentLocation(): Promise<ResolvedLocation> {
  return resolveCoordinatesLocation(await detectCurrentCoordinates())
}

function withTimeout<Value>(promise: Promise<Value>, timeoutMs: number, message: string) {
  return new Promise<Value>((resolve, reject) => {
    let settled = false
    const timeout = window.setTimeout(() => {
      if (settled) return
      settled = true
      reject(new Error(message))
    }, timeoutMs)
    promise.then(
      (value) => {
        if (settled) return
        settled = true
        window.clearTimeout(timeout)
        resolve(value)
      },
      (error) => {
        if (settled) return
        settled = true
        window.clearTimeout(timeout)
        reject(error)
      },
    )
  })
}

export async function detectCurrentCity(): Promise<string> {
  return (await detectCurrentLocation()).city
}

export async function resolveAddressLocation(
  address: string,
  city?: string,
): Promise<ResolvedLocation> {
  const AMap = await loadAmap()
  return new Promise((resolve, reject) => {
    const geocoder = new AMap.Geocoder({ city: city?.trim() || '全国' })
    geocoder.getLocation(address.trim(), (status, result) => {
      if (status !== 'complete' || typeof result === 'string') {
        reject(new Error(typeof result === 'string' ? result : result.info || '地址定位失败。'))
        return
      }
      const match = result.geocodes?.[0]
      if (!match?.location) {
        reject(new Error('没有找到这个地址，请补充附近道路或商场名称。'))
        return
      }
      resolve({
        longitude: match.location.getLng(),
        latitude: match.location.getLat(),
        address: match.formattedAddress || address.trim(),
        city: textValue(match.city) || textValue(match.province) || city?.trim() || '未知城市',
        district: textValue(match.district),
      })
    })
  })
}

function textValue(value: string | string[] | undefined) {
  if (Array.isArray(value)) return value.join('')
  return value ?? ''
}

export async function searchRestaurantPois(
  keyword: string,
  city?: string,
  options: { center?: Coordinates; timeoutMs?: number; radiusMeters?: number; categoryOnly?: boolean } = {},
): Promise<PoiSearchResult[]> {
  const normalizedKeyword = normalizeRestaurantKeyword(keyword)
  if (!normalizedKeyword && !options.categoryOnly) return []
  const AMap = await loadAmap()

  return new Promise((resolve, reject) => {
    let settled = false
    const finish = (callback: () => void) => {
      if (settled) return
      settled = true
      window.clearTimeout(timeout)
      callback()
    }
    const timeout = window.setTimeout(() => {
      finish(() => reject(new Error('搜索超时，请检查网络后重试。')))
    }, options.timeoutMs ?? 8_000)
    const search = new AMap.PlaceSearch({
      city: city?.trim() || '全国',
      citylimit: Boolean(city?.trim()),
      type: '050000',
      pageSize: 15,
      pageIndex: 1,
      extensions: 'all',
    })

    const handleResult = (status: string, result: PlaceSearchResult | string) => {
      if (status === 'no_data') {
        finish(() => resolve([]))
        return
      }
      if (status !== 'complete' || typeof result === 'string') {
        const message =
          typeof result === 'string' ? result : result.info || '搜索失败，请稍后重试。'
        finish(() => reject(new Error(message)))
        return
      }

      const pois = result.poiList?.pois ?? []
      finish(() => resolve(
        pois.flatMap((poi) => {
          if (!poi.id || !poi.name || !poi.location) return []
          return [
            {
              amapPoiId: poi.id,
              name: poi.name,
              address: textValue(poi.address) || '暂无详细地址',
              city: textValue(poi.cityname) || city?.trim() || '未知城市',
              district: textValue(poi.adname),
              longitude: poi.location.getLng(),
              latitude: poi.location.getLat(),
              merchantImageUrl: poi.photos?.find((photo) => photo.url)?.url ?? null,
            },
          ]
        }),
      ))
    }

    if (options.center) {
      search.searchNearBy(
        options.categoryOnly ? '' : normalizedKeyword,
        [options.center.longitude, options.center.latitude],
        options.radiusMeters ?? 8_000,
        handleResult,
      )
    } else {
      search.search(normalizedKeyword, handleResult)
    }
  })
}

export function searchNearbyRestaurantPois(
  center: Coordinates,
  city?: string,
  options: { timeoutMs?: number; radiusMeters?: number } = {},
) {
  return searchRestaurantPois('', city, { center, categoryOnly: true, radiusMeters: options.radiusMeters ?? 2_000, timeoutMs: options.timeoutMs })
}
