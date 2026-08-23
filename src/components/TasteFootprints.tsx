import { MapPin, Star, Store, Truck } from 'lucide-react'
import { diningModeLabel, type RestaurantSummary, type UserProfile } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { RestaurantAvatar } from './RestaurantAvatar'
import { SyncedImage } from './SyncedImage'
import { UserAvatar } from './UserAvatar'

export function TasteFootprints({
  restaurants,
  onSelectRestaurant,
  user,
}: {
  restaurants: RestaurantSummary[]
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
  user?: UserProfile
}) {
  const footprints = restaurants
    .flatMap((restaurant) => restaurant.visits.map((visit) => ({ restaurant, visit })))
    .sort((a, b) => b.visit.visitedAt.localeCompare(a.visit.visitedAt))

  return (
    <section className="taste-footprints">
      <header>
        <div><span className="eyebrow">TASTE FOOTPRINTS</span><h2>味觉足迹</h2></div>
        <strong>{footprints.length} 条</strong>
      </header>
      {footprints.length ? (
        <div className="footprint-feed">
          {footprints.map(({ restaurant, visit }) => {
            const dishPhotos = visit.dishes
              .filter((dish) => dish.imageData || dish.photoId)
              .map((dish) => ({ source: dish.imageData, photoId: dish.photoId, alt: dish.name || '菜品照片' }))
            const photos = visit.photos.length
              ? visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index], alt: `${restaurant.name} 到访照片 ${index + 1}` }))
              : dishPhotos
            return <article className="footprint-card" key={visit.id}>
              <span className="footprint-author-avatar">
                {user ? <UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /> : <RestaurantAvatar restaurant={restaurant} />}
              </span>
              <div className="footprint-card__content">
                <header className="footprint-card__author"><span><strong>{user?.nickname || '我的味觉记录'}</strong><time>{formatVisitDateTime(visit.visitedAt)}</time></span>{visit.rating ? <b><Star fill="currentColor" size={12} /> {visit.rating} 星</b> : null}</header>
                <button className="footprint-card__restaurant" onClick={() => onSelectRestaurant(restaurant)} type="button"><strong>{restaurant.name}</strong><span>{restaurant.city}</span></button>
                {visit.note ? <p>{visit.note}</p> : null}
                {photos.length ? <div className={`footprint-photos count-${Math.min(photos.length, 3)}`}>{photos.slice(0, 9).map((photo, index) => <SyncedImage alt={photo.alt} key={`${visit.id}-${index}`} loading="lazy" photoId={photo.photoId} source={photo.source} />)}</div> : null}
                {visit.dishes.some((dish) => dish.name) ? <div className="footprint-dishes">{visit.dishes.filter((dish) => dish.name).slice(0, 4).map((dish) => <span key={dish.id}>{dish.name}{dish.rating ? ` · ${dish.rating} 星` : ''}</span>)}</div> : null}
                <footer>
                  <span className="footprint-mode">{visit.diningMode === 'takeout' ? <Truck size={12} /> : <Store size={12} />}{diningModeLabel(visit.diningMode)}</span>
                  <span className="footprint-location"><MapPin size={12} />{restaurant.address || restaurant.city}</span>
                </footer>
              </div>
            </article>
          })}
        </div>
      ) : (
        <div className="social-empty"><MapPin size={22} /><strong>还没有味觉足迹</strong><p>记录到访后，这里会按时间整理你的味觉记忆。</p></div>
      )}
    </section>
  )
}
