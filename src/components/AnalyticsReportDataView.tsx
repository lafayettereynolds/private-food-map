import { ArrowLeft, ArrowRight, ChevronRight, Clock3, MapPin, Users, Wallet, Sparkles } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import type { AnalyticsMode, AnalyticsSection, AnalyticsReportSummary, AnalyticsRestaurantEvidence, AnalyticsRow } from '../services/analyticsReportTypes'
import type { AnalyticsReport } from '../services/analyticsReport'
import { analyticsReportHome, analyticsDetailTopics } from '../services/analyticsReportHome'
import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { FoodLibraryArtwork } from '../visuals/FoodLibraryArtwork'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import type { AnalysisVisualRef } from '../types/analysisShare'
import type { buildAnalyticsSourceReport } from '../services/analyticsSocialReport'
import './analyticsReportData.css'

export function AnalysisEvidenceImage({ visual, name, tags }: { visual?: AnalysisVisualRef; name: string; tags?: string[] }) {
  const [failed, setFailed] = useState(false)
  useEffect(() => setFailed(false), [visual?.source])
  return visual?.source && visual.origin === 'visit' && !failed
    ? <img className="tm-hybrid-restaurant-image" src={visual.source} alt={name + ' · 本报告到访实拍'} onError={() => setFailed(true)} />
    : <FoodLibraryArtwork className="tm-hybrid-restaurant-image" name={name} tags={visual?.tags ?? tags} categoryVisualID={resolveFoodCategoryVisualID({ name, tags: visual?.tags ?? tags })} />
}

export function AnalyticsReportDataView({ mode, title, headline, period, summary, sections, evidence, profile, onOpenRestaurant, source, visualEvidence, report, initialSourceID, onSelectSource, onReturnHome }: {
  mode: AnalyticsMode; title: string; headline: string; period: string; summary: AnalyticsReportSummary
  sections: AnalyticsSection[]; evidence: AnalyticsRestaurantEvidence[]
  profile: TasteMapProfileDashboardViewModel; onOpenRestaurant: (id: string) => void
  source?: ReturnType<typeof buildAnalyticsSourceReport> | null
  visualEvidence?: Record<string, AnalysisVisualRef>; report?: AnalyticsReport
  initialSourceID?: string; onSelectSource?: (id: string) => void; onReturnHome?: () => void
}) {
  const home = report ? analyticsReportHome(report) : null
  const [view, setView] = useState<'home' | 'details'>('home')
  const [lens, setLens] = useState<'frequent' | 'rated'>('frequent')
  const [sectionID, setSectionID] = useState(sections[0]?.id ?? '')
  const [customSection, setCustomSection] = useState<AnalyticsSection | null>(null)
  const heading = useRef<HTMLHeadingElement>(null)
  const detailSections: AnalyticsSection[] = [...sections, ...(source ? [{ id: 'source-pitfalls', title: '最坑推荐来源', description: '仅比较达到样本门槛的来源。踩坑以低于个人首次体验评分基线的真实结果判断；并不评价推荐者本人。', rows: source.pitfallRanking.map(item => ({ id: item.id, label: item.displayName, value: Math.round(item.lowRatingRate! * 100) + '%', detail: item.lowRatingCount + '/' + item.ratedRestaurantCount + ' 家低于个人基线；点击查看该来源的餐厅。' })), emptyMessage: '暂时没有达到门槛的低分来源。' }] : [])]
  const topics = analyticsDetailTopics(detailSections)
  const activeSection = customSection ?? detailSections.find(item => item.id === sectionID)
  const activeTopic = topics.find(topic => topic.sections.some(section => section.id === sectionID))
  const go = (id: string, custom: AnalyticsSection | null = null) => {
    setSectionID(id); setCustomSection(custom); setView('details')
    requestAnimationFrame(() => { heading.current?.scrollIntoView({ block: 'start' }); heading.current?.focus({ preventScroll: true }) })
  }
  const image = (item: AnalyticsRow) => <AnalysisEvidenceImage visual={item.restaurantID ? visualEvidence?.[item.restaurantID] : undefined} name={item.label} tags={profile.restaurants.find(restaurant => restaurant.id === item.restaurantID)?.tags} />
  const categories = (lens === 'frequent' ? home?.frequent : home?.highlyRated)?.slice(0, 4) ?? []
  const cuisine = categories[0]
  const photos = evidence.filter(item => visualEvidence?.[item.restaurantID]?.origin === 'visit').slice(0, 4)
  const collage = (photos.length ? photos : evidence).slice(0, mode === 'companion' ? 3 : 4)
  const feature = home?.feature
  const habitIcons = { time: Clock3, price: Wallet, companion: Users, city: MapPin }
  const sourceDetail = (id: string) => {
    if (id !== source?.selectedSourceID && onSelectSource) { onSelectSource(id); return }
    const item = source?.sources.find(value => value.id === id)
    if (!item) return
    go('source-detail', { id: 'source:' + id, title: item.displayName, description: '以来源归因明确的首次体验为单位；高分为 8 分及以上，未评分不填零。', metrics: [
      { id: 'sample', label: '已验证且评分餐厅', value: item.ratedRestaurantCount + ' 家' },
      { id: 'high', label: '高分占比', value: item.highRatingRate == null ? '暂无评分' : Math.round(item.highRatingRate * 100) + '%', note: item.highRatingCount + '/' + item.ratedRestaurantCount + ' 家' },
      { id: 'low', label: '低于个人基线', value: item.lowRatingCount + '/' + item.ratedRestaurantCount + ' 家' },
      { id: 'average', label: '你给首次体验的均分', value: item.averageScoreOutOfTen == null ? '未评分' : item.averageScoreOutOfTen.toFixed(1) + ' / 10' },
    ], rows: item.restaurants })
  }
  useEffect(() => {
    if (initialSourceID && source?.selectedSourceID === initialSourceID) sourceDetail(initialSourceID)
    // The parent report key remounts this view on a new source snapshot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialSourceID, source?.selectedSourceID])
  return <article className="tm-analysis-data" data-analysis-view={view} data-report-state={report?.dataState} aria-label={title + '数据报告'}>
    <header className="tm-analysis-data__intro"><h1 ref={heading} tabIndex={-1}>{view === 'home' ? title : '完整分析'}</h1><p>{period}</p></header>
    {view === 'home' ? <>
      <section className="tm-analysis-story__lead" aria-label="核心结论"><h2>{home?.headline ?? headline}</h2><p>{home?.subtitle ?? '基于 ' + summary.visitCount + ' 次用餐记录 · ' + summary.restaurantCount + ' 家餐厅'}</p></section>
      {summary.visitCount > 0 && mode === 'taste' && home ? <>
        <div className="tm-analysis-story__lens" role="group" aria-label="菜系查看视角"><button type="button" aria-pressed={lens === 'frequent'} onClick={() => setLens('frequent')}>常吃</button><button type="button" aria-pressed={lens === 'rated'} onClick={() => setLens('rated')}>高分</button></div>
        {cuisine ? <div className="tm-analysis-story__hero"><FoodLibraryArtwork name={cuisine.label} tags={[cuisine.label]} categoryVisualID={resolveFoodCategoryVisualID({ name: cuisine.label, tags: [cuisine.label] })} /><span>{cuisine.label} · {lens === 'frequent' ? '记录最多的类型' : '已评分均分更高的类型'}</span></div> : <p className="tm-analysis-data__empty">可比较的餐厅评分样本仍在积累；尚未评分不会被填成零分。</p>}
        <div className="tm-analysis-story__categories">{categories.map(item => <button type="button" key={item.label} onClick={() => go('cuisines', { id: 'cuisine:' + item.label, title: item.label, description: item.visitCount + ' 次到访 · ' + item.restaurantCount + ' 家餐厅 · ' + item.ratedVisitCount + ' 次有效评分。' + (sections.find(section => section.id === 'cuisines')?.description ?? ''), rows: evidence.filter(row => visualEvidence?.[row.restaurantID]?.tags?.includes(item.label)), metrics: [{ id: 'value', label: lens === 'frequent' ? '常吃次数' : '个人平均评分', value: lens === 'frequent' ? item.visitCount + ' 次' : item.averageScoreOutOfTen!.toFixed(1) + ' / 10' }] })}><FoodLibraryArtwork name={item.label} tags={[item.label]} categoryVisualID={resolveFoodCategoryVisualID({ name: item.label, tags: [item.label] })} /><span>{item.label}</span><strong>{lens === 'frequent' ? item.visitCount + ' 次' : item.averageScoreOutOfTen!.toFixed(1) + ' / 10'}</strong></button>)}</div>
        {home.habits.length ? <div className="tm-analysis-story__habits" aria-label="用餐习惯">{home.habits.map(item => { const Icon = habitIcons[item.kind]; return <button key={item.kind} type="button" onClick={() => go(item.sectionID)}><Icon size={21} aria-hidden /><span>{item.label}</span><strong>{item.value}</strong></button> })}</div> : null}
      </> : null}
      {summary.visitCount > 0 && (mode === 'monthly' || mode === 'annual' || mode === 'companion') ? <div className={'tm-analysis-story__collage tm-analysis-story__collage--' + mode} aria-label={mode === 'companion' ? '共同用餐记忆' : '本期用餐记忆'}>{collage.map(item => <button key={item.restaurantID} type="button" onClick={() => onOpenRestaurant(item.restaurantID)}>{image(item)}<span>{item.label}</span></button>)}{!collage.length ? <FoodLibraryArtwork name="用餐记忆" /> : null}</div> : null}
      {home?.facts.length ? <dl className="tm-analysis-story__facts">{home.facts.map(item => <div key={item.label}><dt>{item.label}</dt><dd>{item.value}</dd></div>)}</dl> : null}
      {mode === 'source' ? <section className="tm-analysis-story__sources" aria-label="合格推荐来源前三名">{home?.sourceLeaders.map((item, index) => <button key={item.id} type="button" onClick={() => sourceDetail(item.id)}><span className="tm-analysis-story__rank">{index + 1}</span><span className="tm-analysis-story__source-icon"><Users size={23} aria-hidden /></span><span><strong>{item.displayName}</strong><b>{Math.round(item.highRatingRate! * 100)}% 高分占比</b><small>{item.highRatingCount}/{item.ratedRestaurantCount} 家 · 已验证且评分</small></span><ChevronRight size={17} aria-hidden /></button>)}{!home?.sourceLeaders.length ? <p className="tm-analysis-data__empty">至少验证并评分 5 家餐厅的来源才参与比较；合格来源还需有高分体验。</p> : <p className="tm-analysis-data__sample">高分为你的首次体验 ≥ 8 分；排名同时考虑样本可靠度。</p>}<button className="tm-analysis-data__restaurant-link" type="button" onClick={() => go('source-pitfalls')}>最坑推荐来源<ArrowRight size={17} aria-hidden /></button></section> : null}
      {mode === 'companion' && home?.memories.length ? <section className="tm-analysis-story__memories"><h2>{home.memories.every(item => item.count > 1) ? '一起回去过' : '一起吃过'}</h2><div>{home.memories.map(item => <button key={item.restaurantID} type="button" onClick={() => onOpenRestaurant(item.restaurantID)}>{image(item)}<span>{item.label}</span></button>)}</div></section> : feature ? <button className="tm-analysis-story__feature" type="button" aria-label={'重点发现：' + feature.title} onClick={() => feature.row.restaurantID ? onOpenRestaurant(feature.row.restaurantID) : go(feature.sectionID)}><span><small><Sparkles size={14} aria-hidden />{feature.title}</small><strong>{feature.row.label}</strong><p>{feature.row.detail || feature.row.value}</p></span>{feature.row.restaurantID ? image(feature.row) : <ChevronRight size={19} aria-hidden />}</button> : null}
      {!summary.visitCount && mode !== 'source' ? <p className="tm-analysis-data__empty">这段范围还没有可分析的记录。保留真实空白，不补造人物、照片或结论。</p> : null}
      <button className="tm-analysis-story__cta" type="button" onClick={() => go(sections[0]?.id ?? '')}>{home?.cta ?? '查看完整分析'}<ArrowRight size={18} aria-hidden /></button>
    </> : <>
      <button className="tm-analysis-data__restaurant-link" type="button" onClick={() => { setView('home'); setCustomSection(null); onReturnHome?.(); requestAnimationFrame(() => heading.current?.scrollIntoView({ block: 'start' })) }}><ArrowLeft size={17} aria-hidden />返回报告首页</button>
      <nav className="tm-analysis-detail__topics" aria-label="分析主题">{topics.map(topic => <button key={topic.id} type="button" aria-pressed={!customSection && activeTopic?.id === topic.id} onClick={() => go(topic.sections[0].id)}>{topic.title}</button>)}<button type="button" aria-pressed={sectionID === 'all-evidence'} onClick={() => go('all-evidence')}>原始记录</button></nav>
      {!customSection && activeTopic ? <label className="tm-analysis-detail__select">查看章节<select value={sectionID} onChange={event => go(event.target.value)}>{activeTopic.sections.map(section => <option key={section.id} value={section.id}>{section.title}</option>)}</select></label> : null}
      {activeSection ? <AnalysisDetailSection key={activeSection.id} section={activeSection} onOpenRestaurant={onOpenRestaurant} onOpenRow={['source-comparison', 'source-pitfalls'].includes(activeSection.id) ? row => sourceDetail(row.id) : undefined} /> : null}
      {sectionID === 'all-evidence' ? <AnalysisDetailSection section={{ id: 'original-records', title: '参与本报告的原始记录', description: `当前报告范围内 ${summary.visitCount} 次用餐，按日期倒序。点击可打开餐厅的到访历史。`, rows: report?.recordEvidence ?? evidence }} onOpenRestaurant={onOpenRestaurant} /> : null}
    </>}
  </article>
}

function AnalysisDetailSection({ section, onOpenRestaurant, onOpenRow }: { section: AnalyticsSection; onOpenRestaurant: (id: string) => void; onOpenRow?: (row: AnalyticsRow) => void }) {
  const [expanded, setExpanded] = useState(false)
  const rows = section.rows ?? []
  const chart = /^(?:cuisines|.*-cuisines)$|dish-tastes|dining-times|reference-price|spend-distribution|period-time/.test(section.id)
  const visible = expanded ? rows : rows.slice(0, 12)
  const maximum = Math.max(1, ...rows.map(row => row.share ?? row.count ?? 0))
  return <section className="tm-analysis-data__section" data-analysis-section={section.id}><h2>{section.title}</h2>
    {section.description ? <p className="tm-analysis-data__description">{section.description}</p> : null}
    {section.metrics?.length ? <dl className="tm-analysis-data__metrics">{section.metrics.map(metric => <div key={metric.id}><dt>{metric.label}</dt><dd>{metric.value}</dd>{metric.note ? <p>{metric.note}</p> : null}</div>)}</dl> : null}
    {chart ? <div className="tm-analysis-detail__bars" role="img" aria-label={rows.map(row => row.label + '：' + row.value).join('；')}>{visible.map(row => <div key={row.id}><strong>{row.share != null ? Math.round(row.share * 100) + '%' : (row.count ?? 0) + ' 次'}</strong><span><i style={{ height: ((row.share ?? row.count ?? 0) / maximum * 100) + '%' }} /></span><small>{row.label}</small></div>)}</div> : null}
    {(!chart || expanded) ? visible.map(row => { const content = <><span className="tm-analysis-data__row-copy"><span>{row.label}</span>{row.detail ? <p>{row.detail}</p> : null}{row.scoreOutOfTen != null ? <p>你的评分 {row.scoreOutOfTen.toFixed(1)} / 10</p> : null}</span>{row.value ? <strong>{row.value}</strong> : null}{row.restaurantID || onOpenRow ? <ChevronRight size={16} aria-hidden /> : null}</>; return row.restaurantID || onOpenRow ? <button className="tm-analysis-data__row" type="button" key={row.id} onClick={() => row.restaurantID ? onOpenRestaurant(row.restaurantID) : onOpenRow?.(row)}>{content}</button> : <div className="tm-analysis-data__row" key={row.id}>{content}</div> }) : null}
    {(rows.length > 12 || chart) ? <button className="tm-analysis-data__restaurant-link" type="button" aria-expanded={expanded} onClick={() => setExpanded(!expanded)}>{expanded ? '收起明细' : '查看全部 ' + rows.length + ' 项明细'}</button> : null}
    {!rows.length && !section.metrics?.length ? <p className="tm-analysis-data__empty">{section.emptyMessage ?? '记录仍在积累。'}</p> : null}
  </section>
}
