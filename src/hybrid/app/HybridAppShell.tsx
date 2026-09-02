import { useEffect, useMemo, useRef, useState } from 'react'
import { ArrowLeft, CloudOff, Globe2, Map as MapIcon, Plus, RotateCcw, UserRound } from 'lucide-react'
import { MyMapBrowsePage } from '../../components/MyMapBrowsePage'
import { ProfilePage } from '../../components/ProfilePage'
import { RestaurantPreviewCard } from '../../components/RestaurantPreviewCard'
import { resolveTasteMapPlatform } from '../../platform/tasteMapPlatformResolver'
import { TasteMapPlatformError, type TasteMapHybridRoute as PlatformRoute, type TasteMapPlatform, type TasteMapProfileDashboardViewModel, type TasteMapRestaurantDetailViewModel, type TasteMapRuntimeInfo } from '../../platform/TasteMapPlatform'
import { routeFromLocation, routeHash, surfaceStatus, type HybridRoute } from '../routes/HybridRouteRegistry'
import './hybridShell.css'

type BootstrapState =
  | { state: 'loading' }
  | { state: 'ready'; runtime: TasteMapRuntimeInfo; profile: TasteMapProfileDashboardViewModel }
  | { state: 'authRequired'; message: string }
  | { state: 'fatal'; message: string; code: string }

export function HybridAppShell({ platform: injectedPlatform }: { platform?: TasteMapPlatform }) {
  const platform = useMemo(() => injectedPlatform ?? resolveTasteMapPlatform(), [injectedPlatform])
  const [route, setRoute] = useState<HybridRoute>(initialRoute)
  const [bootstrap, setBootstrap] = useState<BootstrapState>({ state: 'loading' })
  const [restaurant, setRestaurant] = useState<TasteMapRestaurantDetailViewModel | null>(null)
  const [routeError, setRouteError] = useState<string | null>(null)
  const [online, setOnline] = useState(() => navigator.onLine)
  const [generation, setGeneration] = useState(0)
  const [mapWasActivated, setMapWasActivated] = useState(() => initialRoute().surface === 'map')
  const didSynchronizeInitialRoute = useRef(false)

  useEffect(() => {
    let active = true
    let remove: (() => Promise<void>) | undefined
    platform.events.subscribe((event) => {
      if (!active) return
      if (event.name === 'auth.changed') {
        setRestaurant(null)
        setGeneration((value) => value + 1)
      }
      if (event.name === 'navigation.route' || event.name === 'deepLink.received') {
        const next = platformRouteToHybrid(event.payload.route)
        if (next) updateLocation(next)
      }
    }).then((subscription) => { remove = () => subscription.remove() }).catch(() => undefined)
    return () => {
      active = false
      void remove?.()
    }
  }, [platform])

  useEffect(() => {
    if (!window.location.hash) window.history.replaceState(null, '', routeHash(initialRoute()))
    const updateRoute = () => setRoute(routeFromLocation(window.location))
    const updateOnline = () => setOnline(navigator.onLine)
    window.addEventListener('hashchange', updateRoute)
    window.addEventListener('online', updateOnline)
    window.addEventListener('offline', updateOnline)
    return () => {
      window.removeEventListener('hashchange', updateRoute)
      window.removeEventListener('online', updateOnline)
      window.removeEventListener('offline', updateOnline)
    }
  }, [])

  useEffect(() => {
    if (didSynchronizeInitialRoute.current || platform.kind !== 'native') return
    didSynchronizeInitialRoute.current = true
    if (route.surface === 'map') void platform.navigation.openHybrid({ surface: 'map' })
  }, [platform, route.surface])

  useEffect(() => {
    let active = true
    setBootstrap({ state: 'loading' })
    Promise.all([platform.runtime.info(), platform.auth.sessionStatus()])
      .then(async ([runtime, session]) => {
        if (!active) return
        if (session.state !== 'authenticated') {
          setBootstrap({ state: 'authRequired', message: '请先在 Taste Map 完成登录。' })
          return
        }
        const profile = await platform.profile.getCurrent()
        if (!active) return
        setBootstrap({ state: 'ready', runtime, profile })
      })
      .catch((reason: unknown) => {
        if (!active) return
        const error = normalizeError(reason)
        setBootstrap(error.code === 'auth_required'
          ? { state: 'authRequired', message: error.message }
          : { state: 'fatal', message: error.message, code: error.code })
      })
    return () => { active = false }
  }, [generation, platform])

  useEffect(() => {
    setRouteError(null)
    if (route.surface !== 'restaurant') {
      setRestaurant(null)
      return
    }
    let active = true
    platform.restaurant.get(route.id)
      .then((value) => { if (active) setRestaurant(value) })
      .catch((reason: unknown) => { if (active) setRouteError(normalizeError(reason).message) })
    return () => { active = false }
  }, [platform, route])

  useEffect(() => {
    if (route.surface === 'map') setMapWasActivated(true)
  }, [route.surface])

  const navigate = async (nextRoute: HybridRoute) => {
    if (platform.kind === 'native') await platform.navigation.openHybrid(hybridRouteToPlatform(nextRoute))
    updateLocation(nextRoute)
  }

  const navigateBack = async () => {
    if (platform.kind === 'native') {
      const state = await platform.navigation.back()
      const next = platformRouteToHybrid(state.route)
      if (next) updateLocation(next)
      return
    }
    window.history.back()
  }

  if (bootstrap.state === 'loading') return <ShellState kind="loading" message="正在读取 Taste Map 本地数据…" />
  if (bootstrap.state === 'authRequired') return <ShellState action={async () => {
    const result = await platform.auth.signInWithApple()
    if (result.state === 'authenticated') setGeneration((value) => value + 1)
  }} kind="auth" message={bootstrap.message} />
  if (bootstrap.state === 'fatal') {
    return <ShellState action={() => setGeneration((value) => value + 1)} code={bootstrap.code} kind="fatal" message={bootstrap.message} />
  }

  const { profile, runtime } = bootstrap
  return <div className="tm-hybrid-shell" data-adapter={platform.kind} data-bridge-version={runtime.bridgeVersion} data-route={route.surface}>
    {!online ? <div className="tm-hybrid-shell__offline" role="status"><CloudOff aria-hidden="true" size={15} />离线模式 · 正在使用本地数据</div> : null}
    {mapWasActivated ? <MyMapBrowsePage
      active={route.surface === 'map'}
      onAddRestaurant={() => void openNativeRoute(platform, 'add')}
      onOpenRestaurant={(restaurantID) => void navigate({ surface: 'restaurant', id: restaurantID })}
      platform={platform}
      profile={profile}
    /> : null}
    {route.surface === 'map' ? null : route.surface === 'profile'
      ? <ProfilePage
          connections={<p>用户搜索仍由原生主路径承载。</p>}
          followerConnections={<p>关注者列表仍由原生主路径承载。</p>}
          followerCount={profile.followerCount}
          followingConnections={<p>关注列表仍由原生主路径承载。</p>}
          followingCount={profile.followingCount}
          onOpenRoulette={() => void openNativeRoute(platform, 'roulette')}
          onOpenSettings={() => void openNativeRoute(platform, 'settings')}
          onSave={async () => undefined}
          onSelectRestaurant={(selected) => {
            void platform.haptics.selection()
            void navigate({ surface: 'restaurant', id: selected.id })
          }}
          restaurants={profile.restaurants}
          user={profile.user}
          visits={profile.visits}
        />
      : route.surface === 'restaurant'
        ? restaurant
          ? <main className="tm-hybrid-detail">
              <button aria-label="返回上一页" className="tm-hybrid-detail__back" onClick={() => void navigateBack()} type="button"><ArrowLeft aria-hidden="true" size={18} />返回</button>
              <RestaurantPreviewCard
                additionalUserPhotos={restaurant.restaurant.visits.flatMap((visit) => visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index] })))}
                historyRestaurants={profile.restaurants}
                isInRoulette={false}
                onAddToRoulette={() => void openNativeRoute(platform, 'roulette')}
                onAddVisit={() => void openNativeRoute(platform, 'visit', restaurant.restaurant.id)}
                onClose={() => void navigateBack()}
                onDelete={() => undefined}
                onEdit={() => undefined}
                onEditVisit={() => undefined}
                onSaveRecommendation={() => undefined}
                readOnly
                remoteStatsEnabled={false}
                restaurant={restaurant.restaurant}
              />
            </main>
          : <ShellState kind="loading" message={routeError ?? '正在读取餐厅详情…'} />
        : <NativePrimaryHandoff route={route} onBack={() => navigate({ surface: 'profile' })} />}
    <nav aria-label="主要功能" className="tm-hybrid-bottom-nav">
      <button aria-current={route.surface === 'map' ? 'page' : undefined} className={route.surface === 'map' ? 'is-active' : ''} onClick={() => void navigate({ surface: 'map' })} type="button"><MapIcon size={19} /><span>地图</span></button>
      <button className={route.surface === 'discovery' ? 'is-active' : ''} onClick={() => void openNativeRoute(platform, 'discovery')} type="button"><Globe2 size={19} /><span>发现</span></button>
      <button aria-label="添加餐厅" className="is-add" onClick={() => void openNativeRoute(platform, 'add')} type="button"><Plus size={21} /><span>添加</span></button>
      <button aria-current={route.surface === 'profile' ? 'page' : undefined} className={route.surface === 'profile' ? 'is-active' : ''} onClick={() => void navigate({ surface: 'profile' })} type="button"><UserRound size={19} /><span>我的</span></button>
    </nav>
    {import.meta.env.DEV && import.meta.env.VITE_HYBRID_INTERNAL === 'true'
      ? <output className="tm-hybrid-shell__diagnostics" aria-label="Hybrid 开发诊断">{platform.kind} · bridge v{runtime.bridgeVersion} · {runtime.dataSource}</output>
      : null}
  </div>
}

function ShellState({ kind, message, code, action }: { kind: 'loading' | 'auth' | 'fatal'; message: string; code?: string; action?: () => void | Promise<void> }) {
  return <main className={`tm-hybrid-state is-${kind}`}>
    {kind === 'loading' ? <span aria-hidden="true" className="tm-hybrid-state__loader" /> : null}
    <h1>{kind === 'auth' ? '需要登录' : kind === 'fatal' ? '无法启动 Taste Map' : '正在启动 Taste Map'}</h1>
    <p>{message}</p>
    {code ? <small>错误代码：{code}</small> : null}
    {action ? <button onClick={() => void action()} type="button"><RotateCcw aria-hidden="true" size={17} />{kind === 'auth' ? '使用 Apple 登录' : '重试'}</button> : null}
  </main>
}

function NativePrimaryHandoff({ route, onBack }: { route: Exclude<HybridRoute, { surface: 'map' } | { surface: 'profile' } | { surface: 'restaurant'; id: string }>; onBack: () => void }) {
  return <main className="tm-hybrid-state is-native-primary">
    <h1>此功能仍由原生界面承载</h1>
    <p>{route.surface} 当前状态为 {surfaceStatus(route.surface)}，Phase 1 没有迁移这个页面。</p>
    <button onClick={onBack} type="button"><ArrowLeft aria-hidden="true" size={17} />返回我的页面</button>
  </main>
}

async function openNativeRoute(platform: TasteMapPlatform, route: 'discovery' | 'add' | 'visit' | 'roulette' | 'settings', identifier?: string) {
  try { await platform.navigation.openNative({ route, identifier }) }
  catch (reason) {
    if (reason instanceof TasteMapPlatformError && reason.code === 'capability_unavailable') {
      window.location.hash = routeHash({ surface: route, id: identifier })
      return
    }
    throw reason
  }
}

function normalizeError(reason: unknown) {
  if (reason instanceof TasteMapPlatformError) return reason
  if (reason instanceof Error) return new TasteMapPlatformError(reason.message, 'hybrid_initialization_failed')
  return new TasteMapPlatformError('Taste Map 初始化失败。', 'hybrid_initialization_failed')
}

function initialRoute(): HybridRoute {
  const debugRoute = import.meta.env.VITE_HYBRID_INTERNAL === 'true'
    ? import.meta.env.VITE_HYBRID_DEBUG_ROUTE
    : undefined
  return routeFromLocation({ hash: debugRoute || window.location.hash } as Location)
}

function updateLocation(nextRoute: HybridRoute) {
  const hash = routeHash(nextRoute)
  if (window.location.hash === hash) window.dispatchEvent(new HashChangeEvent('hashchange'))
  else window.location.hash = hash
}

function hybridRouteToPlatform(route: HybridRoute): PlatformRoute {
  if (route.surface === 'restaurant') return { surface: 'restaurant', identifier: route.id }
  if (route.surface === 'profile') return { surface: 'profile', identifier: route.id }
  return { surface: route.surface, identifier: route.id }
}

function platformRouteToHybrid(route: PlatformRoute): HybridRoute | null {
  if (route.surface === 'restaurant') return route.identifier ? { surface: 'restaurant', id: route.identifier } : null
  if (route.surface === 'profile') return { surface: 'profile', id: route.identifier }
  if (route.surface === 'publicList' || route.surface === 'activity') return { surface: route.surface, id: route.identifier }
  return { surface: route.surface, id: route.identifier }
}
