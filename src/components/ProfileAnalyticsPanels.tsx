import { useEffect, useMemo, useState, type ChangeEvent, type ReactNode } from 'react'
import { ArrowLeft, Award, BarChart3, CalendarDays, ChevronRight, CircleDollarSign, Clock3, Compass, ImagePlus, Link2, MapPin, MapPinned, PencilLine, Repeat2, Search, Sparkles, Store, Target, Trash2, TrendingDown, TrendingUp, UserRound, Utensils, UsersRound, WalletCards } from 'lucide-react'
import type { DiningCompanion, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { buildCompanionDirectory, buildCompanionInsights, companionKind, companionProfileLabel, resolveCompanionAvatar, selectCompanionInsights, type CompanionListMode } from '../services/companionInsights'
import { buildRecommendationSourceInsights, selectWorstRecommendationSource, type RecommendationSourceInsight } from '../services/recommendationSourceInsights'
import { recommendationService } from '../services/recommendationService'
import { SyncedImage } from './SyncedImage'
import { UserAvatar } from './UserAvatar'
import { updateDiningCompanionProfile } from '../db/diningCompanions'

export function CompanionInsightsPanel({ companions, linkedUsers = [], ownerUserId, restaurants, visits, onSelectRestaurant }: { companions: DiningCompanion[]; linkedUsers?: UserProfile[]; ownerUserId: string; restaurants: RestaurantSummary[]; visits: Visit[]; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const directory = useMemo(() => buildCompanionDirectory(companions, visits, ownerUserId), [companions, ownerUserId, visits])
  const insights = useMemo(() => directory.map((companion) => buildCompanionInsights(companion, restaurants, visits)), [directory, restaurants, visits])
  const linkedUserById = useMemo(() => new Map(linkedUsers.map((user) => [user.id, user])), [linkedUsers])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [mode, setMode] = useState<CompanionListMode>('ALL')
  const selected = insights.find((item) => item.companion.id === selectedId)
  const visibleInsights = useMemo(() => selectCompanionInsights(insights, mode, query), [insights, mode, query])
  const defaultInsights = useMemo(() => selectCompanionInsights(insights, 'ALL'), [insights])
  const mostRestaurants = [...insights].sort((a, b) => b.restaurantCount - a.restaurantCount || b.sharedVisitCount - a.sharedVisitCount)[0]
  const mostRecent = [...insights].filter((item) => item.latestVisitedAt).sort((a, b) => (b.latestVisitedAt ?? '').localeCompare(a.latestVisitedAt ?? ''))[0]
  const linkedUserFor = (companion: DiningCompanion) => companion.linkedUserId ? linkedUserById.get(companion.linkedUserId) ?? null : null
  if (selected) return <CompanionDetail insight={selected} key={selected.companion.id} linkedUser={linkedUserFor(selected.companion)} onBack={() => setSelectedId(null)} onSelectRestaurant={onSelectRestaurant} ownerUserId={ownerUserId} restaurants={restaurants} visits={visits} />
  return <div className="analytics-directory">
    {insights.length ? <>
      <section className="companion-summary"><h3><Sparkles size={15} />关系摘要</h3><div className="companion-summary__grid"><CompanionSummaryCard icon={<Utensils size={15} />} insight={defaultInsights[0]} label="最常一起吃" linkedUser={linkedUserFor(defaultInsights[0].companion)} value={`${defaultInsights[0].sharedVisitCount} 次`} /><CompanionSummaryCard icon={<Store size={15} />} insight={mostRestaurants} label="一起去过最多" linkedUser={linkedUserFor(mostRestaurants.companion)} value={`${mostRestaurants.restaurantCount} 家`} /><CompanionSummaryCard icon={<CalendarDays size={15} />} insight={mostRecent} label="最近一起吃过" linkedUser={linkedUserFor(mostRecent.companion)} value={mostRecent.latestVisitedAt ? shortDate(mostRecent.latestVisitedAt) : '—'} /></div></section>
      <section className="companion-directory-section">
        <header><h3><UsersRound size={16} />饭搭子列表</h3><span>{visibleInsights.length} 位</span></header>
        <label className="companion-search"><Search size={17} /><input onChange={(event) => setQuery(event.target.value)} placeholder="搜索饭搭子" value={query} /></label>
        <div className="companion-filters" aria-label="饭搭子筛选">{([['ALL', '全部'], ['RECENT', '最近一起吃过'], ['FREQUENT', '更常一起吃'], ['HISTORICAL', '历史饭搭子']] as const).map(([value, label]) => <button aria-pressed={mode === value} className={mode === value ? 'is-active' : ''} key={value} onClick={() => setMode(value)} type="button">{label}</button>)}</div>
        {visibleInsights.length ? <div className="analytics-card-list companion-card-list">{visibleInsights.map((insight) => <button key={insight.companion.id} onClick={() => setSelectedId(insight.companion.id)} type="button"><CompanionAvatar companion={insight.companion} linkedUser={linkedUserFor(insight.companion)} /><span><span className="companion-card-list__title"><strong>{insight.companion.displayName}</strong>{insight.companion.relationshipLabel ? <i>{insight.companion.relationshipLabel}</i> : companionKind(insight.companion) === 'CATEGORY_LIKE' ? <i>关系类别</i> : null}</span><small><Utensils size={13} />一起吃过 {insight.sharedVisitCount} 次 · <Store size={13} />去过 {insight.restaurantCount} 家</small><small>{insight.latestVisitedAt ? `最近一起 ${shortDate(insight.latestVisitedAt)}` : '共同记录正在形成'}{insight.topCuisines[0] ? ` · 常吃 ${insight.topCuisines[0].label}` : ''}</small></span><em>{companionProfileLabel(insight.confidence)}</em><ChevronRight size={18} /></button>)}</div> : null}
      </section>
      {!visibleInsights.length ? <EmptyAnalysis text={mode === 'HISTORICAL' && !query.trim() ? '还没有历史饭搭子。和某个人有更多共同到访、并经过一段时间后，这里会出现过去常一起吃饭的人。' : '当前筛选中没有找到这个饭搭子。'} /> : null}
    </> : <EmptyAnalysis text="记录饭搭子后，这里会逐渐形成你们的共同用餐档案。" />}
  </div>
}

function CompanionDetail({ insight, linkedUser, ownerUserId, restaurants, visits, onBack, onSelectRestaurant }: { insight: ReturnType<typeof buildCompanionInsights>; linkedUser: UserProfile | null; ownerUserId: string; restaurants: RestaurantSummary[]; visits: Visit[]; onBack: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const recommendations = useMemo(() => recommendationService.recommend(restaurants, visits, { type: 'for_you', surface: 'discover', city: insight.cities[0]?.label ?? null, partyContext: 'group', preferExploration: true }).slice(0, 3), [insight.cities, restaurants, visits])
  const [editing, setEditing] = useState(false)
  const [displayName, setDisplayName] = useState(insight.companion.displayName)
  const [relationshipLabel, setRelationshipLabel] = useState(insight.companion.relationshipLabel ?? '')
  const [privateAvatarData, setPrivateAvatarData] = useState<string | null>(insight.companion.privateAvatarData ?? null)
  const [saving, setSaving] = useState(false)
  const [editError, setEditError] = useState('')
  const onAvatarFile = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    if (!file.type.startsWith('image/')) { setEditError('请选择图片文件'); return }
    if (file.size > 3 * 1024 * 1024) { setEditError('头像图片不能超过 3 MB'); return }
    const reader = new FileReader()
    reader.onload = () => { setPrivateAvatarData(typeof reader.result === 'string' ? reader.result : null); setEditError('') }
    reader.onerror = () => setEditError('头像读取失败，请重新选择')
    reader.readAsDataURL(file)
  }
  const saveProfile = async () => {
    setSaving(true)
    setEditError('')
    try {
      await updateDiningCompanionProfile(insight.companion, ownerUserId, { displayName, relationshipLabel, privateAvatarData })
      setEditing(false)
    } catch (error) {
      setEditError(error instanceof Error ? error.message : '保存失败，请重试')
    } finally {
      setSaving(false)
    }
  }
  return <div className="analytics-detail">
    <button className="analytics-back" onClick={onBack} type="button"><ArrowLeft size={16} />饭搭子列表</button>
    <header className="companion-detail-header"><CompanionAvatar companion={{ ...insight.companion, privateAvatarData }} linkedUser={linkedUser} /><div><strong>{insight.companion.displayName}</strong><small>{insight.companion.relationshipLabel ? `${insight.companion.relationshipLabel} · ` : ''}{companionKind(insight.companion) === 'CATEGORY_LIKE' ? '关系类别汇总' : insight.companion.linkedUserId ? '已关联 Taste Map 用户' : '历史饭搭子'}{insight.latestVisitedAt ? ` · 最近 ${shortDate(insight.latestVisitedAt)}` : ''}</small></div><button className="companion-edit-trigger" onClick={() => setEditing((value) => !value)} type="button"><PencilLine size={14} />编辑</button><em>{companionProfileLabel(insight.confidence)}</em></header>
    {editing ? <section className="companion-profile-editor">
      <header><h3>编辑饭搭子</h3><small>仅用于你自己的识别，不会修改已关联用户的公开资料。</small></header>
      <div className="companion-profile-editor__avatar"><CompanionAvatar companion={{ ...insight.companion, privateAvatarData }} linkedUser={linkedUser} /><label><ImagePlus size={14} />选择头像<input accept="image/*" onChange={onAvatarFile} type="file" /></label>{privateAvatarData ? <button onClick={() => setPrivateAvatarData(null)} type="button"><Trash2 size={14} />移除</button> : null}</div>
      <label><span>称呼</span><input maxLength={24} onChange={(event) => setDisplayName(event.target.value)} value={displayName} /></label>
      <label><span>关系（可选）</span><input maxLength={20} onChange={(event) => setRelationshipLabel(event.target.value)} placeholder="例如：家人、同事、大学同学" value={relationshipLabel} /></label>
      {linkedUser ? <p>已关联真实用户时，头像优先显示对方的公开头像；你上传的私人头像会保留为解除关联后的备用头像。</p> : null}
      {editError ? <p className="companion-profile-editor__error" role="alert">{editError}</p> : null}
      <footer><button onClick={() => { setEditing(false); setEditError('') }} type="button">取消</button><button disabled={saving || !displayName.trim()} onClick={saveProfile} type="button">{saving ? '保存中…' : '保存'}</button></footer>
    </section> : null}
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
  const [selectedState, setSelectedState] = useState<{ id: string; focus: 'NORMAL' | 'WORST' } | null>(null)
  const selected = insights.find((item) => item.id === selectedState?.id)
  const mostFrequent = insights[0]
  const bestMatched = [...insights].filter((item) => sourceAccuracy(item) !== null).sort((a, b) => (sourceAccuracy(b) ?? -1) - (sourceAccuracy(a) ?? -1))[0]
  const mostStable = [...insights].filter((item) => item.ratedRestaurantCount >= 10).sort((a, b) => (sourceAccuracy(b) ?? -1) - (sourceAccuracy(a) ?? -1) || b.ratedRestaurantCount - a.ratedRestaurantCount)[0] ?? bestMatched
  const worstSource = useMemo(() => selectWorstRecommendationSource(insights), [insights])
  const worstSourceId = worstSource?.insight.id
  const worstSourceSampleCount = worstSource?.insight.ratedRestaurantCount
  const latestSuccessful = [...insights].flatMap((source) => source.restaurants.map((restaurant) => ({ source, restaurant }))).filter((item) => item.restaurant.averageRating !== null).sort((a, b) => (b.restaurant.averageRating ?? 0) - (a.restaurant.averageRating ?? 0))[0]
  const groups = groupSourceInsights(insights)
  useEffect(() => {
    if (worstSourceId) emitWorstSourceAnalytics('recommendation_source_worst_view', worstSourceSampleCount ?? 0)
  }, [worstSourceId, worstSourceSampleCount])
  if (selected) return <SourceDetail insight={selected} onBack={() => setSelectedState(null)} onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} worstMode={selectedState?.focus === 'WORST'} />
  return <div className="analytics-directory source-analysis">
    {insights.length ? <>
      <section className="source-conclusion"><h3><Sparkles size={16} />本页结论</h3><div>
        <SourceConclusion disabled={!bestMatched} icon={<UserRound size={18} />} label="最懂我" onClick={() => bestMatched && setSelectedState({ id: bestMatched.id, focus: 'NORMAL' })} value={bestMatched?.label ?? '继续记录'} />
        <SourceConclusion disabled={!mostFrequent} icon={<Compass size={18} />} label="最容易种草" onClick={() => mostFrequent && setSelectedState({ id: mostFrequent.id, focus: 'NORMAL' })} value={mostFrequent?.label ?? '—'} />
        <SourceConclusion disabled={!mostStable} icon={<Target size={18} />} label="最稳定" onClick={() => mostStable && setSelectedState({ id: mostStable.id, focus: 'NORMAL' })} value={mostStable?.label ?? '继续记录'} />
        {worstSource ? <SourceConclusion icon={<TrendingDown size={18} />} label="最坑" onClick={() => { emitWorstSourceAnalytics('recommendation_source_worst_detail_open', worstSource.insight.ratedRestaurantCount); setSelectedState({ id: worstSource.insight.id, focus: 'WORST' }) }} tone="worst" value={worstSource.insight.label} /> : null}
      </div></section>
      <section className="source-list-card"><header><h3><BarChart3 size={16} />来源列表</h3><span>按真实到访结果排序</span></header>
        {groups.map((group) => <div className="source-group" key={group.label}><h4>{group.label}</h4>{group.items.map((insight, index) => <button key={insight.id} onClick={() => setSelectedState({ id: insight.id, focus: 'NORMAL' })} type="button"><span className="source-rank">{index + 1}</span><SourceMark insight={insight} /><span className="source-row-copy"><strong>{insight.label}</strong><small>发现 {insight.restaurantCount} 家 · 去过 {insight.visitedRestaurantCount} 家</small><em>{sourceDescription(insight)}</em></span><span className="source-accuracy"><small>推荐准确度</small><b>{sourceAccuracy(insight) === null ? '待积累' : `${sourceAccuracy(insight)}%`}</b></span><ChevronRight size={17} /></button>)}</div>)}
      </section>
      <section className="source-performance"><h3><TrendingUp size={16} />Taste Map 推荐表现</h3><div>{insights.filter((item) => item.label.includes('为你推荐') || item.label.includes('同味')).slice(0, 2).map((insight) => <button key={insight.id} onClick={() => setSelectedState({ id: insight.id, focus: 'NORMAL' })} type="button"><SourceMark insight={insight} /><span><strong>{insight.label}</strong><small>平均 {insight.averagePostVisitRating?.toFixed(1) ?? '—'} · 去过 {insight.visitedRestaurantCount} 家</small></span></button>)}{!insights.some((item) => item.label.includes('为你推荐') || item.label.includes('同味')) ? <p>还没有足够的 Taste Map 推荐结果，后续到访会自动接受同样的结果检验。</p> : null}</div></section>
      {latestSuccessful ? <section className="source-success-card"><h3><Award size={16} />最近最成功的一次推荐</h3><button onClick={() => { const restaurant = restaurants.find((item) => item.id === latestSuccessful.restaurant.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button">{restaurantImage(restaurants, latestSuccessful.restaurant.restaurantId) ? <img alt="" src={restaurantImage(restaurants, latestSuccessful.restaurant.restaurantId)!} /> : <span className="source-success-card__placeholder"><Store size={22} /></span>}<span><strong>{latestSuccessful.restaurant.name}</strong><small>{latestSuccessful.source.label} · 到访后 {latestSuccessful.restaurant.averageRating?.toFixed(1)} 分</small><em>查看证据</em></span><ChevronRight size={18} /></button></section> : null}
    </> : <EmptyAnalysis text="在到访记录中填写推荐来源后，这里会按独立餐厅统计真实结果。" />}
  </div>
}

function SourceDetail({ insight, restaurants, onBack, onSelectRestaurant, worstMode = false }: { insight: RecommendationSourceInsight; restaurants: RestaurantSummary[]; onBack: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void; worstMode?: boolean }) {
  const percent = (value: number | null) => value === null ? '—' : `${Math.round(value * 100)}%`
  const sufficientlyDetailed = insight.confidence !== 'INSUFFICIENT'
  const evidence = worstMode ? [...insight.restaurants].sort((a, b) => (a.averageRating ?? 11) - (b.averageRating ?? 11) || b.visitCount - a.visitCount) : insight.restaurants
  const baselineDelta = insight.ratingDeltaFromBaseline === null ? '—' : `${insight.ratingDeltaFromBaseline > 0 ? '+' : ''}${insight.ratingDeltaFromBaseline.toFixed(1)}`
  return <div className={`analytics-detail source-detail${worstMode ? ' source-detail--worst' : ''}`}><button className="analytics-back" onClick={onBack} type="button"><ArrowLeft size={16} />来源列表</button><header><SourceMark insight={insight} /><div><strong>{insight.label}</strong><small>{worstMode ? '“最坑”只代表它过去对你的实际结果相对较差' : '只代表这个来源过去对你的实际结果'}</small></div><em>{sourceConfidenceLabel(insight.confidence)}</em></header><section className="analytics-metrics"><Metric icon={<Store size={15} />} label="实际去过" value={`${insight.visitedRestaurantCount} 家`} /><Metric icon={<Award size={15} />} label="平均评分" value={sufficientlyDetailed && insight.averagePostVisitRating !== null ? insight.averagePostVisitRating.toFixed(1) : '—'} /><Metric icon={<Target size={15} />} label="高分命中" value={sufficientlyDetailed ? percent(insight.highRatingHitRate) : '—'} /><Metric icon={<Repeat2 size={15} />} label="再次到访" value={`${insight.repeatRestaurantCount} 家`} /></section>{insight.confidence === 'INSUFFICIENT' ? <p className="analytics-confidence-note">目前还没有足够数据判断这个来源的推荐表现。</p> : <><section><h3>真实结果</h3><div className="analytics-inline-stats"><span>低分比例 <b>{percent(insight.lowRatingRate)}</b></span><span>重复到访率 <b>{percent(insight.repeatRestaurantRate)}</b></span><span>比我的整体平均 <b>{baselineDelta}</b></span>{insight.spend.sampleCount ? <span>我的平均消费 <b>¥{Math.round(insight.spend.average!)}</b></span> : null}</div></section><section><h3>最近表现</h3><p>{insight.recentRatedRestaurantCount ? `最近 ${insight.recentRatedRestaurantCount} 家有评分餐厅的平均为 ${insight.recentAverageRating?.toFixed(1)} 分。` : '最近还没有可用于判断的评分。'}</p></section><section><h3>{worstMode ? '相对不适合你的菜系' : '最适合你的菜系'}</h3><div className="analytics-tags">{insight.cuisines.map((item) => <span key={item.label}>{item.label} · {item.restaurantCount} 家{item.restaurantCount >= 3 && item.averageRating !== null ? ` · ${item.averageRating.toFixed(1)} 分` : ''}</span>)}</div></section></>}<section><h3>{worstMode ? '低分证据餐厅' : '证据餐厅'}</h3><div className="analytics-evidence-list source-evidence">{evidence.map((item) => <button key={item.restaurantId} onClick={() => { const restaurant = restaurants.find((candidate) => candidate.id === item.restaurantId); if (restaurant) onSelectRestaurant?.(restaurant) }} type="button">{restaurantImage(restaurants, item.restaurantId) ? <img alt="" src={restaurantImage(restaurants, item.restaurantId)!} /> : <span className="source-evidence__placeholder"><Store size={17} /></span>}<span><strong>{item.name}</strong><small>{item.visitCount} 次到访{item.averageRating !== null ? ` · 我的平均 ${item.averageRating.toFixed(1)} 分` : ''}</small></span><ChevronRight size={16} /></button>)}</div></section><p className="analytics-permission-note">来源过去越适合你，只会成为未来推荐的一个信号，不会越过预算、距离、场景与长期口味。</p></div>
}

function SourceConclusion({ icon, label, value, disabled = false, onClick, tone = 'default' }: { icon: ReactNode; label: string; value: string; disabled?: boolean; onClick?: () => void; tone?: 'default' | 'worst' }) { return <button className={`source-conclusion__item${tone === 'worst' ? ' source-conclusion__item--worst' : ''}`} disabled={disabled} onClick={onClick} type="button"><span>{icon}</span><small>{label}</small><strong>{value}</strong></button> }
function SourceMark({ insight }: { insight: RecommendationSourceInsight }) { const icon = insight.type === 'friend' ? <UserRound size={18} /> : insight.type === 'self' ? <Search size={18} /> : insight.label.includes('同味') ? <UsersRound size={18} /> : insight.label.includes('为你推荐') ? <Sparkles size={18} /> : <Compass size={18} />; return <span className={`source-mark source-mark--${insight.type}`}>{icon}</span> }
function sourceAccuracy(insight: RecommendationSourceInsight) { if (!insight.ratedRestaurantCount) return null; const high = insight.highRatingHitRate ?? 0; const repeat = insight.repeatRestaurantRate ?? 0; return Math.round((high * .75 + repeat * .25) * 100) }
function sourceDescription(insight: RecommendationSourceInsight) { if (insight.confidence === 'INSUFFICIENT') return '继续到访后再判断'; if (insight.cuisines[0]) return `${insight.cuisines[0].label}推荐对你更有效`; return '已通过真实到访验证' }
function groupSourceInsights(insights: RecommendationSourceInsight[]) { const labels = [['人', (item: RecommendationSourceInsight) => item.type === 'friend'], ['平台', (item: RecommendationSourceInsight) => !['friend', 'self'].includes(item.type) && !item.label.includes('同味') && !item.label.includes('为你推荐')], ['Taste Map', (item: RecommendationSourceInsight) => item.label.includes('同味') || item.label.includes('为你推荐')], ['自己发现', (item: RecommendationSourceInsight) => item.type === 'self']] as const; return labels.map(([label, filter]) => ({ label, items: insights.filter(filter) })).filter((group) => group.items.length) }
function restaurantImage(restaurants: RestaurantSummary[], restaurantId: string) { const restaurant = restaurants.find((item) => item.id === restaurantId); return restaurant?.merchantImageUrl ?? restaurant?.markerImageData ?? null }

function CompanionAvatar({ companion, linkedUser }: { companion: DiningCompanion; linkedUser?: UserProfile | null }) {
  const avatar = resolveCompanionAvatar(companion, linkedUser)
  return <span aria-label={`${companion.displayName}的头像`} className={`companion-avatar companion-avatar--theme-${avatar.themeIndex} companion-avatar--${avatar.kind.toLocaleLowerCase()}`}>
    {linkedUser ? <UserAvatar alt={linkedUser.nickname} avatarImageData={linkedUser.avatarImageData} avatarPhotoId={linkedUser.avatarPhotoId} avatarPresetId={linkedUser.avatarPresetId} /> : avatar.kind === 'IMAGE' && avatar.imageData ? <img alt="" src={avatar.imageData} /> : avatar.kind === 'CATEGORY' ? <UsersRound aria-hidden="true" size={18} /> : avatar.kind === 'CHARACTER' ? avatar.character : <UserRound aria-hidden="true" size={18} />}
  </span>
}
function CompanionSummaryCard({ insight, linkedUser, icon, label, value }: { insight: ReturnType<typeof buildCompanionInsights>; linkedUser?: UserProfile | null; icon: ReactNode; label: string; value: string }) { return <article><span className="companion-summary__label">{icon}{label}</span><CompanionAvatar companion={insight.companion} linkedUser={linkedUser} /><strong>{insight.companion.displayName}</strong><small>{value}</small></article> }
function Metric({ label, value, icon }: { label: string; value: string; icon?: ReactNode }) { return <span>{icon}<strong>{value}</strong><small>{label}</small></span> }
function EmptyAnalysis({ text }: { text: string }) { return <div className="analytics-empty"><MapPin size={22} /><p>{text}</p></div> }
function sourceConfidenceLabel(value: RecommendationSourceInsight['confidence']) { return value === 'INSUFFICIENT' ? '样本不足' : value === 'EMERGING' ? '样本较少' : value === 'LOW' ? '轻度可信' : '稳定样本' }
function shortDate(value: string) { return new Date(value).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' }) }
function emitWorstSourceAnalytics(event: 'recommendation_source_worst_view' | 'recommendation_source_worst_detail_open', sampleCount: number) {
  if (typeof window === 'undefined') return
  window.dispatchEvent(new CustomEvent('taste-map:product-analytics', { detail: { event, sampleCount } }))
}
