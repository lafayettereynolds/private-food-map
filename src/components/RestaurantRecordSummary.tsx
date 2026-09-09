import type { ChangeEventHandler, ReactNode } from 'react'
import { Clock3, MapPin, Navigation, Pencil, Phone } from 'lucide-react'
import { mapService } from '../services/mapService'
import { STATUS_META, type RestaurantSummary } from '../types/domain'
import { RestaurantContentImage } from './RestaurantContentImage'
import { visitActivityMedia } from './activityMedia'
import type { TasteMapImageDescriptor, TasteMapImageResolutionDTO } from '../platform/TasteMapPlatform'
import { RestaurantSocialStatsPanel, type PersonalRatingOverride } from './RestaurantSocialStatsPanel'
import { RestaurantUserPhotos } from './RestaurantUserPhotos'
import { RestaurantQuickActions } from './RestaurantQuickActions'
import type { RestaurantSocialStats } from '../types/restaurantStats'

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
  contentImage?: TasteMapImageDescriptor
  contentImageResolution?: TasteMapImageResolutionDTO
  actions?: RestaurantSummaryActionSet
  addressEditor?: {
    value: string
    onChange: ChangeEventHandler<HTMLInputElement>
    required?: boolean
  }
  personalRatingOverride?: PersonalRatingOverride
  remoteStatsEnabled?: boolean
  socialStats?: RestaurantSocialStats | null
  referencePrice?: number | null
  className?: string
  onEditAvatar?: () => void
  imageTrailingAction?: ReactNode
}

/**
 * The shared restaurant identity and evidence block used before record forms.
 * Keep restaurant facts here so create, edit and detail surfaces do not drift.
 */
export function RestaurantSummarySection({
  restaurant,
  historyRestaurants = [],
  additionalUserPhotos = [],
  contentImage,
  contentImageResolution,
  actions,
  addressEditor,
  personalRatingOverride,
  remoteStatsEnabled = true,
  socialStats,
  referencePrice,
  className = '',
  onEditAvatar,
  imageTrailingAction,
}: RestaurantSummarySectionProps) {
  const matchingHistoryRestaurants = historyRestaurants.filter((candidate) => sameRestaurant(candidate, restaurant))
  const detailRestaurant = matchingHistoryRestaurants
    .reduce((merged, candidate) => mergeRestaurantDetails(merged, candidate), restaurant)
  const displayPrice = referencePrice ?? detailRestaurant.averagePricePerPerson ?? detailRestaurant.pricePerPerson
  const navigationUrl = mapService.directionsUrl(detailRestaurant)
  const allUserPhotos = uniqueUserPhotos([
    ...additionalUserPhotos,
    ...[restaurant, ...matchingHistoryRestaurants].flatMap((candidate) => candidate.visits.filter((visit) => !visit.deletedAt).flatMap((visit) => [
      ...visitActivityMedia(visit.photos, visit.photoIds),
      ...visit.dishes.map((dish) => ({ source: dish.imageData || '', photoId: dish.photoId })),
    ])),
  ])
  return <section className={`restaurant-record-summary${className ? ` ${className}` : ''}`} data-record-section="restaurant-summary">
    <section className="restaurant-detail-header" aria-label="餐厅信息摘要" data-summary-module="restaurant-facts">
      <div className="restaurant-detail-gallery" aria-label="餐厅图片">
        <div className="restaurant-detail-gallery__merchant">
          {onEditAvatar ? <button aria-label="修改餐厅头像" className="restaurant-avatar-edit-button" onClick={onEditAvatar} type="button"><Pencil aria-hidden="true" size={17} /></button> : null}
          {imageTrailingAction}
          <RestaurantContentImage name={detailRestaurant.name} tags={detailRestaurant.tags} image={contentImage} resolution={contentImageResolution} photos={allUserPhotos} />
        </div>
      </div>

      <div className="map-card__title-row">
        <div>
          <span>{detailRestaurant.city || '暂无城市信息'} · {STATUS_META[restaurant.status].label}</span>
          <h2>{detailRestaurant.name || '暂无餐厅名称'}</h2>
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
        : <p className="map-card__address"><MapPin size={14} /> {detailRestaurant.address || '暂无地址'}</p>}

      <p className="restaurant-detail-categories" data-summary-field="categories">
        {detailRestaurant.tags.length ? `分类：${detailRestaurant.tags.join(' · ')}` : '暂无分类'}
      </p>

      <div className="restaurant-detail-reference" data-summary-field="reference-price">
        <span>{typeof displayPrice === 'number' && Number.isFinite(displayPrice) ? `参考人均约 ¥${Math.round(displayPrice)}` : '暂无参考人均'}</span>
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
      socialStats={socialStats}
    />

    <RestaurantUserPhotos restaurantID={restaurant.id} restaurantName={restaurant.name} photos={allUserPhotos} />
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
    websiteUrl: restaurant.websiteUrl || match.websiteUrl || null,
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
