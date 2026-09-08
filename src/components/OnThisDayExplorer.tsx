import { useMemo, useRef, useState } from 'react'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import type { TasteMapPlatform, TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { buildDayEditorial } from '../services/analysisEditorialData'
import { exactMemoryReview, memoryYearGroups, nearbyMemoryVisits } from '../services/onThisDayMemory'
import { analyticsDataset } from '../services/analyticsReportData'
import { analyticsReportVisuals } from '../services/analyticsReportVisuals'
import { analyticsVisitDateLabel } from '../services/analyticsPeriodReport'
import { buildOnThisDayShareData } from '../services/analysisShare'
import { resolveVisitActualSpend } from '../services/visitSpend'
import { ModalShell } from './ModalShell'
import { AnalysisEvidenceImage } from './AnalyticsReportDataView'
import { MemoryPoster } from './MemoryPoster'
import { ReadingEmpty, ReadingFacts, ReadingLink, ReadingRecords, readingScore, useAnalysisReading } from './AnalysisReadingUI'

export function OnThisDayExplorer({ user, restaurants, visits, profile, platform, onClose, onOpenRestaurant }: { user: UserProfile; restaurants: RestaurantSummary[]; visits: Visit[]; profile?: TasteMapProfileDashboardViewModel; platform?: TasteMapPlatform; onClose: () => void; onOpenRestaurant: (id: string) => void }) {
  const clock = useMemo(() => new Date(), [])
  const dataset = useMemo(() => profile ? analyticsDataset(profile, clock) : { restaurants: restaurants.filter(item => item.userId === user.id && !item.deletedAt), visits: visits.filter(item => item.userId === user.id && !item.deletedAt && Date.parse(item.visitedAt) <= clock.getTime()) }, [profile, restaurants, visits, user.id, clock])
  const [date, setDate] = useState(analyticsVisitDateLabel(clock.toISOString()))
  const [draft, setDraft] = useState(date)
  const [error, setError] = useState('')
  const reference = useMemo(() => new Date(`${date}T12:00:00`), [date])
  const { route, go, setRoute, back, root } = useAnalysisReading(user.id, 'on-this-day', 'D01')
  const review = useMemo(() => exactMemoryReview(dataset.restaurants, dataset.visits, reference), [dataset, reference])
  const exactIDs = new Set(review.memories.map(item => item.visitId))
  const sameDay = dataset.visits.filter(item => exactIDs.has(item.id))
  const selected = dataset.visits.find(item => item.id === route.entity)
  const selectedRestaurant = dataset.restaurants.find(item => item.id === selected?.restaurantId)
  const visuals = useMemo(() => profile ? analyticsReportVisuals(profile, dataset.restaurants, selected ? [selected] : dataset.visits) : {}, [profile, dataset, selected])
  const shareData = useMemo(() => {
    const chosen = dataset.visits.filter(item => item.visibility === 'public' && (route.entity ? item.id === route.entity : review.memories.some(memory => memory.visitId === item.id)))
    const safe = exactMemoryReview(dataset.restaurants, chosen.map(item => ({ ...item, note: '', companions: [] })), reference)
    // Nearby single memories use their own real date, never the selected exact day.
    const result = route.entity && chosen[0] ? exactMemoryReview(dataset.restaurants, chosen.map(item => ({ ...item, note: '', companions: [] })), new Date(clock.getFullYear(), new Date(chosen[0].visitedAt).getMonth(), new Date(chosen[0].visitedAt).getDate(), 12)) : safe
    const data = buildOnThisDayShareData(user, result)
    const allowedVisuals = profile ? analyticsReportVisuals(profile, dataset.restaurants, chosen) : {}
    const evidence = data.restaurants.map(item => ({ ...item, image: allowedVisuals[item.restaurantId] ?? { source: null, photoId: null, origin: 'fallback' as const, label: item.name } }))
    return buildDayEditorial({ ...data, insights: [], posterFindings: [], restaurants: evidence, heroCandidates: evidence.map(item => item.image), footer: 'Taste Map · 仅公开回忆 · 不含金额、同行姓名和备注' }, profile, dataset.restaurants, chosen, 'share', clock)
  }, [dataset, route.entity, review, reference, user, profile, clock])
  const ownerData = useMemo(() => {
    const chosen = dataset.visits.filter(item => route.entity ? item.id === route.entity : review.memories.some(memory => memory.visitId === item.id))
    const actualReference = route.entity && chosen[0] ? new Date(clock.getFullYear(), new Date(chosen[0].visitedAt).getMonth(), new Date(chosen[0].visitedAt).getDate(), 12) : reference
    const result = exactMemoryReview(dataset.restaurants, chosen, actualReference)
    return buildDayEditorial(buildOnThisDayShareData(user, result), profile, dataset.restaurants, chosen, 'owner', clock)
  }, [dataset, route.entity, review, reference, user, profile, clock])
  const openVisit = (id: string) => { if (platform) void platform.navigation.openHybrid({ surface: 'visit', identifier: id }).catch(() => setError('记录详情未打开，请重试。')); else { const visit = dataset.visits.find(item => item.id === id); if (visit) onOpenRestaurant(visit.restaurantId) } }
  const titles: Record<string, string> = { D01: '那年今日', D02: '这顿饭的回忆', D03: '不同年份的这一天', D04: '选择回忆日期', D05: '往年的这一天还没有记录', D06: '附近日期的回忆', D07: '那年今日海报', D08: '同日记录清单' }
  const list = (rows: Visit[]) => rows.map(item => <ReadingLink key={item.id} title={dataset.restaurants.find(restaurant => restaurant.id === item.restaurantId)?.name ?? '餐厅'} note={`${analyticsVisitDateLabel(item.visitedAt)} · ${readingScore(item.rating == null ? null : item.rating * 2)}`} onClick={() => go({ page: 'D02', entity: item.id })} />)
  const displayPage = route.page === 'D01' && !sameDay.length ? 'D05' : route.page
  const backRef = useRef(back); backRef.current = back
  const yearContent = <>
    <p>{reference.getMonth() + 1} 月 {reference.getDate()} 日 · 按年份从近到远，只看往年同日</p>
    {memoryYearGroups(sameDay).map(group => <section key={group.year} aria-label={`${group.year} 年的同日回忆`}>
      <h2>{group.year} 年 · {group.visits.length} 条记录</h2>
      {list(group.visits)}
    </section>)}
    {!sameDay.length ? <ReadingEmpty><p>往年的这一天还没有记录。</p></ReadingEmpty> : null}
    {sameDay.length ? <ReadingLink title="同日记录清单" onClick={() => go({ page: 'D08' })} /> : null}
  </>
  return <ModalShell title={titles[displayPage] ?? '那年今日'} eyebrow="TASTE MAP MEMORIES" size="large" dismissAction="back" onClose={() => { if (!backRef.current()) onClose() }}><article ref={root} className="tm-taste-explorer tm-memory-explorer" data-explore-page={displayPage}>
    {error ? <p role="alert">{error}</p> : null}
    {displayPage === 'D03' ? yearContent : <>
    {displayPage === 'D07' ? <MemoryPoster ownerData={ownerData} data={shareData} platform={platform} pageID="D07" /> : displayPage === 'D04' ? <><p>按实际用餐日期匹配往年同日，不使用创建或上传日期。闰日严格匹配，不平移到 2 月 28 日。</p><input className="tm-memory-date" type="date" aria-label="回忆日期" value={draft} onChange={event => setDraft(event.target.value)} /><button className="tm-explore-primary" type="button" onClick={() => { const value = new Date(`${draft}T12:00:00`); if (!Number.isFinite(value.getTime()) || value.getFullYear() !== clock.getFullYear()) { setError('请选择今年日历中的月日。'); return } setError(''); setDate(draft); setRoute({ page: 'D01' }) }}>查看这一天</button></> : displayPage === 'D02' && selected ? <><p>{analyticsVisitDateLabel(selected.visitedAt)} · {selectedRestaurant?.name}</p><div className="tm-memory-single"><button type="button" onClick={() => onOpenRestaurant(selected.restaurantId)}><AnalysisEvidenceImage name={selectedRestaurant?.name ?? '餐厅'} visual={visuals[selected.restaurantId]} /></button></div><ReadingFacts values={[{ label: '你的评分', value: readingScore(selected.rating == null ? null : selected.rating * 2) }, { label: '个人实际支出', value: resolveVisitActualSpend(selected) == null ? '未记录' : `¥${resolveVisitActualSpend(selected)}` }]} />{selected.note ? <p style={{ whiteSpace: 'pre-wrap' }}>{selected.note}</p> : <p>这次没有留下备注。</p>}<ReadingLink title="打开原始用餐记录" onClick={() => openVisit(selected.id)} /><ReadingLink title="餐厅详情" onClick={() => onOpenRestaurant(selected.restaurantId)} /><button className="tm-explore-primary" type="button" onClick={() => go({ page: 'D07', entity: selected.id })}>生成回忆海报</button></> : displayPage === 'D08' ? <ReadingRecords visits={sameDay} restaurants={dataset.restaurants} onOpenVisit={openVisit} onOpenRestaurant={onOpenRestaurant} /> : displayPage === 'D06' ? <><p>{date} 前后 3 天 · 以下是附近日期，不是往年同日。</p>{list(nearbyMemoryVisits(dataset.restaurants, dataset.visits, reference))}<ReadingLink title="换一个回忆日期" onClick={() => go({ page: 'D04' })} /></> : <><p>{date === analyticsVisitDateLabel(clock.toISOString()) ? '今天' : '所选日期'} · {reference.getMonth() + 1} 月 {reference.getDate()} 日 · 只看往年同日</p>{sameDay.length ? <>{displayPage === 'D01' ? <h2 className="tm-explore-headline">这一天，你留下过 {sameDay.length} 段真实用餐记忆。</h2> : null}{list([...sameDay].sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt)))}<ReadingLink title="不同年份的这一天" onClick={() => go({ page: 'D03' })} /><ReadingLink title="生成同日回忆画报" onClick={() => go({ page: 'D07' })} /><ReadingLink title="同日记录清单" onClick={() => go({ page: 'D08' })} /></> : <ReadingEmpty><p>往年的这一天还没有记录。一条真实记录就能成为回忆，不需要达到分析样本门槛。</p></ReadingEmpty>}<ReadingLink title="选择回忆日期" onClick={() => { setDraft(date); go({ page: 'D04' }) }} /><ReadingLink title="看看附近日期" note="单独标出实际日期，不当作今天" onClick={() => go({ page: 'D06' })} /></>}
    </>}
  </article></ModalShell>
}
