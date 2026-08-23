import { DINING_OCCASION_OPTIONS, type RestaurantSummary, type Visit } from '../types/domain'
import { rankTasteTags, type TastePreferenceSignal } from './tasteProfileCore'

const PRICE_BUCKETS = [
  { key: 'under50', label: '¥0～50', min: 0, max: 50 },
  { key: '50to100', label: '¥50～100', min: 50, max: 100 },
  { key: '100to200', label: '¥100～200', min: 100, max: 200 },
  { key: 'over200', label: '¥200+', min: 200, max: Number.POSITIVE_INFINITY },
]
const NON_CUISINE_TAG = /约会|聚餐|朋友|家人|同事|庆祝|商务|会再去|打卡|环境|服务|性价比|商场|中心|广场|银泰|来福士|附近|安静|热闹|舒适|拥挤|宽敞|精致|氛围|景观|偏贵|合理|划算|超值/

export function buildProfileInsights(restaurants: RestaurantSummary[], visits: Visit[], now = new Date()) {
  const activeVisits = visits.filter((visit) => !visit.deletedAt)
  const monthVisits = activeVisits.filter((visit) => {
    const date = new Date(visit.visitedAt)
    return date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth()
  })
  const yearVisits = activeVisits.filter((visit) => new Date(visit.visitedAt).getFullYear() === now.getFullYear())
  const onThisDay = activeVisits.filter((visit) => {
    const date = new Date(visit.visitedAt)
    return date.getFullYear() < now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
  })
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const tasteProfile = buildTasteProfile(restaurants, activeVisits)
  return {
    month: summary(monthVisits, restaurantById),
    year: summary(yearVisits, restaurantById),
    monthVisits,
    yearVisits,
    onThisDay,
    favoriteTags: tasteProfile.preferredCuisines.map((item) => item.label),
    priceRange: tasteProfile.preferredPriceRange,
    averageScore: tasteProfile.ratingBehavior.average,
    cityCount: new Set(restaurants.filter((restaurant) => restaurant.status === 'visited').map((restaurant) => restaurant.city).filter(Boolean)).size,
    tasteProfile,
  }
}

export function buildTasteProfile(restaurants: RestaurantSummary[], visits: Visit[]) {
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const ratedVisits = visits.filter((visit) => visit.rating !== null && restaurantById.has(visit.restaurantId))
  const signals: TastePreferenceSignal[] = ratedVisits.map((visit) => {
    const restaurant = restaurantById.get(visit.restaurantId)!
    return { restaurantKey: restaurant.amapPoiId || restaurant.id, tags: restaurant.tags.filter((tag) => !NON_CUISINE_TAG.test(tag)), ratingOutOfTen: Number(visit.rating) * 2 }
  })
  const preferredCuisines = rankTasteTags(signals).slice(0, 5).map((item) => ({ label: item.tag, score: item.score, visits: item.visits }))
  const prices = visits.flatMap((visit) => {
    const value = representativeSpend(visit)
    return value === null || value < 0 ? [] : [value]
  })
  const priceBuckets = PRICE_BUCKETS.map((bucket) => {
    const count = prices.filter((price) => price >= bucket.min && price < bucket.max).length
    return { key: bucket.key, label: bucket.label, count, share: prices.length ? count / prices.length : 0 }
  })
  const leadingPriceBucket = [...priceBuckets].sort((a, b) => b.count - a.count)[0]
  const preferredPriceRange = leadingPriceBucket?.count ? leadingPriceBucket.label : '尚无足够数据'
  const highRatedVisits = ratedVisits.filter((visit) => Number(visit.rating) >= 4)
  const traitCounts = new Map<string, number>()
  highRatedVisits.forEach((visit) => {
    const occasionLabels = visit.diningOccasions.map((occasion) => DINING_OCCASION_OPTIONS.find((item) => item.value === occasion)?.label).filter((item): item is string => Boolean(item))
    const traits = [...visit.valueTags, ...visit.environmentTags, ...visit.serviceTags, ...occasionLabels]
    if (visit.noiseLevel === 'quiet') traits.push('安静')
    if (visit.valueRating && visit.valueRating >= 4) traits.push('性价比高')
    traits.forEach((trait) => traitCounts.set(trait, (traitCounts.get(trait) ?? 0) + 1))
  })
  const minimumTraitSamples = highRatedVisits.length >= 10 ? 2 : 1
  const highRatingTraits = [...traitCounts].filter(([, count]) => count >= minimumTraitSamples).sort((a, b) => b[1] - a[1]).slice(0, 6).map(([label, count]) => ({ label, count }))
  const scenes = DINING_OCCASION_OPTIONS.map((option) => {
    const count = visits.filter((visit) => visit.diningOccasions.includes(option.value)).length
    return { label: option.label, count, share: visits.length ? count / visits.length : 0 }
  }).filter((item) => item.count).sort((a, b) => b.count - a.count)
  const dineInCount = visits.filter((visit) => visit.diningMode !== 'takeout').length
  const takeoutCount = visits.filter((visit) => visit.diningMode === 'takeout').length
  const restaurantCounts = new Map<string, number>()
  visits.forEach((visit) => restaurantCounts.set(visit.restaurantId, (restaurantCounts.get(visit.restaurantId) ?? 0) + 1))
  const repeatVisitCount = [...restaurantCounts.values()].reduce((sum, count) => sum + Math.max(0, count - 1), 0)
  const repeatShare = visits.length ? repeatVisitCount / visits.length : 0
  const ratings = ratedVisits.map((visit) => Number(visit.rating) * 2)
  const ratingBehavior = {
    average: ratings.length ? round1(ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length) : null,
    aboveEightShare: shareOf(ratings, (rating) => rating >= 8),
    aboveNineShare: shareOf(ratings, (rating) => rating >= 9),
    lowShare: shareOf(ratings, (rating) => rating < 6),
  }
  const confidence = visits.length < 5 ? 'insufficient' : visits.length < 20 ? 'forming' : 'stable'
  const summary = confidence === 'insufficient'
    ? '多记录一些餐厅后，我们会逐渐了解你的口味。'
    : tasteSummary(preferredCuisines[0]?.label, preferredPriceRange, highRatingTraits.map((item) => item.label), repeatShare)
  return {
    validVisitCount: visits.length,
    confidence,
    preferredCuisines,
    preferredPriceRange,
    priceBuckets,
    highRatingTraits,
    scenes,
    diningMode: { dineInShare: visits.length ? dineInCount / visits.length : 0, takeoutShare: visits.length ? takeoutCount / visits.length : 0 },
    repeatVisit: { share: repeatShare, tendency: repeatShare >= 0.35 ? '复购型' : repeatShare >= 0.18 ? '平衡型' : '尝鲜型' },
    ratingBehavior,
    summary,
  }
}

function representativeSpend(visit: Visit) {
  if (visit.paymentMode === 'separate' && visit.myActualSpend !== null) return visit.myActualSpend
  if (visit.pricePerPerson !== null) return visit.pricePerPerson
  if (visit.totalPrice !== null && visit.partySize > 0) return visit.totalPrice / visit.partySize
  return null
}

function tasteSummary(cuisine: string | undefined, priceRange: string, traits: string[], repeatShare: number) {
  const subject = cuisine ? `你更喜欢${cuisine}` : '你的高分记录'
  const traitText = traits.slice(0, 2).join('、')
  const repeatText = repeatShare >= 0.35 ? '，也愿意反复去稳定喜欢的店' : ''
  return `${subject}${priceRange !== '尚无足够数据' ? `，常去${priceRange}价位` : ''}${traitText ? `，偏好${traitText}` : ''}${repeatText}。`
}

function summary(visits: Visit[], restaurantById: Map<string, RestaurantSummary>) {
  return {
    visitCount: visits.length,
    restaurantCount: new Set(visits.map((visit) => visit.restaurantId)).size,
    cityCount: new Set(visits.map((visit) => restaurantById.get(visit.restaurantId)?.city).filter(Boolean)).size,
    spend: Math.round(visits.reduce((sum, visit) => sum + (visit.myActualSpend ?? visit.totalPrice ?? 0), 0)),
  }
}

function shareOf(values: number[], predicate: (value: number) => boolean) { return values.length ? values.filter(predicate).length / values.length : 0 }
function round1(value: number) { return Math.round(value * 10) / 10 }
