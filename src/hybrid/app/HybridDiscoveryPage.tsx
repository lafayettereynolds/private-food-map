import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import {
  ArrowDownUp, BookmarkPlus, Building2, CirclePlus, Dices, Ellipsis, Heart,
  ListPlus, MapPin, MessageCircle, Send as SendIcon, Share2, SlidersHorizontal, Star, UserPlus,
} from 'lucide-react'
import {
  TasteMapActivityCardFrame,
  TasteMapDiscoveryScaffold,
  TasteMapFilterBar,
} from '../../components/TasteMapDiscoveryShared'
import type {
  TasteMapHybridActivityItemDTO,
  TasteMapHybridActivityInteractionDTO,
  TasteMapCommunityCommentDTO,
  TasteMapCommunityEngagementDTO,
  TasteMapHybridContentSnapshotDTO,
  TasteMapHybridDiscoveryItemDTO,
  TasteMapPlatform,
} from '../../platform/TasteMapPlatform'
import { HybridRestaurantImage, HybridState } from '../../components/TasteMapHybridShared'
import { HYBRID_DISCOVERY_PRIMARY_TABS } from './HybridProductContracts'
import { ModalShell } from '../../components/ModalShell'

type DiscoveryTab = typeof HYBRID_DISCOVERY_PRIMARY_TABS[number][0]
type DiscoverySort = 'recommended' | 'rating'
const tabs = HYBRID_DISCOVERY_PRIMARY_TABS.map(([value, label]) => ({ value, label }))

interface CommentContext {
  target: TasteMapHybridActivityInteractionDTO
  restaurantName: string
}

export function HybridDiscoveryPage({ content, platform, onOpenRestaurant, onRecordVisit, onOpenRoulette, active = true }: {
  content: TasteMapHybridContentSnapshotDTO
  platform: TasteMapPlatform
  onOpenRestaurant: (id: string) => void
  onRecordVisit?: (restaurantID: string) => void
  onOpenRoulette?: (restaurantID: string) => void
  active?: boolean
}) {
  const [tab, setTab] = useState<DiscoveryTab>('forYou')
  const [city, setCity] = useState('all')
  const [sort, setSort] = useState<DiscoverySort>('recommended')
  const [minimumRating, setMinimumRating] = useState(0)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [viewerStates, setViewerStates] = useState<Record<string, 'none' | 'want_to_go' | 'visited'>>({})
  const [engagement, setEngagement] = useState<Record<string, TasteMapCommunityEngagementDTO>>({})
  const [pendingLikes, setPendingLikes] = useState<Set<string>>(new Set())
  const [pendingWant, setPendingWant] = useState<Set<string>>(new Set())
  const [commentContext, setCommentContext] = useState<CommentContext | null>(null)
  const [comments, setComments] = useState<TasteMapCommunityCommentDTO[]>([])
  const [commentText, setCommentText] = useState('')
  const [commentsLoading, setCommentsLoading] = useState(false)
  const [commentSubmitting, setCommentSubmitting] = useState(false)
  const [message, setMessage] = useState('')
  const scrollPosition = useRef(0)

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
  const discovery = tab === 'forYou' ? content.discovery.forYou : tab === 'similarTaste' ? content.discovery.similarTaste : content.discovery.trending
  const activity = tab === 'following' ? content.community.following : content.community.latest
  const citySource = tab === 'following' || tab === 'latest' ? activity.map((item) => item.restaurant.city) : discovery.map((item) => item.restaurant.city)
  const cities = useMemo(() => [...new Set(citySource.filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')), [citySource])
  const visibleDiscovery = useMemo(() => discovery
    .filter((item) => city === 'all' || item.restaurant.city === city)
    .filter((item) => minimumRating === 0 || (item.activityRating ?? 0) >= minimumRating)
    .sort((left, right) => sort === 'rating'
      ? (right.activityRating ?? -1) - (left.activityRating ?? -1)
      : left.rank - right.rank), [city, discovery, minimumRating, sort])
  const visibleActivity = useMemo(() => activity
    .filter((item) => city === 'all' || item.restaurant.city === city)
    .filter((item) => minimumRating === 0 || (item.visitRating ?? 0) >= minimumRating), [activity, city, minimumRating])
  const activeFilterCount = Number(city !== 'all') + Number(minimumRating > 0) + Number(sort !== 'recommended')

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

  async function openComments(context: CommentContext) {
    setCommentContext(context)
    setCommentText('')
    setComments([])
    setCommentsLoading(true)
    try {
      const page = await platform.community.comments(context.target)
      setComments(page.items)
    } catch {
      setMessage('评论暂时无法加载。')
    } finally {
      setCommentsLoading(false)
    }
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
    } catch {
      setMessage('评论没有发送，请重试。')
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
      <button aria-expanded={filtersOpen} className={activeFilterCount ? 'is-active' : ''} onClick={() => setFiltersOpen((value) => !value)} type="button">
        <SlidersHorizontal aria-hidden="true" size={14} />筛选{activeFilterCount ? ` ${activeFilterCount}` : ''}
      </button>
      <label className={city !== 'all' ? 'is-active' : ''}><Building2 aria-hidden="true" size={14} /><select aria-label="城市" onChange={(event) => setCity(event.target.value)} value={city}><option value="all">全部城市</option>{cities.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
      <label className={sort !== 'recommended' ? 'is-active' : ''}><ArrowDownUp aria-hidden="true" size={14} /><select aria-label="排序" onChange={(event) => setSort(event.target.value as DiscoverySort)} value={sort}><option value="recommended">综合推荐</option><option value="rating">本次评分</option></select></label>
      <label className={minimumRating > 0 ? 'is-active' : ''}><Star aria-hidden="true" size={14} /><select aria-label="本次评分" onChange={(event) => setMinimumRating(Number(event.target.value))} value={minimumRating}><option value="0">评分</option><option value="3">3.0+</option><option value="4">4.0+</option><option value="4.5">4.5+</option></select></label>
    </TasteMapFilterBar>
    {filtersOpen ? <div className="tm-discovery-filter-summary" role="region" aria-label="当前筛选">
      <span>筛选只使用当前 Tab 的真实城市与本次到访评分。</span>
      <button disabled={!activeFilterCount} onClick={() => { setCity('all'); setSort('recommended'); setMinimumRating(0) }} type="button">重置</button>
    </div> : null}
  </>

  return <main className="tm-hybrid-page tm-hybrid-discovery" data-discovery-tab={tab} hidden={!active}>
    <TasteMapDiscoveryScaffold
      className="tm-hybrid-discovery__shared"
      description="按照你的口味，找到更值得参考的人和下一家餐厅。"
      filterBar={filterBar}
      onTabChange={setTab}
      tab={tab}
      tabs={tabs}
    >
      {tab === 'following' || tab === 'latest'
        ? visibleActivity.length
          ? <section aria-label={`${tabs.find((item) => item.value === tab)?.label}动态`} className="tm-hybrid-activity-feed">{visibleActivity.map((item) => <ActivityCard
              engagement={item.interaction ? engagementFor(item.interaction, item) : item}
              item={item}
              key={item.id}
              likePending={Boolean(item.interaction && pendingLikes.has(item.interaction.visitID))}
              onComment={(target) => void openComments({ target, restaurantName: item.restaurant.name })}
              onLike={(target) => void toggleLike(target, item)}
              onOpenRestaurant={onOpenRestaurant}
              onOpenRoulette={(id) => onOpenRoulette?.(id) ?? void platform.navigation.openHybrid({ surface: 'roulette' })}
              onRecordVisit={(id) => onRecordVisit?.(id) ?? void platform.navigation.openHybrid({ surface: 'visit', identifier: id })}
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
              onOpenRoulette={(id) => onOpenRoulette?.(id) ?? void platform.navigation.openHybrid({ surface: 'roulette' })}
              onRecordVisit={(id) => onRecordVisit?.(id) ?? void platform.navigation.openHybrid({ surface: 'visit', identifier: id })}
              onToggleWant={(id) => void toggleWantToGo(id, item.viewerState)}
              platform={platform}
              viewerState={viewerStateFor(item.restaurant.id, item.viewerState)}
              wantPending={pendingWant.has(item.restaurant.id)}
            />)}</section>
          : <HybridState kind="empty" message={tab === 'similarTaste' ? '需要更多相同餐厅的真实评分样本；Taste Map 不会伪造“同味”结论。' : '当前城市和筛选下没有可展示的真实内容。'} title={tab === 'similarTaste' ? '同味样本还不够' : '暂无推荐'} />}
    </TasteMapDiscoveryScaffold>
    {commentContext ? <ModalShell description={commentContext.restaurantName} onClose={() => setCommentContext(null)} title="评论">
      <div className="community-comment-panel" data-comment-activity-id={commentContext.target.activityID ?? ''} data-comment-visit-id={commentContext.target.visitID}>
        <div className="community-comment-list">
          {commentsLoading ? <p className="community-comment-empty">正在加载评论…</p> : comments.length
            ? comments.map((comment) => <p key={comment.id}><strong>{comment.author.name}</strong><span>{comment.body}</span></p>)
            : <p className="community-comment-empty">还没有评论，来说说你的想法。</p>}
        </div>
        <form onSubmit={(event) => void submitComment(event)}><input aria-label="写下评论" autoFocus maxLength={280} onChange={(event) => setCommentText(event.target.value)} placeholder="写下评论" value={commentText} /><button aria-label="发送评论" disabled={!commentText.trim() || commentSubmitting} type="submit"><SendIcon size={17} /></button></form>
      </div>
    </ModalShell> : null}
    {message ? <p aria-live="polite" className="community-share-toast" onAnimationEnd={() => setMessage('')}>{message}</p> : null}
  </main>
}

interface CardInteractionProps {
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

function RecommendationCard({ item, platform, onOpenRestaurant, engagement, viewerState, likePending, wantPending, onLike, onComment, onRecordVisit, onToggleWant, onOpenRoulette }: {
  item: TasteMapHybridDiscoveryItemDTO
  platform: TasteMapPlatform
  onOpenRestaurant: (id: string) => void
} & CardInteractionProps) {
  const share = () => void platform.share.open({ title: item.restaurant.name, text: `Taste Map 推荐：${item.restaurant.name}` })
  const facts = [
    item.similarityPercent != null ? `与同味用户相似 ${item.similarityPercent}%` : null,
    item.sharedRestaurantCount != null ? `共同到访 ${item.sharedRestaurantCount} 家餐厅` : null,
    item.uniqueVisitorCount != null ? `近期有 ${item.uniqueVisitorCount} 位用户到访` : null,
    item.wantToGoCount != null ? `${item.wantToGoCount} 人想吃` : null,
  ].filter((value): value is string => Boolean(value))
  const target = item.interaction
  return <TasteMapActivityCardFrame
    activityRating={<>
      <CommunityRatingSummary item={item} />
      {item.sourceUser ? <button aria-label={`查看推荐来源用户 ${item.sourceUser.name}`} className="tm-activity-card__source-inline" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.sourceUser!.id })} type="button"><span className="tm-hybrid-avatar-seed">{item.sourceUser.name.slice(0, 1)}</span><strong>{item.sourceUser.name}</strong>{item.activityRating == null ? <span className="tm-activity-card__visit-rating">本次未评分</span> : <span className="tm-activity-card__visit-rating"><Star aria-hidden="true" fill="currentColor" size={11} />{item.activityRating.toFixed(1)}</span>}{item.activityVisitedAt ? <time>{formatEventTime(item.activityVisitedAt)}</time> : null}</button> : item.activityRating != null ? <span aria-label={`本次到访评分 ${item.activityRating.toFixed(1)}`} className="tm-activity-card__visit-rating" role="img"><Star aria-hidden="true" fill="currentColor" size={12} />本次到访 {item.activityRating.toFixed(1)}</span> : null}
    </>}
    body={<section className="tm-activity-card__recommendation-reason"><strong>{item.mode === 'for_you' ? '为什么适合你' : item.mode === 'similar_taste' ? '同味推荐依据' : '近期趋势依据'}</strong><p>{item.reason}</p>{facts.length ? <ul>{facts.map((fact) => <li key={fact}>{fact}</li>)}</ul> : null}</section>}
    media={<button aria-label={`${item.restaurant.name} 餐厅图片`} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantImage image={item.restaurant.image} name={item.restaurant.name} /></button>}
    onOpen={() => onOpenRestaurant(item.restaurant.id)}
    restaurant={<RestaurantIdentity item={item} onOpenRestaurant={onOpenRestaurant} />}
    restaurantActions={<>
      <button aria-label={`记录 ${item.restaurant.name}`} className="tm-activity-action is-primary" onClick={() => onRecordVisit(item.restaurant.id)} title="记录到访" type="button"><CirclePlus aria-hidden="true" size={19} /></button>
      <button aria-busy={wantPending} aria-label={`${viewerState === 'visited' ? '已去过' : viewerState === 'want_to_go' ? '移出想吃' : '想吃'} ${item.restaurant.name}`} aria-pressed={viewerState === 'want_to_go'} className="tm-activity-action" disabled={viewerState === 'visited' || wantPending} onClick={() => onToggleWant(item.restaurant.id)} title={viewerState === 'want_to_go' ? '移出想吃' : '想吃'} type="button"><BookmarkPlus aria-hidden="true" fill={viewerState === 'want_to_go' ? 'currentColor' : 'none'} size={18} /></button>
      <button aria-label={`食单 ${item.restaurant.name}`} className="tm-activity-action" onClick={() => void platform.navigation.openNative({ route: 'restaurantAddToList', identifier: item.restaurant.id })} title="加入食单" type="button"><ListPlus aria-hidden="true" size={18} /></button>
      <button aria-label={`轮盘 ${item.restaurant.name}`} className="tm-activity-action" onClick={() => onOpenRoulette(item.restaurant.id)} title="加入抽签" type="button"><Dices aria-hidden="true" size={18} /></button>
    </>}
    socialActions={<>
      {target ? <button aria-busy={likePending} aria-label={`${engagement.likedByViewer ? '取消点赞' : '点赞'} ${item.restaurant.name}`} aria-pressed={engagement.likedByViewer} disabled={likePending} onClick={() => onLike(target)} title="点赞" type="button"><Heart aria-hidden="true" fill={engagement.likedByViewer ? 'currentColor' : 'none'} size={19} />{engagement.likeCount}</button> : null}
      {target ? <button aria-label={`评论 ${item.restaurant.name}`} onClick={() => onComment(target)} title="评论" type="button"><MessageCircle aria-hidden="true" size={19} />{engagement.commentCount}</button> : null}
      <button aria-label={`分享动态 ${item.restaurant.name}`} onClick={share} title="分享" type="button"><Share2 aria-hidden="true" size={19} /></button>
    </>}
    variant="recommendation"
  />
}

function ActivityCard({ item, platform, onOpenRestaurant, engagement, viewerState, likePending, wantPending, onLike, onComment, onRecordVisit, onToggleWant, onOpenRoulette }: {
  item: TasteMapHybridActivityItemDTO
  platform: TasteMapPlatform
  onOpenRestaurant: (id: string) => void
} & CardInteractionProps) {
  const target = item.interaction
  return <TasteMapActivityCardFrame
    activityRating={<span aria-label={item.visitRating == null ? '本次到访未评分' : `本次到访评分 ${item.visitRating.toFixed(1)}`} className="tm-activity-card__visit-rating" role="img">{item.visitRating == null ? '本次未评分' : <><Star aria-hidden="true" fill="currentColor" size={12} />本次到访 {item.visitRating.toFixed(1)}</>}</span>}
    body={item.note ? <p>“{item.note}”</p> : undefined}
    header={<><button className="tm-activity-card__user" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.user.id })} type="button"><span className="tm-hybrid-avatar-seed">{item.user.name.slice(0, 1)}</span><span><strong>{item.user.name}</strong><small>{formatEventTime(item.eventAt)} · {item.kind === 'visit' ? '公开到访' : '加入想吃'}</small></span></button><button aria-label="更多操作：举报或拉黑" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.id })} type="button"><Ellipsis size={19} /></button></>}
    media={<button aria-label={`${item.restaurant.name} 餐厅图片`} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantImage image={item.restaurant.image} name={item.restaurant.name} /></button>}
    onOpen={() => onOpenRestaurant(item.restaurant.id)}
    restaurant={<RestaurantIdentity item={item} onOpenRestaurant={onOpenRestaurant} />}
    restaurantActions={<>
      <button aria-label={`记录 ${item.restaurant.name}`} className="tm-activity-action is-primary" onClick={() => onRecordVisit(item.restaurant.id)} title="记录到访" type="button"><CirclePlus aria-hidden="true" size={19} /></button>
      <button aria-busy={wantPending} aria-label={`${viewerState === 'visited' ? '已去过' : viewerState === 'want_to_go' ? '移出想吃' : '想吃'} ${item.restaurant.name}`} aria-pressed={viewerState === 'want_to_go'} className="tm-activity-action" disabled={viewerState === 'visited' || wantPending} onClick={() => onToggleWant(item.restaurant.id)} title={viewerState === 'want_to_go' ? '移出想吃' : '想吃'} type="button"><BookmarkPlus aria-hidden="true" fill={viewerState === 'want_to_go' ? 'currentColor' : 'none'} size={18} /></button>
      <button aria-label={`食单 ${item.restaurant.name}`} className="tm-activity-action" onClick={() => void platform.navigation.openNative({ route: 'restaurantAddToList', identifier: item.restaurant.id })} title="加入食单" type="button"><ListPlus aria-hidden="true" size={18} /></button>
      <button aria-label={`轮盘 ${item.restaurant.name}`} className="tm-activity-action" onClick={() => onOpenRoulette(item.restaurant.id)} title="加入抽签" type="button"><Dices aria-hidden="true" size={18} /></button>
    </>}
    socialActions={<>
      {target ? <button aria-busy={likePending} aria-label={`${engagement.likedByViewer ? '取消点赞' : '点赞'} ${item.restaurant.name}`} aria-pressed={engagement.likedByViewer} disabled={likePending} onClick={() => onLike(target)} type="button"><Heart fill={engagement.likedByViewer ? 'currentColor' : 'none'} size={18} />{engagement.likeCount}</button> : null}
      {target ? <button aria-label={`评论 ${item.restaurant.name}`} onClick={() => onComment(target)} type="button"><MessageCircle size={18} />{engagement.commentCount}</button> : null}
      <button aria-label={`分享动态 ${item.restaurant.name}`} onClick={() => void platform.share.open({ title: item.restaurant.name, text: `${item.user.name} 在 Taste Map 记录了 ${item.restaurant.name}` })} title="分享" type="button"><Share2 aria-hidden="true" size={19} /></button>
      {!item.user.isFollowing ? <button aria-label="关注用户" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.user.id })} type="button"><UserPlus size={18} />关注</button> : null}
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
  const tag = 'mode' in item ? item.mode === 'for_you' ? item.rank === 1 ? '优先推荐' : '推荐给你' : item.mode === 'similar_taste' ? '同味推荐' : '近期趋势' : null
  const metadata = [restaurant.tags.slice(0, 2).join(' · '), restaurant.referencePrice != null ? `约 ¥${Math.round(restaurant.referencePrice)}/人` : ''].filter(Boolean).join(' · ')
  return <button aria-label={`查看餐厅 ${restaurant.name}`} className="tm-activity-card__restaurant-identity" onClick={() => onOpenRestaurant(restaurant.id)} type="button"><span className="tm-activity-card__restaurant-avatar"><HybridRestaurantImage image={restaurant.image} name={restaurant.name} /></span><span className="tm-activity-card__restaurant-copy"><strong>{restaurant.name}</strong>{metadata ? <em>{metadata}</em> : null}<small><MapPin aria-hidden="true" size={12} />{restaurant.city} · {restaurant.address}</small></span>{tag ? <span className="tm-activity-card__recommendation-tag">{tag}</span> : null}</button>
}

function formatEventTime(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
}
