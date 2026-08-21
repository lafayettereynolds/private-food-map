import { searchRestaurantPois } from './amap'
import type { PoiSearchResult, RestaurantSummary } from '../types/domain'

interface TasteKeyword {
  keyword: string
  weight: number
}

interface RankedPoi {
  poi: PoiSearchResult
  score: number
  reasons: string[]
}

const NON_TASTE_TAGS = /约会|聚餐|朋友|家人|同事|会再去|打卡|环境|服务|性价比|商场|中心|广场|银泰|来福士|附近|路|街|区$/
const CUISINE_WORDS = [
  '杭帮菜', '日料', '寿司', '烧鸟', '烧肉', '烤肉', '火锅', '粤菜', '川菜', '湘菜',
  '云南菜', '泰国菜', '新加坡料理', '东南亚菜', '西餐', '牛排', '海鲜', '融合菜',
  '素食', '面馆', '小吃', '甜品', '咖啡', '茶餐厅', '私房菜', '烧烤',
]

export async function fetchTasteRecommendations(
  restaurants: RestaurantSummary[],
): Promise<RestaurantSummary[]> {
  const visited = restaurants.filter(
    (restaurant) => restaurant.status === 'visited' && restaurant.scoreOutOfTen !== null,
  )
  if (!visited.length) return []

  const keywords = buildTasteKeywords(visited).slice(0, 4)
  if (!keywords.length) return []

  const city = mostLikedCity(visited)
  const existingPoiIds = new Set(restaurants.map((restaurant) => restaurant.amapPoiId))
  const existingNames = new Set(restaurants.map((restaurant) => normalizeName(restaurant.name)))
  const searches = await Promise.allSettled(
    keywords.map(async (item) => ({
      item,
      pois: await withTimeout(searchRestaurantPois(item.keyword, city), 8_000),
    })),
  )
  const successfulSearches = searches.filter(
    (result): result is PromiseFulfilledResult<{ item: TasteKeyword; pois: PoiSearchResult[] }> => result.status === 'fulfilled',
  )
  if (!successfulSearches.length) {
    const firstFailure = searches.find((result) => result.status === 'rejected')
    throw firstFailure?.status === 'rejected' && firstFailure.reason instanceof Error
      ? firstFailure.reason
      : new Error('推荐加载失败，请稍后再试。')
  }
  const ranked = new Map<string, RankedPoi>()

  successfulSearches.forEach((result) => {
    const { item, pois } = result.value
    pois.slice(0, 4).forEach((poi, index) => {
      if (existingPoiIds.has(poi.amapPoiId) || existingNames.has(normalizeName(poi.name))) return
      const current = ranked.get(poi.amapPoiId)
      const positionBonus = Math.max(0, 2 - index * 0.12)
      const reason = `你常给“${item.keyword}”相关餐厅高分`
      if (current) {
        current.score += item.weight + positionBonus
        if (!current.reasons.includes(reason)) current.reasons.push(reason)
      } else {
        ranked.set(poi.amapPoiId, {
          poi,
          score: item.weight + positionBonus,
          reasons: [reason],
        })
      }
    })
  })

  const now = new Date().toISOString()
  return [...ranked.values()]
    .sort((a, b) => b.score - a.score || a.poi.name.localeCompare(b.poi.name, 'zh-CN'))
    .slice(0, 12)
    .map(({ poi, score, reasons }) => ({
      id: `recommendation-${poi.amapPoiId}`,
      amapPoiId: poi.amapPoiId,
      name: poi.name,
      address: poi.address,
      city: poi.city,
      latitude: poi.latitude,
      longitude: poi.longitude,
      status: 'wantToGo',
      preferenceLevel: 'normal',
      overallRating: null,
      foodRating: null,
      environmentRating: null,
      serviceRating: null,
      valueRating: null,
      tags: keywords.filter((item) => reasons.some((reason) => reason.includes(`“${item.keyword}”`))).map((item) => item.keyword),
      longTermNote: '',
      pricePerPerson: null,
      markerType: poi.merchantImageUrl ? 'image' : 'emoji',
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: poi.merchantImageUrl,
      markerEmoji: '🍽️',
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      visitCount: 0,
      averageRating: null,
      scoreOutOfTen: null,
      latestVisitDate: null,
      latestVisit: null,
      visits: [],
      averagePricePerPerson: null,
      averageQueueMinutes: null,
      recommendationScore: score,
      recommendationReason: reasons[0],
      isRecommendation: true,
    }))
}

function buildTasteKeywords(restaurants: RestaurantSummary[]): TasteKeyword[] {
  const scores = new Map<string, number>()

  restaurants.forEach((restaurant) => {
    const rating = restaurant.scoreOutOfTen ?? 0
    if (rating < 7) return
    const restaurantWeight = Math.max(1, rating - 6) * Math.max(1, Math.sqrt(restaurant.visitCount))

    restaurant.tags.forEach((tag) => {
      const keyword = tag.trim()
      if (!keyword || NON_TASTE_TAGS.test(keyword)) return
      scores.set(keyword, (scores.get(keyword) ?? 0) + restaurantWeight)
    })

    CUISINE_WORDS.forEach((keyword) => {
      if (restaurant.name.includes(keyword)) {
        scores.set(keyword, (scores.get(keyword) ?? 0) + restaurantWeight * 0.8)
      }
    })

    restaurant.visits.forEach((visit) => {
      visit.dishes.forEach((dish) => {
        if (!dish.name.trim() || (dish.rating ?? 0) < 4) return
        scores.set(dish.name.trim(), (scores.get(dish.name.trim()) ?? 0) + (dish.rating ?? 0) * 1.2)
      })
    })
  })

  return [...scores.entries()]
    .map(([keyword, weight]) => ({ keyword, weight }))
    .sort((a, b) => b.weight - a.weight || a.keyword.localeCompare(b.keyword, 'zh-CN'))
}

function mostLikedCity(restaurants: RestaurantSummary[]) {
  const scores = new Map<string, number>()
  restaurants.forEach((restaurant) => {
    const score = restaurant.scoreOutOfTen ?? 0
    if (score < 7 || !restaurant.city) return
    scores.set(restaurant.city, (scores.get(restaurant.city) ?? 0) + score * Math.max(1, restaurant.visitCount))
  })
  return [...scores.entries()].sort((a, b) => b[1] - a[1])[0]?.[0]
}

function normalizeName(name: string) {
  return name.toLocaleLowerCase('zh-CN').replace(/[\s·•・()（）\-—_]/g, '')
}

function withTimeout<T>(promise: Promise<T>, milliseconds: number) {
  return new Promise<T>((resolve, reject) => {
    const timeout = window.setTimeout(() => reject(new Error('推荐查询超时，请稍后再试。')), milliseconds)
    promise.then(
      (value) => {
        window.clearTimeout(timeout)
        resolve(value)
      },
      (error) => {
        window.clearTimeout(timeout)
        reject(error)
      },
    )
  })
}
