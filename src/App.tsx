import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import {
  CheckCircle2,
  MapPin,
  Plus,
  Search,
  Settings,
  SlidersHorizontal,
  Sparkles,
  Utensils,
} from 'lucide-react'
import { AddRestaurantModal } from './components/AddRestaurantModal'
import { AddVisitModal } from './components/AddVisitModal'
import { ConfirmDeleteModal } from './components/ConfirmDeleteModal'
import { MapView } from './components/MapView'
import { RestaurantEditorModal } from './components/RestaurantEditorModal'
import {
  RestaurantFilters,
  type QueueFilter,
  type ScoreBandFilter,
  type VisitCountFilter,
} from './components/RestaurantFilters'
import { RestaurantList } from './components/RestaurantList'
import { RestaurantPreviewCard } from './components/RestaurantPreviewCard'
import { SettingsModal } from './components/SettingsModal'
import { db } from './db/appDb'
import {
  addRestaurantFromPoi,
  addVisit,
  deleteRestaurant,
  updateRestaurantBasics,
  type AddRestaurantInput,
  type AddVisitInput,
  type RestaurantBasicsUpdate,
} from './db/restaurants'
import { seedSixtyVisitedRestaurants } from './db/seedRestaurants'
import {
  queueDurationApproximateMinutes,
  scoreBandFromScore,
  SCORE_BAND_META,
  SCORE_BAND_ORDER,
  type RestaurantStatus,
  type RestaurantSummary,
  type Visit,
} from './types/domain'

type ActiveList = RestaurantStatus | 'recommended'

export default function App() {
  const restaurants = useLiveQuery(
    () => db.restaurants.orderBy('createdAt').reverse().toArray(),
    [],
  )
  const visits = useLiveQuery(() => db.visits.toArray(), [])
  const [query, setQuery] = useState('')
  const [activeList, setActiveList] = useState<ActiveList>('visited')
  const [visitCountFilter, setVisitCountFilter] = useState<VisitCountFilter>('all')
  const [scoreBandFilter, setScoreBandFilter] = useState<ScoreBandFilter>('all')
  const [queueFilter, setQueueFilter] = useState<QueueFilter>('all')
  const [companionFilter, setCompanionFilter] = useState('all')
  const [tagFilter, setTagFilter] = useState('all')
  const [cityFilter, setCityFilter] = useState('all')
  const [showFilters, setShowFilters] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [showAddModal, setShowAddModal] = useState(false)
  const [showEditor, setShowEditor] = useState(false)
  const [showAddVisit, setShowAddVisit] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [toast, setToast] = useState('')
  const searchInputRef = useRef<HTMLInputElement>(null)

  const allRestaurants = useMemo(() => restaurants ?? [], [restaurants])
  const allVisits = useMemo(() => visits ?? [], [visits])
  const companionOptions = useMemo(
    () =>
      [...new Set(allVisits.flatMap((visit) => visit.companions.map((name) => name.trim())).filter(Boolean))]
        .sort((a, b) => a.localeCompare(b, 'zh-CN')),
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
  const recommendations = useMemo(() => buildRecommendations(summaries), [summaries])
  const listCounts = useMemo(
    () => ({
      visited: summaries.filter((restaurant) => restaurant.status === 'visited').length,
      wantToGo: summaries.filter((restaurant) => restaurant.status === 'wantToGo').length,
      recommended: recommendations.length,
    }),
    [recommendations.length, summaries],
  )

  const visibleRestaurants = useMemo(() => {
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
        (queueFilter !== 'all' || companionFilter !== 'all') &&
        !relatedVisits.some(
          (visit) =>
            matchesQueueDuration(visit.queueDuration, queueFilter) &&
            (companionFilter === 'all' || visit.companions.includes(companionFilter)),
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
          ...visit.dishes.map((dish) => dish.name),
        ]),
      ].some((value) => value.toLocaleLowerCase('zh-CN').includes(normalizedQuery))
    })
    return activeList === 'recommended' ? filtered : filtered.sort(compareRestaurantQuality)
  }, [
    activeList,
    cityFilter,
    companionFilter,
    query,
    queueFilter,
    scoreBandFilter,
    recommendations,
    summaries,
    tagFilter,
    visitCountFilter,
    visitsByRestaurant,
  ])

  const existingRestaurantsByPoiId = useMemo(
    () => new Map(summaries.map((restaurant) => [restaurant.amapPoiId, restaurant])),
    [summaries],
  )
  const activeFilterCount = activeList === 'recommended'
    ? 0
    : (scoreBandFilter !== 'all' ? 1 : 0) +
      (cityFilter !== 'all' ? 1 : 0) +
      (tagFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && visitCountFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && queueFilter !== 'all' ? 1 : 0) +
      (activeList === 'visited' && companionFilter !== 'all' ? 1 : 0)

  useEffect(() => {
    const parameters = new URLSearchParams(window.location.search)
    const requestedFromUrl = parameters.get('addSampleRestaurants') === '60'
    const seedCompleted = localStorage.getItem('shitu-sixty-restaurants-added') === 'yes'
    if (!requestedFromUrl && seedCompleted) return
    if (requestedFromUrl) {
      parameters.delete('addSampleRestaurants')
      const cleanUrl = `${window.location.pathname}${parameters.size ? `?${parameters}` : ''}${window.location.hash}`
      window.history.replaceState(null, '', cleanUrl)
    }
    seedSixtyVisitedRestaurants()
      .then((addedCount) => {
        localStorage.setItem('shitu-sixty-restaurants-added', 'yes')
        setActiveList('visited')
        setSelectedId(null)
        if (addedCount) setToast(`已新增 ${addedCount} 家餐厅`)
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

  const handleSelect = useCallback((restaurant: RestaurantSummary) => {
    setSelectedId(restaurant.id)
  }, [])

  function chooseList(list: ActiveList) {
    setActiveList(list)
    setSelectedId(null)
    if (list !== 'visited') {
      setVisitCountFilter('all')
      setQueueFilter('all')
      setCompanionFilter('all')
    }
    if (list === 'recommended') {
      setScoreBandFilter('all')
      setTagFilter('all')
      setCityFilter('all')
      setShowFilters(false)
    }
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
    await addVisit(selectedRestaurant.id, input)
    setActiveList('visited')
    setShowAddVisit(false)
    setToast('到访记录已保存')
  }

  function handleRecordExisting(restaurant: RestaurantSummary) {
    setSelectedId(restaurant.id)
    setShowAddModal(false)
    setShowAddVisit(true)
  }

  function resetFilters() {
    setVisitCountFilter('all')
    setScoreBandFilter('all')
    setQueueFilter('all')
    setCompanionFilter('all')
    setTagFilter('all')
    setCityFilter('all')
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark"><Utensils size={18} /></span>
          <div><strong>食途</strong><span>我的私人美食地图</span></div>
        </div>
        <div className="topbar-actions">
          <button className="settings-button" aria-label="数据与设置" onClick={() => setShowSettings(true)} type="button"><Settings size={18} /></button>
          <button className="primary-button" onClick={() => setShowAddModal(true)} type="button"><Plus size={17} /> <span>添加餐厅</span></button>
        </div>
      </header>

      <section className="workspace">
        <aside className="sidebar">
          <div className="sidebar-heading">
            <div><span className="eyebrow">MY FOOD MAP</span><h1>我的美食清单</h1><p>只看自己真正记录过的地方。</p></div>
            <span className="count-pill">{summaries.length}</span>
          </div>

          <div className="collection-tabs" aria-label="餐厅列表">
            <button className={activeList === 'visited' ? 'is-active' : ''} onClick={() => chooseList('visited')} type="button"><span>我去过的</span><strong>{listCounts.visited}</strong></button>
            <button className={activeList === 'wantToGo' ? 'is-active' : ''} onClick={() => chooseList('wantToGo')} type="button"><span>我想去的</span><strong>{listCounts.wantToGo}</strong></button>
            <button className={activeList === 'recommended' ? 'is-active' : ''} onClick={() => chooseList('recommended')} type="button"><span><Sparkles size={11} /> 推荐</span><strong>{listCounts.recommended}</strong></button>
          </div>

          <div className="search-filter-row">
            <label className="search-box"><Search size={17} /><input aria-label="搜索我的餐厅" onChange={(event) => setQuery(event.target.value)} placeholder="搜索餐厅、标签、饭搭子" ref={searchInputRef} value={query} /><kbd>⌘ K</kbd></label>
            {activeList !== 'recommended' ? <button className={`filter-toggle${showFilters ? ' is-active' : ''}`} aria-label="筛选餐厅" onClick={() => setShowFilters((current) => !current)} type="button"><SlidersHorizontal size={17} />{activeFilterCount ? <b>{activeFilterCount}</b> : null}</button> : null}
          </div>

          {showFilters ? (
            <RestaurantFilters
              city={cityFilter}
              cityOptions={cityOptions}
              companion={companionFilter}
              companionOptions={companionOptions}
              onCityChange={setCityFilter}
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

          <div className="list-result-line"><span>{activeList === 'visited' ? '去过' : activeList === 'wantToGo' ? '想去' : '根据你的口味推荐'}</span><strong>{visibleRestaurants.length} 家</strong></div>
          <RestaurantList
            activeList={activeList}
            isLoading={restaurants === undefined || visits === undefined}
            onAdd={() => setShowAddModal(true)}
            onSelect={handleSelect}
            query={query}
            restaurants={visibleRestaurants}
            selectedId={selectedRestaurant?.id}
          />
          <footer className="local-data-note"><MapPin size={13} /> 数据仅保存在当前浏览器</footer>
        </aside>

        <section className="map-panel" aria-label="私人美食地图">
          <MapView onClearSelection={() => setSelectedId(null)} onSelect={handleSelect} restaurants={visibleRestaurants} selectedRestaurant={selectedRestaurant} />
          <div className="legend" aria-label="评分颜色图例">
            {SCORE_BAND_ORDER.map((band) => <span key={band}><i style={{ background: SCORE_BAND_META[band].color }} />{SCORE_BAND_META[band].shortLabel}</span>)}
          </div>
          {selectedRestaurant ? <RestaurantPreviewCard onAddVisit={() => setShowAddVisit(true)} onClose={() => setSelectedId(null)} onDelete={() => setShowDeleteConfirm(true)} onEdit={() => setShowEditor(true)} restaurant={selectedRestaurant} /> : null}
        </section>
      </section>

      {showAddModal ? <AddRestaurantModal existingRestaurantsByPoiId={existingRestaurantsByPoiId} onAdd={handleAdd} onClose={() => setShowAddModal(false)} onRecordExisting={handleRecordExisting} /> : null}
      {showEditor && selectedRestaurant ? <RestaurantEditorModal onClose={() => setShowEditor(false)} onSave={handleSave} restaurant={selectedRestaurant} /> : null}
      {showAddVisit && selectedRestaurant ? <AddVisitModal onClose={() => setShowAddVisit(false)} onSave={handleAddVisit} restaurant={selectedRestaurant} /> : null}
      {showDeleteConfirm && selectedRestaurant ? <ConfirmDeleteModal onCancel={() => setShowDeleteConfirm(false)} onConfirm={handleDelete} restaurantName={selectedRestaurant.name} visitCount={selectedRestaurant.visitCount} /> : null}
      {showSettings ? <SettingsModal onClose={() => setShowSettings(false)} onImported={(message) => { setSelectedId(null); setToast(message) }} restaurantCount={summaries.length} visitCount={allVisits.length} /> : null}
      {toast ? <div className="toast" role="status"><CheckCircle2 size={17} /> {toast}</div> : null}
    </main>
  )
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

function buildRecommendations(restaurants: RestaurantSummary[]) {
  const visited = restaurants.filter(
    (restaurant) => restaurant.status === 'visited' && restaurant.averageRating !== null,
  )
  const wanted = restaurants.filter((restaurant) => restaurant.status === 'wantToGo')
  const positiveVisits = visited.filter((restaurant) => (restaurant.averageRating ?? 0) >= 4)

  if (wanted.length) {
    const averageLikedPrice = average(
      positiveVisits
        .map((restaurant) => restaurant.averagePricePerPerson)
        .filter((price): price is number => price !== null),
    )

    return wanted
      .map((candidate) => {
        let score = 0
        const tagScores = new Map<string, number>()
        let sameCityScore = 0

        positiveVisits.forEach((liked) => {
          const weight = Math.max(0.5, (liked.averageRating ?? 4) - 3)
          if (liked.city === candidate.city) sameCityScore += weight
          liked.tags.forEach((tag) => {
            if (candidate.tags.includes(tag)) {
              tagScores.set(tag, (tagScores.get(tag) ?? 0) + weight * 2)
            }
          })
        })

        const topTag = [...tagScores.entries()].sort((a, b) => b[1] - a[1])[0]
        if (topTag) score += topTag[1]
        if (sameCityScore) score += Math.min(2, sameCityScore * 0.5)
        const candidatePrice = candidate.pricePerPerson
        const closeInPrice =
          averageLikedPrice !== null &&
          candidatePrice !== null &&
          Math.abs(candidatePrice - averageLikedPrice) / Math.max(averageLikedPrice, 1) <= 0.35
        if (closeInPrice) score += 1

        const reason = topTag
          ? `你常给“${topTag[0]}”高分`
          : sameCityScore
            ? `和你喜欢的餐厅同在${candidate.city}`
            : closeInPrice
              ? '接近你喜欢的价格区间'
              : '来自你的想去清单'

        return { ...candidate, recommendationScore: score, recommendationReason: reason }
      })
      .sort((a, b) => (b.recommendationScore ?? 0) - (a.recommendationScore ?? 0) || b.createdAt.localeCompare(a.createdAt))
      .slice(0, 10)
  }

  return visited
    .slice()
    .sort((a, b) => (b.averageRating ?? 0) - (a.averageRating ?? 0) || b.visitCount - a.visitCount)
    .slice(0, 8)
    .map((restaurant) => ({
      ...restaurant,
      recommendationScore: restaurant.averageRating ?? 0,
      recommendationReason: `你给了 ${restaurant.scoreOutOfTen?.toFixed(1) ?? '—'} 分，值得再去`,
    }))
}

function average(values: number[]) {
  if (!values.length) return null
  return values.reduce((sum, value) => sum + value, 0) / values.length
}
