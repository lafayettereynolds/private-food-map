import { useEffect } from 'react'
import { ArrowLeft, LockKeyhole, MapPin, Store } from 'lucide-react'
import { buildTasteFootprintEvents, type TasteFootprintEvent } from '../services/tasteFootprint'
import { diningModeLabel, type RestaurantSummary, type UserProfile, type Visit } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { SyncedImage } from './SyncedImage'
import { PersistentPageNavigation } from './TasteMapHybridShared'
import { TasteMapActivityCardFrame, TasteMapActivityRatingBadge } from './TasteMapDiscoveryShared'
import { TasteMapActivityMedia } from './TasteMapActivityMedia'
import { visitActivityMedia } from './activityMedia'
import { UserAvatar } from './UserAvatar'
import { FoodCategoryVisual } from '../visuals/FoodCategoryVisual'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import './tasteFootprints.css'

interface FootprintProps {
  restaurants: RestaurantSummary[]
  visits?: Visit[]
  user?: UserProfile
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
}

export function TasteFootprintPreview(props: FootprintProps) {
  const events = buildTasteFootprintEvents(props.restaurants, props.visits)
  return <section className="profile-dashboard__section profile-taste-footprints-section">
    <header className="profile-dashboard__section-heading"><h2>味觉足迹</h2><span>{events.length} 条</span></header>
    <FootprintCards events={events} onSelectRestaurant={props.onSelectRestaurant} user={props.user} />
  </section>
}

export function TasteFootprints({ onBack, ...props }: FootprintProps & { onBack?: () => void }) {
  const events = buildTasteFootprintEvents(props.restaurants, props.visits)
  useEffect(() => {
    if (onBack) window.requestAnimationFrame(() => window.scrollTo({ top: 0, left: 0, behavior: 'auto' }))
  }, [onBack])
  return <section className={`taste-footprints${onBack ? ' taste-footprints--page' : ''}`}>
    {onBack ? <PersistentPageNavigation as="header" className="taste-footprints__page-header">
      <button aria-label="返回个人主页" onClick={onBack} type="button"><ArrowLeft size={19} /></button>
      <h1>味觉足迹</h1><strong>{events.length} 条</strong>
    </PersistentPageNavigation> : <header><h2>味觉足迹</h2><strong>{events.length} 条</strong></header>}
    <FootprintCards events={events} onSelectRestaurant={props.onSelectRestaurant} user={props.user} />
  </section>
}

function FootprintCards({ events, onSelectRestaurant, user }: {
  events: TasteFootprintEvent[]
  onSelectRestaurant: FootprintProps['onSelectRestaurant']
  user?: UserProfile
}) {
  return events.length ? <div className="taste-footprint-cards">
    {events.map((event) => <div className="taste-footprint-cards__item" data-footprint-id={event.id} key={event.id}>
      <TasteFootprintRecordCard event={event} onSelectRestaurant={onSelectRestaurant} user={user} />
    </div>)}
  </div> : <div className="social-empty"><MapPin size={22} /><strong>还没有味觉足迹</strong><p>记录到访或收藏想去的餐厅后，这里会按时间整理你的味觉记忆。</p></div>
}

/** Shared activity anatomy; private owner history has no invented public social counters. */
function TasteFootprintRecordCard({ event, onSelectRestaurant, user }: {
  event: TasteFootprintEvent
  onSelectRestaurant: FootprintProps['onSelectRestaurant']
  user?: UserProfile
}) {
  const { restaurant, visit } = event
  const onOpen = () => onSelectRestaurant(restaurant)
  const visitPhotos = visit ? visitActivityMedia(visit.photos, visit.photoIds) : []
  const dishPhotos = visit?.dishes.filter((dish) => dish.imageData || dish.photoId)
    .map((dish) => ({ source: dish.imageData || '', photoId: dish.photoId || null })) ?? []
  const exactPhotos = visitActivityMedia([...visitPhotos, ...dishPhotos].map((photo) => photo.source), [...visitPhotos, ...dishPhotos].map((photo) => photo.photoId))
  const photos = exactPhotos.length ? exactPhotos : visitActivityMedia([restaurant.markerImageData || ''], [restaurant.markerPhotoId || null])
  const fallback = <FoodCategoryVisual id={resolveFoodCategoryVisualID(restaurant)} label={`${restaurant.name} 餐饮分类图示`} />
  const images = photos.length ? photos.map((photo, index) => <SyncedImage key={photo.photoId || photo.source} alt={`${restaurant.name} 图片 ${index + 1}`} source={photo.source} photoId={photo.photoId} fallback={fallback} loading="lazy" />) : [fallback]
  const visibility = visit ? visit.visibility === 'public' ? '公开' : visit.visibility === 'friends' ? '好友可见' : '仅自己' : null
  return <TasteMapActivityCardFrame variant="activity" onOpen={onOpen}
    header={<><div className="tm-activity-card__user">
      {user ? <UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /> : null}
      <span><strong>{user?.nickname || '我的记录'}</strong><small>{event.kind === 'visit' ? '记录去过' : '加入想去'} · {formatVisitDateTime(event.eventAt)}</small></span>
    </div>{visibility ? <small className="taste-footprint-visibility">{visibility === '仅自己' ? <LockKeyhole size={12} /> : null}{visibility}</small> : null}</>}
    restaurant={<div className="tm-activity-card__restaurant-identity"><span className="tm-activity-card__restaurant-copy"><strong>{restaurant.name}</strong><small><MapPin size={12} /><span>{[restaurant.city, restaurant.address].filter(Boolean).join(' · ') || '位置未记录'}</span><button aria-label="查看餐厅" title="查看餐厅信息" className="tm-activity-card__restaurant-detail-icon" onClick={onOpen} type="button"><Store size={13} /></button></small></span></div>}
    activityRating={visit ? <TasteMapActivityRatingBadge rating={visit.rating} /> : undefined}
    mediaCount={images.length}
    media={<TasteMapActivityMedia images={images} name={restaurant.name} onOpen={onOpen} />}
    body={<>{visit?.note ? <p>“{visit.note}”</p> : null}{visit ? <small>{diningModeLabel(visit.diningMode)}</small> : null}</>}
    restaurantActions={null}
  />
}
