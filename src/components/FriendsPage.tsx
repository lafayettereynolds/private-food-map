import { Check, Search, UserMinus, UserPlus, UsersRound, X } from 'lucide-react'
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Friendship, RestaurantSummary, SharedMeal, SharedMealParticipant, UserProfile } from '../types/domain'
import { UserAvatar } from './UserAvatar'
import { respondToFriendship, searchCloudUsers, sendFriendRequest } from '../services/socialApi'

export function FriendsPage({
  currentUserId,
  users,
  friendships,
  sharedMeals,
  participants,
  restaurants,
  onFriendshipChange,
  onAcceptMeal,
  onDeclineMeal,
  onViewProfile,
  embedded = false,
}: {
  currentUserId: string
  users: UserProfile[]
  friendships: Friendship[]
  sharedMeals: SharedMeal[]
  participants: SharedMealParticipant[]
  restaurants: RestaurantSummary[]
  onFriendshipChange: (friendship: Friendship) => void
  onAcceptMeal: (participant: SharedMealParticipant, restaurant: RestaurantSummary) => void
  onDeclineMeal: (participant: SharedMealParticipant) => void
  onViewProfile: (user: UserProfile) => void
  embedded?: boolean
}) {
  const [query, setQuery] = useState('')
  const [cloudUsers, setCloudUsers] = useState<UserProfile[]>([])
  const [connectionsOpen, setConnectionsOpen] = useState(false)
  useEffect(() => {
    if (!query.trim()) {
      setCloudUsers([])
      return
    }
    let active = true
    const timeout = window.setTimeout(() => {
      void searchCloudUsers(query).then((items) => {
        if (!active) return
        setCloudUsers(items.map((user) => ({
          ...user,
          email: null,
          avatarImageData: user.avatarImageData ?? (user.avatarPhotoId ? `drive-photo:${user.avatarPhotoId}` : null),
          avatarPresetId: user.avatarPresetId ?? 'polar-bear',
          membershipTier: user.membershipTier ?? 'free',
          mapSharingEnabled: false,
          mapVisibility: 'private',
          authProvider: 'cloudflare-access',
          authSubject: null,
          createdAt: '',
          updatedAt: '',
          deletedAt: null,
        })))
      }).catch(() => { if (active) setCloudUsers([]) })
    }, 280)
    return () => { active = false; window.clearTimeout(timeout) }
  }, [query])
  const searchableUsers = useMemo(() => {
    const merged = new Map(users.map((user) => [user.id, user]))
    cloudUsers.forEach((user) => merged.set(user.id, user))
    return [...merged.values()]
  }, [cloudUsers, users])
  const userById = useMemo(() => new Map(users.map((user) => [user.id, user])), [users])
  const friendshipByUser = useMemo(() => new Map(friendships.flatMap((friendship) => {
    if (friendship.requesterId === currentUserId) return [[friendship.addresseeId, friendship] as const]
    if (friendship.addresseeId === currentUserId) return [[friendship.requesterId, friendship] as const]
    return []
  })), [currentUserId, friendships])
  const results = query.trim() ? searchableUsers.filter((user) => user.id !== currentUserId && `${user.nickname} ${user.city}`.toLocaleLowerCase('zh-CN').includes(query.trim().toLocaleLowerCase('zh-CN'))) : []
  const following = friendships.filter((item) => (item.status === 'pending' && item.requesterId === currentUserId) || (item.status === 'accepted' && (item.requesterId === currentUserId || item.addresseeId === currentUserId)))
  const followers = friendships.filter((item) => (item.status === 'pending' && item.addresseeId === currentUserId) || (item.status === 'accepted' && (item.requesterId === currentUserId || item.addresseeId === currentUserId)))
  const mealInvitations = participants.filter((item) => item.userId === currentUserId && item.status === 'pending')

  const mutate = (friendship: Friendship, status: Friendship['status']) => {
    onFriendshipChange({ ...friendship, status, updatedAt: new Date().toISOString() })
    if (status === 'accepted' || status === 'rejected' || status === 'removed') void respondToFriendship(friendship.id, status).catch(() => undefined)
  }
  const requestFriend = (userId: string) => {
    const now = new Date().toISOString()
    onFriendshipChange({ id: createRelationshipId(currentUserId, userId), requesterId: currentUserId, addresseeId: userId, status: 'pending', createdAt: now, updatedAt: now })
    void sendFriendRequest(userId).catch(() => undefined)
  }

  const connectionContent = <>
    {mealInvitations.length ? <section className="social-section"><h2>饭局邀请</h2><div className="friend-list">{mealInvitations.map((participant) => {
      const meal = sharedMeals.find((item) => item.id === participant.sharedMealId)
      const restaurant = meal ? restaurants.find((item) => item.id === meal.restaurantId) : undefined
      const inviter = meal ? userById.get(meal.createdByUserId) : undefined
      if (!meal || !restaurant) return null
      return <article className="meal-invitation" key={participant.id}><div><strong>{inviter?.nickname ?? '好友'} 邀请你记录一次饭局</strong><p>{restaurant.name} · {new Date(meal.occurredAt).toLocaleString('zh-CN')}</p><span>接受后由你填写自己的评分、感受、照片和消费。</span></div><div><button className="primary-button" onClick={() => onAcceptMeal(participant, restaurant)} type="button"><Check size={14} /> 添加</button><button className="text-button" onClick={() => onDeclineMeal(participant)} type="button">忽略</button></div></article>
    })}</div></section> : null}
    <section className="social-section"><h2>关注我的</h2>{followers.length ? <div className="friend-list">{followers.map((friendship) => {
      const otherId = friendship.requesterId === currentUserId ? friendship.addresseeId : friendship.requesterId
      const isPendingIncoming = friendship.status === 'pending' && friendship.addresseeId === currentUserId
      return <FriendRow actions={isPendingIncoming ? <><button aria-label="回关" onClick={() => mutate(friendship, 'accepted')} title="回关" type="button"><UserPlus size={15} /></button><button aria-label="移除关注者" onClick={() => mutate(friendship, 'rejected')} title="移除" type="button"><X size={15} /></button></> : <span className="relationship-status">互相关注</span>} key={friendship.id} onViewProfile={onViewProfile} user={userById.get(otherId)} />
    })}</div> : <p className="inline-empty">还没有人关注你。</p>}</section>
    <section className="social-section"><h2>我关注的</h2>{following.length ? <div className="friend-list">{following.map((friendship) => {
      const otherId = friendship.requesterId === currentUserId ? friendship.addresseeId : friendship.requesterId
      return <FriendRow actions={<><span className="relationship-status">{friendship.status === 'accepted' ? '互相关注' : '已关注'}</span><button aria-label="取消关注" onClick={() => mutate(friendship, 'removed')} title="取消关注" type="button"><UserMinus size={15} /></button></>} key={friendship.id} onViewProfile={onViewProfile} user={userById.get(otherId)} />
    })}</div> : <p className="inline-empty">还没有关注其他用户。</p>}</section>
  </>

  const discoveryContent = <section className="social-section people-discovery"><h2>发现好友</h2><p>按昵称或城市找到其他 Taste Map 用户。</p><label className="people-search"><Search size={16} /><input onChange={(event) => setQuery(event.target.value)} placeholder="搜索昵称或城市" value={query} /></label>{query.trim() ? <div className="friend-list">{results.length ? results.map((user) => {
    const existing = friendshipByUser.get(user.id)
    return <FriendRow actions={existing && existing.status !== 'removed' && existing.status !== 'rejected' ? <span className="relationship-status">{existing.status === 'accepted' ? '互相关注' : existing.requesterId === currentUserId ? '已关注' : '关注你'}</span> : <button aria-label={`关注 ${user.nickname}`} onClick={() => requestFriend(user.id)} title="关注" type="button"><UserPlus size={15} /></button>} key={user.id} onViewProfile={onViewProfile} user={user} />
  }) : <p className="inline-empty">没有找到这个用户。</p>}</div> : null}</section>

  return <section className={embedded ? 'profile-connections' : 'social-page friends-page'}>
    {!embedded ? <header className="social-page__heading"><div><span className="eyebrow">PEOPLE</span><h1>我的关注</h1><p>饭搭子仍可自由填写；互相关注后可以邀请共同饭局。</p></div><UsersRound size={28} /></header> : null}
    <div className="relationship-counts relationship-counts--profile"><button onClick={() => setConnectionsOpen(true)} type="button"><strong>{followers.length}</strong><span>关注我的</span></button><button onClick={() => setConnectionsOpen(true)} type="button"><strong>{following.length}</strong><span>我关注的</span></button></div>
    {embedded ? <><details className="profile-connections-details" onToggle={(event) => setConnectionsOpen(event.currentTarget.open)} open={connectionsOpen}><summary>管理关注与饭局</summary><div>{connectionContent}</div></details><details className="people-discovery-details"><summary><Search size={15} /> 发现好友</summary>{discoveryContent}</details></> : <>{connectionContent}{discoveryContent}</>}
  </section>
}

function FriendRow({ user, actions, onViewProfile }: { user?: UserProfile; actions: ReactNode; onViewProfile: (user: UserProfile) => void }) {
  if (!user) return null
  return <article className="friend-row"><button className="user-avatar-small" onClick={() => onViewProfile(user)} type="button"><UserAvatar alt="" avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /></button><button className="friend-profile-link" onClick={() => onViewProfile(user)} type="button"><strong>{user.nickname}</strong><span>{user.city || '未填写城市'}</span></button><div className="friend-row__actions">{actions}</div></article>
}

function createRelationshipId(first: string, second: string) {
  return `friendship:${[first, second].sort().join(':')}`
}
