import { useState, type ReactNode } from 'react'
import { AlertCircle, ChevronRight, LoaderCircle, ReceiptText, Search, SlidersHorizontal, Utensils } from 'lucide-react'
import type { TasteMapImageDescriptor } from '../platform/TasteMapPlatform'

export function HybridPageHeader({ eyebrow, title, description, trailing }: { eyebrow?: string; title: string; description?: string; trailing?: ReactNode }) {
  return <header className="tm-hybrid-page-header">
    <div>{eyebrow ? <small>{eyebrow}</small> : null}<h1>{title}</h1>{description ? <p>{description}</p> : null}</div>
    {trailing ? <div className="tm-hybrid-page-header__trailing">{trailing}</div> : null}
  </header>
}

export function HybridRestaurantImage({ image, name, className = '' }: { image: TasteMapImageDescriptor; name: string; className?: string }) {
  const [failed, setFailed] = useState(false)
  const source = 'resourceURL' in image ? image.resourceURL : null
  if (!source || failed) {
    return <div aria-label={`${name} 暂无真实餐厅图片`} className={`tm-hybrid-image-fallback ${className}`} role="img">
      <Utensils aria-hidden="true" size={28} /><span>Taste Map</span>
    </div>
  }
  return <img alt={image.accessibilityLabel || `${name} 餐厅图片`} className={className} decoding="async" loading="lazy" onError={() => setFailed(true)} src={source} />
}

export function HybridFilterBar({ city, cities, onCity, search, onSearch, extra }: { city: string; cities: string[]; onCity: (value: string) => void; search?: string; onSearch?: (value: string) => void; extra?: ReactNode }) {
  return <div className="tm-hybrid-filter-shell">
    {onSearch ? <label className="tm-hybrid-search"><Search aria-hidden="true" size={16} /><input aria-label="搜索" onChange={(event) => onSearch(event.target.value)} placeholder="搜索餐厅" value={search} /></label> : null}
    <div aria-label="筛选" className="tm-hybrid-filter-bar" role="toolbar">
      <span className="tm-hybrid-filter-bar__lead"><SlidersHorizontal aria-hidden="true" size={15} />筛选</span>
      <button aria-pressed={city === 'all'} onClick={() => onCity('all')} type="button">全部城市</button>
      {cities.map((value) => <button aria-pressed={city === value} key={value} onClick={() => onCity(value)} type="button">{value}</button>)}
      {extra}
    </div>
  </div>
}

export function HybridState({ kind, title, message, action }: { kind: 'loading' | 'empty' | 'error' | 'offline'; title: string; message: string; action?: ReactNode }) {
  const Icon = kind === 'loading' ? LoaderCircle : kind === 'error' ? AlertCircle : kind === 'offline' ? ReceiptText : Utensils
  return <section className={`tm-hybrid-inline-state is-${kind}`}>
    <span><Icon aria-hidden="true" className={kind === 'loading' ? 'spin' : ''} size={25} /></span>
    <h2>{title}</h2><p>{message}</p>{action}
  </section>
}

export function HybridEntryRow({ icon, title, detail, onClick, value }: { icon: ReactNode; title: string; detail: string; onClick?: () => void; value?: string }) {
  const content = <><span className="tm-hybrid-entry-row__icon">{icon}</span><span><strong>{title}</strong><small>{detail}</small></span>{value ? <em>{value}</em> : null}{onClick ? <ChevronRight aria-hidden="true" size={17} /> : null}</>
  return onClick
    ? <button className="tm-hybrid-entry-row" onClick={onClick} type="button">{content}</button>
    : <div className="tm-hybrid-entry-row">{content}</div>
}
