import type { ChangeEventHandler } from 'react'
import { Clock3, Images, MapPin, Navigation, Phone } from 'lucide-react'
import { mapService } from '../services/mapService'
import { STATUS_META, type RestaurantSummary } from '../types/domain'
import { RestaurantAvatar } from './RestaurantAvatar'
import { RestaurantSocialStatsPanel, type PersonalRatingOverride } from './RestaurantSocialStatsPanel'
import { SyncedImage } from './SyncedImage'
import { RestaurantQuickActions } from './RestaurantQuickActions'

export interface RestaurantSummaryActionSet {
  onMarkVisited?: () => void
  onAddToWant?: () => void
  onToggleRoulette?: () => void
  visitedActive?: boolean
  wantActive?: boolean
  isInRoulette?: boolean
}

export interface RestaurantSummarySectionProps {
  restaurant: RestaurantSummary
  historyRestaurants?: RestaurantSummary[]
  additionalUserPhotos?: Array<{ source: string; photoId?: string | null }>
  actions?: RestaurantSummaryActionSet
  addressEditor?: {
    value: string
    onChange: ChangeEventHandler<HTMLInputElement>
    required?: boolean
  }
  personalRatingOverride?: PersonalRatingOverride
  remoteStatsEnabled?: boolean
  referencePrice?: number | null
  className?: string
}

/**
 * The shared restaurant identity and evidence block used before record forms.
 * Keep restaurant facts here so create, edit and detail surfaces do not drift.
 */
export function RestaurantSummarySection({
  restaurant,
  historyRestaurants = [],
  additionalUserPhotos = [],
  actions,
  addressEditor,
  personalRatingOverride,
  remoteStatsEnabled = true,
  referencePrice,
  className = '',
}: RestaurantSummarySectionProps) {
  const matchingHistoryRestaurants = historyRestaurants.filter((candidate) => sameRestaurant(candidate, restaurant))
  const detailRestaurant = matchingHistoryRestaurants
    .reduce((merged, candidate) => mergeRestaurantDetails(merged, candidate), restaurant)
  const displayPrice = referencePrice ?? detailRestaurant.averagePricePerPerson ?? detailRestaurant.pricePerPerson
  const navigationUrl = mapService.directionsUrl(detailRestaurant)
  const allUserPhotos = uniqueUserPhotos([
    ...additionalUserPhotos,
    ...[restaurant, ...matchingHistoryRestaurants].flatMap((candidate) => candidate.visits.flatMap((visit) => visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index] })))),
  ])
  const userPhotos = allUserPhotos.slice(0, 4)

  return <section className={`restaurant-record-summary${className ? ` ${className}` : ''}`} data-record-section="restaurant-summary">
    <section className="restaurant-detail-header" aria-label="餐厅信息摘要" data-summary-module="restaurant-facts">
      <div className="restaurant-detail-gallery" aria-label="餐厅图片">
        <div className="restaurant-detail-gallery__merchant">
          {detailRestaurant.merchantImageUrl
            ? <img alt={`${detailRestaurant.name} 商家图片`} loading="lazy" src={detailRestaurant.merchantImageUrl} />
            : <span className="restaurant-detail-gallery__placeholder"><RestaurantAvatar restaurant={detailRestaurant} size="large" /></span>}
          <em>商家图片</em>
        </div>
      </div>

      <div className="map-card__title-row">
        <div>
          <span>{detailRestaurant.city} · {STATUS_META[restaurant.status].label}</span>
          <h2>{detailRestaurant.name}</h2>
        </div>
        {actions ? <RestaurantQuickActions
          className="restaurant-title-actions"
          onRecordVisit={actions.onMarkVisited}
          onToggleWant={actions.onAddToWant}
          onToggleWheel={actions.onToggleRoulette}
          restaurantName={detailRestaurant.name}
          visitedActive={actions.visitedActive}
          wantActive={actions.wantActive}
          wheelActive={actions.isInRoulette}
        /> : null}
      </div>

      {addressEditor
        ? <label className="restaurant-record-summary__address-editor"><MapPin size={14} /><input aria-label="餐厅地址" onChange={addressEditor.onChange} required={addressEditor.required} value={addressEditor.value} /></label>
        : <p className="map-card__address"><MapPin size={14} /> {detailRestaurant.address}</p>}

      <div className="restaurant-detail-reference" data-summary-field="reference-price">
        <span>{typeof displayPrice === 'number' && Number.isFinite(displayPrice) ? `参考人均约 ¥${Math.round(displayPrice)}` : '参考人均待补充'}</span>
      </div>

      <div className="restaurant-contact-actions">
        {detailRestaurant.phone
          ? <a href={`tel:${detailRestaurant.phone.replace(/\s+/g, '')}`}><Phone size={14} /><span><small>电话</small><strong>{detailRestaurant.phone}</strong></span></a>
          : <span aria-label="暂无联系电话" className="is-unavailable"><Phone size={14} /><span><small>电话</small><strong>暂无电话</strong></span></span>}
        {detailRestaurant.openingHours
          ? <span><Clock3 size={14} /><span><small>营业时间</small><strong>{detailRestaurant.openingHours}</strong></span></span>
          : <span aria-label="暂无营业时间" className="is-unavailable"><Clock3 size={14} /><span><small>营业时间</small><strong>暂无营业时间</strong></span></span>}
        <a href={navigationUrl} rel="noreferrer" target="_blank"><Navigation size={14} /><span><small>路线</small><strong>到这里去</strong></span></a>
      </div>
    </section>

    <RestaurantSocialStatsPanel
      amapPoiId={restaurant.amapPoiId}
      historyRestaurants={historyRestaurants}
      personalRatingOverride={personalRatingOverride}
      remoteStatsEnabled={remoteStatsEnabled}
      restaurant={restaurant}
    />

    <section className="restaurant-user-photos" aria-label="用户实拍" data-summary-module="user-photos">
      <header><strong><Images size={14} /> 用户实拍</strong><span>{allUserPhotos.length ? `${allUserPhotos.length} 张` : '暂无实拍'}</span></header>
      {userPhotos.length
        ? <div>{userPhotos.map((photo, index) => <span key={`${photo.photoId ?? photo.source}-${index}`}><SyncedImage alt={`${restaurant.name} 用户实拍 ${index + 1}`} loading="lazy" photoId={photo.photoId} source={photo.source} /></span>)}</div>
        : <p>暂时还没有用户分享的照片。</p>}
    </section>
  </section>
}

/**
 * Backwards-compatible export for older call sites. New form and detail
 * surfaces should use RestaurantSummarySection so the shared topology is
 * explicit in code reviews and tests.
 */
export const RestaurantRecordSummary = RestaurantSummarySection

function mergeRestaurantDetails(restaurant: RestaurantSummary, match?: RestaurantSummary): RestaurantSummary {
  if (!match) return restaurant
  return {
    ...restaurant,
    address: restaurant.address || match.address,
    city: restaurant.city || match.city,
    phone: restaurant.phone || match.phone || null,
    openingHours: restaurant.openingHours || match.openingHours || null,
    merchantImageUrl: restaurant.merchantImageUrl || match.merchantImageUrl,
    pricePerPerson: restaurant.pricePerPerson ?? match.pricePerPerson,
    averagePricePerPerson: restaurant.averagePricePerPerson ?? match.averagePricePerPerson,
  }
}

function sameRestaurant(left: RestaurantSummary, right: RestaurantSummary) {
  if (left.id === right.id) return true
  if (left.amapPoiId && right.amapPoiId && left.amapPoiId === right.amapPoiId) return true
  return normalizeRestaurantIdentity(left.name) === normalizeRestaurantIdentity(right.name)
    && normalizeRestaurantIdentity(left.address) === normalizeRestaurantIdentity(right.address)
}

function normalizeRestaurantIdentity(value: string) {
  return value.toLocaleLowerCase('zh-CN').replace(/[\s·•・()（）\-—_]/g, '')
}

function uniqueUserPhotos(photos: Array<{ source: string; photoId?: string | null }>) {
  const seen = new Set<string>()
  return photos.filter((photo) => {
    const key = photo.photoId || photo.source
    if (!key || seen.has(key)) return false
    seen.add(key)
    return true
  })
}
