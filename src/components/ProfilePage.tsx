import { useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode } from 'react'
import { Activity, ArrowLeft, ArrowRight, BadgeCheck, BookOpen, Bookmark, CalendarDays, Check, ChevronRight, Clock3, Copy, Database, Dices, Heart, Image as ImageIcon, Info, LockKeyhole, MapPinned, MoreHorizontal, Repeat2, Settings, Share2, ShieldCheck, Sparkles, Star, Store, ThumbsDown, ThumbsUp, TrendingUp, UserCheck, UserPlus, UsersRound, Utensils, WalletCards, X } from 'lucide-react'
import type { CloudSyncState } from '../types/cloudSync'
import { scoreColor, type DiningCompanion, type FriendshipStatus, type RestaurantSummary, type UserProfile, type Visibility, type Visit } from '../types/domain'
import { buildProfileInsights } from '../services/profileInsights'
import { optimizeAvatarImage } from '../utils/images'
import { AVATAR_PRESETS } from '../utils/avatarPresets'
import { publicUserId } from '../utils/publicUserId'
import { ModalShell } from './ModalShell'
import { StickyFormActionBar } from './StickyFormActionBar'
import { PresetAvatar, UserAvatar } from './UserAvatar'
import { MembershipAdminEntry } from './MembershipAdminPanel'
import { RestaurantListsSection } from './RestaurantListsPanel'
import { reviewService, type OnThisDayReview, type PeriodReview, type ReviewMemory, type ReviewPhoto } from '../services/reviewService'
import { SyncedImage } from './SyncedImage'
import { CompanionInsightsPanel, RecommendationSourceInsightsPanel } from './ProfileAnalyticsPanels'
import { canUseFeature, type MembershipFeature } from '../services/featurePolicy'
import { buildPublicProfileMap, hasPublicTasteSummary, selectPublicProfileActivity, selectRepresentativeRestaurants, type PublicProfileActivity } from '../services/publicProfile'
import { MapView } from './MapView'
import type { FriendRecommendation } from '../services/socialApi'
import { PremiumBurgerBadge } from './PremiumBurgerBadge'
import { publicProfileTabLabels, selectUniqueProfileRestaurants, shouldShowMutualWant, shouldShowPremiumBurger, visibleProfileBio } from '../services/profileTopStats'
import { buildCompanionShareData, buildOnThisDayShareData, buildPeriodReviewShareData, buildRecommendationSourceShareData, buildTasteProfileShareData } from '../services/analysisShare'
import { AnalysisShareAction } from './AnalysisShareSheet'
import type { AnalysisShareData } from '../types/analysisShare'
import { openPremiumPaywall } from '../services/premiumPaywall'

export function ProfilePage({ user, restaurants = [], viewerRestaurants = [], visits = [], diningCompanions = [], sourceUsers = [], publicFollowers = [], publicFollowing = [], friendRecommendations = [], recommendationPendingIds = new Set<string>(), followerCount = 0, followingCount = 0, onSave, editable = true, isFollowing = false, followPending = false, friendStatus = null, friendPending = false, cloudSyncState, connections, followerConnections, followingConnections, onAddFriend, onBack, onOpenRoulette, onOpenSettings, onMapPrivacyChange, onRequestRecommendationFriend, onDismissFriendRecommendation, onSelectRestaurant, onSelectUser, onToggleFollow }: {
  user: UserProfile
  restaurants?: RestaurantSummary[]
  viewerRestaurants?: RestaurantSummary[]
  visits?: Visit[]
  diningCompanions?: DiningCompanion[]
  sourceUsers?: UserProfile[]
  publicFollowers?: UserProfile[]
  publicFollowing?: UserProfile[]
  friendRecommendations?: FriendRecommendation[]
  recommendationPendingIds?: ReadonlySet<string>
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
  onRequestRecommendationFriend?: (userId: string) => void
  onDismissFriendRecommendation?: (userId: string) => void
  onSelectRestaurant?: (restaurant: RestaurantSummary) => void
  onSelectUser?: (user: UserProfile) => void
  onToggleFollow?: () => void
}) {
  const [page, setPage] = useState<'dashboard' | 'account'>('dashboard')
  const [editorOpen, setEditorOpen] = useState(false)
  const [connectionsOpen, setConnectionsOpen] = useState<'discover' | 'following' | 'followers' | null>(null)
  const [restaurantListOpen, setRestaurantListOpen] = useState<'visited' | 'wantToGo' | null>(null)
  const [copiedUserId, setCopiedUserId] = useState(false)
  const [detail, setDetail] = useState<'month' | 'year' | 'day' | 'taste' | 'data' | 'companions' | 'sources' | null>(null)
  const insights = useMemo(() => buildProfileInsights(restaurants, visits), [restaurants, visits])
  const monthReview = useMemo(() => reviewService.monthly(restaurants, visits, new Date().getFullYear(), new Date().getMonth() + 1), [restaurants, visits])
  const yearReview = useMemo(() => reviewService.annual(restaurants, visits, new Date().getFullYear()), [restaurants, visits])
  const onThisDayReview = useMemo(() => reviewService.onThisDay(restaurants, visits), [restaurants, visits])
  const visitedRestaurants = useMemo(() => selectUniqueProfileRestaurants(restaurants, 'visited'), [restaurants])
  const wantToGoRestaurants = useMemo(() => selectUniqueProfileRestaurants(restaurants, 'wantToGo'), [restaurants])
  const totalSpend = useMemo(() => visits.reduce((sum, visit) => sum + (visit.myActualSpend ?? 0), 0), [visits])
  const numericUserId = useMemo(() => publicUserId(user.id), [user.id])
  async function copyUserId() {
    await navigator.clipboard?.writeText(numericUserId)
    setCopiedUserId(true)
    window.setTimeout(() => setCopiedUserId(false), 1600)
  }
  if (page === 'account') return <AccountPrivacyPage onBack={() => setPage('dashboard')} onMapPrivacyChange={onMapPrivacyChange} onOpenSettings={onOpenSettings} user={user} />
  if (!editable) return <PublicUserProfile followPending={followPending} followers={publicFollowers} following={publicFollowing} friendPending={friendPending} friendStatus={friendStatus} followerCount={followerCount} followingCount={followingCount} isFollowing={isFollowing} onAddFriend={onAddFriend} onBack={onBack} onSelectRestaurant={onSelectRestaurant} onSelectUser={onSelectUser} onToggleFollow={onToggleFollow} restaurants={restaurants} user={user} viewerRestaurants={viewerRestaurants} visits={visits} />

  return <section className={`social-page profile-page profile-dashboard${editable ? ' profile-dashboard--owner' : ' profile-dashboard--public'}`}>
    <div className="profile-dashboard__hero">
      <div className="profile-dashboard__top">{editable ? <><button onClick={() => setConnectionsOpen('discover')} type="button"><UserPlus size={17} />添加好友</button><button aria-label="账号与隐私" onClick={() => setPage('account')} type="button"><Settings size={20} /></button></> : <><button onClick={onBack} type="button"><ArrowLeft size={17} />返回</button><span>公开主页</span></>}</div>
      <header className="profile-dashboard__header">
        <button aria-label={editable ? '编辑个人资料' : `${user.nickname} 的头像`} className="profile-avatar profile-dashboard__avatar" disabled={!editable} onClick={() => setEditorOpen(true)} type="button"><UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /></button>
        <div className="profile-dashboard__identity"><h1><span>{user.nickname}</span>{shouldShowPremiumBurger(user.membershipTier) ? <button aria-label="查看 Premium 会员状态" className="profile-premium-badge-entry" onClick={() => openPremiumPaywall('profile_entry')} title="查看 Premium 会员状态" type="button"><PremiumBurgerBadge /></button> : null}</h1>{visibleProfileBio(user.bio) ? <p>{visibleProfileBio(user.bio)}</p> : null}{formatJoinedMonth(user.createdAt) ? <small className="profile-joined-at">{formatJoinedMonth(user.createdAt)} 加入 Taste Map</small> : null}<div className="profile-dashboard__identity-actions"><button className="profile-user-id" onClick={() => void copyUserId()} title="复制用户 ID" type="button"><span>ID {numericUserId}</span>{copiedUserId ? <Check size={13} /> : <Copy size={13} />}</button>{editable ? <><button className="profile-edit-button" onClick={() => setEditorOpen(true)} type="button">编辑资料</button>{user.membershipTier !== 'member' ? <button className="profile-premium-entry" onClick={() => openPremiumPaywall('profile_entry')} type="button"><Sparkles size={14} />开通 Premium</button> : null}</> : <button className={`profile-follow-button${isFollowing ? ' is-following' : ''}`} disabled={followPending || !onToggleFollow} onClick={onToggleFollow} type="button">{isFollowing ? <UserCheck size={15} /> : <UserPlus size={15} />}{followPending ? '处理中…' : isFollowing ? '已关注' : '关注'}</button>}</div></div>
      </header>
      {editable ? <><div className="profile-dashboard__social-counts"><ProfileStat icon={<UserCheck size={18} />} label="关注" onClick={() => setConnectionsOpen('following')} value={followingCount} /><ProfileStat icon={<UsersRound size={18} />} label="被关注" onClick={() => setConnectionsOpen('followers')} value={followerCount} /></div><div className="profile-dashboard__counts profile-dashboard__counts--primary"><ProfileStat icon={<MapPinned size={18} />} label="去过" onClick={() => setRestaurantListOpen('visited')} value={visitedRestaurants.length} /><ProfileStat icon={<Bookmark size={18} />} label="想去" onClick={() => setRestaurantListOpen('wantToGo')} value={wantToGoRestaurants.length} /><ProfileStat icon={<WalletCards size={18} />} label="总消费" onClick={() => setDetail('data')} value={`¥${Math.round(totalSpend).toLocaleString('zh-CN')}`} /></div></> : <div className="profile-dashboard__counts is-public"><span><strong>{visits.length}</strong><small>公开记录</small></span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong><small>去过餐厅</small></span></div>}
    </div>
    {editable ? <div className="profile-quick-actions"><button className="profile-quick-card profile-quick-card--roulette" onClick={onOpenRoulette} type="button"><span className="profile-quick-card__visual"><Dices size={24} /></span><span className="profile-quick-card__copy"><strong>今天吃什么</strong><small>帮我挑一家</small></span><ArrowRight size={18} /></button><TasteProfileSummary onClick={() => canUseFeature(user.membershipTier, 'full_taste_profile') ? setDetail('taste') : openPremiumPaywall('full_taste_profile')} profile={insights.tasteProfile} /></div> : null}
    {editable ? <ProfileSection title="回味"><div className="profile-memory-grid"><MemoryCard icon={<CalendarDays size={22} />} onClick={() => canUseFeature(user.membershipTier, 'monthly_review') ? setDetail('month') : openPremiumPaywall('monthly_review')} title="本月回顾" subtitle="回顾精彩味道" values={[`${monthReview.visitCount} 次用餐`, `${monthReview.restaurantCount} 家餐厅`]} /><MemoryCard icon={<BookOpen size={22} />} onClick={() => canUseFeature(user.membershipTier, 'annual_review') ? setDetail('year') : openPremiumPaywall('annual_review')} title="年度回顾" subtitle="你的食味年鉴" values={[`${yearReview.visitCount} 次用餐`, `${yearReview.restaurantCount} 家餐厅`]} /><MemoryCard icon={<ImageIcon size={22} />} onClick={() => setDetail('day')} title="那年今日" subtitle="回到味觉记忆" values={onThisDayReview.memories.length ? [onThisDayReview.memories[0].restaurantName] : ['还没有往年记录']} /></div></ProfileSection> : null}
    {editable ? <RestaurantListsSection onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} /> : null}
    {!editable ? <ProfileSection title="公开记录"><div className="public-profile-records">{restaurants.length ? restaurants.map((restaurant) => <button disabled={!onSelectRestaurant} key={restaurant.id} onClick={() => onSelectRestaurant?.(restaurant)} type="button"><span><strong>{restaurant.name}</strong><small>{restaurant.city}{restaurant.visitCount ? ` · 去过 ${restaurant.visitCount} 次` : ''}</small></span><ChevronRight size={16} /></button>) : <p>这个用户暂时没有对你公开餐厅记录。</p>}</div></ProfileSection> : null}
    {editable ? <ProfileSection title="发现与洞察"><div className="profile-analytics-links"><button onClick={() => canUseFeature(user.membershipTier, 'companion_analysis') ? setDetail('companions') : openPremiumPaywall('companion_analysis')} type="button"><span className="profile-analytics-links__icon"><UsersRound size={24} /></span><span><strong>最佳饭搭子</strong><small>看看你和谁最合拍</small></span><ChevronRight size={17} /></button><button onClick={() => canUseFeature(user.membershipTier, 'recommendation_source_analysis') ? setDetail('sources') : openPremiumPaywall('recommendation_source_analysis')} type="button"><span className="profile-analytics-links__icon"><Sparkles size={24} /></span><span><strong>谁最会种草</strong><small>发现灵感从哪里来</small></span><ChevronRight size={17} /></button></div></ProfileSection> : null}
    {editable ? <div className="profile-settings-links"><button onClick={onOpenSettings} type="button"><Database size={19} /><span><strong>数据与设置</strong><small>云同步、备份、恢复与图片存储</small></span><ChevronRight size={18} /></button><button onClick={() => setPage('account')} type="button"><ShieldCheck size={19} /><span><strong>账号与隐私</strong><small>账号安全、地图隐私与权限管理</small></span><ChevronRight size={18} /></button>{cloudSyncState ? <small className="profile-sync-line">{cloudSyncState.status === 'synced' ? '云端已同步' : cloudSyncState.status === 'syncing' ? '正在同步' : cloudSyncState.errorMessage || '等待同步'}</small> : null}</div> : null}
    {editorOpen ? <ProfileEditorModal onClose={() => setEditorOpen(false)} onSave={onSave} user={user} /> : null}
    {connectionsOpen ? <ModalShell description={connectionsOpen === 'discover' ? '搜索用户，或从根据共同好友与口味生成的推荐中添加好友。' : '点击用户可以查看对方的公开资料。'} onClose={() => setConnectionsOpen(null)} size="large" title={connectionsOpen === 'discover' ? '添加好友' : connectionsOpen === 'following' ? '我关注的' : '关注我的'}>{connectionsOpen === 'discover' ? <div className="profile-add-friend-flow">{connections}<FriendRecommendationsSection onDismiss={onDismissFriendRecommendation} onRequestFriend={onRequestRecommendationFriend} pendingIds={recommendationPendingIds} recommendations={friendRecommendations} /></div> : connectionsOpen === 'following' ? followingConnections : followerConnections}</ModalShell> : null}
    {restaurantListOpen ? <ModalShell description={restaurantListOpen === 'visited' ? '按餐厅去重显示，不会把多次到访重复计算。' : '显示当前保存在想吃清单中的餐厅。'} onClose={() => setRestaurantListOpen(null)} size="large" title={restaurantListOpen === 'visited' ? '去过' : '想吃'}><PublicRestaurantRows emptyText={restaurantListOpen === 'visited' ? '还没有去过的餐厅。' : '还没有想吃的餐厅。'} onSelectRestaurant={(restaurant) => { setRestaurantListOpen(null); onSelectRestaurant?.(restaurant) }} restaurants={restaurantListOpen === 'visited' ? visitedRestaurants : wantToGoRestaurants} /></ModalShell> : null}
    {detail ? <ProfileDetailModal detail={detail} diningCompanions={diningCompanions} insights={insights} monthReview={monthReview} onClose={() => setDetail(null)} onSelectRestaurant={onSelectRestaurant} onThisDayReview={onThisDayReview} ownerUserId={user.id} premium={user.membershipTier === 'member'} restaurants={restaurants} sourceUsers={sourceUsers} user={user} visits={visits} yearReview={yearReview} /> : null}
  </section>
}

function ProfileStat({ icon, value, label, onClick }: { icon: ReactNode; value: number | string; label: string; onClick: () => void }) {
  return <button aria-label={`${label} ${value}`} onClick={onClick} type="button"><span aria-hidden="true" className="profile-dashboard__stat-icon">{icon}</span><strong>{value}</strong><small>{label}</small></button>
}

function FriendRecommendationsSection({ recommendations, pendingIds, onRequestFriend, onDismiss }: {
  recommendations: FriendRecommendation[]
  pendingIds: ReadonlySet<string>
  onRequestFriend?: (userId: string) => void
  onDismiss?: (userId: string) => void
}) {
  const renderCard = (recommendation: FriendRecommendation) => {
    const pending = recommendation.friendshipState === 'pending' || pendingIds.has(recommendation.user.id)
    const strength = recommendation.strength ?? fallbackFriendRecommendationStrength(recommendation)
    return <article className="profile-friend-recommendation" key={recommendation.user.id}>
      <UserAvatar alt={recommendation.user.nickname} avatarImageData={recommendation.user.avatarImageData} avatarPhotoId={recommendation.user.avatarPhotoId} avatarPresetId={recommendation.user.avatarPresetId} membershipTier={recommendation.user.membershipTier} />
      <div className="profile-friend-recommendation__body"><span className="profile-friend-recommendation__name"><strong>{recommendation.user.nickname}</strong>{recommendation.user.membershipTier === 'member' ? <PremiumBurgerBadge /> : null}</span><small>{recommendation.user.city || '未设置城市'}</small><p>{recommendation.primaryReason.text}</p><span className={`profile-friend-recommendation__strength is-${strength}`}>{friendRecommendationStrengthLabel(strength)}</span></div>
      <div className="profile-friend-recommendation__actions"><button className="profile-friend-recommendation__add" disabled={pending || !onRequestFriend} onClick={() => onRequestFriend?.(recommendation.user.id)} type="button">{pending ? <UserCheck size={15} /> : <UserPlus size={15} />}{pending ? '已申请' : '加好友'}</button>{onDismiss ? <button aria-label={`隐藏 ${recommendation.user.nickname}`} className="profile-friend-recommendation__dismiss" onClick={() => onDismiss(recommendation.user.id)} title="隐藏推荐" type="button"><X size={14} /></button> : null}</div>
    </article>
  }
  return <section className="profile-friend-recommendations profile-friend-recommendations--add-flow">
    <header><div><strong>好友推荐</strong><small>根据共同好友、口味与餐厅足迹生成</small></div>{recommendations.length ? <span>{recommendations.length} 人</span> : null}</header>
    {recommendations.length ? <div className="profile-friend-recommendations__list">{recommendations.map((item) => renderCard(item))}</div> : <p className="inline-empty">暂时没有新的好友推荐。</p>}
  </section>
}

function fallbackFriendRecommendationStrength(recommendation: FriendRecommendation) {
  if (recommendation.primaryReason.code === 'mutual_friends' || recommendation.primaryReason.code === 'linked_companion') return 'priority' as const
  if (recommendation.primaryReason.code === 'taste_similarity' || recommendation.primaryReason.code === 'shared_restaurants') return 'recommended' as const
  return 'discovery' as const
}

function friendRecommendationStrengthLabel(strength: FriendRecommendation['strength']) {
  if (strength === 'priority') return '优先认识'
  if (strength === 'recommended') return '推荐认识'
  return '可以认识'
}

type PublicProfileTab = 'activity' | 'lists' | 'taste'
type PublicProfileView = 'following' | 'followers' | 'visited' | 'want' | 'map' | 'mutual' | null

function PublicUserProfile({ user, restaurants, viewerRestaurants, visits, followers, following, followerCount, followingCount, isFollowing, followPending = false, friendStatus, friendPending, onBack, onSelectRestaurant, onSelectUser, onToggleFollow, onAddFriend }: {
  user: UserProfile
  restaurants: RestaurantSummary[]
  viewerRestaurants: RestaurantSummary[]
  visits: Visit[]
  followers: UserProfile[]
  following: UserProfile[]
  followerCount: number
  followingCount: number
  isFollowing: boolean
  followPending?: boolean
  friendStatus: FriendshipStatus | null
  friendPending: boolean
  onBack?: () => void
  onSelectRestaurant?: (restaurant: RestaurantSummary) => void
  onSelectUser?: (user: UserProfile) => void
  onToggleFollow?: () => void
  onAddFriend?: () => void
}) {
  const [tab, setTab] = useState<PublicProfileTab>('activity')
  const [view, setView] = useState<PublicProfileView>(null)
  const [shared, setShared] = useState(false)
  const insights = useMemo(() => buildProfileInsights(restaurants, visits), [restaurants, visits])
  const visitedRestaurants = useMemo(() => selectUniqueProfileRestaurants(restaurants, 'visited').sort(comparePublicRestaurants), [restaurants])
  const wantRestaurants = useMemo(() => selectUniqueProfileRestaurants(restaurants, 'wantToGo'), [restaurants])
  const representativeRestaurants = useMemo(() => selectRepresentativeRestaurants(visitedRestaurants, 4), [visitedRestaurants])
  const recentActivity = useMemo(() => selectPublicProfileActivity(visitedRestaurants, 8), [visitedRestaurants])
  const viewerWantKeys = useMemo(() => new Set(viewerRestaurants.filter((restaurant) => restaurant.status === 'wantToGo').map(publicRestaurantKey)), [viewerRestaurants])
  const mutualWants = wantRestaurants.filter((restaurant) => viewerWantKeys.has(publicRestaurantKey(restaurant)))
  const publicLists = useMemo(() => buildPublicProfileLists(visitedRestaurants), [visitedRestaurants])
  const showTasteSummary = useMemo(() => hasPublicTasteSummary(visits), [visits])
  const tabLabels = useMemo(() => publicProfileTabLabels(showTasteSummary), [showTasteSummary])
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
    <header className="public-user-profile__subhead"><button onClick={() => setView(null)} type="button"><ArrowLeft size={18} />返回</button><h1>{view === 'following' ? 'TA 关注的' : view === 'followers' ? '关注 TA 的' : view === 'visited' ? '去过的餐厅' : view === 'want' ? 'TA 想吃的餐厅' : view === 'map' ? 'TA 的公开地图' : '我们都想吃'}</h1><span /></header>
    {view === 'map' ? <PublicProfileMap onSelectRestaurant={onSelectRestaurant} restaurants={visitedRestaurants} user={user} /> : view === 'following' || view === 'followers' ? <PublicProfilePeopleRows emptyText={view === 'following' ? 'TA 暂时没有公开关注列表。' : 'TA 暂时没有公开粉丝列表。'} onSelectUser={onSelectUser} users={view === 'following' ? following : followers} /> : <PublicRestaurantRows emptyText={view === 'mutual' ? '你们暂时还没有共同想吃的餐厅。' : view === 'want' ? '这个用户暂时没有公开想吃的餐厅。' : '这个用户暂时没有公开到访记录。'} onSelectRestaurant={onSelectRestaurant} restaurants={view === 'mutual' ? mutualWants : view === 'want' ? wantRestaurants : visitedRestaurants} />}
  </section>

  return <section className="social-page public-user-profile">
    <header className="public-user-profile__hero">
      <div className="public-user-profile__top"><button onClick={onBack} type="button"><ArrowLeft size={19} /><span>返回</span></button><div><button aria-label="分享主页" onClick={() => void shareProfile()} type="button">{shared ? <Check size={19} /> : <Share2 size={19} />}</button><button aria-label="更多" type="button"><MoreHorizontal size={21} /></button></div></div>
      <div className="public-user-profile__identity">
        <span className="public-user-profile__avatar"><UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /></span>
        <div><h1><span>{user.nickname}</span>{shouldShowPremiumBurger(user.membershipTier) ? <PremiumBurgerBadge /> : null}</h1><strong>@{publicHandle(user)}</strong><p>{user.city || '未设置城市'}</p>{visibleProfileBio(user.bio) ? <p className="public-user-profile__bio">{visibleProfileBio(user.bio)}</p> : null}{formatJoinedMonth(user.createdAt) ? <small className="profile-joined-at">{formatJoinedMonth(user.createdAt)} 加入 Taste Map</small> : null}<span><BadgeCheck size={13} />ID {numericUserId}</span></div>
      </div>
      <div className="public-user-profile__actions"><button className={isFollowing ? 'is-following' : ''} disabled={followPending || !onToggleFollow} onClick={onToggleFollow} type="button">{isFollowing ? <UserCheck size={16} /> : <UserPlus size={16} />}{followPending ? '处理中…' : isFollowing ? '已关注' : '关注'}</button><button disabled={friendPending || friendStatus === 'accepted' || friendStatus === 'pending' || !onAddFriend} onClick={onAddFriend} type="button"><UsersRound size={16} />{friendLabel}</button></div>
      <div className="public-user-profile__metrics"><button onClick={() => openView('following')} type="button"><strong>{followingCount}</strong><small>关注</small></button><button onClick={() => openView('followers')} type="button"><strong>{followerCount}</strong><small>粉丝</small></button><button onClick={() => openView('visited')} type="button"><strong>{visitedRestaurants.length}</strong><small>去过餐厅</small></button><button onClick={() => openView('want')} type="button"><strong>{wantRestaurants.length}</strong><small>想去餐厅</small></button></div>
    </header>

    <nav className="public-profile-tabs" aria-label="公开主页内容">{tabLabels.map((label) => { const nextTab: PublicProfileTab = label === '动态' ? 'activity' : label === '口味' ? 'taste' : 'lists'; return <button className={tab === nextTab ? 'is-active' : ''} key={label} onClick={() => setTab(nextTab)} type="button">{label}</button> })}</nav>

    {shouldShowMutualWant(mutualWants.length) ? <button className="public-profile-mutual" onClick={() => openView('mutual')} type="button"><Heart size={19} /><span><strong>我们都想吃 {mutualWants.length} 家</strong><small>一起去试试这些店吧</small></span><span className="public-profile-mutual__avatars">{mutualWants.slice(0, 3).map((restaurant) => <RestaurantThumb key={restaurant.id} restaurant={restaurant} />)}</span><ChevronRight size={18} /></button> : null}

    {tab === 'activity' ? <>
      <ProfileSection action={representativeRestaurants.length ? '查看全部' : undefined} onAction={representativeRestaurants.length ? () => openView('visited') : undefined} title="最代表 TA 的餐厅"><div className="public-profile-representative">{representativeRestaurants.length ? representativeRestaurants.map((restaurant) => <button key={restaurant.id} onClick={() => onSelectRestaurant?.(restaurant)} type="button"><RestaurantThumb restaurant={restaurant} /><strong>{restaurant.name}</strong><small>{restaurant.tags[0] || restaurant.city}{restaurant.scoreOutOfTen !== null ? ` · ${restaurant.scoreOutOfTen.toFixed(1)}` : ''}</small><em>去过 {restaurant.visitCount} 次{restaurant.visitCount > 1 ? ' · 会再回去' : ''}</em></button>) : <p>继续公开记录后，这里会形成 TA 的代表餐厅。</p>}</div></ProfileSection>
      <button className="public-profile-footprint" onClick={() => openView('map')} type="button"><MapPinned size={20} /><span><strong>TA 去过的餐厅 · {visitedRestaurants.length} 家</strong><small>查看公开城市足迹</small></span><span>查看全部<ChevronRight size={16} /></span></button>
      <section className="public-profile-activity"><header><h2>最近公开到访</h2>{recentActivity.length ? <button onClick={() => openView('visited')} type="button">查看全部</button> : null}</header>{recentActivity.length ? recentActivity.map((activity) => <PublicActivityCard activity={activity} key={activity.visit.id} onSelectRestaurant={onSelectRestaurant} />) : <p className="public-profile-empty">这个用户暂时没有公开动态。</p>}</section>
    </> : null}
    {tab === 'lists' ? <section className="public-profile-lists"><header><h2>TA 的公开食单</h2></header>{publicLists.length ? publicLists.map((list) => <article key={list.title}><div className="public-profile-list-cover">{list.restaurants.slice(0, 4).map((restaurant) => <RestaurantThumb key={restaurant.id} restaurant={restaurant} />)}</div><div><strong>{list.title}</strong><small>{list.restaurants.length} 家餐厅</small><p>{list.description}</p></div></article>) : <p className="public-profile-empty">这个用户暂时没有公开食单。</p>}</section> : null}
    {tab === 'taste' && showTasteSummary ? <section className="public-profile-taste"><header><h2>TA 的口味偏好</h2><span>公开信息</span></header><dl><div><dt>偏爱菜系</dt><dd>{insights.tasteProfile.preferredCuisines.slice(0, 5).map((item) => item.label).join(' · ') || '数据积累中'}</dd></div><div><dt>常去价位</dt><dd>{insights.tasteProfile.preferredPriceRange}</dd></div><div><dt>偏好氛围</dt><dd>{insights.tasteProfile.highRatingTraits.slice(0, 4).map((item) => item.label).join(' · ') || '数据积累中'}</dd></div></dl><p>{insights.tasteProfile.summary}</p><small>基于 {insights.tasteProfile.validVisitCount} 次公开有效记录生成</small></section> : null}
  </section>
}

function PublicProfileMap({ user, restaurants, onSelectRestaurant }: { user: UserProfile; restaurants: RestaurantSummary[]; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const initialCity = useMemo(() => buildPublicProfileMap(restaurants).defaultCity, [restaurants])
  const [selectedCity, setSelectedCity] = useState<string | null>(initialCity)
  const [selectedRestaurant, setSelectedRestaurant] = useState<RestaurantSummary | undefined>()
  const model = useMemo(() => buildPublicProfileMap(restaurants, selectedCity), [restaurants, selectedCity])

  function selectCity(city: string) {
    setSelectedCity(city)
    setSelectedRestaurant(undefined)
  }

  if (!model.totalRestaurantCount) return <div className="public-profile-map-empty"><span><MapPinned size={24} /></span><h2>暂无可见的公开足迹</h2><p>对方公开到访餐厅后，会在这里形成地图。</p></div>

  return <div className="public-profile-map">
    <header className="public-profile-map__summary"><div><strong>{user.nickname} 的公开地图</strong><span>{model.totalRestaurantCount} 家可见餐厅</span></div><MapPinned size={21} /></header>
    <nav className="public-profile-map__cities" aria-label="选择公开足迹城市">
      {model.cities.map(({ city, restaurantCount }) => <button className={model.selectedCity === city ? 'is-active' : ''} key={city} onClick={() => selectCity(city)} type="button">{city}<span>{restaurantCount}</span></button>)}
    </nav>
    <div className="public-profile-map__canvas">
      <MapView key={`${user.id}:${model.selectedCity ?? 'all'}`} onClearSelection={() => setSelectedRestaurant(undefined)} onSelect={setSelectedRestaurant} restaurants={model.restaurants} selectedRestaurant={selectedRestaurant} />
      {selectedRestaurant ? <aside className="public-profile-map__preview">
        <RestaurantThumb restaurant={selectedRestaurant} />
        <span><strong>{selectedRestaurant.name}</strong><small>{[selectedRestaurant.tags[0], selectedRestaurant.averagePricePerPerson !== null ? `人均 ¥${Math.round(selectedRestaurant.averagePricePerPerson)}` : '', selectedRestaurant.city].filter(Boolean).join(' · ')}</small><em>TA 有 {selectedRestaurant.visitCount} 次可见到访记录</em></span>
        {onSelectRestaurant ? <button onClick={() => onSelectRestaurant(selectedRestaurant)} type="button">查看详情<ChevronRight size={15} /></button> : null}
      </aside> : null}
    </div>
  </div>
}

function PublicActivityCard({ activity, onSelectRestaurant }: { activity: PublicProfileActivity; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const { restaurant, visit } = activity
  const score = visit.rating === null ? null : visit.rating * 2
  const photo = visit.photos[0] ? { source: visit.photos[0], photoId: visit.photoIds[0] ?? null } : null
  return <button className="public-profile-activity-card" onClick={() => onSelectRestaurant?.(restaurant)} type="button">{photo ? <span className="public-profile-activity-card__photo"><SyncedImage alt="" loading="lazy" photoId={photo.photoId} source={photo.source} /></span> : <RestaurantThumb restaurant={restaurant} />}<span><strong>{restaurant.name}</strong><small>{restaurant.tags[0] || '餐厅'} · {restaurant.city}</small>{score !== null ? <em style={{ color: scoreColor(score) }}><Star size={12} fill="currentColor" />{score.toFixed(1)}</em> : null}<small>{formatPublicDate(visit.visitedAt)}</small>{visit.note ? <p>“{visit.note}”</p> : null}</span><Bookmark size={17} /></button>
}

function PublicProfilePeopleRows({ users, emptyText, onSelectUser }: { users: UserProfile[]; emptyText: string; onSelectUser?: (user: UserProfile) => void }) {
  return <div className="public-profile-people-rows">{users.length ? users.map((person) => <button disabled={!onSelectUser} key={person.id} onClick={() => onSelectUser?.(person)} type="button"><UserAvatar alt={person.nickname} avatarImageData={person.avatarImageData} avatarPhotoId={person.avatarPhotoId} avatarPresetId={person.avatarPresetId} membershipTier={person.membershipTier} /><span><strong>{person.nickname}{shouldShowPremiumBurger(person.membershipTier) ? <PremiumBurgerBadge /> : null}</strong><small>{person.city || '未设置城市'}{visibleProfileBio(person.bio) ? ` · ${visibleProfileBio(person.bio)}` : ''}</small></span><ChevronRight size={17} /></button>) : <p className="public-profile-empty">{emptyText}</p>}</div>
}

function PublicRestaurantRows({ restaurants, emptyText, onSelectRestaurant }: { restaurants: RestaurantSummary[]; emptyText: string; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  return <div className="public-profile-restaurant-rows">{restaurants.length ? restaurants.map((restaurant) => <button key={restaurant.id} onClick={() => onSelectRestaurant?.(restaurant)} type="button"><RestaurantThumb restaurant={restaurant} /><span><strong>{restaurant.name}</strong><small>{restaurant.tags[0] || '餐厅'} · {restaurant.city}</small><small>{restaurant.status === 'wantToGo' ? '已加入想去' : `去过 ${restaurant.visitCount} 次${restaurant.latestVisitDate ? ` · 最近 ${formatPublicDate(restaurant.latestVisitDate)}` : ''}`}</small></span>{restaurant.scoreOutOfTen !== null ? <em style={{ color: scoreColor(restaurant.scoreOutOfTen) }}>{restaurant.scoreOutOfTen.toFixed(1)}</em> : null}<ChevronRight size={17} /></button>) : <p className="public-profile-empty">{emptyText}</p>}</div>
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
function formatJoinedMonth(value?: string) { const date = value ? new Date(value) : null; return date && !Number.isNaN(date.getTime()) ? `${date.getFullYear()} 年 ${date.getMonth() + 1} 月` : '' }

function ProfileSection({ title, action, onAction, children }: { title: string; action?: string; onAction?: () => void; children: ReactNode }) { return <section className="profile-dashboard__section"><header><h2>{title}</h2>{action ? <button disabled={!onAction} onClick={onAction} type="button">{action}</button> : null}</header>{children}</section> }

function MemoryCard({ title, subtitle, values, icon, onClick }: { title: string; subtitle: string; values: string[]; icon: ReactNode; onClick: () => void }) { return <button onClick={onClick} type="button"><span className="profile-memory-card__icon">{icon}</span><span className="profile-memory-card__copy"><strong>{title}</strong><small>{subtitle}</small><em>{values.join(' · ')}</em></span><ChevronRight size={15} /></button> }

type TasteProfile = ReturnType<typeof buildProfileInsights>['tasteProfile']

function TasteProfileSummary({ profile, onClick }: { profile: TasteProfile; onClick: () => void }) {
  const cuisines = profile.preferredCuisines.slice(0, 3).map((item) => item.label).join(' · ') || '逐渐形成中'
  const traits = profile.highRatingTraits.slice(0, 2).map((item) => item.label).join(' · ')
  return <button className="profile-quick-card profile-quick-card--taste" onClick={onClick} type="button"><span className="profile-quick-card__visual"><Utensils size={24} /></span><span className="profile-quick-card__copy"><strong>我的口味档案</strong><small>{cuisines}</small><em>{[profile.preferredPriceRange, traits].filter(Boolean).join(' · ')}</em></span><ChevronRight size={18} /></button>
}

function ProfileDetailModal({ detail, insights, visits, restaurants, diningCompanions, sourceUsers, user, ownerUserId, monthReview, yearReview, onThisDayReview, premium, onClose, onSelectRestaurant }: { detail: 'month' | 'year' | 'day' | 'taste' | 'data' | 'companions' | 'sources'; insights: ReturnType<typeof buildProfileInsights>; visits: Visit[]; restaurants: RestaurantSummary[]; diningCompanions: DiningCompanion[]; sourceUsers: UserProfile[]; user: UserProfile; ownerUserId: string; monthReview: PeriodReview; yearReview: PeriodReview; onThisDayReview: OnThisDayReview; premium: boolean; onClose: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const membershipTier = premium ? 'member' : 'free'
  const gatedDetails: Partial<Record<typeof detail, { feature: MembershipFeature; title: string; description: string }>> = {
    taste: { feature: 'full_taste_profile', title: '完整口味档案', description: '查看完整偏好、预算、场景、评分风格与口味变化。' },
    companions: { feature: 'companion_analysis', title: '最佳饭搭子', description: '查看与你最常一起吃饭的人，以及共同偏好与到访洞察。' },
    sources: { feature: 'recommendation_source_analysis', title: '谁最会种草', description: '验证哪些人和平台更懂你的口味。' },
    month: { feature: 'monthly_review', title: '本月回顾', description: '把本月的味觉照片、记忆与变化整理成一页回顾。' },
    year: { feature: 'annual_review', title: '年度回顾', description: '查看完整食味年鉴、城市足迹与年度变化。' },
  }
  const gate = gatedDetails[detail]
  if (gate && !canUseFeature(membershipTier, gate.feature)) return <ModalShell description="当前账号为免费版。" onClose={onClose} size="large" title={gate.title}><PremiumFeatureGate description={gate.description} feature={gate.feature} /></ModalShell>
  if (detail === 'taste') {
    const shareData = buildTasteProfileShareData(user, insights.tasteProfile, restaurants, visits)
    return <ModalShell description="根据真实到访、评分、重复到访与结构化体验持续更新。" onClose={onClose} size="large" title="完整口味档案"><AnalysisShareToolbar data={shareData} /><TasteProfileDetails profile={insights.tasteProfile} restaurants={restaurants} /></ModalShell>
  }
  if (detail === 'data') return <ModalShell description="只统计当前账号的有效记录。" onClose={onClose} size="large" title="我的数据"><div className="profile-data-detail"><span><strong>{visits.length}</strong>总用餐次数</span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong>去过餐厅</span><span><strong>{insights.cityCount}</strong>去过城市</span><span><strong>{insights.tasteProfile.repeatVisit.tendency}</strong>复购倾向</span></div></ModalShell>
  if (detail === 'companions') {
    const shareData = buildCompanionShareData(user, diningCompanions, restaurants, visits)
    return <ModalShell description="只基于你自己的真实共同到访记录，不评价关系质量。" onClose={onClose} size="large" title="最佳饭搭子"><AnalysisShareToolbar data={shareData} /><CompanionInsightsPanel companions={diningCompanions} linkedUsers={sourceUsers} onSelectRestaurant={onSelectRestaurant} ownerUserId={ownerUserId} restaurants={restaurants} visits={visits} /></ModalShell>
  }
  if (detail === 'sources') {
    const shareData = buildRecommendationSourceShareData(user, restaurants, visits, sourceUsers)
    return <ModalShell description="推荐的价值由真实到访、评分和再次到访验证。" onClose={onClose} size="large" title="谁最会种草"><AnalysisShareToolbar data={shareData} /><RecommendationSourceInsightsPanel onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} sourceUsers={sourceUsers} visits={visits} /></ModalShell>
  }
  if (detail === 'month' || detail === 'year') {
    const review = detail === 'month' ? monthReview : yearReview
    return <ReviewDetail review={review} shareData={buildPeriodReviewShareData(user, review)} onClose={onClose} />
  }
  return <OnThisDayDetail review={onThisDayReview} shareData={buildOnThisDayShareData(user, onThisDayReview)} onClose={onClose} />
}

function AnalysisShareToolbar({ data }: { data: AnalysisShareData }) {
  return <div className="analysis-share-toolbar"><div><Share2 size={18} /><span><strong>分享这份分析</strong><small>生成独立海报，不会截取当前页面</small></span></div><AnalysisShareAction data={data} /></div>
}

function PremiumFeatureGate({ description, feature }: { description: string; feature: MembershipFeature }) {
  return <section className="premium-feature-gate"><span><LockKeyhole size={25} /></span><small>PREMIUM</small><h3>会员专属深度功能</h3><p>{description}</p><button onClick={() => openPremiumPaywall(feature)} type="button"><Sparkles size={16} /> 查看 Premium</button></section>
}

function ReviewPhotoImage({ photo, alt }: { photo: ReviewPhoto; alt: string }) {
  return <SyncedImage alt={alt} fallback={<span className="review-photo-placeholder"><Utensils size={24} /></span>} loading="lazy" photoId={photo.photoId} source={photo.source} />
}

function ReviewMemoryCard({ memory, label }: { memory: ReviewMemory; label?: string }) {
  return <article className="review-memory-card">
    <ReviewPhotoImage alt={memory.restaurantName} photo={memory.photo} />
    <div>{label ? <small>{label}</small> : null}<strong>{memory.restaurantName}</strong><span>{memory.city}{memory.scoreOutOfTen !== null ? ` · ${memory.scoreOutOfTen.toFixed(1)} 分` : ''}{memory.visitCount > 1 ? ` · ${memory.visitCount} 次` : ''}</span>{memory.note ? <p>{memory.note}</p> : null}<time>{new Date(memory.visitedAt).toLocaleDateString('zh-CN')}</time></div>
  </article>
}

function ReviewMetrics({ review }: { review: PeriodReview }) {
  const metrics: Array<[string, string]> = [
    ['用餐', `${review.visitCount} 次`],
    ['餐厅', `${review.restaurantCount} 家`],
    [review.kind === 'year' ? '初次记录' : '新店', `${review.newRestaurantCount} 家`],
  ]
  if (review.kind === 'year') metrics.push(['再次到访', `${review.revisitCount} 家`])
  return <><section className="period-review__hero">{metrics.map(([label, value]) => <span key={label}><strong>{value}</strong><small>{label}</small></span>)}</section>{review.visitCount ? <p className="period-review__spend-note">{review.spendDisplay === 'total' ? `实际消费总计 ¥${Math.round(review.actualSpend)}` : review.spendDisplay === 'recorded' ? `已记录实际消费 ¥${Math.round(review.actualSpend)}（${review.visitsWithSpend}/${review.visitCount} 次有金额）` : `实际消费记录覆盖 ${review.visitsWithSpend}/${review.visitCount} 次，暂不汇总金额`}</p> : null}</>
}

function ReviewInsightSections({ review }: { review: PeriodReview }) {
  return <>
    {review.companionInsight ? <section className="review-insight-card"><UsersRound size={19} /><div><h3>和谁一起吃</h3><strong>{review.companionInsight.name}</strong><p>一起记录 {review.companionInsight.count} 次，去过 {review.companionInsight.restaurantCount} 家餐厅。</p></div></section> : null}
    {review.sourceInsight ? <section className="review-insight-card"><Sparkles size={19} /><div><h3>灵感从哪里来</h3><strong>{review.sourceInsight.title}</strong><p>{review.sourceInsight.body}</p></div></section> : null}
    {review.changes.length ? <section><h3>{review.kind === 'month' ? '和上月相比' : '和去年相比'}</h3><div className="review-change-list">{review.changes.map((change) => <span className={`is-${change.tone}`} key={`${change.label}-${change.value}`}><small>{change.label}</small><strong>{change.value}</strong></span>)}</div></section> : null}
  </>
}

function ReviewDetail({ review, shareData, onClose }: { review: PeriodReview; shareData: AnalysisShareData; onClose: () => void }) {
  const title = review.kind === 'month' ? `${review.month} 月回顾` : `${review.year} 食味年鉴`
  if (!review.visitCount) return <ModalShell description={review.summary} onClose={onClose} size="large" title={title}><AnalysisShareToolbar data={shareData} /><div className="review-empty"><CalendarDays size={30} /><strong>这段时间还没有到访记录</strong><p>下一次真实记录会自动出现在这里。</p></div></ModalShell>
  return <ModalShell description={review.summary} onClose={onClose} size="large" title={title}><div className={`period-review period-review--${review.kind}`}>
    <AnalysisShareToolbar data={shareData} />
    {review.heroPhotos.length ? <section className="period-review__cover"><div>{review.heroPhotos.map((photo, index) => <ReviewPhotoImage alt={`${title}照片 ${index + 1}`} key={`${photo.photoId || photo.source}-${index}`} photo={photo} />)}</div><small>{review.kind === 'month' ? '本月照片记忆' : '这一年的食味拼图'}</small></section> : null}
    <ReviewMetrics review={review} />
    {review.highlightVisit ? <section><h3>{review.kind === 'month' ? '本月最值得记住' : '年度记忆'}</h3><ReviewMemoryCard memory={review.highlightVisit} /></section> : null}
    {review.kind === 'month' ? <>
      {review.diningPatterns.length ? <section><h3>这个月怎么吃</h3><div className="review-patterns">{review.diningPatterns.map((pattern) => <span key={pattern}>{pattern}</span>)}</div></section> : null}
      <ReviewInsightSections review={review} />
    </> : <>
      {review.keyRestaurants.length ? <section><h3>这一年的关键餐厅</h3><div className="review-key-restaurants">{review.keyRestaurants.map((item) => <ReviewMemoryCard key={`${item.kind}-${item.memory.visitId}`} label={item.label} memory={item.memory} />)}</div></section> : null}
      {review.tasteChanges.length ? <section><h3>口味变化</h3><div className="review-patterns">{review.tasteChanges.map((item) => <span key={item}>{item}</span>)}</div></section> : null}
      {review.mapFootprint.length ? <section><h3>城市足迹</h3><div className="review-city-list">{review.mapFootprint.map((item) => <span key={item.city}><MapPinned size={15} /><strong>{item.city}</strong><small>{item.count} 次</small></span>)}</div></section> : null}
      <section><h3>全年节奏</h3><div className="period-review__distribution">{review.timeDistribution.map((item) => <span key={item.label}><i style={{ height: `${Math.max(8, item.count / Math.max(1, ...review.timeDistribution.map((value) => value.count)) * 100)}%` }} /><small>{item.label}</small><b>{item.count}</b></span>)}</div></section>
      <ReviewInsightSections review={review} />
      {review.milestones.length ? <section><h3>年度里程碑</h3><div className="review-patterns">{review.milestones.map((item) => <span key={item}>{item}</span>)}</div></section> : null}
    </>}
  </div></ModalShell>
}

function OnThisDayDetail({ review, shareData, onClose }: { review: OnThisDayReview; shareData: AnalysisShareData; onClose: () => void }) {
  return <ModalShell description={`${review.month} 月 ${review.day} 日的往年味觉记忆`} onClose={onClose} size="large" title="那年今日"><div className="on-this-day-review">
    <AnalysisShareToolbar data={shareData} />
    {review.memories.length ? review.memories.map((memory) => <article key={memory.visitId}><span className="on-this-day-review__year">{memory.yearsAgo} 年前</span><ReviewMemoryCard memory={memory} /></article>) : <div className="review-empty"><ImageIcon size={30} /><strong>今天还没有往年记录</strong><p>这里只显示同月同日的真实到访。</p></div>}
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
  const hasChanges = nickname !== user.nickname
    || bio !== (user.bio ?? '')
    || city !== (user.city ?? '')
    || avatarImageData !== (user.avatarImageData ?? null)
    || avatarPhotoId !== (user.avatarPhotoId ?? null)
    || avatarPresetId !== (user.avatarPresetId ?? AVATAR_PRESETS[0]?.id ?? '')
  async function chooseAvatar(event: ChangeEvent<HTMLInputElement>) { const file = event.target.files?.[0]; event.target.value = ''; if (file && user.membershipTier === 'member') { setAvatarImageData(await optimizeAvatarImage(file)); setAvatarPhotoId(null) } }
  async function submit(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    setMessage('')
    try {
      await onSave({ nickname, bio, city, avatarImageData, avatarPhotoId, avatarPresetId })
      setMessage('个人资料已保存并等待云端同步')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : '保存失败，请重试')
    } finally {
      setSaving(false)
    }
  }
  return <ModalShell description="头像、昵称、城市和简介统一在这里修改。" onClose={onClose} size="large" title="编辑资料">
    <form className="sticky-action-form" onSubmit={submit}>
      <div className="profile-editor-modal sticky-action-form__content">
        <div className="avatar-preset-grid">{AVATAR_PRESETS.map((preset) => <button aria-label={preset.label} className={avatarPresetId === preset.id && !avatarImageData && !avatarPhotoId ? 'is-active' : ''} key={preset.id} onClick={() => { setAvatarPresetId(preset.id); setAvatarImageData(null); setAvatarPhotoId(null) }} type="button"><PresetAvatar id={preset.id} /><small>{preset.label}</small></button>)}</div>
        {user.membershipTier === 'member' ? <button className="custom-avatar-upload" onClick={() => inputRef.current?.click()} type="button">自定义上传头像</button> : <button className="custom-avatar-locked" onClick={() => openPremiumPaywall('custom_avatar')} type="button"><LockKeyhole size={14} />会员可上传自定义头像；预设头像均可直接使用。</button>}
        <input accept="image/*" hidden onChange={chooseAvatar} ref={inputRef} type="file" />
        <div className="profile-editor-modal__fields"><label className="field"><span>昵称</span><input maxLength={30} onChange={(event) => setNickname(event.target.value)} required value={nickname} /></label><label className="field"><span>城市</span><input maxLength={30} onChange={(event) => setCity(event.target.value)} placeholder="例如：杭州" value={city} /></label><label className="field"><span>个人简介</span><textarea maxLength={160} onChange={(event) => setBio(event.target.value)} rows={3} value={bio} /></label></div>
      </div>
      <StickyFormActionBar
        primaryDisabled={!nickname.trim() || !hasChanges}
        primaryLabel="保存资料"
        primaryLoading={saving}
        secondaryAction={onClose}
        statusMessage={message}
        statusTone={message.includes('失败') ? 'error' : 'success'}
      />
    </form>
  </ModalShell>
}

function AccountPrivacyPage({ user, onBack, onOpenSettings, onMapPrivacyChange }: { user: UserProfile; onBack: () => void; onOpenSettings?: () => void; onMapPrivacyChange?: (changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) => Promise<unknown> }) {
  return <section className="social-page account-privacy-page"><header><button aria-label="返回我的" onClick={onBack} type="button"><ArrowLeft size={20} /></button><h1>账号与隐私</h1><span /></header><SettingsGroup title="账户"><SettingRow label="登录方式" value={user.authProvider === 'cloudflare-access' ? 'Cloudflare Access' : '本地账号'} /><SettingRow label="绑定邮箱" value={user.email || '未绑定'} /><MembershipAdminEntry /></SettingsGroup><SettingsGroup title="隐私设置"><div className="account-map-privacy"><span><strong>个人主页可见范围</strong><small>决定其他用户能否看到你的地图足迹</small></span><div>{([['private', '仅自己'], ['friends', '好友'], ['public', '公开']] as [Visibility, string][]).map(([value, label]) => <button className={user.mapVisibility === value && user.mapSharingEnabled === (value !== 'private') ? 'is-active' : ''} key={value} onClick={() => void onMapPrivacyChange?.({ mapSharingEnabled: value !== 'private', mapVisibility: value })} type="button">{label}</button>)}</div></div><SettingRow label="公开记录默认权限" value="每次记录时选择" /><SettingRow label="谁可以给我发送消息" value="好友" /></SettingsGroup><SettingsGroup title="权限管理"><SettingRow label="定位权限" value="由浏览器管理" /><SettingRow label="照片权限" value="选择照片时授权" /><SettingRow label="通知权限" value="由浏览器管理" /></SettingsGroup><SettingsGroup title="数据管理"><button className="account-setting-button" onClick={onOpenSettings} type="button"><span><strong>导出、备份与恢复</strong><small>打开数据与设置</small></span><ChevronRight size={17} /></button></SettingsGroup><SettingsGroup title="关于"><SettingRow label="隐私政策" value="查看" /><SettingRow label="用户协议" value="查看" /><SettingRow label="帮助与反馈" value="查看" /><SettingRow label="关于 Taste Map" value="v1.2.0" /></SettingsGroup><section className="danger-zone"><strong>危险操作</strong><button disabled type="button">删除账号</button><small>账号删除需要再次验证登录身份，当前不会误触执行。</small></section></section>
}
function SettingsGroup({ title, children }: { title: string; children: ReactNode }) { return <section className="account-settings-group"><h2>{title}</h2><div>{children}</div></section> }
function SettingRow({ label, value }: { label: string; value: string }) { return <button className="account-setting-button" type="button"><span><strong>{label}</strong></span><em>{value}</em><ChevronRight size={16} /></button> }
