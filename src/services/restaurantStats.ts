import { SOCIAL_API_ENABLED } from '../config/appEnvironment'
import { apiURL } from '../config/apiEnvironment'
import type { RestaurantSocialStats } from '../types/restaurantStats'

export async function fetchRestaurantSocialStats(amapPoiId: string, signal?: AbortSignal): Promise<RestaurantSocialStats | null> {
  if (!SOCIAL_API_ENABLED || !amapPoiId) return null
  const response = await fetch(apiURL(`/api/restaurants/${encodeURIComponent(amapPoiId)}/stats`), {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
    cache: 'no-store',
    signal,
  })
  const payload: unknown = await response.json().catch(() => null)
  if (!response.ok) throw new Error(readError(payload) ?? `评分参考请求失败（${response.status}）`)
  return payload as RestaurantSocialStats
}

function readError(value: unknown) {
  return value && typeof value === 'object' && typeof (value as Record<string, unknown>).error === 'string'
    ? String((value as Record<string, unknown>).error)
    : null
}
