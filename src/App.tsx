import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import {
  CheckCircle2,
  Globe2,
  List,
  Map as MapIcon,
  MapPin,
  PanelLeftClose,
  PanelLeftOpen,
  Plus,
  Search,
  SlidersHorizontal,
  Sparkles,
  Utensils,
  UserRound,
} from 'lucide-react'
import { AddRestaurantModal } from './components/AddRestaurantModal'
import { AddVisitModal } from './components/AddVisitModal'
import { ConfirmDeleteModal } from './components/ConfirmDeleteModal'
import { MapView } from './components/MapView'
import { RestaurantEditorModal } from './components/RestaurantEditorModal'
import {
  RestaurantFilters,
  type DiningModeFilter,
  type DiningOccasionFilter,
  type PriceRangeFilter,
  type QueueFilter,
  type RecommendationSourceFilter,
  type ScoreBandFilter,
  type VisitPeriodFilter,
  type VisitCountFilter,
} from './components/RestaurantFilters'
import { RestaurantList } from './components/RestaurantList'
import { RestaurantPreviewCard } from './components/RestaurantPreviewCard'
import { SettingsModal } from './components/SettingsModal'
import { CommunityPage } from './components/CommunityPage'
import { FriendsPage } from './components/FriendsPage'
import { ProfilePage } from './components/ProfilePage'
import { RestaurantRoulette } from './components/RestaurantRoulette'
import { TasteFootprints } from './components/TasteFootprints'
import { CLOUD_SYNC_ENABLED, IS_DEVELOPMENT } from './config/appEnvironment'
import { db } from './db/appDb'
import {
  addRestaurantFromPoi,
  addVisit,
  deleteRestaurant,
  updateRestaurantBasics,
  updateVisit,
  type AddRestaurantInput,
  type AddVisitInput,
  type RestaurantBasicsUpdate,
} from './db/restaurants'
import { seedSixtyVisitedRestaurants } from './db/seedRestaurants'
import { CURRENT_USER_ID, ensureCurrentUser, setSharedMealInvitationStatus, updateCurrentUserMapPrivacy, updateCurrentUserProfile, upsertFriendship } from './db/social'
import { fetchTasteRecommendations } from './services/recommendations'
import { initializeCloudSync } from './services/cloudSync'
import { useCloudSync } from './services/useCloudSync'
import { initializePhotoSync } from './services/photoSync'
import { fetchUserProfile } from './services/socialApi'
import {
  queueDurationApproximateMinutes,
  scoreBandFromScore,
  type RestaurantStatus,
  type RestaurantSummary,
  type SharedMealParticipant,
  type UserProfile,
  type Visit,
} from './types/domain'

type ActiveList = RestaurantStatus | 'recommended' | 'footprints'
type ActiveView = 'map' | 'community' | 'profile'

export default function App() {
  const restaurants = useLiveQuery(
    () => db.restaurants.orderBy('createdAt').reverse().filter((restaurant) => !restaurant.deletedAt).toArray(),
    [],
  )
  const visits = useLiveQuery(() => db.visits.filter((visit) => !visit.deletedAt).toArray(), [])
  const users = useLiveQuery(() => db.users.filter((user) => !user.deletedAt).toArray(), [])
  const friendships = useLiveQuery(() => db.friendships.toArray(), [])
  const sharedMeals = useLiveQuery(() => db.sharedMeals.filter((meal) => !meal.deletedAt).toArray(), [])
  const sharedMealParticipants = useLiveQuery(() => db.sharedMealParticipants.toArray(), [])
  const cloudSyncState = useCloudSync()
  const [query, setQuery] = useState('')
  const [activeView, setActiveView] = useState<ActiveView>('map')
  const [viewedProfile, setViewedProfile] = useState<{ user: UserProfile; restaurants: RestaurantSummary[] } | null>(null)
  const [activeList, setActiveList] = useState<ActiveList>('visited')
  const [visitCountFilter, setVisitCountFilter] = useState<VisitCountFilter>('all')
  const [scoreBandFilter, setScoreBandFilter] = useState<ScoreBandFilter>('all')
  const [queueFilter, setQueueFilter] = useState<QueueFilter>('all')
  const [diningModeFilter, setDiningModeFilter] = useState<DiningModeFilter>('all')
  const [diningOccasionFilter, setDiningOccasionFilter] = useState<DiningOccasionFilter>('all')
  const [recommendationSourceFilter, setRecommendationSourceFilter] = useState<RecommendationSourceFilter>('all')
  const [priceRangeFilter, setPriceRangeFilter] = useState<PriceRangeFilter>('all')
  const [visitPeriodFilter, setVisitPeriodFilter] = useState<VisitPeriodFilter>('all')
  const [companionFilter, setCompanionFilter] = useState('all')
  const [tagFilter, setTagFilter] = useState('all')
  const [cityFilter, setCityFilter] = useState('all')
  const [showFilters, setShowFilters] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [showAddModal, setShowAddModal] = useState(false)
  const [showEditor, setShowEditor] = useState(false)
  const [showAddVisit, setShowAddVisit] = useState(false)
  const [editingVisit, setEditingVisit] = useState<Visit | null>(null)
  const [acceptedMealParticipant, setAcceptedMealParticipant] = useState<SharedMealParticipant | null>(null)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [showRoulette, setShowRoulette] = useState(false)
  const [isSidebarOpen, setIsSidebarOpen] = useState(false)
  const [toast, setToast] = useState('')
  const [recommendations, setRecommendations] = useState<RestaurantSummary[]>([])
  const [recommendationsLoading, setRecommendationsLoading] = useState(false)
  const [recommendationError, setRecommendationError] = useState('')
  const searchInputRef = useRef<HTMLInputElement>(null)

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
  const tagOptions = useMemo(
    () => [...new Set(allRestaurants.flatMap((restaurant) => restaurant.tags).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')),
    [allRestaurants],
  )
  const cityOptions = useMemo(
    () => [...new Set(allRestaurants.map((restaurant) => restaurant.city).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')),
    [allRestaurants],
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
    () =>
      allRestaurants.map((restaurant) => {
        const restaurantVisits = visitsByRestaurant.get(restaurant.id) ?? []
        const ratedVisits = restaurantVisits.filter((visit) => visit.rating !== null)
        const pricedVisits = restaurantVisits.filter((visit) => visit.pricePerPerson !== null)
        const queuedVisits = restaurantVisits
          .map((visit) => queueDurationApproximateMinutes(visit.queueDuration))
          .filter((minutes): minutes is number => minutes !== null)
        const averageRating = ratedVisits.length
          ? Math.round((ratedVisits.reduce((sum, visit) => sum + (visit.rating ?? 0), 0) / ratedVisits.length) * 10) / 10
          : null
        const averagePricePerPerson = pricedVisits.length
          ? Math.round(pricedVisits.reduce((sum, visit) => sum + (visit.pricePerPerson ?? 0), 0) / pricedVisits.length)
          : restaurant.pricePerPerson ?? null
        const averageQueueMinutes = queuedVisits.length
          ? queuedVisits.reduce((sum, minutes) => sum + minutes, 0) / queuedVisits.length
          : null
        return {
          ...restaurant,
          markerType: restaurant.markerType || 'emoji',
          markerImageData: restaurant.markerImageData ?? null,
          markerPhotoId: restaurant.markerPhotoId ?? null,
          merchantImageUrl: restaurant.merchantImageUrl ?? null,
          markerEmoji: restaurant.markerEmoji || '🍽️',
          pricePerPerson: restaurant.pricePerPerson ?? null,
          visitCount: restaurantVisits.length,
          averageRating,
          scoreOutOfTen: restaurant.overallRating ?? (averageRating !== null ? Math.round(averageRating * 20) / 10 : null),
          latestVisitDate: restaurantVisits[0]?.visitedAt ?? null,
          latestVisit: restaurantVisits[0] ?? null,
          visits: restaurantVisits,
          averagePricePerPerson,
          averageQueueMinutes,
        }
      }),
    [allRestaurants, visitsByRestaurant],
  )

  const selectedRestaurant = summaries.find((item) => item.id === selectedId)
    ?? recommendations.find((item) => item.id === selectedId)
  const listCounts = useMemo(
    () => ({
      visited: summaries.filter((restaurant) => restaurant.status === 'visited').length,
      wantToGo: summaries.filter((restaurant) => restaurant.status === 'wantToGo').length,
      recommended: recommendations.length,
      footprints: summaries.reduce((count, restaurant) => count + restaurant.visits.length, 0),
    }),
    [recommendations.length, summaries],
  )

  const visibleRestaurants = useMemo(() => {
    if (activeList === 'footprints') {
      return summaries.filter((restaurant) => restaurant.status === 'visited').sort(compareRestaurantQuality)
    }
    const normalizedQuery = query.trim().toLocaleLowerCase('zh-CN')
    const source = activeList === 'recommended' ? recommendations : summaries
    const filtered = source.filter((restaurant) => {
      if (activeList !== 'recommended' && restaurant.status !== activeList) return false
      if (activeList === 'visited' && !matchesVisitCount(restaurant.visitCount, visitCountFilter)) return false
      if (
        activeList !== 'recommended' &&
        scoreBandFilter !== 'all' &&
        scoreBandFromScore(restaurant.scoreOutOfTen) !== scoreBandFilter
      ) return false
      if (activeList !== 'recommended' && cityFilter !== 'all' && restaurant.city !== cityFilter) return false
      if (activeList !== 'recommended' && tagFilter !== 'all' && !restaurant.tags.includes(tagFilter)) return false
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
        ...restaurant.tags,
        ...relatedVisits.flatMap((visit) => [
          visit.note,
          ...visit.companions,
          ...visit.dishes.flatMap((dish) => [dish.name, dish.taste]),
        ]),
      ].some((value) => value.toLocaleLowerCase('zh-CN').includes(normalizedQuery))
    })
    return activeList === 'recommended' ? filtered : filtered.sort(compareRestaurantQuality)
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
    recommendations,
    summaries,
    tagFilter,
    visitCountFilter,
    visitPeriodFilter,
    visitsByRestaurant,
  ])

  const existingRestaurantsByPoiId = useMemo(
    () => new Map(summaries.map((restaurant) => [restaurant.amapPoiId, restaurant])),
    [summaries],
  )
  const activeFilterCount = activeList === 'recommended' || activeList === 'footprints'
    ? 0
    : (scoreBandFilter !== 'all' ? 1 : 0) +
      (cityFilter !== 'all' ? 1 : 0) +
      (tagFilter !== 'all' ? 1 : 0) +
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
    if (!IS_DEVELOPMENT) return
    if (requestedFromUrl) {
      parameters.delete('addSampleRestaurants')
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

  const handleSelect = useCallback((restaurant: RestaurantSummary) => {
    setActiveView('map')
    setSelectedId(restaurant.id)
    setShowFilters(false)
    setIsSidebarOpen(false)
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
    if (list === 'recommended' || list === 'footprints') {
      setScoreBandFilter('all')
      setTagFilter('all')
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

  function openNewVisit() {
    setEditingVisit(null)
    setAcceptedMealParticipant(null)
    setShowAddVisit(true)
  }

  function acceptMealInvitation(participant: SharedMealParticipant, restaurant: RestaurantSummary) {
    setActiveView('map')
    setSelectedId(restaurant.id)
    setEditingVisit(null)
    setAcceptedMealParticipant(participant)
    setShowAddVisit(true)
  }

  async function viewUserProfile(user: UserProfile) {
    setActiveView('profile')
    if (user.id === CURRENT_USER_ID) {
      setViewedProfile(null)
      return
    }
    const remote = await fetchUserProfile(user.id).catch(() => null)
    setViewedProfile(remote ?? { user, restaurants: [] })
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
        merchantImageUrl: selectedRestaurant.merchantImageUrl,
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

  function handleRecordExisting(restaurant: RestaurantSummary) {
    setSelectedId(restaurant.id)
    setShowAddModal(false)
    setEditingVisit(null)
    setShowAddVisit(true)
  }

  function resetFilters() {
    setVisitCountFilter('all')
    setScoreBandFilter('all')
    setQueueFilter('all')
    setDiningModeFilter('all')
    setDiningOccasionFilter('all')
    setRecommendationSourceFilter('all')
    setPriceRangeFilter('all')
    setVisitPeriodFilter('all')
    setCompanionFilter('all')
    setTagFilter('all')
    setCityFilter('all')
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark"><Utensils size={18} /></span>
          <div><strong>Taste Map</strong><span>我的私人美食地图</span></div>
          {IS_DEVELOPMENT ? <span className="environment-badge" title="当前使用 food-map-dev 测试数据库">🧪 测试环境</span> : null}
        </div>
      </header>

      {activeView === 'map' ? <section className={`workspace${isSidebarOpen ? '' : ' is-sidebar-collapsed'}${selectedRestaurant ? ' has-selection' : ''}`}>
        <aside aria-label="我的美食清单" className={`sidebar${isSidebarOpen ? '' : ' is-collapsed'}${showFilters && isSidebarOpen ? ' has-open-filters' : ''}`}>
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
            <label className="search-box"><Search size={17} /><input aria-label="搜索我的餐厅" onChange={(event) => setQuery(event.target.value)} placeholder="搜索餐厅、标签、饭搭子" ref={searchInputRef} value={query} /><kbd>⌘ K</kbd></label>
            {activeList !== 'recommended' ? <button className={`filter-toggle${showFilters ? ' is-active' : ''}`} aria-label="筛选餐厅" onClick={() => setShowFilters((current) => !current)} type="button"><SlidersHorizontal size={17} />{activeFilterCount ? <b>{activeFilterCount}</b> : null}</button> : null}
          </div> : null}

          {showFilters ? (
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
              onTagChange={setTagFilter}
              onVisitCountChange={setVisitCountFilter}
              queueDuration={queueFilter}
              scoreBand={scoreBandFilter}
              showVisitCount={activeList === 'visited'}
              tag={tagFilter}
              tagOptions={tagOptions}
              visitCount={visitCountFilter}
            />
          ) : null}

          {activeList === 'footprints' ? (
            <div className="restaurant-list footprints-list"><TasteFootprints onSelectRestaurant={handleSelect} restaurants={summaries.filter((restaurant) => restaurant.status === 'visited')} /></div>
          ) : <>
            <div className="list-result-line"><span>{activeList === 'visited' ? '去过' : activeList === 'wantToGo' ? '想去' : '根据你的口味推荐'}</span><strong>{visibleRestaurants.length} 家</strong></div>
            <RestaurantList
            activeList={activeList}
            emptyMessage={activeList === 'recommended' ? recommendationError : undefined}
            isLoading={restaurants === undefined || visits === undefined || (activeList === 'recommended' && recommendationsLoading)}
            onAdd={() => setShowAddModal(true)}
            onSelect={handleSelect}
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
          <MapView currentUser={currentUser} onClearSelection={() => setSelectedId(null)} onSelect={handleSelect} restaurants={visibleRestaurants} selectedRestaurant={selectedRestaurant} />
          {selectedRestaurant ? <RestaurantPreviewCard onAddVisit={openNewVisit} onClose={() => setSelectedId(null)} onDelete={() => setShowDeleteConfirm(true)} onEdit={() => setShowEditor(true)} onEditVisit={(visit) => { setEditingVisit(visit); setShowAddVisit(true) }} onSaveRecommendation={handleSaveRecommendation} restaurant={selectedRestaurant} /> : null}
        </section>
        {!isSidebarOpen ? <CollectionTabs activeList={activeList} className="map-collection-tabs" counts={listCounts} onChoose={chooseList} /> : null}
        <button className="map-view-mode-toggle" onClick={toggleMapList} type="button">{isSidebarOpen ? <MapIcon size={17} /> : <List size={17} />}{isSidebarOpen ? '查看地图' : '查看列表'}</button>
      </section> : activeView === 'profile' && (viewedProfile?.user ?? currentUser) ? (
        <ProfilePage
          cloudSyncState={cloudSyncState}
          connections={!viewedProfile ? <FriendsPage
            currentUserId={CURRENT_USER_ID}
            embedded
            friendships={allFriendships}
            onAcceptMeal={acceptMealInvitation}
            onDeclineMeal={(participant) => void setSharedMealInvitationStatus(participant.id, 'declined')}
            onFriendshipChange={(friendship) => void upsertFriendship(friendship)}
            onViewProfile={(user) => void viewUserProfile(user)}
            participants={sharedMealParticipants ?? []}
            restaurants={summaries}
            sharedMeals={sharedMeals ?? []}
            users={allUsers}
          /> : null}
          editable={!viewedProfile}
          onMapPrivacyChange={updateCurrentUserMapPrivacy}
          onOpenRoulette={() => setShowRoulette(true)}
          onOpenSettings={() => setShowSettings(true)}
          onSave={updateCurrentUserProfile}
          user={(viewedProfile?.user ?? currentUser) as UserProfile}
        />
      ) : (
        <CommunityPage onSelectRestaurant={handleSelect} onViewProfile={(user) => void viewUserProfile(user)} restaurants={summaries} users={allUsers} />
      )}

      <nav aria-label="主要功能" className="bottom-navigation">
        <button className={activeView === 'map' ? 'is-active' : ''} onClick={() => setActiveView('map')} type="button"><MapIcon size={18} /><span>地图</span></button>
        <button className={activeView === 'community' ? 'is-active' : ''} onClick={() => setActiveView('community')} type="button"><Globe2 size={18} /><span>社区</span></button>
        <button aria-label="添加餐厅" className="bottom-navigation__add" onClick={() => setShowAddModal(true)} type="button"><Plus size={21} /><span>添加餐厅</span></button>
        <button className={`bottom-navigation__profile${activeView === 'profile' && !viewedProfile ? ' is-active' : ''}`} onClick={() => { setViewedProfile(null); setActiveView('profile') }} type="button"><UserRound size={18} /><span>我的</span></button>
      </nav>

      {showAddModal ? <AddRestaurantModal companionOptions={companionOptions} existingRestaurantsByPoiId={existingRestaurantsByPoiId} friendOptions={friendOptions} onAdd={handleAdd} onClose={() => setShowAddModal(false)} onRecordExisting={handleRecordExisting} /> : null}
      {showEditor && selectedRestaurant ? <RestaurantEditorModal onClose={() => setShowEditor(false)} onSave={handleSave} restaurant={selectedRestaurant} /> : null}
      {showAddVisit && selectedRestaurant ? <AddVisitModal companionOptions={companionOptions} friendOptions={friendOptions} initialVisit={editingVisit ?? undefined} key={editingVisit?.id ?? acceptedMealParticipant?.id ?? 'new-visit'} onClose={() => { setShowAddVisit(false); setEditingVisit(null); setAcceptedMealParticipant(null) }} onSave={editingVisit ? handleUpdateVisit : handleAddVisit} restaurant={selectedRestaurant} /> : null}
      {showDeleteConfirm && selectedRestaurant ? <ConfirmDeleteModal onCancel={() => setShowDeleteConfirm(false)} onConfirm={handleDelete} restaurantName={selectedRestaurant.name} visitCount={selectedRestaurant.visitCount} /> : null}
      {showSettings ? <SettingsModal onClose={() => setShowSettings(false)} onImported={(message) => { setSelectedId(null); setToast(message) }} restaurantCount={summaries.length} visitCount={allVisits.length} /> : null}
      {showRoulette ? <RestaurantRoulette onClose={() => setShowRoulette(false)} onSelectRestaurant={handleSelect} restaurants={summaries} /> : null}
      {toast ? <div className="toast" role="status"><CheckCircle2 size={17} /> {toast}</div> : null}
    </main>
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
    <button className={activeList === 'visited' ? 'is-active' : ''} onClick={() => onChoose('visited')} type="button"><span>我去过的</span><strong>{counts.visited}</strong></button>
    <button className={activeList === 'wantToGo' ? 'is-active' : ''} onClick={() => onChoose('wantToGo')} type="button"><span>我想去的</span><strong>{counts.wantToGo}</strong></button>
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
