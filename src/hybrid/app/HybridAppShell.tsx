import { useEffect, useMemo, useRef, useState } from 'react'
import { ArrowLeft, BookOpen, CloudOff, Globe2, Map as MapIcon, RotateCcw, Sparkles, UserRound } from 'lucide-react'
import { MyMapBrowsePage } from '../../components/MyMapBrowsePage'
import { ProfilePage } from '../../components/ProfilePage'
import { RestaurantPreviewCard } from '../../components/RestaurantPreviewCard'
import { RestaurantRoulette, type RouletteTemporaryCandidate } from '../../components/RestaurantRoulette'
import { resolveTasteMapPlatform } from '../../platform/tasteMapPlatformResolver'
import { TasteMapPlatformError, type TasteMapHybridContentSnapshotDTO, type TasteMapHybridRoute as PlatformRoute, type TasteMapPlatform, type TasteMapProfileDashboardViewModel, type TasteMapRestaurantDetailViewModel, type TasteMapRuntimeInfo } from '../../platform/TasteMapPlatform'
import { routeFromLocation, routeFromStartupLocation, routeHash, surfaceStatus, type HybridRoute } from '../routes/HybridRouteRegistry'
import './hybridShell.css'
import { HybridDiscoveryPage } from './HybridDiscoveryPage'
import { HybridAddRestaurantPage } from './HybridAddRestaurantPage'
import { HybridVisitEditorPage } from './HybridVisitEditorPage'
import { TasteMapListsPage } from '../../components/TasteMapListsPage'
import { TasteMapAnalyticsPage, type AnalyticsMode } from '../../components/TasteMapAnalyticsPage'
import { TasteMapPremiumPage, TasteMapSettingsPage } from '../../components/TasteMapPremiumSettingsPages'
import { HYBRID_BOTTOM_NAVIGATION } from './HybridProductContracts'
import { PREMIUM_PAYWALL_OPEN_EVENT } from '../../services/premiumPaywall'

type BootstrapState =
  | { state: 'loading' }
  | { state: 'ready'; runtime: TasteMapRuntimeInfo; profile: TasteMapProfileDashboardViewModel; content: TasteMapHybridContentSnapshotDTO }
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
  const [rouletteRestaurantIDs, setRouletteRestaurantIDs] = useState<string[]>([])
  const [rouletteTemporaryItems, setRouletteTemporaryItems] = useState<RouletteTemporaryCandidate[]>([])
  const [detailRevision, setDetailRevision] = useState(0)
  const didSynchronizeInitialRoute = useRef(false)
  const didInitializeRoulette = useRef(false)

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
        if (next) {
          updateLocation(next)
          if (next.surface === 'restaurant') setDetailRevision((value) => value + 1)
        }
      }
    }).then((subscription) => { remove = () => subscription.remove() }).catch(() => undefined)
    return () => {
      active = false
      void remove?.()
    }
  }, [platform])

  useEffect(() => {
    const openPremium = () => {
      const next: HybridRoute = { surface: 'premium' }
      updateLocation(next)
      if (platform.kind === 'native') void platform.navigation.openHybrid(hybridRouteToPlatform(next))
    }
    window.addEventListener(PREMIUM_PAYWALL_OPEN_EVENT, openPremium)
    return () => window.removeEventListener(PREMIUM_PAYWALL_OPEN_EVENT, openPremium)
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
        const [profile, content] = await Promise.all([
          platform.profile.getCurrent(),
          platform.content.snapshot().catch(() => emptyContentSnapshot()),
        ])
        if (!active) return
        setBootstrap({ state: 'ready', runtime, profile, content })
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
  }, [detailRevision, platform, route])

  useEffect(() => {
    if (route.surface === 'map') setMapWasActivated(true)
  }, [route.surface])

  useEffect(() => {
    if (bootstrap.state !== 'ready' || didInitializeRoulette.current) return
    didInitializeRoulette.current = true
    setRouletteRestaurantIDs(bootstrap.profile.restaurants
      .filter((item) => item.status === 'visited' || item.status === 'wantToGo')
      .slice(0, 5)
      .map((item) => item.id))
  }, [bootstrap])

  const navigate = async (nextRoute: HybridRoute) => {
    updateLocation(nextRoute)
    if (platform.kind === 'native') await platform.navigation.openHybrid(hybridRouteToPlatform(nextRoute))
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

  const { profile, runtime, content } = bootstrap
  return <div className="tm-hybrid-shell" data-adapter={platform.kind} data-bridge-version={runtime.bridgeVersion} data-route={route.surface}>
    {!online ? <div className="tm-hybrid-shell__offline" role="status"><CloudOff aria-hidden="true" size={15} />离线模式 · 正在使用本地数据</div> : null}
    {mapWasActivated ? <MyMapBrowsePage
      active={route.surface === 'map'}
      onAddRestaurant={() => void navigate({ surface: 'add' })}
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
          onOpenAnalytics={(section) => void navigate({ surface: 'analytics', id: section })}
          onOpenLists={() => void navigate({ surface: 'lists' })}
          onOpenRoulette={() => void navigate({ surface: 'roulette' })}
          onOpenSettings={() => void navigate({ surface: 'settings' })}
          onEditProfile={() => void platform.navigation.openNative({ route: 'profileEdit' })}
          onOpenConnections={() => void platform.navigation.openNative({ route: 'socialNative' })}
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
                isInRoulette={rouletteRestaurantIDs.includes(restaurant.restaurant.id)}
                onAddToRoulette={restaurant.capabilities.canAddToRoulette ? () => setRouletteRestaurantIDs((ids) => ids.includes(restaurant.restaurant.id) ? ids.filter((id) => id !== restaurant.restaurant.id) : [...ids, restaurant.restaurant.id]) : undefined}
                onAddToList={restaurant.capabilities.canAddToList ? () => void openNativeRoute(platform, 'restaurantAddToList', restaurant.restaurant.id) : undefined}
                onAddToWant={restaurant.capabilities.canAddToWantToGo && restaurant.viewerState === 'none' ? () => void openNativeRoute(platform, 'restaurantWantToGo', restaurant.restaurant.id) : undefined}
                onAddVisit={restaurant.capabilities.canRecordVisit ? () => void navigate({ surface: 'visit', id: restaurant.restaurant.id }) : undefined}
                onClose={() => void navigateBack()}
                onDelete={restaurant.capabilities.canDeleteRestaurant ? () => void openNativeRoute(platform, 'restaurantDelete', restaurant.restaurant.id) : undefined}
                onEdit={restaurant.capabilities.canEditRestaurant ? () => void openNativeRoute(platform, 'restaurantEdit', restaurant.restaurant.id) : undefined}
                onEditVisit={(visit) => void navigate({ surface: 'visitEdit', id: visit.id })}
                onShare={restaurant.capabilities.canShare ? () => void platform.share.open({ title: restaurant.restaurant.name, text: `${restaurant.restaurant.name} · ${restaurant.restaurant.address}` }) : undefined}
                canEditVisit={(visit) => restaurant.editableVisitIDs.includes(visit.id)}
                readOnly={!restaurant.capabilities.canEditRestaurant && !restaurant.capabilities.canDeleteRestaurant}
                remoteStatsEnabled={false}
                restaurant={restaurant.restaurant}
                viewerStatus={restaurant.viewerState === 'none' ? null : restaurant.viewerState === 'visited' ? 'visited' : 'wantToGo'}
              />
            </main>
          : <ShellState kind="loading" message={routeError ?? '正在读取餐厅详情…'} />
        : route.surface === 'discovery' || route.surface === 'activity'
          ? <HybridDiscoveryPage content={content} onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} />
        : route.surface === 'add'
          ? <HybridAddRestaurantPage onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} />
        : route.surface === 'visit' || route.surface === 'visitEdit'
          ? <HybridVisitEditorPage
              onClose={() => void navigateBack()}
              onSaved={(restaurantID) => {
                setGeneration((value) => value + 1)
                setDetailRevision((value) => value + 1)
                void navigate({ surface: 'restaurant', id: restaurantID })
              }}
              platform={platform}
              restaurantID={route.surface === 'visit' ? route.id : undefined}
              restaurants={profile.restaurants}
              visitID={route.surface === 'visitEdit' ? route.id : undefined}
              visits={profile.visits}
            />
        : route.surface === 'lists' || route.surface === 'publicList'
          ? <TasteMapListsPage lists={content.lists} onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} />
        : route.surface === 'roulette'
          ? <RestaurantRoulette
              onClose={() => void navigate({ surface: 'profile' })}
              onSelectRestaurant={(item) => void navigate({ surface: 'restaurant', id: item.id })}
              onSelectedRestaurantIdsChange={setRouletteRestaurantIDs}
              onTemporaryItemsChange={setRouletteTemporaryItems}
              restaurants={profile.restaurants.filter((item) => item.status === 'visited' || item.status === 'wantToGo')}
              selectedRestaurantIds={rouletteRestaurantIDs}
              temporaryItems={rouletteTemporaryItems}
            />
        : route.surface === 'analytics'
          ? <TasteMapAnalyticsPage initialMode={analyticsMode(route.id)} onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} profile={profile} />
        : route.surface === 'premium'
          ? <TasteMapPremiumPage platform={platform} />
        : route.surface === 'settings'
          ? <TasteMapSettingsPage onOpenPremium={() => void navigate({ surface: 'premium' })} platform={platform} profile={profile} />
        : <NativePrimaryHandoff route={route} onBack={() => navigate({ surface: 'profile' })} />}
    <nav aria-label="主要功能" className="tm-hybrid-bottom-nav" data-product-contract="bottom-navigation">
      {HYBRID_BOTTOM_NAVIGATION.map((item) => <button
        aria-current={route.surface === item.surface ? 'page' : undefined}
        className={route.surface === item.surface ? 'is-active' : ''}
        key={item.surface}
        onClick={() => void navigate({ surface: item.surface })}
        type="button"
      >{item.surface === 'map' ? <MapIcon size={19} /> : item.surface === 'discovery' ? <Globe2 size={19} /> : <UserRound size={19} />}<span>{item.label}</span></button>)}
    </nav>
    {route.surface === 'profile' ? <div aria-label="Hybrid 主要功能快捷入口" className="tm-hybrid-profile-shortcuts"><button onClick={() => void navigate({ surface: 'lists' })} type="button"><BookOpen size={16} />我的食单</button><button onClick={() => void navigate({ surface: 'analytics' })} type="button"><Sparkles size={16} />数据分析</button></div> : null}
    {import.meta.env.DEV && import.meta.env.VITE_HYBRID_DIAGNOSTICS === 'true'
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

async function openNativeRoute(platform: TasteMapPlatform, route: 'restaurantEdit' | 'restaurantDelete' | 'restaurantAddToList' | 'restaurantWantToGo', identifier: string) {
  try { await platform.navigation.openNative({ route, identifier }) }
  catch (reason) {
    if (reason instanceof TasteMapPlatformError && reason.code === 'capability_unavailable') {
      return
    }
    throw reason
  }
}

function emptyContentSnapshot(): TasteMapHybridContentSnapshotDTO {
  return {
    generatedAt: new Date(0).toISOString(),
    discovery: { forYou: [], similarTaste: [], trending: [] },
    community: { following: [], latest: [] },
    lists: [],
  }
}

function analyticsMode(value?: string): AnalyticsMode {
  return value === 'companion' || value === 'source' || value === 'monthly' || value === 'annual' ? value : 'taste'
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
  return routeFromStartupLocation(window.location, debugRoute)
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
  if (route.surface === 'visitEdit'
    || route.surface === 'acquisitionNative'
    || route.surface === 'listManage'
    || route.surface === 'premiumStore'
    || route.surface === 'settingsNative'
    || route.surface === 'socialNative'
    || route.surface === 'profileEdit'
    || route.surface === 'restaurantEdit'
    || route.surface === 'restaurantDelete'
    || route.surface === 'restaurantAddToList'
    || route.surface === 'restaurantWantToGo') return null
  if (route.surface === 'restaurant') return route.identifier ? { surface: 'restaurant', id: route.identifier } : null
  if (route.surface === 'profile') return { surface: 'profile', id: route.identifier }
  if (route.surface === 'publicList' || route.surface === 'activity') return { surface: route.surface, id: route.identifier }
  return { surface: route.surface, id: route.identifier }
}
