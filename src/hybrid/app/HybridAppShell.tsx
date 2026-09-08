import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ArrowLeft, CloudOff, Globe2, Map as MapIcon, RotateCcw, UserRound } from 'lucide-react'
import { MyMapBrowsePage } from '../../components/MyMapBrowsePage'
import { PremiumAccessBoundary } from '../../components/PremiumAccess'
import { PremiumReturnLayer } from '../../components/PremiumReturnLayer'
import { NativeMapSurface } from '../../components/NativeMapSurface'
import { ProfilePage } from '../../components/ProfilePage'
import { RestaurantPreviewCard } from '../../components/RestaurantPreviewCard'
import { HybridBackButton, HybridState } from '../../components/TasteMapHybridShared'
import { RestaurantRoulette, type RouletteSessionState, type RouletteTemporaryCandidate } from '../../components/RestaurantRoulette'
import { RouletteCandidateDock } from '../../components/RouletteCandidateDock'
import { resolveTasteMapPlatform } from '../../platform/tasteMapPlatformResolver'
import { TasteMapPlatformError, type TasteMapHybridContentSnapshotDTO, type TasteMapHybridRoute as PlatformRoute, type TasteMapPlatform, type TasteMapProfileDashboardViewModel, type TasteMapRestaurantDetailViewModel, type TasteMapRuntimeInfo } from '../../platform/TasteMapPlatform'
import { routeFromLocation, routeFromStartupLocation, routeHash, surfaceStatus, type HybridRoute } from '../routes/HybridRouteRegistry'
import './hybridShell.css'
import { HybridDiscoveryPage } from './HybridDiscoveryPage'
import { HybridAddRestaurantPage } from './HybridAddRestaurantPage'
import { HybridVisitEditorPage } from './HybridVisitEditorPage'
import { boundedSnapshotRead, refreshHybridSnapshots } from './hybridSnapshotRefresh'
import { discoveryRefreshMessage } from './discoveryRefreshState'
import { beginHybridHistoryBack } from './hybridHistoryTraversal'
import { detailMatchesRoute, restaurantDetailIdentityKey } from './restaurantDetailIdentity'
import { HybridProfileListsPreview, TasteMapListsPage } from '../../components/TasteMapListsPage'
import { TasteMapAnalyticsPage, type AnalyticsMode } from '../../components/TasteMapAnalyticsPage'
import { TasteMapPremiumPage, TasteMapSettingsPage } from '../../components/TasteMapPremiumSettingsPages'
import { TasteMapReferralPage } from '../../components/TasteMapReferralPage'
import { TasteMapDirectoryPage } from '../../components/TasteMapDirectoryPage'
import { RestaurantAvatarEditorSheet } from '../../components/RestaurantAvatarEditorSheet'
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
  const [premiumLayerOpen, setPremiumLayerOpen] = useState(false)
  const [bootstrap, setBootstrap] = useState<BootstrapState>({ state: 'loading' })
  const [restaurant, setRestaurant] = useState<TasteMapRestaurantDetailViewModel | null>(null)
  const [resolvedRestaurantRequestID, setResolvedRestaurantRequestID] = useState<string | null>(null)
  const [routeError, setRouteError] = useState<string | null>(null)
  const [online, setOnline] = useState(() => navigator.onLine)
  const [generation, setGeneration] = useState(0)
  const [mapWasActivated, setMapWasActivated] = useState(() => initialRoute().surface === 'map')
  const [discoveryWasActivated, setDiscoveryWasActivated] = useState(() => ['discovery', 'activity'].includes(initialRoute().surface))
  const [profileWasActivated, setProfileWasActivated] = useState(() => initialRoute().surface === 'profile')
  const [rouletteRestaurantIDs, setRouletteRestaurantIDs] = useState<string[]>([])
  const [rouletteExternalRestaurants, setRouletteExternalRestaurants] = useState<RestaurantSummary[]>([])
  const [rouletteTemporaryItems, setRouletteTemporaryItems] = useState<RouletteTemporaryCandidate[]>([])
  const [rouletteSession, setRouletteSession] = useState<RouletteSessionState>({ rotation: 0, winnerId: null })
  const [showRouletteCandidates, setShowRouletteCandidates] = useState(false)
  const visitParentRoute = useRef<HybridRoute | null>(null)
  const currentRouteRef = useRef(route)
  currentRouteRef.current = route
  const [detailRevision, setDetailRevision] = useState(0)
  const [avatarEditorOpen, setAvatarEditorOpen] = useState(false)
  const didSynchronizeInitialRoute = useRef(false)
  const pendingHybridNavigation = useRef<{ hash: string; expiresAt: number } | null>(null)
  const navigationRevision = useRef(0)
  const pendingRestaurantDeletion = useRef<{ routeID: string } | null>(null)
  const restaurantDetailCache = useRef(new Map<string, TasteMapRestaurantDetailViewModel>())
  const deletedRestaurantRoutes = useRef(new Set<string>())
  const snapshotRefreshSequence = useRef(0)
  const [refreshError, setRefreshError] = useState<string | null>(null)
  const [contentReadError, setContentReadError] = useState<string | null>(null)
  const readyRef = useRef(false)
  readyRef.current = bootstrap.state === 'ready'

  const navigate = useCallback((nextRoute: HybridRoute, replace = false) => {
    if (nextRoute.surface === 'premium') {
      setPremiumLayerOpen(true)
      return
    }
    const current = currentRouteRef.current
    if ((nextRoute.surface === 'visit' || nextRoute.surface === 'visitEdit')
      && current.surface !== 'visit' && current.surface !== 'visitEdit') visitParentRoute.current = current
    const revision = ++navigationRevision.current
    currentRouteRef.current = nextRoute
    if (replace) replaceLocalRoute(nextRoute, setRoute)
    else commitLocalRoute(nextRoute, setRoute)
    if (platform.kind !== 'native') return
    // Older hosts have no correlation ID; retain their same-route acknowledgement
    // compatibility. Current hosts consume correlated acknowledgements in the adapter.
    pendingHybridNavigation.current = { hash: routeHash(nextRoute), expiresAt: Date.now() + 2_000 }
    // Enqueue now, without awaiting: deferring this to RAF lets a Back request
    // overtake the open request and corrupt Native history before first paint.
    void platform.navigation.openHybrid(hybridRouteToPlatform(nextRoute), { localTransition: true, replaceCurrent: replace }).catch(reason => {
      if (revision === navigationRevision.current) setRouteError(normalizeError(reason).message)
    })
  }, [platform])

  const refreshReadyData = useCallback(async (forceRefresh = false) => {
    if (!readyRef.current) return
    const sequence = ++snapshotRefreshSequence.current
    const isCurrent = () => readyRef.current && sequence === snapshotRefreshSequence.current
    const result = await refreshHybridSnapshots(platform, {
      isCurrent,
      onProfile: (profile) => setBootstrap((current) => isCurrent() && current.state === 'ready'
        ? { ...current, profile } : current),
      onContent: (content) => setBootstrap((current) => isCurrent() && current.state === 'ready'
        ? { ...current, content, contentReady: true } : current),
    }, 15_000, { forceRefresh })
    if (sequence !== snapshotRefreshSequence.current) return
    // Local owner records must still update when the independent social/feed
    // request fails. Keep mounted pages and drafts; never re-run boot for data.
    setRefreshError((current) => isCurrent()
      ? result.failed ? result.message ?? '部分内容暂未更新，已保留当前页面。请重试。' : null
      : current)
    setContentReadError((current) => isCurrent()
      ? result.contentFailed ? '发现内容暂时无法读取，请重试。' : null
      : current)
  }, [platform])

  useEffect(() => {
    let active = true
    let remove: (() => Promise<void>) | undefined
    const refreshSnapshot = () => { void refreshReadyData() }
    platform.events.subscribe((event) => {
      if (!active) return
      if (event.name === 'auth.changed') {
        pendingRestaurantDeletion.current = null
        ++snapshotRefreshSequence.current
        readyRef.current = false
        setRestaurant(null)
        restaurantDetailCache.current.clear()
        visitParentRoute.current = null
        setGeneration((value) => value + 1)
      }
      if (event.name === 'data.changed') {
        restaurantDetailCache.current.clear()
        // New Native hosts complete successful deletion explicitly. Ordinary
        // sheet dismissal is cancellation and must resume Detail refreshes.
        if (event.payload.reason === 'nativePresentationDismissed') pendingRestaurantDeletion.current = null
        const deletion = pendingRestaurantDeletion.current
        const awaitingDeletedDetailExit = deletion && currentRouteRef.current.surface === 'restaurant'
          && sameRestaurantID(currentRouteRef.current.id, deletion.routeID)
        if (event.payload.reason === 'restaurantDeleted') {
          if (!awaitingDeletedDetailExit) setRestaurant(null)
        }
        if (event.payload.reason === 'localDataCleared') {
          setRestaurant(null)
          setRouletteRestaurantIDs([])
          setRouletteExternalRestaurants([])
          setRouletteTemporaryItems([])
          setRouletteSession({ rotation: 0, winnerId: null })
        }
        refreshSnapshot()
        // The successful Native deletion still owns its confirmation sheet.
        // Do not reread the deleted detail while that sheet is closing.
        if (!awaitingDeletedDetailExit) setDetailRevision((value) => value + 1)
      }
      if (event.name === 'app.lifecycle' && (event.payload.state === 'foreground' || event.payload.state === 'resume')) {
        refreshSnapshot()
      }
      if (event.name === 'navigation.route' || event.name === 'deepLink.received') {
        const next = platformRouteToHybrid(event.payload.route)
        if (next) {
          if (event.name === 'navigation.route' && event.payload.completedAction === 'restaurantDelete') {
            // Native has atomically closed its sheet and consumed the deleted
            // Detail. Reflect that result with replace, never issue a second
            // Native Back or push the deleted Detail behind its return page.
            pendingRestaurantDeletion.current = null
            pendingHybridNavigation.current = null
            ++navigationRevision.current
            currentRouteRef.current = next
            restaurantDetailCache.current.clear()
            setRestaurant(null)
            replaceLocalRoute(next, setRoute)
            refreshSnapshot()
            return
          }
          const deletion = pendingRestaurantDeletion.current
          if (event.name === 'navigation.route' && deletion) {
            // A queued underlying-detail echo while the confirmation opens
            // must neither disarm the operation nor reread its deleted data.
            if (next.surface === 'restaurant' && sameRestaurantID(next.id, deletion.routeID)) return
            pendingRestaurantDeletion.current = null
          }
          const nextHash = routeHash(next)
          const pending = pendingHybridNavigation.current
          const isLocalNavigationEcho = event.name === 'navigation.route'
            && pending?.hash === nextHash
            && pending.expiresAt >= Date.now()
          if (isLocalNavigationEcho || (pending && pending.expiresAt < Date.now())) {
            pendingHybridNavigation.current = null
          }
          const routeWasAlreadyVisible = window.location.hash === nextHash
          if (!routeWasAlreadyVisible && (next.surface === 'visit' || next.surface === 'visitEdit')) {
            const current = currentRouteRef.current
            if (current.surface !== 'visit' && current.surface !== 'visitEdit') visitParentRoute.current = current
          }
          if (!routeWasAlreadyVisible) {
            ++navigationRevision.current
            currentRouteRef.current = next
            commitLocalRoute(next, setRoute)
          }
          if (next.surface === 'restaurant' && routeWasAlreadyVisible && !isLocalNavigationEcho) {
            setDetailRevision((value) => value + 1)
          }
          if (event.name === 'navigation.route' && !isLocalNavigationEcho && (next.surface === 'profile' || next.surface === 'lists')) {
            refreshSnapshot()
          }
        }
      }
    }).then((subscription) => { remove = () => subscription.remove() }).catch(() => undefined)
    return () => {
      active = false
      ++snapshotRefreshSequence.current
      void remove?.()
    }
  }, [platform, refreshReadyData])

  useEffect(() => {
    const openPremium = () => {
      const next: HybridRoute = { surface: 'premium' }
      navigate(next)
    }
    window.addEventListener(PREMIUM_PAYWALL_OPEN_EVENT, openPremium)
    return () => window.removeEventListener(PREMIUM_PAYWALL_OPEN_EVENT, openPremium)
  }, [navigate])

  useEffect(() => {
    if (!window.location.hash) window.history.replaceState(null, '', routeHash(initialRoute()))
    const updateRoute = () => {
      const next = routeFromLocation(window.location)
      if (next.surface === 'restaurant' && deletedRestaurantRoutes.current.has(restaurantDetailIdentityKey(next.id))) {
        replaceLocalRoute({ surface: 'map' }, setRoute)
      } else setRoute(next)
    }
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
    if (route.surface === 'map') navigate({ surface: 'map' })
  }, [navigate, platform, route.surface])

  useEffect(() => {
    let active = true
    const sequence = ++snapshotRefreshSequence.current
    setBootstrap({ state: 'loading' })
    setRefreshError(null)
    setContentReadError(null)
    Promise.all([platform.runtime.info(), platform.auth.sessionStatus()])
      .then(async ([runtime, session]) => {
        if (!active) return
        if (session.state !== 'authenticated') {
          setBootstrap({ state: 'authRequired', message: '请先在 Taste Map 完成登录。' })
          return
        }
        const profileRequest = platform.profile.getCurrent()
        const contentRequest = boundedSnapshotRead(platform.content.snapshot()).then(
          (value) => ({ value, failed: false }),
          () => ({ value: emptyContentSnapshot(), failed: true }),
        )
        const profile = await profileRequest
        if (!active) return
        setBootstrap({ state: 'ready', runtime, profile, content: emptyContentSnapshot(), contentReady: false })
        const result = await contentRequest
        if (!active || sequence !== snapshotRefreshSequence.current) return
        setRefreshError(result.failed ? '发现与食单暂未更新，请重试。' : discoveryRefreshMessage(result.value))
        setContentReadError(result.failed ? '发现内容暂时无法读取，请重试。' : null)
        setBootstrap((current) => current.state === 'ready'
          ? { ...current, content: result.value, contentReady: true }
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
    if (route.surface !== 'restaurant' || bootstrap.state !== 'ready') {
      return
    }
    const cached = restaurantDetailCache.current.get(restaurantDetailIdentityKey(route.id))
    if (cached) setResolvedRestaurantRequestID(route.id)
    setRestaurant((current) => cached ?? (current && sameRestaurantID(current.restaurant.id, route.id) ? current : null))
    let active = true
    boundedSnapshotRead(platform.restaurant.get(route.id))
      .then((value) => {
        if (!active || !readyRef.current) return
        restaurantDetailCache.current.set(restaurantDetailIdentityKey(route.id), value)
        restaurantDetailCache.current.set(restaurantDetailIdentityKey(value.restaurant.id), value)
        setResolvedRestaurantRequestID(route.id)
        setRestaurant(value)
      })
      .catch((reason: unknown) => { if (active) setRouteError(normalizeError(reason).message) })
    return () => { active = false }
  }, [bootstrap.state, detailRevision, generation, platform, route])

  useEffect(() => {
    if (route.surface === 'map') setMapWasActivated(true)
    if (route.surface === 'discovery' || route.surface === 'activity') setDiscoveryWasActivated(true)
    if (route.surface === 'profile') setProfileWasActivated(true)
  }, [route.surface])

  useEffect(() => {
    // Hybrid routes replace the visible document surface. Do not carry the
    // previous Profile/List scroll offset into the next screen.
    window.requestAnimationFrame(() => window.scrollTo({ top: 0, left: 0, behavior: 'auto' }))
  }, [route.id, route.surface])

  useEffect(() => {
    if (route.surface !== 'restaurant') setAvatarEditorOpen(false)
  }, [route.surface])

  const navigateBack = async () => {
    const revision = ++navigationRevision.current
    if (platform.kind === 'native') {
      // Browser history owns the immediately visible Hybrid transition. Native
      // history reconciles afterward for deep links and Native-owned sheets.
      const traversed = beginHybridHistoryBack()
      const [state] = await Promise.all([platform.navigation.back({ localTransition: true }), traversed])
      if (revision !== navigationRevision.current) return
      const next = platformRouteToHybrid(state.route)
      if (next && window.location.hash !== routeHash(next)) {
        currentRouteRef.current = next
        replaceLocalRoute(next, setRoute)
      }
      return
    }
    window.history.back()
  }

  const requestRestaurantDeletion = (restaurantID: string) => {
    const current = currentRouteRef.current
    const attempt = platform.kind === 'native' && current.surface === 'restaurant'
      ? { routeID: current.id } : null
    pendingRestaurantDeletion.current = attempt
    void openNativeRoute(platform, 'restaurantDelete', restaurantID).catch(reason => {
      if (pendingRestaurantDeletion.current === attempt) pendingRestaurantDeletion.current = null
      setRouteError(normalizeError(reason).message)
    })
  }

  const returnFromProfileList = async () => {
    const revision = ++navigationRevision.current
    const profileRoute: HybridRoute = { surface: 'profile' }
    // A Profile List detail is a drill-in, not a standalone destination. Replace
    // it synchronously so returning never exposes the intermediate all-Lists page
    // or asks WKWebView to perform a document-history navigation.
    replaceLocalRoute(profileRoute, setRoute)
    currentRouteRef.current = profileRoute
    if (platform.kind !== 'native') return
    const state = await platform.navigation.back({ localTransition: true })
    if (revision !== navigationRevision.current) return
    const next = platformRouteToHybrid(state.route)
    if (next?.surface !== 'profile') {
      await platform.navigation.openHybrid(hybridRouteToPlatform(profileRoute), { localTransition: true })
    }
  }

  const openDiscoveryVisit = (restaurantID: string) => {
    void navigate({ surface: 'visit', id: restaurantID })
  }

  const openDiscoveryRoulette = (restaurantID: string) => {
    if (rouletteRestaurantIDs.includes(restaurantID)) {
      setRouletteRestaurantIDs((current) => current.filter((id) => id !== restaurantID))
      return
    }
    if (rouletteRestaurantIDs.length + rouletteTemporaryItems.length >= 10) return
    void platform.restaurant.get(restaurantID).then((detail) => {
      restaurantDetailCache.current.set(restaurantDetailIdentityKey(detail.restaurant.id), detail)
      setRouletteExternalRestaurants((current) => current.some((item) => item.id === detail.restaurant.id) ? current : [...current, detail.restaurant])
      setRouletteRestaurantIDs((current) => current.includes(detail.restaurant.id) ? current : [...current, detail.restaurant.id].slice(0, 10 - rouletteTemporaryItems.length))
    }).catch((reason: unknown) => setRouteError(normalizeError(reason).message))
  }

  const toggleDetailRoulette = (detail: TasteMapRestaurantDetailViewModel) => {
    const restaurantID = detail.restaurant.id
    if (rouletteRestaurantIDs.includes(restaurantID)) {
      setRouletteRestaurantIDs((current) => current.filter((id) => id !== restaurantID))
      return
    }
    if (rouletteRestaurantIDs.length + rouletteTemporaryItems.length >= 10) return
    setRouletteExternalRestaurants((current) => current.some((item) => item.id === restaurantID)
      ? current
      : [...current, detail.restaurant])
    setRouletteRestaurantIDs((current) => current.includes(restaurantID) ? current : [...current, restaurantID])
  }

  const removeRouletteCandidate = (candidateID: string) => {
    if (rouletteTemporaryItems.some((item) => item.id === candidateID)) {
      setRouletteTemporaryItems((current) => current.filter((item) => item.id !== candidateID))
    } else {
      setRouletteRestaurantIDs((current) => current.filter((id) => id !== candidateID))
    }
    setRouletteSession((current) => current.winnerId === candidateID ? { ...current, winnerId: null } : current)
  }

  const clearRouletteCandidates = () => {
    setRouletteRestaurantIDs([])
    setRouletteTemporaryItems([])
    setRouletteSession({ rotation: 0, winnerId: null })
    setShowRouletteCandidates(false)
  }

  const toggleDetailCollection = async (detail: TasteMapRestaurantDetailViewModel) => {
    if (!detail.capabilities.canAddToWantToGo || detail.viewerState === 'visited') return
    const result = await platform.restaurant.setWantToGo(
      detail.restaurant.id,
      detail.viewerState !== 'want_to_go',
    )
    restaurantDetailCache.current.delete(restaurantDetailIdentityKey(detail.restaurant.id))
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
  const rouletteRestaurants = [
    ...profile.restaurants.filter((item) => item.status === 'visited' || item.status === 'wantToGo'),
    ...rouletteExternalRestaurants.filter((external) => !profile.restaurants.some((item) => item.id === external.id)),
  ]
  const rouletteCandidates = [
    ...rouletteRestaurantIDs.flatMap((id) => {
      const selected = rouletteRestaurants.find((item) => item.id === id)
      return selected ? [{ id, name: selected.name }] : []
    }),
    ...rouletteTemporaryItems,
  ]
  const detailRestaurant = route.surface === 'restaurant'
    ? restaurant && detailMatchesRoute(restaurant, route.id, resolvedRestaurantRequestID)
      ? restaurant
      : routeError ? null : ownedRestaurantPreview(profile, route.id)
    : null
  return <PremiumAccessBoundary key={profile.user.id} ownerID={profile.user.id} platform={platform} revision={`${profile.user.membershipTier}:${route.surface}`}><div
    className="tm-hybrid-shell"
    data-adapter={platform.kind}
    data-bridge-version={runtime.bridgeVersion}
    data-route={route.surface}
    onContextMenu={(event) => {
      if ((event.target as HTMLElement).closest('input, textarea, [contenteditable="true"]')) return
      event.preventDefault()
    }}
  >
    {!online ? <div className="tm-hybrid-shell__offline" role="status"><CloudOff aria-hidden="true" size={15} />离线模式 · 正在使用本地数据</div> : null}
    {refreshError ? <div className="tm-hybrid-shell__offline" role="status"><span>{refreshError}</span><button onClick={() => void refreshReadyData(true)} type="button">重试刷新</button></div> : null}
    {mapWasActivated ? <MyMapBrowsePage
      MapSurface={NativeMapSurface}
      active={route.surface === 'map' && !premiumLayerOpen}
      controlOverlayRevision={`roulette:${rouletteCandidates.length}:${showRouletteCandidates}`}
      onAddRestaurant={() => void navigate({ surface: 'add' })}
      onOpenRestaurant={(restaurantID) => void navigate({ surface: 'restaurant', id: restaurantID })}
      platform={platform}
      profile={profile}
      forYouRecommendations={content.discovery.forYou}
      recommendationSnapshotGeneratedAt={content.generatedAt}
    /> : null}
    {discoveryWasActivated ? <HybridDiscoveryPage
      profile={profile}
      onOpenPremium={() => void navigate({ surface: 'premium' })}
      onAddRestaurant={() => void navigate({ surface: 'add' })}
      candidateRestaurantIDs={rouletteRestaurantIDs}
      active={route.surface === 'discovery' || route.surface === 'activity'}
      content={content}
      onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })}
      onOpenRoulette={(id) => void openDiscoveryRoulette(id)}
      onRecordVisit={openDiscoveryVisit}
      platform={platform}
      loading={!contentReady}
      loadError={contentReadError}
      onRetry={() => void refreshReadyData(true)}
    /> : null}
    {profileWasActivated ? <div className="tm-hybrid-persistent-route" hidden={route.surface !== 'profile'}>
      <ProfilePage
        memoryProfile={profile}
        memoryPlatform={platform}
        connections={<p>用户搜索仍由原生主路径承载。</p>}
        followerConnections={<p>粉丝列表仍由原生主路径承载。</p>}
        followerCount={profile.followerCount}
        followingConnections={<p>关注列表仍由原生主路径承载。</p>}
        followingCount={profile.followingCount}
        listCount={contentReady ? content.lists.filter((item) => item.isOwnedByViewer).length : undefined}
        listsPreview={<HybridProfileListsPreview
          lists={content.lists}
          loading={!contentReady}
          onCreate={() => void platform.navigation.openNative({ route: 'listManage' })}
          onOpenList={(id) => void navigate({ surface: 'lists', id })}
        />}
        onDeleteAccount={() => void platform.account.openDelete()}
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
              <HybridBackButton onBack={() => void navigateBack()} />
              <RestaurantPreviewCard
                recommendationPlatform={platform}
                contentImage={detailRestaurant.contentImage}
                contentImageResolution={detailRestaurant.contentImageResolution}
                showCloseButton={false}
                additionalUserPhotos={detailRestaurant.restaurant.visits.flatMap((visit) => visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index] })))}
                historyRestaurants={profile.restaurants}
                isInRoulette={rouletteRestaurantIDs.includes(detailRestaurant.restaurant.id)}
                onAddToRoulette={detailRestaurant.capabilities.canAddToRoulette ? () => toggleDetailRoulette(detailRestaurant) : undefined}
                onAddToList={detailRestaurant.capabilities.canAddToList ? () => void openNativeRoute(platform, 'restaurantAddToList', detailRestaurant.restaurant.id) : undefined}
                onAddToWant={detailRestaurant.capabilities.canAddToWantToGo && detailRestaurant.viewerState !== 'visited' ? () => void toggleDetailCollection(detailRestaurant) : undefined}
                onAddVisit={detailRestaurant.capabilities.canRecordVisit ? () => void navigate({ surface: 'visit', id: detailRestaurant.restaurant.id }) : undefined}
                onClose={() => void navigateBack()}
                onDelete={detailRestaurant.capabilities.canDeleteRestaurant ? () => requestRestaurantDeletion(detailRestaurant.restaurant.id) : undefined}
                onEdit={detailRestaurant.capabilities.canEditRestaurant ? () => void openNativeRoute(platform, 'restaurantEdit', detailRestaurant.restaurant.id) : undefined}
                onEditVisit={(visit) => void navigate({ surface: 'visitEdit', id: visit.id })}
                onEditAvatar={detailRestaurant.capabilities.canEditRestaurant ? () => {
                  void platform.haptics.selection()
                  setAvatarEditorOpen(true)
                } : undefined}
                onShare={detailRestaurant.capabilities.canShare ? () => void platform.share.open({ title: detailRestaurant.restaurant.name, text: `${detailRestaurant.restaurant.name} · ${detailRestaurant.restaurant.address}` }) : undefined}
                canEditVisit={(visit) => detailRestaurant.editableVisitIDs.includes(visit.id)}
                readOnly={!detailRestaurant.capabilities.canEditRestaurant && !detailRestaurant.capabilities.canDeleteRestaurant}
                remoteStatsEnabled={false}
                restaurant={detailRestaurant.restaurant}
                socialStats={detailRestaurant.socialStats}
                viewerStatus={detailRestaurant.viewerState === 'none' ? null : detailRestaurant.viewerState === 'visited' ? 'visited' : 'wantToGo'}
              />
            </main>
          : <main className="tm-hybrid-page"><HybridBackButton onBack={() => void navigateBack()} /><HybridState kind={routeError ? 'error' : 'loading'} title={routeError ? '无法读取餐厅详情' : '正在读取餐厅详情'} message={routeError ?? '请稍候…'} action={routeError ? <button onClick={() => setDetailRevision((value) => value + 1)} type="button">重试</button> : undefined} /></main>
        : route.surface === 'add'
          ? <HybridAddRestaurantPage onBack={() => void navigateBack()} onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} />
        : route.surface === 'visit' || route.surface === 'visitEdit'
          ? <HybridVisitEditorPage
              membershipTier={profile.user.membershipTier}
              onClose={() => { visitParentRoute.current = null; void navigateBack() }}
              onRestaurantDeleted={(restaurantID) => {
                visitParentRoute.current = null
                deletedRestaurantRoutes.current.add(restaurantDetailIdentityKey(restaurantID))
                for (const [key, detail] of restaurantDetailCache.current) {
                  if (sameRestaurantID(detail.restaurant.id, restaurantID)) deletedRestaurantRoutes.current.add(key)
                }
                restaurantDetailCache.current.clear()
                setRestaurant(null)
                setRouletteRestaurantIDs((ids) => ids.filter((id) => !sameRestaurantID(id, restaurantID)))
                void refreshReadyData()
                // Native emits completedAction=restaurantDelete and owns stack
                // cleanup. Do not back again or override a newer destination.
                if (platform.kind !== 'native' && routeHash(currentRouteRef.current) === routeHash(route)) navigate({ surface: 'map' }, true)
              }}
              onSaved={(restaurantID) => {
                deletedRestaurantRoutes.current.delete(restaurantDetailIdentityKey(restaurantID))
                const parentRoute = visitParentRoute.current
                visitParentRoute.current = null
                setDetailRevision((value) => value + 1)
                void refreshReadyData()
                if (parentRoute) {
                  // Complete the editor's existing history entry. Pushing a
                  // second Detail would make its Back action reopen the editor.
                  void navigateBack()
                } else {
                  const destination: HybridRoute = { surface: 'restaurant', id: restaurantID }
                  navigate(destination, true)
                }
              }}
              platform={platform}
              restaurantID={route.surface === 'visit' ? route.id : undefined}
              restaurants={profile.restaurants}
              visitID={route.surface === 'visitEdit' ? route.id : undefined}
              visits={profile.visits}
              sourceDetail={route.surface === 'visitEdit' ? restaurant : undefined}
            />
        : route.surface === 'lists' || route.surface === 'publicList'
          ? <TasteMapListsPage initialSelectedID={route.id} lists={content.lists} onBack={() => void navigateBack()} onInitialDetailBack={() => void (route.surface === 'lists' ? returnFromProfileList() : navigateBack())} onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} />
        : route.surface === 'roulette'
          ? <RestaurantRoulette
              onClose={() => void navigateBack()}
              onSelectRestaurant={(item) => void navigate({ surface: 'restaurant', id: item.id })}
              onSessionStateChange={setRouletteSession}
              onSelectedRestaurantIdsChange={setRouletteRestaurantIDs}
              onTemporaryItemsChange={setRouletteTemporaryItems}
              restaurants={rouletteRestaurants}
              sessionState={rouletteSession}
              selectedRestaurantIds={rouletteRestaurantIDs}
              temporaryItems={rouletteTemporaryItems}
            />
        : route.surface === 'analytics'
          ? <TasteMapAnalyticsPage initialMode={analyticsMode(route.id)} onBack={() => void navigateBack()} onOpenRestaurant={(id) => void navigate({ surface: 'restaurant', id })} platform={platform} profile={profile} singleReport />
        : route.surface === 'premium'
          ? <TasteMapPremiumPage onBack={() => void navigateBack()} platform={platform} />
        : route.surface === 'settings'
          ? route.id === 'directory' ? <TasteMapDirectoryPage platform={platform} onBack={()=>void navigateBack()}/> : route.id === 'referrals'
            ? <TasteMapReferralPage platform={platform} onBack={()=>void navigateBack()}/>
            : <TasteMapSettingsPage onBack={() => void navigateBack()} onOpenDirectory={()=>void navigate({surface:'settings',id:'directory'})} onOpenReferral={()=>void navigate({surface:'settings',id:'referrals'})} onOpenPremium={() => void navigate({ surface: 'premium' })} platform={platform} profile={profile} />
        : <NativePrimaryHandoff route={route} onBack={() => navigate({ surface: 'profile' })} />}
    {route.surface === 'map' || route.surface === 'discovery' ? <RouletteCandidateDock
      candidates={rouletteCandidates}
      expanded={showRouletteCandidates}
      onClear={clearRouletteCandidates}
      onExpandedChange={setShowRouletteCandidates}
      onOpen={() => void navigate({ surface: 'roulette' })}
      onRemove={removeRouletteCandidate}
    /> : null}
    {avatarEditorOpen && detailRestaurant ? <RestaurantAvatarEditorSheet
      detail={detailRestaurant}
      onClose={() => setAvatarEditorOpen(false)}
      onSaved={async (next) => {
        restaurantDetailCache.current.set(restaurantDetailIdentityKey(next.restaurant.id), next)
        restaurantDetailCache.current.set(restaurantDetailIdentityKey(detailRestaurant.restaurant.id), next)
        setRestaurant(next)
        await refreshReadyData()
      }}
      platform={platform}
    /> : null}
    {premiumLayerOpen ? <PremiumReturnLayer onClose={() => setPremiumLayerOpen(false)}><TasteMapPremiumPage platform={platform} onBack={() => { setPremiumLayerOpen(false); void refreshReadyData(true) }} /></PremiumReturnLayer> : null}
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
  </div></PremiumAccessBoundary>
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
  return restaurantDetailIdentityKey(left) === restaurantDetailIdentityKey(right)
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
  if (route.surface === 'acquisitionNative'
    || route.surface === 'listManage'
    || route.surface === 'premiumStore'
    || route.surface === 'settingsNative'
    || route.surface === 'socialNative'
    || route.surface === 'accountSettings'
    || route.surface === 'dataBackup'
    || route.surface === 'dataClear'
    || route.surface === 'privacySettings'
    || route.surface === 'permissions'
    || route.surface === 'storage'
    || route.surface === 'helpSettings'
    || route.surface === 'aboutSettings'
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
