import { useEffect, useMemo, useState } from 'react'
import { ArrowLeft, Database, UserRound } from 'lucide-react'
import { ProfilePage } from '../components/ProfilePage'
import { RestaurantPreviewCard } from '../components/RestaurantPreviewCard'
import { resolveTasteMapPlatform } from '../platform/tasteMapPlatformResolver'
import type { TasteMapPlatform, TasteMapProfileSnapshot, TasteMapRuntimeInfo } from '../platform/TasteMapPlatform'
import type { RestaurantSummary } from '../types/domain'
import './hybridPOC.css'

type Route = { page: 'profile' } | { page: 'restaurant'; id: string }

function routeFromHash(): Route {
  const match = window.location.hash.match(/^#\/hybrid-poc\/restaurant\/([^/?#]+)$/)
  return match ? { page: 'restaurant', id: decodeURIComponent(match[1]) } : { page: 'profile' }
}

export function HybridPOCApp({ platform: injectedPlatform }: { platform?: TasteMapPlatform }) {
  const platform = useMemo(() => injectedPlatform ?? resolveTasteMapPlatform(), [injectedPlatform])
  const [route, setRoute] = useState<Route>(routeFromHash)
  const [profile, setProfile] = useState<TasteMapProfileSnapshot | null>(null)
  const [restaurant, setRestaurant] = useState<RestaurantSummary | null>(null)
  const [runtime, setRuntime] = useState<TasteMapRuntimeInfo | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!window.location.hash) window.location.replace(`${window.location.pathname}${window.location.search}#/hybrid-poc/profile`)
    const update = () => setRoute(routeFromHash())
    window.addEventListener('hashchange', update)
    return () => window.removeEventListener('hashchange', update)
  }, [])

  useEffect(() => {
    let active = true
    Promise.all([platform.runtime.info(), platform.profile.getCurrent()])
      .then(([nextRuntime, nextProfile]) => {
        if (!active) return
        setRuntime(nextRuntime)
        setProfile(nextProfile)
      })
      .catch((reason: unknown) => active && setError(reason instanceof Error ? reason.message : 'POC 数据加载失败。'))
    return () => { active = false }
  }, [platform])

  useEffect(() => {
    if (route.page !== 'restaurant') { setRestaurant(null); return }
    let active = true
    platform.restaurant.get(route.id)
      .then((value) => active && setRestaurant(value))
      .catch((reason: unknown) => active && setError(reason instanceof Error ? reason.message : '餐厅读取失败。'))
    return () => { active = false }
  }, [platform, route])

  const openRestaurant = async (selected: RestaurantSummary) => {
    await platform.haptics.selection()
    window.location.hash = `/hybrid-poc/restaurant/${encodeURIComponent(selected.id)}`
  }

  if (error) return <main className="hybrid-poc-state"><strong>无法打开 Taste Map POC</strong><p>{error}</p></main>
  if (!profile || !runtime) return <main className="hybrid-poc-state"><span className="hybrid-poc-loader" /><strong>正在读取 Taste Map 数据…</strong></main>

  return <div className="hybrid-poc-root" data-adapter={platform.kind} data-bridge-version={runtime.bridgeVersion}>
    {route.page === 'restaurant'
      ? restaurant
        ? <main className="hybrid-poc-detail"><button className="hybrid-poc-back" onClick={() => window.history.back()} type="button"><ArrowLeft size={18} />返回我的页面</button><RestaurantPreviewCard additionalUserPhotos={restaurant.visits.flatMap((visit) => visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index] })))} historyRestaurants={profile.restaurants} isInRoulette={false} onAddToRoulette={() => undefined} onAddVisit={() => undefined} onClose={() => window.history.back()} onDelete={() => undefined} onEdit={() => undefined} onEditVisit={() => undefined} onSaveRecommendation={() => undefined} readOnly remoteStatsEnabled={false} restaurant={restaurant} /></main>
        : <main className="hybrid-poc-state"><span className="hybrid-poc-loader" /><strong>正在从 SwiftData 读取餐厅…</strong></main>
      : <ProfilePage connections={<p>POC 仅验证现有 Profile 主体。</p>} followerConnections={<p>已由 Profile Bridge 提供计数。</p>} followerCount={profile.followerCount} followingConnections={<p>已由 Profile Bridge 提供计数。</p>} followingCount={profile.followingCount} onOpenRoulette={() => undefined} onOpenSettings={() => undefined} onSave={async () => undefined} onSelectRestaurant={(selected) => void openRestaurant(selected)} restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />}
    <footer className="hybrid-poc-proof" aria-label="POC 数据来源"><Database size={13} /><span>{runtime.dataSource === 'native-swiftdata-in-memory' ? 'Native SwiftData · 隔离内存库' : 'Browser · 确定性同源 fixture'}</span><UserRound size={13} /><span>{profile.user.nickname}</span></footer>
  </div>
}
