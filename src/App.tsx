import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { PremiumAccessBoundary } from './components/PremiumAccess'
import { restaurantCityFilterOptions } from './services/restaurantCity'
import { useLiveQuery } from 'dexie-react-hooks'
import {
  Bookmark,
  CheckCircle2,
  Globe2,
  List,
  Map as MapIcon,
  MapPin,
  PanelLeftClose,
  PanelLeftOpen,
  Search,
  SlidersHorizontal,
  Sparkles,
  UserRound,
  X,
} from 'lucide-react'
import { AddRestaurantModal } from './components/AddRestaurantModal'
import { AddVisitModal } from './components/AddVisitModal'
import { ConfirmDeleteModal } from './components/ConfirmDeleteModal'
import { MapView } from './components/MapView'
import { MapRestaurantGroupSheet, MyMapBrowsePage, resolveMapGroupRestaurants } from './components/MyMapBrowsePage'
import { BrowserMapSurface } from './components/BrowserMapSurface'
import { HybridBackButton } from './components/TasteMapHybridShared'
import { RestaurantEditorModal } from './components/RestaurantEditorModal'
import {
  RestaurantFilters,
  type DiningModeFilter,
  type DiningOccasionFilter,
  type PriceRangeFilter,
  type QueueFilter,
  type RecommendationSourceFilter,
  type RecommendationDistanceFilter,
  type RecommendationSortFilter,
  type ScoreBandFilter,
  type VisitPeriodFilter,
  type VisitCountFilter,
} from './components/RestaurantFilters'
import { RestaurantList } from './components/RestaurantList'
import { RestaurantPreviewCard } from './components/RestaurantPreviewCard'
import { SettingsModal } from './components/SettingsModal'
import { CommunityPage } from './components/CommunityPage'
import { FriendsPage } from './components/FriendsPage'
import { AccountPrivacyPage, ProfilePage, type AccountSettingsSection } from './components/ProfilePage'
import { RestaurantRoulette, type RouletteTemporaryCandidate } from './components/RestaurantRoulette'
import { RouletteCandidateDock } from './components/RouletteCandidateDock'
import { TasteFootprints } from './components/TasteFootprints'
import { PublicRestaurantListRoute } from './components/RestaurantListsPanel'
import { PremiumBurgerBadge } from './components/PremiumBurgerBadge'
import { TasteMapVisitedIcon } from './components/TasteMapStatusIcons'
import { PremiumPaywallHost } from './components/PremiumPaywall'
import { TasteMapAnalyticsPage, type AnalyticsMode } from './components/TasteMapAnalyticsPage'
import { TasteMapListsPage } from './components/TasteMapListsPage'
import { TasteMapPremiumPage, TasteMapSettingsPage } from './components/TasteMapPremiumSettingsPages'
import { openPremiumPaywall } from './services/premiumPaywall'
import { CLOUD_SYNC_ENABLED, IS_DEVELOPMENT, LOCAL_TEST_ACCOUNT } from './config/appEnvironment'
import { db } from './db/appDb'
import {
  addRestaurantFromPoi,
  addVisit,
  deleteRestaurant,
  deleteVisit,
  updateRestaurantBasics,
  updateVisit,
  type AddRestaurantInput,
  type AddVisitInput,
  type RestaurantBasicsUpdate,
} from './db/restaurants'
import { seedSixtyVisitedRestaurants } from './db/seedRestaurants'
import { CURRENT_USER_ID, ensureCurrentUser, setSharedMealInvitationStatus, updateCurrentUserMapPrivacy, updateCurrentUserProfile, upsertFriendship } from './db/social'
import { fetchTasteRecommendations } from './services/recommendations'
import { mapService } from './services/mapService'
import { initializeCloudSync } from './services/cloudSync'
import { useCloudSync } from './services/useCloudSync'
import { initializePhotoSync } from './services/photoSync'
import { fetchFollows, fetchFriendRecommendations, fetchUserProfile, sendFriendRequest, setFollow, type DiscoveryMode, type FriendRecommendation } from './services/socialApi'
import {
  scoreBandFromScore,
  type RestaurantStatus,
  type RestaurantSummary,
  type SharedMealParticipant,
  type Follow,
  type Coordinates,
  type PoiSearchResult,
  type UserProfile,
  type Visit,
} from './types/domain'
import { buildRestaurantSummaries } from './services/restaurantSummaryProjection'
import { visitPhotoLimit } from './services/featurePolicy'
import { buildRecommendationEmptyState, candidateCentroid, distanceKilometers, resolveRecommendationFilters, sameCity, type RelaxationSuggestion } from './services/recommendationFilterResolver'
import { MEMBERSHIP_CHANGED_EVENT, MembershipService } from './services/membershipService'
import { TasteMapBrowserAdapter } from './platform/TasteMapBrowserAdapter'
import type { TasteMapHybridListDTO, TasteMapProfileDashboardViewModel } from './platform/TasteMapPlatform'

type ActiveList = RestaurantStatus | 'recommended' | 'footprints'
type ActiveView = 'map' | 'community' | 'profile'
const FRIEND_RECOMMENDATION_DISMISSALS_KEY = 'taste-map:friend-recommendations:dismissed'
const EXPLICIT_TEST_DATA = IS_DEVELOPMENT && (() => {
  const parameters = new URLSearchParams(window.location.search)
  return parameters.get('testData') === '1' || parameters.get('testAccount') === 'free'
})()

function switchTestAccount(account: 'premium' | 'free') {
  const url = new URL(window.location.href)
  if (account === 'free') url.searchParams.set('testAccount', 'free')
  else url.searchParams.delete('testAccount')
  window.location.assign(url.toString())
}

export default function App() {
  const browserPlatform = useMemo(() => new TasteMapBrowserAdapter(), [])
  const restaurants = useLiveQuery(
    () => db.restaurants.orderBy('createdAt').reverse().filter((restaurant) =>
      !restaurant.deletedAt
      && restaurant.userId === CURRENT_USER_ID
      && (EXPLICIT_TEST_DATA || !restaurant.isTestData)).toArray(),
    [],
  )
  const visits = useLiveQuery(() => db.visits.filter((visit) => !visit.deletedAt && visit.userId === CURRENT_USER_ID).toArray(), [])
  const users = useLiveQuery(() => db.users.filter((user) => !user.deletedAt).toArray(), [])
  const friendships = useLiveQuery(() => db.friendships.toArray(), [])
  const sharedMeals = useLiveQuery(() => db.sharedMeals.filter((meal) => !meal.deletedAt).toArray(), [])
  const sharedMealParticipants = useLiveQuery(() => db.sharedMealParticipants.toArray(), [])
  const diningCompanions = useLiveQuery(() => db.diningCompanions.filter((companion) => !companion.deletedAt).toArray(), [])
  const cloudSyncState = useCloudSync()
  const [query, setQuery] = useState('')
  const [activeView, setActiveView] = useState<ActiveView>('map')
  const [communityMode, setCommunityMode] = useState<DiscoveryMode>('for_you')
  const [profileReturnView, setProfileReturnView] = useState<ActiveView>('profile')
  const [viewedProfile, setViewedProfile] = useState<{ user: UserProfile; restaurants: RestaurantSummary[]; followerCount: number; followingCount: number; followers: UserProfile[]; following: UserProfile[] } | null>(null)
  const [activeList, setActiveList] = useState<ActiveList>('visited')
  const [visitCountFilter, setVisitCountFilter] = useState<VisitCountFilter>('all')
  const [scoreBandFilter, setScoreBandFilter] = useState<ScoreBandFilter>([])
  const [queueFilter, setQueueFilter] = useState<QueueFilter>('all')
  const [diningModeFilter, setDiningModeFilter] = useState<DiningModeFilter>('all')
  const [diningOccasionFilter, setDiningOccasionFilter] = useState<DiningOccasionFilter>('all')
  const [recommendationSourceFilter, setRecommendationSourceFilter] = useState<RecommendationSourceFilter>('all')
  const [priceRangeFilter, setPriceRangeFilter] = useState<PriceRangeFilter>('all')
  const [visitPeriodFilter, setVisitPeriodFilter] = useState<VisitPeriodFilter>('all')
  const [companionFilter, setCompanionFilter] = useState('all')
  const [cityFilter, setCityFilter] = useState('all')
  const [recommendationDistanceFilter, setRecommendationDistanceFilter] = useState<RecommendationDistanceFilter>('all')
  const [recommendationSortFilter, setRecommendationSortFilter] = useState<RecommendationSortFilter>('recommended')
  const [recommendationCoordinates, setRecommendationCoordinates] = useState<Coordinates | null>(null)
  const [recommendationLocationStatus, setRecommendationLocationStatus] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle')
  const [recommendationDistanceAnchor, setRecommendationDistanceAnchor] = useState<'device' | 'city' | null>(null)
  const [recommendationAnchorKey, setRecommendationAnchorKey] = useState('')
  const [showFilters, setShowFilters] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [selectedMapGroupIDs, setSelectedMapGroupIDs] = useState<string[]>([])
  const [showAddModal, setShowAddModal] = useState(false)
  const [showEditor, setShowEditor] = useState(false)
  const [showAddVisit, setShowAddVisit] = useState(false)
  const [editingVisit, setEditingVisit] = useState<Visit | null>(null)
  const [acceptedMealParticipant, setAcceptedMealParticipant] = useState<SharedMealParticipant | null>(null)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [settingsDataSection, setSettingsDataSection] = useState<'all' | 'sync' | 'storage' | 'export' | 'import'>('all')
  const [settingsAccountSection, setSettingsAccountSection] = useState<AccountSettingsSection | null>(null)
  const [showRoulette, setShowRoulette] = useState(false)
  const [rouletteRestaurantIds, setRouletteRestaurantIds] = useState<string[]>([])
  const [rouletteTemporaryItems, setRouletteTemporaryItems] = useState<RouletteTemporaryCandidate[]>([])
  const [rouletteRestaurantSnapshots, setRouletteRestaurantSnapshots] = useState<RestaurantSummary[]>([])
  const [showRouletteCandidates, setShowRouletteCandidates] = useState(false)
  const [sharedAnalyticsMode, setSharedAnalyticsMode] = useState<AnalyticsMode | null>(null)
  const [sharedAnalyticsProfile, setSharedAnalyticsProfile] = useState<TasteMapProfileDashboardViewModel | null>(null)
  const [sharedLists, setSharedLists] = useState<TasteMapHybridListDTO[] | null>(null)
  const [sharedSettingsProfile, setSharedSettingsProfile] = useState<TasteMapProfileDashboardViewModel | null>(null)
  const [sharedPremiumOpen, setSharedPremiumOpen] = useState(false)
  const [standaloneRestaurant, setStandaloneRestaurant] = useState<RestaurantSummary | null>(null)
  const [isSidebarOpen, setIsSidebarOpen] = useState(false)
  const [toast, setToast] = useState('')
  const [recommendations, setRecommendations] = useState<RestaurantSummary[]>([])
  const [recommendationsLoading, setRecommendationsLoading] = useState(false)
  const [recommendationError, setRecommendationError] = useState('')
  const [cloudFollows, setCloudFollows] = useState<Follow[]>([])
  const [followPending, setFollowPending] = useState(false)
  const [friendPending, setFriendPending] = useState(false)
  const [friendRecommendations, setFriendRecommendations] = useState<FriendRecommendation[]>([])
  const [recommendationPendingIds, setRecommendationPendingIds] = useState<Set<string>>(() => new Set())
  const [dismissedRecommendationIds, setDismissedRecommendationIds] = useState<Set<string>>(() => {
    try { return new Set(JSON.parse(window.sessionStorage.getItem(FRIEND_RECOMMENDATION_DISMISSALS_KEY) ?? '[]') as string[]) }
    catch { return new Set() }
  })
  const searchInputRef = useRef<HTMLInputElement>(null)
  const profileReturnScrollRef = useRef(0)

  const openSharedAnalytics = useCallback(async (mode: AnalyticsMode) => {
    const profile = await browserPlatform.profile.getCurrent()
    setSharedAnalyticsProfile(profile)
    setSharedAnalyticsMode(mode)
  }, [browserPlatform])

  const openSharedLists = useCallback(async () => {
    const content = await browserPlatform.content.snapshot()
    setSharedLists(content.lists)
  }, [browserPlatform])

  const openSharedSettings = useCallback(async () => {
    setSharedSettingsProfile(await browserPlatform.profile.getCurrent())
  }, [browserPlatform])

  const allRestaurants = useMemo(() => restaurants ?? [], [restaurants])
  const allVisits = useMemo(() => visits ?? [], [visits])
  const allUsers = useMemo(() => users ?? [], [users])
  const allFriendships = useMemo(() => friendships ?? [], [friendships])
  const currentUser = allUsers.find((user) => user.id === CURRENT_USER_ID)
  const friendOptions = useMemo(() => {
    const userById = new Map(allUsers.map((user) => [user.id, user]))
    return allFriendships.flatMap((friendship) => {
      if (friendship.status !== 'accepted') return []
      const otherId = friendship.requesterId === CURRENT_USER_ID ? friendship.addresseeId : friendship.addresseeId === CURRENT_USER_ID ? friendship.requesterId : null
      const user = otherId ? userById.get(otherId) : undefined
      return user ? [{ id: user.id, nickname: user.nickname }] : []
    })
  }, [allFriendships, allUsers])
  const followingCount = cloudFollows.filter((item) => item.followerId === CURRENT_USER_ID).length
  const followerCount = cloudFollows.filter((item) => item.followedUserId === CURRENT_USER_ID).length
  const viewedFriendship = viewedProfile ? allFriendships.find((friendship) => friendship.status !== 'removed' && (
    (friendship.requesterId === CURRENT_USER_ID && friendship.addresseeId === viewedProfile.user.id)
    || (friendship.addresseeId === CURRENT_USER_ID && friendship.requesterId === viewedProfile.user.id)
  )) : undefined
  const companionOptions = useMemo(
    () => {
      const usageCounts = new Map<string, number>()
      allVisits.forEach((visit) => visit.companions.forEach((name) => {
        const normalizedName = name.trim()
        if (normalizedName) usageCounts.set(normalizedName, (usageCounts.get(normalizedName) ?? 0) + 1)
      }))
      return [...usageCounts]
        .sort(([nameA, countA], [nameB, countB]) => countB - countA || nameA.localeCompare(nameB, 'zh-CN'))
        .map(([name]) => name)
    },
    [allVisits],
  )
  const cityOptions = useMemo(
    () => restaurantCityFilterOptions((activeList === 'recommended'
      ? recommendations
      : allRestaurants.filter((restaurant) => activeList === 'footprints' || restaurant.status === activeList))
      .map((restaurant) => restaurant.city)),
    [activeList, allRestaurants, recommendations],
  )

  const visitsByRestaurant = useMemo(() => {
    const grouped = new Map<string, Visit[]>()
    allVisits.forEach((visit) => {
      const group = grouped.get(visit.restaurantId) ?? []
      group.push(visit)
      grouped.set(visit.restaurantId, group)
    })
    grouped.forEach((group) => group.sort((a, b) => b.visitedAt.localeCompare(a.visitedAt)))
    return grouped
  }, [allVisits])

  const summaries = useMemo<RestaurantSummary[]>(
    () => buildRestaurantSummaries(allRestaurants, allVisits, { development: IS_DEVELOPMENT }),
    [allRestaurants, allVisits],
  )

  useLayoutEffect(() => {
    if (!currentUser || !restaurants || !visits) return
    browserPlatform.acceptProfileSnapshot({
      user: currentUser, restaurants: summaries, visits: allVisits, followingCount, followerCount,
    })
  }, [allVisits, browserPlatform, currentUser, followerCount, followingCount, restaurants, summaries, visits])

  const selectedRestaurant = summaries.find((item) => item.id === selectedId)
    ?? recommendations.find((item) => item.id === selectedId)
  const rouletteRestaurantOptions = useMemo(() => {
    const byId = new Map(summaries.map((restaurant) => [restaurant.id, restaurant]))
    rouletteRestaurantSnapshots.forEach((restaurant) => { if (!byId.has(restaurant.id)) byId.set(restaurant.id, restaurant) })
    return [...byId.values()]
  }, [rouletteRestaurantSnapshots, summaries])
  const rouletteCandidates = useMemo(() => [
    ...rouletteRestaurantIds.flatMap((id) => {
      const restaurant = rouletteRestaurantOptions.find((item) => item.id === id)
      return restaurant ? [{ id, name: restaurant.name }] : []
    }),
    ...rouletteTemporaryItems,
  ], [rouletteRestaurantIds, rouletteRestaurantOptions, rouletteTemporaryItems])
  const listCounts = useMemo(
    () => ({
      visited: summaries.filter((restaurant) => restaurant.status === 'visited').length,
      wantToGo: summaries.filter((restaurant) => restaurant.status === 'wantToGo').length,
      recommended: recommendations.length,
      footprints: summaries.reduce((count, restaurant) => count + restaurant.visits.length, 0),
    }),
    [recommendations.length, summaries],
  )

  const recommendationFilterResolution = useMemo(() => resolveRecommendationFilters(
    recommendations,
    {
      city: cityFilter === 'all' ? null : cityFilter,
      distanceKm: recommendationDistanceFilter === 'all' ? null : Number(recommendationDistanceFilter),
      scoreBands: scoreBandFilter,
    },
    recommendationCoordinates,
  ), [cityFilter, recommendationCoordinates, recommendationDistanceFilter, recommendations, scoreBandFilter])
  const recommendationEmptyState = useMemo(() => buildRecommendationEmptyState(recommendationFilterResolution.relaxationSuggestion, recommendationFilterResolution.emptyReason, recommendationError), [recommendationError, recommendationFilterResolution.emptyReason, recommendationFilterResolution.relaxationSuggestion])

  const visibleRestaurants = useMemo(() => {
    if (activeList === 'footprints') {
      return summaries.filter((restaurant) => restaurant.status === 'visited').sort(compareRestaurantQuality)
    }
    const normalizedQuery = query.trim().toLocaleLowerCase('zh-CN')
    const source = activeList === 'recommended' ? recommendationFilterResolution.results : summaries
    const filtered = source.filter((restaurant) => {
      if (activeList !== 'recommended' && restaurant.status !== activeList) return false
      if (activeList === 'visited' && !matchesVisitCount(restaurant.visitCount, visitCountFilter)) return false
      if (activeList !== 'recommended' && scoreBandFilter.length > 0 && !scoreBandFilter.some((band) => band === scoreBandFromScore(restaurant.scoreOutOfTen))) return false
      if (activeList !== 'recommended' && cityFilter !== 'all' && !sameCity(restaurant.city, cityFilter)) return false
      const relatedVisits = visitsByRestaurant.get(restaurant.id) ?? []
      if (
        activeList === 'visited' &&
        (
          queueFilter !== 'all' ||
          companionFilter !== 'all' ||
          diningModeFilter !== 'all' ||
          diningOccasionFilter !== 'all' ||
          recommendationSourceFilter !== 'all' ||
          priceRangeFilter !== 'all' ||
          visitPeriodFilter !== 'all'
        ) &&
        !relatedVisits.some(
          (visit) =>
            matchesQueueDuration(visit.queueDuration, queueFilter) &&
            (companionFilter === 'all' || visit.companions.includes(companionFilter)) &&
            (diningModeFilter === 'all' || (visit.diningMode ?? 'dine_in') === diningModeFilter) &&
            (diningOccasionFilter === 'all' || visit.diningOccasions?.includes(diningOccasionFilter) || visit.diningOccasion === diningOccasionFilter) &&
            (recommendationSourceFilter === 'all' || visit.recommendationSourceType === recommendationSourceFilter) &&
            matchesPriceRange(visit.pricePerPerson, priceRangeFilter) &&
            matchesVisitPeriod(visit.visitedAt, visitPeriodFilter),
        )
      ) return false
      if (!normalizedQuery) return true
      return [
        restaurant.name,
        restaurant.city,
        restaurant.address,
        restaurant.longTermNote,
        ...relatedVisits.flatMap((visit) => [
          visit.note,
          ...visit.companions,
          ...visit.dishes.flatMap((dish) => [dish.name, dish.taste]),
        ]),
      ].some((value) => value.toLocaleLowerCase('zh-CN').includes(normalizedQuery))
    })
    if (activeList === 'recommended') {
      if (recommendationSortFilter === 'rating') return [...filtered].sort((left, right) => (right.scoreOutOfTen ?? 0) - (left.scoreOutOfTen ?? 0))
      if (recommendationSortFilter === 'nearest' && recommendationCoordinates) return [...filtered].sort((left, right) => distanceKilometers(recommendationCoordinates, left) - distanceKilometers(recommendationCoordinates, right))
      return filtered
    }
    return filtered.sort(compareRestaurantQuality)
  }, [
    activeList,
    cityFilter,
    companionFilter,
    diningModeFilter,
    diningOccasionFilter,
    priceRangeFilter,
    query,
    queueFilter,
    recommendationSourceFilter,
    scoreBandFilter,
    recommendationFilterResolution,
    recommendationCoordinates,
    recommendationSortFilter,
    summaries,
    visitCountFilter,
    visitPeriodFilter,
    visitsByRestaurant,
  ])

  const existingRestaurantsByPoiId = useMemo(
    () => new Map(summaries.map((restaurant) => [restaurant.amapPoiId, restaurant])),
    [summaries],
  )
  const activeFilterCount = activeList === 'footprints'
    ? 0
    : activeList === 'recommended'
      ? recommendationFilterResolution.activeFilters.length
      : (scoreBandFilter.length ? 1 : 0) +
      (cityFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && visitCountFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && queueFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && companionFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && diningModeFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && diningOccasionFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && recommendationSourceFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && priceRangeFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && visitPeriodFilter !== 'all' ? 1 : 0)

  useEffect(() => {
    void ensureCurrentUser()
  }, [])

  useEffect(() => {
    let active = true
    const refreshMembership = async () => {
      try {
        const result = await MembershipService.getEntitlement()
        if (!active) return
        const user = await ensureCurrentUser()
        const membershipTier = result.entitlement.isPremium ? 'member' : 'free'
        if (user.membershipTier !== membershipTier) await db.users.put({ ...user, membershipTier, updatedAt: new Date().toISOString() })
      } catch {
        // Local development remains usable when the Worker is not running.
      }
    }
    void refreshMembership()
    window.addEventListener(MEMBERSHIP_CHANGED_EVENT, refreshMembership)
    return () => {
      active = false
      window.removeEventListener(MEMBERSHIP_CHANGED_EVENT, refreshMembership)
    }
  }, [])

  useEffect(() => {
    let cleanup: (() => void) | undefined
    let disposed = false
    initializeCloudSync().then((dispose) => {
      if (disposed) dispose()
      else cleanup = dispose
    })
    return () => {
      disposed = true
      cleanup?.()
    }
  }, [])

  useEffect(() => {
    let cleanup: (() => void) | undefined
    let disposed = false
    initializePhotoSync().then((dispose) => {
      if (disposed) dispose()
      else cleanup = dispose
    })
    return () => {
      disposed = true
      cleanup?.()
    }
  }, [])

  useEffect(() => {
    const parameters = new URLSearchParams(window.location.search)
    const requestedFromUrl = parameters.get('addSampleRestaurants') === '60'
    // Demo records are a deliberate developer action, never an automatic
    // consequence of launching a normal Debug build.
    if (!IS_DEVELOPMENT || !requestedFromUrl) return
    if (requestedFromUrl) {
      parameters.delete('addSampleRestaurants')
      parameters.set('testData', '1')
      const cleanUrl = `${window.location.pathname}${parameters.size ? `?${parameters}` : ''}${window.location.hash}`
      window.history.replaceState(null, '', cleanUrl)
    }
    seedSixtyVisitedRestaurants()
      .then((addedCount) => {
        setActiveList('visited')
        setSelectedId(null)
        if (requestedFromUrl && addedCount) setToast(`已新增 ${addedCount} 家餐厅`)
        else if (requestedFromUrl) setToast('这 60 家餐厅已经添加过了')
      })
      .catch((seedError) => {
        setToast(seedError instanceof Error ? seedError.message : '批量添加失败')
      })
  }, [])

  useEffect(() => {
    let active = true
    void Promise.all([fetchFollows(), fetchFriendRecommendations()]).then(([follows, friendSuggestions]) => {
      if (!active) return
      setCloudFollows(follows)
      setFriendRecommendations(friendSuggestions)
    }).catch(() => undefined)
    return () => { active = false }
  }, [cloudSyncState.lastSuccessfulSyncAt])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        searchInputRef.current?.focus()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [])

  useEffect(() => {
    if (!toast) return
    const timeout = window.setTimeout(() => setToast(''), 2600)
    return () => window.clearTimeout(timeout)
  }, [toast])

  useEffect(() => {
    if (activeList !== 'recommended') return
    let active = true
    setRecommendationsLoading(true)
    setRecommendationError('')
    fetchTasteRecommendations(summaries)
      .then((items) => {
        if (active) setRecommendations(items)
      })
      .catch((error) => {
        if (!active) return
        setRecommendations([])
        setRecommendationError(error instanceof Error ? error.message : '推荐加载失败，请稍后再试。')
      })
      .finally(() => {
        if (active) setRecommendationsLoading(false)
      })
    return () => {
      active = false
    }
  }, [activeList, summaries])

  useEffect(() => {
    const needsLocation = activeList === 'recommended' && (recommendationDistanceFilter !== 'all' || recommendationSortFilter === 'nearest')
    const anchorKey = cityFilter === 'all' ? 'device' : `city:${cityFilter}`
    if (!needsLocation || (recommendationAnchorKey === anchorKey && recommendationCoordinates)) return
    let active = true
    setRecommendationLocationStatus('loading')
    const selectedCityCandidates = cityFilter === 'all' ? recommendations : recommendations.filter((item) => sameCity(item.city, cityFilter))
    void mapService.detectCurrentLocation()
      .then((location) => {
        if (!active) return
        const deviceMatchesCandidates = selectedCityCandidates.some((item) => sameCity(item.city, location.city))
        const canUseDevice = cityFilter === 'all' ? deviceMatchesCandidates : sameCity(location.city, cityFilter)
        const coordinates = canUseDevice ? location : candidateCentroid(selectedCityCandidates)
        if (!coordinates) throw new Error('没有可用的距离锚点')
        setRecommendationCoordinates(coordinates)
        setRecommendationDistanceAnchor(canUseDevice ? 'device' : 'city')
        setRecommendationAnchorKey(anchorKey)
        setRecommendationLocationStatus('ready')
      })
      .catch(() => {
        if (!active) return
        const fallback = candidateCentroid(selectedCityCandidates)
        if (fallback) {
          setRecommendationCoordinates(fallback)
          setRecommendationDistanceAnchor('city')
          setRecommendationAnchorKey(anchorKey)
          setRecommendationLocationStatus('ready')
        } else {
          setRecommendationCoordinates(null)
          setRecommendationDistanceAnchor(null)
          setRecommendationLocationStatus('error')
        }
      })
    return () => { active = false }
  }, [activeList, cityFilter, recommendationAnchorKey, recommendationCoordinates, recommendationDistanceFilter, recommendationSortFilter, recommendations])

  const handleSelect = useCallback((restaurant: RestaurantSummary) => {
    setActiveView('map')
    setSelectedId(restaurant.id)
    setShowFilters(false)
    setIsSidebarOpen(false)
  }, [])

  const handleListSelect = useCallback((restaurant: RestaurantSummary) => {
    setSelectedId(restaurant.id)
    setShowFilters(false)
    setIsSidebarOpen(true)
  }, [])

  const handleProfileListSelect = useCallback((restaurant: RestaurantSummary) => {
    setSelectedId(restaurant.id)
    setStandaloneRestaurant(restaurant)
  }, [])

  function chooseList(list: ActiveList) {
    setActiveList(list)
    setSelectedId(null)
    if (list !== 'visited') {
      setVisitCountFilter('all')
      setQueueFilter('all')
      setDiningModeFilter('all')
      setDiningOccasionFilter('all')
      setRecommendationSourceFilter('all')
      setPriceRangeFilter('all')
      setVisitPeriodFilter('all')
      setCompanionFilter('all')
    }
    if (list === 'footprints') {
      setScoreBandFilter([])
      setCityFilter('all')
      setShowFilters(false)
    }
  }

  function toggleMapList() {
    setSelectedId(null)
    if (isSidebarOpen && activeList === 'footprints') setActiveList('visited')
    setIsSidebarOpen((open) => !open)
  }

  async function handleAdd(input: AddRestaurantInput) {
    const restaurant = await addRestaurantFromPoi(input)
    setActiveList(restaurant.status)
    setSelectedId(restaurant.id)
    setShowAddModal(false)
    setToast(`${restaurant.name} 已添加到你的地图`)
  }

  async function handleSave(changes: RestaurantBasicsUpdate) {
    if (!selectedRestaurant) return
    await updateRestaurantBasics(selectedRestaurant.id, changes)
    setActiveList(changes.status)
    setShowEditor(false)
    setToast('餐厅信息已保存')
  }

  async function handleDelete() {
    if (!selectedRestaurant) return
    const name = selectedRestaurant.name
    await deleteRestaurant(selectedRestaurant.id)
    setStandaloneRestaurant((current) => current?.id === selectedRestaurant.id ? null : current)
    setSelectedId(null)
    setShowDeleteConfirm(false)
    setToast(`${name} 已从地图中删除`)
  }

  async function handleAddVisit(input: AddVisitInput) {
    if (!selectedRestaurant) return
    const visit = await addVisit(selectedRestaurant.id, input)
    if (acceptedMealParticipant) {
      await setSharedMealInvitationStatus(acceptedMealParticipant.id, 'accepted', visit.id)
    }
    setActiveList('visited')
    setShowAddVisit(false)
    setEditingVisit(null)
    setAcceptedMealParticipant(null)
    setToast('到访记录已保存')
  }

  async function handleUpdateVisit(input: AddVisitInput) {
    if (!editingVisit) return
    await updateVisit(editingVisit.id, input)
    setShowAddVisit(false)
    setEditingVisit(null)
    setToast('到访记录已更新')
  }

  async function handleDeleteVisit() {
    if (!editingVisit) return
    const result = await deleteVisit(editingVisit.id)
    setShowAddVisit(false)
    setEditingVisit(null)
    if (result.deletedRestaurantID) {
      setSelectedId(null)
      setStandaloneRestaurant((current) => current?.id === result.deletedRestaurantID ? null : current)
      setRouletteRestaurantIds((current) => current.filter((id) => id !== result.deletedRestaurantID))
    }
    setToast(result.deletedRestaurantID ? '最后一次到访及餐厅已删除' : '到访记录已删除')
  }

  function openNewVisit() {
    setEditingVisit(null)
    setAcceptedMealParticipant(null)
    setShowAddVisit(true)
  }

  async function openQuickVisit(restaurant: RestaurantSummary) {
    const existing = summaries.find((item) => item.id === restaurant.id || item.amapPoiId === restaurant.amapPoiId || (item.name === restaurant.name && item.address === restaurant.address))
    if (existing) {
      setSelectedId(existing.id)
      setEditingVisit(null)
      setShowAddVisit(true)
      return
    }
    const saved = await addRestaurantFromPoi({
      poi: {
        amapPoiId: restaurant.amapPoiId,
        name: restaurant.name,
        address: restaurant.address,
        city: restaurant.city,
        district: '',
        latitude: restaurant.latitude,
        longitude: restaurant.longitude,
        categoryHints: restaurant.tags,
        merchantImageUrl: restaurant.merchantImageUrl,
        phone: restaurant.phone ?? null,
        openingHours: restaurant.openingHours ?? null,
      },
      address: restaurant.address,
      status: 'visited',
      tags: restaurant.tags,
      pricePerPerson: restaurant.pricePerPerson,
      markerType: restaurant.merchantImageUrl ? 'image' : 'emoji',
      markerImageData: null,
      markerEmoji: restaurant.markerEmoji || '🍽️',
      initialVisit: null,
    })
    setSelectedId(saved.id)
    setEditingVisit(null)
    setShowAddVisit(true)
  }

  function addSelectedRestaurantToRoulette() {
    if (!selectedRestaurant) return
    toggleRouletteRestaurant(selectedRestaurant)
  }

  function toggleRouletteRestaurant(restaurant: RestaurantSummary) {
    if (rouletteRestaurantIds.includes(restaurant.id)) {
      setRouletteRestaurantIds((ids) => ids.filter((id) => id !== restaurant.id))
      setToast(`已从抽签中移除「${restaurant.name}」`)
      return
    }
    if (rouletteRestaurantIds.length + rouletteTemporaryItems.length >= 10) {
      setToast('最多选择 10 家餐厅')
      return
    }
    setRouletteRestaurantSnapshots((items) => items.some((item) => item.id === restaurant.id) ? items : [...items, restaurant])
    setRouletteRestaurantIds((ids) => [...ids, restaurant.id])
    setToast(`已加入「${restaurant.name}」 · ${rouletteRestaurantIds.length + rouletteTemporaryItems.length + 1}/10`)
  }

  function togglePoiRouletteCandidate(poi: PoiSearchResult) {
    const id = `temporary-poi-${poi.amapPoiId}`
    if (rouletteTemporaryItems.some((item) => item.id === id)) {
      setRouletteTemporaryItems((items) => items.filter((item) => item.id !== id))
      setToast(`已从抽签中移除「${poi.name}」`)
      return
    }
    if (rouletteRestaurantIds.length + rouletteTemporaryItems.length >= 10) {
      setToast('最多选择 10 家餐厅')
      return
    }
    setRouletteTemporaryItems((items) => [...items, { id, name: poi.name }])
    setToast(`已加入「${poi.name}」 · ${rouletteRestaurantIds.length + rouletteTemporaryItems.length + 1}/10`)
  }

  function removeRouletteCandidate(id: string) {
    if (id.startsWith('temporary-')) setRouletteTemporaryItems((items) => items.filter((item) => item.id !== id))
    else setRouletteRestaurantIds((ids) => ids.filter((item) => item !== id))
  }

  function clearRouletteCandidates() {
    setRouletteRestaurantIds([])
    setRouletteTemporaryItems([])
    setShowRouletteCandidates(false)
    setToast('抽签候选已清空')
  }

  function acceptMealInvitation(participant: SharedMealParticipant, restaurant: RestaurantSummary) {
    setActiveView('map')
    setSelectedId(restaurant.id)
    setEditingVisit(null)
    setAcceptedMealParticipant(participant)
    setShowAddVisit(true)
  }

  async function viewUserProfile(user: UserProfile) {
    profileReturnScrollRef.current = window.scrollY
    setProfileReturnView(activeView)
    setActiveView('profile')
    window.requestAnimationFrame(() => window.scrollTo({ top: 0, behavior: 'auto' }))
    if (user.id === CURRENT_USER_ID) {
      setViewedProfile(null)
      return
    }
    setViewedProfile({ user, restaurants: [], followerCount: 0, followingCount: 0, followers: [], following: [] })
    const remote = await fetchUserProfile(user.id).catch(() => null)
    setViewedProfile(remote ?? { user, restaurants: [], followerCount: 0, followingCount: 0, followers: [], following: [] })
  }

  function returnFromViewedProfile() {
    const returnView = profileReturnView
    const returnScroll = profileReturnScrollRef.current
    setViewedProfile(null)
    setActiveView(returnView)
    let attempts = 0
    const restoreScroll = () => {
      const maxScroll = Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
      if (maxScroll + 2 >= returnScroll || attempts >= 12) {
        window.scrollTo({ top: Math.min(returnScroll, maxScroll), behavior: 'auto' })
        return
      }
      attempts += 1
      window.setTimeout(restoreScroll, 100)
    }
    window.requestAnimationFrame(() => window.requestAnimationFrame(restoreScroll))
  }

  async function toggleViewedProfileFollow() {
    if (!viewedProfile || followPending) return
    const targetUserId = viewedProfile.user.id
    const currentlyFollowing = cloudFollows.some((follow) => follow.followerId === CURRENT_USER_ID && follow.followedUserId === targetUserId)
    setFollowPending(true)
    try {
      await setFollow(targetUserId, !currentlyFollowing)
      const nextFollows = await fetchFollows()
      setCloudFollows(nextFollows)
      setViewedProfile((current) => current && current.user.id === targetUserId ? {
        ...current,
        followerCount: Math.max(0, current.followerCount + (currentlyFollowing ? -1 : 1)),
      } : current)
      setToast(currentlyFollowing ? '已取消关注' : '已关注')
    } catch (error) {
      setToast(error instanceof Error ? error.message : '关注操作失败，请稍后重试')
    } finally {
      setFollowPending(false)
    }
  }

  async function requestViewedProfileFriendship() {
    if (!viewedProfile || friendPending) return
    setFriendPending(true)
    try {
      const friendship = await sendFriendRequest(viewedProfile.user.id)
      await upsertFriendship(friendship)
      setToast('好友申请已发送')
    } catch (error) {
      setToast(error instanceof Error ? error.message : '好友申请发送失败，请稍后重试')
    } finally {
      setFriendPending(false)
    }
  }

  async function requestRecommendedFriendship(userId: string) {
    if (recommendationPendingIds.has(userId)) return
    setRecommendationPendingIds((current) => new Set(current).add(userId))
    try {
      const friendship = await sendFriendRequest(userId)
      await upsertFriendship(friendship)
      setFriendRecommendations((current) => current.map((item) => item.user.id === userId ? { ...item, friendshipState: 'pending' } : item))
      setToast('好友申请已发送')
    } catch (error) {
      setToast(error instanceof Error ? error.message : '好友申请发送失败，请稍后重试')
    } finally {
      setRecommendationPendingIds((current) => { const next = new Set(current); next.delete(userId); return next })
    }
  }

  function dismissFriendRecommendation(userId: string) {
    setDismissedRecommendationIds((current) => {
      const next = new Set(current).add(userId)
      window.sessionStorage.setItem(FRIEND_RECOMMENDATION_DISMISSALS_KEY, JSON.stringify([...next]))
      return next
    })
  }

  async function handleSaveRecommendation() {
    if (!selectedRestaurant?.isRecommendation) return
    const saved = await addRestaurantFromPoi({
      poi: {
        amapPoiId: selectedRestaurant.amapPoiId,
        name: selectedRestaurant.name,
        address: selectedRestaurant.address,
        city: selectedRestaurant.city,
        district: '',
        latitude: selectedRestaurant.latitude,
        longitude: selectedRestaurant.longitude,
        categoryHints: selectedRestaurant.tags,
        merchantImageUrl: selectedRestaurant.merchantImageUrl,
        phone: selectedRestaurant.phone ?? null,
        openingHours: selectedRestaurant.openingHours ?? null,
      },
      address: selectedRestaurant.address,
      status: 'wantToGo',
      tags: selectedRestaurant.tags,
      pricePerPerson: null,
      markerType: selectedRestaurant.merchantImageUrl ? 'image' : 'emoji',
      markerImageData: null,
      markerEmoji: '🍽️',
      initialVisit: null,
    })
    setActiveList('wantToGo')
    setSelectedId(saved.id)
    setToast(`${saved.name} 已加入想去清单`)
  }

  async function handleToggleDiscoveryWant(restaurant: RestaurantSummary) {
    const existing = summaries.find((item) => item.id === restaurant.id || item.amapPoiId === restaurant.amapPoiId || (item.name === restaurant.name && item.address === restaurant.address))
    if (existing) {
      if (existing.status === 'visited') {
        setToast(`「${existing.name}」已经在去过清单里`)
        return
      }
      await deleteRestaurant(existing.id)
      if (selectedId === existing.id) setSelectedId(null)
      setToast(`「${existing.name}」已移出想吃`)
      return
    }
    const saved = await addRestaurantFromPoi({
      poi: {
        amapPoiId: restaurant.amapPoiId,
        name: restaurant.name,
        address: restaurant.address,
        city: restaurant.city,
        district: '',
        latitude: restaurant.latitude,
        longitude: restaurant.longitude,
        categoryHints: restaurant.tags,
        merchantImageUrl: restaurant.merchantImageUrl,
        phone: restaurant.phone ?? null,
        openingHours: restaurant.openingHours ?? null,
      },
      address: restaurant.address,
      status: 'wantToGo',
      tags: restaurant.tags,
      pricePerPerson: restaurant.pricePerPerson,
      markerType: restaurant.merchantImageUrl ? 'image' : 'emoji',
      markerImageData: null,
      markerEmoji: restaurant.markerEmoji || '🍽️',
      initialVisit: null,
    })
    setToast(`「${saved.name}」已加入想吃`)
  }

  function handleRecordExisting(restaurant: RestaurantSummary) {
    setSelectedId(restaurant.id)
    setShowAddModal(false)
    setEditingVisit(null)
    setShowAddVisit(true)
  }

  function resetFilters() {
    setVisitCountFilter('all')
    setScoreBandFilter([])
    setQueueFilter('all')
    setDiningModeFilter('all')
    setDiningOccasionFilter('all')
    setRecommendationSourceFilter('all')
    setPriceRangeFilter('all')
    setVisitPeriodFilter('all')
    setCompanionFilter('all')
    setCityFilter('all')
    setRecommendationDistanceFilter('all')
    setRecommendationSortFilter('recommended')
  }

  function applyRecommendationRelaxation(suggestion: RelaxationSuggestion) {
    if (suggestion.type === 'distance') setRecommendationDistanceFilter(suggestion.to === null ? 'all' : String(suggestion.to) as RecommendationDistanceFilter)
    if (suggestion.type === 'scoreBands') setScoreBandFilter(suggestion.to)
    if (suggestion.type === 'city') setCityFilter('all')
    setShowFilters(false)
  }

  const filtersPanel = activeList !== 'footprints' ? (
    <RestaurantFilters
      city={cityFilter}
      cityOptions={cityOptions}
      companion={companionFilter}
      companionOptions={companionOptions}
      diningMode={diningModeFilter}
      diningOccasion={diningOccasionFilter}
      onDiningModeChange={setDiningModeFilter}
      onDiningOccasionChange={setDiningOccasionFilter}
      onPriceRangeChange={setPriceRangeFilter}
      onRecommendationSourceChange={setRecommendationSourceFilter}
      onVisitPeriodChange={setVisitPeriodFilter}
      priceRange={priceRangeFilter}
      recommendationSource={recommendationSourceFilter}
      visitPeriod={visitPeriodFilter}
      onCityChange={setCityFilter}
      onClose={() => setShowFilters(false)}
      onCompanionChange={setCompanionFilter}
      onQueueDurationChange={setQueueFilter}
      onScoreBandChange={setScoreBandFilter}
      onReset={resetFilters}
      onVisitCountChange={setVisitCountFilter}
      queueDuration={queueFilter}
      scoreBand={scoreBandFilter}
      showVisitCount={activeList === 'visited'}
      isRecommendation={activeList === 'recommended'}
      recommendationDistance={recommendationDistanceFilter}
      recommendationSort={recommendationSortFilter}
      recommendationLocationStatus={recommendationLocationStatus}
      recommendationLocationLabel={recommendationDistanceAnchor === 'device' ? '已按当前位置计算距离' : `已按${cityFilter === 'all' ? '当前地图范围' : cityFilter}中心计算距离`}
      onRecommendationDistanceChange={(value) => {
        setRecommendationDistanceFilter(value)
        if (value !== 'all' && recommendationLocationStatus === 'error') setRecommendationLocationStatus('idle')
      }}
      onRecommendationSortChange={(value) => {
        setRecommendationSortFilter(value)
        if (value === 'nearest' && recommendationLocationStatus === 'error') setRecommendationLocationStatus('idle')
      }}
      visitCount={visitCountFilter}
    />
  ) : null

  const renderEmbeddedFriends = (embeddedView: 'discover' | 'following' | 'followers') => !viewedProfile ? <FriendsPage
    currentUserId={CURRENT_USER_ID}
    embedded
    embeddedView={embeddedView}
    follows={cloudFollows}
    friendships={allFriendships}
    onAcceptMeal={acceptMealInvitation}
    onDeclineMeal={(participant) => void setSharedMealInvitationStatus(participant.id, 'declined')}
    onFriendshipChange={(friendship) => void upsertFriendship(friendship)}
    onViewProfile={(user) => void viewUserProfile(user)}
    participants={sharedMealParticipants ?? []}
    restaurants={summaries}
    sharedMeals={sharedMeals ?? []}
    users={allUsers}
  /> : null

  return (
    <PremiumAccessBoundary key={currentUser?.id ?? 'guest'} ownerID={currentUser?.id ?? 'guest'} platform={browserPlatform} revision={currentUser?.membershipTier ?? 'free'}><main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark"><img alt="" aria-hidden="true" src="/icons/taste-map-icon-192.png" /></span>
          <div><strong>Taste Map</strong><span>我的私人美食地图</span></div>
          {IS_DEVELOPMENT ? <span className="environment-badge" title="当前使用 food-map-dev 测试数据库">🧪 测试环境</span> : null}
          {IS_DEVELOPMENT ? <div aria-label="切换测试账号" className="test-account-switcher">
            <button className={LOCAL_TEST_ACCOUNT === 'premium' ? 'is-active' : ''} onClick={() => switchTestAccount('premium')} type="button"><PremiumBurgerBadge className="is-inline" />会员</button>
            <button className={LOCAL_TEST_ACCOUNT === 'free' ? 'is-active' : ''} onClick={() => switchTestAccount('free')} type="button">非会员</button>
          </div> : null}
        </div>
      </header>

      {activeView === 'map' && currentUser ? <MyMapBrowsePage
        MapSurface={BrowserMapSurface}
        active
        onAddRestaurant={() => setShowAddModal(true)}
        onOpenRestaurant={(restaurantID) => {
          const restaurant = summaries.find((item) => item.id === restaurantID)
          if (restaurant) setStandaloneRestaurant(restaurant)
        }}
        platform={browserPlatform}
        profile={{ user: currentUser, restaurants: summaries, visits: allVisits, followerCount, followingCount, restaurantImages: {} }}
      /> : activeView === 'map' ? <section className={`workspace${isSidebarOpen ? '' : ' is-sidebar-collapsed'}${selectedRestaurant ? ' has-selection' : ''}`}>
        <aside aria-label="我的美食清单" className={`sidebar${isSidebarOpen ? '' : ' is-collapsed'}${showFilters && isSidebarOpen ? ' has-open-filters' : ''}${selectedRestaurant && isSidebarOpen ? ' has-detail' : ''}`}>
          {isSidebarOpen ? <>
            <div className="sidebar-heading">
              <div><span className="eyebrow">MY TASTE MAP</span><h1>我的美食清单</h1></div>
              <div className="sidebar-heading-actions">
                <span className="count-pill">{summaries.length}</span>
                <button aria-label="收起美食清单" className="sidebar-toggle" onClick={() => setIsSidebarOpen(false)} title="收起美食清单" type="button"><PanelLeftClose size={17} /></button>
              </div>
            </div>

          <CollectionTabs activeList={activeList} counts={listCounts} onChoose={chooseList} showFootprints />

          {activeList !== 'footprints' ? <div className="search-filter-row">
            <label className="search-box"><Search size={17} /><input aria-label="搜索我的餐厅" onChange={(event) => setQuery(event.target.value)} placeholder="搜索餐厅、城市、饭搭子" ref={searchInputRef} value={query} /><kbd>⌘ K</kbd></label>
            <button className={`filter-toggle${showFilters ? ' is-active' : ''}`} aria-label="筛选餐厅" onClick={() => setShowFilters((current) => !current)} type="button"><SlidersHorizontal size={17} />{activeFilterCount ? <b>{activeFilterCount}</b> : null}</button>
          </div> : null}

          {showFilters ? filtersPanel : null}

          {activeList === 'footprints' ? (
            <div className="restaurant-list footprints-list"><TasteFootprints onSelectRestaurant={handleListSelect} restaurants={summaries} visits={visits} user={currentUser} /></div>
          ) : <>
            <div className="list-result-line"><span>{activeList === 'visited' ? '去过' : activeList === 'wantToGo' ? '想去' : '根据你的口味推荐'}</span><strong>{visibleRestaurants.length} 家</strong></div>
            <RestaurantList
            activeList={activeList}
            emptyActionLabel={activeList === 'recommended' && !query ? recommendationEmptyState.actionLabel : undefined}
            emptyMessage={activeList === 'recommended' && !query ? recommendationEmptyState.message : activeList === 'recommended' ? recommendationError : undefined}
            emptyTitle={activeList === 'recommended' && !query ? recommendationEmptyState.title : undefined}
            isLoading={restaurants === undefined || visits === undefined || (activeList === 'recommended' && recommendationsLoading)}
            onAdd={() => setShowAddModal(true)}
            onAddToRoulette={toggleRouletteRestaurant}
            onAddToWant={(restaurant) => void handleToggleDiscoveryWant(restaurant)}
            onMarkVisited={(restaurant) => void openQuickVisit(restaurant)}
            onEmptyAction={recommendationFilterResolution.relaxationSuggestion ? () => applyRecommendationRelaxation(recommendationFilterResolution.relaxationSuggestion!) : undefined}
            onSelect={handleListSelect}
            query={query}
            restaurants={visibleRestaurants}
            selectedId={selectedRestaurant?.id}
            />
          </>}
            <footer className="local-data-note"><MapPin size={13} /> {CLOUD_SYNC_ENABLED ? '本地优先保存 · 自动云端同步' : '数据保存在当前隔离的本地环境'}</footer>
          </> : (
            <button aria-label="展开美食清单" className="sidebar-expand-button" onClick={() => setIsSidebarOpen(true)} title="展开美食清单" type="button"><PanelLeftOpen size={19} /><span>打开清单</span></button>
          )}
        </aside>

        <section className="map-panel" aria-label="私人美食地图">
          <MapView currentUser={currentUser} onClearSelection={() => setSelectedId(null)} onSelect={handleSelect} onSelectGroup={setSelectedMapGroupIDs} restaurants={visibleRestaurants} selectedRestaurant={selectedRestaurant} />
          {selectedMapGroupIDs.length ? createPortal(<MapRestaurantGroupSheet items={resolveMapGroupRestaurants(visibleRestaurants, selectedMapGroupIDs)} images={{}} scope={activeList === 'footprints' ? 'visited' : activeList} onClose={() => setSelectedMapGroupIDs([])} onOpen={(restaurant) => { setSelectedMapGroupIDs([]); handleSelect(restaurant) }} />, document.body) : null}
          {!isSidebarOpen && activeList !== 'footprints' ? <div className={`map-filter-control${showFilters ? ' is-open' : ''}`}>
            <button aria-expanded={showFilters} className={`map-filter-button${showFilters ? ' is-active' : ''}`} onClick={() => setShowFilters((current) => !current)} type="button"><SlidersHorizontal size={16} /><span>筛选</span>{activeFilterCount ? <b>{activeFilterCount}</b> : null}</button>
            {showFilters ? <div className="map-filters-popover">{filtersPanel}</div> : null}
          </div> : null}
          {selectedRestaurant && !isSidebarOpen ? <RestaurantPreviewCard historyRestaurants={[...summaries, ...recommendations]} isInRoulette={rouletteRestaurantIds.includes(selectedRestaurant.id)} onAddToRoulette={addSelectedRestaurantToRoulette} onAddToWant={() => void handleToggleDiscoveryWant(selectedRestaurant)} onAddVisit={openNewVisit} onClose={() => setSelectedId(null)} onDelete={selectedRestaurant.userId === CURRENT_USER_ID ? () => setShowDeleteConfirm(true) : undefined} onEdit={() => setShowEditor(true)} onEditVisit={(visit) => { setEditingVisit(visit); setShowAddVisit(true) }} onSaveRecommendation={handleSaveRecommendation} restaurant={selectedRestaurant} /> : null}
        </section>
        {!isSidebarOpen ? <CollectionTabs activeList={activeList} className="map-collection-tabs" counts={listCounts} onChoose={chooseList} /> : null}
        <button className="map-view-mode-toggle" onClick={toggleMapList} type="button">{isSidebarOpen ? <MapIcon size={17} /> : <List size={17} />}{isSidebarOpen ? '查看地图' : '查看列表'}</button>
      </section> : activeView === 'profile' && (viewedProfile?.user ?? currentUser) ? (
        <ProfilePage
          cloudSyncState={cloudSyncState}
          connections={renderEmbeddedFriends('discover')}
          diningCompanions={viewedProfile ? [] : (diningCompanions ?? [])}
          sourceUsers={allUsers}
          editable={!viewedProfile}
          followerConnections={renderEmbeddedFriends('followers')}
          followerCount={viewedProfile ? viewedProfile.followerCount : followerCount}
          publicFollowers={viewedProfile?.followers ?? []}
          publicFollowing={viewedProfile?.following ?? []}
          followPending={followPending}
          friendPending={friendPending}
          friendStatus={viewedFriendship?.status ?? null}
          friendRecommendations={viewedProfile ? [] : friendRecommendations.filter((item) => !dismissedRecommendationIds.has(item.user.id))}
          followingConnections={renderEmbeddedFriends('following')}
          followingCount={viewedProfile ? viewedProfile.followingCount : followingCount}
          isFollowing={Boolean(viewedProfile && cloudFollows.some((follow) => follow.followerId === CURRENT_USER_ID && follow.followedUserId === viewedProfile.user.id))}
          key={(viewedProfile?.user ?? currentUser)?.id ?? 'profile'}
          onMapPrivacyChange={updateCurrentUserMapPrivacy}
          onAddFriend={viewedProfile ? () => void requestViewedProfileFriendship() : undefined}
          onBack={viewedProfile ? returnFromViewedProfile : undefined}
          onDismissFriendRecommendation={viewedProfile ? undefined : dismissFriendRecommendation}
          onOpenRoulette={() => setShowRoulette(true)}
          onOpenAnalytics={(section) => void openSharedAnalytics(section)}
          onOpenLists={() => void openSharedLists()}
          onOpenSettings={() => void openSharedSettings()}
          onRequestRecommendationFriend={viewedProfile ? undefined : (userId) => void requestRecommendedFriendship(userId)}
          onSelectRestaurant={handleProfileListSelect}
          onSelectUser={viewedProfile ? (nextUser) => void viewUserProfile(nextUser) : undefined}
          onToggleFollow={viewedProfile ? () => void toggleViewedProfileFollow() : undefined}
          onSave={updateCurrentUserProfile}
          recommendationPendingIds={recommendationPendingIds}
          restaurants={viewedProfile?.restaurants ?? summaries}
          user={(viewedProfile?.user ?? currentUser) as UserProfile}
          viewerRestaurants={summaries}
          visits={viewedProfile ? viewedProfile.restaurants.flatMap((restaurant) => restaurant.visits) : allVisits}
        />
      ) : (
        <CommunityPage onAddRestaurant={() => setShowAddModal(true)} candidateRestaurantIds={rouletteRestaurantIds} mode={communityMode} onMarkVisited={(restaurant) => void openQuickVisit(restaurant)} onModeChange={setCommunityMode} onToggleCandidate={toggleRouletteRestaurant} onToggleWant={(restaurant) => void handleToggleDiscoveryWant(restaurant)} onViewProfile={(user) => void viewUserProfile(user)} restaurants={summaries} users={allUsers} />
      )}

      {activeView === 'map' && selectedRestaurant && isSidebarOpen ? <section className="app-restaurant-detail" aria-label={`${selectedRestaurant.name} 餐厅详情`}><HybridBackButton onBack={() => setSelectedId(null)} /><RestaurantPreviewCard showCloseButton={false} historyRestaurants={[...summaries, ...recommendations]} isInRoulette={rouletteRestaurantIds.includes(selectedRestaurant.id)} onAddToRoulette={addSelectedRestaurantToRoulette} onAddToWant={() => void handleToggleDiscoveryWant(selectedRestaurant)} onAddVisit={openNewVisit} onClose={() => setSelectedId(null)} onDelete={selectedRestaurant.userId === CURRENT_USER_ID ? () => setShowDeleteConfirm(true) : undefined} onEdit={() => setShowEditor(true)} onEditVisit={(visit) => { setEditingVisit(visit); setShowAddVisit(true) }} onSaveRecommendation={handleSaveRecommendation} restaurant={selectedRestaurant} /></section> : null}
      {standaloneRestaurant ? <section className="app-restaurant-detail" aria-label={`${standaloneRestaurant.name} 餐厅详情`}><HybridBackButton onBack={() => setStandaloneRestaurant(null)} /><RestaurantPreviewCard showCloseButton={false} historyRestaurants={[...summaries, ...recommendations]} isInRoulette={rouletteRestaurantIds.includes(standaloneRestaurant.id)} onAddToRoulette={() => toggleRouletteRestaurant(standaloneRestaurant)} onAddToWant={() => void handleToggleDiscoveryWant(standaloneRestaurant)} onAddVisit={() => void openQuickVisit(standaloneRestaurant).then(() => setStandaloneRestaurant(null))} onClose={() => setStandaloneRestaurant(null)} onDelete={standaloneRestaurant.userId === CURRENT_USER_ID ? () => { setSelectedId(standaloneRestaurant.id); setShowDeleteConfirm(true) } : undefined} onEdit={() => { setSelectedId(standaloneRestaurant.id); setShowEditor(true) }} onEditVisit={(visit) => { setSelectedId(standaloneRestaurant.id); setEditingVisit(visit); setShowAddVisit(true) }} onSaveRecommendation={() => void handleToggleDiscoveryWant(standaloneRestaurant)} restaurant={standaloneRestaurant} /></section> : null}

      {activeView === 'map' || activeView === 'community' ? <RouletteCandidateDock
        candidates={rouletteCandidates}
        expanded={showRouletteCandidates}
        onClear={clearRouletteCandidates}
        onExpandedChange={setShowRouletteCandidates}
        onOpen={() => setShowRoulette(true)}
        onRemove={removeRouletteCandidate}
      /> : null}

      <nav aria-label="主要功能" className="bottom-navigation" data-product-contract="bottom-navigation">
        <button className={activeView === 'map' && !isSidebarOpen ? 'is-active' : ''} onClick={() => { setActiveView('map'); setSelectedId(null); setIsSidebarOpen(false) }} type="button"><MapIcon size={18} /><span>地图</span></button>
        <button className={activeView === 'community' ? 'is-active' : ''} onClick={() => setActiveView('community')} type="button"><Globe2 size={18} /><span>发现</span></button>
        <button className={`bottom-navigation__profile${activeView === 'profile' && !viewedProfile ? ' is-active' : ''}`} onClick={() => { setViewedProfile(null); setActiveView('profile') }} type="button"><UserRound size={18} /><span>我的</span></button>
      </nav>

      {showAddModal ? <AddRestaurantModal key={currentUser?.id ?? 'signed-out'} companionOptions={companionOptions} existingRestaurantsByPoiId={existingRestaurantsByPoiId} friendOptions={friendOptions} historyRestaurants={[...summaries, ...recommendations]} isRouletteCandidate={(poi) => rouletteTemporaryItems.some((item) => item.id === `temporary-poi-${poi.amapPoiId}`)} canUploadDishPhotos={currentUser?.membershipTier === 'member'} maxPhotos={visitPhotoLimit(currentUser?.membershipTier ?? 'free')} onAdd={handleAdd} onClose={() => setShowAddModal(false)} onRecordExisting={handleRecordExisting} onToggleRoulette={togglePoiRouletteCandidate} photoUpgradeAvailable={(currentUser?.membershipTier ?? 'free') !== 'member'} /> : null}
      {showEditor && selectedRestaurant ? <RestaurantEditorModal onClose={() => setShowEditor(false)} onSave={handleSave} restaurant={selectedRestaurant} /> : null}
      {showAddVisit && selectedRestaurant ? <AddVisitModal companionOptions={companionOptions} friendOptions={friendOptions} initialVisit={editingVisit ?? undefined} key={editingVisit?.id ?? acceptedMealParticipant?.id ?? 'new-visit'} canUploadDishPhotos={currentUser?.membershipTier === 'member'} maxPhotos={visitPhotoLimit(currentUser?.membershipTier ?? 'free')} onClose={() => { setShowAddVisit(false); setEditingVisit(null); setAcceptedMealParticipant(null) }} onDelete={editingVisit ? handleDeleteVisit : undefined} onSave={editingVisit ? handleUpdateVisit : handleAddVisit} photoUpgradeAvailable={(currentUser?.membershipTier ?? 'free') !== 'member'} restaurant={selectedRestaurant} /> : null}
      {showDeleteConfirm && selectedRestaurant ? <ConfirmDeleteModal onCancel={() => setShowDeleteConfirm(false)} onConfirm={handleDelete} restaurantName={selectedRestaurant.name} visitCount={selectedRestaurant.visitCount} /> : null}
      {showSettings ? <SettingsModal membershipTier={currentUser?.membershipTier ?? 'free'} onClose={() => { setShowSettings(false); setSettingsDataSection('all') }} onImported={(message) => { setSelectedId(null); setToast(message) }} restaurantCount={summaries.length} section={settingsDataSection} visitCount={allVisits.length} /> : null}
      <PremiumPaywallHost membershipTier={currentUser?.membershipTier ?? 'free'} />
      {showRoulette ? <RestaurantRoulette onClose={() => setShowRoulette(false)} onSelectRestaurant={(restaurant) => { setShowRoulette(false); handleSelect(restaurant) }} onSelectedRestaurantIdsChange={setRouletteRestaurantIds} onTemporaryItemsChange={setRouletteTemporaryItems} restaurants={rouletteRestaurantOptions} selectedRestaurantIds={rouletteRestaurantIds} temporaryItems={rouletteTemporaryItems} /> : null}
      {sharedAnalyticsMode && sharedAnalyticsProfile ? <section aria-label="数据分析" className="app-shared-surface-overlay"><button aria-label="关闭数据分析" className="app-shared-surface-overlay__close" onClick={() => { setSharedAnalyticsMode(null); setSharedAnalyticsProfile(null) }} type="button"><X size={18} />关闭</button><TasteMapAnalyticsPage initialMode={sharedAnalyticsMode} onOpenRestaurant={(restaurantID) => { const value = summaries.find((item) => item.id === restaurantID); if (value) { setSharedAnalyticsMode(null); setSharedAnalyticsProfile(null); setStandaloneRestaurant(value) } }} platform={browserPlatform} profile={sharedAnalyticsProfile} /></section> : null}
      {sharedLists ? <section aria-label="我的食单" className="app-shared-surface-overlay"><button aria-label="关闭我的食单" className="app-shared-surface-overlay__close" onClick={() => setSharedLists(null)} type="button"><X size={18} />关闭</button><TasteMapListsPage lists={sharedLists} onOpenRestaurant={(restaurantID) => { const value = summaries.find((item) => item.id === restaurantID); if (value) { setSharedLists(null); setStandaloneRestaurant(value) } }} platform={browserPlatform} /></section> : null}
      {sharedSettingsProfile ? <section aria-label="设置" className="app-shared-surface-overlay"><button aria-label="关闭设置" className="app-shared-surface-overlay__close" onClick={() => { setSharedSettingsProfile(null); setSettingsAccountSection(null) }} type="button"><X size={18} />关闭</button>{settingsAccountSection ? <AccountPrivacyPage onBack={() => setSettingsAccountSection(null)} onMapPrivacyChange={updateCurrentUserMapPrivacy} onOpenSettings={() => { setSettingsDataSection('all'); setShowSettings(true) }} onSave={updateCurrentUserProfile} section={settingsAccountSection} user={currentUser ?? sharedSettingsProfile.user} /> : <TasteMapSettingsPage onOpenNativeSettings={({ route, identifier }) => {
        if (route === 'dataBackup' || route === 'storage') {
          setSettingsDataSection(route === 'storage' ? 'storage' : identifier === 'sync' || identifier === 'export' || identifier === 'import' ? identifier : 'all')
          setShowSettings(true)
          return
        }
        const sections: Partial<Record<typeof route, AccountSettingsSection>> = { accountSettings: 'account', privacySettings: 'privacy', permissions: 'permissions', helpSettings: 'help', aboutSettings: 'about' }
        const section = sections[route]
        if (!section) throw new Error('当前浏览器不支持此操作。')
        setSettingsAccountSection(section)
      }} onOpenPremium={() => setSharedPremiumOpen(true)} platform={browserPlatform} profile={{ ...sharedSettingsProfile, user: currentUser ?? sharedSettingsProfile.user }} />}</section> : null}
      {sharedPremiumOpen ? <section aria-label="Premium" className="app-shared-surface-overlay"><button aria-label="关闭 Premium" className="app-shared-surface-overlay__close" onClick={() => setSharedPremiumOpen(false)} type="button"><X size={18} />关闭</button><TasteMapPremiumPage onOpenStore={() => openPremiumPaywall('settings_entry')} platform={browserPlatform} /></section> : null}
      <PublicRestaurantListRoute onSelectRestaurant={handleProfileListSelect} restaurants={summaries} />
      {toast ? <div className="toast" role="status"><CheckCircle2 size={17} /> {toast}</div> : null}
    </main></PremiumAccessBoundary>
  )
}

function CollectionTabs({
  activeList,
  counts,
  onChoose,
  className = '',
  showFootprints = false,
}: {
  activeList: ActiveList
  counts: Record<ActiveList, number>
  onChoose: (list: ActiveList) => void
  className?: string
  showFootprints?: boolean
}) {
  return <div className={`collection-tabs${showFootprints ? ' has-footprints' : ''}${className ? ` ${className}` : ''}`} aria-label="餐厅列表分类">
    <button className={activeList === 'visited' ? 'is-active' : ''} onClick={() => onChoose('visited')} type="button"><span><TasteMapVisitedIcon size={11} /> 去过</span><strong>{counts.visited}</strong></button>
    <button className={activeList === 'wantToGo' ? 'is-active' : ''} onClick={() => onChoose('wantToGo')} type="button"><span><Bookmark size={11} /> 想吃</span><strong>{counts.wantToGo}</strong></button>
    <button className={activeList === 'recommended' ? 'is-active' : ''} onClick={() => onChoose('recommended')} type="button"><span><Sparkles size={11} /> 推荐</span><strong>{counts.recommended}</strong></button>
    {showFootprints ? <button className={activeList === 'footprints' ? 'is-active' : ''} onClick={() => onChoose('footprints')} type="button"><span>味觉足迹</span><strong>{counts.footprints}</strong></button> : null}
  </div>
}

function matchesVisitCount(count: number, filter: VisitCountFilter) {
  if (filter === 'all') return true
  return count >= Number(filter)
}

function compareRestaurantQuality(a: RestaurantSummary, b: RestaurantSummary) {
  return (
    (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1) ||
    b.visitCount - a.visitCount ||
    b.latestVisitDate?.localeCompare(a.latestVisitDate ?? '') ||
    b.createdAt.localeCompare(a.createdAt)
  )
}

function matchesQueueDuration(queueDuration: Visit['queueDuration'], filter: QueueFilter) {
  if (filter === 'all') return true
  if (filter === 'unrecorded') return queueDuration === null
  return queueDuration === filter
}

function matchesPriceRange(price: number | null, filter: PriceRangeFilter) {
  if (filter === 'all') return true
  if (price === null) return false
  if (filter === 'under100') return price < 100
  if (filter === '100to200') return price >= 100 && price <= 200
  return price > 200
}

function matchesVisitPeriod(visitedAt: string, filter: VisitPeriodFilter) {
  if (filter === 'all') return true
  const cutoff = new Date()
  cutoff.setMonth(cutoff.getMonth() - (filter === 'sixMonths' ? 6 : 12))
  return new Date(visitedAt) >= cutoff
}
