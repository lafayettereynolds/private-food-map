import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { AMapNamespace } from './amap'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { UserProfile } from '../types/domain'

const sdk = vi.hoisted(() => ({ load: vi.fn(), convert: vi.fn(), getAddress: vi.fn(), getLocation: vi.fn(), search: vi.fn(), nearby: vi.fn(), gps: vi.fn() }))
vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: sdk.load } }))

const rawGps = { longitude: 120.15, latitude: 30.28 }
const providerPoint = { longitude: 120.15489, latitude: 30.2778 }
const lngLat = (point = providerPoint) => ({ getLng: () => point.longitude, getLat: () => point.latitude })
type ConversionCallback = Parameters<AMapNamespace['convertFrom']>[2]
let amap: typeof import('./amap')

beforeEach(async () => {
  vi.resetModules()
  vi.useFakeTimers()
  Object.values(sdk).forEach((mock) => mock.mockReset())
  vi.stubEnv('VITE_APP_ENV', 'development')
  vi.stubEnv('VITE_AMAP_DEV_KEY', 'isolated-sdk-test-key')
  vi.stubEnv('VITE_AMAP_DEV_SECURITY_CODE', 'isolated-sdk-test-security')
  vi.stubGlobal('window', { setTimeout, clearTimeout, location: { search: '', protocol: 'http:', hostname: 'localhost', href: 'http://localhost/' } })
  vi.stubGlobal('navigator', { geolocation: { getCurrentPosition: sdk.gps } })
  sdk.gps.mockImplementation((success) => success({ coords: { ...rawGps, accuracy: 5 }, timestamp: Date.now() }))
  sdk.convert.mockImplementation((_point, _type, callback: ConversionCallback) => callback('complete', { locations: [lngLat()] }))
  sdk.getAddress.mockImplementation((_point, callback) => callback('complete', { regeocode: { formattedAddress: '转换位置', addressComponent: { city: '杭州市', district: '测试区' } } }))
  sdk.getLocation.mockImplementation((_address, callback) => callback('complete', { geocodes: [{ formattedAddress: '手动地址', city: '杭州市', location: lngLat() }] }))
  sdk.search.mockImplementation((_keyword, callback) => callback('complete', { poiList: { pois: [] } }))
  sdk.nearby.mockImplementation((_keyword, _point, _radius, callback) => callback('complete', { poiList: { pois: [] } }))
  sdk.load.mockResolvedValue({
    convertFrom: sdk.convert,
    Geocoder: class { getAddress = sdk.getAddress; getLocation = sdk.getLocation },
    PlaceSearch: class { search = sdk.search; searchNearBy = sdk.nearby },
  })
  amap = await import('./amap')
})

afterEach(() => {
  vi.clearAllTimers()
  vi.useRealTimers()
  vi.unstubAllGlobals()
  vi.unstubAllEnvs()
})

describe('Browser GPS → AMap conversion boundary', () => {
  it('passes raw GPS to the SDK once and returns only its explicit successful coordinates', async () => {
    await expect(amap.detectCurrentCoordinates()).resolves.toEqual(providerPoint)
    expect(sdk.convert).toHaveBeenCalledWith([rawGps.longitude, rawGps.latitude], 'gps', expect.any(Function))
    expect(sdk.gps).toHaveBeenCalledWith(expect.any(Function), expect.any(Function), { enableHighAccuracy: true, timeout: 8_000, maximumAge: 0 })
    expect(sdk.convert).toHaveBeenCalledTimes(1)
  })

  it.each([
    ['error', { info: 'SERVICE_UNAVAILABLE' }],
    ['error', { locations: [lngLat()] }],
    ['complete', 'INVALID_RESPONSE'],
    ['complete', { locations: [] }],
    ['complete', {}],
  ])('rejects a %s conversion result without a raw-coordinate fallback', async (status, result) => {
    sdk.convert.mockImplementation((_point, _type, callback) => callback(status, result))
    await expect(amap.detectCurrentCoordinates()).rejects.toThrow('当前位置转换失败，请重试定位，或使用城市/地址搜索。')
  })

  it.each([
    { longitude: NaN, latitude: 30 },
    { longitude: 120, latitude: Infinity },
    { longitude: 181, latitude: 30 },
    { longitude: 120, latitude: -91 },
  ])('rejects malformed converted coordinates %j', async (point) => {
    sdk.convert.mockImplementation((_point, _type, callback: ConversionCallback) => callback('complete', { locations: [lngLat(point)] }))
    await expect(amap.detectCurrentCoordinates()).rejects.toThrow('当前位置转换失败')
  })

  it('accepts an explicitly converted unchanged point, including valid zero coordinates', async () => {
    sdk.convert.mockImplementation((_point, _type, callback: ConversionCallback) => callback('complete', { locations: [lngLat(rawGps)] }))
    await expect(amap.detectCurrentCoordinates()).resolves.toEqual(rawGps)
    sdk.convert.mockImplementation((_point, _type, callback: ConversionCallback) => callback('complete', { locations: [lngLat({ longitude: 0, latitude: 0 })] }))
    await expect(amap.detectCurrentCoordinates()).resolves.toEqual({ longitude: 0, latitude: 0 })
  })

  it('normalizes synchronous SDK failures and malformed coordinate-accessor exceptions', async () => {
    sdk.convert.mockImplementationOnce(() => { throw new Error('SDK stopped') })
    await expect(amap.detectCurrentCoordinates()).rejects.toThrow('当前位置转换失败')
    sdk.convert.mockImplementationOnce((_point, _type, callback: ConversionCallback) => callback('complete', { locations: [{ getLng: () => { throw new Error('Malformed location') }, getLat: () => 30 }] }))
    await expect(amap.detectCurrentCoordinates()).rejects.toThrow('当前位置转换失败')
  })

  it('rejects at the conversion deadline and ignores a late callback; a new attempt can succeed', async () => {
    let late!: ConversionCallback
    sdk.convert.mockImplementationOnce((_point, _type, callback: ConversionCallback) => { late = callback })
    const accepted = vi.fn()
    const pending = amap.detectCurrentCoordinates()
    const failure = expect(pending).rejects.toThrow('当前位置转换超时，请重试定位，或使用城市/地址搜索。')
    void pending.then(accepted, () => undefined)
    await vi.advanceTimersByTimeAsync(2499)
    expect(accepted).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1)
    await failure
    await expect(amap.detectCurrentCoordinates()).resolves.toEqual(providerPoint)
    late('complete', { locations: [lngLat({ longitude: 1, latitude: 2 })] })
    await Promise.resolve()
    expect(accepted).not.toHaveBeenCalled()
    expect(sdk.gps).toHaveBeenCalledTimes(2)
    expect(sdk.convert).toHaveBeenCalledTimes(2)
  })

  it('never reverse-geocodes raw GPS on failure and geocodes converted coordinates after retry', async () => {
    sdk.convert.mockImplementationOnce((_point, _type, callback: ConversionCallback) => callback('error', {}))
    await expect(amap.detectCurrentLocation()).rejects.toThrow('当前位置转换失败')
    expect(sdk.getAddress).not.toHaveBeenCalled()
    await expect(amap.detectCurrentCity()).resolves.toBe('杭州市')
    expect(sdk.getAddress).toHaveBeenCalledWith([providerPoint.longitude, providerPoint.latitude], expect.any(Function))
  })

  it('leaves city/name search and manual address resolution independent of a failed GPS conversion', async () => {
    sdk.convert.mockImplementation((_point, _type, callback: ConversionCallback) => callback('error', {}))
    await expect(amap.detectCurrentCoordinates()).rejects.toThrow('当前位置转换失败')
    await expect(amap.searchRestaurantPois('测试餐厅', '杭州市')).resolves.toEqual([])
    await expect(amap.resolveAddressLocation('手动地址', '杭州市')).resolves.toMatchObject(providerPoint)
    expect(sdk.search).toHaveBeenCalledWith('测试餐厅', expect.any(Function))
    expect(sdk.getLocation).toHaveBeenCalledWith('手动地址', expect.any(Function))
    expect(sdk.gps).toHaveBeenCalledTimes(1)
    expect(sdk.nearby).not.toHaveBeenCalled()
  })

  it('propagates through real MapService/Browser adapter without querying Nearby or displaying a false empty success', async () => {
    sdk.convert.mockImplementationOnce((_point, _type, callback: ConversionCallback) => callback('error', {}))
    const { TasteMapBrowserAdapter } = await import('../platform/TasteMapBrowserAdapter')
    const profile: TasteMapProfileDashboardViewModel = { user: { id: 'isolated-owner', nickname: '测试', city: '' } as UserProfile, restaurants: [], visits: [], restaurantImages: {}, followerCount: 0, followingCount: 0 }
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
    await expect(adapter.acquisition.nearby()).rejects.toThrow('当前位置转换失败')
    expect(sdk.nearby).not.toHaveBeenCalled()
    expect(sdk.getAddress).not.toHaveBeenCalled()
    const retried = await adapter.acquisition.nearby()
    expect(retried.candidates).toEqual([])
    expect(retried.message).toBe('3 公里内没有找到餐厅。')
    expect(sdk.nearby).toHaveBeenCalledTimes(3)
    expect(sdk.nearby.mock.calls.every((call) => call[1][0] === providerPoint.longitude && call[1][1] === providerPoint.latitude)).toBe(true)
  })
})
