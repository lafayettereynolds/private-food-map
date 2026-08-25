import { Bookmark, CalendarClock, CheckCircle2, ChevronDown, Clock3, Dices, Edit3, Images, MapPin, Navigation, Phone, Plus, Star, Store, Trash2, Truck, Users, WalletCards, X } from 'lucide-react'
import { RestaurantAvatar } from './RestaurantAvatar'
import { DINING_OCCASION_OPTIONS, diningModeLabel, formatAverageQueueDuration, queueDurationLabel, starToTenScore, STATUS_META, type RestaurantSummary, type Visit } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'
import { SyncedImage } from './SyncedImage'
import { RestaurantSocialStatsPanel } from './RestaurantSocialStatsPanel'
import { mapService } from '../services/mapService'

interface RestaurantPreviewCardProps {
  restaurant: RestaurantSummary
  historyRestaurants?: RestaurantSummary[]
  additionalUserPhotos?: Array<{ source: string; photoId?: string | null }>
  onClose: () => void
  onEdit: () => void
  onDelete: () => void
  onAddVisit: () => void
  onEditVisit: (visit: Visit) => void
  onSaveRecommendation: () => void
  onAddToRoulette: () => void
  isInRoulette: boolean
  onAddToWant?: () => void
}

export function RestaurantPreviewCard({
  restaurant,
  historyRestaurants = [],
  additionalUserPhotos = [],
  onClose,
  onEdit,
  onDelete,
  onAddVisit,
  onEditVisit,
  onSaveRecommendation,
  onAddToRoulette,
  isInRoulette,
  onAddToWant,
}: RestaurantPreviewCardProps) {
  const navigationUrl = mapService.directionsUrl(restaurant)
  const recordedSpend = restaurant.visits.map((visit) => visit.myActualSpend ?? visit.pricePerPerson).filter((value): value is number => value !== null)
  const averageActualSpend = recordedSpend.length ? Math.round(recordedSpend.reduce((sum, value) => sum + value, 0) / recordedSpend.length) : null
  const stableCover = restaurant.merchantImageUrl
  const allUserPhotos = uniqueUserPhotos([
    ...additionalUserPhotos,
    ...restaurant.visits.flatMap((visit) => visit.photos.map((source, index) => ({ source, photoId: visit.photoIds[index] }))),
  ])
  const userPhotos = allUserPhotos.slice(0, 4)
  const overviewFacets = buildOverviewFacets(restaurant.visits)
  return (
    <article className="map-card">
      <button className="map-card__close" aria-label="关闭餐厅卡片" onClick={onClose} type="button"><X size={16} /></button>
      <section className="restaurant-detail-header" aria-label="餐厅信息">
        <div className="restaurant-detail-gallery" aria-label="餐厅与用户图片">
          <div className="restaurant-detail-gallery__merchant">
            {stableCover ? <img alt={`${restaurant.name} 商家图片`} loading="lazy" src={stableCover} /> : <span className="restaurant-detail-gallery__placeholder"><RestaurantAvatar restaurant={restaurant} size="large" /></span>}
            <em>商家图片</em>
          </div>
        </div>
        <div className="map-card__title-row">
          <div>
            <span>{restaurant.city} · {STATUS_META[restaurant.status].label}</span>
            <h2>{restaurant.name}</h2>
          </div>
          <div className="restaurant-title-actions" aria-label="餐厅快捷操作">
            <button aria-label="记录去过" onClick={onAddVisit} title="去过" type="button"><Plus size={16} /></button>
            <button aria-label="加入想吃" onClick={onAddToWant ?? onSaveRecommendation} title="想吃" type="button"><Bookmark size={16} /></button>
            <button aria-label={isInRoulette ? '移出抽签' : '加入抽签'} aria-pressed={isInRoulette} className={isInRoulette ? 'is-selected' : ''} onClick={onAddToRoulette} title={isInRoulette ? '已加入抽签' : '抽签'} type="button">{isInRoulette ? <CheckCircle2 size={16} /> : <Dices size={16} />}</button>
          </div>
        </div>
        <p className="map-card__address"><MapPin size={14} /> {restaurant.address}</p>
        {restaurant.averagePricePerPerson !== null ? <div className="restaurant-detail-reference"><span>参考人均约 ¥{restaurant.averagePricePerPerson}</span></div> : null}
        <div className="restaurant-contact-actions">
          {restaurant.phone ? <a href={`tel:${restaurant.phone.replace(/\s+/g, '')}`}><Phone size={14} /><span><small>电话</small><strong>{restaurant.phone}</strong></span></a> : null}
          {restaurant.openingHours ? <span><Clock3 size={14} /><span><small>营业时间</small><strong>{restaurant.openingHours}</strong></span></span> : null}
          <a href={navigationUrl} rel="noreferrer" target="_blank"><Navigation size={14} /><span><small>路线</small><strong>到这里去</strong></span></a>
        </div>
      </section>
      <RestaurantSocialStatsPanel amapPoiId={restaurant.amapPoiId} historyRestaurants={historyRestaurants} restaurant={restaurant} />
      <section className="restaurant-user-photos" aria-label="用户实拍">
        <header><strong><Images size={14} /> 用户实拍</strong><span>{allUserPhotos.length ? `${allUserPhotos.length} 张` : '暂无实拍'}</span></header>
        {userPhotos.length ? <div>{userPhotos.map((photo, index) => <span key={`${photo.photoId ?? photo.source}-${index}`}><SyncedImage alt={`${restaurant.name} 用户实拍 ${index + 1}`} loading="lazy" photoId={photo.photoId} source={photo.source} /></span>)}</div> : <p>记录到访并上传照片后，会显示在这里。</p>}
      </section>
      {restaurant.status === 'visited' ? <section className="restaurant-visit-overview" aria-label="我的到访概览">
        <header><strong>我的到访概览</strong></header>
        <div className="restaurant-visit-overview__metrics">
          <span><small>到访次数</small><strong>{restaurant.visitCount} 次</strong></span>
          <span><small>平均消费</small><strong>{averageActualSpend !== null ? `¥${averageActualSpend}` : '—'}</strong></span>
          <span><small>平均排队</small><strong>{restaurant.averageQueueMinutes !== null ? formatAverageQueueDuration(restaurant.averageQueueMinutes) : '—'}</strong></span>
          <span><small>最近到访</small><strong>{restaurant.latestVisitDate ? new Date(restaurant.latestVisitDate).toLocaleDateString('zh-CN') : '—'}</strong></span>
        </div>
        {overviewFacets.length ? <div className="restaurant-visit-overview__facets">{overviewFacets.map((facet) => <section key={facet.label}><small>{facet.label}</small><div>{facet.values.map((value) => <span key={`${facet.label}-${value}`}>{value}</span>)}</div></section>)}</div> : <p className="restaurant-visit-overview__empty">继续记录适合场景、服务和环境后，这里会形成你的餐厅画像。</p>}
      </section> : null}
      {restaurant.longTermNote ? <p className="map-card__note restaurant-summary-note">{restaurant.longTermNote}</p> : null}
      {restaurant.visits.length ? (
        <details className="visit-history-preview" open>
          <summary><strong>到访历史</strong><span>{restaurant.visits.length} 条 · 展开查看 <ChevronDown size={14} /></span></summary>
          <div className="visit-history-scroll">
            {restaurant.visits.map((visit, index) => (
              <article className="visit-history-row" key={visit.id}>
                <div className="visit-history-row__top">
                  <strong>第 {restaurant.visits.length - index} 次</strong>
                  <div className="visit-history-row__top-actions">
                    <time><CalendarClock size={12} /> {formatVisitDateTime(visit.visitedAt)}</time>
                    <button aria-label={`编辑第 ${restaurant.visits.length - index} 次到访`} onClick={() => onEditVisit(visit)} type="button"><Edit3 size={11} /> 编辑</button>
                  </div>
                </div>
                <div className="visit-history-row__details">
                  <span className="visit-mode-chip">{(visit.diningMode ?? 'dine_in') === 'dine_in' ? <Store size={12} /> : <Truck size={12} />} {diningModeLabel(visit.diningMode)}</span>
                  <span className={visit.rating ? 'has-rating' : ''}><Star fill={visit.rating ? 'currentColor' : 'none'} size={12} /> {visit.rating ? `${starToTenScore(visit.rating)?.toFixed(1)} 分` : '未评分'}</span>
                  <span><WalletCards size={12} /> {visit.paymentMode === 'separate' && visit.myActualSpend !== null ? `我的消费 ¥${visit.myActualSpend}` : visit.totalPrice !== null ? `总价 ¥${visit.totalPrice}${visit.pricePerPerson !== null ? ` · ¥${visit.pricePerPerson}/人` : ''}` : '未记价格'}</span>
                  <span><Users size={12} /> {visit.partySize || Math.max(1, visit.companions.length + 1)} 人</span>
                  <span><Clock3 size={12} /> {queueDurationLabel(visit.queueDuration)}</span>
                </div>
                {visit.specialNotes ? <p className="visit-extra-summary">{visit.specialNotes}</p> : null}
                {[...(visit.valueTags ?? []), ...(visit.serviceTags ?? []), ...(visit.environmentTags ?? [])].length ? <div className="visit-experience-tags">{[...(visit.valueTags ?? []), ...(visit.serviceTags ?? []), ...(visit.environmentTags ?? [])].map((tag, tagIndex) => <span key={`${visit.id}-${tag}-${tagIndex}`}>{tag}</span>)}</div> : null}
                {visit.companions.length ? <p>饭搭子：{visit.companions.join('、')}</p> : null}
                {visit.note ? <blockquote className="visit-feeling">“{visit.note}”</blockquote> : null}
                {visit.photos.length ? (
                  <div className="visit-photos">
                    {visit.photos.map((photo, photoIndex) => <span key={`${visit.id}-photo-${photoIndex}`}><SyncedImage alt={`第 ${restaurant.visits.length - index} 次到访照片 ${photoIndex + 1}`} loading="lazy" photoId={visit.photoIds[photoIndex]} source={photo} /></span>)}
                  </div>
                ) : null}
                {visit.dishes.length ? (
                  <div className="visit-dishes">
                    {visit.dishes.map((dish) => (
                      <span key={dish.id}>
                        {dish.imageData || dish.photoId ? <SyncedImage alt="" loading="lazy" photoId={dish.photoId} source={dish.imageData} /> : null}
                        <b>{dish.name || '未命名菜品'}</b>
                        {dish.taste ? <em>{dish.taste}</em> : null}
                        {dish.rating !== null ? <small className="dish-rating-summary"><Star fill="currentColor" size={8} />{dish.rating}</small> : null}
                        {dish.price !== null ? <small>¥{dish.price}</small> : null}
                      </span>
                    ))}
                  </div>
                ) : null}
              </article>
            ))}
          </div>
        </details>
      ) : null}
      <div className="map-card__actions">
        {!restaurant.isRecommendation ? <><button className="secondary-button" onClick={onEdit} type="button"><Edit3 size={15} /> 编辑</button><button className="danger-ghost-button" onClick={onDelete} type="button"><Trash2 size={15} /> 删除</button></> : null}
      </div>
    </article>
  )
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

function buildOverviewFacets(visits: Visit[]) {
  const occasionLabels = new Map(DINING_OCCASION_OPTIONS.map((option) => [option.value, option.label]))
  const diningDurationLabels: Record<NonNullable<Visit['diningDuration']>, string> = {
    under15: '15 分钟以内', under30: '30 分钟以内', under45: '45 分钟以内', under60: '1 小时以内', under90: '1.5 小时以内', under120: '2 小时以内', over120: '超过 2 小时',
  }
  const noiseLabels: Record<NonNullable<Visit['noiseLevel']>, string> = { quiet: '安静', normal: '正常', loud: '较吵', very_loud: '很吵' }
  const portionLabels: Record<NonNullable<Visit['portionLevel']>, string> = { small: '偏少', normal: '正常', generous: '很足' }
  const transportLabels: Record<NonNullable<Visit['transportConvenience']>, string> = { very_convenient: '很方便', convenient: '比较方便', normal: '一般', inconvenient: '不方便' }
  const occasions = visits.flatMap((visit) => {
    const values = visit.diningOccasions?.length ? visit.diningOccasions : visit.diningOccasion ? [visit.diningOccasion] : []
    return values.map((value) => value === 'other' && visit.diningOccasionText ? visit.diningOccasionText : occasionLabels.get(value) ?? value)
  })
  return [
    { label: '适合场景', values: topValues(occasions) },
    { label: '服务', values: topValues(visits.flatMap((visit) => visit.serviceTags ?? [])) },
    { label: '环境', values: topValues(visits.flatMap((visit) => visit.environmentTags ?? [])) },
    { label: '性价比', values: topValues(visits.flatMap((visit) => visit.valueTags ?? [])) },
    { label: '上餐时长', values: topValues(visits.flatMap((visit) => visit.diningDuration ? [diningDurationLabels[visit.diningDuration]] : []), 1) },
    { label: '菜量', values: topValues(visits.flatMap((visit) => visit.portionLevel ? [portionLabels[visit.portionLevel]] : []), 1) },
    { label: '用餐环境', values: topValues(visits.flatMap((visit) => visit.noiseLevel ? [noiseLabels[visit.noiseLevel]] : []), 1) },
    { label: '交通', values: topValues(visits.flatMap((visit) => visit.transportConvenience ? [transportLabels[visit.transportConvenience]] : []), 1) },
  ].filter((facet) => facet.values.length)
}

function topValues(values: string[], limit = 3) {
  const counts = new Map<string, number>()
  values.filter(Boolean).forEach((value) => counts.set(value, (counts.get(value) ?? 0) + 1))
  return [...counts.entries()].sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0], 'zh-CN')).slice(0, limit).map(([value]) => value)
}
