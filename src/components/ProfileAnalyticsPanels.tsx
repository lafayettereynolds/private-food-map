import { useMemo, useState, type ReactNode } from 'react'
import { ArrowLeft, Award, BarChart3, CalendarDays, ChevronRight, CircleDollarSign, Clock3, Compass, Link2, MapPin, MapPinned, ReceiptText, Repeat2, Search, Sparkles, Store, Target, TrendingUp, UserRound, Utensils, UsersRound, WalletCards } from 'lucide-react'
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
  const [filter, setFilter] = useState<'all' | 'recent' | 'frequent' | 'other'>('all')
  const selected = insights.find((item) => item.companion.id === selectedId)
  const visibleInsights = insights.filter((item) => {
    if (!item.companion.displayName.toLocaleLowerCase('zh-CN').includes(query.trim().toLocaleLowerCase('zh-CN'))) return false
    if (filter === 'recent') return item.latestVisitedAt !== null && Date.now() - Date.parse(item.latestVisitedAt) <= 120 * 86400000
    if (filter === 'frequent') return item.sharedVisitCount >= 3
    if (filter === 'other') return item.companion.linkedUserId === null
    return true
  })
  const mostRestaurants = [...insights].sort((a, b) => b.restaurantCount - a.restaurantCount || b.sharedVisitCount - a.sharedVisitCount)[0]
  const mostRecent = [...insights].filter((item) => item.latestVisitedAt).sort((a, b) => (b.latestVisitedAt ?? '').localeCompare(a.latestVisitedAt ?? ''))[0]
  if (selected) return <CompanionDetail insight={selected} onBack={() => setSelectedId(null)} onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} visits={visits} />
  return <div className="analytics-directory">
    <header><UsersRound size={20} /><div><strong>饭搭子分析</strong><small>先看关系摘要，再查看每一段共同味觉记忆。</small></div></header>
    {insights.length ? <>
      <section className="companion-summary"><h3><Sparkles size={15} />关系摘要</h3><div className="companion-summary__grid"><CompanionSummaryCard icon={<Utensils size={15} />} insight={insights[0]} label="最常一起吃" value={`${insights[0].sharedVisitCount} 次`} /><CompanionSummaryCard icon={<Store size={15} />} insight={mostRestaurants} label="一起去过最多" value={`${mostRestaurants.restaurantCount} 家`} /><CompanionSummaryCard icon={<CalendarDays size={15} />} insight={mostRecent} label="最近一起吃过" value={mostRecent.latestVisitedAt ? shortDate(mostRecent.latestVisitedAt) : '—'} /></div></section>
      <label className="companion-search"><Search size={15} /><input onChange={(event) => setQuery(event.target.value)} placeholder="搜索饭搭子" value={query} /></label>
      <div className="companion-filters" aria-label="饭搭子筛选">{([['all', '全部'], ['recent', '最近一起吃过'], ['frequent', '更常一起吃'], ['other', '历史饭搭子']] as const).map(([value, label]) => <button className={filter === value ? 'is-active' : ''} key={value} onClick={() => setFilter(value)} type="button">{label}</button>)}</div>
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
    <section><h3><Store size={15} />最常一起去</h3><div className="analytics-evidence-list source-evidence">{insight.topRestaurants.map((item) => <button key={item.restaurantId} onClick={() => { const restaurant = restaurants.find((candidate) => candidate.id === item.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button">{restaurantImage(restaurants, item.restaurantId) ? <img alt="" src={restaurantImage(restaurants, item.restaurantId)!} /> : <span className="source-evidence__placeholder"><Store size={17} /></span>}<span><strong>{item.name}</strong><small>{item.visitCount} 次{item.averageRating !== null ? ` · 我的平均 ${item.averageRating.toFixed(1)} 分` : ''}</small></span><ChevronRight size={16} /></button>)}</div></section>
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
  const mostFrequent = insights[0]
  const bestMatched = [...insights].filter((item) => sourceAccuracy(item) !== null).sort((a, b) => (sourceAccuracy(b) ?? -1) - (sourceAccuracy(a) ?? -1))[0]
  const latestSuccessful = [...insights].flatMap((source) => source.restaurants.map((restaurant) => ({ source, restaurant }))).filter((item) => item.restaurant.averageRating !== null).sort((a, b) => (b.restaurant.averageRating ?? 0) - (a.restaurant.averageRating ?? 0))[0]
  const groups = groupSourceInsights(insights)
  return <div className="analytics-directory source-analysis">
    <header><ReceiptText size={19} /><div><strong>推荐来源分析</strong><small>看看你通常从哪里发现餐厅，以及这些来源最后是否真的适合你。</small></div></header>
    {insights.length ? <>
      <section className="source-conclusion"><h3><Sparkles size={16} />本页结论</h3><div>
        <SourceConclusion icon={<Compass size={18} />} label="最常发现" value={mostFrequent?.label ?? '—'} />
        <SourceConclusion icon={<UserRound size={18} />} label="最适合你" value={bestMatched?.label ?? '继续记录'} />
        <SourceConclusion icon={<Target size={18} />} label="最近最准确" value={latestSuccessful?.source.label ?? '继续记录'} />
      </div></section>
      <section className="source-list-card"><header><h3><BarChart3 size={16} />来源列表</h3><span>按真实到访结果排序</span></header>
        {groups.map((group) => <div className="source-group" key={group.label}><h4>{group.label}</h4>{group.items.map((insight, index) => <button key={insight.id} onClick={() => setSelectedId(insight.id)} type="button"><span className="source-rank">{index + 1}</span><SourceMark insight={insight} /><span className="source-row-copy"><strong>{insight.label}</strong><small>发现 {insight.restaurantCount} 家 · 去过 {insight.visitedRestaurantCount} 家</small><em>{sourceDescription(insight)}</em></span><span className="source-accuracy"><small>推荐准确度</small><b>{sourceAccuracy(insight) === null ? '待积累' : `${sourceAccuracy(insight)}%`}</b></span><ChevronRight size={17} /></button>)}</div>)}
      </section>
      <section className="source-performance"><h3><TrendingUp size={16} />Taste Map 推荐表现</h3><div>{insights.filter((item) => item.label.includes('为你推荐') || item.label.includes('同味')).slice(0, 2).map((insight) => <button key={insight.id} onClick={() => setSelectedId(insight.id)} type="button"><SourceMark insight={insight} /><span><strong>{insight.label}</strong><small>平均 {insight.averagePostVisitRating?.toFixed(1) ?? '—'} · 去过 {insight.visitedRestaurantCount} 家</small></span></button>)}{!insights.some((item) => item.label.includes('为你推荐') || item.label.includes('同味')) ? <p>还没有足够的 Taste Map 推荐结果，后续到访会自动接受同样的结果检验。</p> : null}</div></section>
      {latestSuccessful ? <section className="source-success-card"><h3><Award size={16} />最近最成功的一次推荐</h3><button onClick={() => { const restaurant = restaurants.find((item) => item.id === latestSuccessful.restaurant.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button">{restaurantImage(restaurants, latestSuccessful.restaurant.restaurantId) ? <img alt="" src={restaurantImage(restaurants, latestSuccessful.restaurant.restaurantId)!} /> : <span className="source-success-card__placeholder"><Store size={22} /></span>}<span><strong>{latestSuccessful.restaurant.name}</strong><small>{latestSuccessful.source.label} · 到访后 {latestSuccessful.restaurant.averageRating?.toFixed(1)} 分</small><em>查看证据</em></span><ChevronRight size={18} /></button></section> : null}
    </> : <EmptyAnalysis text="在到访记录中填写推荐来源后，这里会按独立餐厅统计真实结果。" />}
  </div>
}

function SourceDetail({ insight, restaurants, onBack, onSelectRestaurant }: { insight: RecommendationSourceInsight; restaurants: RestaurantSummary[]; onBack: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const percent = (value: number | null) => value === null ? '—' : `${Math.round(value * 100)}%`
  const sufficientlyDetailed = insight.confidence !== 'INSUFFICIENT'
  return <div className="analytics-detail source-detail"><button className="analytics-back" onClick={onBack} type="button"><ArrowLeft size={16} />来源列表</button><header><SourceMark insight={insight} /><div><strong>{insight.label}</strong><small>只代表这个来源过去对你的实际结果</small></div><em>{sourceConfidenceLabel(insight.confidence)}</em></header><section className="analytics-metrics"><Metric icon={<Store size={15} />} label="实际去过" value={`${insight.visitedRestaurantCount} 家`} /><Metric icon={<Award size={15} />} label="平均评分" value={sufficientlyDetailed && insight.averagePostVisitRating !== null ? insight.averagePostVisitRating.toFixed(1) : '—'} /><Metric icon={<Target size={15} />} label="高分命中" value={sufficientlyDetailed ? percent(insight.highRatingHitRate) : '—'} /><Metric icon={<Repeat2 size={15} />} label="再次到访" value={`${insight.repeatRestaurantCount} 家`} /></section>{insight.confidence === 'INSUFFICIENT' ? <p className="analytics-confidence-note">目前还没有足够数据判断这个来源的推荐表现。</p> : <><section><h3>真实结果</h3><div className="analytics-inline-stats"><span>低分比例 <b>{percent(insight.lowRatingRate)}</b></span><span>重复到访率 <b>{percent(insight.repeatRestaurantRate)}</b></span>{insight.spend.sampleCount ? <span>我的平均消费 <b>¥{Math.round(insight.spend.average!)}</b></span> : null}</div></section><section><h3>最适合你的菜系</h3><div className="analytics-tags">{insight.cuisines.map((item) => <span key={item.label}>{item.label} · {item.restaurantCount} 家{item.restaurantCount >= 3 && item.averageRating !== null ? ` · ${item.averageRating.toFixed(1)} 分` : ''}</span>)}</div></section></>}<section><h3>证据餐厅</h3><div className="analytics-evidence-list source-evidence">{insight.restaurants.map((item) => <button key={item.restaurantId} onClick={() => { const restaurant = restaurants.find((candidate) => candidate.id === item.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button">{restaurantImage(restaurants, item.restaurantId) ? <img alt="" src={restaurantImage(restaurants, item.restaurantId)!} /> : <span className="source-evidence__placeholder"><Store size={17} /></span>}<span><strong>{item.name}</strong><small>{item.visitCount} 次到访{item.averageRating !== null ? ` · 我的平均 ${item.averageRating.toFixed(1)} 分` : ''}</small></span><ChevronRight size={16} /></button>)}</div></section><p className="analytics-permission-note">来源过去越适合你，只会成为未来推荐的一个信号，不会越过预算、距离、场景与长期口味。</p></div>
}

function SourceConclusion({ icon, label, value }: { icon: ReactNode; label: string; value: string }) { return <article><span>{icon}</span><small>{label}</small><strong>{value}</strong></article> }
function SourceMark({ insight }: { insight: RecommendationSourceInsight }) { const icon = insight.type === 'friend' ? <UserRound size={18} /> : insight.type === 'self' ? <Search size={18} /> : insight.label.includes('同味') ? <UsersRound size={18} /> : insight.label.includes('为你推荐') ? <Sparkles size={18} /> : <Compass size={18} />; return <span className={`source-mark source-mark--${insight.type}`}>{icon}</span> }
function sourceAccuracy(insight: RecommendationSourceInsight) { if (!insight.ratedRestaurantCount) return null; const high = insight.highRatingHitRate ?? 0; const repeat = insight.repeatRestaurantRate ?? 0; return Math.round((high * .75 + repeat * .25) * 100) }
function sourceDescription(insight: RecommendationSourceInsight) { if (insight.confidence === 'INSUFFICIENT') return '继续到访后再判断'; if (insight.cuisines[0]) return `${insight.cuisines[0].label}推荐对你更有效`; return '已通过真实到访验证' }
function groupSourceInsights(insights: RecommendationSourceInsight[]) { const labels = [['人', (item: RecommendationSourceInsight) => item.type === 'friend'], ['平台', (item: RecommendationSourceInsight) => !['friend', 'self'].includes(item.type) && !item.label.includes('同味') && !item.label.includes('为你推荐')], ['Taste Map', (item: RecommendationSourceInsight) => item.label.includes('同味') || item.label.includes('为你推荐')], ['自己发现', (item: RecommendationSourceInsight) => item.type === 'self']] as const; return labels.map(([label, filter]) => ({ label, items: insights.filter(filter) })).filter((group) => group.items.length) }
function restaurantImage(restaurants: RestaurantSummary[], restaurantId: string) { const restaurant = restaurants.find((item) => item.id === restaurantId); return restaurant?.merchantImageUrl ?? restaurant?.markerImageData ?? null }

function CompanionAvatar({ name }: { name: string }) { return <span className="companion-avatar">{name.slice(0, 1)}</span> }
function CompanionSummaryCard({ insight, icon, label, value }: { insight: ReturnType<typeof buildCompanionInsights>; icon: ReactNode; label: string; value: string }) { return <article><span className="companion-summary__label">{icon}{label}</span><CompanionAvatar name={insight.companion.displayName} /><strong>{insight.companion.displayName}</strong><small>{value}</small></article> }
function Metric({ label, value, icon }: { label: string; value: string; icon?: ReactNode }) { return <span>{icon}<strong>{value}</strong><small>{label}</small></span> }
function EmptyAnalysis({ text }: { text: string }) { return <div className="analytics-empty"><MapPin size={22} /><p>{text}</p></div> }
function confidenceLabel(value: ReturnType<typeof buildCompanionInsights>['confidence']) { return value === 'INSUFFICIENT' ? '样本不足' : value === 'EMERGING' ? '逐渐形成' : '稳定画像' }
function sourceConfidenceLabel(value: RecommendationSourceInsight['confidence']) { return value === 'INSUFFICIENT' ? '样本不足' : value === 'EMERGING' ? '样本较少' : value === 'LOW' ? '轻度可信' : '稳定样本' }
function shortDate(value: string) { return new Date(value).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' }) }
