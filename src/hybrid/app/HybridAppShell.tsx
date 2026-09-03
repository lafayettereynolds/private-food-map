import { useEffect, useMemo, useRef, useState } from 'react'
import { ArrowLeft, CloudOff, Globe2, Map as MapIcon, RotateCcw, UserRound } from 'lucide-react'
import { MyMapBrowsePage } from '../../components/MyMapBrowsePage'
import { NativeMapSurface } from '../../components/NativeMapSurface'
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
import type { RestaurantSummary } from '../../types/domain'

type BootstrapState =
  | { state: 'loading' }
  | { state: 'ready'; runtime: TasteMapRuntimeInfo; profile: TasteMapProfileDashboardViewModel; content: TasteMapHybridContentSnapshotDTO; contentReady: boolean }
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
  const [discoveryWasActivated, setDiscoveryWasActivated] = useState(() => ['discovery', 'activity'].includes(initialRoute().surface))
  const [profileWasActivated, setProfileWasActivated] = useState(() => initialRoute().surface === 'profile')
  const [rouletteRestaurantIDs, setRouletteRestaurantIDs] = useState<string[]>([])
  const [rouletteExternalRestaurants, setRouletteExternalRestaurants] = useState<RestaurantSummary[]>([])
  const [rouletteTemporaryItems, setRouletteTemporaryItems] = useState<RouletteTemporaryCandidate[]>([])
  const [visitReturnToDiscovery, setVisitReturnToDiscovery] = useState(false)
  const [detailRevision, setDetailRevision] = useState(0)
  const didSynchronizeInitialRoute = useRef(false)
  const didInitializeRoulette = useRef(false)
  const pendingHybridNavigation = useRef<{ hash: string; expiresAt: number } | null>(null)
  const restaurantDetailCache = useRef(new Map<string, TasteMapRestaurantDetailViewModel>())

  useEffect(() => {
    let active = true
    let remove: (() => Promise<void>) | undefined
    platform.events.subscribe((event) => {
      if (!active) return
      if (event.name === 'auth.changed') {
        setRestaurant(null)
        restaurantDetailCache.current.clear()
        setGeneration((value) => value + 1)
      }
      if (event.name === 'navigation.route' || event.name === 'deepLink.received') {
        const next = platformRouteToHybrid(event.payload.route)
        if (next) {
          const nextHash = routeHash(next)
          const pending = pendingHybridNavigation.current
          const isLocalNavigationEcho = event.name === 'navigation.route'
            && pending?.hash === nextHash
            && pending.expiresAt >= Date.now()
          if (isLocalNavigationEcho || (pending && pending.expiresAt < Date.now())) {
            pendingHybridNavigation.current = null
          }
          const routeWasAlreadyVisible = window.location.hash === nextHash
          if (!routeWasAlreadyVisible) commitLocalRoute(next, setRoute)
          if (next.surface === 'restaurant' && routeWasAlreadyVisible && !isLocalNavigationEcho) {
            setDetailRevision((value) => value + 1)
          }
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
      commitLocalRoute(next, setRoute)
      if (platform.kind === 'native') {
        window.requestAnimationFrame(() => void platform.navigation.openHybrid(hybridRouteToPlatform(next)))
      }
    }
    window.addEventListener(PREMIUM_PAYWALL_OPEN_EVENT, openPremium)
    return () => window.removeEventListener(PREMIUM_PAYWALL_OPEN_EVENT, openPremium)
  }, [platform])

  useEffect(() => {
    if (!window.location.hash) window.history.replaceState(null, '', routeHash(initialRoute()))
    const updateRoute = () => setRoute(routeFromLocation(window.location))
    const updateOnline = () => setOnline(navigator.onLine)
    window.addEventListener('hashchange', updateRoute)
    window.addEventListener('popstate', updateRoute)
    window.addEventListener('online', updateOnline)
    window.addEventListener('offline', updateOnline)
    return () => {
      window.removeEventListener('hashchange', updateRoute)
      window.removeEventListener('popstate', updateRoute)
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
        const profileRequest = platform.profile.getCurrent()
        const contentRequest = platform.content.snapshot().catch(() => emptyContentSnapshot())
        const profile = await profileRequest
        if (!active) return
        setBootstrap({ state: 'ready', runtime, profile, content: emptyContentSnapshot(), contentReady: false })
        const content = await contentRequest
        if (!active) return
        setBootstrap((current) => current.state === 'ready'
          ? { ...current, content, contentReady: true }
          : current)
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
      return
    }
    const cached = restaurantDetailCache.current.get(route.id.toLowerCase())
    setRestaurant((current) => cached ?? (current && sameRestaurantID(current.restaurant.id, route.id) ? current : null))
    let active = true
    platform.restaurant.get(route.id)
      .then((value) => {
        restaurantDetailCache.current.set(route.id.toLowerCase(), value)
        restaurantDetailCache.current.set(value.restaurant.id.toLowerCase(), value)
        if (active) setRestaurant(value)
      })
      .catch((reason: unknown) => { if (active) setRouteError(normalizeError(reason).message) })
    return () => { active = false }
  }, [detailRevision, platform, route])

  useEffect(() => {
    if (route.surface === 'map') setMapWasActivated(true)
    if (route.surface === 'discovery' || route.surface === 'activity') setDiscoveryWasActivated(true)
    if (route.surface === 'profile') setProfileWasActivated(true)
  }, [route.surface])

  useEffect(() => {
    if (bootstrap.state !== 'ready' || didInitializeRoulette.current) return
    didInitializeRoulette.current = true
    setRouletteRestaurantIDs(bootstrap.profile.restaurants
      .filter((item) => item.status === 'visited' || item.status === 'wantToGo')
      .slice(0, 5)
      .map((item) => item.id))
  }, [bootstrap])

  const navigate = (nextRoute: HybridRoute) => {
    commitLocalRoute(nextRoute, setRoute)
    if (platform.kind === 'native') {
      const nextHash = routeHash(nextRoute)
      // Native publishes the accepted route back as an event. Keep a short
      // acknowledgement window so an asynchronously delivered echo cannot
      // trigger a second Restaurant read after the visible route changes.
      pendingHybridNavigation.current = { hash: nextHash, expiresAt: Date.now() + 2_000 }
      // Let React commit the next screen before synchronizing Native history;
      // the bookkeeping bridge must never sit in the user's tap-to-paint path.
      window.requestAnimationFrame(() => {
        void platform.navigation.openHybrid(hybridRouteToPlatform(nextRoute))
      })
    }
  }

  const navigateBack = async () => {
    if (platform.kind === 'native') {
      // Browser history owns the immediately visible Hybrid transition. Native
      // history reconciles afterward for deep links and Native-owned sheets.
      window.history.back()
      const state = await platform.navigation.back()
      const next = platformRouteToHybrid(state.route)
      if (next && window.location.hash !== routeHash(next)) {
        replaceLocalRoute(next, setRoute)
      }
      return
    }
    window.history.back()
  }

  const refreshReadyData = async () => {
    const [nextProfile, nextContent] = await Promise.all([platform.profile.getCurrent(), platform.content.snapshot()])
    setBootstrap((current) => current.state === 'ready'
      ? { ...current, profile: nextProfile, content: nextContent, contentReady: true }
      : current)
  }

  const openDiscoveryVisit = (restaurantID: string) => {
    setVisitReturnToDiscovery(true)
    void navigate({ surface: 'visit', id: restaurantID })
  }

  const openDiscoveryRoulette = (restaurantID: string) => {
    navigate({ surface: 'roulette' })
    void platform.restaurant.get(restaurantID).then((detail) => {
      restaurantDetailCache.current.set(detail.restaurant.id.toLowerCase(), detail)
      setRouletteExternalRestaurants((current) => current.some((item) => item.id === detail.restaurant.id) ? current : [...current, detail.restaurant])
      setRouletteRestaurantIDs((current) => current.includes(detail.restaurant.id) ? current : [...current, detail.restaurant.id].slice(0, 10))
    }).catch((reason: unknown) => setRouteError(normalizeError(reason).message))
  }

  const toggleDetailCollection = async (detail: TasteMapRestaurantDetailViewModel) => {
    if (!detail.capabilities.canAddToWantToGo || detail.viewerState === 'visited') return
    const result = await platform.restaurant.setWantToGo(
      detail.restaurant.id,
      detail.viewerState !== 'want_to_go',
    )
    restaurantDetailCache.current.delete(detail.restaurant.id.toLowerCase())
    void refreshReadyData().catch(() => undefined)
    if (result.viewerState === 'none') {
      await navigateBack()
      return
    }
    setDetailRevision((value) => value + 1)
  }

  if (bootstrap.state === 'loading') return <ShellState kind="loading" message="正在读取 Taste Map 本地数据…" />
  if (bootstrap.state === 'authRequired') return <ShellState action={async () => {
    const result = await platform.auth.signInWithApple()
    if (result.state === 'authenticated') setGeneration((value) => value + 1)
  }} kind="auth" message={bootstrap.message} />
  if (bootstrap.state === 'fatal') {
    return <ShellState action={() => setGeneration((value) => value + 1)} code={bootstrap.code} kind="fatal" message={bootstrap.message} />
  }

  const { profile, runtime, content, contentReady } = bootstrap
  const detailRestaurant = route.surface === 'restaurant'
    ? restaurant && sameRestaurantID(restaurant.restaurant.id, route.id)
      ? restaurant
      : ownedRestaurantPreview(profile, route.id)
    : null
  return <div className="tm-hybrid-shell" data-adapter={platform.kind} data-bridge-version={runtime.bridgeVersion} data-route={route.surface}>
    {!online ? <div className="tm-hybrid-shell__offline" role="status"><CloudOff aria-hidden="true" size={15} />离线模式 · 正在使用本地数据</div> : null}
    {mapWasActivated ? <MyMapBrowsePage
      MapSurface={NativeMapSurface}
      active={route.surface === 'map'}
      onAddRestaurant={() => void navigate({ surface: 'add' })}
      onOpenRestaurant={(restaurantID) => void navigate({ surface: 'restaurant', id: restaurantID })}
      platform={platform}
      profile={profile}
    /> : null}
    {discoveryWasActivated ? <HybridDiscoveryPage
      active={route.surface === 'discovery' || route.surface === 'activity'}
      content={content}
      onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })}
      onOpenRoulette={(id) => void openDiscoveryRoulette(id)}
      onRecordVisit={openDiscoveryVisit}
      platform={platform}
      loading={!contentReady}
    /> : null}
    {profileWasActivated ? <div className="tm-hybrid-persistent-route" hidden={route.surface !== 'profile'}>
      <ProfilePage
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
        onOpenConnections={(section) => void platform.navigation.openNative({ route: 'socialNative', identifier: section })}
        onSelectRestaurant={(selected) => {
          void platform.haptics.selection()
          void navigate({ surface: 'restaurant', id: selected.id })
        }}
        restaurants={profile.restaurants}
        user={profile.user}
        visits={profile.visits}
      />
    </div> : null}
    {route.surface === 'map' || route.surface === 'discovery' || route.surface === 'activity' ? null : route.surface === 'profile'
      ? null
        : route.surface === 'restaurant'
        ? detailRestaurant
          ? <main className="tm-hybrid-detail">
              <button aria-label="返回上一页" className="tm-hybrid-detail__back" onClick={() => void navigateBack()} type="button"><ArrowLeft aria-hidden="true" size={18} />返回</button>
              <RestaurantPreviewCard
                additionalUserPhotos={detailRestaurant.restaurant.visits.flatMap((visit) => visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index] })))}
                historyRestaurants={profile.restaurants}
                isInRoulette={rouletteRestaurantIDs.includes(detailRestaurant.restaurant.id)}
                onAddToRoulette={detailRestaurant.capabilities.canAddToRoulette ? () => setRouletteRestaurantIDs((ids) => ids.includes(detailRestaurant.restaurant.id) ? ids.filter((id) => id !== detailRestaurant.restaurant.id) : [...ids, detailRestaurant.restaurant.id]) : undefined}
                onAddToList={detailRestaurant.capabilities.canAddToList ? () => void openNativeRoute(platform, 'restaurantAddToList', detailRestaurant.restaurant.id) : undefined}
                onAddToWant={detailRestaurant.capabilities.canAddToWantToGo && detailRestaurant.viewerState !== 'visited' ? () => void toggleDetailCollection(detailRestaurant) : undefined}
                onAddVisit={detailRestaurant.capabilities.canRecordVisit ? () => void navigate({ surface: 'visit', id: detailRestaurant.restaurant.id }) : undefined}
                onClose={() => void navigateBack()}
                onDelete={detailRestaurant.capabilities.canDeleteRestaurant ? () => void openNativeRoute(platform, 'restaurantDelete', detailRestaurant.restaurant.id) : undefined}
                onEdit={detailRestaurant.capabilities.canEditRestaurant ? () => void openNativeRoute(platform, 'restaurantEdit', detailRestaurant.restaurant.id) : undefined}
                onEditVisit={(visit) => void navigate({ surface: 'visitEdit', id: visit.id })}
                onShare={detailRestaurant.capabilities.canShare ? () => void platform.share.open({ title: detailRestaurant.restaurant.name, text: `${detailRestaurant.restaurant.name} · ${detailRestaurant.restaurant.address}` }) : undefined}
                canEditVisit={(visit) => detailRestaurant.editableVisitIDs.includes(visit.id)}
                readOnly={!detailRestaurant.capabilities.canEditRestaurant && !detailRestaurant.capabilities.canDeleteRestaurant}
                remoteStatsEnabled={false}
                restaurant={detailRestaurant.restaurant}
                socialStats={detailRestaurant.socialStats}
                viewerStatus={detailRestaurant.viewerState === 'none' ? null : detailRestaurant.viewerState === 'visited' ? 'visited' : 'wantToGo'}
              />
            </main>
          : <ShellState kind="loading" message={routeError ?? '正在读取餐厅详情…'} />
        : route.surface === 'add'
          ? <HybridAddRestaurantPage onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} />
        : route.surface === 'visit' || route.surface === 'visitEdit'
          ? <HybridVisitEditorPage
              onClose={() => { setVisitReturnToDiscovery(false); void navigateBack() }}
              onSaved={(restaurantID) => {
                setDetailRevision((value) => value + 1)
                if (visitReturnToDiscovery) {
                  setVisitReturnToDiscovery(false)
                  void refreshReadyData().finally(() => void navigateBack())
                } else {
                  setGeneration((value) => value + 1)
                  void navigate({ surface: 'restaurant', id: restaurantID })
                }
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
              onClose={() => void navigateBack()}
              onSelectRestaurant={(item) => void navigate({ surface: 'restaurant', id: item.id })}
              onSelectedRestaurantIdsChange={setRouletteRestaurantIDs}
              onTemporaryItemsChange={setRouletteTemporaryItems}
              restaurants={[...profile.restaurants.filter((item) => item.status === 'visited' || item.status === 'wantToGo'), ...rouletteExternalRestaurants.filter((external) => !profile.restaurants.some((item) => item.id === external.id))]}
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

async function openNativeRoute(platform: TasteMapPlatform, route: 'restaurantEdit' | 'restaurantDelete' | 'restaurantAddToList', identifier: string) {
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

function sameRestaurantID(left: string, right: string) {
  return left.toLowerCase() === right.toLowerCase()
}

function ownedRestaurantPreview(
  profile: TasteMapProfileDashboardViewModel,
  restaurantID: string,
): TasteMapRestaurantDetailViewModel | null {
  const restaurant = profile.restaurants.find((item) => sameRestaurantID(item.id, restaurantID))
  if (!restaurant) return null
  const imageEntry = Object.entries(profile.restaurantImages)
    .find(([id]) => sameRestaurantID(id, restaurantID))
  if (!imageEntry) return null
  return {
    restaurant,
    image: imageEntry[1],
    socialStats: null,
    viewerState: restaurant.status === 'visited' ? 'visited' : 'want_to_go',
    editableVisitIDs: restaurant.visits.map((visit) => visit.id),
    capabilities: {
      canEditRestaurant: true,
      canDeleteRestaurant: true,
      canRecordVisit: true,
      canAddToWantToGo: true,
      canAddToList: true,
      canAddToRoulette: true,
      canShare: true,
    },
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

function commitLocalRoute(nextRoute: HybridRoute, setRoute: (route: HybridRoute) => void) {
  const hash = routeHash(nextRoute)
  if (window.location.hash !== hash) window.history.pushState(null, '', hash)
  setRoute(nextRoute)
}

function replaceLocalRoute(nextRoute: HybridRoute, setRoute: (route: HybridRoute) => void) {
  window.history.replaceState(null, '', routeHash(nextRoute))
  setRoute(nextRoute)
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
    || route.surface === 'dataBackup'
    || route.surface === 'permissions'
    || route.surface === 'storage'
    || route.surface === 'accountDelete'
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
