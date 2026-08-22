import { Check, Search, UserMinus, UserPlus, UsersRound, X } from 'lucide-react'
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Friendship, RestaurantSummary, SharedMeal, SharedMealParticipant, UserProfile } from '../types/domain'
import { SyncedImage } from './SyncedImage'
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
}) {
  const [query, setQuery] = useState('')
  const [cloudUsers, setCloudUsers] = useState<UserProfile[]>([])
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
  const accepted = friendships.filter((item) => item.status === 'accepted' && (item.requesterId === currentUserId || item.addresseeId === currentUserId))
  const incoming = friendships.filter((item) => item.status === 'pending' && item.addresseeId === currentUserId)
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

  return <section className="social-page friends-page">
    <header className="social-page__heading"><div><span className="eyebrow">PEOPLE</span><h1>好友与饭局</h1><p>饭搭子仍可自由填写；好友只用于邀请共同饭局。</p></div><UsersRound size={28} /></header>
    {mealInvitations.length ? <section className="social-section"><h2>饭局邀请</h2><div className="friend-list">{mealInvitations.map((participant) => {
      const meal = sharedMeals.find((item) => item.id === participant.sharedMealId)
      const restaurant = meal ? restaurants.find((item) => item.id === meal.restaurantId) : undefined
      const inviter = meal ? userById.get(meal.createdByUserId) : undefined
      if (!meal || !restaurant) return null
      return <article className="meal-invitation" key={participant.id}><div><strong>{inviter?.nickname ?? '好友'} 邀请你记录一次饭局</strong><p>{restaurant.name} · {new Date(meal.occurredAt).toLocaleString('zh-CN')}</p><span>接受后由你填写自己的评分、感受、照片和消费。</span></div><div><button className="primary-button" onClick={() => onAcceptMeal(participant, restaurant)} type="button"><Check size={14} /> 添加</button><button className="text-button" onClick={() => onDeclineMeal(participant)} type="button">忽略</button></div></article>
    })}</div></section> : null}
    {incoming.length ? <section className="social-section"><h2>好友请求</h2><div className="friend-list">{incoming.map((friendship) => <FriendRow actions={<><button aria-label="接受好友请求" onClick={() => mutate(friendship, 'accepted')} type="button"><Check size={15} /></button><button aria-label="拒绝好友请求" onClick={() => mutate(friendship, 'rejected')} type="button"><X size={15} /></button></>} key={friendship.id} onViewProfile={onViewProfile} user={userById.get(friendship.requesterId)} />)}</div></section> : null}
    <section className="social-section"><h2>查找用户</h2><label className="people-search"><Search size={16} /><input onChange={(event) => setQuery(event.target.value)} placeholder="搜索昵称或城市" value={query} /></label>{query.trim() ? <div className="friend-list">{results.length ? results.map((user) => {
      const existing = friendshipByUser.get(user.id)
      return <FriendRow actions={existing && existing.status !== 'removed' && existing.status !== 'rejected' ? <span className="relationship-status">{existing.status === 'accepted' ? '已是好友' : '已发送'}</span> : <button aria-label={`添加 ${user.nickname}`} onClick={() => requestFriend(user.id)} type="button"><UserPlus size={15} /></button>} key={user.id} onViewProfile={onViewProfile} user={user} />
    }) : <p className="inline-empty">没有找到这个用户。</p>}</div> : null}</section>
    <section className="social-section"><h2>我的好友</h2>{accepted.length ? <div className="friend-list">{accepted.map((friendship) => {
      const otherId = friendship.requesterId === currentUserId ? friendship.addresseeId : friendship.requesterId
      return <FriendRow actions={<button aria-label="删除好友" onClick={() => mutate(friendship, 'removed')} type="button"><UserMinus size={15} /></button>} key={friendship.id} onViewProfile={onViewProfile} user={userById.get(otherId)} />
    })}</div> : <div className="social-empty compact"><UsersRound size={20} /><strong>还没有好友</strong><p>只有接受关系后，好友记录才会按权限显示。</p></div>}</section>
  </section>
}

function FriendRow({ user, actions, onViewProfile }: { user?: UserProfile; actions: ReactNode; onViewProfile: (user: UserProfile) => void }) {
  if (!user) return null
  return <article className="friend-row"><button className="user-avatar-small" onClick={() => onViewProfile(user)} type="button">{user.avatarImageData || user.avatarPhotoId ? <SyncedImage alt="" photoId={user.avatarPhotoId} source={user.avatarImageData} /> : user.nickname.slice(0, 1)}</button><button className="friend-profile-link" onClick={() => onViewProfile(user)} type="button"><strong>{user.nickname}</strong><span>{user.city || '未填写城市'}</span></button><div className="friend-row__actions">{actions}</div></article>
}

function createRelationshipId(first: string, second: string) {
  return `friendship:${[first, second].sort().join(':')}`
}
