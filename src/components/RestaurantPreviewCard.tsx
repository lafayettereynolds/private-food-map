import { CalendarClock, Clock3, Edit3, MapPin, Navigation, Plus, Star, Trash2, Users, WalletCards, X } from 'lucide-react'
import { RestaurantAvatar } from './RestaurantAvatar'
import { formatAverageQueueDuration, queueDurationLabel, scoreColor, starToTenScore, STATUS_META, type RestaurantSummary } from '../types/domain'
import { formatVisitDateTime } from '../utils/date'

interface RestaurantPreviewCardProps {
  restaurant: RestaurantSummary
  onClose: () => void
  onEdit: () => void
  onDelete: () => void
  onAddVisit: () => void
  onSaveRecommendation: () => void
}

export function RestaurantPreviewCard({
  restaurant,
  onClose,
  onEdit,
  onDelete,
  onAddVisit,
  onSaveRecommendation,
}: RestaurantPreviewCardProps) {
  const navigationUrl = createNavigationUrl(restaurant)
  return (
    <article className="map-card">
      <button className="map-card__close" aria-label="关闭餐厅卡片" onClick={onClose} type="button"><X size={16} /></button>
      <div className="map-card__title-row">
        <RestaurantAvatar restaurant={restaurant} size="large" />
        <div>
          <span>{restaurant.city} · {STATUS_META[restaurant.status].label}</span>
          <h2>{restaurant.name}</h2>
          {restaurant.scoreOutOfTen !== null ? (
            <p className="map-card__rating" style={{ color: scoreColor(restaurant.scoreOutOfTen) }}><Star fill="currentColor" size={13} /> {restaurant.scoreOutOfTen.toFixed(1)} / 10</p>
          ) : <p className="map-card__rating">{restaurant.isRecommendation ? '为你推荐 · 尚未去过' : '想去清单'}</p>}
        </div>
      </div>
      <p className="map-card__address"><MapPin size={14} /> {restaurant.address}</p>
      <div className="map-card__meta">
        <span><small>到访次数</small><strong>{restaurant.visitCount} 次</strong></span>
        <span><small>平均人均</small><strong>{restaurant.averagePricePerPerson !== null ? `¥${restaurant.averagePricePerPerson}` : '—'}</strong></span>
        <span><small>平均排队</small><strong>{formatAverageQueueDuration(restaurant.averageQueueMinutes)}</strong></span>
        <span><small>最近到访</small><strong>{restaurant.latestVisitDate ? new Date(restaurant.latestVisitDate).toLocaleDateString('zh-CN') : '—'}</strong></span>
      </div>
      {restaurant.tags.length ? <div className="tag-row">{restaurant.tags.slice(0, 5).map((tag) => <span key={tag}>{tag}</span>)}</div> : null}
      {restaurant.longTermNote ? <p className="map-card__note">{restaurant.longTermNote}</p> : null}
      {restaurant.visits.length ? (
        <section className="visit-history-preview">
          <header><strong>到访历史</strong><span>{restaurant.visits.length} 条 · 可滚动查看</span></header>
          <div className="visit-history-scroll">
            {restaurant.visits.map((visit, index) => (
              <article className="visit-history-row" key={visit.id}>
                <div className="visit-history-row__top">
                  <strong>第 {restaurant.visits.length - index} 次</strong>
                  <time><CalendarClock size={12} /> {formatVisitDateTime(visit.visitedAt)}</time>
                </div>
                <div className="visit-history-row__details">
                  <span className={visit.rating ? 'has-rating' : ''}><Star fill={visit.rating ? 'currentColor' : 'none'} size={12} /> {visit.rating ? `${starToTenScore(visit.rating)?.toFixed(1)} 分` : '未评分'}</span>
                  <span><WalletCards size={12} /> {visit.totalPrice !== null ? `总价 ¥${visit.totalPrice}${visit.pricePerPerson !== null ? ` · ¥${visit.pricePerPerson}/人` : ''}` : '未记价格'}</span>
                  <span><Users size={12} /> {visit.partySize || Math.max(1, visit.companions.length + 1)} 人</span>
                  <span><Clock3 size={12} /> {queueDurationLabel(visit.queueDuration)}</span>
                </div>
                {visit.companions.length ? <p>饭搭子：{visit.companions.join('、')}</p> : null}
                {visit.note ? <blockquote className="visit-feeling">“{visit.note}”</blockquote> : null}
                {visit.photos.length ? (
                  <div className="visit-photos">
                    {visit.photos.map((photo, photoIndex) => <a href={photo} key={`${visit.id}-photo-${photoIndex}`} rel="noreferrer" target="_blank"><img alt={`第 ${restaurant.visits.length - index} 次到访照片 ${photoIndex + 1}`} src={photo} /></a>)}
                  </div>
                ) : null}
                {visit.dishes.length ? (
                  <div className="visit-dishes">
                    {visit.dishes.map((dish) => (
                      <span key={dish.id}>
                        {dish.imageData ? <img alt="" src={dish.imageData} /> : null}
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
        </section>
      ) : null}
      <div className="map-card__actions">
        <a className="navigation-button compact-button" href={navigationUrl} rel="noreferrer" target="_blank"><Navigation size={15} /> 到这里去</a>
        {restaurant.isRecommendation ? (
          <button className="primary-button compact-button" onClick={onSaveRecommendation} type="button"><Plus size={15} /> 加入想去</button>
        ) : (
          <>
            <button className="primary-button compact-button" onClick={onAddVisit} type="button"><Plus size={15} /> 记录到访</button>
            <button className="secondary-button" onClick={onEdit} type="button"><Edit3 size={15} /> 编辑</button>
            <button className="danger-ghost-button" onClick={onDelete} type="button"><Trash2 size={15} /> 删除</button>
          </>
        )}
      </div>
    </article>
  )
}

function createNavigationUrl(restaurant: RestaurantSummary) {
  const parameters = new URLSearchParams({
    from: '',
    to: `${restaurant.longitude},${restaurant.latitude},${restaurant.name}`,
    mode: 'car',
    policy: '0',
    src: 'taste-map',
    callnative: '1',
  })
  return `https://uri.amap.com/navigation?${parameters.toString()}`
}
