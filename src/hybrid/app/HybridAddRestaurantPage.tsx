import { useEffect, useMemo, useState } from 'react'
import { ChevronRight, MapPin, Search } from 'lucide-react'
import type { TasteMapLocationDTO, TasteMapPlatform, TasteMapRestaurantDetailViewModel } from '../../platform/TasteMapPlatform'
import { HybridRestaurantImage } from '../../components/TasteMapHybridShared'
import { TasteMapRestaurantAcquisitionScaffold } from '../../components/TasteMapRestaurantAcquisitionShared'

export function HybridAddRestaurantPage({ platform, onOpenRestaurant }: { platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void }) {
  const [query, setQuery] = useState('')
  const [location, setLocation] = useState<TasteMapLocationDTO | null>(null)
  const [locationState, setLocationState] = useState<'idle' | 'loading' | 'ready' | 'error'>('loading')
  const [items, setItems] = useState<TasteMapRestaurantDetailViewModel[]>([])

  useEffect(() => { void platform.restaurant.list({ limit: 200 }).then(setItems) }, [platform])
  useEffect(() => {
    if (locationState !== 'loading') return
    void platform.location.current().then((value) => { setLocation(value); setLocationState('ready') }).catch(() => setLocationState('error'))
  }, [locationState, platform])

  const searchResults = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase('zh-CN')
    if (!normalized) return []
    return items.filter(({ restaurant }) => [restaurant.name, restaurant.address, restaurant.city, ...restaurant.tags].join('\n').toLocaleLowerCase('zh-CN').includes(normalized)).slice(0, 20)
  }, [items, query])
  const nearby = useMemo(() => location ? items.map((item) => ({ ...item, distance: distanceMeters(location, item.restaurant) })).filter((item) => item.distance <= 3_000).sort((a, b) => a.distance - b.distance).slice(0, 12) : [], [items, location])

  const openNativeAcquisition = () => void platform.navigation.openNative({ route: 'acquisitionNative' })

  return <main className="tm-hybrid-page tm-hybrid-add">
    <TasteMapRestaurantAcquisitionScaffold
      pageHeader
      onOpenManual={openNativeAcquisition}
      onOpenShare={openNativeAcquisition}
      search={<>
        <div className="tm-hybrid-add-search-row">
          <label className="tm-hybrid-add-search"><Search aria-hidden="true" size={17} /><input autoComplete="off" onChange={(event) => setQuery(event.target.value)} placeholder="例如：寿喜烧、南京西路" value={query} /></label>
          <button onClick={openNativeAcquisition} type="button">搜索</button>
        </div>
        {query.trim() ? searchResults.length ? <RestaurantResults items={searchResults} onOpenRestaurant={onOpenRestaurant} /> : <p className="tm-acquisition__inline-state">没有已记录的匹配项；可继续用正式地图服务搜索新商户。</p> : null}
      </>}
      nearby={<>
        <div className={`tm-hybrid-location-status is-${locationState}`}><MapPin aria-hidden="true" size={16} /><span><strong>{locationState === 'ready' ? '当前位置已更新' : locationState === 'loading' ? '正在取得新鲜位置' : '暂时无法取得精确位置'}</strong><small>{location ? `精度约 ${Math.round(location.horizontalAccuracy)} 米 · ${location.accuracyMode === 'reduced' ? '约略位置' : '精确位置'}` : locationState === 'error' ? '搜索和手动添加仍可使用，不采用城市中心兜底' : '只接受足够新鲜、精度合理的 CLLocation'}</small></span>{locationState === 'error' ? <button onClick={() => { setLocation(null); setLocationState('loading') }} type="button">重试</button> : null}</div>
        {nearby.length ? <div className="tm-hybrid-nearby-list">{nearby.map((item) => <button key={item.restaurant.id} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantImage image={item.image} name={item.restaurant.name} /><span><strong>{item.restaurant.name}</strong><small>{item.restaurant.address}</small><em>{item.distance < 1_000 ? `${Math.round(item.distance)} 米` : `${(item.distance / 1_000).toFixed(1)} 公里`}</em></span><ChevronRight aria-hidden="true" size={17} /></button>)}</div> : locationState === 'ready' ? <p className="tm-acquisition__inline-state">3 公里内暂无已记录餐厅，可用正式 Nearby provider 继续查找。</p> : null}
      </>}
    />
  </main>
}

function RestaurantResults({ items, onOpenRestaurant }: { items: TasteMapRestaurantDetailViewModel[]; onOpenRestaurant: (id: string) => void }) {
  return <div className="tm-hybrid-search-results">{items.map((item) => <button key={item.restaurant.id} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantImage image={item.image} name={item.restaurant.name} /><span><strong>{item.restaurant.name}</strong><small>{item.restaurant.city} · {item.restaurant.address}</small><em>{item.restaurant.status === 'visited' ? `去过 ${item.restaurant.visitCount} 次` : '想吃'}</em></span></button>)}</div>
}

function distanceMeters(origin: { latitude: number; longitude: number }, target: { latitude: number; longitude: number }) {
  const radians = (value: number) => value * Math.PI / 180
  const latitudeDelta = radians(target.latitude - origin.latitude)
  const longitudeDelta = radians(target.longitude - origin.longitude)
  const a = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(radians(origin.latitude)) * Math.cos(radians(target.latitude)) * Math.sin(longitudeDelta / 2) ** 2
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}
