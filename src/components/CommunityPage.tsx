import { BookmarkPlus, Check, Dices, Globe2, MapPin, Star } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import type { CommunityVisit, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { fetchCommunityFeed, type DiscoveryMode } from '../services/socialApi'
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
}

const DISCOVERY_TABS: Array<{ value: DiscoveryMode; label: string }> = [
  { value: 'following', label: '关注' },
  { value: 'for_you', label: '为你推荐' },
  { value: 'similar', label: '同味之选' },
  { value: 'latest', label: '最新' },
  { value: 'trending', label: '趋势' },
]

export function CommunityPage({ users, restaurants, candidateRestaurantIds, onAddToWant, onToggleCandidate, onViewProfile }: {
  users: UserProfile[]
  restaurants: RestaurantSummary[]
  candidateRestaurantIds: string[]
  onAddToWant: (restaurant: RestaurantSummary) => void
  onToggleCandidate: (restaurant: RestaurantSummary) => void
  onViewProfile: (user: UserProfile) => void
}) {
  const [mode, setMode] = useState<DiscoveryMode>('for_you')
  const [city, setCity] = useState('杭州市')
  const [trendWindow, setTrendWindow] = useState<7 | 30>(7)
  const [cloudFeed, setCloudFeed] = useState<CommunityVisit[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [selectedItem, setSelectedItem] = useState<FeedItem | null>(null)
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
      })
    })
    return [...items.values()]
  }, [cloudFeed, localFeed, restaurants])

  return <section className="social-page community-page discovery-page">
    <header className="social-page__heading"><div><span className="eyebrow">DISCOVER</span><h1>发现</h1><p>按照你的口味，找到更值得参考的人和下一家餐厅。</p></div><Globe2 size={28} /></header>
    <div className="discovery-controls">
      <label className="discovery-city"><MapPin size={15} /><input aria-label="搜索发现城市" list="discovery-city-options" onChange={(event) => setCity(event.target.value)} placeholder="搜索城市" value={city} /><datalist id="discovery-city-options">{cityOptions.map((option) => <option key={option} value={option} />)}</datalist></label>
      <div className="discovery-tabs" role="tablist">{DISCOVERY_TABS.map((tab) => <button aria-selected={mode === tab.value} className={mode === tab.value ? 'active' : ''} key={tab.value} onClick={() => setMode(tab.value)} role="tab" type="button">{tab.label}</button>)}</div>
    </div>
    {mode === 'for_you' ? <p className="discovery-explainer">根据你跨城市积累的评分、菜系与重复到访偏好生成。</p> : null}
    {mode === 'similar' ? <p className="discovery-explainer">看看和你口味相近的人，在当前城市真正喜欢什么。</p> : null}
    {mode === 'trending' ? <div className="trend-window"><button className={trendWindow === 7 ? 'active' : ''} onClick={() => setTrendWindow(7)} type="button">近 7 天</button><button className={trendWindow === 30 ? 'active' : ''} onClick={() => setTrendWindow(30)} type="button">近 30 天</button></div> : null}
    {loading ? <div className="social-empty"><span className="loading-spinner" /><strong>正在整理发现内容</strong></div> : null}
    {!loading && error ? <div className="social-empty"><strong>暂时无法加载</strong><p>{error}</p></div> : null}
    {!loading && !error && feed.length ? <div className="community-feed">{feed.map((item) => <article className={`community-card${mode === 'for_you' ? ' is-restaurant-recommendation' : ''}`} key={item.visit.id}>
      {mode !== 'for_you' ? <header><button className="user-avatar-small" onClick={() => onViewProfile(item.user)} type="button"><UserAvatar alt="" avatarImageData={item.user.avatarImageData} avatarPhotoId={item.user.avatarPhotoId} avatarPresetId={item.user.avatarPresetId} membershipTier={item.user.membershipTier} /></button><button className="community-user-link" onClick={() => onViewProfile(item.user)} type="button"><strong>{item.user.nickname}</strong><time>{formatVisitDateTime(item.visit.visitedAt)}</time></button>{mode === 'similar' && item.similarity !== null && item.similarity !== undefined ? <span className="similarity-pill">口味相似 {item.similarity}%</span> : null}</header> : null}
      <button className="community-restaurant" onClick={() => setSelectedItem(item)} type="button"><RestaurantAvatar restaurant={item.restaurant} /><div className="community-restaurant__body"><strong>{item.restaurant.name}</strong><span><MapPin size={12} /> {item.restaurant.city} · {item.restaurant.address}</span></div><div className="community-restaurant__right">{item.visit.rating ? <b><Star fill="currentColor" size={13} /> {item.visit.rating} 星</b> : null}<span className="discovery-card-quick-actions"><button aria-label="加入想吃" onClick={(event) => { event.stopPropagation(); onAddToWant(item.restaurant) }} title="加入想吃" type="button"><BookmarkPlus size={16} /></button><button aria-label={candidateRestaurantIds.includes(item.restaurant.id) ? '移出抽签' : '加入抽签'} aria-pressed={candidateRestaurantIds.includes(item.restaurant.id)} className={candidateRestaurantIds.includes(item.restaurant.id) ? 'is-selected' : ''} onClick={(event) => { event.stopPropagation(); onToggleCandidate(item.restaurant) }} title={candidateRestaurantIds.includes(item.restaurant.id) ? '移出抽签' : '加入抽签'} type="button">{candidateRestaurantIds.includes(item.restaurant.id) ? <Check size={16} /> : <Dices size={16} />}</button></span></div></button>
      {mode !== 'for_you' && item.visit.note ? <p>{item.visit.note}</p> : null}
      {item.recommendationReason ? <p className="discovery-reason">{item.recommendationReason}</p> : null}
      {mode !== 'for_you' && item.visit.photos.length ? <div className="community-photos">{item.visit.photos.slice(0, 6).map((photo, index) => <SyncedImage alt="公开到访照片" key={`${item.visit.id}-${index}`} loading="lazy" photoId={item.visit.photoIds[index]} source={photo} />)}</div> : null}
    </article>)}</div> : null}
    {!loading && !error && !feed.length ? <div className="social-empty"><Globe2 size={24} /><strong>{mode === 'for_you' ? '还没有足够信息推荐' : mode === 'similar' ? '目前还没有足够的口味匹配数据' : '这里暂时没有公开记录'}</strong><p>{mode === 'for_you' ? '多记录几家餐厅后，我们会逐渐了解你的口味。' : '换一个城市或稍后再看看。'}</p></div> : null}
    {selectedItem ? <ModalShell description={mode === 'for_you' ? selectedItem.recommendationReason || '根据你的历史口味推荐' : `${selectedItem.user.nickname} 的公开到访记录`} onClose={() => setSelectedItem(null)} size="large" title="餐厅信息"><div className="discovery-restaurant-preview"><RestaurantPreviewCard isInRoulette={candidateRestaurantIds.includes(selectedItem.restaurant.id)} onAddToRoulette={() => onToggleCandidate(selectedItem.restaurant)} onAddVisit={() => undefined} onClose={() => setSelectedItem(null)} onDelete={() => undefined} onEdit={() => undefined} onEditVisit={() => undefined} onSaveRecommendation={() => onAddToWant(selectedItem.restaurant)} restaurant={{ ...selectedItem.restaurant, isRecommendation: true }} /></div></ModalShell> : null}
  </section>
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
