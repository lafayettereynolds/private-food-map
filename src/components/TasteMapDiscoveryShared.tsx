import { useId, useState, type CSSProperties, type MouseEvent, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { scoreColor, starToTenScore } from '../types/domain'
import './tasteMapDiscoveryShared.css'
import { ModalShell } from './ModalShell'
import { ChevronsUpDown } from 'lucide-react'
import { recommendationSignal, type RecommendationSignalInput } from '../contracts/recommendationSignal'

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
  return <div aria-label={ariaLabel} className="tm-browse-filter-bar tm-shared-filter-bar" role="toolbar">{children}</div>
}

/** Intrinsic visible text sizes the pill; hidden menu options never reserve space. */
export function TasteMapFilterSelect({ icon, label, value, options, onChange, active = false, presentation = 'native' }: {
  icon: ReactNode
  label: string
  value: string
  options: ReadonlyArray<{ value: string; label: string }>
  onChange: (value: string) => void
  active?: boolean
  presentation?: 'native' | 'dialog'
}) {
  const visibleLabel = options.find((option) => option.value === value)?.label ?? value
  const [pointerFocus, setPointerFocus] = useState(false)
  const [open, setOpen] = useState(false)
  if (presentation === 'dialog') return <>
    <button type="button" className={`tm-filter-select${active ? ' is-active' : ''}`} aria-label={label} aria-haspopup="dialog" aria-expanded={open} onClick={() => setOpen(true)}>
      {icon}<span className="tm-filter-select__value">{visibleLabel}</span><ChevronsUpDown aria-hidden="true" className="tm-filter-select__disclosure" />
    </button>
    {open ? createPortal(<ModalShell title={label} eyebrow={null} size="small" onClose={() => setOpen(false)}>
      <div className="tm-discovery-query-fields">{options.map(option => <button key={option.value} type="button" aria-pressed={value === option.value}
        className={value === option.value ? 'primary-button' : 'secondary-button'} onClick={() => { onChange(option.value); setOpen(false) }}>{option.label}</button>)}</div>
    </ModalShell>, document.body) : null}
  </>
  return <label className={`tm-filter-select${active ? ' is-active' : ''}`} data-pointer-focus={pointerFocus || undefined}>
    {icon}
    <span aria-hidden="true" className="tm-filter-select__value">{visibleLabel}</span>
    <ChevronsUpDown aria-hidden="true" className="tm-filter-select__disclosure" />
    <select aria-label={label} value={value}
      onPointerDown={() => setPointerFocus(true)}
      onKeyDown={() => setPointerFocus(false)}
      onBlur={() => setPointerFocus(false)}
      onChange={(event) => onChange(event.target.value)}>
      {options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
    </select>
  </label>
}

/** A Filters action always opens editable controls, never just explanatory copy. */
export function TasteMapFilterSheet({ children, description, activeCount, onReset, onClose, onApply }: {
  children: ReactNode
  description?: string
  activeCount: number
  onReset: () => void
  onClose: () => void
  onApply?: () => void
}) {
  return <ModalShell title="筛选餐厅" description={description} onClose={onClose} size="small" backdropClassName="tm-discovery-filter-sheet">
    <div className="sticky-action-form">
    <div className="discovery-filter-grid sticky-action-form__content">{children}</div>
    <div className="sticky-form-action-bar"><div className="modal-actions">
      <button className="secondary-button" disabled={!activeCount} onClick={onReset} type="button">重置</button>
      {onApply ? <button className="secondary-button" onClick={onClose} type="button">取消</button> : null}
      <button className="primary-button" onClick={onApply ?? onClose} type="button">{onApply ? '应用' : '查看结果'}</button>
    </div></div>
    </div>
  </ModalShell>
}

/**
 * The author's concrete Visit rating. Taste Map stores Visits on a five-point
 * scale, while Discovery presents the established ten-point score and palette.
 */
export function TasteMapActivityRatingBadge({ rating, prefix = '本次到访' }: { rating: number | null; prefix?: string }) {
  const score = starToTenScore(rating)
  const color = scoreColor(score)
  return <span
    aria-label={score == null ? `${prefix}未评分` : `${prefix}评分 ${score.toFixed(1)}`}
    className={`tm-activity-rating-badge${rating == null ? ' is-unrated' : ''}`}
    role="img"
    style={{ '--tm-activity-rating-color': color } as CSSProperties}
    title={score == null ? `${prefix}未评分` : `${prefix} ${score.toFixed(1)}`}
  ><strong aria-hidden="true">{score == null ? '未评分' : score.toFixed(1)}</strong></span>
}

/** Complete supplied evidence is readable directly; no excerpt or hidden tap layer. */
export function TasteMapRecommendationReasons({ reasons, className = '', evidence }: {
  reasons: ReadonlyArray<string>
  className?: string
  evidence?: string
}) {
  const items = [...new Set(reasons.map((reason) => reason.trim()).filter(Boolean))]
  if (!items.length) return null
  return <ul aria-label="推荐理由" className={`tm-activity-card__recommendation-reasons${className ? ` ${className}` : ''}`} data-discovery-evidence={evidence}>
    {items.map((reason) => <li key={reason}>{reason}</li>)}
  </ul>
}

/** Shared gold rosette/ribbons: decoration only, never a fabricated award or rank. */
function RecommendationRibbonArtwork({ value, label }: { value: string; label: string }) {
  const goldID = useId()
  const seal = Array.from({ length: 144 }, (_, index) => {
    const angle = index * Math.PI / 72 - Math.PI / 2
    const radius = 30 + 1.6 * Math.cos(index * Math.PI / 6)
    return `${index ? 'L' : 'M'}${36 + Math.cos(angle) * radius},${34 + Math.sin(angle) * radius}`
  }).join(' ') + ' Z'
  return <svg aria-hidden="true" className="tm-recommendation-ribbon" viewBox="0 0 72 80" focusable="false">
    <defs><linearGradient id={goldID} x1="0" y1="0" x2="1" y2="1"><stop stopColor="#a76b1d"/><stop offset=".25" stopColor="#f5d67c"/><stop offset=".48" stopColor="#fff0b7"/><stop offset=".7" stopColor="#c38d2f"/><stop offset="1" stopColor="#f0d17b"/></linearGradient></defs>
    <path d="M20 51 12 75 23 70 29 77 35 56M37 56 43 77 49 70 60 75 52 51" fill="#41586b"/>
    <path d="M25 53 20 71 25 68 29 73 34 57M38 57 43 73 47 68 52 71 47 53" fill={`url(#${goldID})`}/>
    <path d={seal} fill={`url(#${goldID})`} stroke="#a97828" strokeWidth=".8"/>
    <circle cx="36" cy="34" r="27.4" fill="none" stroke="#fff4cb" strokeWidth=".8"/>
    <circle cx="36" cy="34" r="24.5" fill="#fffdf5" stroke="#866327" strokeWidth=".8"/>
    <circle cx="36" cy="34" r="22.5" fill="none" stroke="var(--tm-taste-prediction-color)" strokeWidth="1"/>
    <path d="m30 16 2 5h8l2-5-4 2-2-4-2 4z" fill="#be8d35"/>
    <text className="tm-recommendation-ribbon__percent" x="36" y="37" textAnchor="middle" fontSize={value === '积累中' ? 12 : value === '100%' ? 13 : 16} fontWeight="750" fill="var(--tm-taste-prediction-color)">{value}</text>
    <text className="tm-recommendation-ribbon__label" x="36" y="46" textAnchor="middle" fontSize="7.3" fontWeight="600" fill="#685a42">{label}</text>
  </svg>
}

/** Browser and Capacitor share the same honest two-mode signal and explanation. */
export function TasteMapRecommendationSignal({ input }: { input: RecommendationSignalInput }) {
  const [showExplanation, setShowExplanation] = useState(false)
  const signal = recommendationSignal(input)
  const value = signal.percent == null ? '积累中' : `${signal.percent}%`
  return <><button aria-label={`${signal.label} ${value}，查看说明`} aria-haspopup="dialog" onClick={() => setShowExplanation(true)} type="button"
    className={`tm-activity-card__taste-prediction is-${signal.mode}${signal.percent == null ? ' is-pending' : ''}`}
    data-recommendation-signal={signal.mode} data-signal-artwork="ribbon-medal"
    style={{ '--tm-taste-prediction-color': scoreColor(signal.percent == null ? null : signal.percent / 10), '--tm-taste-prediction-progress': `${signal.percent ?? 0}%` } as CSSProperties}
  ><RecommendationRibbonArtwork value={value} label={signal.label} /></button>
    {showExplanation ? <ModalShell eyebrow="推荐说明" title={signal.label} onClose={() => setShowExplanation(false)} size="small">
      <p>{signal.explanation}</p>
      {signal.mode === 'probability' && input.calibratedLikeProbability ? <p className="tm-recommendation-signal-explanation">模型 {input.calibratedLikeProbability.modelVersion} · 校准 {input.calibratedLikeProbability.calibrationVersion} · 经过验证的样本 {input.calibratedLikeProbability.validationSampleCount.toLocaleString('zh-CN')} 条</p> : <p className="tm-recommendation-signal-explanation">尚无符合展示条件的经校准概率；记录数量增加不会自动变成喜欢概率。</p>}
    </ModalShell> : null}</>
}

/** Bare social icon + quiet count; never shrink the actual interactive target. */
export function TasteMapSocialAction({ label, icon, count, pressed, pending = false, onClick }: {
  label: string
  icon: ReactNode
  count?: number
  pressed?: boolean
  pending?: boolean
  onClick: () => void
}) {
  const visibleCount = count != null && Number.isFinite(count) && count > 0
    ? new Intl.NumberFormat('zh-CN', { notation: 'compact', maximumFractionDigits: 1 }).format(count)
    : null
  return <button aria-label={label} aria-description={count == null ? undefined : `当前数量 ${count}`} aria-pressed={pressed} aria-busy={pending || undefined} disabled={pending} onClick={onClick} type="button">
    <span aria-hidden="true" className="tm-social-action__icon">{icon}</span>
    {visibleCount ? <span aria-hidden="true" className="tm-social-action__count">{visibleCount}</span> : null}
  </button>
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
  mediaCount = 1,
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
  mediaCount?: number
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
    data-media-layout="compact"
    onClick={open}
  >
    {header ? <header data-activity-region="author-time-visibility">{header}</header> : null}
    {activityRating ? <div className="tm-activity-card__restaurant-row">
      <div className="tm-activity-card__restaurant" data-activity-region="restaurant-name-address-context">{restaurant}</div>
      <div className="tm-activity-card__rating" data-activity-region="visit-rating">{activityRating}</div>
    </div> :
      <div className="tm-activity-card__restaurant" data-activity-region="restaurant-name-address-context">{restaurant}</div>
    }
    {media ? <div className={`tm-activity-card__media${mediaCount > 1 ? ' has-multiple' : ''}`} data-activity-region="restaurant-image">{media}</div> : null}
    {body ? <div className="tm-activity-card__body" data-activity-region={variant === 'recommendation' ? 'recommendation-reason' : 'activity-context'}>{body}</div> : null}
    {socialActions || restaurantActions ? <footer>
      {socialActions ? <div className="tm-activity-card__social" data-activity-region="like-comment-more-share">{socialActions}</div> : null}
      <div className="tm-activity-card__restaurant-actions" data-activity-region="restaurant-actions">{restaurantActions}</div>
    </footer> : null}
  </article>
}
