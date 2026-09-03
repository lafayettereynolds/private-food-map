import type { CSSProperties, MouseEvent, ReactNode } from 'react'
import { scoreColor } from '../types/domain'
import './tasteMapDiscoveryShared.css'

export interface TasteMapPrimaryTab<Value extends string> {
  value: Value
  label: string
  icon?: ReactNode
  count?: number
}

export function TasteMapPrimaryTabBar<Value extends string>({
  ariaLabel,
  className,
  items,
  onChange,
  value,
}: {
  ariaLabel: string
  className?: string
  items: ReadonlyArray<TasteMapPrimaryTab<Value>>
  onChange: (value: Value) => void
  value: Value
}) {
  return <nav
    aria-label={ariaLabel}
    className={`tm-primary-tab-bar${className ? ` ${className}` : ''}`}
    role="tablist"
    style={{ '--tm-tab-count': items.length } as CSSProperties}
  >
    {items.map((item) => <button
      aria-label={item.count === undefined ? item.label : `${item.label}，${item.count} 家餐厅`}
      aria-selected={item.value === value}
      className={item.value === value ? 'is-active' : ''}
      key={item.value}
      onClick={() => onChange(item.value)}
      role="tab"
      type="button"
    >{item.icon ? <span aria-hidden="true" className="tm-primary-tab-bar__icon">{item.icon}</span> : null}<span className="tm-primary-tab-bar__label">{item.label}</span>{item.count === undefined ? null : <span aria-hidden="true" className="tm-primary-tab-bar__count">{item.count.toLocaleString('zh-CN')}</span>}</button>)}
  </nav>
}

export function TasteMapFilterBar({ children, ariaLabel = '筛选' }: { children: ReactNode; ariaLabel?: string }) {
  return <div aria-label={ariaLabel} className="tm-shared-filter-bar" role="toolbar">{children}</div>
}

/**
 * The author's concrete Visit rating. Taste Map stores this on a five-point
 * scale; color selection uses the canonical ten-point score palette.
 */
export function TasteMapActivityRatingBadge({ rating, prefix = '本次到访' }: { rating: number | null; prefix?: string }) {
  const color = scoreColor(rating == null ? null : rating * 2)
  return <span
    aria-label={rating == null ? `${prefix}未评分` : `${prefix}评分 ${rating.toFixed(1)}`}
    className={`tm-activity-rating-badge${rating == null ? ' is-unrated' : ''}`}
    role="img"
    style={{ '--tm-activity-rating-color': color } as CSSProperties}
    title={rating == null ? `${prefix}未评分` : `${prefix} ${rating.toFixed(1)}`}
  ><strong aria-hidden="true">{rating == null ? '—' : rating.toFixed(1)}</strong></span>
}

export function TasteMapDiscoveryScaffold<Value extends string>({
  children,
  className,
  description,
  filterBar,
  onTabChange,
  tab,
  tabs,
}: {
  children: ReactNode
  className?: string
  description: string
  filterBar: ReactNode
  onTabChange: (value: Value) => void
  tab: Value
  tabs: ReadonlyArray<TasteMapPrimaryTab<Value>>
}) {
  return <section className={`tm-discovery-page${className ? ` ${className}` : ''}`} data-product-contract="discovery-page">
    <header className="tm-discovery-page__header" data-discovery-region="header">
      <h1>发现</h1>
      <p>{description}</p>
    </header>
    <TasteMapPrimaryTabBar ariaLabel="发现分类" items={tabs} onChange={onTabChange} value={tab} />
    <div className="tm-discovery-page__filters" data-discovery-region="filter-bar">{filterBar}</div>
    <div className="tm-discovery-page__content">{children}</div>
  </section>
}

/**
 * Canonical semantic frame for Discovery/Community activity content.
 * Data projection and action effects stay with each platform adapter; the
 * product hierarchy and visual geometry live here once for Browser/Capacitor.
 */
export function TasteMapActivityCardFrame({
  activityRating,
  body,
  header,
  media,
  onOpen,
  restaurant,
  restaurantActions,
  socialActions,
  variant,
}: {
  activityRating?: ReactNode
  body?: ReactNode
  header?: ReactNode
  media?: ReactNode
  onOpen?: () => void
  restaurant: ReactNode
  restaurantActions: ReactNode
  socialActions?: ReactNode
  variant: 'recommendation' | 'activity'
}) {
  const open = (event: MouseEvent<HTMLElement>) => {
    if (!onOpen || event.defaultPrevented) return
    if ((event.target as HTMLElement).closest('button, a, input, select, textarea, [role="button"]')) return
    onOpen()
  }
  return <article
    className={`tm-activity-card is-${variant}`}
    data-product-contract="activity-card"
    onClick={open}
  >
    {header ? <header data-activity-region="author-time-visibility">{header}</header> : null}
    {variant === 'activity' && activityRating ? <div className="tm-activity-card__restaurant-row">
      <div className="tm-activity-card__restaurant" data-activity-region="restaurant-name-address-context">{restaurant}</div>
      <div className="tm-activity-card__rating" data-activity-region="visit-rating">{activityRating}</div>
    </div> : <>
      <div className="tm-activity-card__restaurant" data-activity-region="restaurant-name-address-context">{restaurant}</div>
      {activityRating ? <div className="tm-activity-card__rating" data-activity-region="visit-rating">{activityRating}</div> : null}
    </>}
    {media ? <div className="tm-activity-card__media" data-activity-region="restaurant-image">{media}</div> : null}
    {body ? <div className="tm-activity-card__body" data-activity-region={variant === 'recommendation' ? 'recommendation-reason' : 'activity-context'}>{body}</div> : null}
    <footer>
      {socialActions ? <div className="tm-activity-card__social" data-activity-region="like-comment-more-share">{socialActions}</div> : null}
      <div className="tm-activity-card__restaurant-actions" data-activity-region="restaurant-actions">{restaurantActions}</div>
    </footer>
  </article>
}
