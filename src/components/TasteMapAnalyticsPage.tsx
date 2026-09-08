import { useEffect, useMemo, useRef, useState } from 'react'
import { BarChart3, Download, Image, Share2 } from 'lucide-react'
import { PremiumFeatureLabel } from './PremiumFeatureLabel'
import { usePremiumAccess } from './PremiumAccess'
import { openPremiumPaywall } from '../services/premiumPaywall'
import type { MembershipFeature } from '../services/featurePolicy'
import type { AnalysisShareData } from '../types/analysisShare'
import type { TasteMapPlatform, TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { renderAnalysisPosterBlob, downloadAnalysisPoster, shareAnalysisPoster } from '../services/analysisPosterRenderer'
import { buildAnalyticsReport } from '../services/analyticsReport'
import { analyticsReportOwnerPosterData, analyticsReportShareData, analyticsReportShareText } from '../services/analyticsReportShare'
import { HybridBackButton, HybridPageHeader, HybridState } from './TasteMapHybridShared'
import { HYBRID_ANALYTICS_MODES, HYBRID_ANALYTICS_MODULES } from '../hybrid/app/HybridProductContracts'
import { ZoomablePosterPreview } from './ZoomablePosterPreview'
import { AnalyticsReportDataView } from './AnalyticsReportDataView'
import { TasteProfileExplorer } from './TasteProfileExplorer'
import { RecommendationSourceExplorer } from './RecommendationSourceExplorer'
import { PeriodMemoryExplorer } from './PeriodMemoryExplorer'
import { MemoryPoster } from './MemoryPoster'
import { analyticsMemoryShareData } from '../services/analyticsMemoryShare'
import { getAnalyticsReadingFilter, setAnalyticsReadingFilter, type AnalyticsExploreFilter } from '../services/analyticsExploreQuery'

export type AnalyticsMode = 'taste' | 'companion' | 'source' | 'monthly' | 'annual'
type AnalyticsModule = 'data' | 'poster'
// IDs and period only; no record snapshot survives a route handoff.
let readingPeriod: { owner: string; year: number; month: number } | undefined

export function TasteMapAnalyticsPage({ platform, profile, onOpenRestaurant, initialMode = 'taste', singleReport = false, onBack }: { platform: TasteMapPlatform; profile: TasteMapProfileDashboardViewModel; onOpenRestaurant: (id: string) => void; initialMode?: AnalyticsMode; singleReport?: boolean; onBack?: () => void }) {
  const premium = usePremiumAccess()
  const [mode, setMode] = useState<AnalyticsMode>(initialMode)
  const [module, setModule] = useState<AnalyticsModule>('data')
  const [posterAudience, setPosterAudience] = useState<'owner' | 'share'>('owner')
  // A refreshed owner snapshot gets a fresh as-of clock; switching presentation does not.
  const now = useMemo(() => new Date(), [profile])
  const [year, setYear] = useState(readingPeriod?.owner === profile.user.id ? readingPeriod.year : now.getFullYear())
  const [month, setMonth] = useState(readingPeriod?.owner === profile.user.id ? readingPeriod.month : now.getMonth() + 1)
  const [companionID, setCompanionID] = useState<string | undefined>()
  const sourceFromTaste = useRef(false)
  const [sourceFilter, setSourceFilter] = useState<AnalyticsExploreFilter>({})
  const [sourcePoster, setSourcePoster] = useState(false)
  const [sourceID, setSourceID] = useState<string | undefined>()
  const [dataSourceDetailID, setDataSourceDetailID] = useState<string | undefined>()
  const [tasteFilter, setTasteFilter] = useState<AnalyticsExploreFilter>(() => getAnalyticsReadingFilter(profile.user.id))
  const filterOwner = useRef(profile.user.id)
  useEffect(() => { readingPeriod = { owner: profile.user.id, year, month } }, [profile.user.id, year, month])
  const applyTasteFilter = (value: AnalyticsExploreFilter) => { setAnalyticsReadingFilter(profile.user.id, value); setTasteFilter(value) }
  useEffect(() => { if (filterOwner.current !== profile.user.id) { filterOwner.current = profile.user.id; applyTasteFilter({}); setYear(now.getFullYear()); setMonth(now.getMonth() + 1); setSourceFilter({}); setSourcePoster(false); sourceFromTaste.current = false } }, [profile.user.id])
  const memoryShare = useRef<(() => void) | null>(null)
  const registerMemoryShare = useRef((handler: (() => void) | null) => { memoryShare.current = handler }).current
  const explorerBack = useRef<(() => boolean) | null>(null)
  const registerExplorerBack = useRef((handler: (() => boolean) | null) => { explorerBack.current = handler }).current
  const [sharing, setSharing] = useState(false)
  const sharingRef = useRef(false)
  const [shareError, setShareError] = useState<string | null>(null)
  const [poster, setPoster] = useState<{ data: AnalysisShareData; blob: Blob; url: string } | null>(null)
  const [posterError, setPosterError] = useState(false)
  const [posterAttempt, setPosterAttempt] = useState(0)
  useEffect(() => { setMode(initialMode); setModule('data') }, [initialMode])
  useEffect(() => { setCompanionID(undefined); setSourceID(undefined); setDataSourceDetailID(undefined); setShareError(null); setPosterAudience('owner') }, [profile.user.id])
  const report = useMemo(() => buildAnalyticsReport(profile, { mode, now, year, month, companionID, sourceID, filter: mode === 'taste' ? tasteFilter : mode === 'source' ? sourceFilter : undefined }), [profile, mode, now, year, month, companionID, sourceID, tasteFilter, sourceFilter])
  // F24 rebuilds from public records, not a private snapshot with names hidden.
  const memoryV2 = mode === 'source' || mode === 'monthly' || mode === 'annual'
  const editorialPosterMode = memoryV2 || mode === 'companion'
  const shareReport = useMemo(() => buildAnalyticsReport(profile, { mode, now, year, month, companionID: report.companion?.selectedCompanionID ?? companionID, sourceID, filter: mode === 'taste' ? tasteFilter : mode === 'source' ? sourceFilter : undefined, excludePrivate: true }), [mode, profile, now, tasteFilter, report, year, month, sourceID, sourceFilter, companionID])
  const data = useMemo(() => editorialPosterMode ? analyticsMemoryShareData(shareReport, profile) : module === 'poster' && posterAudience === 'owner' ? analyticsReportOwnerPosterData(report, profile) : analyticsReportShareData(shareReport, profile), [report, shareReport, profile, module, posterAudience, editorialPosterMode])
  const ownerMemoryData = useMemo(() => analyticsMemoryShareData(report, profile, 'owner'), [report, profile])
  const ownerSourceMemoryData = useMemo(() => analyticsMemoryShareData({ ...report, mode: 'source', title: '谁最会种草' }, profile, 'owner'), [report, profile])
  const sourceMemoryData = useMemo(() => analyticsMemoryShareData({ ...shareReport, mode: 'source', title: '谁最会种草' }, profile), [shareReport, profile])
  const years = useMemo(() => [...new Set([now.getFullYear(), ...profile.visits.filter(visit => !visit.deletedAt).map(visit => new Date(visit.visitedAt).getFullYear()).filter(value => Number.isFinite(value) && value <= now.getFullYear())])].sort((a, b) => b - a), [profile.visits, now])

  useEffect(() => {
    if (module !== 'poster' || editorialPosterMode) return
    let active = true
    let url: string | null = null
    setPosterError(false); setPoster(null)
    void renderAnalysisPosterBlob(data).then(blob => {
      if (!active) return
      url = URL.createObjectURL(blob)
      setPoster({ data, blob, url })
    }).catch(() => { if (active) setPosterError(true) })
    return () => { active = false; if (url) URL.revokeObjectURL(url) }
  }, [data, module, posterAttempt, editorialPosterMode])
  const readyPoster = poster?.data === data ? poster : null
  const share = async () => {
    // Never send the private preview. First show the exact safe export; the user
    // reviews it and invokes Share again after generation has completed.
    if (module === 'poster' && posterAudience === 'owner' && !editorialPosterMode) { setPosterAudience('share'); return }
    if (sharingRef.current || report.dataState === 'unavailable' || (module === 'poster' && !readyPoster)) return
    sharingRef.current = true; setSharing(true); setShareError(null)
    try {
      if (module === 'data') {
        const text = memoryV2 ? analysisDataShareText(data) : analyticsReportShareText(shareReport, profile)
        if (platform.kind === 'browser' && typeof navigator.share !== 'function') downloadAnalysisData(text, data.title)
        else await platform.share.open({ title: data.title + ' · 数据', text })
      } else if (readyPoster) {
        // Export the exact preview blob; never rebuild from a later snapshot.
        if (platform.kind === 'browser') await shareAnalysisPoster(readyPoster.blob, data)
        else await platform.share.open({ title: data.title, text: data.summary, imageDataURL: await blobDataURL(readyPoster.blob) })
      }
    } catch (error) {
      if (!(error instanceof Error && error.name === 'AbortError')) setShareError('分享未完成，请重试。')
    } finally { sharingRef.current = false; setSharing(false) }
  }
  if (!premium) {
    const feature: MembershipFeature = ({ taste: 'full_taste_profile', companion: 'companion_analysis', source: 'recommendation_source_analysis', monthly: 'monthly_review', annual: 'annual_review' } as const)[mode]
    return <main className="tm-hybrid-page tm-hybrid-analytics" data-analysis-mode={mode}><HybridBackButton onBack={onBack ?? (() => void platform.navigation.back())} /><HybridPageHeader title={HYBRID_ANALYTICS_MODES.find(([value]) => value === mode)?.[1] ?? '数据分析'} eyebrow="TASTE MAP ANALYSIS" description="会员功能保留在这里，开通后即可查看；原有记录不会改变。" /><div className="tm-hybrid-analysis-tabs" aria-label="会员分析入口">{['数据', '画报', ...(mode === 'source' ? ['最坑推荐来源'] : [])].map(label => <button key={label} onClick={() => openPremiumPaywall(feature)} type="button"><PremiumFeatureLabel>{label}</PremiumFeatureLabel></button>)}</div><HybridState kind="empty" title="会员专享" message="解锁后可查看完整分析与画报。" /><button className="primary-button" onClick={() => openPremiumPaywall(feature)} type="button">查看会员权益</button></main>
  }
  if (sourcePoster) return <main className="tm-hybrid-page tm-hybrid-analytics"><HybridBackButton onBack={() => setSourcePoster(false)} /><MemoryPoster ownerData={ownerSourceMemoryData} data={sourceMemoryData} platform={platform} pageID="S10" /></main>
  return <main className="tm-hybrid-page tm-hybrid-analytics" data-analysis-mode={mode} data-report-presentation={singleReport ? 'dedicated' : 'overview'}>
    <HybridBackButton onBack={() => { if (module === 'poster') { setModule('data'); return } if (!explorerBack.current?.()) { if (sourceFromTaste.current && mode === 'source') { sourceFromTaste.current = false; setMode('taste') } else onBack?.() } }} />
    {!singleReport ? <><HybridPageHeader title="数据分析" eyebrow="TASTE MAP ANALYSIS" description="从真实记录里，读懂你的饮食变化。" /><div aria-label="分析类型" className="tm-hybrid-analysis-tabs" role="tablist">{HYBRID_ANALYTICS_MODES.map(([value, label]) => <button aria-selected={mode === value} key={value} onClick={() => { setMode(value); setModule('data') }} role="tab" type="button">{label}</button>)}</div></> : null}
    <AnalysisModuleNavigation module={module} onChange={setModule} onShare={() => { if (module === 'poster' && editorialPosterMode) memoryShare.current?.(); else void share() }} sharing={sharing} previewBeforeShare={module === 'poster' && posterAudience === 'owner' && !editorialPosterMode} disabled={report.dataState === 'unavailable' || (module === 'poster' && !editorialPosterMode && !readyPoster)} />
    {shareError ? <p role="alert">{shareError}</p> : null}
    {mode === 'companion' && report.companion?.companions.length ? <section className="tm-analysis-period"><label>查看饭搭子<select aria-label="选择饭搭子" value={report.companion.selectedCompanionID ?? ''} onChange={event => setCompanionID(event.target.value)}>{report.companion.companions.map(item => <option key={item.id} value={item.id}>{item.displayName} · {item.sharedVisitCount} 次共同到访</option>)}</select></label></section> : null}
    {mode === 'taste' && report.dataState !== 'unavailable' ? <div hidden={module !== 'data'}><TasteProfileExplorer key={profile.user.id} report={report} filter={tasteFilter} onFilter={applyTasteFilter} onOpenRestaurant={onOpenRestaurant} onOpenVisit={id => { void platform.navigation.openHybrid({ surface: 'visit', identifier: id }).catch(() => setShareError('到访详情未打开，请重试。')) }} onPoster={() => { setModule('poster'); setPosterAudience('share') }} onSourcePoster={() => setSourcePoster(true)} onOpenSources={() => { sourceFromTaste.current = true; setSourceFilter(tasteFilter); setMode('source'); setModule('data') }} registerBack={registerExplorerBack} /></div> : null}
    {memoryV2 && report.dataState !== 'unavailable' ? <div hidden={module !== 'data'}>{mode === 'source' ? <RecommendationSourceExplorer report={report} onOpenRestaurant={onOpenRestaurant} onOpenVisit={id => { void platform.navigation.openHybrid({ surface: 'visit', identifier: id }).catch(() => setShareError('记录未打开，请重试。')) }} onPoster={() => setModule('poster')} registerBack={registerExplorerBack} /> : <PeriodMemoryExplorer profile={profile} onSourcePoster={() => setSourcePoster(true)} report={report} year={year} month={month} years={years} onPeriod={(valueYear, valueMonth) => { setYear(valueYear); setMonth(valueMonth) }} onOpenRestaurant={onOpenRestaurant} onOpenVisit={id => { void platform.navigation.openHybrid({ surface: 'visit', identifier: id }).catch(() => setShareError('记录未打开，请重试。')) }} onPoster={() => setModule('poster')} registerBack={registerExplorerBack} />}</div> : null}
    {report.dataState === 'unavailable' ? <HybridState kind="error" title="当前记录暂时无法分析" message={report.dataNote} /> : module === 'data' ? mode === 'taste' || memoryV2 ? null : <><AnalyticsReportDataView key={report.id} report={report} initialSourceID={dataSourceDetailID} onSelectSource={id => { setSourceID(id); setDataSourceDetailID(id) }} onReturnHome={() => setDataSourceDetailID(undefined)} mode={mode} title={report.title} headline={report.headline} period={report.scope.periodLabel} summary={report.summary} sections={report.sections} evidence={report.evidenceRestaurants} visualEvidence={report.visualEvidence} profile={profile} onOpenRestaurant={onOpenRestaurant} source={report.source} /><p className="tm-analysis-privacy-note">{report.dataNote}</p></> : editorialPosterMode ? <MemoryPoster key={`${profile.user.id}:${mode}:${companionID ?? ''}`} ownerData={ownerMemoryData} data={data} platform={platform} registerShare={registerMemoryShare} pageID={mode === 'source' ? 'S10' : mode === 'monthly' ? 'M08' : mode === 'companion' ? 'C08' : 'Y08'} /> : <section className="tm-hybrid-poster-stage" data-explore-page={mode === 'taste' ? 'F24' : undefined}>
      <HybridPageHeader title={report.title + '画报'} eyebrow={data.eyebrow} description={report.scope.periodLabel + ' · 当前报告的分享摘要'} />
      <section className="tm-analysis-poster-audience" aria-label="画报隐私预览">
        <div><strong>{posterAudience === 'owner' ? '本人完整预览' : '对外分享预览'}</strong><p>{posterAudience === 'owner' ? '与数据版同一份记录，仅在本页查看。' : mode === 'taste' ? '仅用公开记录重新分析，已排除私密和好友记录；下方原图就是分享内容。' : '已隐藏消费与同行信息；下方原图就是分享内容。'}</p></div>
        <button type="button" onClick={() => setPosterAudience(posterAudience === 'owner' ? 'share' : 'owner')}>{posterAudience === 'owner' ? '查看分享版' : '查看完整版'}</button>
      </section>
      <div className="tm-hybrid-poster-preview" aria-label={report.title + '画报预览'} style={{ aspectRatio: mode === 'taste' ? '2 / 3' : '9 / 16' }}>
        {readyPoster ? <ZoomablePosterPreview src={readyPoster.url} alt={report.title + '分享画报'} /> : posterError ? <HybridState kind="error" title="画报生成失败" message="报告数据仍在，请重新生成。" /> : <HybridState kind="loading" title="生成分享画报" message="正在准备同一份报告的画报。" />}
      </div>
      {posterError ? <button type="button" onClick={() => setPosterAttempt(value => value + 1)}>重新生成画报</button> : null}
      <p className="tm-analysis-privacy-note">{mode === 'taste' ? '1080 × 1620' : '1080 × 1920'} · 可双指缩放查看；{posterAudience === 'owner' ? '分享前请先查看分享版。' : '分享的是当前预览原图。'}完整统计保留在数据模式。</p>
      {platform.kind === 'browser' && posterAudience === 'share' ? <button className="tm-hybrid-poster-export" type="button" disabled={!readyPoster} onClick={() => readyPoster && downloadAnalysisPoster(readyPoster.blob, data)}><Download size={17} />保存画报</button> : null}
    </section>}
    <p className="tm-analysis-privacy-note">数据与画报来自同一份报告。分享默认隐藏消费金额和饭搭子姓名，不分享私人笔记。</p>
  </main>
}

export function AnalysisModuleNavigation({ module, onChange, onShare, sharing = false, disabled = false, previewBeforeShare = false }: { module: AnalyticsModule; onChange: (module: AnalyticsModule) => void; onShare: () => void; sharing?: boolean; disabled?: boolean; previewBeforeShare?: boolean }) {
  return <section aria-label="分析模块" className="tm-hybrid-analysis-modules"><div role="tablist" aria-label="选择数据或画报">{HYBRID_ANALYTICS_MODULES.map(([value, label]) => <button aria-selected={module === value} key={value} onClick={() => onChange(value)} role="tab" type="button">{value === 'data' ? <BarChart3 size={16} /> : <Image size={16} />}{label}</button>)}</div><button aria-busy={sharing} disabled={sharing || disabled} className="tm-hybrid-analysis-data-share" onClick={onShare} type="button"><Share2 size={16} />{sharing ? '准备分享' : module === 'data' ? '分享数据' : previewBeforeShare ? '预览分享版' : '分享画报'}</button></section>
}

function blobDataURL(blob: Blob) {
  return new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onerror = () => reject(reader.error ?? new Error('海报编码失败')); reader.onload = () => typeof reader.result === 'string' ? resolve(reader.result) : reject(new Error('海报编码失败')); reader.readAsDataURL(blob) })
}

export function analysisDataShareText(data: AnalysisShareData) {
  const metrics = data.metrics.map(item => item.label + '：' + item.value + (item.note ? '（' + item.note + '）' : ''))
  return [data.title, data.subtitle, data.summary, metrics.length ? '\n数据\n' + metrics.join('\n') : '', data.insights.length ? '\n洞察\n' + data.insights.map(item => '• ' + item).join('\n') : '', '\n' + data.footer].filter(Boolean).join('\n')
}

function downloadAnalysisData(text: string, title: string) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' })); const anchor = document.createElement('a'); anchor.href = url; anchor.download = title + '-数据.txt'; anchor.click(); URL.revokeObjectURL(url)
}
