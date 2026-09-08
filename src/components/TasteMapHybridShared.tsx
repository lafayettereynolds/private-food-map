import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { AlertCircle, ArrowLeft, ChevronRight, LoaderCircle, ReceiptText, Search, SlidersHorizontal, Utensils } from 'lucide-react'
import type { TasteMapImageDescriptor, TasteMapImageResolutionDTO } from '../platform/TasteMapPlatform'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import { RestaurantFoodEmoji } from '../visuals/RestaurantFoodEmoji'
import { FoodLibraryArtwork } from '../visuals/FoodLibraryArtwork'
import { resolvedImageDescriptor } from './TasteMapImageResolution'
import './tasteMapNavigation.css'
import './tasteMapHybridShared.css'

export function HybridPageHeader({ eyebrow, title, description, trailing }: { eyebrow?: string; title: string; description?: string; trailing?: ReactNode }) {
  return <header className="tm-hybrid-page-header">
    <div>{eyebrow ? <small>{eyebrow}</small> : null}<h1>{title}</h1>{description ? <p>{description}</p> : null}</div>
    {trailing ? <div className="tm-hybrid-page-header__trailing">{trailing}</div> : null}
  </header>
}

export function PersistentPageNavigation({ children, className = '', as: Element = 'nav' }: { children: ReactNode; className?: string; as?: 'nav' | 'header' | 'div' }) {
  return <Element aria-label="页面返回导航" className={`tm-hybrid-page-navigation ${className}`.trim()} role="navigation">{children}</Element>
}

export function HybridBackButton({ onBack }: { onBack?: () => void }) {
  if (!onBack) return null
  return <PersistentPageNavigation>
    <PageBackIconButton onBack={onBack} />
  </PersistentPageNavigation>
}

export function PageBackIconButton({ onBack, disabled = false }: { onBack: () => void; disabled?: boolean }) {
  return <button aria-label="返回上一页" className="tm-hybrid-page-back" disabled={disabled} onClick={onBack} type="button"><ArrowLeft aria-hidden="true" size={21} /></button>
}

export function HybridRestaurantImage({ image, resolution, name, tags, appearance = 'avatar', className = '' }: { image?: TasteMapImageDescriptor; resolution?: TasteMapImageResolutionDTO; name: string; tags?: readonly string[]; appearance?: 'avatar' | 'content'; className?: string }) {
  const plan = useMemo(() => resolution ?? compatibilityResolution(image, name), [image, name, resolution])
  const identity = useMemo(() => JSON.stringify(plan), [plan])
  const [sourceIndex, setSourceIndex] = useState(0)
  useEffect(() => setSourceIndex(0), [identity])
  const selected = resolvedImageDescriptor(plan, sourceIndex)
  if (appearance === 'content' && (selected.kind === 'foodCategoryVisual' || selected.kind === 'foodDiningFallback')) {
    return <FoodLibraryArtwork categoryVisualID={selected.kind === 'foodCategoryVisual' ? selected.categoryVisualID : undefined} className={className} name={name} tags={tags} />
  }
  if (selected.kind === 'foodCategoryVisual') {
    return <RestaurantFoodEmoji categoryVisualID={selected.categoryVisualID} className={className} label={selected.accessibilityLabel || `${name} 食物表情`} name={name} preferredEmoji={selected.preferredEmoji} />
  }
  if (selected.kind === 'foodDiningFallback') {
    return <RestaurantFoodEmoji className={className} label={selected.accessibilityLabel || `${name} 食物表情`} name={name} />
  }
  return <img alt={selected.accessibilityLabel || `${name} 餐厅图片`} className={className} decoding="async" loading="lazy" onError={() => setSourceIndex((value) => value + 1)} src={selected.resourceURL} />
}

function compatibilityResolution(image: TasteMapImageDescriptor | undefined, name: string): TasteMapImageResolutionDTO {
  const fallback = image?.kind === 'foodDiningFallback' || image?.kind === 'foodCategoryVisual'
    ? image
    : { kind: 'foodCategoryVisual' as const, categoryVisualID: resolveFoodCategoryVisualID({ name }), stableSeed: name, accessibilityLabel: `${name} 餐饮分类图示`, exportAllowed: false as const }
  return { sources: image && image.kind !== 'foodDiningFallback' && image.kind !== 'foodCategoryVisual' ? [image] : [], fallback }
}

export function HybridFilterBar({ city, cities, onCity, search, onSearch, extra }: { city: string; cities: string[]; onCity: (value: string) => void; search?: string; onSearch?: (value: string) => void; extra?: ReactNode }) {
  return <div className="tm-hybrid-filter-shell">
    {onSearch ? <label className="tm-hybrid-search"><Search aria-hidden="true" size={16} /><input aria-label="搜索" onChange={(event) => onSearch(event.target.value)} placeholder="搜索餐厅" value={search} /></label> : null}
    <div aria-label="筛选" className="tm-hybrid-filter-bar" role="toolbar">
      <span className="tm-hybrid-filter-bar__lead"><SlidersHorizontal aria-hidden="true" size={15} />筛选</span>
      <button aria-pressed={city === 'all'} onClick={() => onCity('all')} type="button">城市</button>
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

export function HybridEntryRow({ icon, title, detail, onClick, value, disabled = false }: { icon: ReactNode; title: string; detail: string; onClick?: () => void; value?: string; disabled?: boolean }) {
  const content = <><span className="tm-hybrid-entry-row__icon">{icon}</span><span><strong>{title}</strong><small>{detail}</small></span>{value ? <em>{value}</em> : null}{onClick ? <ChevronRight aria-hidden="true" size={17} /> : null}</>
  return onClick
    ? <button className="tm-hybrid-entry-row" disabled={disabled} onClick={onClick} type="button">{content}</button>
    : <div className="tm-hybrid-entry-row">{content}</div>
}
