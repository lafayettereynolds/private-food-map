import { BookmarkPlus, Check, Dices, Globe2, LocateFixed, MapPin, Plus, SlidersHorizontal, X } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { scoreColor, type CommunityVisit, type Coordinates, type RestaurantSummary, type UserProfile, type Visit } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { fetchCommunityFeed, type DiscoveryMode } from '../services/socialApi'
import { trackDiscoveryRecommendationEvent } from '../services/recommendationAnalytics'
import { mapService } from '../services/mapService'
import { buildRecommendationEmptyState, candidateCentroid, distanceKilometers, resolveRecommendationFilters, sameCity, type RelaxationSuggestion } from '../services/recommendationFilterResolver'
import { SyncedImage } from './SyncedImage'
import { UserAvatar } from './UserAvatar'
import { ModalShell } from './ModalShell'
import { RestaurantPreviewCard } from './RestaurantPreviewCard'
import { RestaurantAvatar } from './RestaurantAvatar'

interface FeedItem {
  user: UserProfile
  restaurant: RestaurantSummary
  visit: Visit
  similarity?: number | null
  recommendationReason?: string | null
  recommendationType?: CommunityVisit['recommendationType']
  recommendationRank?: number | null
  recommendationConfidence?: CommunityVisit['recommendationConfidence']
  reasonCodes?: CommunityVisit['reasonCodes']
  surface?: CommunityVisit['surface']
}

const DISCOVERY_TABS: Array<{ value: DiscoveryMode; label: string }> = [
  { value: 'following', label: '关注' },
  { value: 'for_you', label: '为你推荐' },
  { value: 'similar', label: '同味之选' },
  { value: 'latest', label: '最新' },
  { value: 'trending', label: '趋势' },
]

type RecommendationSort = 'recommended' | 'nearest' | 'rating'
type RecommendationDistance = 'all' | 1 | 3 | 5 | 10
type RecommendationRating = 'all' | 7 | 8 | 9

const DISTANCE_OPTIONS: Array<{ value: RecommendationDistance; label: string }> = [
  { value: 'all', label: '不限距离' },
  { value: 1, label: '1 km 内' },
  { value: 3, label: '3 km 内' },
  { value: 5, label: '5 km 内' },
  { value: 10, label: '10 km 内' },
]

const RATING_OPTIONS: Array<{ value: RecommendationRating; label: string }> = [
  { value: 'all', label: '不限评分' },
  { value: 9, label: '9 分以上' },
  { value: 8, label: '8 分以上' },
  { value: 7, label: '7 分以上' },
]

export function CommunityPage({ users, restaurants, candidateRestaurantIds, mode, onModeChange, onAddToWant, onMarkVisited, onToggleCandidate, onViewProfile }: {
  users: UserProfile[]
  restaurants: RestaurantSummary[]
  candidateRestaurantIds: string[]
  mode: DiscoveryMode
  onModeChange: (mode: DiscoveryMode) => void
  onAddToWant: (restaurant: RestaurantSummary) => void
  onMarkVisited: (restaurant: RestaurantSummary) => void
  onToggleCandidate: (restaurant: RestaurantSummary) => void
  onViewProfile: (user: UserProfile) => void
}) {
  const [city, setCity] = useState('杭州市')
  const [trendWindow, setTrendWindow] = useState<7 | 30>(7)
  const [cloudFeed, setCloudFeed] = useState<CommunityVisit[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [selectedItem, setSelectedItem] = useState<FeedItem | null>(null)
  const [showRecommendationFilters, setShowRecommendationFilters] = useState(false)
  const [distanceFilter, setDistanceFilter] = useState<RecommendationDistance>('all')
  const [ratingFilter, setRatingFilter] = useState<RecommendationRating>('all')
  const [recommendationSort, setRecommendationSort] = useState<RecommendationSort>('recommended')
  const [coordinates, setCoordinates] = useState<Coordinates | null>(null)
  const [locationStatus, setLocationStatus] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle')
  const [distanceAnchor, setDistanceAnchor] = useState<'device' | 'city' | null>(null)
  const [anchorKey, setAnchorKey] = useState('')
  const userById = useMemo(() => new Map(users.map((user) => [user.id, user])), [users])
  const cityOptions = useMemo(() => [...new Set(['杭州市', '上海市', '北京市', '东京', '大阪', '香港', ...restaurants.map((restaurant) => restaurant.city).filter(Boolean)])], [restaurants])

  useEffect(() => {
    let active = true
    setLoading(true)
    setError('')
    void fetchCommunityFeed(mode, city, trendWindow).then((items) => { if (active) setCloudFeed(items) })
      .catch((feedError) => { if (active) setError(feedError instanceof Error ? feedError.message : '发现内容暂时无法加载。') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [city, mode, trendWindow])

  useEffect(() => {
    cloudFeed.slice(0, 20).forEach((item) => trackDiscoveryRecommendationEvent('impression', item))
  }, [cloudFeed])

  const localFeed = useMemo<FeedItem[]>(() => mode === 'latest' ? restaurants.flatMap((restaurant) => restaurant.visits.flatMap((visit) => {
    const user = userById.get(visit.userId ?? 'owner')
    return user?.mapSharingEnabled && user.mapVisibility === 'public' && (!city || restaurant.city === city) ? [{ user, restaurant, visit }] : []
  })) : [], [city, mode, restaurants, userById])
  const feed = useMemo(() => {
    const items = new Map<string, FeedItem>(localFeed.map((item) => [item.visit.id, item]))
    cloudFeed.forEach((item) => {
      const localRestaurant = restaurants.find((restaurant) => restaurant.id === item.restaurant.id)
      items.set(item.visit.id, {
        user: { ...item.user, email: null, mapSharingEnabled: false, mapVisibility: 'private', authProvider: 'cloudflare-access', authSubject: null, createdAt: '', updatedAt: '', deletedAt: null },
        restaurant: localRestaurant
          ? {
              ...localRestaurant,
              merchantImageUrl: localRestaurant.merchantImageUrl ?? item.restaurant.merchantImageUrl,
              markerType: localRestaurant.markerImageData || localRestaurant.markerPhotoId || localRestaurant.merchantImageUrl || item.restaurant.merchantImageUrl ? 'image' : localRestaurant.markerType,
            }
          : communityRestaurant(item),
        visit: item.visit, similarity: item.similarity, recommendationReason: item.recommendationReason,
        recommendationType: item.recommendationType, recommendationRank: item.recommendationRank,
        recommendationConfidence: item.recommendationConfidence, reasonCodes: item.reasonCodes, surface: item.surface,
      })
    })
    return [...items.values()]
  }, [cloudFeed, localFeed, restaurants])

  const needsLocation = distanceFilter !== 'all' || recommendationSort === 'nearest'

  useEffect(() => {
    if (mode !== 'for_you' || !needsLocation || (coordinates && anchorKey === city)) return
    let active = true
    setLocationStatus('loading')
    void mapService.detectCurrentLocation()
      .then((location) => {
        if (!active) return
        const canUseDevice = !city || sameCity(location.city, city)
        const nextCoordinates = canUseDevice ? location : candidateCentroid(feed.map((item) => item.restaurant))
        if (!nextCoordinates) throw new Error('没有可用的距离锚点')
        setCoordinates(nextCoordinates)
        setDistanceAnchor(canUseDevice ? 'device' : 'city')
        setAnchorKey(city)
        setLocationStatus('ready')
      })
      .catch(() => {
        if (!active) return
        const fallback = candidateCentroid(feed.map((item) => item.restaurant))
        if (fallback) {
          setCoordinates(fallback)
          setDistanceAnchor('city')
          setAnchorKey(city)
          setLocationStatus('ready')
        } else {
          setCoordinates(null)
          setDistanceAnchor(null)
          setLocationStatus('error')
        }
      })
    return () => { active = false }
  }, [anchorKey, city, coordinates, feed, mode, needsLocation])

  const recommendationCandidates = useMemo(() => feed.map((item) => ({
    ...item.restaurant,
    scoreOutOfTen: item.restaurant.scoreOutOfTen ?? (item.visit.rating ? item.visit.rating * 2 : null),
    feedItem: item,
  })), [feed])
  const recommendationFilterResolution = useMemo(() => resolveRecommendationFilters(
    recommendationCandidates,
    {
      distanceKm: distanceFilter === 'all' ? null : distanceFilter,
      ratingMinimum: ratingFilter === 'all' ? null : ratingFilter,
    },
    coordinates,
  ), [coordinates, distanceFilter, ratingFilter, recommendationCandidates])

  const visibleFeed = useMemo(() => {
    if (mode !== 'for_you') return feed
    const filtered = recommendationFilterResolution.results.map((item) => item.feedItem)
    if (recommendationSort === 'rating') return [...filtered].sort((left, right) => feedScore(right) - feedScore(left))
    if (recommendationSort === 'nearest' && coordinates) {
      return [...filtered].sort((left, right) => distanceKilometers(coordinates, left.restaurant) - distanceKilometers(coordinates, right.restaurant))
    }
    return filtered
  }, [coordinates, feed, mode, recommendationFilterResolution.results, recommendationSort])

  const activeRecommendationFilterCount = recommendationFilterResolution.activeFilters.length

  function resetRecommendationFilters() {
    setDistanceFilter('all')
    setRatingFilter('all')
    setRecommendationSort('recommended')
  }

  function applyRelaxation(suggestion: RelaxationSuggestion) {
    if (suggestion.type === 'distance') setDistanceFilter(suggestion.to === null ? 'all' : suggestion.to as RecommendationDistance)
    if (suggestion.type === 'rating') setRatingFilter(suggestion.to === null ? 'all' : suggestion.to as RecommendationRating)
  }

  const filterEmptyState = buildRecommendationEmptyState(recommendationFilterResolution.relaxationSuggestion, recommendationFilterResolution.emptyReason, '')

  return <section className="social-page community-page discovery-page">
    <header className="social-page__heading"><div><span className="eyebrow">DISCOVER</span><h1>发现</h1><p>按照你的口味，找到更值得参考的人和下一家餐厅。</p></div><Globe2 size={28} /></header>
    <div className="discovery-controls">
      <label className="discovery-city"><MapPin size={15} /><input aria-label="搜索发现城市" list="discovery-city-options" onChange={(event) => setCity(event.target.value)} placeholder="搜索城市" value={city} /><datalist id="discovery-city-options">{cityOptions.map((option) => <option key={option} value={option} />)}</datalist></label>
      <div className="discovery-tabs" role="tablist">{DISCOVERY_TABS.map((tab) => <button aria-selected={mode === tab.value} className={mode === tab.value ? 'active' : ''} key={tab.value} onClick={() => onModeChange(tab.value)} role="tab" type="button">{tab.label}</button>)}</div>
    </div>
    {mode === 'for_you' ? <><div className="discovery-recommendation-toolbar"><p className="discovery-explainer">根据你跨城市积累的评分、菜系与重复到访偏好生成。</p><button aria-expanded={showRecommendationFilters} className={showRecommendationFilters ? 'is-active' : ''} onClick={() => setShowRecommendationFilters((current) => !current)} type="button"><SlidersHorizontal size={15} />筛选{activeRecommendationFilterCount ? <b>{activeRecommendationFilterCount}</b> : null}</button></div>{showRecommendationFilters ? <div className="discovery-recommendation-filters"><header><strong>筛选推荐</strong><button disabled={!activeRecommendationFilterCount} onClick={resetRecommendationFilters} type="button">重置</button></header><div className="discovery-filter-grid"><label><span>排序</span><select onChange={(event) => setRecommendationSort(event.target.value as RecommendationSort)} value={recommendationSort}><option value="recommended">综合推荐</option><option value="nearest">距离最近</option><option value="rating">评分最高</option></select></label><fieldset><legend>距离</legend><div>{DISTANCE_OPTIONS.map((option) => <button className={distanceFilter === option.value ? 'is-active' : ''} key={option.value} onClick={() => setDistanceFilter(option.value)} type="button">{option.label}</button>)}</div></fieldset><fieldset><legend>评分</legend><div>{RATING_OPTIONS.map((option) => <button className={ratingFilter === option.value ? 'is-active' : ''} key={option.value} onClick={() => setRatingFilter(option.value)} type="button">{option.label}</button>)}</div></fieldset></div>{needsLocation ? <p className={`discovery-location-status is-${locationStatus}`}>{locationStatus === 'loading' ? <><span className="loading-spinner" />正在确定距离基准…</> : locationStatus === 'error' ? <><X size={13} />无法取得距离基准，请先选择城市或允许定位。<button onClick={() => { setAnchorKey(''); setLocationStatus('idle') }} type="button">重试</button></> : locationStatus === 'ready' ? <><LocateFixed size={13} />{distanceAnchor === 'device' ? '已按当前位置计算距离' : `已按${city || '当前城市'}中心计算距离`}</> : null}</p> : null}</div> : null}</> : null}
    {mode === 'similar' ? <p className="discovery-explainer">看看和你口味相近的人，在当前城市真正喜欢什么。</p> : null}
    {mode === 'trending' ? <div className="trend-window"><button className={trendWindow === 7 ? 'active' : ''} onClick={() => setTrendWindow(7)} type="button">近 7 天</button><button className={trendWindow === 30 ? 'active' : ''} onClick={() => setTrendWindow(30)} type="button">近 30 天</button></div> : null}
    {loading ? <div className="social-empty"><span className="loading-spinner" /><strong>正在整理发现内容</strong></div> : null}
    {!loading && error ? <div className="social-empty"><strong>暂时无法加载</strong><p>{error}</p></div> : null}
    {!loading && !error && visibleFeed.length ? <div className="community-feed">{visibleFeed.map((item) => <DiscoveryCard candidateRestaurantIds={candidateRestaurantIds} distance={coordinates ? distanceKilometers(coordinates, item.restaurant) : null} item={item} key={item.visit.id} mode={mode} onAddToWant={onAddToWant} onMarkVisited={onMarkVisited} onOpen={() => { trackDiscoveryRecommendationEvent('restaurantDetailOpen', item as CommunityVisit); setSelectedItem(item) }} onToggleCandidate={onToggleCandidate} onViewProfile={onViewProfile} />)}</div> : null}
    {!loading && !error && !visibleFeed.length ? <div className="social-empty compact-recommendation-empty"><Globe2 size={22} /><strong>{mode === 'for_you' && feed.length ? filterEmptyState.title : mode === 'for_you' ? '还没有足够信息推荐' : mode === 'similar' ? '当前地区还没有足够的同味数据' : mode === 'latest' ? '这里最近还没有公开到访记录' : mode === 'trending' ? '近期样本不足，暂时还没有形成趋势' : '最近还没有新的关注动态'}</strong><p>{mode === 'for_you' && feed.length ? filterEmptyState.message : mode === 'for_you' ? '多记录几家餐厅后，我们会逐渐了解你的口味。' : mode === 'similar' ? '有更多真实同味到访后会自动出现。' : mode === 'following' ? '可以先去发现好友，或稍后再看看。' : '换一个城市或稍后再看看。'}</p>{mode === 'for_you' && recommendationFilterResolution.relaxationSuggestion ? <button className="secondary-button recommendation-relax-button" onClick={() => applyRelaxation(recommendationFilterResolution.relaxationSuggestion!)} type="button">{filterEmptyState.actionLabel}</button> : null}</div> : null}
    {selectedItem ? <ModalShell description={mode === 'for_you' ? selectedItem.recommendationReason || '根据你的历史口味推荐' : `${selectedItem.user.nickname} 的公开到访记录`} onClose={() => setSelectedItem(null)} size="large" title="餐厅信息"><div className="discovery-restaurant-preview"><RestaurantPreviewCard additionalUserPhotos={selectedItem.visit.photos.map((source, index) => ({ source, photoId: selectedItem.visit.photoIds[index] }))} historyRestaurants={restaurants} isInRoulette={candidateRestaurantIds.includes(selectedItem.restaurant.id)} onAddToRoulette={() => onToggleCandidate(selectedItem.restaurant)} onAddVisit={() => onMarkVisited(selectedItem.restaurant)} onClose={() => setSelectedItem(null)} onDelete={() => undefined} onEdit={() => undefined} onEditVisit={() => undefined} onSaveRecommendation={() => onAddToWant(selectedItem.restaurant)} restaurant={{ ...selectedItem.restaurant, isRecommendation: true }} /></div></ModalShell> : null}
  </section>
}

function DiscoveryCard({ item, mode, distance, candidateRestaurantIds, onAddToWant, onMarkVisited, onOpen, onToggleCandidate, onViewProfile }: {
  item: FeedItem
  mode: DiscoveryMode
  distance: number | null
  candidateRestaurantIds: string[]
  onAddToWant: (restaurant: RestaurantSummary) => void
  onMarkVisited: (restaurant: RestaurantSummary) => void
  onOpen: () => void
  onToggleCandidate: (restaurant: RestaurantSummary) => void
  onViewProfile: (user: UserProfile) => void
}) {
  const score = item.restaurant.scoreOutOfTen ?? (item.visit.rating ? item.visit.rating * 2 : null)
  const selected = candidateRestaurantIds.includes(item.restaurant.id)
  const visitPhotos = item.visit.photos.slice(0, 3).map((source, index) => ({ source, photoId: item.visit.photoIds[index] }))
  const fallbackImage = item.restaurant.merchantImageUrl || item.restaurant.markerImageData
  const media = visitPhotos.length ? visitPhotos : fallbackImage ? [{ source: fallbackImage, photoId: item.restaurant.markerPhotoId }] : []

  return <article className={`community-card discovery-feed-card is-${mode}`}>
    {mode !== 'for_you' ? <header><button className="user-avatar-small" onClick={() => onViewProfile(item.user)} type="button"><UserAvatar alt="" avatarImageData={item.user.avatarImageData} avatarPhotoId={item.user.avatarPhotoId} avatarPresetId={item.user.avatarPresetId} membershipTier={item.user.membershipTier} /></button><button className="community-user-link" onClick={() => onViewProfile(item.user)} type="button"><strong>{item.user.nickname}</strong><time>{formatVisitDateTime(item.visit.visitedAt)}</time></button>{mode === 'similar' && item.similarity !== null && item.similarity !== undefined ? <span className="similarity-pill">口味相似 {item.similarity}%</span> : null}</header> : null}
    <button className="community-restaurant" onClick={onOpen} type="button"><RestaurantAvatar restaurant={item.restaurant} /><div className="community-restaurant__body"><strong>{item.restaurant.name}</strong><span><MapPin size={12} /> {distance !== null ? `${formatDistance(distance)} · ` : ''}{item.restaurant.city} · {item.restaurant.address}</span></div>{score !== null ? <span className="community-score-orb" style={{ borderColor: scoreColor(score), color: scoreColor(score) }}>{score.toFixed(1)}</span> : null}</button>
    {media.length ? <button className={`community-media count-${media.length}`} aria-label={`查看 ${item.restaurant.name} 详情`} onClick={onOpen} type="button">{media.map((photo, index) => <SyncedImage alt={`${item.restaurant.name} 图片 ${index + 1}`} key={`${item.visit.id}-media-${index}`} loading="lazy" photoId={photo.photoId} source={photo.source} />)}</button> : null}
    {mode !== 'for_you' && item.visit.note ? <p className="community-note"><strong>笔记</strong>{item.visit.note}</p> : null}
    {item.recommendationReason ? <p className="discovery-reason">{item.recommendationReason}</p> : null}
    <footer className="discovery-feed-card__footer"><span>{mode === 'for_you' ? '根据你的就餐历史推荐' : formatVisitDateTime(item.visit.visitedAt)}</span><div className="discovery-card-quick-actions"><button aria-label="记录去过" onClick={() => onMarkVisited(item.restaurant)} title="记录去过" type="button"><Plus size={18} /></button><button aria-label="加入想吃" onClick={() => { trackDiscoveryRecommendationEvent('wantToGoAdded', item as CommunityVisit); onAddToWant(item.restaurant) }} title="加入想吃" type="button"><BookmarkPlus size={18} /></button><button aria-label={selected ? '移出抽签' : '加入抽签'} aria-pressed={selected} className={selected ? 'is-selected' : ''} onClick={() => { if (!selected) trackDiscoveryRecommendationEvent('wheelCandidateAdded', item as CommunityVisit); onToggleCandidate(item.restaurant) }} title={selected ? '移出抽签' : '加入抽签'} type="button">{selected ? <Check size={18} /> : <Dices size={18} />}</button></div></footer>
  </article>
}

function feedScore(item: FeedItem) {
  return item.restaurant.scoreOutOfTen ?? (item.visit.rating ? item.visit.rating * 2 : 0)
}

function formatDistance(distance: number) {
  return distance < 1 ? `${Math.max(10, Math.round(distance * 1000 / 10) * 10)} m` : `${distance.toFixed(distance < 10 ? 1 : 0)} km`
}

function communityRestaurant(item: CommunityVisit): RestaurantSummary {
  return {
    ...item.restaurant, userId: item.visit.userId, status: 'visited', preferenceLevel: 'normal', overallRating: null, isRecommendation: true,
    foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags: [], longTermNote: '', pricePerPerson: item.visit.pricePerPerson,
    markerType: item.restaurant.merchantImageUrl ? 'image' : 'emoji', markerImageData: null, markerPhotoId: null, markerEmoji: '🍽️', createdAt: item.visit.createdAt,
    updatedAt: item.visit.updatedAt, deletedAt: null, visitCount: 1, averageRating: item.visit.rating, scoreOutOfTen: item.visit.rating ? item.visit.rating * 2 : null,
    latestVisitDate: item.visit.visitedAt, latestVisit: item.visit, visits: [item.visit], averagePricePerPerson: item.visit.pricePerPerson, averageQueueMinutes: null,
  }
}
