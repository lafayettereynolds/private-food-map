import { useMemo, useState, type ReactNode } from 'react'
import { ArrowLeft, CalendarDays, ChevronRight, CircleDollarSign, Clock3, Link2, MapPin, MapPinned, ReceiptText, Repeat2, Search, Sparkles, Store, Utensils, UsersRound, WalletCards } from 'lucide-react'
import type { DiningCompanion, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { buildCompanionDirectory, buildCompanionInsights } from '../services/companionInsights'
import { buildRecommendationSourceInsights, type RecommendationSourceInsight } from '../services/recommendationSourceInsights'
import { recommendationService } from '../services/recommendationService'
import { SyncedImage } from './SyncedImage'

export function CompanionInsightsPanel({ companions, ownerUserId, restaurants, visits, onSelectRestaurant }: { companions: DiningCompanion[]; ownerUserId: string; restaurants: RestaurantSummary[]; visits: Visit[]; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const directory = useMemo(() => buildCompanionDirectory(companions, visits, ownerUserId), [companions, ownerUserId, visits])
  const insights = useMemo(() => directory.map((companion) => buildCompanionInsights(companion, restaurants, visits)).sort((a, b) => b.sharedVisitCount - a.sharedVisitCount), [directory, restaurants, visits])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const selected = insights.find((item) => item.companion.id === selectedId)
  const visibleInsights = insights.filter((item) => item.companion.displayName.toLocaleLowerCase('zh-CN').includes(query.trim().toLocaleLowerCase('zh-CN')))
  const mostRestaurants = [...insights].sort((a, b) => b.restaurantCount - a.restaurantCount || b.sharedVisitCount - a.sharedVisitCount)[0]
  const mostRecent = [...insights].filter((item) => item.latestVisitedAt).sort((a, b) => (b.latestVisitedAt ?? '').localeCompare(a.latestVisitedAt ?? ''))[0]
  if (selected) return <CompanionDetail insight={selected} onBack={() => setSelectedId(null)} onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} visits={visits} />
  return <div className="analytics-directory">
    <header><UsersRound size={20} /><div><strong>饭搭子分析</strong><small>先看关系摘要，再查看每一段共同味觉记忆。</small></div></header>
    {insights.length ? <>
      <section className="companion-summary"><h3><Sparkles size={15} />关系摘要</h3><div className="companion-summary__grid"><CompanionSummaryCard icon={<Utensils size={15} />} insight={insights[0]} label="最常一起吃" value={`${insights[0].sharedVisitCount} 次`} /><CompanionSummaryCard icon={<Store size={15} />} insight={mostRestaurants} label="一起去过最多" value={`${mostRestaurants.restaurantCount} 家`} /><CompanionSummaryCard icon={<CalendarDays size={15} />} insight={mostRecent} label="最近一起吃过" value={mostRecent.latestVisitedAt ? shortDate(mostRecent.latestVisitedAt) : '—'} /></div></section>
      <label className="companion-search"><Search size={15} /><input onChange={(event) => setQuery(event.target.value)} placeholder="搜索饭搭子" value={query} /></label>
      <div className="analytics-card-list companion-card-list">{visibleInsights.map((insight) => <button key={insight.companion.id} onClick={() => setSelectedId(insight.companion.id)} type="button"><CompanionAvatar name={insight.companion.displayName} /><span><strong>{insight.companion.displayName}</strong><small><Utensils size={12} />一起吃过 {insight.sharedVisitCount} 次 · <Store size={12} />去过 {insight.restaurantCount} 家</small><small>{insight.topCuisines[0] ? `最常一起吃 ${insight.topCuisines[0].label}` : insight.latestVisitedAt ? `最近 ${shortDate(insight.latestVisitedAt)}` : '共同记录正在形成'}</small></span><em>{confidenceLabel(insight.confidence)}</em><ChevronRight size={17} /></button>)}</div>
      {!visibleInsights.length ? <EmptyAnalysis text="没有找到这个饭搭子。" /> : null}
    </> : <EmptyAnalysis text="记录饭搭子后，这里会逐渐形成你们的共同用餐档案。" />}
  </div>
}

function CompanionDetail({ insight, restaurants, visits, onBack, onSelectRestaurant }: { insight: ReturnType<typeof buildCompanionInsights>; restaurants: RestaurantSummary[]; visits: Visit[]; onBack: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const recommendations = useMemo(() => recommendationService.recommend(restaurants, visits, { type: 'for_you', surface: 'discover', city: insight.cities[0]?.label ?? null, partyContext: 'group', preferExploration: true }).slice(0, 3), [insight.cities, restaurants, visits])
  return <div className="analytics-detail">
    <button className="analytics-back" onClick={onBack} type="button"><ArrowLeft size={16} />饭搭子列表</button>
    <header className="companion-detail-header"><CompanionAvatar name={insight.companion.displayName} /><div><strong>{insight.companion.displayName}</strong><small>{insight.companion.linkedUserId ? '已关联 Taste Map 用户' : '历史饭搭子'}{insight.latestVisitedAt ? ` · 最近 ${shortDate(insight.latestVisitedAt)}` : ''}</small></div><em>{confidenceLabel(insight.confidence)}</em></header>
    <section className="analytics-metrics"><Metric icon={<Utensils size={15} />} label="一起吃饭" value={`${insight.sharedVisitCount} 次`} /><Metric icon={<Store size={15} />} label="去过餐厅" value={`${insight.restaurantCount} 家`} /><Metric icon={<Repeat2 size={15} />} label="重复去过" value={`${insight.repeatRestaurantCount} 家`} /><Metric icon={<Clock3 size={15} />} label="相伴跨度" value={insight.spanDays ? `${insight.spanDays} 天` : '刚开始'} /></section>
    {insight.confidence === 'INSUFFICIENT' ? <p className="analytics-confidence-note">目前只有少量共同记录，先展示事实，不生成强结论。</p> : null}
    <section><h3><WalletCards size={15} />和 TA 一起时，我的消费</h3>{insight.spend.sampleCount ? <div className="analytics-inline-stats"><span><CircleDollarSign size={13} />累计 <b>¥{Math.round(insight.spend.total!)}</b></span><span>平均 <b>¥{Math.round(insight.spend.average!)}</b></span><span>最高 <b>¥{Math.round(insight.spend.maximum!)}</b></span></div> : <p>还没有记录“我的实际消费”。</p>}</section>
    <section><h3><Utensils size={15} />我们最常吃什么</h3><div className="analytics-ranked-bars">{insight.topCuisines.map((item) => <div key={item.label}><span>{item.label}</span><i><b style={{ width: `${Math.max(12, item.visitCount / Math.max(1, insight.topCuisines[0]?.visitCount ?? 1) * 100)}%` }} /></i><em>{item.visitCount} 次</em></div>)}</div></section>
    <section><h3><Store size={15} />最常一起去</h3><div className="analytics-evidence-list">{insight.topRestaurants.map((item) => <button key={item.restaurantId} onClick={() => { const restaurant = restaurants.find((candidate) => candidate.id === item.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button"><span><strong>{item.name}</strong><small>{item.visitCount} 次{item.averageRating !== null ? ` · 我的平均 ${item.averageRating.toFixed(1)} 分` : ''}</small></span><ChevronRight size={16} /></button>)}</div></section>
    <section><h3><MapPinned size={15} />共同用餐画像</h3><div className="analytics-tags">{[...insight.diningModes, ...insight.occasions, ...insight.cities].slice(0, 8).map((item) => <span key={`${item.label}-${item.count}`}>{item.label} · {item.count}</span>)}</div>{insight.rating.ratedVisitCount ? <p>有评分的 {insight.rating.ratedVisitCount} 次中，我的平均评分为 {insight.rating.average?.toFixed(1)}。</p> : null}</section>
    {insight.memories.length ? <section><h3>共同回忆</h3><div className="analytics-memories">{insight.memories.map((memory) => <article key={memory.visitId}>{memory.photos[0] ? <SyncedImage alt={memory.restaurantName} source={memory.photos[0]} /> : null}<div><strong>{memory.restaurantName}</strong><time>{new Date(memory.visitedAt).toLocaleDateString('zh-CN')}</time>{memory.note ? <p>{memory.note}</p> : null}</div></article>)}</div></section> : null}
    <section><h3>下次和 TA 吃</h3><p>复用 Taste Map 的推荐服务，并继续受城市、距离、预算和你的长期口味约束。</p><div className="analytics-evidence-list">{recommendations.map((item) => <button key={item.restaurant.id} onClick={() => onSelectRestaurant?.(item.restaurant)} type="button"><span><strong>{item.restaurant.name}</strong><small>{item.restaurant.city} · {item.confidence === 'low' ? '仍在学习' : '结合共同场景推荐'}</small></span><Sparkles size={16} /></button>)}</div></section>
    {insight.linkedUserStatus === 'LINKED_RESTRICTED' ? <p className="analytics-permission-note"><Link2 size={14} />已完成身份关联；对方评分和口味只会在权限与样本都满足时参与，不会由本地记录推测。</p> : null}
  </div>
}

export function RecommendationSourceInsightsPanel({ restaurants, visits, sourceUsers = [], onSelectRestaurant }: { restaurants: RestaurantSummary[]; visits: Visit[]; sourceUsers?: UserProfile[]; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const sourceUserNames = useMemo(() => new Map(sourceUsers.map((user) => [user.id, user.nickname])), [sourceUsers])
  const insights = useMemo(() => buildRecommendationSourceInsights(restaurants, visits, sourceUserNames), [restaurants, sourceUserNames, visits])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const selected = insights.find((item) => item.id === selectedId)
  if (selected) return <SourceDetail insight={selected} onBack={() => setSelectedId(null)} onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} />
  return <div className="analytics-directory"><header><ReceiptText size={19} /><div><strong>推荐来源分析</strong><small>用真实到访、评分和再次到访，判断哪些来源对你更合适。</small></div></header>{insights.length ? <div className="analytics-card-list">{insights.map((insight) => <button key={insight.id} onClick={() => setSelectedId(insight.id)} type="button"><span><strong>{insight.label}</strong><small>{insight.visitedRestaurantCount} 家实际到访{insight.confidence !== 'INSUFFICIENT' && insight.averagePostVisitRating !== null ? ` · 均分 ${insight.averagePostVisitRating.toFixed(1)}` : ''}</small></span><em>{sourceConfidenceLabel(insight.confidence)}</em><ChevronRight size={17} /></button>)}</div> : <EmptyAnalysis text="在到访记录中填写推荐来源后，这里会按独立餐厅统计真实结果。" />}</div>
}

function SourceDetail({ insight, restaurants, onBack, onSelectRestaurant }: { insight: RecommendationSourceInsight; restaurants: RestaurantSummary[]; onBack: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const percent = (value: number | null) => value === null ? '—' : `${Math.round(value * 100)}%`
  const sufficientlyDetailed = insight.confidence !== 'INSUFFICIENT'
  return <div className="analytics-detail"><button className="analytics-back" onClick={onBack} type="button"><ArrowLeft size={16} />来源列表</button><header><div><strong>{insight.label}</strong><small>只代表这个来源过去对你的实际结果</small></div><em>{sourceConfidenceLabel(insight.confidence)}</em></header><section className="analytics-metrics"><Metric label="实际去过" value={`${insight.visitedRestaurantCount} 家`} /><Metric label="平均评分" value={sufficientlyDetailed && insight.averagePostVisitRating !== null ? insight.averagePostVisitRating.toFixed(1) : '—'} /><Metric label="高分命中" value={sufficientlyDetailed ? percent(insight.highRatingHitRate) : '—'} /><Metric label="再次到访" value={`${insight.repeatRestaurantCount} 家`} /></section>{insight.confidence === 'INSUFFICIENT' ? <p className="analytics-confidence-note">目前还没有足够数据判断这个来源的推荐表现。</p> : <><section><h3>真实结果</h3><div className="analytics-inline-stats"><span>低分比例 <b>{percent(insight.lowRatingRate)}</b></span><span>重复到访率 <b>{percent(insight.repeatRestaurantRate)}</b></span>{insight.spend.sampleCount ? <span>我的平均消费 <b>¥{Math.round(insight.spend.average!)}</b></span> : null}</div></section><section><h3>在哪些菜系更适合我</h3><div className="analytics-tags">{insight.cuisines.map((item) => <span key={item.label}>{item.label} · {item.restaurantCount} 家{item.restaurantCount >= 3 && item.averageRating !== null ? ` · ${item.averageRating.toFixed(1)} 分` : ''}</span>)}</div></section></>}<section><h3>证据餐厅</h3><div className="analytics-evidence-list">{insight.restaurants.map((item) => <button key={item.restaurantId} onClick={() => { const restaurant = restaurants.find((candidate) => candidate.id === item.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button"><span><strong>{item.name}</strong><small>{item.visitCount} 次到访{item.averageRating !== null ? ` · 我的平均 ${item.averageRating.toFixed(1)} 分` : ''}</small></span><ChevronRight size={16} /></button>)}</div></section><p className="analytics-permission-note">来源表现可以作为未来推荐的弱信号，但不会越过你明确设置的预算、距离、场景与长期口味。</p></div>
}

function CompanionAvatar({ name }: { name: string }) { return <span className="companion-avatar">{name.slice(0, 1)}</span> }
function CompanionSummaryCard({ insight, icon, label, value }: { insight: ReturnType<typeof buildCompanionInsights>; icon: ReactNode; label: string; value: string }) { return <article><span className="companion-summary__label">{icon}{label}</span><CompanionAvatar name={insight.companion.displayName} /><strong>{insight.companion.displayName}</strong><small>{value}</small></article> }
function Metric({ label, value, icon }: { label: string; value: string; icon?: ReactNode }) { return <span>{icon}<strong>{value}</strong><small>{label}</small></span> }
function EmptyAnalysis({ text }: { text: string }) { return <div className="analytics-empty"><MapPin size={22} /><p>{text}</p></div> }
function confidenceLabel(value: ReturnType<typeof buildCompanionInsights>['confidence']) { return value === 'INSUFFICIENT' ? '样本不足' : value === 'EMERGING' ? '逐渐形成' : '稳定画像' }
function sourceConfidenceLabel(value: RecommendationSourceInsight['confidence']) { return value === 'INSUFFICIENT' ? '样本不足' : value === 'EMERGING' ? '样本较少' : value === 'LOW' ? '轻度可信' : '稳定样本' }
function shortDate(value: string) { return new Date(value).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' }) }
