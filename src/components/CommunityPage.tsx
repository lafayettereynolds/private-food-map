import { Globe2, MapPin, Star } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import type { CommunityVisit, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { SyncedImage } from './SyncedImage'
import { UserAvatar } from './UserAvatar'
import { fetchCommunityFeed } from '../services/socialApi'

interface FeedItem {
  user: UserProfile
  restaurant: RestaurantSummary
  visit: Visit
}

export function CommunityPage({
  users,
  restaurants,
  onSelectRestaurant,
  onViewProfile,
}: {
  users: UserProfile[]
  restaurants: RestaurantSummary[]
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
  onViewProfile: (user: UserProfile) => void
}) {
  const userById = new Map(users.map((user) => [user.id, user]))
  const [cloudFeed, setCloudFeed] = useState<CommunityVisit[]>([])
  useEffect(() => {
    let active = true
    void fetchCommunityFeed().then((items) => { if (active) setCloudFeed(items) }).catch(() => undefined)
    return () => { active = false }
  }, [])
  const localFeed: FeedItem[] = restaurants.flatMap((restaurant) => restaurant.visits.flatMap((visit) => {
    const user = userById.get(visit.userId ?? 'owner')
    return user?.mapSharingEnabled && user.mapVisibility !== 'private' ? [{ user, restaurant, visit }] : []
  }))
  const feed = useMemo(() => {
    const items = new Map<string, FeedItem>(localFeed.map((item) => [item.visit.id, item]))
    cloudFeed.forEach((item) => {
      if (items.has(item.visit.id)) return
      const localRestaurant = restaurants.find((restaurant) => restaurant.id === item.restaurant.id)
      items.set(item.visit.id, {
        user: {
          id: item.user.id, nickname: item.user.nickname, email: null, bio: item.user.bio, city: item.user.city,
          avatarImageData: item.user.avatarImageData, avatarPhotoId: item.user.avatarPhotoId,
          avatarPresetId: item.user.avatarPresetId ?? 'polar-bear', membershipTier: item.user.membershipTier ?? 'free',
          mapSharingEnabled: false, mapVisibility: 'private',
          authProvider: 'cloudflare-access', authSubject: null, createdAt: '', updatedAt: '', deletedAt: null,
        },
        restaurant: localRestaurant ?? {
          ...item.restaurant,
          userId: item.visit.userId,
          amapPoiId: `community-${item.restaurant.id}`,
          status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null,
          environmentRating: null, serviceRating: null, valueRating: null, tags: [], longTermNote: '', pricePerPerson: null,
          markerType: 'emoji', markerImageData: null, markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍽️',
          createdAt: item.visit.createdAt, updatedAt: item.visit.updatedAt, deletedAt: null,
          visitCount: 1, averageRating: item.visit.rating, scoreOutOfTen: item.visit.rating ? item.visit.rating * 2 : null,
          latestVisitDate: item.visit.visitedAt, latestVisit: item.visit, visits: [item.visit], averagePricePerPerson: item.visit.pricePerPerson,
          averageQueueMinutes: null,
        },
        visit: item.visit,
      })
    })
    return [...items.values()].sort((a, b) => b.visit.visitedAt.localeCompare(a.visit.visitedAt))
  }, [cloudFeed, localFeed, restaurants])

  return <section className="social-page community-page">
    <header className="social-page__heading"><div><span className="eyebrow">COMMUNITY</span><h1>社区</h1><p>是否展示足迹，由每位用户在“我的地图隐私”中统一控制。</p></div><Globe2 size={28} /></header>
    {feed.length ? <div className="community-feed">{feed.map((item) => <article className="community-card" key={item.visit.id}>
      <header><button className="user-avatar-small" onClick={() => onViewProfile(item.user)} type="button"><UserAvatar alt="" avatarImageData={item.user.avatarImageData} avatarPhotoId={item.user.avatarPhotoId} avatarPresetId={item.user.avatarPresetId} membershipTier={item.user.membershipTier} /></button><button className="community-user-link" onClick={() => onViewProfile(item.user)} type="button"><strong>{item.user.nickname}</strong><time>{formatVisitDateTime(item.visit.visitedAt)}</time></button></header>
      <button className="community-restaurant" onClick={() => onSelectRestaurant(item.restaurant)} type="button"><div><strong>{item.restaurant.name}</strong><span><MapPin size={12} /> {item.restaurant.city} · {item.restaurant.address}</span></div>{item.visit.rating ? <b><Star fill="currentColor" size={13} /> {item.visit.rating} 星</b> : null}</button>
      {item.visit.note ? <p>{item.visit.note}</p> : null}
      {item.visit.photos.length ? <div className="community-photos">{item.visit.photos.slice(0, 6).map((photo, index) => <SyncedImage alt="公开到访照片" key={`${item.visit.id}-${index}`} loading="lazy" photoId={item.visit.photoIds[index]} source={photo} />)}</div> : null}
    </article>)}</div> : <div className="social-empty"><Globe2 size={24} /><strong>还没有可见记录</strong><p>在“我的”里开启地图分享后，足迹会按你选择的范围展示。</p></div>}
  </section>
}
