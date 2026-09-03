import { useEffect, useMemo, useState } from 'react'
import { Download, MapPin, ReceiptText, Share2, Sparkles, Star, TicketCheck, Utensils, WalletCards } from 'lucide-react'
import { rankTasteTags } from '../services/tasteProfileCore'
import type { AnalysisShareData, AnalysisShareType } from '../types/analysisShare'
import type { TasteMapPlatform, TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import { renderAnalysisPosterBlob, downloadAnalysisPoster } from '../services/analysisPosterRenderer'
import { HybridPageHeader, HybridRestaurantImage, HybridState } from './TasteMapHybridShared'
import { HYBRID_ANALYTICS_MODES } from '../hybrid/app/HybridProductContracts'

export type AnalyticsMode = 'taste' | 'companion' | 'source' | 'monthly' | 'annual'
const modes: ReadonlyArray<readonly [AnalyticsMode, string]> = HYBRID_ANALYTICS_MODES

export function TasteMapAnalyticsPage({ platform, profile, onOpenRestaurant, initialMode = 'taste' }: { platform: TasteMapPlatform; profile: TasteMapProfileDashboardViewModel; onOpenRestaurant: (id: string) => void; initialMode?: AnalyticsMode }) {
  const [mode, setMode] = useState<AnalyticsMode>(initialMode)
  const [poster, setPoster] = useState(false)
  useEffect(() => { setMode(initialMode); setPoster(false) }, [initialMode])
  const model = useMemo(() => buildAnalyticsModel(profile, mode), [mode, profile])
  if (!profile.visits.length) return <main className="tm-hybrid-page"><HybridPageHeader eyebrow="ANALYSIS" title="数据分析" /><HybridState kind="empty" message="记录真实到访后，Taste Map 才会生成口味与回顾结论。" title="还没有足够数据" /></main>
  return <main className="tm-hybrid-page tm-hybrid-analytics" data-analysis-mode={mode}>
    <HybridPageHeader description="只根据你的真实餐厅、到访、评分与消费记录动态生成。" eyebrow="TASTE MAP ANALYSIS" title="数据分析" trailing={<button className="tm-hybrid-page-action" onClick={() => setPoster((value) => !value)} type="button">{poster ? <Sparkles size={16} /> : <Share2 size={16} />}{poster ? '返回分析' : '分享海报'}</button>} />
    <div className="tm-hybrid-analysis-tabs" role="tablist">{modes.map(([value, label]) => <button aria-selected={mode === value} key={value} onClick={() => { setMode(value); setPoster(false) }} role="tab" type="button">{label}</button>)}</div>
    {poster ? <TasteMapAnalysisPoster model={model} platform={platform} profile={profile} /> : <AnalysisInfographic model={model} onOpenRestaurant={onOpenRestaurant} profile={profile} />}
  </main>
}

interface AnalyticsModel {
  mode: AnalyticsMode
  title: string
  eyebrow: string
  period: string
  heroLabel: string
  heroAsset: string
  heroCaption: string
  heroRestaurantID: string | null
  nodes: Array<{ label: string; value: string }>
  headline: string
  insights: string[]
  top: Array<{ label: string; detail: string; restaurantID?: string }>
  spend: number
  city: string
  restaurantCount: number
  visitCount: number
  averageRating: number | null
  timeDistribution: Array<{ label: string; value: number }>
}

function AnalysisInfographic({ model, profile, onOpenRestaurant }: { model: AnalyticsModel; profile: TasteMapProfileDashboardViewModel; onOpenRestaurant: (id: string) => void }) {
  return <article className="tm-hybrid-analysis-board">
    <header className="tm-hybrid-analysis-title"><span>{model.eyebrow}</span><h2>{model.title}</h2><p>{model.period}</p><i aria-hidden="true" /></header>
    <section className="tm-hybrid-analysis-hero-network" aria-label={`${model.title} 核心食物主视觉`}>
      <div className="tm-hybrid-analysis-hero"><img alt="" src={model.heroAsset} /><strong>{model.heroLabel}</strong><small>{model.heroCaption}</small></div>
      <div aria-label="周边分析节点" className="tm-hybrid-analysis-nodes">{model.nodes.slice(0, 6).map((node, index) => <div className={`is-node-${index + 1}`} key={`${node.label}-${index}`}><i aria-hidden="true" /><strong>{node.value}</strong><span>{node.label}</span></div>)}</div>
    </section>
    <aside className="tm-hybrid-analysis-overview"><span className="tm-hybrid-analysis-paperclip" aria-hidden="true" /><h3>数据总览</h3><Metric icon={<Utensils size={16} />} label="记录餐厅" value={`${model.restaurantCount} 家`} /><Metric icon={<TicketCheck size={16} />} label="记录到访" value={`${model.visitCount} 次`} /><Metric icon={<WalletCards size={16} />} label="总消费" value={`¥${Math.round(model.spend).toLocaleString('zh-CN')}`} /><Metric icon={<MapPin size={16} />} label="主要城市" value={model.city || '—'} /><Metric icon={<Star size={16} />} label="平均评分" value={model.averageRating ? `${model.averageRating.toFixed(1)} / 5` : '未评分'} /></aside>
    <section aria-label="核心洞察" className="tm-hybrid-analysis-headline"><small>近期洞察</small><h3>{model.headline}</h3>{model.insights.map((value) => <p key={value}><Sparkles size={15} />{value}</p>)}</section>
    <section className="tm-hybrid-analysis-top"><h3>{model.mode === 'companion' ? '饭搭子 TOP 3' : model.mode === 'source' ? '来源 TOP 3' : '最常吃 TOP 3'}</h3>{model.top.slice(0, 3).map((value, index) => <button disabled={!value.restaurantID} key={`${value.label}-${index}`} onClick={() => value.restaurantID && onOpenRestaurant(value.restaurantID)} type="button"><b>{index + 1}</b><span><strong>{value.label}</strong><small>{value.detail}</small></span></button>)}</section>
    <section className="tm-hybrid-analysis-preferences"><h3>口味偏好</h3><div>{model.nodes.slice(0, 6).map((item, index) => <span key={`${item.label}-preference`}><i style={{ '--preference': `${Math.max(14, Number.parseInt(item.value, 10) || 24)}%`, '--preference-index': index } as React.CSSProperties} /><strong>{item.label}</strong><small>{item.value}</small></span>)}</div></section>
    <section className="tm-hybrid-analysis-distribution"><h3><ReceiptText size={17} />消费与时间</h3><div className="tm-hybrid-analysis-spend"><span>累计消费</span><strong>¥{Math.round(model.spend).toLocaleString('zh-CN')}</strong><small>仅统计填写了“我的实际消费”的到访</small></div><div>{model.timeDistribution.map((item) => <span key={item.label}><i style={{ height: `${Math.max(10, item.value)}%` }} /><b>{item.value}%</b><small>{item.label}</small></span>)}</div></section>
    <section className="tm-hybrid-analysis-footprint"><h3><MapPin size={17} />城市足迹</h3><strong>{model.city || '仍在积累'}</strong><p>{model.restaurantCount} 家餐厅 · {model.visitCount} 次到访</p><div aria-hidden="true"><i /><i /><i /></div></section>
    <section className="tm-hybrid-analysis-restaurants"><h3>代表餐厅</h3>{profile.restaurants.filter((item) => item.status === 'visited').sort((a, b) => (b.averageRating ?? 0) - (a.averageRating ?? 0)).slice(0, 3).map((item) => <button key={item.id} onClick={() => onOpenRestaurant(item.id)} type="button"><HybridRestaurantImage image={profile.restaurantImages[item.id]} name={item.name} /><span><strong>{item.name}</strong><small>{item.city} · {item.visitCount} 次到访</small></span></button>)}</section>
    <footer><span><Utensils size={17} />Taste Map</span><small>基于真实记录生成 · Food Hero 仅在真实偏好支持时表达数据</small></footer>
  </article>
}

function Metric({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) { return <div><span>{icon}{label}</span><strong>{value}</strong></div> }

function TasteMapAnalysisPoster({ model, profile, platform }: { model: AnalyticsModel; profile: TasteMapProfileDashboardViewModel; platform: TasteMapPlatform }) {
  const shareData = useMemo(() => posterData(model, profile), [model, profile])
  const [previewURL, setPreviewURL] = useState<string | null>(null)
  const [previewError, setPreviewError] = useState(false)
  useEffect(() => {
    let active = true
    let objectURL: string | null = null
    setPreviewURL(null)
    setPreviewError(false)
    void renderAnalysisPosterBlob(shareData).then((blob) => {
      if (!active) return
      objectURL = URL.createObjectURL(blob)
      setPreviewURL(objectURL)
    }).catch(() => { if (active) setPreviewError(true) })
    return () => { active = false; if (objectURL) URL.revokeObjectURL(objectURL) }
  }, [shareData])
  const exportPoster = async () => {
    const blob = await renderAnalysisPosterBlob(shareData)
    if (platform.kind === 'browser') downloadAnalysisPoster(blob, shareData)
    else await platform.share.open({ title: shareData.title, text: shareData.summary, imageDataURL: await blobDataURL(blob) })
  }
  return <section className="tm-hybrid-poster-stage">
    <div className="tm-hybrid-poster-preview" aria-label={`${model.title} 9:16 海报预览`}>
      {previewURL ? <img alt={`${model.title} 9:16 分享海报`} src={previewURL} /> : previewError ? <HybridState kind="error" message="海报数据仍然保留，可以重新生成。" title="预览生成失败" /> : <HybridState kind="loading" message="正在用正式 1080 × 1920 renderer 生成预览。" title="生成分享海报" />}
    </div>
    <p>此处展示的就是正式 1080 × 1920 renderer 输出，不是另一个简化预览模板。</p>
    <button className="tm-hybrid-poster-export" disabled={!previewURL} onClick={() => void exportPoster()} type="button"><Download size={17} />{platform.kind === 'browser' ? '导出 9:16 海报' : '打开系统分享'}</button>
  </section>
}

function blobDataURL(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(reader.error ?? new Error('海报编码失败'))
    reader.onload = () => typeof reader.result === 'string' ? resolve(reader.result) : reject(new Error('海报编码失败'))
    reader.readAsDataURL(blob)
  })
}

function buildAnalyticsModel(profile: TasteMapProfileDashboardViewModel, mode: AnalyticsMode): AnalyticsModel {
  const restaurants = profile.restaurants.filter((item) => item.status === 'visited')
  const visits = profile.visits.filter((item) => !item.deletedAt)
  const restaurantsByID = new Map(restaurants.map((item) => [item.id, item]))
  const now = new Date()
  const filteredVisits = mode === 'monthly'
    ? visits.filter((visit) => { const value = new Date(visit.visitedAt); return value.getFullYear() === now.getFullYear() && value.getMonth() === now.getMonth() })
    : mode === 'annual' ? visits.filter((visit) => new Date(visit.visitedAt).getFullYear() === now.getFullYear()) : visits
  const filteredRestaurantIDs = new Set(filteredVisits.map((visit) => visit.restaurantId))
  const filteredRestaurants = mode === 'monthly' || mode === 'annual'
    ? restaurants.filter((item) => filteredRestaurantIDs.has(item.id))
    : restaurants
  const ratings = filteredVisits.flatMap((visit) => visit.rating == null ? [] : [visit.rating])
  const spend = filteredVisits.reduce((sum, visit) => sum + (visit.myActualSpend ?? 0), 0)
  const cuisine = rankTasteTags(filteredVisits.flatMap((visit) => {
    const restaurant = restaurantsByID.get(visit.restaurantId)
    return visit.rating == null || !restaurant ? [] : [{ restaurantKey: restaurant.id, tags: restaurant.tags, ratingOutOfTen: visit.rating * 2 }]
  }))
  const companionCounts = count(filteredVisits.flatMap((visit) => visit.companions))
  const sourceCounts = count(filteredVisits.map((visit) => visit.recommendationSourceText).filter(Boolean))
  const cityCounts = count(filteredRestaurants.map((item) => item.city).filter(Boolean))
  const topRestaurants = [...filteredRestaurants].sort((a, b) => (b.averageRating ?? 0) - (a.averageRating ?? 0) || b.visitCount - a.visitCount)
  const diningTimes = [0, 0, 0, 0]
  filteredVisits.forEach((visit) => { const hour = new Date(visit.visitedAt).getHours(); diningTimes[hour < 10 ? 0 : hour < 15 ? 1 : hour < 21 ? 2 : 3] += 1 })
  const total = diningTimes.reduce((sum, value) => sum + value, 0) || 1
  const timeDistribution = ['早餐', '午餐', '晚餐', '夜宵'].map((label, index) => ({ label, value: Math.round(diningTimes[index] / total * 100) }))
  const firstCuisine = cuisine[0]?.tag ?? restaurants[0]?.tags[0] ?? '餐饮偏好'
  const heroAsset = foodHeroAsset(firstCuisine)
  const base = {
    mode, restaurantCount: filteredRestaurants.length, visitCount: filteredVisits.length,
    spend, city: cityCounts[0]?.[0] ?? profile.user.city,
    averageRating: ratings.length ? ratings.reduce((sum, value) => sum + value, 0) / ratings.length : null,
    timeDistribution,
    heroRestaurantID: topRestaurants[0]?.id ?? null, heroAsset,
    heroCaption: `基于真实高频偏好 · ${firstCuisine}`,
  }
  if (mode === 'companion') {
    const best = companionCounts[0]
    return { ...base, title: '最佳饭搭子', eyebrow: 'DINING COMPANION', period: '全部真实到访', heroLabel: '双人餐桌', heroCaption: best ? `${best[0]} · 最常一起吃 ${firstCuisine}` : `高频口味 · ${firstCuisine}`, nodes: companionCounts.slice(0, 6).map(([label, value]) => ({ label, value: `${value} 次` })), headline: best ? `和 ${best[0]} 一起吃过最多` : '饭搭子画像正在形成', insights: [`共同到访覆盖 ${new Set(visits.filter((visit) => visit.companions.includes(best?.[0] ?? '')).map((visit) => visit.restaurantId)).size} 家餐厅`, `最常一起吃 ${firstCuisine}`], top: companionCounts.slice(0, 3).map(([label, value]) => ({ label, detail: `${value} 次共同到访` })) }
  }
  if (mode === 'source') {
    const best = sourceCounts[0]
    return { ...base, title: '谁最会种草', eyebrow: 'RECOMMENDATION SOURCE', period: '全部真实到访', heroLabel: best?.[0] ?? '推荐来源', heroCaption: `到访后验证 · 高频口味 ${firstCuisine}`, nodes: sourceCounts.slice(0, 6).map(([label, value]) => ({ label, value: `${value} 家` })), headline: best ? `${best[0]} 带来的餐厅最多` : '推荐来源样本还在形成', insights: ['只统计实际到访后的真实结果', `高分餐厅集中在 ${firstCuisine}`], top: sourceCounts.slice(0, 3).map(([label, value]) => ({ label, detail: `${value} 家已到访餐厅` })) }
  }
  if (mode === 'monthly' || mode === 'annual') {
    const period = mode === 'monthly' ? `${now.getFullYear()} 年 ${now.getMonth() + 1} 月` : `${now.getFullYear()} 年`
    return { ...base, title: mode === 'monthly' ? '本月回顾' : '年度回顾', eyebrow: mode === 'monthly' ? 'MONTHLY REVIEW' : 'ANNUAL REVIEW', period, heroLabel: firstCuisine, heroCaption: `${period} 的味觉主线`, nodes: cuisine.slice(0, 6).map((item) => ({ label: item.tag, value: `${item.visits} 次` })), headline: filteredVisits.length ? `${period} 共留下 ${filteredVisits.length} 次真实到访` : `${period} 还没有到访记录`, insights: [`主要城市是 ${base.city || '未记录'}`, `最高频口味是 ${firstCuisine}`], top: topRestaurants.slice(0, 3).map((item) => ({ label: item.name, detail: `${item.visitCount} 次 · ${item.averageRating?.toFixed(1) ?? '未评分'}`, restaurantID: item.id })) }
  }
  return { ...base, title: '我的口味档案', eyebrow: 'TASTE PROFILE', period: '基于全部真实记录', heroLabel: firstCuisine, heroCaption: '你的高频菜系主视觉', nodes: cuisine.slice(0, 6).map((item) => ({ label: item.tag, value: `${Math.round(item.highRatingShare * 100)}%` })), headline: `你最稳定的偏好是 ${firstCuisine}`, insights: [`高频记录集中在 ${base.city || '多个城市'}`, `共记录 ${restaurants.length} 家餐厅与 ${visits.length} 次到访`], top: topRestaurants.slice(0, 3).map((item) => ({ label: item.name, detail: `${item.visitCount} 次 · ${item.averageRating?.toFixed(1) ?? '未评分'}`, restaurantID: item.id })) }
}

function foodHeroAsset(label: string) {
  const value = label.toLocaleLowerCase('zh-CN')
  if (/(日|寿司|刺身|拉面)/.test(value)) return '/food-heroes/japanese.png'
  if (/(火锅|烧烤|烤肉|串)/.test(value)) return '/food-heroes/hotpot-grill.png'
  if (/(西|牛排|意|披萨|汉堡)/.test(value)) return '/food-heroes/western.png'
  if (/(咖啡|茶|甜|蛋糕|面包)/.test(value)) return '/food-heroes/cafe.png'
  if (/(中|川|粤|湘|江浙|本帮)/.test(value)) return '/food-heroes/chinese.png'
  return '/food-heroes/mixed.png'
}

function posterData(model: AnalyticsModel, profile: TasteMapProfileDashboardViewModel): AnalysisShareData {
  const type: Record<AnalyticsMode, AnalysisShareType> = { taste: 'TASTE_PROFILE', companion: 'COMPANION_ANALYSIS', source: 'RECOMMENDATION_SOURCE', monthly: 'MONTHLY_REVIEW', annual: 'ANNUAL_REVIEW' }
  const restaurants = model.top.flatMap((item) => {
    const restaurant = item.restaurantID ? profile.restaurants.find((value) => value.id === item.restaurantID) : null
    return restaurant ? [{ restaurantId: restaurant.id, name: restaurant.name, meta: item.detail, image: shareVisual(profile, restaurant.id, restaurant.name) }] : []
  })
  return {
    reportId: `hybrid:${model.mode}:${new Date().toISOString().slice(0, 10)}`, type: type[model.mode], userId: profile.user.id,
    title: model.title, eyebrow: model.eyebrow, subtitle: model.period, summary: model.headline,
    periodLabel: model.period, metrics: [{ label: '餐厅', value: `${model.restaurantCount} 家` }, { label: '到访', value: `${model.visitCount} 次` }, { label: '消费', value: `¥${Math.round(model.spend)}` }, { label: '城市', value: model.city }],
    insights: model.insights, keywords: model.nodes.map((item) => item.label), restaurants,
    heroCandidates: [{ source: model.heroAsset, photoId: null, origin: 'fallback', label: model.heroLabel }, ...restaurants.map((item) => item.image)], footer: 'Taste Map · 基于真实记录生成', logoSource: '/icons/taste-map-icon-192.png',
    privacy: { companionNameIncluded: model.mode === 'companion', spendIncluded: true, exactLocationIncluded: false },
  }
}

function shareVisual(profile: TasteMapProfileDashboardViewModel, restaurantID: string, name: string) {
  const descriptor = profile.restaurantImages[restaurantID]
  if (!descriptor || descriptor.kind === 'foodDiningFallback' || descriptor.kind === 'foodCategoryVisual' || descriptor.kind === 'activityPhoto' || descriptor.kind === 'publicUGC') {
    return { source: null, photoId: null, origin: 'fallback' as const, label: name, restaurantId: restaurantID }
  }
  return {
    source: descriptor.resourceURL,
    photoId: 'photoID' in descriptor ? descriptor.photoID : null,
    origin: descriptor.kind === 'nativeResource' || descriptor.kind === 'ownerPhoto' ? 'visit' as const : descriptor.kind === 'providerMerchant' ? 'provider' as const : 'restaurant' as const,
    label: name,
    restaurantId: restaurantID,
  }
}

function count(values: string[]) {
  const result = new Map<string, number>()
  values.map((value) => value.trim()).filter(Boolean).forEach((value) => result.set(value, (result.get(value) ?? 0) + 1))
  return [...result].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'zh-CN'))
}
