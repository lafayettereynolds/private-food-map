import { ArrowDownUp, ChevronDown, Globe2, Heart, LocateFixed, MapPin, MessageCircle, Send, SlidersHorizontal, Star, Store, X } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { DISCOVERY_RATING_FILTER_THRESHOLDS, minimumRatingFilterLabel } from '../utils/ratingFilterOptions'
import { DINING_OCCASION_OPTIONS, RECOMMENDATION_SOURCE_OPTIONS, starToTenScore, type CommunityVisit, type Coordinates, type RestaurantSummary, type UserProfile, type Visit } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { fetchCommunityFeed, type CommunityFeedAccess, type DiscoveryMode } from '../services/socialApi'
import { trackDiscoveryRecommendationEvent } from '../services/recommendationAnalytics'
import { mapService } from '../services/mapService'
import { buildRecommendationEmptyState, candidateCentroid, distanceKilometers, resolveRecommendationFilters, sameCity, type RelaxationSuggestion } from '../services/recommendationFilterResolver'
import { UserAvatar } from './UserAvatar'
import { PremiumBurgerBadge } from './PremiumBurgerBadge'
import { ModalShell } from './ModalShell'
import { RestaurantPreviewCard } from './RestaurantPreviewCard'
import { RestaurantShareSheet } from './RestaurantShareSheet'
import { buildRestaurantShareModel, copyRestaurantShareLink, isShareCancellation, trackDiscoverShareEvent, type RestaurantShareModel } from '../services/restaurantShare'
import { RestaurantQuickActions } from './RestaurantQuickActions'
import { openPremiumPaywall } from '../services/premiumPaywall'
import { FilterChoiceGroup } from './MyMapBrowsePage'
import { LockKeyhole } from 'lucide-react'
import { usePremiumAccess } from './PremiumAccess'
import { TasteMapActivityCardFrame, TasteMapActivityRatingBadge, TasteMapRecommendationReasons, TasteMapRecommendationSignal, TasteMapSocialAction, TasteMapDiscoveryScaffold, TasteMapFilterBar, TasteMapFilterSheet, TasteMapFilterSelect } from './TasteMapDiscoveryShared'
import { TasteMapActivityMedia } from './TasteMapActivityMedia'
import { TasteMapCitySearch } from './TasteMapCitySearch'
import { DiscoveryAvailabilityState } from './DiscoveryAvailabilityState'
import { visitActivityMedia } from './activityMedia'
import { RestaurantContentImage } from './RestaurantContentImage'
import {
  DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE,
} from '../contracts/discoveryContract'

interface FeedItem {
  personalTastePercent?: CommunityVisit['personalTastePercent']
  calibratedLikeProbability?: CommunityVisit['calibratedLikeProbability']
  user: UserProfile
  restaurant: RestaurantSummary
  visit: Visit
  /** The current viewer's saved state. Remote public visits do not imply that I visited the restaurant. */
  viewerRestaurantStatus: RestaurantSummary['status'] | null
  similarity?: number | null
  recommendationReason?: string | null
  recommendationReasons?: string[]
  recommendationFitLevel?: CommunityVisit['recommendationFitLevel']
  primaryReasons?: CommunityVisit['primaryReasons']
  secondaryReasons?: CommunityVisit['secondaryReasons']
  publicRating?: CommunityVisit['publicRating']
  isExploration?: boolean
  recommendationType?: CommunityVisit['recommendationType']
  recommendationRank?: number | null
  recommendationConfidence?: CommunityVisit['recommendationConfidence']
  reasonCodes?: CommunityVisit['reasonCodes']
  surface?: CommunityVisit['surface']
}

interface CommunityEngagement {
  liked: boolean
  likeCount: number
  comments: string[]
}

const EMPTY_ENGAGEMENT: CommunityEngagement = { liked: false, likeCount: 0, comments: [] }
const COMMUNITY_ENGAGEMENT_STORAGE_KEY = 'taste-map-community-engagement-v1'

const DISCOVERY_TABS: Array<{ value: DiscoveryMode; label: string }> = [
  { value: 'following', label: '关注' },
  { value: 'for_you', label: '为你推荐' },
  { value: 'similar', label: '同味之选' },
  { value: 'latest', label: '最新' },
  { value: 'trending', label: '趋势' },
]

type RecommendationSort = 'recommended' | 'nearest' | 'rating'
type RecommendationDistance = 'all' | 1 | 3 | 5 | 10
type RecommendationRating = 'all' | number

const DISTANCE_OPTIONS: Array<{ value: RecommendationDistance; label: string }> = [
  { value: 'all', label: '不限距离' },
  { value: 1, label: '1 km 内' },
  { value: 3, label: '3 km 内' },
  { value: 5, label: '5 km 内' },
  { value: 10, label: '10 km 内' },
]

const RATING_OPTIONS: Array<{ value: RecommendationRating; label: string }> = [
  { value: 'all', label: '不限评分' },
  ...DISCOVERY_RATING_FILTER_THRESHOLDS.map((value) => ({ value, label: minimumRatingFilterLabel(value) })),
]

export function CommunityPage({ users, restaurants, candidateRestaurantIds, mode, onModeChange, onToggleWant, onMarkVisited, onToggleCandidate, onViewProfile, onAddRestaurant }: {
  onAddRestaurant?: () => void
  users: UserProfile[]
  restaurants: RestaurantSummary[]
  candidateRestaurantIds: string[]
  mode: DiscoveryMode
  onModeChange: (mode: DiscoveryMode) => void
  onToggleWant: (restaurant: RestaurantSummary) => void
  onMarkVisited: (restaurant: RestaurantSummary) => void
  onToggleCandidate: (restaurant: RestaurantSummary) => void
  onViewProfile: (user: UserProfile) => void
}) {
  const [city, setCity] = useState('杭州市')
  const premiumVisible = usePremiumAccess()
  const [trendWindow, setTrendWindow] = useState<7 | 30>(7)
  const [cloudFeed, setCloudFeed] = useState<CommunityVisit[]>([])
  const [feedAccess, setFeedAccess] = useState<CommunityFeedAccess | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [selectedItem, setSelectedItem] = useState<FeedItem | null>(null)
  const [showRecommendationFilters, setShowRecommendationFilters] = useState(false)
  const [distanceFilter, setDistanceFilter] = useState<RecommendationDistance>('all')
  const [ratingFilter, setRatingFilter] = useState<RecommendationRating>('all')
  const [recommendationSort, setRecommendationSort] = useState<RecommendationSort>('recommended')
  const [sourceFilter, setSourceFilter] = useState('')
  const [occasionFilter, setOccasionFilter] = useState('')
  const [companionFilter, setCompanionFilter] = useState('')
  const [coordinates, setCoordinates] = useState<Coordinates | null>(null)
  const [locationStatus, setLocationStatus] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle')
  const [distanceAnchor, setDistanceAnchor] = useState<'device' | 'city' | null>(null)
  const [anchorKey, setAnchorKey] = useState('')
  const [engagement, setEngagement] = useState<Record<string, CommunityEngagement>>(readCommunityEngagement)
  const [commentingItem, setCommentingItem] = useState<FeedItem | null>(null)
  const [commentText, setCommentText] = useState('')
  const [shareMessage, setShareMessage] = useState('')
  const [shareModel, setShareModel] = useState<RestaurantShareModel | null>(null)
  const [shareItemContext, setShareItemContext] = useState<FeedItem | null>(null)
  const [shareBusy, setShareBusy] = useState(false)
  const [shareSheetMessage, setShareSheetMessage] = useState('')
  const discoveryScrollPositionRef = useRef(0)
  const userById = useMemo(() => new Map(users.map((user) => [user.id, user])), [users])
  const cityOptions = useMemo(() => [...new Set(['杭州市', '上海市', '北京市', '东京', '大阪', '香港', ...restaurants.map((restaurant) => restaurant.city).filter(Boolean)])], [restaurants])

  useEffect(() => {
    let active = true
    setLoading(true)
    setError('')
    // A new city/mode must not retain the prior query's cards while awaiting
    // its response or after a failed request.
    setCloudFeed([])
    void fetchCommunityFeed(mode, city, trendWindow).then((result) => { if (active) { setCloudFeed(result.items); setFeedAccess(result.access) } })
      .catch((feedError) => { if (active) setError(feedError instanceof Error ? feedError.message : '发现内容暂时无法加载。') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [city, mode, trendWindow])

  useEffect(() => {
    cloudFeed.slice(0, 20).forEach((item) => trackDiscoveryRecommendationEvent('impression', item))
  }, [cloudFeed])

  const localFeed = useMemo<FeedItem[]>(() => mode === 'latest' ? restaurants.flatMap((restaurant) => restaurant.visits.flatMap((visit) => {
    const user = userById.get(visit.userId ?? 'owner')
    return user?.mapSharingEnabled && user.mapVisibility === 'public' && (!city || restaurant.city === city) ? [{ user, restaurant, visit, viewerRestaurantStatus: restaurant.status }] : []
  })) : [], [city, mode, restaurants, userById])
  const feed = useMemo(() => {
    const items = new Map<string, FeedItem>(localFeed.map((item) => [item.visit.id, item]))
    cloudFeed.forEach((item) => {
      const localRestaurant = findMatchingRestaurant(restaurants, item.restaurant)
      items.set(item.visit.id, {
        user: { ...item.user, email: null, mapSharingEnabled: false, mapVisibility: 'private', authProvider: 'cloudflare-access', authSubject: null, createdAt: '', updatedAt: '', deletedAt: null },
        restaurant: localRestaurant
          ? {
              ...localRestaurant,
              merchantImageUrl: localRestaurant.merchantImageUrl ?? item.restaurant.merchantImageUrl,
              markerType: localRestaurant.markerImageData || localRestaurant.markerPhotoId || localRestaurant.merchantImageUrl || item.restaurant.merchantImageUrl ? 'image' : localRestaurant.markerType,
            }
          : communityRestaurant(item),
        viewerRestaurantStatus: localRestaurant?.status ?? null,
        visit: item.visit, similarity: item.similarity, recommendationReason: item.recommendationReason, recommendationReasons: item.recommendationReasons,
        recommendationFitLevel: item.recommendationFitLevel, primaryReasons: item.primaryReasons,
        secondaryReasons: item.secondaryReasons, publicRating: item.publicRating, isExploration: item.isExploration,
        recommendationType: item.recommendationType, recommendationRank: item.recommendationRank,
        recommendationConfidence: item.recommendationConfidence, reasonCodes: item.reasonCodes, surface: item.surface,
        personalTastePercent: item.personalTastePercent, calibratedLikeProbability: item.calibratedLikeProbability,
      })
    })
    return [...items.values()]
  }, [cloudFeed, localFeed, restaurants])

  useEffect(() => {
    if (!selectedItem) return
    const refreshed = feed.find((item) => item.visit.id === selectedItem.visit.id)
    if (refreshed) setSelectedItem(refreshed)
  }, [feed, selectedItem?.visit.id])

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
    scoreOutOfTen: item.publicRating?.value ?? item.restaurant.scoreOutOfTen ?? null,
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

  const ratingFilterLabel = mode === 'for_you' || mode === 'trending' ? '公开评分' : '本次评分'
  const primarySortLabel = mode === 'for_you' ? '综合推荐' : mode === 'similar' ? '同味匹配' : mode === 'trending' ? '趋势热度' : '最新动态'
  const hasAdvancedFilters = mode === 'for_you' && Boolean(feedAccess?.advancedFiltersEnabled)
  const companionOptions = [...new Set(feed.flatMap((item) => item.visit.companions ?? []).filter(Boolean))]

  const visibleFeed = useMemo(() => {
    // Trends consume visit counts at every rating. Every other Discovery mode
    // requires a qualified 7.5/10 concrete Visit as recommendation evidence.
    const evidenceFeed = (mode === 'trending' ? feed : feed.filter((item) =>
      item.visit.rating !== null && item.visit.rating >= DISCOVERY_MINIMUM_QUALIFIED_RATING_OUT_OF_FIVE))
      .filter((item) => !city.trim() || sameCity(item.restaurant.city, city))
    if (mode !== 'for_you') {
      const score = (item: FeedItem) => mode === 'trending' ? feedScore(item) : starToTenScore(item.visit.rating) ?? -1
      const filtered = evidenceFeed.filter((item) => ratingFilter === 'all' || score(item) >= ratingFilter)
      return recommendationSort === 'rating' ? [...filtered].sort((left, right) => score(right) - score(left)) : filtered
    }
    const allowedVisitIDs = new Set(evidenceFeed.map((item) => item.visit.id))
    const filtered = recommendationFilterResolution.results
      .map((item) => item.feedItem)
      .filter((item) => allowedVisitIDs.has(item.visit.id))
      .filter((item) => !hasAdvancedFilters || (
        (!sourceFilter || item.visit.recommendationSourceType === sourceFilter)
        && (!occasionFilter || [...(item.visit.diningOccasions ?? []), item.visit.diningOccasion].includes(occasionFilter as Visit['diningOccasion']))
        && (!companionFilter || (item.visit.companions ?? []).includes(companionFilter))
      ))
    if (recommendationSort === 'rating') return [...filtered].sort((left, right) => feedScore(right) - feedScore(left))
    if (recommendationSort === 'nearest' && coordinates) {
      return [...filtered].sort((left, right) => distanceKilometers(coordinates, left.restaurant) - distanceKilometers(coordinates, right.restaurant))
    }
    return filtered
  }, [coordinates, feed, mode, city, recommendationFilterResolution.results, recommendationSort, ratingFilter, hasAdvancedFilters, sourceFilter, occasionFilter, companionFilter])

  const activeRecommendationFilterCount = Number(Boolean(city)) + Number(ratingFilter !== 'all')
    + Number(recommendationSort === 'rating' || (mode === 'for_you' && recommendationSort === 'nearest'))
    + Number(mode === 'for_you' && distanceFilter !== 'all')
    + (hasAdvancedFilters ? Number(Boolean(sourceFilter)) + Number(Boolean(occasionFilter)) + Number(Boolean(companionFilter)) : 0)

  useEffect(() => {
    localStorage.setItem(COMMUNITY_ENGAGEMENT_STORAGE_KEY, JSON.stringify(engagement))
  }, [engagement])

  function updateEngagement(visitId: string, update: (current: CommunityEngagement) => CommunityEngagement) {
    setEngagement((current) => ({ ...current, [visitId]: update(current[visitId] ?? EMPTY_ENGAGEMENT) }))
  }

  function toggleLike(item: FeedItem) {
    updateEngagement(item.visit.id, (current) => ({ ...current, liked: !current.liked, likeCount: Math.max(0, current.likeCount + (current.liked ? -1 : 1)) }))
  }

  function submitComment() {
    if (!commentingItem || !commentText.trim()) return
    updateEngagement(commentingItem.visit.id, (current) => ({ ...current, comments: [...current.comments, commentText.trim()] }))
    setCommentText('')
  }

  async function shareItem(item: FeedItem) {
    try {
      const model = await buildRestaurantShareModel(item.restaurant, item.publicRating)
      const eventContext = {
        restaurantId: item.restaurant.id,
        discoverTab: mode,
        recommendationTier: feedAccess?.entitlementTier ?? 'unknown',
      }
      trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_open', ...eventContext })
      setShareItemContext(item)
      setShareModel(model)
      setShareSheetMessage('')
      if (typeof navigator.share !== 'function') return
      setShareBusy(true)
      trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_system', shareMethod: 'system', ...eventContext })
      try {
        await navigator.share({ title: model.title, text: model.text, url: model.url })
        trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_success', shareMethod: 'system', ...eventContext })
        setShareModel(null)
        setShareItemContext(null)
        setShareMessage('已打开系统分享')
        window.setTimeout(() => setShareMessage(''), 1800)
      } catch (error) {
        if (isShareCancellation(error)) {
          setShareModel(null)
          return
        }
        trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_failed', shareMethod: 'system', ...eventContext })
        setShareSheetMessage('暂时无法分享，可以复制链接。')
      } finally {
        setShareBusy(false)
      }
    } catch {
      setShareMessage('暂时无法生成分享链接')
      window.setTimeout(() => setShareMessage(''), 2200)
    }
  }

  async function shareFromSheet() {
    if (!shareModel || !shareItemContext || typeof navigator.share !== 'function') return
    const eventContext = { restaurantId: shareItemContext.restaurant.id, discoverTab: mode, recommendationTier: feedAccess?.entitlementTier ?? 'unknown' }
    setShareBusy(true)
    setShareSheetMessage('')
    trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_system', shareMethod: 'system', ...eventContext })
    try {
      await navigator.share({ title: shareModel.title, text: shareModel.text, url: shareModel.url })
      trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_success', shareMethod: 'system', ...eventContext })
      setShareModel(null)
      setShareItemContext(null)
    } catch (error) {
      if (!isShareCancellation(error)) {
        trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_failed', shareMethod: 'system', ...eventContext })
        setShareSheetMessage('暂时无法分享，可以复制链接。')
      }
    } finally {
      setShareBusy(false)
    }
  }

  async function copyShareLink() {
    if (!shareModel || !shareItemContext) return
    const eventContext = { restaurantId: shareItemContext.restaurant.id, discoverTab: mode, recommendationTier: feedAccess?.entitlementTier ?? 'unknown' }
    setShareBusy(true)
    setShareSheetMessage('')
    trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_copy_link', shareMethod: 'copy_link', ...eventContext })
    try {
      await copyRestaurantShareLink(shareModel)
      trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_success', shareMethod: 'copy_link', ...eventContext })
      setShareSheetMessage('链接已复制')
    } catch {
      trackDiscoverShareEvent({ eventName: 'discover_restaurant_share_failed', shareMethod: 'copy_link', ...eventContext })
      setShareSheetMessage('复制失败，请重试')
    } finally {
      setShareBusy(false)
    }
  }

  function resetRecommendationFilters() {
    setCity('')
    setDistanceFilter('all')
    setRatingFilter('all')
    setRecommendationSort('recommended')
    setSourceFilter('')
    setOccasionFilter('')
    setCompanionFilter('')
  }

  function applyRelaxation(suggestion: RelaxationSuggestion) {
    if (suggestion.type === 'distance') setDistanceFilter(suggestion.to === null ? 'all' : suggestion.to as RecommendationDistance)
    if (suggestion.type === 'rating') setRatingFilter(suggestion.to === null ? 'all' : suggestion.to as RecommendationRating)
  }

  function openRestaurant(item: FeedItem) {
    discoveryScrollPositionRef.current = window.scrollY
    trackDiscoveryRecommendationEvent('restaurantDetailOpen', item as CommunityVisit)
    setSelectedItem(item)
  }

  function closeRestaurant() {
    setSelectedItem(null)
    window.requestAnimationFrame(() => window.scrollTo({ top: discoveryScrollPositionRef.current }))
  }

  const filterEmptyState = buildRecommendationEmptyState(recommendationFilterResolution.relaxationSuggestion, recommendationFilterResolution.emptyReason, '')

  return <TasteMapDiscoveryScaffold
    className="social-page community-page discovery-page"
    description="按照你的口味，找到更值得参考的人和下一家餐厅。"
    filterBar={<TasteMapFilterBar>
      <button aria-haspopup="dialog" aria-expanded={showRecommendationFilters} className={activeRecommendationFilterCount ? 'is-active' : ''} onClick={() => setShowRecommendationFilters(true)} type="button"><SlidersHorizontal aria-hidden="true" size={15} />筛选{activeRecommendationFilterCount ? ` ${activeRecommendationFilterCount}` : ''}</button>
      <TasteMapCitySearch city={city} suggestions={cityOptions} onChange={setCity} />
      <TasteMapFilterSelect icon={<ArrowDownUp aria-hidden="true" size={15} />} label="排序" active={recommendationSort === 'rating' || (mode === 'for_you' && recommendationSort === 'nearest')} value={mode !== 'for_you' && recommendationSort === 'nearest' ? 'recommended' : recommendationSort} onChange={(value) => setRecommendationSort(value as RecommendationSort)} options={[{ value: 'recommended', label: primarySortLabel }, ...(mode === 'for_you' ? [{ value: 'nearest', label: '距离最近' }] : []), { value: 'rating', label: `${ratingFilterLabel}从高到低` }]} />
      <TasteMapFilterSelect icon={<Star aria-hidden="true" size={15} />} label={ratingFilterLabel} active={ratingFilter !== 'all'} value={String(ratingFilter)} onChange={(value) => setRatingFilter(value === 'all' ? 'all' : Number(value))} options={RATING_OPTIONS.map((option) => ({ ...option, value: String(option.value) }))} />
    </TasteMapFilterBar>}
    onTabChange={(nextMode) => { if (nextMode === 'similar' && feedAccess && !feedAccess.similarTasteEnabled) { openPremiumPaywall('similar_taste'); return } onModeChange(nextMode) }}
    tab={mode}
    tabs={DISCOVERY_TABS.map(tab => tab.value === 'similar' && !premiumVisible ? { ...tab, icon: <LockKeyhole aria-label="会员专享" size={12} /> } : tab)}
  >
    {mode === 'for_you' && feedAccess ? <button className={`recommendation-tier-note is-${feedAccess.entitlementTier}`} onClick={() => { if (feedAccess.entitlementTier !== 'premium') openPremiumPaywall('deep_recommendation') }} type="button"><strong>{feedAccess.entitlementTier === 'premium' ? feedAccess.experienceTier === 'deep' ? '深度推荐已开启' : 'Premium 已开启' : '免费基础推荐'}</strong><span>{feedAccess.entitlementTier === 'premium' ? feedAccess.message : '升级后可查看完整推荐依据与高级筛选'}</span></button> : null}
    {showRecommendationFilters ? <TasteMapFilterSheet activeCount={activeRecommendationFilterCount} onClose={() => setShowRecommendationFilters(false)} onReset={resetRecommendationFilters}>
      <label><span>搜索城市</span><input aria-label="筛选城市" list="discovery-city-options" placeholder="输入其他城市" value={city} onChange={(event) => setCity(event.target.value)} /><datalist id="discovery-city-options">{cityOptions.map((option) => <option key={option} value={option} />)}</datalist></label>
      <label><span>排序</span><select aria-label="筛选排序" value={mode !== 'for_you' && recommendationSort === 'nearest' ? 'recommended' : recommendationSort} onChange={(event) => setRecommendationSort(event.target.value as RecommendationSort)}><option value="recommended">{primarySortLabel}</option>{mode === 'for_you' ? <option value="nearest">距离最近</option> : null}<option value="rating">{ratingFilterLabel}从高到低</option></select></label>
      <label><span>{ratingFilterLabel}</span><select aria-label="筛选最低评分" value={ratingFilter} onChange={(event) => setRatingFilter(event.target.value === 'all' ? 'all' : Number(event.target.value))}>{RATING_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
      {mode === 'for_you' ? <>
        <fieldset><legend>距离</legend><div>{DISTANCE_OPTIONS.map((option) => <button aria-pressed={distanceFilter === option.value} className={distanceFilter === option.value ? 'is-active' : ''} key={option.value} onClick={() => setDistanceFilter(option.value)} type="button">{option.label}</button>)}</div></fieldset>
        <FilterChoiceGroup premiumOnly label="推荐来源" value={sourceFilter} options={RECOMMENDATION_SOURCE_OPTIONS.filter(option => option.value !== 'other').map(option => [option.value, option.label])} onSelect={value => hasAdvancedFilters ? setSourceFilter(value) : openPremiumPaywall('advanced_recommendation_filters')} />
        <FilterChoiceGroup premiumOnly label="适合场景" value={occasionFilter} options={DINING_OCCASION_OPTIONS.map(option => [option.value, option.label])} onSelect={value => hasAdvancedFilters ? setOccasionFilter(value) : openPremiumPaywall('advanced_recommendation_filters')} />
        <FilterChoiceGroup premiumOnly label="饭搭子" value={companionFilter} options={companionOptions.map(value => [value, value])} onSelect={value => hasAdvancedFilters ? setCompanionFilter(value) : openPremiumPaywall('advanced_recommendation_filters')} />
        {needsLocation ? <p className={`discovery-location-status is-${locationStatus}`}>{locationStatus === 'loading' ? <><span className="loading-spinner" />正在确定距离基准…</> : locationStatus === 'error' ? <><X size={13} />无法取得距离基准，请先选择城市或允许定位。<button onClick={() => { setAnchorKey(''); setLocationStatus('idle') }} type="button">重试</button></> : locationStatus === 'ready' ? <><LocateFixed size={13} />{distanceAnchor === 'device' ? '已按当前位置计算距离' : `已按${city || '当前城市'}中心计算距离`}</> : null}</p> : null}
      </> : null}
    </TasteMapFilterSheet> : null}
    {mode === 'similar' ? <p className="discovery-explainer">{feedAccess && !feedAccess.similarTasteEnabled ? <>同味之选属于 Premium 深度洞察。<button onClick={() => openPremiumPaywall('similar_taste')} type="button">查看 Premium</button></> : '看看和你口味相近的人，在当前城市真正喜欢什么。'}</p> : null}
    {mode === 'trending' ? <div className="trend-window"><button className={trendWindow === 7 ? 'active' : ''} onClick={() => setTrendWindow(7)} type="button">近 7 天</button><button className={trendWindow === 30 ? 'active' : ''} onClick={() => setTrendWindow(30)} type="button">近 30 天</button></div> : null}
    {loading ? <div className="social-empty"><span className="loading-spinner" /><strong>正在整理发现内容</strong></div> : null}
    {!loading && error ? <div className="social-empty"><strong>暂时无法加载</strong><p>{error}</p></div> : null}
    {!loading && !error && visibleFeed.length ? <div className="community-feed">{visibleFeed.map((item) => <DiscoveryCard candidateRestaurantIds={candidateRestaurantIds} distance={coordinates ? distanceKilometers(coordinates, item.restaurant) : null} engagement={engagement[item.visit.id] ?? EMPTY_ENGAGEMENT} feedAccess={feedAccess} item={item} key={item.visit.id} mode={mode} onComment={() => setCommentingItem(item)} onLike={() => toggleLike(item)} onMarkVisited={onMarkVisited} onOpen={() => openRestaurant(item)} onShare={() => void shareItem(item)} onToggleCandidate={onToggleCandidate} onToggleWant={onToggleWant} onViewProfile={onViewProfile} />)}</div> : null}
    {!loading && !error && !visibleFeed.length ? mode === 'similar'
      ? <DiscoveryAvailabilityState membership={feedAccess ? feedAccess.entitlementTier === 'premium' ? 'member' : 'free' : undefined} evidence={feedAccess?.evidenceAvailability} onPremium={() => openPremiumPaywall('similar_taste')} onRecord={onAddRestaurant} onCity={() => setShowRecommendationFilters(true)} onForYou={() => onModeChange('for_you')} />
      : <div className="social-empty compact-recommendation-empty"><Globe2 size={22} /><strong>{mode === 'for_you' && feed.length ? filterEmptyState.title : mode === 'for_you' ? '还没有足够信息推荐' : mode === 'latest' ? '这里最近还没有公开到访记录' : mode === 'trending' ? '近期样本不足，暂时还没有形成趋势' : '最近还没有新的关注动态'}</strong><p>{mode === 'for_you' && feed.length ? filterEmptyState.message : mode === 'for_you' ? '多记录几家餐厅后，我们会逐渐了解你的口味。' : mode === 'following' ? '可以先去发现好友，或稍后再看看。' : '换一个城市或稍后再看看。'}</p>{mode === 'for_you' && recommendationFilterResolution.relaxationSuggestion ? <button className="secondary-button recommendation-relax-button" onClick={() => applyRelaxation(recommendationFilterResolution.relaxationSuggestion!)} type="button">{filterEmptyState.actionLabel}</button> : null}</div> : null}
    {selectedItem ? <ModalShell description={mode === 'for_you' ? selectedItem.recommendationReason || '根据你的历史口味推荐' : `${selectedItem.user.nickname} 的公开到访记录`} onClose={closeRestaurant} size="large" title="餐厅信息"><div className="discovery-restaurant-preview"><RestaurantPreviewCard additionalUserPhotos={visitActivityMedia(selectedItem.visit.photos, selectedItem.visit.photoIds)} historyRestaurants={restaurants} isInRoulette={candidateRestaurantIds.includes(selectedItem.restaurant.id)} onAddToRoulette={() => onToggleCandidate(selectedItem.restaurant)} onAddToWant={() => onToggleWant(selectedItem.restaurant)} onAddVisit={() => onMarkVisited(selectedItem.restaurant)} onClose={closeRestaurant} onSaveRecommendation={() => onToggleWant(selectedItem.restaurant)} readOnly restaurant={{ ...selectedItem.restaurant, isRecommendation: true }} viewerStatus={selectedItem.viewerRestaurantStatus} /></div></ModalShell> : null}
    {commentingItem ? <ModalShell description={commentingItem.restaurant.name} onClose={() => { setCommentingItem(null); setCommentText('') }} title="评论"><div className="community-comment-panel"><div className="community-comment-list">{(engagement[commentingItem.visit.id]?.comments ?? []).length ? engagement[commentingItem.visit.id].comments.map((comment, index) => <p key={`${commentingItem.visit.id}-comment-${index}`}><strong>我</strong><span>{comment}</span></p>) : <p className="community-comment-empty">还没有评论，来说说你的想法。</p>}</div><form onSubmit={(event) => { event.preventDefault(); submitComment() }}><input autoFocus maxLength={280} onChange={(event) => setCommentText(event.target.value)} placeholder="写下评论" value={commentText} /><button aria-label="发送评论" disabled={!commentText.trim()} type="submit"><Send size={17} /></button></form></div></ModalShell> : null}
    {shareModel ? <RestaurantShareSheet busy={shareBusy} canSystemShare={typeof navigator.share === 'function'} message={shareSheetMessage} model={shareModel} onClose={() => { setShareModel(null); setShareItemContext(null); setShareSheetMessage('') }} onCopy={() => void copyShareLink()} onSystemShare={() => void shareFromSheet()} /> : null}
    {shareMessage ? <p aria-live="polite" className="community-share-toast">{shareMessage}</p> : null}
  </TasteMapDiscoveryScaffold>
}

function DiscoveryCard({ item, mode, distance, engagement, feedAccess, candidateRestaurantIds, onToggleWant, onComment, onLike, onMarkVisited, onOpen, onShare, onToggleCandidate, onViewProfile }: {
  item: FeedItem
  mode: DiscoveryMode
  distance: number | null
  engagement: CommunityEngagement
  feedAccess: CommunityFeedAccess | null
  candidateRestaurantIds: string[]
  onToggleWant: (restaurant: RestaurantSummary) => void
  onComment: () => void
  onLike: () => void
  onMarkVisited: (restaurant: RestaurantSummary) => void
  onOpen: () => void
  onShare: () => void
  onToggleCandidate: (restaurant: RestaurantSummary) => void
  onViewProfile: (user: UserProfile) => void
}) {
  const [showFullAnalysis, setShowFullAnalysis] = useState(false)
  const wanted = item.viewerRestaurantStatus === 'wantToGo'
  const activityRating = item.visit.rating
  const selected = candidateRestaurantIds.includes(item.restaurant.id)
  const isActivity = mode === 'similar' || mode === 'latest' || mode === 'following'
  const visitMedia = isActivity ? visitActivityMedia(item.visit.photos, item.visit.photoIds) : []
  const media = isActivity ? (visitMedia.length ? visitMedia : recommendationMedia(item).slice(0, 1)) : recommendationMedia(item)
  const reasonFallback = item.recommendationReasons?.map((text) => ({ text })) ?? (item.recommendationReason ? [{ text: item.recommendationReason }] : [])
  const allReasons = dedupeRecommendationReasons([...(item.primaryReasons?.length ? item.primaryReasons : reasonFallback), ...(item.secondaryReasons ?? [])])
  const highValueReasons = allReasons.filter(isHighValueRecommendationReason)
  const isPremium = feedAccess?.entitlementTier === 'premium'
  const coreReasonLimit = isPremium ? 3 : 1
  const primaryReasons = (isPremium ? highValueReasons : (highValueReasons.length ? highValueReasons : allReasons)).slice(0, coreReasonLimit)
  const primaryReasonTexts = new Set(primaryReasons.map((reason) => reason.text))
  const cautionReason = allReasons.find((reason) => !primaryReasonTexts.has(reason.text) && isRecommendationCaution(reason.text))
  const secondaryReasons = allReasons.filter((reason) => !primaryReasonTexts.has(reason.text) && reason !== cautionReason).slice(0, 5)
  const canShowFullAnalysis = mode === 'for_you' && isPremium && Boolean(feedAccess?.fullExplanationEnabled) && secondaryReasons.length > 0
  const evidenceTitle = item.recommendationFitLevel === 'EXPLORATION' ? '为什么推荐它' : '为什么适合你'
  const price = item.restaurant.averagePricePerPerson ?? item.restaurant.pricePerPerson
  const cuisines = item.restaurant.tags.filter(Boolean).slice(0, 2)
  const metadata = [cuisines.join(' · '), price ? `约 ¥${Math.round(price)}/人` : '', distance !== null ? formatDistance(distance) : ''].filter(Boolean)

  const stopAndRun = (event: React.MouseEvent, action: () => void) => {
    event.stopPropagation()
    action()
  }

  return <TasteMapActivityCardFrame
    activityRating={mode === 'trending' ? undefined : mode === 'for_you' ? <TasteMapRecommendationSignal input={item} /> : <TasteMapActivityRatingBadge rating={activityRating} />}
    body={<>
      {mode !== 'for_you' && item.visit.note ? <p className="community-note"><strong>笔记</strong>{item.visit.note}</p> : null}
      {mode === 'for_you' && primaryReasons.length ? <section aria-label={evidenceTitle} className="recommendation-evidence"><TasteMapRecommendationReasons reasons={primaryReasons.map((reason) => reason.text)} />{cautionReason ? <div className="recommendation-evidence__caution"><strong>需要注意</strong><span>{cautionReason.text}</span></div> : null}<small>{recommendationEvidenceHint(item.recommendationConfidence)}</small>{canShowFullAnalysis ? <><button aria-expanded={showFullAnalysis} onClick={(event) => stopAndRun(event, () => setShowFullAnalysis((current) => !current))} type="button">查看完整分析 <ChevronDown className={showFullAnalysis ? 'is-open' : ''} size={15} /></button>{showFullAnalysis ? <TasteMapRecommendationReasons className="recommendation-evidence__more" reasons={secondaryReasons.map((reason) => reason.text)} /> : null}</> : null}</section> : <TasteMapRecommendationReasons reasons={primaryReasons.map((reason) => reason.text)} />}
    </>}
    header={mode !== 'for_you' ? <><button className="tm-activity-card__user" onClick={(event) => stopAndRun(event, () => onViewProfile(item.user))} type="button"><UserAvatar alt="" avatarImageData={item.user.avatarImageData} avatarPhotoId={item.user.avatarPhotoId} avatarPresetId={item.user.avatarPresetId} membershipTier={item.user.membershipTier} /><span><strong>{item.user.nickname}{item.user.membershipTier === 'member' ? <PremiumBurgerBadge /> : null}</strong><small>{formatVisitDateTime(item.visit.visitedAt)} · 公开到访</small></span></button>{mode === 'similar' && item.similarity != null ? <span className="similarity-pill">口味相似 {item.similarity}%</span> : null}</> : undefined}
    mediaCount={isActivity ? media.length : 1}
    media={isActivity && media.length
      ? <TasteMapActivityMedia name={item.restaurant.name} onOpen={onOpen} images={media.map((photo, index) => <RestaurantContentImage name={item.restaurant.name} tags={item.restaurant.tags} key={`${item.visit.id}-media-${index}`} photos={[photo]} />)} />
      : <button aria-label={`查看 ${item.restaurant.name} 详情`} onClick={(event) => stopAndRun(event, onOpen)} type="button"><RestaurantContentImage name={item.restaurant.name} tags={item.restaurant.tags} photos={media} /></button>}
    onOpen={onOpen}
    restaurant={<div className="community-restaurant"><div className="community-restaurant__body"><strong>{item.restaurant.name}</strong>{mode === 'for_you' && metadata.length ? <small>{metadata.join(' · ')}</small> : null}<span><MapPin aria-hidden="true" size={12} /><span>{item.restaurant.city} · {item.restaurant.address}</span><button aria-label={`查看餐厅 ${item.restaurant.name}`} className="tm-activity-card__restaurant-detail-icon" onClick={(event) => stopAndRun(event, onOpen)} title="查看餐厅信息" type="button"><Store aria-hidden="true" size={13} /></button></span></div></div>}
    restaurantActions={<RestaurantQuickActions
      className="discovery-card-quick-actions"
      onRecordVisit={() => onMarkVisited(item.restaurant)}
      onToggleWant={() => {
        if (!wanted) trackDiscoveryRecommendationEvent('wantToGoAdded', item as CommunityVisit)
        onToggleWant(item.restaurant)
      }}
      onToggleWheel={() => {
        if (!selected) trackDiscoveryRecommendationEvent('wheelCandidateAdded', item as CommunityVisit)
        onToggleCandidate(item.restaurant)
      }}
      restaurantName={item.restaurant.name}
      visitedActive={item.viewerRestaurantStatus === 'visited'}
      wantActive={wanted}
      wheelActive={selected}
    />}
    socialActions={<><TasteMapSocialAction label={engagement.liked ? '取消点赞' : '点赞'} pressed={engagement.liked} count={engagement.likeCount} onClick={onLike} icon={<Heart fill={engagement.liked ? 'currentColor' : 'none'} />} /><TasteMapSocialAction label="评论" count={engagement.comments.length} onClick={onComment} icon={<MessageCircle />} /><TasteMapSocialAction label="分享餐厅" onClick={onShare} icon={<Send />} /></>}
    variant={mode === 'for_you' ? 'recommendation' : 'activity'}
  />
}

function feedScore(item: FeedItem) {
  return item.publicRating?.value ?? item.restaurant.scoreOutOfTen ?? 0
}

function dedupeRecommendationReasons<T extends { text: string }>(reasons: T[]) {
  const seen = new Set<string>()
  return reasons.filter((reason) => {
    const normalized = reason.text.trim()
    if (!normalized || seen.has(normalized)) return false
    seen.add(normalized)
    return true
  })
}

function isHighValueRecommendationReason(reason: { code?: string; text: string }) {
  const highValueCodes = new Set(['HIGH_CUISINE_MATCH', 'PRICE_RANGE_MATCH', 'REPEAT_VISIT_PATTERN', 'COMPANION_CONTEXT_MATCH', 'SOURCE_AFFINITY_MATCH', 'SHORT_TERM_DIVERSITY', 'SIMILAR_USERS'])
  if (reason.code && highValueCodes.has(reason.code)) return true
  return !/(当前城市|当前位置|附近|距离你|公开高分|综合长期口味|符合你的偏好|值得一试)/.test(reason.text)
}

function isRecommendationCaution(text: string) {
  return /(略高|高于|排队|拥挤|较远|样本较少|记录仍较少|不多)/.test(text)
}

function recommendationEvidenceHint(confidence: CommunityVisit['recommendationConfidence']) {
  if (confidence === 'high') return '基于较充分的历史记录与相关到访'
  if (confidence === 'medium') return '基于现有历史记录，证据仍在积累'
  return '当前相关记录较少，推荐仅供探索参考'
}

function recommendationMedia(item: FeedItem) {
  const sources = [
    ...visitActivityMedia(item.visit.photos, item.visit.photoIds),
    ...item.visit.dishes.map((dish) => ({ source: dish.imageData || '', photoId: dish.photoId })),
  ].filter((photo) => Boolean(photo.source || photo.photoId))
  const uniquePhotos = new Map<string, { source: string; photoId: string | null }>()
  sources.forEach((photo) => {
    const key = photo.photoId || photo.source
    if (!uniquePhotos.has(key)) uniquePhotos.set(key, photo)
  })
  return [...uniquePhotos.values()].slice(0, 3)
}

function formatDistance(distance: number) {
  return distance < 1 ? `${Math.max(10, Math.round(distance * 1000 / 10) * 10)} m` : `${distance.toFixed(distance < 10 ? 1 : 0)} km`
}

function communityRestaurant(item: CommunityVisit): RestaurantSummary {
  return {
    ...item.restaurant, userId: item.visit.userId, status: 'visited', preferenceLevel: 'normal', overallRating: null, isRecommendation: true,
    foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags: item.restaurant.tags ?? [], longTermNote: '', pricePerPerson: item.restaurant.pricePerPerson ?? item.visit.pricePerPerson,
    markerType: item.restaurant.merchantImageUrl ? 'image' : 'emoji', markerImageData: null, markerPhotoId: null, markerEmoji: item.restaurant.markerEmoji || '🍽️', createdAt: item.visit.createdAt,
    updatedAt: item.visit.updatedAt, deletedAt: null, visitCount: 1, averageRating: item.visit.rating, scoreOutOfTen: item.visit.rating ? item.visit.rating * 2 : null,
    latestVisitDate: item.visit.visitedAt, latestVisit: item.visit, visits: [item.visit], averagePricePerPerson: item.visit.pricePerPerson, averageQueueMinutes: null,
  }
}

function findMatchingRestaurant(restaurants: RestaurantSummary[], remote: CommunityVisit['restaurant']) {
  return restaurants.find((restaurant) => restaurant.id === remote.id
    || Boolean(restaurant.amapPoiId && remote.amapPoiId && restaurant.amapPoiId === remote.amapPoiId)
    || (normalizeRestaurantIdentity(restaurant.name) === normalizeRestaurantIdentity(remote.name)
      && normalizeRestaurantIdentity(restaurant.address) === normalizeRestaurantIdentity(remote.address)))
}

function normalizeRestaurantIdentity(value: string) {
  return value.toLocaleLowerCase('zh-CN').replace(/[\s·•・()（）\-—_]/g, '')
}

function readCommunityEngagement(): Record<string, CommunityEngagement> {
  try {
    const raw = localStorage.getItem(COMMUNITY_ENGAGEMENT_STORAGE_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as Record<string, Partial<CommunityEngagement>>
    return Object.fromEntries(Object.entries(parsed).map(([visitId, value]) => [visitId, {
      liked: Boolean(value.liked),
      likeCount: typeof value.likeCount === 'number' ? value.likeCount : 0,
      comments: Array.isArray(value.comments) ? value.comments.filter((comment): comment is string => typeof comment === 'string') : [],
    }]))
  } catch {
    return {}
  }
}
