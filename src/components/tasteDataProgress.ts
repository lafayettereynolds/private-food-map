import type { RestaurantSummary } from '../types/domain'

export interface TasteDataProgress {
  ratedRestaurantCount: number
  displayCount: number
  target: 5 | 10 | 15 | 20
  remaining: number
  message: string
  fraction: number
  isComplete: boolean
}

export function tasteDataProgress(restaurants: readonly RestaurantSummary[]): TasteDataProgress {
  const ratedRestaurantIDs = new Set<string>()
  for (const restaurant of restaurants) {
    if (restaurant.deletedAt != null || !restaurant.visits.some((visit) => visit.deletedAt == null && isValidTasteRating(visit.rating))) continue
    const restaurantID = restaurant.id.trim().toLowerCase()
    if (restaurantID) ratedRestaurantIDs.add(restaurantID)
  }
  return tasteDataProgressForCount(ratedRestaurantIDs.size)
}

export function tasteDataProgressForCount(value: number): TasteDataProgress {
  const ratedRestaurantCount = Math.max(0, Math.floor(Number.isFinite(value) ? value : 0))
  const displayCount = Math.min(ratedRestaurantCount, 20)
  const target: TasteDataProgress['target'] = ratedRestaurantCount <= 5
    ? 5
    : ratedRestaurantCount <= 10
      ? 10
      : ratedRestaurantCount <= 15
        ? 15
        : 20
  const remaining = Math.max(0, target - displayCount)
  const message = remaining > 0
    ? ratedRestaurantCount <= 5
      ? `再评分 ${remaining} 家，开始形成你的口味判断`
      : ratedRestaurantCount <= 10
        ? `再评分 ${remaining} 家，推荐和分析会更准确`
        : ratedRestaurantCount <= 15
          ? `再评分 ${remaining} 家，口味分析会更完整`
          : `再评分 ${remaining} 家，口味判断会更稳定`
    : target === 5
      ? '开始形成你的口味判断'
      : target === 10
        ? '推荐和分析正在变得更准确'
        : target === 15
          ? '口味分析正在变得更完整'
          : '口味数据已较稳定'

  return {
    ratedRestaurantCount,
    displayCount,
    target,
    remaining,
    message,
    fraction: displayCount / target,
    isComplete: ratedRestaurantCount >= 20,
  }
}

function isValidTasteRating(value: number | null): boolean {
  return value != null
    && Number.isFinite(value)
    && value >= 0.5
    && value <= 5
    && Number.isInteger(value * 2)
}
