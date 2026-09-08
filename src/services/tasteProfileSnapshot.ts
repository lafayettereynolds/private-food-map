import type { RestaurantSummary, Visit } from '../types/domain'
import type { AnalysisTasteProfileSnapshot } from '../types/analysisShare'
import { rankTasteTags } from './tasteProfileCore'
import { summarizeVisitSpend } from './visitSpend'

export const NON_CUISINE_TAG = /约会|聚餐|朋友|家人|同事|庆祝|商务|会再去|打卡|环境|服务|性价比|商场|中心|广场|银泰|来福士|附近|安静|热闹|舒适|拥挤|宽敞|精致|氛围|景观|偏贵|合理|划算|超值|江景|湖景|露台|包厢|早餐|早午餐|午餐|晚餐|夜宵|下午茶/

const PRICE_RANGES = [
  { label: '¥0 – ¥50', minimum: 0, maximum: 50 },
  { label: '¥50 – ¥100', minimum: 50, maximum: 100 },
  { label: '¥100 – ¥200', minimum: 100, maximum: 200 },
  { label: '¥200 – ¥300', minimum: 200, maximum: 300 },
  { label: '¥300+', minimum: 300, maximum: Number.POSITIVE_INFINITY },
]

export function rankTasteCuisines(restaurants: RestaurantSummary[], visits: Visit[]) {
  const restaurantByID = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  return rankTasteTags(visits.flatMap((visit) => {
    const restaurant = restaurantByID.get(visit.restaurantId)
    if (!restaurant || visit.deletedAt) return []
    const tags = restaurant.tags.filter((tag) => tag.trim() && !NON_CUISINE_TAG.test(tag))
    return tags.length ? [{ restaurantKey: restaurant.id, tags, ratingOutOfTen: visit.rating == null ? 5 : visit.rating * 2 }] : []
  }))
}

export function buildTasteProfileSnapshot(restaurants: RestaurantSummary[], visits: Visit[], rankedCuisines = rankTasteCuisines(restaurants, visits)): AnalysisTasteProfileSnapshot {
  const activeVisits = visits.filter((visit) => !visit.deletedAt)
  const restaurantByID = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const cuisineCounts = rankedCuisines.slice(0, 7).map((item) => ({ label: item.tag, count: item.visits }))
  const cuisines = normalizedSlices(cuisineCounts).map((item) => ({ ...item, symbol: cuisineSymbol(item.label) }))

  const preferenceCounts = count(activeVisits.flatMap((visit) => {
    const values = visit.dishes.flatMap((dish) => tasteDimensions(dish.taste))
    return [...new Set(values)]
  })).slice(0, 6)
  const preferences = preferenceCounts.length
    ? preferenceCounts.map(([label, value]) => ({
        label,
        value: Math.max(1, Math.min(100, Math.round(value / Math.max(1, activeVisits.length) * 100))),
        symbol: preferenceSymbol(label),
      }))
    : cuisines.slice(0, 6)

  const spendCategoryCounts = count(activeVisits.map((visit) => restaurantCategory(restaurantByID.get(visit.restaurantId))))
  const spendCategories = normalizedSlices(spendCategoryCounts.map(([label, value]) => ({ label, count: value })))
    .map((item) => ({ ...item, symbol: categorySymbol(item.label) }))
  const priceCounts = new Map<string, number>(PRICE_RANGES.map((range) => [range.label, 0]))
  for (const visit of activeVisits) {
    const value = visit.pricePerPerson ?? visit.myActualSpend ?? (visit.totalPrice != null && visit.partySize ? visit.totalPrice / visit.partySize : null)
    if (value == null || value < 0) continue
    const range = PRICE_RANGES.find((item) => value >= item.minimum && value < item.maximum)
    if (range) priceCounts.set(range.label, (priceCounts.get(range.label) ?? 0) + 1)
  }
  const pricedCount = [...priceCounts.values()].reduce((sum, value) => sum + value, 0)
  const priceRanges = [...priceCounts].map(([label, value]) => ({
    label,
    value: pricedCount ? Math.round(value / pricedCount * 100) : 0,
    symbol: '•',
  }))

  const diningTimeCounts = [0, 0, 0, 0]
  activeVisits.forEach((visit) => {
    const hour = new Date(visit.visitedAt).getHours()
    if (!Number.isNaN(hour)) diningTimeCounts[hour < 10 ? 0 : hour < 15 ? 1 : hour < 21 ? 2 : 3] += 1
  })
  const diningTimeTotal = diningTimeCounts.reduce((sum, value) => sum + value, 0) || 1
  const diningTimes = ['早餐', '午餐', '晚餐', '夜宵'].map((label, index) => ({
    label,
    value: Math.round(diningTimeCounts[index] / diningTimeTotal * 100),
    symbol: label === '早餐' ? '☀️' : label === '午餐' ? '🌤️' : label === '晚餐' ? '🌇' : '🌙',
  }))

  const cities = count(restaurants.map((restaurant) => restaurant.city).filter(Boolean)).slice(0, 5)
    .map(([label, value]) => ({ label, value, symbol: '📍' }))
  const companionCounts = count(activeVisits.map(companionCategory))
  const companions = normalizedSlices(companionCounts.slice(0, 4).map(([label, value]) => ({ label, count: value })))
    .map((item) => ({ ...item, symbol: companionSymbol(item.label) }))
  const dates = activeVisits.map((visit) => new Date(visit.visitedAt)).filter((value) => !Number.isNaN(value.getTime())).sort((a, b) => a.getTime() - b.getTime())
  const ratings = activeVisits.flatMap((visit) => visit.rating == null ? [] : [visit.rating * 2])
  const averageScoreOutOfTen = ratings.length ? ratings.reduce((sum, value) => sum + value, 0) / ratings.length : null
  const dishCount = new Set(activeVisits.flatMap((visit) => visit.dishes.map((dish) => dish.id || dish.name.trim()).filter(Boolean))).size

  return {
    periodLabel: dates.length ? `${formatPeriodDate(dates[0])} – ${formatPeriodDate(dates[dates.length - 1])}` : '尚无记录',
    restaurantCount: restaurants.length,
    dishCount,
    visitCount: activeVisits.length,
    spend: summarizeVisitSpend(activeVisits).total,
    cityCount: new Set(restaurants.map((restaurant) => restaurant.city).filter(Boolean)).size,
    averageScoreOutOfTen: averageScoreOutOfTen == null ? null : Math.round(averageScoreOutOfTen * 10) / 10,
    cuisines,
    preferences,
    spendCategories,
    priceRanges,
    cities,
    companions,
    diningTimes,
  }
}

function count(values: Array<string | null | undefined>) {
  const result = new Map<string, number>()
  values.forEach((value) => { if (value) result.set(value, (result.get(value) ?? 0) + 1) })
  return [...result].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'zh-CN'))
}

function normalizedSlices(items: Array<{ label: string; count: number }>) {
  const positive = items.filter((item) => item.count > 0)
  const total = positive.reduce((sum, item) => sum + item.count, 0)
  if (!total) return []
  const values = positive.map((item) => ({ ...item, raw: item.count / total * 100, value: Math.floor(item.count / total * 100) }))
  let remainder = 100 - values.reduce((sum, item) => sum + item.value, 0)
  const order = [...values].sort((a, b) => (b.raw - b.value) - (a.raw - a.value) || b.count - a.count)
  for (let index = 0; remainder > 0; index += 1, remainder -= 1) order[index % order.length].value += 1
  return values.map(({ label, value }) => ({ label, value }))
}

function restaurantCategory(restaurant: RestaurantSummary | undefined) {
  const value = restaurant?.tags.join(' ') ?? ''
  if (/咖啡|甜|蛋糕|烘焙|面包|茶/.test(value)) return '咖啡 & 甜点'
  if (/小吃|快餐|汉堡|炸|串|面点/.test(value)) return '小吃 & 快餐'
  if (/饮品|奶茶|酒吧|果汁/.test(value)) return '饮品'
  if (/早餐|早午餐/.test(value)) return '早餐'
  return '正餐'
}

function companionCategory(visit: Visit) {
  if (visit.diningOccasions.includes('solo')) return '一个人'
  if (visit.diningOccasions.includes('friends')) return '朋友'
  if (visit.diningOccasions.includes('date')) return '伴侣'
  if (visit.diningOccasions.includes('family')) return '家人'
  if (visit.companions.length) return '有饭搭子'
  return '未记录'
}

function cuisineSymbol(label: string) {
  if (/意|披萨/.test(label)) return '🍕'
  if (/日|寿司|刺身/.test(label)) return '🍣'
  if (/韩/.test(label)) return '🍲'
  if (/西|汉堡|牛排/.test(label)) return '🍔'
  if (/咖啡|甜|蛋糕/.test(label)) return '🍰'
  if (/东南亚|泰|越/.test(label)) return '🥗'
  if (/中|川|湘|粤|江浙/.test(label)) return '🥘'
  return '🥣'
}

function preferenceSymbol(label: string) {
  if (/鲜|海鲜/.test(label)) return '🍅'
  if (/辣/.test(label)) return '🌶️'
  if (/酸/.test(label)) return '🍋'
  if (/甜/.test(label)) return '🧁'
  if (/淡|清/.test(label)) return '🌿'
  if (/咸|重口/.test(label)) return '🧂'
  return '🍴'
}

export function tasteDimensions(rawValue: string) {
  const value = rawValue.trim()
  if (!value) return []
  const dimensions = [
    [/咸|重口|酱香|炭香/, '偏咸'],
    [/鲜|海味/, '偏鲜'],
    [/辣|麻/, '偏辣'],
    [/酸/, '偏酸'],
    [/甜/, '偏甜'],
    [/淡|清爽|清鲜/, '清淡'],
  ] as const
  const matched = dimensions.flatMap(([pattern, label]) => pattern.test(value) ? [label] : [])
  return matched.length ? matched : [value]
}

function categorySymbol(label: string) {
  if (label.includes('咖啡')) return '☕'
  if (label.includes('小吃')) return '🍟'
  if (label.includes('饮品')) return '🥤'
  if (label.includes('早餐')) return '🥐'
  return '🍲'
}

function companionSymbol(label: string) {
  if (label === '一个人') return '👩🏻'
  if (label === '朋友') return '👭'
  if (label === '伴侣') return '👩‍❤️‍👨'
  if (label === '家人') return '👨‍👩‍👧'
  if (label === '有饭搭子') return '🧑‍🤝‍🧑'
  return '◌'
}

function formatPeriodDate(date: Date) {
  return `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, '0')}.${String(date.getDate()).padStart(2, '0')}`
}
