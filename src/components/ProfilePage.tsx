import { useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode } from 'react'
import { Activity, ArrowLeft, ArrowRight, BadgeCheck, BookOpen, Bookmark, CalendarDays, Check, ChevronRight, Clock3, Copy, Database, Dices, Heart, Image as ImageIcon, Info, ListChecks, LockKeyhole, MapPinned, MoreHorizontal, Repeat2, Save, Settings, Share2, ShieldCheck, Sparkles, Star, Store, ThumbsDown, ThumbsUp, TrendingUp, UserCheck, UserPlus, UsersRound, Utensils, WalletCards } from 'lucide-react'
import type { CloudSyncState } from '../types/cloudSync'
import { scoreColor, type DiningCompanion, type FriendshipStatus, type RestaurantSummary, type UserProfile, type Visibility, type Visit } from '../types/domain'
import { buildProfileInsights } from '../services/profileInsights'
import { optimizeAvatarImage } from '../utils/images'
import { AVATAR_PRESETS } from '../utils/avatarPresets'
import { publicUserId } from '../utils/publicUserId'
import { ModalShell } from './ModalShell'
import { PresetAvatar, UserAvatar } from './UserAvatar'
import { MembershipAdminEntry } from './MembershipAdminPanel'
import { RestaurantListsSection } from './RestaurantListsPanel'
import { reviewService, type PeriodReview } from '../services/reviewService'
import { SyncedImage } from './SyncedImage'
import { CompanionInsightsPanel, RecommendationSourceInsightsPanel } from './ProfileAnalyticsPanels'

export function ProfilePage({ user, restaurants = [], viewerRestaurants = [], visits = [], diningCompanions = [], sourceUsers = [], followerCount = 0, followingCount = 0, onSave, editable = true, isFollowing = false, followPending = false, friendStatus = null, friendPending = false, cloudSyncState, connections, followerConnections, followingConnections, onAddFriend, onBack, onOpenRoulette, onOpenSettings, onMapPrivacyChange, onSelectRestaurant, onToggleFollow }: {
  user: UserProfile
  restaurants?: RestaurantSummary[]
  viewerRestaurants?: RestaurantSummary[]
  visits?: Visit[]
  diningCompanions?: DiningCompanion[]
  sourceUsers?: UserProfile[]
  followerCount?: number
  followingCount?: number
  onSave: (changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'>) => Promise<unknown>
  editable?: boolean
  isFollowing?: boolean
  followPending?: boolean
  friendStatus?: FriendshipStatus | null
  friendPending?: boolean
  cloudSyncState?: CloudSyncState
  connections?: ReactNode
  followerConnections?: ReactNode
  followingConnections?: ReactNode
  onAddFriend?: () => void
  onBack?: () => void
  onOpenRoulette?: () => void
  onOpenSettings?: () => void
  onMapPrivacyChange?: (changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) => Promise<unknown>
  onSelectRestaurant?: (restaurant: RestaurantSummary) => void
  onToggleFollow?: () => void
}) {
  const [page, setPage] = useState<'dashboard' | 'account'>('dashboard')
  const [editorOpen, setEditorOpen] = useState(false)
  const [connectionsOpen, setConnectionsOpen] = useState<'discover' | 'following' | 'followers' | null>(null)
  const [copiedUserId, setCopiedUserId] = useState(false)
  const [detail, setDetail] = useState<'month' | 'year' | 'day' | 'taste' | 'data' | 'companions' | 'sources' | null>(null)
  const insights = useMemo(() => buildProfileInsights(restaurants, visits), [restaurants, visits])
  const monthReview = useMemo(() => reviewService.monthly(restaurants, visits, new Date().getFullYear(), new Date().getMonth() + 1), [restaurants, visits])
  const yearReview = useMemo(() => reviewService.annual(restaurants, visits, new Date().getFullYear()), [restaurants, visits])
  const numericUserId = useMemo(() => publicUserId(user.id), [user.id])
  async function copyUserId() {
    await navigator.clipboard?.writeText(numericUserId)
    setCopiedUserId(true)
    window.setTimeout(() => setCopiedUserId(false), 1600)
  }
  if (page === 'account') return <AccountPrivacyPage onBack={() => setPage('dashboard')} onMapPrivacyChange={onMapPrivacyChange} onOpenSettings={onOpenSettings} user={user} />
  if (!editable) return <PublicUserProfile followPending={followPending} friendPending={friendPending} friendStatus={friendStatus} followerCount={followerCount} followingCount={followingCount} isFollowing={isFollowing} onAddFriend={onAddFriend} onBack={onBack} onSelectRestaurant={onSelectRestaurant} onToggleFollow={onToggleFollow} restaurants={restaurants} user={user} viewerRestaurants={viewerRestaurants} visits={visits} />

  return <section className={`social-page profile-page profile-dashboard${editable ? ' profile-dashboard--owner' : ' profile-dashboard--public'}`}>
    <div className="profile-dashboard__hero">
      <div className="profile-dashboard__top">{editable ? <><button onClick={() => setConnectionsOpen('discover')} type="button"><UserPlus size={17} />添加好友</button><button aria-label="账号与隐私" onClick={() => setPage('account')} type="button"><Settings size={20} /></button></> : <><button onClick={onBack} type="button"><ArrowLeft size={17} />返回</button><span>公开主页</span></>}</div>
      <header className="profile-dashboard__header">
        <button aria-label={editable ? '编辑个人资料' : `${user.nickname} 的头像`} className="profile-avatar profile-dashboard__avatar" disabled={!editable} onClick={() => setEditorOpen(true)} type="button"><UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /></button>
        <div className="profile-dashboard__identity"><h1>{user.nickname}</h1><p>{user.city ? `${user.city} · ` : ''}{user.bio || '记录每一次真实的味觉记忆。'}</p><div className="profile-dashboard__identity-actions"><button className="profile-user-id" onClick={() => void copyUserId()} title="复制用户 ID" type="button"><span>ID {numericUserId}</span>{copiedUserId ? <Check size={13} /> : <Copy size={13} />}</button>{editable ? <button className="profile-edit-button" onClick={() => setEditorOpen(true)} type="button">编辑资料</button> : <button className={`profile-follow-button${isFollowing ? ' is-following' : ''}`} disabled={followPending || !onToggleFollow} onClick={onToggleFollow} type="button">{isFollowing ? <UserCheck size={15} /> : <UserPlus size={15} />}{followPending ? '处理中…' : isFollowing ? '已关注' : '关注'}</button>}</div></div>
      </header>
      <div className={`profile-dashboard__counts${editable ? '' : ' is-public'}`}>{editable ? <><button onClick={() => setConnectionsOpen('following')} type="button"><strong>{followingCount}</strong><small>我关注的</small></button><button onClick={() => setConnectionsOpen('followers')} type="button"><strong>{followerCount}</strong><small>关注我的</small></button><button onClick={() => setDetail('data')} type="button"><strong>{visits.length}</strong><small>公开记录</small></button><button onClick={() => setDetail('data')} type="button"><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong><small>去过餐厅</small></button></> : <><span><strong>{visits.length}</strong><small>公开记录</small></span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong><small>去过餐厅</small></span></>}</div>
    </div>
    {editable ? <button className="profile-roulette-card" onClick={onOpenRoulette} type="button"><span className="profile-roulette-card__visual"><Dices size={28} /></span><div><strong>今天吃什么</strong><small>从餐厅库中随机挑一家</small></div><span className="profile-roulette-card__arrow"><ArrowRight size={20} /></span></button> : null}
    {editable ? <TasteProfileSummary onClick={() => setDetail('taste')} profile={insights.tasteProfile} /> : null}
    {editable ? <ProfileSection title="回味"><div className="profile-memory-grid"><MemoryCard icon={<CalendarDays size={22} />} onClick={() => setDetail('month')} title="本月回顾" subtitle="回顾精彩味道" values={[`${monthReview.visitCount} 次用餐`, `${monthReview.restaurantCount} 家餐厅`]} /><MemoryCard icon={<BookOpen size={22} />} onClick={() => setDetail('year')} title="年度回顾" subtitle="你的味觉足迹" values={[`${yearReview.visitCount} 次用餐`, `${yearReview.restaurantCount} 家餐厅`]} /><MemoryCard icon={<ImageIcon size={22} />} onClick={() => setDetail('day')} title="那年今日" subtitle="回到味觉记忆" values={insights.onThisDay.length ? insights.onThisDay.slice(0, 1).map((visit) => restaurants.find((item) => item.id === visit.restaurantId)?.name ?? '一次味觉记忆') : ['还没有往年记录']} /></div></ProfileSection> : null}
    {editable ? <RestaurantListsSection onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} /> : null}
    {!editable ? <ProfileSection title="公开记录"><div className="public-profile-records">{restaurants.length ? restaurants.map((restaurant) => <button disabled={!onSelectRestaurant} key={restaurant.id} onClick={() => onSelectRestaurant?.(restaurant)} type="button"><span><strong>{restaurant.name}</strong><small>{restaurant.city}{restaurant.visitCount ? ` · 去过 ${restaurant.visitCount} 次` : ''}</small></span><ChevronRight size={16} /></button>) : <p>这个用户暂时没有对你公开餐厅记录。</p>}</div></ProfileSection> : null}
    {editable ? <ProfileSection title="发现与洞察"><div className="profile-analytics-links"><button onClick={() => setDetail('companions')} type="button"><span className="profile-analytics-links__icon"><UsersRound size={24} /></span><span><strong>饭搭子分析</strong><small>看看你和谁最合拍</small></span><ChevronRight size={17} /></button><button onClick={() => setDetail('sources')} type="button"><span className="profile-analytics-links__icon"><Sparkles size={24} /></span><span><strong>推荐来源分析</strong><small>发现灵感从哪里来</small></span><ChevronRight size={17} /></button></div></ProfileSection> : null}
    {editable ? <div className="profile-settings-links"><button onClick={onOpenSettings} type="button"><Database size={19} /><span><strong>数据与设置</strong><small>云同步、备份、恢复与图片存储</small></span><ChevronRight size={18} /></button><button onClick={() => setPage('account')} type="button"><ShieldCheck size={19} /><span><strong>账号与隐私</strong><small>账号安全、地图隐私与权限管理</small></span><ChevronRight size={18} /></button>{cloudSyncState ? <small className="profile-sync-line">{cloudSyncState.status === 'synced' ? '云端已同步' : cloudSyncState.status === 'syncing' ? '正在同步' : cloudSyncState.errorMessage || '等待同步'}</small> : null}</div> : null}
    {editorOpen ? <ProfileEditorModal onClose={() => setEditorOpen(false)} onSave={onSave} user={user} /> : null}
    {connectionsOpen ? <ModalShell description={connectionsOpen === 'discover' ? '搜索昵称或城市，找到想关注的 Taste Map 用户。' : '点击用户可以查看对方的公开资料。'} onClose={() => setConnectionsOpen(null)} size="large" title={connectionsOpen === 'discover' ? '发现好友' : connectionsOpen === 'following' ? '我关注的' : '关注我的'}>{connectionsOpen === 'discover' ? connections : connectionsOpen === 'following' ? followingConnections : followerConnections}</ModalShell> : null}
    {detail ? <ProfileDetailModal detail={detail} diningCompanions={diningCompanions} insights={insights} monthReview={monthReview} onClose={() => setDetail(null)} onSelectRestaurant={onSelectRestaurant} ownerUserId={user.id} premium={user.membershipTier === 'member'} restaurants={restaurants} sourceUsers={sourceUsers} visits={visits} yearReview={yearReview} /> : null}
  </section>
}

type PublicProfileTab = 'activity' | 'lists' | 'taste'
type PublicProfileView = 'visited' | 'map' | 'mutual' | null

function PublicUserProfile({ user, restaurants, viewerRestaurants, visits, followerCount, followingCount, isFollowing, followPending = false, friendStatus, friendPending, onBack, onSelectRestaurant, onToggleFollow, onAddFriend }: {
  user: UserProfile
  restaurants: RestaurantSummary[]
  viewerRestaurants: RestaurantSummary[]
  visits: Visit[]
  followerCount: number
  followingCount: number
  isFollowing: boolean
  followPending?: boolean
  friendStatus: FriendshipStatus | null
  friendPending: boolean
  onBack?: () => void
  onSelectRestaurant?: (restaurant: RestaurantSummary) => void
  onToggleFollow?: () => void
  onAddFriend?: () => void
}) {
  const [tab, setTab] = useState<PublicProfileTab>('activity')
  const [view, setView] = useState<PublicProfileView>(null)
  const [shared, setShared] = useState(false)
  const insights = useMemo(() => buildProfileInsights(restaurants, visits), [restaurants, visits])
  const visitedRestaurants = useMemo(() => restaurants.filter((restaurant) => restaurant.status === 'visited' || restaurant.visitCount > 0).sort(comparePublicRestaurants), [restaurants])
  const wantRestaurants = useMemo(() => restaurants.filter((restaurant) => restaurant.status === 'wantToGo'), [restaurants])
  const representativeRestaurants = visitedRestaurants.slice(0, 4)
  const activityRestaurants = useMemo(() => [...visitedRestaurants].sort((a, b) => (b.latestVisitDate ?? '').localeCompare(a.latestVisitDate ?? '')), [visitedRestaurants])
  const viewerWantKeys = useMemo(() => new Set(viewerRestaurants.filter((restaurant) => restaurant.status === 'wantToGo').map(publicRestaurantKey)), [viewerRestaurants])
  const mutualWants = wantRestaurants.filter((restaurant) => viewerWantKeys.has(publicRestaurantKey(restaurant)))
  const cityGroups = useMemo(() => {
    const counts = new Map<string, number>()
    visitedRestaurants.forEach((restaurant) => counts.set(restaurant.city || '其他城市', (counts.get(restaurant.city || '其他城市') ?? 0) + 1))
    return [...counts].sort((a, b) => b[1] - a[1])
  }, [visitedRestaurants])
  const publicLists = useMemo(() => buildPublicProfileLists(visitedRestaurants), [visitedRestaurants])
  const friendLabel = friendPending ? '处理中…' : friendStatus === 'accepted' ? '已是好友' : friendStatus === 'pending' ? '已申请' : '加好友'
  const numericUserId = useMemo(() => publicUserId(user.id), [user.id])

  function openView(next: Exclude<PublicProfileView, null>) {
    setView(next)
    window.requestAnimationFrame(() => window.scrollTo({ top: 0, behavior: 'smooth' }))
  }
  async function shareProfile() {
    const shareData = { title: `${user.nickname} 的 Taste Map`, text: `看看 ${user.nickname} 的公开美食主页`, url: window.location.href }
    if (navigator.share) await navigator.share(shareData).catch(() => undefined)
    else await navigator.clipboard?.writeText(window.location.href)
    setShared(true)
    window.setTimeout(() => setShared(false), 1600)
  }

  if (view) return <section className="social-page public-user-profile public-user-profile--subpage">
    <header className="public-user-profile__subhead"><button onClick={() => setView(null)} type="button"><ArrowLeft size={18} />返回</button><h1>{view === 'visited' ? '去过的餐厅' : view === 'map' ? 'TA 的公开地图' : '我们都想吃'}</h1><span /></header>
    {view === 'map' ? <div className="public-profile-map-summary"><div className="public-profile-map-summary__canvas"><MapPinned size={38} /><strong>{visitedRestaurants.length}</strong><small>公开足迹</small></div><div className="public-profile-city-list">{cityGroups.length ? cityGroups.map(([city, count]) => <div key={city}><strong>{city}</strong><span>{count} 家</span></div>) : <p>暂时没有公开城市足迹。</p>}</div></div> : <PublicRestaurantRows emptyText={view === 'mutual' ? '你们暂时还没有共同想吃的餐厅。' : '这个用户暂时没有公开到访记录。'} onSelectRestaurant={onSelectRestaurant} restaurants={view === 'mutual' ? mutualWants : visitedRestaurants} />}
  </section>

  return <section className="social-page public-user-profile">
    <header className="public-user-profile__hero">
      <div className="public-user-profile__top"><button onClick={onBack} type="button"><ArrowLeft size={19} /><span>返回</span></button><div><button aria-label="分享主页" onClick={() => void shareProfile()} type="button">{shared ? <Check size={19} /> : <Share2 size={19} />}</button><button aria-label="更多" type="button"><MoreHorizontal size={21} /></button></div></div>
      <div className="public-user-profile__identity">
        <span className="public-user-profile__avatar"><UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /></span>
        <div><h1>{user.nickname}</h1><strong>@{publicHandle(user)}</strong><p>{user.city || '未设置城市'}{user.bio ? ` · ${user.bio}` : ''}</p><span><BadgeCheck size={13} />ID {numericUserId}</span></div>
      </div>
      <div className="public-user-profile__actions"><button className={isFollowing ? 'is-following' : ''} disabled={followPending || !onToggleFollow} onClick={onToggleFollow} type="button">{isFollowing ? <UserCheck size={16} /> : <UserPlus size={16} />}{followPending ? '处理中…' : isFollowing ? '已关注' : '关注'}</button><button disabled={friendPending || friendStatus === 'accepted' || friendStatus === 'pending' || !onAddFriend} onClick={onAddFriend} type="button"><UsersRound size={16} />{friendLabel}</button></div>
      <div className="public-user-profile__metrics"><span><strong>{followingCount}</strong><small>关注</small></span><span><strong>{followerCount}</strong><small>粉丝</small></span><span><strong>{visits.length}</strong><small>公开到访</small></span><span><strong>{visitedRestaurants.length}</strong><small>去过餐厅</small></span></div>
    </header>

    <section className="public-profile-shortcuts">
      <button onClick={() => setTab('activity')} type="button"><Activity size={20} /><strong>动态</strong><small>{visits.length} 条</small></button>
      <button onClick={() => openView('mutual')} type="button"><Bookmark size={20} /><strong>想吃</strong><small>{wantRestaurants.length} 家</small></button>
      <button onClick={() => setTab('lists')} type="button"><ListChecks size={20} /><strong>食单</strong><small>{publicLists.length} 个</small></button>
      <button onClick={() => openView('map')} type="button"><MapPinned size={20} /><strong>地图</strong><small>查看轨迹</small></button>
    </section>

    <button className="public-profile-mutual" onClick={() => openView('mutual')} type="button"><Heart size={19} /><span><strong>我们都想吃 {mutualWants.length} 家</strong><small>{mutualWants.length ? '一起去试试这些店吧' : '共同收藏的餐厅会显示在这里'}</small></span><span className="public-profile-mutual__avatars">{mutualWants.slice(0, 3).map((restaurant) => <RestaurantThumb key={restaurant.id} restaurant={restaurant} />)}</span><ChevronRight size={18} /></button>

    <ProfileSection action={representativeRestaurants.length ? '查看全部' : undefined} onAction={representativeRestaurants.length ? () => openView('visited') : undefined} title="最代表 TA 的餐厅"><div className="public-profile-representative">{representativeRestaurants.length ? representativeRestaurants.map((restaurant) => <button key={restaurant.id} onClick={() => onSelectRestaurant?.(restaurant)} type="button"><RestaurantThumb restaurant={restaurant} /><strong>{restaurant.name}</strong><small>{restaurant.tags[0] || restaurant.city}{restaurant.scoreOutOfTen !== null ? ` · ${restaurant.scoreOutOfTen.toFixed(1)}` : ''}</small></button>) : <p>继续公开记录后，这里会形成 TA 的代表餐厅。</p>}</div></ProfileSection>

    <nav className="public-profile-tabs" aria-label="公开主页内容"><button className={tab === 'activity' ? 'is-active' : ''} onClick={() => setTab('activity')} type="button">动态</button><button className={tab === 'lists' ? 'is-active' : ''} onClick={() => setTab('lists')} type="button">食单</button><button className={tab === 'taste' ? 'is-active' : ''} onClick={() => setTab('taste')} type="button">口味</button></nav>
    {tab === 'activity' ? <section className="public-profile-activity"><header><h2>最近公开到访</h2>{activityRestaurants.length ? <button onClick={() => openView('visited')} type="button">查看全部</button> : null}</header>{activityRestaurants.length ? activityRestaurants.slice(0, 8).map((restaurant) => <PublicActivityCard key={restaurant.id} onSelectRestaurant={onSelectRestaurant} restaurant={restaurant} />) : <p className="public-profile-empty">这个用户暂时没有公开动态。</p>}</section> : null}
    {tab === 'lists' ? <section className="public-profile-lists"><header><h2>TA 的公开食单</h2></header>{publicLists.length ? publicLists.map((list) => <article key={list.title}><div className="public-profile-list-cover">{list.restaurants.slice(0, 4).map((restaurant) => <RestaurantThumb key={restaurant.id} restaurant={restaurant} />)}</div><div><strong>{list.title}</strong><small>{list.restaurants.length} 家餐厅</small><p>{list.description}</p></div></article>) : <p className="public-profile-empty">这个用户暂时没有公开食单。</p>}</section> : null}
    {tab === 'taste' ? <section className="public-profile-taste"><header><h2>TA 的口味偏好</h2><span>公开信息</span></header><dl><div><dt>偏爱菜系</dt><dd>{insights.tasteProfile.preferredCuisines.slice(0, 5).map((item) => item.label).join(' · ') || '数据积累中'}</dd></div><div><dt>常去价位</dt><dd>{insights.tasteProfile.preferredPriceRange}</dd></div><div><dt>偏好氛围</dt><dd>{insights.tasteProfile.highRatingTraits.slice(0, 4).map((item) => item.label).join(' · ') || '数据积累中'}</dd></div></dl><p>{insights.tasteProfile.summary}</p><small>基于 {insights.tasteProfile.validVisitCount} 次公开有效记录生成</small></section> : null}
  </section>
}

function PublicActivityCard({ restaurant, onSelectRestaurant }: { restaurant: RestaurantSummary; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const latest = restaurant.latestVisit
  const score = restaurant.scoreOutOfTen
  return <button className="public-profile-activity-card" onClick={() => onSelectRestaurant?.(restaurant)} type="button"><RestaurantThumb restaurant={restaurant} /><span><strong>{restaurant.name}</strong><small>{restaurant.tags[0] || '餐厅'} · {restaurant.city}</small>{score !== null ? <em style={{ color: scoreColor(score) }}><Star size={12} fill="currentColor" />{score.toFixed(1)}</em> : null}<small>去过 {restaurant.visitCount} 次{restaurant.latestVisitDate ? ` · 最近 ${formatPublicDate(restaurant.latestVisitDate)}` : ''}</small>{latest?.note ? <p>“{latest.note}”</p> : null}</span><Bookmark size={17} /></button>
}

function PublicRestaurantRows({ restaurants, emptyText, onSelectRestaurant }: { restaurants: RestaurantSummary[]; emptyText: string; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  return <div className="public-profile-restaurant-rows">{restaurants.length ? restaurants.map((restaurant) => <button key={restaurant.id} onClick={() => onSelectRestaurant?.(restaurant)} type="button"><RestaurantThumb restaurant={restaurant} /><span><strong>{restaurant.name}</strong><small>{restaurant.tags[0] || '餐厅'} · {restaurant.city}</small><small>去过 {restaurant.visitCount} 次{restaurant.latestVisitDate ? ` · 最近 ${formatPublicDate(restaurant.latestVisitDate)}` : ''}</small></span>{restaurant.scoreOutOfTen !== null ? <em style={{ color: scoreColor(restaurant.scoreOutOfTen) }}>{restaurant.scoreOutOfTen.toFixed(1)}</em> : null}<ChevronRight size={17} /></button>) : <p className="public-profile-empty">{emptyText}</p>}</div>
}

function RestaurantThumb({ restaurant }: { restaurant: RestaurantSummary }) {
  const photo = publicRestaurantPhoto(restaurant)
  return <span className="public-profile-restaurant-thumb">{photo ? <SyncedImage alt="" loading="lazy" photoId={photo.photoId} source={photo.source} /> : <Utensils size={20} />}</span>
}

function publicRestaurantPhoto(restaurant: RestaurantSummary) {
  for (const visit of restaurant.visits) {
    if (visit.photos[0]) return { source: visit.photos[0], photoId: visit.photoIds[0] ?? null }
  }
  const source = restaurant.markerImageData || restaurant.merchantImageUrl
  return source || restaurant.markerPhotoId ? { source, photoId: restaurant.markerPhotoId } : null
}

function comparePublicRestaurants(a: RestaurantSummary, b: RestaurantSummary) {
  return (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1) || b.visitCount - a.visitCount || (b.latestVisitDate ?? '').localeCompare(a.latestVisitDate ?? '')
}

function buildPublicProfileLists(restaurants: RestaurantSummary[]) {
  if (!restaurants.length) return []
  const frequent = [...restaurants].sort((a, b) => b.visitCount - a.visitCount).slice(0, 8)
  const rated = [...restaurants].filter((item) => item.scoreOutOfTen !== null).sort(comparePublicRestaurants).slice(0, 8)
  const recent = [...restaurants].sort((a, b) => (b.latestVisitDate ?? '').localeCompare(a.latestVisitDate ?? '')).slice(0, 8)
  return [
    { title: '最常回去的店', description: 'TA 反复到访、最熟悉的一组餐厅', restaurants: frequent },
    rated.length ? { title: 'TA 的高分餐厅', description: '按公开评分整理的心头好', restaurants: rated } : null,
    { title: '最近去过', description: '按最近公开到访整理', restaurants: recent },
  ].filter((item): item is { title: string; description: string; restaurants: RestaurantSummary[] } => Boolean(item?.restaurants.length))
}

function publicRestaurantKey(restaurant: RestaurantSummary) { return restaurant.amapPoiId || `${restaurant.city}:${restaurant.name}` }
function publicHandle(user: UserProfile) { return (user.nickname || user.id).replace(/\s+/g, '').replace(/[^\w\u4e00-\u9fff-]/g, '').toLowerCase() || user.id }
function formatPublicDate(value: string) { const date = new Date(value); return Number.isNaN(date.getTime()) ? value : `${date.getMonth() + 1}月${date.getDate()}日` }

function ProfileSection({ title, action, onAction, children }: { title: string; action?: string; onAction?: () => void; children: ReactNode }) { return <section className="profile-dashboard__section"><header><h2>{title}</h2>{action ? <button disabled={!onAction} onClick={onAction} type="button">{action}</button> : null}</header>{children}</section> }

function MemoryCard({ title, subtitle, values, icon, onClick }: { title: string; subtitle: string; values: string[]; icon: ReactNode; onClick: () => void }) { return <button onClick={onClick} type="button"><span className="profile-memory-card__icon">{icon}</span><span className="profile-memory-card__copy"><strong>{title}</strong><small>{subtitle}</small><em>{values.join(' · ')}</em></span><ChevronRight size={15} /></button> }

type TasteProfile = ReturnType<typeof buildProfileInsights>['tasteProfile']

function TasteProfileSummary({ profile, onClick }: { profile: TasteProfile; onClick: () => void }) {
  return <button className="taste-profile-card taste-profile-card--summary" onClick={onClick} type="button"><span className="taste-profile-card__title"><Utensils size={18} /><strong>我的口味档案</strong><ChevronRight size={17} /></span>{profile.moduleConfidence.cuisines === 'insufficient' ? <p>{profile.summary}</p> : <dl><div><dt>偏爱菜系</dt><dd>{profile.preferredCuisines.slice(0, 3).map((item) => item.label).join(' · ') || '逐渐形成中'}</dd></div><div><dt>常去价位</dt><dd>{profile.preferredPriceRange}</dd></div><div><dt>偏好氛围</dt><dd>{profile.highRatingTraits.slice(0, 3).map((item) => item.label).join(' · ') || '继续记录后生成'}</dd></div><div className="taste-profile-summary"><dd>{profile.summary}</dd></div></dl>}<small>基于 {profile.validVisitCount} 次有效记录生成 · 持续更新中</small></button>
}

function ProfileDetailModal({ detail, insights, visits, restaurants, diningCompanions, sourceUsers, ownerUserId, monthReview, yearReview, premium, onClose, onSelectRestaurant }: { detail: 'month' | 'year' | 'day' | 'taste' | 'data' | 'companions' | 'sources'; insights: ReturnType<typeof buildProfileInsights>; visits: Visit[]; restaurants: RestaurantSummary[]; diningCompanions: DiningCompanion[]; sourceUsers: UserProfile[]; ownerUserId: string; monthReview: PeriodReview; yearReview: PeriodReview; premium: boolean; onClose: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  if (detail === 'taste') return <ModalShell description="根据真实到访、评分、重复到访与结构化体验持续更新。" onClose={onClose} size="large" title="完整口味档案"><TasteProfileDetails profile={insights.tasteProfile} restaurants={restaurants} /></ModalShell>
  if (detail === 'data') return <ModalShell description="只统计当前账号的有效记录。" onClose={onClose} size="large" title="我的数据"><div className="profile-data-detail"><span><strong>{visits.length}</strong>总用餐次数</span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong>去过餐厅</span><span><strong>{insights.cityCount}</strong>去过城市</span><span><strong>{insights.tasteProfile.repeatVisit.tendency}</strong>复购倾向</span></div></ModalShell>
  if (detail === 'companions') return <ModalShell description="只基于你自己的真实共同到访记录，不评价关系质量。" onClose={onClose} size="large" title="饭搭子分析"><CompanionInsightsPanel companions={diningCompanions} onSelectRestaurant={onSelectRestaurant} ownerUserId={ownerUserId} restaurants={restaurants} visits={visits} /></ModalShell>
  if (detail === 'sources') return <ModalShell description="推荐的价值由真实到访、评分和再次到访验证。" onClose={onClose} size="large" title="推荐来源分析"><RecommendationSourceInsightsPanel onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} sourceUsers={sourceUsers} visits={visits} /></ModalShell>
  if (detail === 'month' || detail === 'year') return <ReviewDetail premium={premium} review={detail === 'month' ? monthReview : yearReview} onClose={onClose} />
  const selectedVisits = insights.onThisDay
  return <ModalShell description={`${selectedVisits.length} 条真实到访记录`} onClose={onClose} size="large" title="那年今日"><div className="profile-memory-detail">{selectedVisits.length ? selectedVisits.map((visit) => <article key={visit.id}><time>{new Date(visit.visitedAt).toLocaleDateString('zh-CN')}</time><strong>{restaurants.find((item) => item.id === visit.restaurantId)?.name ?? '一次味觉记忆'}</strong>{visit.note ? <p>{visit.note}</p> : null}</article>) : <p>这一段时间还没有记录。</p>}</div></ModalShell>
}

function ReviewDetail({ review, premium, onClose }: { review: PeriodReview; premium: boolean; onClose: () => void }) {
  const title = review.kind === 'month' ? `${review.month} 月回顾` : `${review.year} 食味年鉴`
  return <ModalShell description={review.summary} onClose={onClose} size="large" title={title}><div className="period-review">
    <section className="period-review__hero"><span><strong>{review.visitCount}</strong>次用餐</span><span><strong>{review.restaurantCount}</strong>家餐厅</span><span><strong>{review.newRestaurantCount}</strong>家新店</span><span><strong>¥{Math.round(review.actualSpend)}</strong>实际消费</span></section>
    {review.highlights.length ? <section><h3>这一段最值得记住的事</h3>{review.highlights.map((item) => <p key={item}>{item}</p>)}</section> : null}
    <section className="period-review__stories"><article><small>第一次</small><strong>{review.firstVisit?.name ?? '还没有记录'}</strong>{review.firstVisit ? <time>{new Date(review.firstVisit.visitedAt).toLocaleDateString('zh-CN')}</time> : null}</article><article><small>最喜欢</small><strong>{review.favorite?.name ?? '等待下一次高分'}</strong>{review.favorite?.scoreOutOfTen !== null && review.favorite ? <em>{review.favorite.scoreOutOfTen.toFixed(1)} 分</em> : null}</article><article><small>最熟悉</small><strong>{review.mostVisited?.name ?? '还没有重复到访'}</strong>{review.mostVisited ? <em>{review.mostVisited.visitCount} 次</em> : null}</article></section>
    <section><h3>时间足迹</h3><div className="period-review__distribution">{review.timeDistribution.map((item) => <span key={item.label}><i style={{ height: `${Math.max(8, item.count / Math.max(1, ...review.timeDistribution.map((value) => value.count)) * 100)}%` }} /><small>{item.label}</small><b>{item.count}</b></span>)}</div></section>
    {review.photoMemories.length ? <section><h3>照片回忆</h3><div className="period-review__photos">{review.photoMemories.slice(0, premium ? 18 : 6).map((photo, index) => <SyncedImage alt="用餐回忆" key={`${photo.visitId}-${index}`} loading="lazy" photoId={photo.photoId} source={photo.source} />)}</div></section> : null}
    {premium ? <><section><h3>人与饭</h3><p>{review.companions.length ? review.companions.slice(0, 5).map((item) => `${item.name} ${item.count} 次`).join(' · ') : '这段时间以自己的节奏用餐。'}</p></section><section><h3>推荐来源故事</h3><p>{review.recommendationSources.length ? review.recommendationSources.slice(0, 4).map((item) => `${item.label} ${item.count} 次${item.averageScore !== null ? `，均分 ${item.averageScore.toFixed(1)}` : ''}`).join('；') : '还没有记录推荐来源。'}</p></section><section><h3>里程碑</h3>{review.milestones.length ? review.milestones.map((item) => <p key={item}>{item}</p>) : <p>继续记录，里程碑会自然出现。</p>}</section></> : <section className="period-review__premium"><LockKeyhole size={18} /><div><strong>会员可查看完整年鉴故事</strong><small>包括饭搭子、推荐来源、更多照片与历史比较。</small></div></section>}
    {review.comparison ? <section><h3>和上一段相比</h3><p>用餐 {review.comparison.visitDelta >= 0 ? '+' : ''}{review.comparison.visitDelta} 次 · 实际消费 {review.comparison.spendDelta >= 0 ? '+' : ''}¥{Math.round(review.comparison.spendDelta)}</p></section> : null}
  </div></ModalShell>
}

function TasteProfileDetails({ profile, restaurants }: { profile: TasteProfile; restaurants: RestaurantSummary[] }) {
  const percent = (value: number) => `${Math.round(value * 100)}%`
  const maturity = Math.min(96, Math.round(28 + profile.validVisitCount * .42))
  const recurringRestaurants = profile.repeatVisit.preferences.map((item) => ({ ...item, restaurant: restaurants.find((restaurant) => restaurant.name === item.label) })).slice(0, 4)
  return <div className="taste-profile-report">
    <header className="taste-profile-report__intro"><div><small>基于 {profile.validVisitCount} 次有效记录 · 最近持续更新</small><h2>{profile.summary}</h2></div><span><Utensils size={34} /></span></header>
    <div className="taste-profile-report__columns">
      <div className="taste-profile-report__column">
        <section className="taste-profile-maturity"><header><h3>档案成熟度</h3><Info size={14} /></header><strong>{maturity}%</strong><div><i><b style={{ width: `${maturity}%` }} /></i><span>记录越多，洞察越准确</span></div></section>
        <section className="taste-profile-keyfacts"><span><Utensils size={18} /><small>偏爱菜系</small><strong>{profile.preferredCuisines.slice(0, 2).map((item) => item.label).join('、') || '积累中'}</strong></span><span><WalletCards size={18} /><small>常见预算</small><strong>{profile.preferredPriceRange}</strong></span><span><Store size={18} /><small>用餐倾向</small><strong>{profile.diningMode.dineInShare >= .5 ? '到店为主' : '外卖更多'}</strong></span></section>
        <blockquote>{profile.summary}</blockquote>
        <section><header className="taste-section-title"><h3>你真正喜欢什么</h3><small>综合偏好</small></header>{profile.preferredCuisines.length ? <ol className="taste-cuisine-ranking">{profile.preferredCuisines.map((item, index) => <li key={item.label}><span>{index + 1}</span><div><strong>{item.label}</strong><small>{item.visits} 次 · 平均 {item.averageRating.toFixed(1)} 分</small></div><em>{item.score >= 0 ? '偏好明显' : '仍在尝试'}</em></li>)}</ol> : <p>多记录一些带评分的餐厅后生成。</p>}</section>
        <section><header className="taste-section-title"><h3>你的常见预算</h3><small>{profile.preferredPriceRange}</small></header><div className="taste-profile-bars">{profile.priceBuckets.filter((bucket) => bucket.count || profile.priceBuckets.length <= 4).map((bucket) => <div key={bucket.key}><span>{bucket.label}</span><i><b style={{ width: percent(bucket.share) }} /></i><em>{percent(bucket.share)}</em></div>)}</div></section>
      </div>
      <div className="taste-profile-report__column">
        <section><header className="taste-section-title"><h3>什么会影响你的体验</h3><Info size={14} /></header><div className="taste-impact-block"><strong><ThumbsUp size={16} />更容易让你加分</strong><div className="taste-profile-tags">{profile.highRatingTraits.length ? profile.highRatingTraits.map((item) => <span key={item.label}>{item.label}</span>) : <span>继续记录后生成</span>}</div></div><div className="taste-impact-block is-negative"><strong><ThumbsDown size={16} />更容易让你减分</strong><div className="taste-profile-tags">{profile.pitfallTraits.length ? profile.pitfallTraits.map((item) => <span key={item.label}>{item.label}</span>) : <span>暂无稳定踩雷因素</span>}</div></div><small className="taste-profile-note">只展示记录中的相关性，不代表因果。</small></section>
        <section><header className="taste-section-title"><h3>你通常怎么吃</h3></header><h4>用餐场景偏好</h4><div className="taste-scene-grid">{profile.scenes.slice(0, 4).map((scene) => <span key={scene.label}><UsersRound size={18} /><strong>{scene.label}</strong><small>{percent(scene.share)}</small></span>)}</div><div className="taste-split-stat"><span><small>到店 / 外卖</small><strong>{percent(profile.diningMode.dineInShare)}</strong><em>到店为主</em></span><span><small>复购倾向</small><strong>{percent(profile.repeatVisit.share)}</strong><em>{profile.repeatVisit.tendency}</em></span></div></section>
        <section><header className="taste-section-title"><h3>你最常回去的餐厅</h3><Repeat2 size={15} /></header>{recurringRestaurants.length ? <div className="taste-repeat-restaurants">{recurringRestaurants.map((item) => <article key={item.label}>{item.restaurant ? <RestaurantThumb restaurant={item.restaurant} /> : <span><Store size={18} /></span>}<strong>{item.label}</strong><small>{item.count} 次 · 平均 {item.averageRating.toFixed(1)}</small></article>)}</div> : <p>重复到访后，这里会出现最熟悉的餐厅。</p>}</section>
        <section><header className="taste-section-title"><h3>最近的口味变化</h3><TrendingUp size={15} /></header>{profile.recentTasteChanges.length ? <p>近 90 天更常出现：<strong>{profile.recentTasteChanges.join('、')}</strong></p> : <p>近期还没有明显变化，继续记录后会自动比较。</p>}</section>
      </div>
      <div className="taste-profile-report__column">
        <section><header className="taste-section-title"><h3>你的打分风格</h3><Info size={14} /></header><strong className="taste-rating-style">{profile.ratingBehavior.average !== null && profile.ratingBehavior.average >= 8 ? '整体偏宽松' : profile.ratingBehavior.average !== null && profile.ratingBehavior.average < 6 ? '整体偏严格' : '整体偏中性'}</strong><p>平均评分 <b>{profile.ratingBehavior.average?.toFixed(1) ?? '—'}</b></p><div className="taste-rating-grid"><span><strong>{percent(profile.ratingBehavior.aboveEightShare)}</strong>8 分以上</span><span><strong>{percent(profile.ratingBehavior.aboveNineShare)}</strong>9 分以上</span><span><strong>{profile.ratingBehavior.stability?.toFixed(1) ?? '—'}</strong>评分波动</span></div></section>
        <section><header className="taste-section-title"><h3>推荐来源</h3><Sparkles size={15} /></header>{profile.sourceQuality.length ? <div className="taste-source-summary">{profile.sourceQuality.slice(0, 3).map((item) => <span key={item.label}><strong>{item.label}</strong><small>{item.count} 次验证 · 平均 {item.averageRating.toFixed(1)}</small></span>)}</div> : <p>记录推荐来源并实际到访后，这里会显示哪些来源更懂你。</p>}</section>
        <section><header className="taste-section-title"><h3>更多数据</h3></header><div className="taste-more-links"><span><MapPinned size={16} /><div><strong>城市偏好</strong><small>去过城市与区域分布</small></div><ChevronRight size={15} /></span><span><Clock3 size={16} /><div><strong>用餐时段偏好</strong><small>你更常在什么时候吃</small></div><ChevronRight size={15} /></span><span><Utensils size={16} /><div><strong>用餐类型偏好</strong><small>菜系、场景与复购关系</small></div><ChevronRight size={15} /></span><span><Activity size={16} /><div><strong>更多维度</strong><small>查看完整口味数据</small></div><ChevronRight size={15} /></span></div></section>
        <section className="taste-profile-conclusion"><Sparkles size={24} /><h3>口味档案会随你的记录持续更新</h3><p>记录越多，洞察越准确。</p><small>口味档案只基于你的记录生成，不会对外公开。</small></section>
      </div>
    </div>
  </div>
}

function ProfileEditorModal({ user, onSave, onClose }: { user: UserProfile; onSave: (changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'>) => Promise<unknown>; onClose: () => void }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [nickname, setNickname] = useState(user.nickname)
  const [bio, setBio] = useState(user.bio)
  const [city, setCity] = useState(user.city)
  const [avatarImageData, setAvatarImageData] = useState(user.avatarImageData)
  const [avatarPhotoId, setAvatarPhotoId] = useState(user.avatarPhotoId)
  const [avatarPresetId, setAvatarPresetId] = useState(user.avatarPresetId ?? 'polar-bear')
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  async function chooseAvatar(event: ChangeEvent<HTMLInputElement>) { const file = event.target.files?.[0]; event.target.value = ''; if (file && user.membershipTier === 'member') { setAvatarImageData(await optimizeAvatarImage(file)); setAvatarPhotoId(null) } }
  async function submit(event: FormEvent) { event.preventDefault(); setSaving(true); setMessage(''); try { await onSave({ nickname, bio, city, avatarImageData, avatarPhotoId, avatarPresetId }); setMessage('个人资料已保存并等待云端同步') } finally { setSaving(false) } }
  return <ModalShell description="头像、昵称、城市和简介统一在这里修改。" onClose={onClose} size="large" title="编辑资料"><form className="profile-editor-modal" onSubmit={submit}><div className="avatar-preset-grid">{AVATAR_PRESETS.map((preset) => <button aria-label={preset.label} className={avatarPresetId === preset.id && !avatarImageData && !avatarPhotoId ? 'is-active' : ''} key={preset.id} onClick={() => { setAvatarPresetId(preset.id); setAvatarImageData(null); setAvatarPhotoId(null) }} type="button"><PresetAvatar id={preset.id} /><small>{preset.label}</small></button>)}</div>{user.membershipTier === 'member' ? <button className="custom-avatar-upload" onClick={() => inputRef.current?.click()} type="button">自定义上传头像</button> : <p className="custom-avatar-locked"><LockKeyhole size={14} />会员可上传自定义头像；预设头像均可直接使用。</p>}<input accept="image/*" hidden onChange={chooseAvatar} ref={inputRef} type="file" /><div className="profile-editor-modal__fields"><label className="field"><span>昵称</span><input maxLength={30} onChange={(event) => setNickname(event.target.value)} required value={nickname} /></label><label className="field"><span>城市</span><input maxLength={30} onChange={(event) => setCity(event.target.value)} placeholder="例如：杭州" value={city} /></label><label className="field"><span>个人简介</span><textarea maxLength={160} onChange={(event) => setBio(event.target.value)} rows={3} value={bio} /></label></div><footer><span>{message}</span><button className="primary-button" disabled={saving} type="submit"><Save size={15} />{saving ? '保存中' : '保存资料'}</button></footer></form></ModalShell>
}

function AccountPrivacyPage({ user, onBack, onOpenSettings, onMapPrivacyChange }: { user: UserProfile; onBack: () => void; onOpenSettings?: () => void; onMapPrivacyChange?: (changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) => Promise<unknown> }) {
  return <section className="social-page account-privacy-page"><header><button aria-label="返回我的" onClick={onBack} type="button"><ArrowLeft size={20} /></button><h1>账号与隐私</h1><span /></header><SettingsGroup title="账户"><SettingRow label="登录方式" value={user.authProvider === 'cloudflare-access' ? 'Cloudflare Access' : '本地账号'} /><SettingRow label="绑定邮箱" value={user.email || '未绑定'} /><MembershipAdminEntry /></SettingsGroup><SettingsGroup title="隐私设置"><div className="account-map-privacy"><span><strong>个人主页可见范围</strong><small>决定其他用户能否看到你的地图足迹</small></span><div>{([['private', '仅自己'], ['friends', '好友'], ['public', '公开']] as [Visibility, string][]).map(([value, label]) => <button className={user.mapVisibility === value && user.mapSharingEnabled === (value !== 'private') ? 'is-active' : ''} key={value} onClick={() => void onMapPrivacyChange?.({ mapSharingEnabled: value !== 'private', mapVisibility: value })} type="button">{label}</button>)}</div></div><SettingRow label="公开记录默认权限" value="每次记录时选择" /><SettingRow label="谁可以给我发送消息" value="好友" /></SettingsGroup><SettingsGroup title="权限管理"><SettingRow label="定位权限" value="由浏览器管理" /><SettingRow label="照片权限" value="选择照片时授权" /><SettingRow label="通知权限" value="由浏览器管理" /></SettingsGroup><SettingsGroup title="数据管理"><button className="account-setting-button" onClick={onOpenSettings} type="button"><span><strong>导出、备份与恢复</strong><small>打开数据与设置</small></span><ChevronRight size={17} /></button></SettingsGroup><SettingsGroup title="关于"><SettingRow label="隐私政策" value="查看" /><SettingRow label="用户协议" value="查看" /><SettingRow label="帮助与反馈" value="查看" /><SettingRow label="关于 Taste Map" value="v1.2.0" /></SettingsGroup><section className="danger-zone"><strong>危险操作</strong><button disabled type="button">删除账号</button><small>账号删除需要再次验证登录身份，当前不会误触执行。</small></section></section>
}
function SettingsGroup({ title, children }: { title: string; children: ReactNode }) { return <section className="account-settings-group"><h2>{title}</h2><div>{children}</div></section> }
function SettingRow({ label, value }: { label: string; value: string }) { return <button className="account-setting-button" type="button"><span><strong>{label}</strong></span><em>{value}</em><ChevronRight size={16} /></button> }
