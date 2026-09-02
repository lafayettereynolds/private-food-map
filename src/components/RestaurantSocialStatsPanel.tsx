import { useEffect, useState } from 'react'
import { Ghost, RefreshCw, UsersRound } from 'lucide-react'
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

export function RestaurantSocialStatsPanel({ amapPoiId, restaurant, historyRestaurants = [], personalRatingOverride, remoteStatsEnabled = true }: { amapPoiId: string; restaurant: RestaurantSummary; historyRestaurants?: RestaurantSummary[]; personalRatingOverride?: PersonalRatingOverride; remoteStatsEnabled?: boolean }) {
  const [stats, setStats] = useState<RestaurantSocialStats | null>(null)
  const [loading, setLoading] = useState(remoteStatsEnabled)
  const personalVisits = restaurant.visits.filter((visit) => visit.userId === CURRENT_USER_ID)
  const personalRating = personalRestaurantRating(personalVisits, CURRENT_USER_ID)
  const isCurrentUsersVisitedRestaurant = !restaurant.isRecommendation && restaurant.userId === CURRENT_USER_ID && restaurant.status === 'visited'
  const prediction = isCurrentUsersVisitedRestaurant ? null : predictPersonalTasteScore(restaurant, historyRestaurants)

  useEffect(() => {
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
  }, [amapPoiId, remoteStatsEnabled])

  return <section className="restaurant-social-stats" aria-label="评分参考" data-summary-module="rating-reference">
    <header><span><UsersRound size={13} />评分参考</span>{loading ? <RefreshCw className="is-spinning" size={12} /> : null}</header>
    <div className="restaurant-social-stats__ratings">
      <PersonalStat
        count={personalRatingOverride?.count ?? (prediction ? prediction.ratedRestaurantCount : personalRating.ratedVisitCount)}
        description={personalRatingOverride?.description ?? prediction?.description}
        label={personalRatingOverride?.label ?? (prediction ? '历史预测' : '我的评分')}
        value={personalRatingOverride ? personalRatingOverride.score : prediction?.score ?? personalRating.score}
      />
      <GroupStat count={stats?.overallUserCount ?? 0} label="全部用户" loading={loading} value={stats?.overallUserRating ?? null} />
      <GroupStat count={stats?.friendUserCount ?? 0} label="好友评分" loading={loading} value={stats?.friendAverageRating ?? null} />
      <GroupStat count={stats?.similarTasteUserCount ?? 0} label="同味评分" loading={loading} value={stats?.similarTasteAverageRating ?? null} />
    </div>
  </section>
}

function PersonalStat({ value, count, label, description }: { value: number | null; count: number; label: string; description?: string }) {
  return <Stat confidence={value === null ? 'NO_DATA' : 'NORMAL'} count={count} label={label} loading={false} sampleLabel={value === null ? (label === '历史预测' ? '记录更多评分后生成' : '未评分') : description ?? null} value={value} />
}

function GroupStat({ label, value, count, loading }: { label: string; value: number | null; count: number; loading: boolean }) {
  const display = groupRatingDisplay(value, count)
  return <Stat confidence={display.confidence} count={count} label={label} loading={loading} sampleLabel={display.sampleLabel} value={display.displayScore} />
}

function Stat({ label, value, count, loading, confidence, sampleLabel }: { label: string; value: number | null; count: number; loading: boolean; confidence: RatingConfidence; sampleLabel: string | null }) {
  const showEmptyGraphic = confidence === 'NO_DATA' && !loading
  const showInsufficient = confidence === 'INSUFFICIENT' && !loading
  const showScore = value !== null && !loading
  const color = showScore ? scoreColor(value) : undefined
  return <article className={`score-reference-item${label === '我的评分' || label === '历史预测' ? ' is-personal' : ''}${showEmptyGraphic || showInsufficient ? ' is-empty' : ''}${confidence === 'LOW' ? ' is-low-confidence' : ''}`}><span className="score-reference-orb" style={color ? { borderColor: color, color } : undefined}>{loading ? <strong>—</strong> : showScore ? <strong>{value.toFixed(1)}</strong> : showInsufficient ? <span className="score-reference-empty is-insufficient"><Ghost size={16} strokeWidth={1.35} /><em>样本不足</em></span> : showEmptyGraphic && label !== '我的评分' && label !== '历史预测' ? <span className="score-reference-empty"><Ghost size={18} strokeWidth={1.4} /><em>暂无数据</em></span> : <strong>—</strong>}<i aria-label={`${count} 个有效样本`}>{loading ? '…' : count}</i></span><span><b>{label}</b>{loading || (sampleLabel && !showInsufficient) ? <small className={confidence === 'LOW' ? 'is-low-confidence' : ''}>{loading ? '正在读取评分' : sampleLabel}</small> : null}</span></article>
}
