import { useEffect, useState } from 'react'
import { RefreshCw, UsersRound } from 'lucide-react'
import { fetchRestaurantSocialStats } from '../services/restaurantStats'
import type { RestaurantSocialStats } from '../types/restaurantStats'

export function RestaurantSocialStatsPanel({ amapPoiId }: { amapPoiId: string }) {
  const [stats, setStats] = useState<RestaurantSocialStats | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const controller = new AbortController()
    setLoading(true)
    void fetchRestaurantSocialStats(amapPoiId, controller.signal)
      .then((result) => setStats(result))
      .catch(() => setStats(null))
      .finally(() => setLoading(false))
    return () => controller.abort()
  }, [amapPoiId])

  if (!loading && !stats) return null
  return <section className="restaurant-social-stats" aria-label="评分参考">
    <header><span><UsersRound size={13} />评分参考</span>{loading ? <RefreshCw className="is-spinning" size={12} /> : null}</header>
    <div className="restaurant-social-stats__ratings">
      <Stat label="全部用户" loading={loading} value={stats?.overallUserRating ?? null} />
      <Stat label="好友" loading={loading} value={stats?.friendAverageRating ?? null} />
      <Stat label="口味相似" loading={loading} value={stats?.similarTasteAverageRating ?? null} />
    </div>
    <div className="restaurant-social-stats__repeat"><span>重复到访</span><strong>{loading ? '读取中' : stats?.repeatVisitRate === null || stats?.repeatVisitRate === undefined ? '暂无足够数据' : `${stats.repeatVisitRate}% 用户重复到访`}</strong></div>
  </section>
}

function Stat({ label, value, loading }: { label: string; value: number | null; loading: boolean }) {
  return <span><small>{label}</small><strong>{loading ? '—' : value === null ? '暂无足够数据' : value.toFixed(1)}</strong></span>
}
