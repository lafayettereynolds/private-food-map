import { useMemo, useState } from 'react'
import {
  ArrowDownUp, BookmarkPlus, Building2, CirclePlus, Dices, Ellipsis, Heart,
  ListPlus, MapPin, MessageCircle, Send, SlidersHorizontal, Star, UserPlus,
} from 'lucide-react'
import {
  TasteMapActivityCardFrame,
  TasteMapDiscoveryScaffold,
  TasteMapFilterBar,
} from '../../components/TasteMapDiscoveryShared'
import type {
  TasteMapHybridActivityItemDTO,
  TasteMapHybridContentSnapshotDTO,
  TasteMapHybridDiscoveryItemDTO,
  TasteMapPlatform,
} from '../../platform/TasteMapPlatform'
import { HybridRestaurantImage, HybridState } from '../../components/TasteMapHybridShared'
import { HYBRID_DISCOVERY_PRIMARY_TABS } from './HybridProductContracts'

type DiscoveryTab = typeof HYBRID_DISCOVERY_PRIMARY_TABS[number][0]
type DiscoverySort = 'recommended' | 'rating'
const tabs = HYBRID_DISCOVERY_PRIMARY_TABS.map(([value, label]) => ({ value, label }))

export function HybridDiscoveryPage({ content, platform, onOpenRestaurant }: {
  content: TasteMapHybridContentSnapshotDTO
  platform: TasteMapPlatform
  onOpenRestaurant: (id: string) => void
}) {
  const [tab, setTab] = useState<DiscoveryTab>('forYou')
  const [city, setCity] = useState('all')
  const [sort, setSort] = useState<DiscoverySort>('recommended')
  const [minimumRating, setMinimumRating] = useState(0)
  const [filtersOpen, setFiltersOpen] = useState(false)
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

  return <main className="tm-hybrid-page tm-hybrid-discovery" data-discovery-tab={tab}>
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
          ? <section aria-label={`${tabs.find((item) => item.value === tab)?.label}动态`} className="tm-hybrid-activity-feed">{visibleActivity.map((item) => <ActivityCard item={item} key={item.id} onOpenRestaurant={onOpenRestaurant} platform={platform} />)}</section>
          : <HybridState kind="empty" message={tab === 'following' ? '关注用户有新的公开到访后，会在这里出现。' : '还没有可见的最新公开动态。'} title={tab === 'following' ? '关注动态暂时为空' : '暂无最新动态'} />
        : visibleDiscovery.length
          ? <section aria-label={`${tabs.find((item) => item.value === tab)?.label}餐厅`} className="tm-hybrid-activity-feed">{visibleDiscovery.map((item) => <RecommendationCard item={item} key={item.id} onOpenRestaurant={onOpenRestaurant} platform={platform} />)}</section>
          : <HybridState kind="empty" message={tab === 'similarTaste' ? '需要更多相同餐厅的真实评分样本；Taste Map 不会伪造“同味”结论。' : '当前城市和筛选下没有可展示的真实内容。'} title={tab === 'similarTaste' ? '同味样本还不够' : '暂无推荐'} />}
    </TasteMapDiscoveryScaffold>
  </main>
}

function RecommendationCard({ item, platform, onOpenRestaurant }: { item: TasteMapHybridDiscoveryItemDTO; platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void }) {
  const share = () => void platform.share.open({ title: item.restaurant.name, text: `Taste Map 推荐：${item.restaurant.name}` })
  const facts = [
    item.similarityPercent != null ? `同味 ${item.similarityPercent}%` : null,
    item.sharedRestaurantCount != null ? `共同 ${item.sharedRestaurantCount} 家` : null,
    item.uniqueVisitorCount != null ? `${item.uniqueVisitorCount} 人到访` : null,
  ].filter((value): value is string => Boolean(value))
  return <TasteMapActivityCardFrame
    activityRating={<span aria-label={item.activityRating == null ? '本次到访未评分' : `本次到访评分 ${item.activityRating.toFixed(1)}`} role="img">{item.activityRating == null ? '本次未评分' : <><Star aria-hidden="true" fill="currentColor" size={14} />本次到访 {item.activityRating.toFixed(1)}</>}</span>}
    body={<><p>{item.reason}</p>{facts.length ? <ul>{facts.map((fact) => <li key={fact}>{fact}</li>)}</ul> : null}{item.sourceUser ? <p className="tm-activity-card__source"><span className="tm-hybrid-avatar-seed">{item.sourceUser.name.slice(0, 1)}</span><strong>{item.sourceUser.name}</strong>{item.activityVisitedAt ? <time>{formatEventTime(item.activityVisitedAt)}</time> : null}</p> : null}</>}
    media={<button aria-label={`${item.restaurant.name} 餐厅图片`} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantImage image={item.restaurant.image} name={item.restaurant.name} /></button>}
    onOpen={() => onOpenRestaurant(item.restaurant.id)}
    restaurant={<div className="tm-activity-card__restaurant-row"><span><strong>{item.restaurant.name}</strong><small><MapPin aria-hidden="true" size={12} />{item.restaurant.city} · {item.restaurant.address}</small></span><button aria-label="查看餐厅" className="tm-activity-card__open" onClick={() => onOpenRestaurant(item.restaurant.id)} type="button">查看</button></div>}
    restaurantActions={<>
      <button className="tm-activity-action is-primary" onClick={() => void platform.navigation.openNative({ route: 'visit', identifier: item.restaurant.id })} type="button"><CirclePlus size={15} />记录</button>
      <button className="tm-activity-action" disabled={item.viewerState === 'visited' || item.viewerState === 'want_to_go'} onClick={() => void platform.navigation.openNative({ route: 'restaurantWantToGo', identifier: item.restaurant.id })} type="button"><BookmarkPlus size={15} />{item.viewerState === 'visited' ? '已去过' : item.viewerState === 'want_to_go' ? '已想吃' : '想吃'}</button>
      <button className="tm-activity-action" onClick={() => void platform.navigation.openNative({ route: 'restaurantAddToList', identifier: item.restaurant.id })} type="button"><ListPlus size={15} />食单</button>
      <button className="tm-activity-action" onClick={() => void platform.navigation.openHybrid({ surface: 'roulette' })} type="button"><Dices size={15} />轮盘</button>
    </>}
    socialActions={<button aria-label="分享动态" onClick={share} type="button"><Send size={17} />分享动态</button>}
    variant="recommendation"
  />
}

function ActivityCard({ item, platform, onOpenRestaurant }: { item: TasteMapHybridActivityItemDTO; platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void }) {
  return <TasteMapActivityCardFrame
    activityRating={<span aria-label={item.visitRating == null ? '本次到访未评分' : `本次到访评分 ${item.visitRating.toFixed(1)}`} role="img">{item.visitRating == null ? '本次未评分' : <><Star aria-hidden="true" fill="currentColor" size={14} />本次到访 {item.visitRating.toFixed(1)}</>}</span>}
    body={item.note ? <p>“{item.note}”</p> : undefined}
    header={<><button className="tm-activity-card__user" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.user.id })} type="button"><span className="tm-hybrid-avatar-seed">{item.user.name.slice(0, 1)}</span><span><strong>{item.user.name}</strong><small>{formatEventTime(item.eventAt)} · {item.kind === 'visit' ? '公开到访' : '加入想吃'}</small></span></button><button aria-label="更多操作：举报或拉黑" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.id })} type="button"><Ellipsis size={19} /></button></>}
    media={<button aria-label={`${item.restaurant.name} 餐厅图片`} onClick={() => onOpenRestaurant(item.restaurant.id)} type="button"><HybridRestaurantImage image={item.restaurant.image} name={item.restaurant.name} /></button>}
    onOpen={() => onOpenRestaurant(item.restaurant.id)}
    restaurant={<div className="tm-activity-card__restaurant-row"><span><strong>{item.restaurant.name}</strong><small><MapPin aria-hidden="true" size={12} />{item.restaurant.city} · {item.restaurant.address}</small></span><button aria-label="查看餐厅" className="tm-activity-card__open" onClick={() => onOpenRestaurant(item.restaurant.id)} type="button">查看</button></div>}
    restaurantActions={<>
      <button className="tm-activity-action is-primary" onClick={() => void platform.navigation.openNative({ route: 'visit', identifier: item.restaurant.id })} type="button"><CirclePlus size={15} />记录</button>
      <button className="tm-activity-action" disabled={item.viewerState === 'visited' || item.viewerState === 'want_to_go'} onClick={() => void platform.navigation.openNative({ route: 'restaurantWantToGo', identifier: item.restaurant.id })} type="button"><BookmarkPlus size={15} />{item.viewerState === 'visited' ? '已去过' : item.viewerState === 'want_to_go' ? '已想吃' : '想吃'}</button>
      <button className="tm-activity-action" onClick={() => void platform.navigation.openNative({ route: 'restaurantAddToList', identifier: item.restaurant.id })} type="button"><ListPlus size={15} />食单</button>
    </>}
    socialActions={<>
      <button aria-label={item.likedByViewer ? '取消点赞' : '点赞'} aria-pressed={item.likedByViewer} onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.id })} type="button"><Heart fill={item.likedByViewer ? 'currentColor' : 'none'} size={18} />{item.likeCount}</button>
      <button aria-label="评论" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.id })} type="button"><MessageCircle size={18} />{item.commentCount}</button>
      <button aria-label="分享动态" onClick={() => void platform.share.open({ title: item.restaurant.name, text: `${item.user.name} 在 Taste Map 记录了 ${item.restaurant.name}` })} type="button"><Send size={18} />分享</button>
      {!item.user.isFollowing ? <button aria-label="关注用户" onClick={() => void platform.navigation.openNative({ route: 'socialNative', identifier: item.user.id })} type="button"><UserPlus size={18} />关注</button> : null}
    </>}
    variant="activity"
  />
}

function formatEventTime(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
}
