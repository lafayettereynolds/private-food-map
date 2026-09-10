import { restaurantCategoryLabels } from '../../utils/restaurantCategoryLabels'
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { usePremiumAccess } from '../../components/PremiumAccess'
import { UserAvatar } from '../../components/UserAvatar'
import { LockKeyhole } from 'lucide-react'
import { TasteMapPredictedLiking } from '../../components/TasteMapPredictedLiking'
import {
  Heart, MapPin, Star, Users, Image, CircleCheck,
  MessageCircle, Send as SendIcon, SlidersHorizontal, Store,
} from 'lucide-react'
import {
  TasteMapActivityCardFrame,
  TasteMapActivityRatingBadge,
  TasteMapRecommendationReasons,
  TasteMapRecommendationSignal,
  TasteMapSocialAction,
  TasteMapDiscoveryScaffold,
  TasteMapFilterBar,
  TasteMapFilterSelect,
} from '../../components/TasteMapDiscoveryShared'
import type {
  TasteMapHybridActivityItemDTO,
  TasteMapHybridActivityInteractionDTO,
  TasteMapCommunityCommentDTO,
  TasteMapCommunityEngagementDTO,
  TasteMapHybridContentSnapshotDTO,
  TasteMapHybridDiscoveryItemDTO,
  TasteMapDiscoveryCityPageDTO,
  TasteMapDiscoveryCityPageRequest,
  TasteMapPlatform,
  TasteMapProfileDashboardViewModel,
} from '../../platform/TasteMapPlatform'
import {
  isDiscoveryFeedActivityEligible,
  isDiscoveryPlacementEligible,
} from '../../platform/TasteMapDiscoveryPolicy'
import { HybridState } from '../../components/TasteMapHybridShared'
import { DiscoveryAvailabilityState } from '../../components/DiscoveryAvailabilityState'
import { RecommendationEvidence } from '../../components/RecommendationEvidence'
import { HybridRestaurantContentImage } from '../../components/RestaurantContentImage'
import { recommendationIsDismissed } from '../../services/recommendationIntent'
import { RestaurantQuickActions } from '../../components/RestaurantQuickActions'
import { TasteMapActivityMedia } from '../../components/TasteMapActivityMedia'
import { HYBRID_DISCOVERY_PRIMARY_TABS } from './HybridProductContracts'
import { ModalShell } from '../../components/ModalShell'
import { RecommendationNotInterested, useRecommendationPreferences } from '../../components/RecommendationNotInterested'
import { CommunityCommentList } from '../../components/CommunityCommentList'
import { UGCSafetyMenu } from '../../components/UGCSafetyMenu'
import { useUGCSafetyState } from '../../components/ugcSafetyState'
import { starToTenScore } from '../../types/domain'
import { TasteMapCitySearch } from '../../components/TasteMapCitySearch'
import { usesCanonicalForYou } from '../../components/discoveryDefaultScope'
import { DiscoveryQueryPanel } from '../../components/DiscoveryQueryPanel'
import { normalizeDiscoveryFilters } from '../../contracts/discoveryFilters'
import { DISCOVERY_RATING_FILTER_THRESHOLDS, minimumRatingFilterLabel } from '../../utils/ratingFilterOptions'
import { normalizeDiscoverySessionPreferences, type DiscoverySessionPreferences } from '../../contracts/discoverySessionPreferences'
import { createDiscoveryCityQuerySession, discoveryCityQueryKey, type CityQueryState } from '../../components/discoveryCityQuerySession'

type DiscoveryTab = typeof HYBRID_DISCOVERY_PRIMARY_TABS[number][0]
const tabs = HYBRID_DISCOVERY_PRIMARY_TABS.map(([value, label]) => ({ value, label }))

interface CommentContext {
  target: TasteMapHybridActivityInteractionDTO
  restaurantName: string
}

export function HybridDiscoveryPage({ content, platform, profile, onOpenPremium, onAddRestaurant, onOpenRestaurant, onRecordVisit, onOpenRoulette, candidateRestaurantIDs = [], active = true, loading = false, loadError = null, onRetry }: {
  content: TasteMapHybridContentSnapshotDTO
  platform: TasteMapPlatform
  profile?: TasteMapProfileDashboardViewModel
  onOpenPremium?: () => void
  onAddRestaurant?: () => void
  onOpenRestaurant: (id: string) => void
  onRecordVisit?: (restaurantID: string) => void
  onOpenRoulette?: (restaurantID: string) => void
  candidateRestaurantIDs?: string[]
  active?: boolean
  loading?: boolean
  loadError?: string | null
  onRetry?: () => void
}) {
  const [tab, setTab] = useState<DiscoveryTab>('forYou')
  const premiumVisible = usePremiumAccess()
  const [entitlement, setEntitlement] = useState<'loading' | 'free' | 'premium' | 'unavailable'>('loading')
  const [entitlementRevision, setEntitlementRevision] = useState(0)
  useEffect(() => {
    if (!active || tab !== 'similarTaste') return
    let current = true
    setEntitlement('loading')
    const timeout = window.setTimeout(() => { if (current) { current = false; setEntitlement('unavailable') } }, 10_000)
    void platform.premium.status().then((status) => {
      if (current) setEntitlement(status.state)
    }).catch(() => { if (current) setEntitlement('unavailable') }).finally(() => window.clearTimeout(timeout))
    return () => { current = false; window.clearTimeout(timeout) }
  }, [platform, profile?.user.id, profile?.user.membershipTier, active, tab, entitlementRevision])
  const [city, setCity] = useState('all')
  const [detectedCity, setDetectedCity] = useState('')
  useEffect(() => {
    if (!active || city !== 'all') return
    let current = true
    void platform.location.current().then(value => {
      if (!current || !value.detectedCity?.trim()) return
      setDetectedCity(value.detectedCity.trim())
      onRetry?.()
    }).catch(() => undefined)
    return () => { current = false }
  }, [platform, profile?.user.id, active, city])
  const [sorts, setSorts] = useState<Record<string, NonNullable<TasteMapDiscoveryCityPageRequest['sort']>>>({})
  const [windows, setWindows] = useState<Record<string, 7 | 30>>({})
  const [sessionPreferences, setSessionPreferences] = useState<Record<string, DiscoverySessionPreferences>>({})
  const [hardFilters, setHardFilters] = useState(() => normalizeDiscoveryFilters())
  const [recordStateExplicit, setRecordStateExplicit] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const openFilters = () => setFiltersOpen(true)
  const [viewerStates, setViewerStates] = useState<Record<string, 'none' | 'want_to_go' | 'visited'>>({})
  const [engagement, setEngagement] = useState<Record<string, TasteMapCommunityEngagementDTO>>({})
  const [pendingLikes, setPendingLikes] = useState<Set<string>>(new Set())
  const [pendingWant, setPendingWant] = useState<Set<string>>(new Set())
  const [commentContext, setCommentContext] = useState<CommentContext | null>(null)
  const [comments, setComments] = useState<TasteMapCommunityCommentDTO[]>([])
  const [commentText, setCommentText] = useState('')
  const [commentsLoading, setCommentsLoading] = useState(false)
  const [commentsError, setCommentsError] = useState<string | null>(null)
  const commentRequestSequence = useRef(0)
  const commentReturnScroll = useRef({ top: 0, left: 0 })
  const [commentSubmitting, setCommentSubmitting] = useState(false)
  const [message, setMessage] = useState('')
  const scrollPosition = useRef(0)
  const recommendationPreferences = useRecommendationPreferences(platform)
  const cityMode: TasteMapDiscoveryCityPageRequest['mode'] = tab === 'forYou' ? 'for_you' : tab === 'similarTaste' ? 'similar_taste' : tab
  const selectedCity = city === 'all' ? detectedCity || content.discovery.refreshStatus?.for_you?.city || profile?.user.city?.trim() || '' : city
  const personalized = tab === 'forYou' || tab === 'similarTaste'
  const sort = sorts[tab] ?? (tab === 'trending' ? 'trend' : tab === 'latest' || tab === 'following' ? 'latest' : 'recommended')
  const windowDays = windows[tab] ?? 7
  const preferences = useMemo(() => sessionPreferences[tab] ?? normalizeDiscoverySessionPreferences(), [sessionPreferences, tab])
  const filters = useMemo(() => ({ ...hardFilters, minimumPublicScoreOutOfTen: null, minimumPublicRatingUsers: null,
    minimumPredictedLikingOutOfTen: tab === 'forYou' ? hardFilters.minimumPredictedLikingOutOfTen : null,
    minimumTasteMatchPercent: tab === 'forYou' ? hardFilters.minimumTasteMatchPercent : null,
    viewerStates: recordStateExplicit ? hardFilters.viewerStates : personalized ? ['none' as const] : [] }), [hardFilters, recordStateExplicit, personalized, tab])
  const query = useMemo(() => ({ mode: cityMode, city: selectedCity, windowDays, sort, filters, ...(personalized ? { preferences } : {}) }), [cityMode, selectedCity, windowDays, sort, filters, personalized, preferences])
  const [cityState, setCityState] = useState<CityQueryState<TasteMapDiscoveryCityPageDTO>>({ key: null, page: null, loading: false, appending: false, error: null })
  const citySession = useMemo(() => createDiscoveryCityQuerySession<TasteMapDiscoveryCityPageRequest & { windowDays: 7 | 30 }, TasteMapDiscoveryCityPageDTO>({
    load: (query) => platform.discovery?.cityPage
      ? platform.discovery.cityPage(query)
      : Promise.reject(new Error('此版本暂未连接城市查询，请更新后重试。')),
    owner: async () => { const session = await platform.auth.sessionStatus(); return session.state === 'authenticated' ? session.userID : null },
    publish: setCityState,
  }), [platform])
  const canonicalScope = usesCanonicalForYou(city === 'all', query)
  const cityKey = canonicalScope ? null : discoveryCityQueryKey(query)
  const cityPage = cityKey && cityState.key === cityKey ? cityState.page : null
  const cityLoading = canonicalScope ? loading && !content.discovery.forYou.length : Boolean(cityKey && (cityState.key !== cityKey || cityState.loading))
  const feedbackKey = recommendationPreferences.ready ? JSON.stringify([recommendationPreferences.ownerID, recommendationPreferences.excludedIDs, recommendationPreferences.intentFeedback]) : null
  const previousFeedbackKey = useRef<string | null>(null)
  useEffect(() => {
    const previous = previousFeedbackKey.current
    previousFeedbackKey.current = feedbackKey
    if (feedbackKey && previous && previous !== feedbackKey && cityMode === 'for_you') {
      if (canonicalScope) onRetry?.(); else void citySession.retry()
    }
  }, [feedbackKey, cityMode, citySession, canonicalScope, onRetry])
  useEffect(() => {
    // Local optimistic state from the default feed must not shadow a newly
    // hydrated city response for the same Restaurant / Visit.
    setViewerStates({}); setEngagement({}); setCommentContext(null)
    void citySession.select(canonicalScope ? null : query)
    return () => citySession.invalidate()
  }, [citySession, selectedCity, query, canonicalScope])
  useEffect(() => {
    let cancelled = false
    const subscription = platform.events.subscribe((event) => {
      if (cancelled) return
      if (event.name === 'data.changed' && (event.payload.reason === 'communityUserBlocked' || event.payload.reason === 'communityCommentDeleted')) {
        if (canonicalScope) onRetry?.(); else void citySession.retry()
        return
      }
      // The optimistic refresh can precede the server acknowledgement. Requery
      // after sync as well, so the ranked page uses the persisted feedback.
      if (event.name === 'data.changed' && event.payload.reason === 'recommendationPreferenceSynced') {
        if (cityMode === 'for_you') { if (canonicalScope) onRetry?.(); else void citySession.retry() }
        return
      }
      if (event.name === 'data.changed' && event.payload.reason === 'syncCompleted') {
        if (!canonicalScope) void citySession.refreshAutomatically()
        return
      }
      if (event.name !== 'auth.changed') return
      citySession.invalidate()
      setViewerStates({}); setEngagement({}); setCommentContext(null)
      // Never carry the previous account's private query or editor context over.
      setCity('all'); setDetectedCity(''); setSorts({}); setWindows({}); setSessionPreferences({}); setHardFilters(normalizeDiscoveryFilters()); setRecordStateExplicit(false)
      setFiltersOpen(false); setTab('forYou'); setComments([]); setCommentText('')
      commentRequestSequence.current += 1
      scrollPosition.current = 0
    })
    return () => { cancelled = true; void subscription.then((value) => value.remove()).catch(() => undefined) }
  }, [platform, citySession, selectedCity, cityMode, canonicalScope, onRetry])

  useEffect(() => {
    if (!active) {
      scrollPosition.current = window.scrollY
      return
    }
    window.requestAnimationFrame(() => window.scrollTo({ top: scrollPosition.current }))
  }, [active])

  useEffect(() => {
    const items = [
      ...content.discovery.forYou, ...content.discovery.similarTaste, ...content.discovery.trending,
      ...content.community.following, ...content.community.latest,
    ]
    setViewerStates((current) => {
      const next = { ...current }
      for (const item of items) next[item.restaurant.id] ??= item.viewerState
      return next
    })
    setEngagement((current) => {
      const next = { ...current }
      for (const item of items) {
        if (!item.interaction) continue
        next[item.interaction.visitID] ??= {
          likedByViewer: item.likedByViewer,
          likeCount: item.likeCount,
          commentCount: item.commentCount,
        }
      }
      return next
    })
  }, [content])
  const cityDiscovery = useMemo(() => cityPage?.discoveryItems.map((item) => cityPage.engagementState === 'known' && cityPage.interactionsAvailable ? item : { ...item, interaction: null }) ?? [], [cityPage])
  const cityActivity = useMemo(() => cityPage?.activityItems.map((item) => cityPage.engagementState === 'known' && cityPage.interactionsAvailable ? item : { ...item, interaction: null }) ?? [], [cityPage])
  const forYouSource = canonicalScope ? content.discovery.forYou : cityDiscovery
  const canonicalForYou = useMemo(
    () => !recommendationPreferences.ready ? [] : forYouSource.filter(item => !recommendationIsDismissed(item.restaurant, recommendationPreferences)),
    [forYouSource, recommendationPreferences.excludedIDs, recommendationPreferences.intentFeedback, recommendationPreferences.ready],
  )
  const discovery = tab === 'forYou' ? canonicalForYou : cityDiscovery
  const activity = cityActivity
  const discoveryMode = tab === 'forYou' ? 'for_you' : tab === 'similarTaste' ? 'similar_taste' : tab === 'trending' ? 'trending' : null
  const refreshStatus = canonicalScope ? content.discovery.refreshStatus?.for_you : cityPage?.refreshStatus
  const evidenceAvailability = canonicalScope ? content.discovery.evidenceAvailability?.for_you : cityPage?.evidenceAvailability
  const currentReadError = (canonicalScope ? loadError : cityState.error) ?? refreshStatus?.issue?.message
  const retryCurrentCity = () => { if (canonicalScope) onRetry?.(); else void citySession.retry() }
  const citySource = tab === 'following' || tab === 'latest' ? activity.map((item) => item.restaurant.city) : discovery.map((item) => item.restaurant.city)
  const cities = useMemo(() => [...new Set(citySource.filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')), [citySource])
  // Filters and ranking are applied to the full qualified server candidate set,
  // never to the already-loaded first page.
  const visibleDiscovery = useMemo(() => discovery.filter(isDiscoveryPlacementEligible), [discovery])
  const visibleActivity = useMemo(() => activity.filter(isDiscoveryFeedActivityEligible), [activity])
  const activeFilterCount = Number(filters.cuisines.length > 0) + Number(filters.types.length > 0) + Number(filters.minimumPredictedLikingOutOfTen != null) + Number(filters.minimumTasteMatchPercent != null) + Number(filters.requireActualPhoto) + Number(filters.distance != null) + Number(filters.viewerStates.length > 0)
  const changeCity = (value: string) => {
    if (value === selectedCity) return
    setCity(value || 'all')
    setHardFilters(current => ({ ...current, distance: null }))
    setSorts(current => Object.fromEntries(Object.entries(current).map(([key, value]) => [key, value === 'distance' ? 'recommended' : value])))
    setSessionPreferences(current => Object.fromEntries(Object.entries(current).map(([key, preference]) => [key, { ...preference, nearby: false, reference: null }])))
    if (filters.distance || Object.values(sessionPreferences).some(value => value.reference)) setMessage('已切换城市，并清除原城市的距离范围与附近偏好。')
  }
  const filterTags: Array<{ label: string; clear: () => void }> = [
    ...(filters.priceRange ? [{ label: `参考人均 ¥${filters.priceRange.minimum}–${filters.priceRange.maximumExclusive ?? '不限'}`, clear: () => setHardFilters(current => ({ ...current, priceRange: null })) }] : []),
    ...filters.cuisines.map(value => ({ label: value, clear: () => setHardFilters(current => ({ ...current, cuisines: current.cuisines.filter(item => item !== value) })) })),
    ...filters.types.map(value => ({ label: value, clear: () => setHardFilters(current => ({ ...current, types: current.types.filter(item => item !== value) })) })),
    ...(filters.minimumPredictedLikingOutOfTen == null ? [] : [{ label: `预计喜欢度 ≥ ${filters.minimumPredictedLikingOutOfTen} 分`, clear: () => setHardFilters(current => ({ ...current, minimumPredictedLikingOutOfTen: null })) }]),
    ...(filters.minimumTasteMatchPercent == null ? [] : [{ label: `口味匹配度 ≥ ${filters.minimumTasteMatchPercent}%`, clear: () => setHardFilters(current => ({ ...current, minimumTasteMatchPercent: null })) }]),
    ...(filters.requireActualPhoto ? [{ label: '有实拍', clear: () => setHardFilters(current => ({ ...current, requireActualPhoto: false })) }] : []),
    ...(filters.distance ? [{ label: `${filters.distance.maximumMeters} 米以内`, clear: () => {
      setHardFilters(current => ({ ...current, distance: null }))
      setSorts(current => Object.fromEntries(Object.entries(current).map(([key, value]) => [key, value === 'distance' ? 'recommended' : value])))
    } }] : []),
  ]

  const viewerStateFor = (restaurantID: string, fallback: 'none' | 'want_to_go' | 'visited') => viewerStates[restaurantID] ?? fallback
  const engagementFor = (target: TasteMapHybridActivityInteractionDTO, fallback: TasteMapCommunityEngagementDTO) => engagement[target.visitID] ?? fallback

  async function toggleLike(target: TasteMapHybridActivityInteractionDTO, fallback: TasteMapCommunityEngagementDTO) {
    if (pendingLikes.has(target.visitID)) return
    const previous = engagementFor(target, fallback)
    const liked = !previous.likedByViewer
    const optimistic = { ...previous, likedByViewer: liked, likeCount: Math.max(0, previous.likeCount + (liked ? 1 : -1)) }
    setEngagement((current) => ({ ...current, [target.visitID]: optimistic }))
    setPendingLikes((current) => new Set(current).add(target.visitID))
    try {
      const result = await platform.community.setLike(target, liked)
      setEngagement((current) => ({ ...current, [target.visitID]: result }))
    } catch {
      setEngagement((current) => ({ ...current, [target.visitID]: previous }))
      setMessage('点赞没有保存，请重试。')
    } finally {
      setPendingLikes((current) => { const next = new Set(current); next.delete(target.visitID); return next })
    }
  }

  useEffect(() => () => { commentRequestSequence.current += 1 }, [])

  async function loadComments(context: CommentContext) {
    const sequence = ++commentRequestSequence.current
    setCommentsLoading(true)
    setCommentsError(null)
    try {
      const page = await platform.community.comments(context.target)
      if (sequence !== commentRequestSequence.current) return
      setComments(page.items)
    } catch {
      if (sequence !== commentRequestSequence.current) return
      setCommentsError('评论暂时无法加载，请重试。')
    } finally {
      if (sequence === commentRequestSequence.current) setCommentsLoading(false)
    }
  }

  function openComments(context: CommentContext) {
    commentReturnScroll.current = { top: window.scrollY, left: window.scrollX }
    setCommentContext(context)
    setCommentText('')
    setComments([])
    void loadComments(context)
  }

  function closeComments() {
    commentRequestSequence.current += 1
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    setCommentContext(null)
    window.requestAnimationFrame(() => window.scrollTo({ ...commentReturnScroll.current, behavior: 'instant' }))
  }

  async function submitComment(event: FormEvent) {
    event.preventDefault()
    const body = commentText.trim()
    if (!commentContext || !body || commentSubmitting) return
    setCommentSubmitting(true)
    try {
      const result = await platform.community.addComment(commentContext.target, body)
      setComments((current) => [...current, result.comment])
      setEngagement((current) => ({ ...current, [commentContext.target.visitID]: result }))
      setCommentText('')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : '评论没有发送，请重试。')
    } finally {
      setCommentSubmitting(false)
    }
  }

  async function toggleWantToGo(restaurantID: string, fallback: 'none' | 'want_to_go' | 'visited') {
    if (pendingWant.has(restaurantID)) return
    const previous = viewerStateFor(restaurantID, fallback)
    if (previous === 'visited') return
    const wanted = previous !== 'want_to_go'
    setViewerStates((current) => ({ ...current, [restaurantID]: wanted ? 'want_to_go' : 'none' }))
    setPendingWant((current) => new Set(current).add(restaurantID))
    try {
      const result = await platform.restaurant.setWantToGo(restaurantID, wanted)
      setViewerStates((current) => ({ ...current, [restaurantID]: result.viewerState }))
      setMessage(result.viewerState === 'want_to_go' ? '已加入想吃。' : result.viewerState === 'none' ? '已移出想吃。' : '这家餐厅已经去过。')
    } catch {
      setViewerStates((current) => ({ ...current, [restaurantID]: previous }))
      setMessage('想吃状态没有保存，请重试。')
    } finally {
      setPendingWant((current) => { const next = new Set(current); next.delete(restaurantID); return next })
    }
  }

  const filterBar = <>
    <TasteMapFilterBar>
      <button aria-haspopup="dialog" aria-expanded={filtersOpen} className={activeFilterCount ? 'is-active' : ''} onClick={openFilters} type="button">
        <SlidersHorizontal aria-hidden="true" size={14} />筛选 · {activeFilterCount}
      </button>
      <TasteMapCitySearch city={selectedCity} suggestions={cities} onChange={changeCity} />
      <TasteMapFilterSelect presentation="dialog" icon={<CircleCheck aria-hidden="true" size={14} />} label="去过状态" value={filters.viewerStates[0] ?? ''}
        active={filters.viewerStates.length > 0}
        options={[{ value: '', label: '全部状态' }, { value: 'none', label: '未去过' }, { value: 'visited', label: '去过' }, { value: 'want_to_go', label: '想吃' }]}
        onChange={value => { setRecordStateExplicit(true); setHardFilters(current => ({ ...current, viewerStates: value ? [value as 'none' | 'visited' | 'want_to_go'] : [] })) }} />
      {tab === 'forYou' ? <>
        <TasteMapFilterSelect presentation="dialog" icon={<Star aria-hidden="true" size={14} />} label="预计喜欢度" value={String(filters.minimumPredictedLikingOutOfTen ?? '')}
          active={filters.minimumPredictedLikingOutOfTen != null}
          options={[{ value: '', label: '预计喜欢度' }, ...DISCOVERY_RATING_FILTER_THRESHOLDS.map(value => ({ value: String(value), label: minimumRatingFilterLabel(value) }))]}
          onChange={value => setHardFilters(current => ({ ...current, minimumPredictedLikingOutOfTen: value ? Number(value) : null }))} />
        <TasteMapFilterSelect presentation="dialog" icon={<Users aria-hidden="true" size={14} />} label="口味匹配度" value={String(filters.minimumTasteMatchPercent ?? '')}
          active={filters.minimumTasteMatchPercent != null}
          options={[{ value: '', label: '口味匹配度' }, ...[10,20,30,40,50,60,70,80,90,100].map(value => ({ value: String(value), label: `${value}% 以上` }))]}
          onChange={value => setHardFilters(current => ({ ...current, minimumTasteMatchPercent: value ? Number(value) : null }))} />
      </> : null}
      <TasteMapFilterSelect presentation="dialog" icon={<Image aria-hidden="true" size={14} />} label="实拍照片" value={filters.requireActualPhoto ? 'yes' : ''}
        active={filters.requireActualPhoto} options={[{ value: '', label: '实拍照片' }, { value: 'yes', label: '仅有实拍' }]}
        onChange={value => setHardFilters(current => ({ ...current, requireActualPhoto: value === 'yes' }))} />
      {filterTags.map(tag => <button key={tag.label} className="is-active" type="button" aria-label={`清除${tag.label}`} onClick={tag.clear}>{tag.label}<span aria-hidden="true">×</span></button>)}
    </TasteMapFilterBar>
  </>

  return <main className="tm-hybrid-page tm-hybrid-discovery" data-discovery-tab={tab} hidden={!active}>
    <TasteMapDiscoveryScaffold
      className="tm-hybrid-discovery__shared"
      description={cityPage?.dataSource === 'debug_city_fixture' ? '模拟数据' : '按照你的口味，找到更值得参考的人和下一家餐厅。'}
      filterBar={filterBar}
      onTabChange={setTab}
      tab={tab}
      tabs={tabs.map(item => item.value === 'similarTaste' && !premiumVisible ? { ...item, icon: <LockKeyhole aria-label="会员专享" size={12} /> } : item)}
    >
      {currentReadError && (discoveryMode ? visibleDiscovery.length : visibleActivity.length) > 0 && tab !== 'similarTaste'
        ? <div role="status" className="tm-discovery-city-pagination"><p>{currentReadError} 正在显示上次缓存。</p><button onClick={retryCurrentCity} type="button">重试</button></div> : null}
      {tab === 'similarTaste' && entitlement === 'loading'
        ? <HybridState kind="loading" title="正在确认同味权益" message="会员权限与推荐证据会分别核对。" />
        : tab === 'similarTaste' && entitlement === 'unavailable'
        ? <HybridState kind="error" title="暂时无法确认会员状态" message="尚未确认权益，不会把已开通的会员当作未开通。请重试核对。" action={<button type="button" onClick={() => setEntitlementRevision(value => value + 1)}>重新确认权益</button>} />
        : tab === 'similarTaste' && currentReadError && refreshStatus?.issue?.code !== 'membership_required'
        ? <HybridState kind="error" title="发现内容暂未更新" message={currentReadError} action={refreshStatus?.issue?.recoverable !== false ? <button type="button" onClick={retryCurrentCity}>重试</button> : undefined} />
        : tab === 'similarTaste' && entitlement === 'free'
        ? <DiscoveryAvailabilityState membership="free" onPremium={onOpenPremium} onCity={openFilters} onForYou={() => setTab('forYou')} />
        : tab === 'forYou' && !recommendationPreferences.ready
        ? <HybridState kind={recommendationPreferences.error ? 'error' : 'loading'} title="正在读取推荐偏好" message={recommendationPreferences.error ?? '读取完成后显示推荐。'} action={recommendationPreferences.error ? <button type="button" onClick={() => void recommendationPreferences.retry()}>重试</button> : undefined} />
        : cityLoading
        ? <HybridState kind="loading" message="推荐与动态会在读取完成后自动出现。" title="正在整理发现内容" />
        : refreshStatus?.state === 'restricted' || (currentReadError && !(discoveryMode ? visibleDiscovery.length : visibleActivity.length))
        ? <HybridState kind="error" title={refreshStatus?.state === 'restricted' ? '暂时无法访问这部分发现内容' : '发现内容暂未更新'} message={currentReadError ?? '请确认访问权限后重试。'} action={refreshStatus?.issue?.recoverable !== false ? <button onClick={retryCurrentCity} type="button">重试</button> : undefined} />
        : tab === 'following' || tab === 'latest'
        ? visibleActivity.length
          ? <section aria-label={`${tabs.find((item) => item.value === tab)?.label}动态`} className="tm-hybrid-activity-feed">{visibleActivity.map((item) => <ActivityCard
              engagement={item.interaction ? engagementFor(item.interaction, item) : item}
              item={item}
              key={item.id}
              likePending={Boolean(item.interaction && pendingLikes.has(item.interaction.visitID))}
              onComment={(target) => void openComments({ target, restaurantName: item.restaurant.name })}
              onLike={(target) => void toggleLike(target, item)}
              onOpenRestaurant={onOpenRestaurant}
              onOpenRoulette={(id) => { onOpenRoulette?.(id) }}
              wheelActive={candidateRestaurantIDs.includes(item.restaurant.id)}
              onRecordVisit={(id) => onRecordVisit ? onRecordVisit(id) : void platform.navigation.openHybrid({ surface: 'visit', identifier: id })}
              onToggleWant={(id) => void toggleWantToGo(id, item.viewerState)}
              platform={platform}
              viewerState={viewerStateFor(item.restaurant.id, item.viewerState)}
              wantPending={pendingWant.has(item.restaurant.id)}
            />)}</section>
          : <HybridState kind="empty" message={tab === 'following' ? '关注用户有新的公开到访后，会在这里出现。' : '还没有可见的最新公开动态。'} title={tab === 'following' ? '关注动态暂时为空' : '暂无最新动态'} />
        : visibleDiscovery.length
          ? <section aria-label={`${tabs.find((item) => item.value === tab)?.label}餐厅`} className="tm-hybrid-activity-feed">{visibleDiscovery.map((item) => <RecommendationCard
              engagement={item.interaction ? engagementFor(item.interaction, item) : item}
              item={item}
              key={item.id}
              likePending={Boolean(item.interaction && pendingLikes.has(item.interaction.visitID))}
              onComment={(target) => void openComments({ target, restaurantName: item.restaurant.name })}
              onLike={(target) => void toggleLike(target, item)}
              onOpenRestaurant={onOpenRestaurant}
              onOpenRoulette={(id) => { onOpenRoulette?.(id) }}
              wheelActive={candidateRestaurantIDs.includes(item.restaurant.id)}
              onRecordVisit={(id) => onRecordVisit ? onRecordVisit(id) : void platform.navigation.openHybrid({ surface: 'visit', identifier: id })}
              onToggleWant={(id) => void toggleWantToGo(id, item.viewerState)}
              platform={platform}
              viewerState={viewerStateFor(item.restaurant.id, item.viewerState)}
              wantPending={pendingWant.has(item.restaurant.id)}
            />)}</section>
          : activeFilterCount > Number(!recordStateExplicit && personalized)
            ? <HybridState kind="empty" title="当前筛选没有结果" message="没有符合已应用条件的餐厅，不会自动放宽城市、价格或评分门槛。" action={<button type="button" onClick={openFilters}>调整筛选</button>} />
            : tab === 'similarTaste'
              ? <DiscoveryAvailabilityState membership={entitlement === 'premium' ? 'member' : undefined} evidence={evidenceAvailability} onPremium={onOpenPremium} onRecord={onAddRestaurant} onCity={openFilters} onForYou={() => setTab('forYou')} onRetry={retryCurrentCity} />
              : <HybridState kind="empty" message={tab === 'trending' ? '当前城市在近期窗口内还没有足够的真实热度样本。' : '当前城市暂未生成可展示的推荐。可以补充真实到访与评分，或切换城市；会员权限不能替代缺失的证据。'} title={tab === 'trending' ? '趋势样本还不够' : '暂未找到合适的推荐'} action={tab === 'forYou' ? <div className="tm-discovery-availability-actions">{onAddRestaurant ? <button type="button" onClick={onAddRestaurant}>补充到访与评分</button> : null}<button type="button" onClick={openFilters}>切换城市</button></div> : undefined} />}
      {cityPage && !cityLoading && !currentReadError ? <div className="tm-discovery-city-pagination" aria-live="polite">
        {currentReadError ? <p role="alert">{currentReadError}</p> : null}
        <small>{cityPage.resolvedCity || selectedCity} · 已加载 {cityPage.discoveryItems.length + cityPage.activityItems.length} 条{cityPage.pagination === 'complete' ? ' · 本次查询已加载完' : ''}</small>
        {cityPage.pagination === 'more' && cityPage.nextCursor && cityPage.snapshotID ? <button type="button" disabled={cityState.appending} onClick={() => void citySession.more()}>{cityState.appending ? '正在加载…' : currentReadError ? '重试加载更多' : '继续加载'}</button> : null}
        <button type="button" disabled={cityState.appending} onClick={() => void citySession.retry()}>刷新城市结果</button>
      </div> : null}
    </TasteMapDiscoveryScaffold>
    {active && filtersOpen ? <DiscoveryQueryPanel
      initial={{ city: selectedCity, filters, sort, windowDays, preferences }} mode={cityMode} platform={platform}
      onCancel={() => setFiltersOpen(false)}
      onApply={(draft) => {
        if (draft.city !== selectedCity) changeCity(draft.city)
        setHardFilters(draft.filters)
        if (!draft.filters.distance) setSorts(current => Object.fromEntries(Object.entries(current).map(([key, value]) => [key, value === 'distance' ? 'recommended' : value])))
        if (JSON.stringify(draft.filters.viewerStates) !== JSON.stringify(filters.viewerStates)) setRecordStateExplicit(true)
        setSorts(current => ({ ...current, [tab]: draft.sort }))
        setWindows(current => ({ ...current, [tab]: draft.windowDays }))
        setSessionPreferences(current => ({ ...current, [tab]: draft.preferences }))
        setFiltersOpen(false)
      }}
    /> : null}
    {commentContext ? <ModalShell description={commentContext.restaurantName} onClose={closeComments} title="评论">
      <div className="community-comment-panel" data-comment-activity-id={commentContext.target.activityID ?? ''} data-comment-visit-id={commentContext.target.visitID}>
        <CommunityCommentList platform={platform} items={comments} loading={commentsLoading} error={commentsError} onRetry={() => void loadComments(commentContext)} />
        <form onSubmit={(event) => void submitComment(event)}><input aria-label="写下评论" maxLength={280} onChange={(event) => setCommentText(event.target.value)} placeholder="写下评论" value={commentText} /><button aria-label="发送评论" disabled={!commentText.trim() || commentSubmitting} type="submit"><SendIcon size={17} /></button></form>
      </div>
    </ModalShell> : null}
    {message ? <p aria-live="polite" className="community-share-toast" onAnimationEnd={() => setMessage('')}>{message}</p> : null}
  </main>
}

interface CardInteractionProps {
  wheelActive: boolean
  engagement: TasteMapCommunityEngagementDTO
  viewerState: 'none' | 'want_to_go' | 'visited'
  likePending: boolean
  wantPending: boolean
  onLike: (target: TasteMapHybridActivityInteractionDTO) => void
  onComment: (target: TasteMapHybridActivityInteractionDTO) => void
  onRecordVisit: (restaurantID: string) => void
  onToggleWant: (restaurantID: string) => void
  onOpenRoulette: (restaurantID: string) => void
}

function discoveryItemScore(item: TasteMapHybridDiscoveryItemDTO) {
  const rating = item.mode === 'similar_taste'
    ? item.activityRating
    : item.communityRating.valueOutOfFive
  return starToTenScore(rating) ?? -1
}

function discoveryReasons(item: TasteMapHybridDiscoveryItemDTO) {
  const supplied = item.reasons?.map((reason) => reason.text.trim()).filter(Boolean) ?? []
  const fallback = item.reason?.trim() ? [item.reason.trim()] : []
  const semanticFallback = item.mode === 'similar_taste' && item.sharedRestaurantCount != null
    ? [`基于 ${item.sharedRestaurantCount} 家共同评分餐厅，${item.sourceUser?.name ?? '同味用户'}在这家给过高分`]
    : item.mode === 'trending' && item.uniqueVisitorCount != null
      ? [`近 ${item.trendWindowDays ?? 7} 天有 ${item.uniqueVisitorCount} 位用户到访`, ...(item.wantToGoCount ? [`近期有 ${item.wantToGoCount} 位用户加入想吃`] : [])]
      : []
  return [...new Set(supplied.length ? supplied : fallback.length ? fallback : semanticFallback)]
}

function DiscoveryEvidence({ item }: { item: TasteMapHybridDiscoveryItemDTO }) {
  if (item.mode !== 'trending') return <RecommendationEvidence item={item} />
  const reasons = discoveryReasons(item)
  return <TasteMapRecommendationReasons className={`is-${item.mode.replace(/_/g, '-')}`} evidence={item.mode} reasons={reasons} />
}

export function RecommendationCard({ item, platform, onOpenRestaurant, engagement, viewerState, likePending, wantPending, wheelActive, onLike, onComment, onRecordVisit, onToggleWant, onOpenRoulette }: {
  item: TasteMapHybridDiscoveryItemDTO
  platform: TasteMapPlatform
  onOpenRestaurant: (id: string) => void
} & CardInteractionProps) {
  const share = () => void platform.share.open({ title: item.restaurant.name, text: `在 Taste Map 发现：${item.restaurant.name}` })
  const similarTasteSource = item.mode === 'similar_taste' ? item.sourceUser : null
  const target = item.mode === 'similar_taste' ? item.interaction : null
  const reasons = discoveryReasons(item)
  const [photo, setPhoto] = useState<import('../../platform/TasteMapPlatform').TasteMapImageDescriptor | null>(null)
  const safetyVisit = item.interaction?.visitID ?? (photo && 'visitID' in photo ? photo.visitID : null)
  const safety = useUGCSafetyState(platform)
  if ((item.sourceUser && safety.blocked.has(item.sourceUser.id)) || (photo && 'sourceOwnerID' in photo && safety.blocked.has(photo.sourceOwnerID))) return null
  return <TasteMapActivityCardFrame
    safetyAction={safetyVisit ? <UGCSafetyMenu platform={platform} target={{ type: 'visit', id: safetyVisit }} /> : null}
    activityRating={similarTasteSource
      ? <span className="tm-activity-card__similar-rating"><TasteMapActivityRatingBadge prefix={`${similarTasteSource.name}本次到访`} rating={item.activityRating} /></span>
      : item.mode === 'for_you'
        ? <TasteMapRecommendationSignal input={item} />
        : item.mode === 'trending' ? undefined : <CommunityRatingSummary item={item} />}
    body={<>{item.mode === 'for_you' ? <TasteMapPredictedLiking value={item.predictedLiking} /> : null}{reasons.length ? <DiscoveryEvidence item={item} /> : null}</>}
    header={similarTasteSource ? <><button aria-label={`查看同味来源用户 ${similarTasteSource.name}`} className="tm-activity-card__user" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: similarTasteSource.id })} type="button"><ActivityAvatar user={similarTasteSource} /><span><strong>{similarTasteSource.name}</strong><small>{item.activityVisitedAt ? `${formatEventTime(item.activityVisitedAt)} · 公开到访` : '与你口味相近'}</small></span></button>{item.similarityPercent != null ? <span className="similarity-pill">口味相似 {item.similarityPercent}%</span> : null}</> : undefined}
    mediaCount={item.mode === 'similar_taste' ? item.activityImages?.length : 1}
    media={item.mode === 'similar_taste'
      ? <TasteMapActivityMedia name={item.restaurant.name} onOpen={() => onOpenRestaurant(item.restaurant.id)} images={(item.activityImages?.length ? item.activityImages : [undefined]).map((image, index) => <HybridRestaurantContentImage key={index} activityImage={image} restaurant={item.restaurant} />)} />
      : <button aria-label={`${item.restaurant.name} 餐厅图片`} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantContentImage onResolved={setPhoto} restaurant={item.restaurant} /></button>}
    onOpen={() => onOpenRestaurant(item.restaurant.id)}
    restaurant={<RestaurantIdentity item={item} onOpenRestaurant={onOpenRestaurant} />}
    restaurantActions={<RestaurantQuickActions
      wheelActive={wheelActive}
      onRecordVisit={() => onRecordVisit(item.restaurant.id)}
      onToggleWant={() => onToggleWant(item.restaurant.id)}
      onToggleWheel={() => onOpenRoulette(item.restaurant.id)}
      restaurantName={item.restaurant.name}
      visitedActive={viewerState === 'visited'}
      wantActive={viewerState === 'want_to_go'}
      wantPending={wantPending}
    />}
    socialActions={<>
      {target ? <TasteMapSocialAction label={`${engagement.likedByViewer ? '取消点赞' : '点赞'} ${item.restaurant.name}`} pressed={engagement.likedByViewer} pending={likePending} count={engagement.likeCount} onClick={() => onLike(target)} icon={<Heart fill={engagement.likedByViewer ? 'currentColor' : 'none'} />} /> : null}
      {target ? <TasteMapSocialAction label={`评论 ${item.restaurant.name}`} count={engagement.commentCount} onClick={() => onComment(target)} icon={<MessageCircle />} /> : null}
      <TasteMapSocialAction label={`分享餐厅 ${item.restaurant.name}`} onClick={share} icon={<SendIcon />} />
      {item.mode === 'for_you' ? <RecommendationNotInterested platform={platform} restaurantID={item.restaurant.id} restaurantName={item.restaurant.name} /> : null}
    </>}
    variant={item.mode === 'similar_taste' ? 'activity' : 'recommendation'}
  />
}

function ActivityAvatar({ user }: { user: TasteMapHybridActivityItemDTO['user'] }) {
  return <span className="tm-hybrid-avatar-seed"><UserAvatar alt="" avatarPresetId={user.avatarPresetID}
    avatarPhotoId={user.avatarPhotoID} avatarImageData={user.avatarPhotoID
      ? `tastemap-resource://public-photo/${encodeURIComponent(user.avatarPhotoID)}/display` : null} /></span>
}

function ActivityCard({ item, platform, onOpenRestaurant, engagement, viewerState, likePending, wantPending, wheelActive, onLike, onComment, onRecordVisit, onToggleWant, onOpenRoulette }: {
  item: TasteMapHybridActivityItemDTO
  platform: TasteMapPlatform
  onOpenRestaurant: (id: string) => void
} & CardInteractionProps) {
  const target = item.interaction
  const safety = useUGCSafetyState(platform)
  if (safety.blocked.has(item.user.id)) return null
  return <TasteMapActivityCardFrame
    safetyAction={<UGCSafetyMenu platform={platform} target={target ? { type: 'visit', id: target.visitID } : { type: 'user', id: item.user.id }} />}
    activityRating={item.kind === 'visit' ? <TasteMapActivityRatingBadge rating={item.visitRating} /> : undefined}
    body={item.note ? <p>“{item.note}”</p> : undefined}
    header={<button className="tm-activity-card__user" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.user.id })} type="button"><ActivityAvatar user={item.user} /><span><strong>{item.user.name}</strong><small>{formatEventTime(item.eventAt)} · {item.kind === 'visit' ? '公开到访' : '加入想吃'}</small></span></button>}
    mediaCount={item.activityImages?.length}
    media={<TasteMapActivityMedia name={item.restaurant.name} onOpen={() => onOpenRestaurant(item.restaurant.id)} images={(item.activityImages?.length ? item.activityImages : [undefined]).map((image, index) => <HybridRestaurantContentImage key={index} activityImage={image} restaurant={item.restaurant} />)} />}
    onOpen={() => onOpenRestaurant(item.restaurant.id)}
    restaurant={<RestaurantIdentity item={item} onOpenRestaurant={onOpenRestaurant} />}
    restaurantActions={<RestaurantQuickActions
      wheelActive={wheelActive}
      onRecordVisit={() => onRecordVisit(item.restaurant.id)}
      onToggleWant={() => onToggleWant(item.restaurant.id)}
      onToggleWheel={() => onOpenRoulette(item.restaurant.id)}
      restaurantName={item.restaurant.name}
      visitedActive={viewerState === 'visited'}
      wantActive={viewerState === 'want_to_go'}
      wantPending={wantPending}
    />}
    socialActions={<>
      {target ? <TasteMapSocialAction label={`${engagement.likedByViewer ? '取消点赞' : '点赞'} ${item.restaurant.name}`} pressed={engagement.likedByViewer} pending={likePending} count={engagement.likeCount} onClick={() => onLike(target)} icon={<Heart fill={engagement.likedByViewer ? 'currentColor' : 'none'} />} /> : null}
      {target ? <TasteMapSocialAction label={`评论 ${item.restaurant.name}`} count={engagement.commentCount} onClick={() => onComment(target)} icon={<MessageCircle />} /> : null}
      <TasteMapSocialAction label={`分享动态 ${item.restaurant.name}`} onClick={() => void platform.share.open({ title: item.restaurant.name, text: `${item.user.name} 在 Taste Map 记录了 ${item.restaurant.name}` })} icon={<SendIcon />} />
    </>}
    variant="activity"
  />
}

function CommunityRatingSummary({ item }: { item: TasteMapHybridDiscoveryItemDTO }) {
  const value = item.communityRating.valueOutOfFive
  const sampleCount = item.communityRating.sampleCount
  return <span aria-label={value == null || sampleCount < 1 ? '大家评分暂无样本' : `大家评分 ${(value * 2).toFixed(1)}，${sampleCount} 人`} className="tm-activity-card__rating-summary" role="img"><span>大家评分</span><strong>{value == null || sampleCount < 1 ? '—' : (value * 2).toFixed(1)}</strong><small>{sampleCount > 0 ? `${sampleCount} 人` : '暂无样本'}</small></span>
}

function RestaurantIdentity({ item, onOpenRestaurant }: { item: TasteMapHybridDiscoveryItemDTO | TasteMapHybridActivityItemDTO; onOpenRestaurant: (id: string) => void }) {
  const restaurant = item.restaurant
  const metadata = [restaurantCategoryLabels(restaurant.tags).slice(0, 2).join(' · '), restaurant.referencePrice != null ? `约 ¥${Math.round(restaurant.referencePrice)}/人` : ''].filter(Boolean).join(' · ')
  return <button aria-label={`查看餐厅 ${restaurant.name}`} className="tm-activity-card__restaurant-identity" onClick={() => onOpenRestaurant(restaurant.id)} title="查看餐厅信息" type="button"><span className="tm-activity-card__restaurant-copy"><strong>{restaurant.name}</strong>{metadata ? <em>{metadata}</em> : null}<small><MapPin aria-hidden="true" size={12} /><span>{restaurant.city} · {restaurant.address}</span><span aria-hidden="true" className="tm-activity-card__restaurant-detail-icon"><Store size={13} /></span></small></span></button>
}

function formatEventTime(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
}
