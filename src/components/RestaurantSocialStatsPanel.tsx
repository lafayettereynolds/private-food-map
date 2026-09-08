import { useEffect, useId, useState } from 'react'
import { createPortal } from 'react-dom'
import { Ghost, Info, LockKeyhole, RefreshCw, UsersRound, X } from 'lucide-react'
import { usePremiumAccess } from './PremiumAccess'
import { openPremiumPaywall } from '../services/premiumPaywall'
import { fetchRestaurantSocialStats } from '../services/restaurantStats'
import { groupRatingDisplay, personalRestaurantRating, type RatingConfidence } from '../services/ratingConfidence'
import { scoreColor, type RestaurantSummary } from '../types/domain'
import type { RestaurantSocialStats } from '../types/restaurantStats'
import { predictPersonalTasteScore } from '../services/personalTasteScore'
import { CURRENT_USER_ID } from '../db/social'

export interface PersonalRatingOverride {
  score: number | null
  count: number
  label: '我的评分' | '历史预测'
  description?: string
}

export function RestaurantSocialStatsPanel({ amapPoiId, restaurant, historyRestaurants = [], personalRatingOverride, remoteStatsEnabled = true, socialStats }: { amapPoiId: string; restaurant: RestaurantSummary; historyRestaurants?: RestaurantSummary[]; personalRatingOverride?: PersonalRatingOverride; remoteStatsEnabled?: boolean; socialStats?: RestaurantSocialStats | null }) {
  const hasAdapterStats = socialStats !== undefined
  const premium = usePremiumAccess()
  const [stats, setStats] = useState<RestaurantSocialStats | null>(socialStats ?? null)
  const [loading, setLoading] = useState(remoteStatsEnabled && !hasAdapterStats)
  const personalVisits = restaurant.visits.filter((visit) => visit.userId === CURRENT_USER_ID)
  const personalRating = personalRestaurantRating(personalVisits, CURRENT_USER_ID)
  const isCurrentUsersVisitedRestaurant = !restaurant.isRecommendation && restaurant.userId === CURRENT_USER_ID && restaurant.status === 'visited'
  const prediction = isCurrentUsersVisitedRestaurant ? null : predictPersonalTasteScore(restaurant, historyRestaurants)
  const [explanation, setExplanation] = useState<RatingExplanation | null>(null)
  const explanationId = useId()

  useEffect(() => {
    if (hasAdapterStats) {
      setStats(socialStats ?? null)
      setLoading(false)
      return
    }
    if (!remoteStatsEnabled) {
      setStats(null)
      setLoading(false)
      return
    }
    const controller = new AbortController()
    setLoading(true)
    void fetchRestaurantSocialStats(amapPoiId, controller.signal)
      .then((result) => setStats(result))
      .catch(() => setStats(null))
      .finally(() => setLoading(false))
    return () => controller.abort()
  }, [amapPoiId, hasAdapterStats, remoteStatsEnabled, socialStats])

  useEffect(() => setExplanation(null), [restaurant.id])

  const toggleExplanation = (next: RatingExplanation) => {
    setExplanation((current) => current?.key === next.key ? null : next)
  }

  return <section className="restaurant-social-stats" aria-label="评分参考" data-summary-module="rating-reference">
    <header><span><UsersRound size={13} />评分参考</span>{loading ? <RefreshCw className="is-spinning" size={12} /> : null}</header>
    <div className="restaurant-social-stats__ratings">
      <PersonalStat
        count={personalRatingOverride?.count ?? (prediction ? prediction.ratedRestaurantCount : personalRating.ratedVisitCount)}
        description={personalRatingOverride?.description ?? prediction?.description}
        expanded={explanation?.key === 'personal'}
        explanationId={explanationId}
        label={personalRatingOverride?.label ?? (prediction ? '历史预测' : '我的评分')}
        onExplain={toggleExplanation}
        value={personalRatingOverride ? personalRatingOverride.score : prediction?.score ?? personalRating.score}
      />
      <GroupStat count={stats?.overallUserCount ?? 0} expanded={explanation?.key === 'community'} explanationId={explanationId} group="community" label="全部用户" loading={loading} onExplain={toggleExplanation} value={stats?.overallUserRating ?? null} />
      <GroupStat count={stats?.friendUserCount ?? 0} expanded={explanation?.key === 'friends'} explanationId={explanationId} group="friends" label="好友评分" loading={loading} onExplain={toggleExplanation} value={stats?.friendAverageRating ?? null} />
      {premium ? <GroupStat count={stats?.similarTasteUserCount ?? 0} expanded={explanation?.key === 'similarTaste'} explanationId={explanationId} group="similarTaste" label="同味评分" loading={loading} onExplain={toggleExplanation} value={stats?.similarTasteAverageRating ?? null} /> : <button aria-label="同味评分，会员专享，点击解锁" className="score-reference-item is-locked" onClick={() => openPremiumPaywall('similar_taste')} type="button"><span className="score-reference-orb"><LockKeyhole aria-hidden="true" size={21} /></span><span><b>同味评分</b></span></button>}
    </div>
    {explanation && (explanation.key !== 'similarTaste' || premium) ? <RatingExplanationDialog explanation={explanation} id={explanationId} onClose={() => setExplanation(null)} /> : null}
  </section>
}

type RatingExplanationKey = 'personal' | 'community' | 'friends' | 'similarTaste'
interface RatingExplanation { key: RatingExplanationKey; label: string; detail: string }
interface ExplainableStatProps {
  expanded: boolean
  explanationId: string
  onExplain: (value: RatingExplanation) => void
}

function RatingExplanationDialog({ explanation, id, onClose }: { explanation: RatingExplanation; id: string; onClose: () => void }) {
  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose() }
    window.addEventListener('keydown', closeOnEscape)
    return () => window.removeEventListener('keydown', closeOnEscape)
  }, [onClose])

  if (typeof document === 'undefined') return null
  return createPortal(<div className="rating-explanation-backdrop" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose() }}><section aria-labelledby={`${id}-title`} aria-modal="true" className="rating-explanation-dialog" id={id} role="dialog"><header><span><Info aria-hidden="true" size={17} /><strong id={`${id}-title`}>{explanation.label}</strong></span><button aria-label="关闭评分说明" onClick={onClose} type="button"><X aria-hidden="true" size={18} /></button></header><p>{explanation.detail}</p></section></div>, document.body)
}

function PersonalStat({ value, count, label, description, expanded, explanationId, onExplain }: { value: number | null; count: number; label: string; description?: string } & ExplainableStatProps) {
  const displayValue = typeof value === 'number' && Number.isFinite(value) ? value : null
  const detail = description ?? (displayValue === null
    ? '当前还没有可用于显示这一项的有效评分。'
    : `基于你在这家餐厅的 ${count} 次有效评分计算。`)
  return <Stat confidence={displayValue === null ? 'NO_DATA' : 'NORMAL'} count={count} expanded={expanded} explanation={{ key: 'personal', label, detail }} explanationId={explanationId} label={label} loading={false} onExplain={onExplain} value={displayValue} />
}

function GroupStat({ label, value, count, loading, group, expanded, explanationId, onExplain }: { label: string; value: number | null; count: number; loading: boolean; group: Exclude<RatingExplanationKey, 'personal'> } & ExplainableStatProps) {
  const display = groupRatingDisplay(value, count)
  const audience = group === 'community' ? '全部用户' : group === 'friends' ? '好友' : '同味用户'
  const detail = display.confidence === 'NO_DATA'
    ? `当前还没有${audience}对这家餐厅的有效评分。`
    : display.confidence === 'INSUFFICIENT'
      ? `目前只有 ${count} 位${audience}留下有效评分，尚未达到公开显示分数的最低样本门槛。`
      : `基于 ${count} 位${audience}对这家餐厅的有效评分计算${display.confidence === 'LOW' ? '；当前样本较少，结果仅供参考。' : '。'}`
  return <Stat confidence={display.confidence} count={count} expanded={expanded} explanation={{ key: group, label, detail }} explanationId={explanationId} label={label} loading={loading} onExplain={onExplain} value={display.displayScore} />
}

function Stat({ label, value, count, loading, confidence, expanded, explanation, explanationId, onExplain }: { label: string; value: number | null; count: number; loading: boolean; confidence: RatingConfidence; expanded: boolean; explanation: RatingExplanation; explanationId: string; onExplain: (value: RatingExplanation) => void }) {
  const showEmptyGraphic = confidence === 'NO_DATA' && !loading
  const showInsufficient = confidence === 'INSUFFICIENT' && !loading
  const showScore = value !== null && !loading
  const color = showScore ? scoreColor(value) : undefined
  return <button aria-controls={explanationId} aria-expanded={expanded} aria-label={`查看${label}说明`} className={`score-reference-item${label === '我的评分' || label === '历史预测' ? ' is-personal' : ''}${showEmptyGraphic || showInsufficient ? ' is-empty' : ''}${confidence === 'LOW' ? ' is-low-confidence' : ''}${expanded ? ' is-selected' : ''}`} onClick={() => onExplain(explanation)} type="button"><span className="score-reference-orb" style={color ? { borderColor: color, color } : undefined}>{loading ? <strong>—</strong> : showScore ? <strong>{value.toFixed(1)}</strong> : showInsufficient ? <span className="score-reference-empty is-insufficient"><Ghost aria-hidden="true" size={16} strokeWidth={1.35} /><em>样本不足</em></span> : showEmptyGraphic ? <span aria-label={`${label}暂无数据`} className="score-reference-empty"><Ghost aria-hidden="true" size={18} strokeWidth={1.4} /><em>暂无数据</em></span> : <strong>—</strong>}<i aria-label={`${count} 个有效样本`}>{loading ? '…' : count}</i></span><span><b>{label}</b></span></button>
}
