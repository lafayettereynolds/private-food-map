import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ArrowRight, BarChart3, BookOpen, ChevronRight, Clock3, Info, MapPin, Search, Share2, SlidersHorizontal, Users, Utensils, Wallet } from 'lucide-react'
import type { AnalyticsReport } from '../services/analyticsReport'
import { analyticsReportHome } from '../services/analyticsReportHome'
import { analyticsQueryRecords, analyticsMealTime, type AnalyticsExploreFilter, type AnalyticsRecordCondition } from '../services/analyticsExploreQuery'
import { analyticsAverage, analyticsCities, analyticsRestaurantRanking } from '../services/analyticsReportData'
import { analyticsRepresentativeRatings, ANALYTICS_EVIDENCE_RULES } from '../services/analyticsEvidenceRules'
import { visitReferencePrice } from '../services/visitSpend'
import { FoodLibraryArtwork } from '../visuals/FoodLibraryArtwork'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import { ModalShell } from './ModalShell'
import { AnalysisEvidenceImage } from './AnalyticsReportDataView'
import type { AnalyticsRow, AnalyticsSection } from '../services/analyticsReportTypes'
import './tasteProfileExplorer.css'
import { RecommendationSourceExplorer } from './RecommendationSourceExplorer'

type Page = 'F01' | 'F02' | 'F04' | 'F05' | 'F06' | 'F07' | 'F08' | 'F09' | 'F10' | 'F11' | 'F12' | 'F13' | 'F14' | 'F15' | 'F16' | 'F17' | 'F18' | 'F19' | 'F20' | 'F21' | 'F23'
interface Destination { page: Page; condition: AnalyticsRecordCondition; entity?: string }
interface Evidence { title: string; formula: string; condition: AnalyticsRecordCondition; sample?: string }
interface ReadingEntry { route: Destination; lens: string; search: string; limit: number; positions: number[] }
let retained: { ownerID: string; route: Destination; lens: string; search: string; limit: number; history: ReadingEntry[]; scroll: number[] } | null = null
const all: AnalyticsRecordCondition = { label: '当前档案全部记录' }
const titles: Record<Page, string> = { F01: '我的口味档案', F02: '从一个问题开始', F04: '偏好与发现', F05: '菜系详情', F06: '你记录过的味道', F07: '我记录的餐饮支出', F08: '常吃价位与高分', F09: '这个价位的餐厅', F10: '你的用餐节奏', F11: '最近，哪里变了', F12: '偏好的长期轨迹', F13: '餐厅与足迹', F14: '新发现与再回去', F15: '你的代表餐厅', F16: '和谁一起吃', F17: '哪些来源更合口味', F18: '来源详情', F19: '你怎样打分', F20: '哪些数据参与了分析', F21: '原始记录', F23: '还在积累，但不是空白' }
const topics: [Page, string, string, typeof Utensils][] = [
  ['F04', '偏好与发现', '常吃什么，哪些体验更高分', Utensils], ['F07', '消费与价位', '实际支出与用餐人均分开看', Wallet],
  ['F10', '时间与变化', '用餐时段，最近发生的变化', Clock3], ['F13', '餐厅与足迹', '去哪里吃，哪些店会再回去', MapPin],
  ['F19', '评分与记录', '评分分布，数据完整程度', BarChart3],
]
const scoreBands = [{ label: '低于 6', minimum: 0, maximum: 6 }, { label: '6–不足 8', minimum: 6, maximum: 8 }, { label: '8–不足 9', minimum: 8, maximum: 9 }, { label: '9 分及以上', minimum: 9, maximum: 11 }]
const percent = (value: number) => `${Math.round(value * 100)}%`
const score = (value: number | null | undefined) => value == null ? '未评分' : value.toFixed(1) + ' / 10'
const money = (value: number | null) => value == null ? '未记录' : '¥' + value.toLocaleString('zh-CN', { maximumFractionDigits: 2 })

/** F01–F24 is a report-local reading stack, not a second app router or database.
 * Restaurant/Visit transitions retain the canonical product destinations. */
export function TasteProfileExplorer({ report, filter, onFilter, onOpenRestaurant, onOpenVisit, onPoster, onSourcePoster, onOpenSources, registerBack }: {
  report: AnalyticsReport; filter: AnalyticsExploreFilter; onFilter: (filter: AnalyticsExploreFilter) => void
  onOpenRestaurant: (id: string) => void; onOpenVisit: (id: string) => void; onPoster: () => void
  onOpenSources?: () => void
  onSourcePoster?: () => void
  registerBack: (handler: (() => boolean) | null) => void
}) {
  const saved = retained?.ownerID === report.scope.ownerID ? retained : null
  const [route, setRoute] = useState<Destination>(saved?.route ?? { page: 'F01', condition: all })
  const [lens, setLens] = useState(saved?.lens ?? 'frequency')
  const [search, setSearch] = useState(saved?.search ?? '')
  const [limit, setLimit] = useState(saved?.limit ?? 20)
  const [sheet, setSheet] = useState<'filter' | Evidence | null>(null)
  const [draft, setDraft] = useState(filter)
  const root = useRef<HTMLElement>(null)
  const sourceBack = useRef<(() => boolean) | null>(null)
  const registerSourceBack = useRef((handler: (() => boolean) | null) => { sourceBack.current = handler }).current
  const history = useRef<ReadingEntry[]>(saved?.history ?? [])
  const scrollPositions = () => { const result: number[] = []; let node: Element | null = root.current; while (node) { result.push(node.scrollTop); node = node.parentElement } return result }
  const restoreScroll = (positions: number[]) => { let node: Element | null = root.current; let index = 0; while (node) { node.scrollTop = positions[index++] ?? 0; node = node.parentElement } }
  useEffect(() => { if (saved) requestAnimationFrame(() => restoreScroll(saved.scroll)); return () => {} }, [])
  useEffect(() => () => { retained = { ownerID: report.scope.ownerID, route, lens, search, limit, history: history.current, scroll: scrollPositions() } }, [report.scope.ownerID, route, lens, search, limit])
  const go = (page: Page, condition = all, entity?: string) => {
    if (page === 'F17' && onOpenSources) { onOpenSources(); return }
    history.current.push({ route, lens, search, limit, positions: scrollPositions() })
    setRoute({ page, condition, entity }); setLens('frequency'); setSearch(''); setLimit(20)
    requestAnimationFrame(() => root.current?.scrollIntoView({ block: 'start' }))
  }
  useEffect(() => { registerBack(() => {
    if (sourceBack.current?.()) return true
    if (sheet) { setSheet(null); return true }
    const previous = history.current.pop(); if (!previous) return false
    setRoute(previous.route); setLens(previous.lens); setSearch(previous.search); setLimit(previous.limit)
    requestAnimationFrame(() => restoreScroll(previous.positions))
    return true
  }); return () => registerBack(null) }, [sheet, registerBack])
  const { page, condition } = route
  const taste = report.taste!
  const home = analyticsReportHome(report)
  const visits = report.scopedVisits
  const restaurants = report.scopedRestaurants
  const byID = new Map(restaurants.map(item => [item.id, item]))
  const selected = analyticsQueryRecords(restaurants, visits, condition)
  const records = selected.filter(visit => !search.trim() || (byID.get(visit.restaurantId)?.name ?? '').toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()))
  const evidence = (title: string, formula: string, query = condition, sample?: string) => setSheet({ title, formula, condition: query, sample })
  const openRecords = (query = condition) => go('F21', query)
  const section = (id: string) => report.sections.find(item => item.id === id)
  const note = (title: string, formula: string, query = condition, sample?: string) => <button className="tm-explore-note" type="button" onClick={() => evidence(title, formula, query, sample)}><Info size={17} aria-hidden /><span>{title}</span><ChevronRight size={14} aria-hidden /></button>
  const link = (target: Page, title: string, subtitle: string, query = all, Icon = BookOpen) => <button className="tm-explore-topic" type="button" onClick={() => go(target, query)}><span className="tm-explore-topic__icon"><Icon size={21} aria-hidden /></span><span><strong>{title}</strong><small>{subtitle}</small></span><ChevronRight size={16} aria-hidden /></button>
  const empty = (text: string) => <div className="tm-explore-empty"><p>{text}</p><button type="button" onClick={() => openRecords(all)}>查看已有记录<ArrowRight size={16} aria-hidden /></button></div>
  const restaurantRows = (rows: AnalyticsRow[], maximum = 3) => rows.slice(0, maximum).map(item => <button className="tm-explore-restaurant" key={item.id} type="button" onClick={() => item.restaurantID && onOpenRestaurant(item.restaurantID)}><AnalysisEvidenceImage visual={report.visualEvidence[item.restaurantID ?? '']} name={item.label} tags={byID.get(item.restaurantID ?? '')?.tags} /><span><strong>{item.label}</strong><small>{byID.get(item.restaurantID ?? '')?.city} · {item.count ?? 0} 次用餐{item.detail ? ' · ' + item.detail : ''}</small></span><b>{score(item.scoreOutOfTen)}</b><ChevronRight size={14} aria-hidden /></button>)
  const cuisineGo = (label: string) => go('F05', { label, cuisine: label })
  const facts = (values: [string, string][]) => <dl className="tm-explore-facts">{values.map(([label, value]) => <div key={label}><dd>{value}</dd><dt>{label}</dt></div>)}</dl>
  const related = (ids: string[]) => ids.map(id => section(id)).filter((value): value is AnalyticsSection => !!value).map(item => <details className="tm-explore-related" key={item.id}><summary>{item.title}</summary><p>{item.description}</p>{item.metrics?.map(metric => <p key={metric.id}>{metric.label}：{metric.value}</p>)}{item.rows?.length ? item.rows.map(row => <p key={row.id}>{row.restaurantID ? <button type="button" onClick={() => onOpenRestaurant(row.restaurantID!)}>{row.label} · {row.value}</button> : <>{row.label} · {row.value}</>}{row.detail ? ` · ${row.detail}` : ''}</p>) : <p>{item.emptyMessage}</p>}</details>)
  let content: ReactNode
  if (page === 'F01') content = <>
    <h2 className="tm-explore-headline">{home.headline}</h2>
    {home.frequent[0] ? <div className="tm-explore-hero"><Food name={home.frequent[0].label} /><small>最常记录 · {home.frequent[0].label}</small></div> : null}
    <div className="tm-explore-food-four">{home.frequent.slice(0, 4).map(item => <button type="button" key={item.label} onClick={() => go('F04')}><Food name={item.label} /><b>{item.label}</b><small>{item.visitCount} 次</small></button>)}</div>
    {home.habits.length ? <div className="tm-explore-habits">{home.habits.map(item => { const Icon = { time: Clock3, price: Wallet, companion: Users, city: MapPin }[item.kind]; return <button key={item.kind} type="button" onClick={() => go(({ time: 'F10', price: 'F08', companion: 'F16', city: 'F13' } as const)[item.kind])}><Icon size={20} aria-hidden /><small>{item.label}</small><b>{item.value}</b></button> })}</div> : null}
    {taste.recentComparison.changes[0] ? <button type="button" className="tm-explore-callout" onClick={() => go('F11')}><span><small>最近一个变化</small><b>{taste.recentComparison.changes[0]}</b></span><ArrowRight size={19} aria-hidden /></button> : null}
    <button className="tm-explore-primary" type="button" onClick={() => go('F02')}>查看完整分析<ArrowRight size={18} aria-hidden /></button>
    <p className="tm-explore-muted">先看重点；具体分母、记录与口径都能继续查看。</p>
  </>
  else if (page === 'F02') content = <><h2 className="tm-explore-intro">不用先读完报表。<br />选择你现在最想了解的一件事。</h2><nav aria-label="分析主题">{topics.map(([target, title, subtitle, Icon]) => <div key={target}>{link(target, title, subtitle, all, Icon)}</div>)}</nav>{link('F21', '直接查看原始记录', '带着当前时间和城市条件')}{note('各模块独立判断样本', '评分、频率、时期比较和来源质量分别执行正式分析服务的样本规则；缺失字段不填零。', all)}</>
  else if (page === 'F04') content = <><Lens value={lens} onChange={setLens} labels={['常吃与高分', '高低分条件']} />{lens === 'frequency' ? <div className="tm-explore-ranks">{[home.frequent, home.highlyRated].map((items, index) => <section key={index}><h2>{index ? '记录中的高分' : '你常常选择'}</h2>{items.slice(0, 3).map(item => <button key={item.label} type="button" onClick={() => cuisineGo(item.label)}><Food name={item.label} /><span><b>{item.label}</b><small>{index ? `${item.averageScoreOutOfTen!.toFixed(1)} 分 · ${item.ratedRestaurantCount} 家` : `${item.visitCount} 次`}</small></span></button>)}{!items.length ? <p className="tm-explore-muted">评分样本仍在积累</p> : null}</section>)}</div> : related(['high-traits', 'pitfalls', 'hidden-preferences'])}
    {link('F06', '菜品与口味', '吃过的菜品与明确记录的味道', all, Utensils)}{note('常吃按到访；高分按不同餐厅', `只取有效的个人评分，先计算每家餐厅均分，再对不同餐厅等权汇总。菜系至少 ${ANALYTICS_EVIDENCE_RULES.comparisonRatedRestaurants} 家已评分餐厅才进入高分比较。`, all)}<details className="tm-explore-related"><summary>完整菜系分布 · {home.frequent.length} 类</summary>{home.frequent.map(item => <button className="tm-explore-topic" key={item.label} type="button" onClick={() => cuisineGo(item.label)}>{item.label}<span>{item.visitCount} 次</span><ChevronRight size={16} /></button>)}</details></>
  else if (page === 'F05') {
    const cuisine = taste.cuisines.find(item => item.label === condition.cuisine)
    const ratings = analyticsRepresentativeRatings(selected)
    content = <>{facts([['你的餐厅均分', score(cuisine?.averageScoreOutOfTen)], ['已评分餐厅', ratings.length + ' 家'], ['到访记录', selected.length + ' 次']])}<h2>评分集中在哪里</h2><Bars rows={scoreBands.map(band => ({ label: band.label, count: ratings.filter(item => item.scoreOutOfTen >= band.minimum && item.scoreOutOfTen < band.maximum).length }))} unit="家" onSelect={index => openRecords({ ...condition, label: condition.label + ' · 餐厅均分 ' + scoreBands[index].label, restaurantIDs: ratings.filter(item => item.scoreOutOfTen >= scoreBands[index].minimum && item.scoreOutOfTen < scoreBands[index].maximum).map(item => item.restaurantID) })} /><h2>代表餐厅</h2>{restaurantRows(analyticsRestaurantRanking(restaurants, selected))}{link('F21', '全部相关记录', `${selected.length} 次真实用餐`, condition)}{note('到访评分 → 餐厅等权汇总', '先计算每家餐厅在当前范围内的个人均分，再对不同餐厅等权平均。评分分布也按不同餐厅统计；点击柱查看这些餐厅的原始记录。', condition, `${selected.filter(item => item.rating != null).length} 次评分 · ${ratings.length} 家餐厅`)}</>
  } else if (page === 'F06') content = <><p className="tm-explore-muted">口味来自明确标签，不由菜系自动推测</p><div className="tm-explore-flavours">{taste.snapshot.preferences.map(item => <button key={item.label} type="button" onClick={() => evidence(item.label + '口味标签', '每次到访内相同口味只计一次，除以当前全部到访数。口味可多选，不要求相加为 100%。', { label: item.label + '口味标签', taste: item.label }, item.value + '% · 当前全部 ' + visits.length + ' 次到访')}><Utensils size={25} aria-hidden /><b>{item.label}</b><strong>{item.value}%</strong></button>)}</div>{!taste.snapshot.preferences.length ? empty('还没有可靠的菜品口味标签。已有餐厅和用餐记忆仍然保留。') : null}<h2>{taste.dishes.some(item => item.count > 1) ? '反复出现在记录里的菜' : '吃过的菜'}</h2>{restaurantRows(taste.dishes)}{link('F21', '查看菜品记录', '同店、可靠菜品身份汇总；不跨餐厅按名称合并', { label: '有菜品记录', coverage: 'dishes' })}</>
  else if (page === 'F07') content = <><div className="tm-explore-money"><small>已记录个人支出</small><strong>{money(report.summary.spend.recordedVisitCount ? report.summary.spend.total : null)}</strong><p>{report.summary.spend.recordedVisitCount} / {visits.length} 次包含个人实际付款</p></div>{facts([['单次个人支出中位数', money(report.summary.spend.median)], ['中间一半记录的范围', report.summary.spend.lowerQuartile == null ? '未记录' : `${money(report.summary.spend.lowerQuartile)}–${money(report.summary.spend.upperQuartile)}`]])}<h2>支出主要在哪里</h2><Bars rows={taste.spendCategories.map(item => ({ label: item.label, count: item.amount, text: money(item.amount) }))} unit="元" onSelect={index => openRecords({ label: taste.spendCategories[index].label + '支出', spendCategory: taste.spendCategories[index].label })} />{link('F08', '常吃什么价位？', '选餐厅时看参考人均，不是付款额', all, Wallet)}{note('个人实际付款与餐厅人均分开统计', section('personal-spend')?.description ?? '', { label: '个人支出', coverage: 'spend' })}{link('F21', '查看支出记录', '不把缺失金额记为零', { label: '个人支出', coverage: 'spend' })}{related(['personal-spend-distribution'])}</>
  else if (page === 'F08') {
    const prices = taste.referenceDistribution
    const comparisonCuisine = condition.cuisine ?? home.frequent[0]?.label
    const rated = prices.map(item => ({ ...item, ratings: analyticsRepresentativeRatings(analyticsQueryRecords(restaurants, visits, { label: item.label, price: item, cuisine: comparisonCuisine })) })).filter(item => item.ratings.length >= ANALYTICS_EVIDENCE_RULES.comparisonRatedRestaurants)
    content = <><Lens value={lens} onChange={setLens} labels={['常吃价位', '高分表现']} />{lens === 'rating' ? <div className="tm-explore-person-choice" aria-label="选择价位比较菜系">{home.frequent.map(item => <button key={item.label} type="button" aria-pressed={comparisonCuisine === item.label} onClick={() => setRoute({ ...route, condition: { ...condition, cuisine: item.label } })}>{item.label}</button>)}</div> : null}{lens === 'frequency' ? <Bars rows={prices.map(item => ({ label: item.label, count: item.count }))} onSelect={index => go('F09', { label: prices[index].label, price: prices[index] })} /> : rated.length ? <Bars rows={rated.map(item => ({ label: item.label, count: analyticsAverage(item.ratings.map(row => row.scoreOutOfTen))!, text: score(analyticsAverage(item.ratings.map(row => row.scoreOutOfTen))) + ` · ${item.ratings.length} 家` }))} onSelect={index => go('F09', { label: comparisonCuisine + ' · ' + rated[index].label, price: rated[index], cuisine: comparisonCuisine })} /> : empty('各价位至少有 5 家已评分餐厅，才展示可比较的均分。')}{note('人均不是你的付款额；更贵不自动代表更好', section('reference-price')?.description ?? '', all)}</>
  } else if (page === 'F09') content = <><p className="tm-explore-condition">可靠人均 {condition.label} · {new Set(selected.map(item => item.restaurantId)).size} 家</p>{restaurantRows(analyticsRestaurantRanking(restaurants, selected).map(item => ({ ...item, detail: '本区间参考人均 ' + money(analyticsAverage(selected.filter(visit => visit.restaurantId === item.restaurantID).map(visit => visitReferencePrice(visit)!))) })), limit)}{selected.length > limit ? <button className="tm-explore-secondary" type="button" onClick={() => setLimit(limit + 20)}>继续显示餐厅</button> : null}{link('F21', '参与计算的用餐记录', '只包含选中的人均区间', condition)}</>
  else if (page === 'F10') content = <><p className="tm-explore-muted">{section('dining-times')?.description}</p><Bars rows={(section('dining-times')?.rows ?? []).map(item => ({ label: item.label, count: item.count ?? 0 }))} onSelect={index => { const time = section('dining-times')!.rows![index].label; openRecords({ label: time, time }) }} /><h2>按星期看记录节奏</h2><Bars rows={['周一', '周二', '周三', '周四', '周五', '周六', '周日'].map((label, index) => ({ label, count: visits.filter(visit => new Date(visit.visitedAt).getDay() === (index + 1) % 7).length }))} onSelect={index => openRecords({ label: '星期' + (index + 1), weekday: (index + 1) % 7 })} />{link('F11', '最近，哪里变了', '同一维度，两期对照')}{link('F20', '哪些数据参与了分析', '未记录时刻不视为夜宵')}</>
  else if (page === 'F11') content = <><p className="tm-explore-muted">最近 90 天 vs 此前 90 天 · 各 {taste.recentComparison.currentVisitCount} / {taste.recentComparison.previousVisitCount} 次记录</p>{taste.recentComparison.changes.length ? <h2 className="tm-explore-intro">{taste.recentComparison.changes[0]}</h2> : empty(taste.recentComparison.available ? '两期暂未发现达到门槛的明显变化。' : '两期样本仍在积累，暂不形成趋势结论。')}{taste.recentComparison.frequencyChanges.map(item => <button type="button" className="tm-explore-change" key={item.label} onClick={() => evidence(item.label + '记录占比变化', `最近 90 天该菜系到访数 ÷ 本期全部到访，与此前 90 天相同口径比较。${percent(item.previousShare)} → ${percent(item.currentShare)}，变化 ${Math.round(item.delta * 100)} 个百分点。只表示频率，不等于更喜欢。`, { label: item.label + '两期记录', cuisine: item.label, visitIDs: visits.filter(visit => Date.parse(visit.visitedAt) >= Date.parse(taste.recentComparison.previousStart)).map(visit => visit.id) })}><b>{item.label}</b><span>{percent(item.previousShare)} → {percent(item.currentShare)}</span><i style={{ width: percent(Math.max(item.previousShare, item.currentShare)) }} /></button>)}{link('F12', '看更长的轨迹', '查看时间跨度内的实际记录')}{note('两期样本量和日期范围', `本期从 ${new Date(taste.recentComparison.currentStart).toLocaleDateString()} 至报告生成时间；前期从 ${new Date(taste.recentComparison.previousStart).toLocaleDateString()} 至本期开始前。频率比较每期至少 10 次到访、5 家餐厅；评分比较每期至少 5 家已评分餐厅。`, { label: '两期记录', visitIDs: visits.filter(visit => Date.parse(visit.visitedAt) >= Date.parse(taste.recentComparison.previousStart)).map(visit => visit.id) })}</>
  else if (page === 'F12') content = <><p className="tm-explore-muted">按自然月展示常见菜系的记录占比；空月没有曲线，不推断未记录的生活。</p><Timeline report={report} onRecords={openRecords} />{note('查看每期样本、类别占比与原始记录', '每个自然月内，该菜系到访次数除以该月全部到访次数。菜系多选，比例不相加；频率与评分不共用坐标轴。', all)}</>
  else if (page === 'F13') content = <><h2 className="tm-explore-intro">在 {report.summary.cityCount} 个已记录城市，留下 {report.summary.restaurantCount} 家餐厅的记忆。</h2>{analyticsCities(restaurants, visits).map(item => <button className="tm-explore-topic" key={item.id} type="button" onClick={() => openRecords({ label: item.label, city: item.label })}><span className="tm-explore-topic__icon"><MapPin size={22} aria-hidden /></span><span><strong>{item.label}</strong><small>{item.restaurantCount} 家餐厅 · {item.count} 次用餐</small></span><ChevronRight size={16} aria-hidden /></button>)}{link('F14', '新发现与再回去', '探索和回访，分开看')}{link('F15', '你的代表餐厅', '不同的入选理由，不混成一个总榜')}</>
  else if (page === 'F14') {
    const first = new Set(report.firstVisitIDs); const firstIDs: string[] = [], repeatIDs: string[] = []
    for (const visit of visits) { if (first.has(visit.id)) firstIDs.push(visit.id); else repeatIDs.push(visit.id) }
    content = <><p className="tm-explore-muted">当前范围内的首次记录与回访互斥统计；首次身份由完整历史核对。</p><div className="tm-explore-ring-layout"><div className="tm-explore-ring" style={{ background: visits.length ? `conic-gradient(var(--tm-explore-warm) 0 ${percent(firstIDs.length / visits.length)}, var(--brand) 0)` : 'var(--line)' }}><span><strong>{visits.length}</strong>次用餐</span></div><div><button type="button" onClick={() => openRecords({ label: '首次记录餐厅', visitIDs: firstIDs })}>{firstIDs.length} 次首次记录</button><button type="button" onClick={() => openRecords({ label: '回访记录', visitIDs: repeatIDs })}>{repeatIDs.length} 次回访</button></div></div>{facts([['去过餐厅', report.summary.restaurantCount + ' 家'], ['有回访记录的餐厅', new Set(visits.filter(visit => !first.has(visit.id)).map(visit => visit.restaurantId)).size + ' 家']])}{restaurantRows(report.evidenceRestaurants.filter(item => item.count > 1))}{link('F15', '你的代表餐厅', '不同的入选理由')}{note('回访店数和回访次数不是同一个指标', '回访店数：本范围内存在回访记录的不同餐厅。回访次数：原始完整历史中不是该餐厅首次记录、且位于当前范围的到访数。首次记录不等于人生第一次去过。', all)}</>
  } else if (page === 'F15') content = <>{restaurantRows(taste.representativeRestaurants, 3)}{link('F21', '全部餐厅记录', '保留所有原始到访')}{note('每家餐厅都有明确的入选理由', section('restaurant-roles')?.description ?? '', all)}{related(['top-restaurants', 'restaurant-roles'])}</>
  else if (page === 'F16') content = <><Lens value={lens} onChange={setLens} labels={['共同经历', '用餐场景']} /><div className="tm-explore-person-choice" aria-label="选择饭搭子">{report.companion?.companions.map(person => <button key={person.id} type="button" aria-pressed={person.id === (route.entity ?? report.companion?.companions[0]?.id)} onClick={() => setRoute({ ...route, entity: person.id })}>{person.displayName}</button>)}</div>{lens === 'frequency' ? <>{report.companion?.companions.filter(person => person.id === (route.entity ?? report.companion?.companions[0]?.id)).map(person => <section key={person.id} className="tm-explore-person"><h2>{person.displayName}</h2><p>{person.sharedVisitCount} 次共同用餐 · {person.restaurantCount} 家餐厅</p><p>你给这些共同用餐的均分 {score(person.ratingAverage)}</p>{restaurantRows(person.restaurants)}<button type="button" className="tm-explore-secondary" onClick={() => openRecords({ label: `与${person.displayName}的共同记录`, visitIDs: person.visitIDs })}>查看共同记录</button></section>)}{!report.companion?.companions.length ? empty('尚无可核验身份的饭搭子记录；不从姓名猜测关系。') : null}</> : <>{related(['companion-context', 'scenes'])}</>}{link('F17', '哪些来源更合口味', '推荐来源与实际体验', all, Users)}{note('只描述同行记录，不衡量关系亲疏', '均分仅来自你自己的评分；多人同行不是互斥分类，不能相加成 100%。独自／同行与到店／外卖是不同维度。', all)}</>
  else if (page === 'F19') content = <>{facts([['平均评分', score(taste.ratingBehavior.average)], ['评分中位数', score(taste.ratingBehavior.median)]])}<Bars rows={scoreBands.map(band => ({ label: band.label, count: analyticsQueryRecords(restaurants, visits, { label: band.label, score: band }).length }))} onSelect={index => openRecords({ label: scoreBands[index].label, score: scoreBands[index] })} /><p className="tm-explore-muted">{visits.length - report.summary.ratedVisitCount} 次未评分，不计为 0 分。不根据打分习惯给你贴人格标签。</p>{link('F20', '哪些数据参与了分析', '按模块查看实际覆盖')}{note('评分统计来自你的有效到访评分', '均分和中位数以当前范围有效到访评分计算，十分制；不包含未评分。此处分布按到访计，与菜系详情按餐厅计的分布不同。', { label: '有效评分', coverage: 'rated' })}</>
  else if (page === 'F20') content = <>{([['rated', '个人评分'], ['spend', '个人支出'], ['time', '可靠用餐时刻'], ['companion', '明确同行或独自'], ['source', '推荐来源类型']] as const).map(([coverage, label]) => { const count = analyticsQueryRecords(restaurants, visits, { label, coverage }).length; return <button type="button" key={coverage} className="tm-explore-coverage" onClick={() => openRecords({ label, coverage })}><span>{label}<b>{count} / {visits.length}</b></span><i><em style={{ width: percent(visits.length ? count / visits.length : 0) }} /></i></button> })}<div className="tm-explore-empty"><h2>有记录，不代表每种分析都成熟</h2><p>近期变化、菜系评分与来源质量各自需要相应样本；会员不能补足缺失事实。</p></div>{link('F21', '查看已有记录', '原始内容完整保留')}{link('F23', '样本不足时', '仍然有真实记忆可看')}</>
  else if (page === 'F21') content = <><p className="tm-explore-condition">{condition.label} · {selected.length} 次记录</p><label className="tm-explore-search"><Search size={18} aria-hidden /><input aria-label="搜索原始记录餐厅" placeholder="搜索餐厅" value={search} onChange={event => { setSearch(event.target.value); setLimit(20) }} /></label>{records.slice().reverse().slice(0, limit).map(visit => <button type="button" className="tm-explore-record" key={visit.id} onClick={() => onOpenVisit(visit.id)}><Food name={byID.get(visit.restaurantId)?.name ?? '餐厅'} tags={byID.get(visit.restaurantId)?.tags} /><span><strong>{byID.get(visit.restaurantId)?.name}</strong><small>{new Date(visit.visitedAt).toLocaleDateString()} · {analyticsMealTime(visit) ?? '未记录时刻'} · {visit.visibility === 'private' ? '仅自己' : visit.visibility === 'public' ? '公开' : '限定可见'}</small>{visit.note ? <p>{visit.note}</p> : null}</span><b>{score(visit.rating == null ? null : visit.rating * 2)}</b><ChevronRight size={14} /></button>)}{records.length > limit ? <button className="tm-explore-secondary" type="button" onClick={() => setLimit(limit + 20)}>继续显示 · 已展示 {limit}/{records.length}</button> : null}{!records.length ? <p className="tm-explore-muted">当前条件下没有记录。</p> : null}</>
  else content = <>{empty('暂时不生成强结论，也不补造数据。你已经留下的用餐记录仍然值得回看。')}{restaurantRows(report.evidenceRestaurants)}{link('F21', '回看已有记录', '在现有到访详情中补充真实信息')}</>
  if (page === 'F17' || page === 'F18') return <RecommendationSourceExplorer report={report} onOpenVisit={onOpenVisit} onOpenRestaurant={onOpenRestaurant} onPoster={onSourcePoster ?? onPoster} registerBack={registerSourceBack} />
  return <article ref={root} className="tm-analysis-data tm-taste-explorer" data-explore-page={page} data-analysis-view={page === 'F01' ? 'home' : 'details'} aria-label="我的口味档案数据报告">
    <div className="tm-explore-tools"><span>个人食味档案</span><button type="button" aria-label="筛选这份档案" onClick={() => { setDraft(filter); setSheet('filter') }}><SlidersHorizontal size={20} /></button><button type="button" aria-label="分享口味名片" onClick={onPoster}><Share2 size={20} /></button></div>
    <header className="tm-explore-title"><h1>{page === 'F05' ? condition.cuisine : titles[page]}</h1><p>{page === 'F01' ? `${report.summary.visitCount} 次到访 · ${report.summary.restaurantCount} 家餐厅` : report.scope.periodLabel}</p></header>{content}
    {sheet === 'filter' ? <ModalShell title="筛选这份档案" eyebrow={null} onClose={() => setSheet(null)} backdropClassName="tm-explore-sheet"><div className="tm-explore-filter"><h3>时间范围</h3><div className="tm-explore-options">{([90, 365, undefined] as const).map(days => <button type="button" key={days ?? 'all'} aria-pressed={draft.days === days} onClick={() => setDraft({ ...draft, days })}>{days === 90 ? '最近90天' : days === 365 ? '最近一年' : '全部历史'}</button>)}</div><label>城市<input value={draft.city ?? ''} placeholder="全部城市" onChange={event => setDraft({ ...draft, city: event.target.value })} /></label><p>取消不应用；应用后保留当前页面与浏览位置。</p><div className="tm-explore-actions"><button className="tm-explore-secondary" type="button" onClick={() => setDraft({})}>重置</button><button className="tm-explore-primary" type="button" onClick={() => { onFilter({ ...draft, city: draft.city?.trim() || undefined }); setSheet(null) }}>应用条件</button></div></div></ModalShell> : sheet ? <ModalShell title="这条结论如何得出" eyebrow={null} onClose={() => setSheet(null)} backdropClassName="tm-explore-sheet"><h3>{sheet.title}</h3><p>{report.scope.periodLabel}</p><p>{sheet.sample ?? `${analyticsQueryRecords(restaurants, visits, sheet.condition).length} 次参与记录`}</p><p className="tm-explore-formula">{sheet.formula}</p><p>只描述已记录的体验，不代表全部现实用餐。</p><button type="button" className="tm-explore-primary" onClick={() => { openRecords(sheet.condition); setSheet(null) }}>查看参与计算的记录<ArrowRight size={18} /></button></ModalShell> : null}
  </article>
}

function Food({ name, tags }: { name: string; tags?: string[] }) { return <FoodLibraryArtwork name={name} tags={tags ?? [name]} categoryVisualID={resolveFoodCategoryVisualID({ name, tags: tags ?? [name] })} /> }
function Lens({ value, onChange, labels }: { value: string; onChange: (value: string) => void; labels: [string, string] }) { return <div className="tm-explore-lens" role="group" aria-label="查看视角">{labels.map((label, index) => <button type="button" key={label} aria-pressed={value === (index ? 'rating' : 'frequency')} onClick={() => onChange(index ? 'rating' : 'frequency')}>{label}</button>)}</div> }
function Bars({ rows, onSelect, unit = '次' }: { rows: { label: string; count: number; text?: string }[]; onSelect: (index: number) => void; unit?: string }) {
  const max = Math.max(1, ...rows.map(item => item.count))
  return <div className="tm-explore-bars" aria-label="可查看对应记录的分布图">{rows.map((row, index) => <button type="button" key={row.label} onClick={() => onSelect(index)} aria-label={`${row.label}：${row.text ?? row.count + unit}，查看对应记录`}><b>{row.text ?? row.count + unit}</b><span><i style={{ height: (row.count / max * 100) + '%' }} /></span><small>{row.label}</small></button>)}</div>
}
function Timeline({ report, onRecords }: { report: AnalyticsReport; onRecords: (condition: AnalyticsRecordCondition) => void }) {
  const now = new Date(report.generatedAt)
  const endMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1)
  const periods = Array.from({ length: 4 }, (_, index) => {
    const start = new Date(endMonth.getFullYear(), endMonth.getMonth() - 12 + index * 3, 1)
    const end = new Date(start.getFullYear(), start.getMonth() + 3, 1)
    return { label: `${start.getFullYear()}.${start.getMonth() + 1}—${new Date(end.getTime() - 1).getMonth() + 1}`,
      visits: report.scopedVisits.filter(visit => Date.parse(visit.visitedAt) >= start.getTime() && Date.parse(visit.visitedAt) < end.getTime()) }
  })
  const categories = report.taste!.frequent.slice(0, 3)
  const colors = ['var(--brand,#6b8faa)', 'var(--tm-explore-warm)', '#87a58e']
  const points = categories.map(category => periods.map((period, index) => {
    const count = analyticsQueryRecords(report.scopedRestaurants, period.visits, { label: category.label, cuisine: category.label }).length
    return { x: 38 + index * 90, y: 198 - (period.visits.length ? count / period.visits.length * 160 : 0), count,
      share: period.visits.length ? percent(count / period.visits.length) : '无记录', available: period.visits.length > 0 }
  }))
  return <div className="tm-explore-timeline"><p className="tm-explore-muted">最近 12 个自然月，分四期；每期三个月，末期截至今天。只画实际频率，不生成稳定指数。</p>
    <svg viewBox="0 0 350 236" role="img" aria-label="四期菜系频率变化">
      {[0, 50, 100].map(value => <g key={value}><path d={`M30 ${198 - value * 1.6}H326`} stroke="var(--line,#dce5e8)" /><text x="0" y={202 - value * 1.6} fontSize="10" fill="currentColor">{value}%</text></g>)}
      {points.map((values, categoryIndex) => <g key={categories[categoryIndex].label}>{values.map((point, index) => <g key={index}>
        {index > 0 && point.available && values[index - 1].available ? <path d={`M${values[index - 1].x} ${values[index - 1].y}L${point.x} ${point.y}`} stroke={colors[categoryIndex]} strokeWidth="2" fill="none" /> : null}
        {point.available ? <circle cx={point.x} cy={point.y} r="4" fill={colors[categoryIndex]} /> : null}
      </g>)}</g>)}
      {periods.map((period, index) => <text key={period.label} x={38 + index * 90} y="228" textAnchor="middle" fontSize="10" fill="currentColor">第{index + 1}期</text>)}
    </svg>
    <div className="tm-explore-timeline-legend">{categories.map((item, index) => <span key={item.label}><i style={{ background: colors[index] }} />{item.label}</span>)}</div>
    {periods.map((period, index) => <details className="tm-explore-related" key={period.label}><summary>{period.label} · {period.visits.length} 次</summary>{categories.map((category, categoryIndex) => <button key={category.label} type="button" className="tm-explore-coverage" onClick={() => onRecords({ label: `${period.label} · ${category.label}`, cuisine: category.label, visitIDs: period.visits.map(visit => visit.id) })}><span>{category.label}<b>{points[categoryIndex][index].share} · {points[categoryIndex][index].count} 次</b></span></button>)}</details>)}
  </div>
}
