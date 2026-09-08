import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ArrowRight, ChevronRight } from 'lucide-react'
import type { Visit, RestaurantSummary } from '../types/domain'
import type { AnalyticsReport } from '../services/analyticsReport'
import { analyticsVisitDateLabel } from '../services/analyticsPeriodReport'
import { analyticsHasMealTime } from '../services/analyticsDiningContext'
import { AnalysisEvidenceImage } from './AnalyticsReportDataView'
import './tasteProfileExplorer.css'
import './analysisMemoryExplorer.css'

export const readingScore = (value: number | null | undefined) => value == null ? '未评分' : `${value.toFixed(1)} / 10`
export const readingPercent = (value: number | null | undefined) => value == null ? '暂无评分' : `${Number((value * 100).toFixed(1))}%`
export function ReadingLink({ title, note, onClick, tone }: { title: string; note?: string; onClick: () => void; tone?: 'positive' | 'negative' }) {
  return <button type="button" className={tone ? `tm-memory-feature is-${tone}` : 'tm-explore-topic'} onClick={onClick}><span><strong>{title}</strong>{note ? <small>{note}</small> : null}</span>{tone ? <ArrowRight size={19} /> : <ChevronRight size={17} />}</button>
}
export function ReadingFacts({ values }: { values: Array<{ label: string; value: string | number }> }) {
  return <dl className="tm-explore-facts">{values.map(item => <div key={item.label}><dd>{item.value}</dd><dt>{item.label}</dt></div>)}</dl>
}
export function ReadingEmpty({ children }: { children: ReactNode }) { return <div className="tm-explore-empty">{children}</div> }
export interface ReadingRoute { page: string; entity?: string; lens?: string; ids?: string[]; label?: string; date?: string }
export function readingRouteKey(route: ReadingRoute) {
  return JSON.stringify([route.page, route.entity, route.lens, route.ids, route.label, route.date])
}
type Entry = { route: ReadingRoute; scroll: number[] }
let session: { owner: string; entries: Map<string, { route: ReadingRoute; stack: Entry[]; scroll: number[] }> } | null = null
/** Reading state only, never persisted records, a second app router or an owner cache. */
export function useAnalysisReading(owner: string, key: string, first: string, registerBack?: (handler: (() => boolean) | null) => void) {
  if (session?.owner !== owner) session = { owner, entries: new Map() }
  const saved = session.entries.get(key)
  const [route, setRoute] = useState<ReadingRoute>(saved?.route ?? { page: first })
  const root = useRef<HTMLElement>(null)
  const stack = useRef<Entry[]>(saved?.stack ?? [])
  const position = () => { const values: number[] = []; let element: Element | null = root.current; while (element) { values.push(element.scrollTop); element = element.parentElement } return values }
  const restore = (values: number[]) => { let element: Element | null = root.current; let index = 0; while (element) { element.scrollTop = values[index++] ?? 0; element = element.parentElement } }
  const latest = useRef(route); latest.current = route
  const go = (next: ReadingRoute, returning = latest.current) => {
    // Repeated taps before React commits must not append the same destination.
    if (readingRouteKey(next) === readingRouteKey(latest.current)) return
    stack.current.push({ route: returning, scroll: position() })
    latest.current = next
    setRoute(next)
    requestAnimationFrame(() => restore([]))
  }
  const back = () => { const entry = stack.current.pop(); if (!entry) return false; setRoute(entry.route); requestAnimationFrame(() => restore(entry.scroll)); return true }
  useEffect(() => { if (saved) requestAnimationFrame(() => restore(saved.scroll)); return () => { if (session?.owner === owner) session.entries.set(key, { route: latest.current, stack: stack.current, scroll: position() }) } }, [owner, key])
  useEffect(() => { registerBack?.(back); return () => registerBack?.(null) }, [registerBack])
  return { route, setRoute, go, back, root }
}
export function ReadingRecords({ visits, restaurants, onOpenVisit, onOpenRestaurant }: { visits: Visit[]; restaurants: RestaurantSummary[]; onOpenVisit: (id: string) => void; onOpenRestaurant: (id: string) => void }) {
  const [limit, setLimit] = useState(20)
  return <>{[...visits].sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt) || a.id.localeCompare(b.id)).slice(0, limit).map(visit => <article className="tm-memory-record" key={visit.id}>
    <button type="button" onClick={() => onOpenVisit(visit.id)}><span><strong>{restaurants.find(item => item.id === visit.restaurantId)?.name ?? '餐厅'}</strong><small>{analyticsVisitDateLabel(visit.visitedAt)}{analyticsHasMealTime(visit) ? ` · ${new Date(visit.visitedAt).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}` : ' · 未记录时段'} · {visit.visibility === 'public' ? '公开' : visit.visibility === 'friends' ? '好友可见' : '仅自己'}</small></span><b>{readingScore(visit.rating == null ? null : visit.rating * 2)}</b><ChevronRight size={16} /></button>
    {visit.note ? <p>{visit.note}</p> : null}<button type="button" className="tm-memory-quiet" onClick={() => onOpenRestaurant(visit.restaurantId)}>餐厅详情<ChevronRight size={14} /></button>
  </article>)}{!visits.length ? <ReadingEmpty><p>这个条件下还没有记录。缺失不等于零分。</p></ReadingEmpty> : null}{visits.length > limit ? <button className="tm-explore-secondary" type="button" onClick={() => setLimit(value => value + 20)}>继续查看 · {limit}/{visits.length}</button> : null}</>
}
export function ReadingCollage({ report, ids, onSelect }: { report: AnalyticsReport; ids: string[]; onSelect?: (id: string) => void }) {
  return <div className="tm-memory-collage">{ids.slice(0, 3).map(id => { const name = report.scopedRestaurants.find(item => item.id === id)?.name ?? '餐厅'; return <button key={id} type="button" disabled={!onSelect} onClick={() => onSelect?.(id)}><AnalysisEvidenceImage visual={report.visualEvidence[id]} name={name} /><small>{name}</small></button> })}</div>
}
