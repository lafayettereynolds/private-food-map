import { DINING_OCCASION_OPTIONS, RECOMMENDATION_SOURCE_OPTIONS, type RestaurantSummary, type Visibility, type Visit } from '../types/domain'
import { rankTasteTags, type TastePreferenceSignal } from './tasteProfileCore'
import { buildValidTasteVisits, moduleConfidence, type ModuleConfidence, type ValidTasteVisit } from './validTasteVisits'

const PRICE_BUCKETS = [
  { key: 'under50', label: '¥0～50', min: 0, max: 50 },
  { key: '50to100', label: '¥50～100', min: 50, max: 100 },
  { key: '100to200', label: '¥100～200', min: 100, max: 200 },
  { key: '200to300', label: '¥200～300', min: 200, max: 300 },
  { key: '300to500', label: '¥300～500', min: 300, max: 500 },
  { key: '500to800', label: '¥500～800', min: 500, max: 800 },
  { key: 'over800', label: '¥800+', min: 800, max: Number.POSITIVE_INFINITY },
]
const NON_CUISINE_TAG = /约会|聚餐|朋友|家人|同事|庆祝|商务|会再去|打卡|环境|服务|性价比|商场|中心|广场|银泰|来福士|附近|安静|热闹|舒适|拥挤|宽敞|精致|氛围|景观|偏贵|合理|划算|超值/

export function buildProfileInsights(restaurants: RestaurantSummary[], visits: Visit[], now = new Date()) {
  const activeVisits = visits.filter((visit) => !visit.deletedAt)
  const monthVisits = activeVisits.filter((visit) => sameMonth(new Date(visit.visitedAt), now))
  const yearVisits = activeVisits.filter((visit) => new Date(visit.visitedAt).getFullYear() === now.getFullYear())
  const onThisDay = activeVisits.filter((visit) => {
    const date = new Date(visit.visitedAt)
    return date.getFullYear() < now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
  })
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const tasteProfile = buildTasteProfile(restaurants, activeVisits, now)
  return {
    month: summarizePeriod(monthVisits, restaurantById), year: summarizePeriod(yearVisits, restaurantById), monthVisits, yearVisits, onThisDay,
    favoriteTags: tasteProfile.preferredCuisines.map((item) => item.label), priceRange: tasteProfile.preferredPriceRange,
    averageScore: tasteProfile.ratingBehavior.average,
    cityCount: new Set(restaurants.filter((restaurant) => restaurant.status === 'visited').map((restaurant) => restaurant.city).filter(Boolean)).size,
    tasteProfile,
  }
}

export function buildTasteProfile(restaurants: RestaurantSummary[], visits: Visit[], now = new Date()) {
  const valid = buildValidTasteVisits(restaurants, visits)
  const rated = valid.filter((item) => item.ratingOutOfTen !== null)
  const signals: TastePreferenceSignal[] = rated.map(({ restaurant, ratingOutOfTen }) => ({ restaurantKey: restaurant.amapPoiId || restaurant.id, tags: restaurant.tags.filter((tag) => !NON_CUISINE_TAG.test(tag)), ratingOutOfTen: ratingOutOfTen as number }))
  const preferredCuisines = rankTasteTags(signals).slice(0, 5).map((item) => ({ label: item.tag, score: item.score, visits: item.visits, averageRating: round1(item.averageRating) }))
  const priceSamples = valid.filter((item) => item.normalizedPerCapitaSpend !== null)
  const priceBuckets = PRICE_BUCKETS.map((bucket) => {
    const values = priceSamples.filter((item) => (item.normalizedPerCapitaSpend as number) >= bucket.min && (item.normalizedPerCapitaSpend as number) < bucket.max)
    const ratedValues = values.filter((item) => item.ratingOutOfTen !== null)
    return { key: bucket.key, label: bucket.label, count: values.length, share: share(values.length, priceSamples.length), highRatingShare: share(ratedValues.filter((item) => (item.ratingOutOfTen as number) >= 8).length, ratedValues.length) }
  })
  const leadingPriceBucket = [...priceBuckets].sort((a, b) => b.count - a.count)[0]
  const sweetPriceBucket = [...priceBuckets].filter((item) => item.count >= 2).sort((a, b) => b.highRatingShare - a.highRatingShare || b.count - a.count)[0]
  const highRated = rated.filter((item) => (item.ratingOutOfTen as number) >= 8)
  const lowRated = rated.filter((item) => (item.ratingOutOfTen as number) < 6)
  const highRatingTraits = traitRanking(highRated).slice(0, 6)
  const pitfallTraits = traitRanking(lowRated).slice(0, 6)
  const scenes = DINING_OCCASION_OPTIONS.map((option) => {
    const count = valid.filter(({ visit }) => visit.diningOccasions.includes(option.value)).length
    return { label: option.label, count, share: share(count, valid.length) }
  }).filter((item) => item.count).sort((a, b) => b.count - a.count)
  const restaurantCounts = countBy(valid, (item) => item.restaurant.id)
  const repeatVisits = [...restaurantCounts.values()].reduce((sum, count) => sum + Math.max(0, count - 1), 0)
  const repeatShare = share(repeatVisits, valid.length)
  const ratings = rated.map((item) => item.ratingOutOfTen as number)
  const overallRatingAverage = average(ratings)
  const hiddenPreferences = preferredCuisines.filter((item) => item.visits >= 3 && overallRatingAverage !== null && item.averageRating < overallRatingAverage - 0.6).slice(0, 3)
  const repeatPreferences = repeatPreference(valid).slice(0, 4)
  const companionImpact = compareGroups(rated.filter(({ visit }) => visit.companions.length > 0).map((item) => item.ratingOutOfTen as number), rated.filter(({ visit }) => visit.companions.length === 0).map((item) => item.ratingOutOfTen as number))
  const sourceQuality = RECOMMENDATION_SOURCE_OPTIONS.flatMap((option) => {
    const values = rated.filter(({ visit }) => visit.recommendationSourceType === option.value).map((item) => item.ratingOutOfTen as number)
    return values.length >= 2 ? [{ label: option.label, count: values.length, averageRating: round1(average(values) as number) }] : []
  }).sort((a, b) => b.averageRating - a.averageRating || b.count - a.count)
  const recentCutoff = new Date(now); recentCutoff.setDate(recentCutoff.getDate() - 90)
  const previousCutoff = new Date(recentCutoff); previousCutoff.setDate(previousCutoff.getDate() - 180)
  const recentTags = topTags(rated.filter((item) => new Date(item.visit.visitedAt) >= recentCutoff))
  const previousTags = topTags(rated.filter((item) => new Date(item.visit.visitedAt) >= previousCutoff && new Date(item.visit.visitedAt) < recentCutoff))
  const recentTasteChanges = recentTags.filter((tag) => !previousTags.includes(tag)).slice(0, 3)
  const stability = ratings.length < 4 || overallRatingAverage === null ? null : round1(Math.sqrt(average(ratings.map((rating) => (rating - overallRatingAverage) ** 2)) as number))
  const moduleConfidenceMap = {
    cuisines: moduleConfidence(rated.length), prices: moduleConfidence(priceSamples.length, 10, 3), traits: moduleConfidence(rated.length, 12, 5), repeat: moduleConfidence(valid.length, 15, 5),
    scenes: moduleConfidence(valid.length, 12, 4), companionImpact: moduleConfidence(Math.min(companionImpact.withCount, companionImpact.withoutCount), 6, 3),
    sources: moduleConfidence(sourceQuality.reduce((sum, item) => sum + item.count, 0), 8, 3), recentChange: moduleConfidence(recentTags.length + previousTags.length, 8, 3), ratings: moduleConfidence(ratings.length, 12, 4),
  } satisfies Record<string, ModuleConfidence>
  const preferredPriceRange = leadingPriceBucket?.count ? leadingPriceBucket.label : '尚无足够数据'
  const summary = moduleConfidenceMap.cuisines === 'insufficient' ? '多记录一些带评分的餐厅后，我们会逐渐了解你的口味。' : tasteSummary(preferredCuisines[0]?.label, preferredPriceRange, highRatingTraits.map((item) => item.label), repeatShare)
  return {
    validVisitCount: valid.length, ratedVisitCount: rated.length, moduleConfidence: moduleConfidenceMap, preferredCuisines, preferredPriceRange,
    sweetPriceRange: sweetPriceBucket?.count ? sweetPriceBucket.label : null, priceBuckets, highRatingTraits, pitfallTraits, hiddenPreferences, scenes,
    diningMode: { dineInShare: share(valid.filter(({ visit }) => visit.diningMode !== 'takeout').length, valid.length), takeoutShare: share(valid.filter(({ visit }) => visit.diningMode === 'takeout').length, valid.length) },
    repeatVisit: { share: repeatShare, tendency: repeatShare >= 0.35 ? '复购型' : repeatShare >= 0.18 ? '平衡型' : '尝鲜型', preferences: repeatPreferences },
    companionImpact, sourceQuality, recentTasteChanges,
    ratingBehavior: { average: overallRatingAverage === null ? null : round1(overallRatingAverage), aboveEightShare: shareOf(ratings, (rating) => rating >= 8), aboveNineShare: shareOf(ratings, (rating) => rating >= 9), lowShare: shareOf(ratings, (rating) => rating < 6), stability },
    summary, highConfidenceRules: moduleConfidenceMap.traits === 'established' ? highRatingTraits.slice(0, 3).map((item) => `在你的记录中，“${item.label}”更常伴随高分体验。`) : [],
  }
}

export interface PublicTasteSummary { visibility: Exclude<Visibility, 'private'>; topCuisines: string[]; representativePriceRange: string | null; highRatingTraits: string[]; summary: string; confidence: ModuleConfidence }
export function buildPublicTasteSummary(restaurants: RestaurantSummary[], visits: Visit[], visibility: Visibility): PublicTasteSummary | null {
  if (visibility === 'private') return null
  const allowed = visits.filter((visit) => !visit.deletedAt && (visit.visibility === 'public' || (visibility === 'friends' && visit.visibility === 'friends')))
  const profile = buildTasteProfile(restaurants, allowed)
  if (profile.moduleConfidence.cuisines === 'insufficient') return null
  return { visibility, topCuisines: profile.preferredCuisines.slice(0, 3).map((item) => item.label), representativePriceRange: profile.moduleConfidence.prices === 'insufficient' ? null : profile.preferredPriceRange, highRatingTraits: profile.moduleConfidence.traits === 'insufficient' ? [] : profile.highRatingTraits.slice(0, 3).map((item) => item.label), summary: profile.summary, confidence: profile.moduleConfidence.cuisines }
}

function traitRanking(items: ValidTasteVisit[]) { const counts = new Map<string, number>(); items.forEach(({ visit }) => visitTraits(visit).forEach((trait) => counts.set(trait, (counts.get(trait) ?? 0) + 1))); const minimum = items.length >= 10 ? 2 : 1; return [...counts].filter(([, count]) => count >= minimum).sort((a, b) => b[1] - a[1]).map(([label, count]) => ({ label, count })) }
function visitTraits(visit: Visit) { const occasions = visit.diningOccasions.map((value) => DINING_OCCASION_OPTIONS.find((item) => item.value === value)?.label).filter((item): item is string => Boolean(item)); return [...new Set([...visit.valueTags, ...visit.environmentTags, ...visit.serviceTags, ...occasions, ...(visit.noiseLevel === 'quiet' ? ['安静'] : [])])] }
function repeatPreference(valid: ValidTasteVisit[]) { const grouped = new Map<string, ValidTasteVisit[]>(); valid.forEach((item) => grouped.set(item.restaurant.id, [...(grouped.get(item.restaurant.id) ?? []), item])); return [...grouped.values()].filter((items) => items.length >= 2).map((items) => ({ label: items[0].restaurant.name, count: items.length, averageRating: round1(average(items.flatMap((item) => item.ratingOutOfTen == null ? [] : [item.ratingOutOfTen])) ?? 0) })).sort((a, b) => b.count - a.count || b.averageRating - a.averageRating) }
function compareGroups(withValues: number[], withoutValues: number[]) { const withAverage = average(withValues); const withoutAverage = average(withoutValues); return { withCount: withValues.length, withoutCount: withoutValues.length, withAverage: withAverage === null ? null : round1(withAverage), withoutAverage: withoutAverage === null ? null : round1(withoutAverage), difference: withAverage === null || withoutAverage === null ? null : round1(withAverage - withoutAverage) } }
function topTags(items: ValidTasteVisit[]) { return rankTasteTags(items.map((item) => ({ restaurantKey: item.restaurant.id, tags: item.restaurant.tags.filter((tag) => !NON_CUISINE_TAG.test(tag)), ratingOutOfTen: item.ratingOutOfTen as number }))).slice(0, 4).map((item) => item.tag) }
function countBy<T>(items: T[], key: (item: T) => string) { const map = new Map<string, number>(); items.forEach((item) => map.set(key(item), (map.get(key(item)) ?? 0) + 1)); return map }
function tasteSummary(cuisine: string | undefined, priceRange: string, traits: string[], repeatShare: number) { const subject = cuisine ? `你更喜欢${cuisine}` : '你的高分记录'; const traitText = traits.slice(0, 2).join('、'); return `${subject}${priceRange !== '尚无足够数据' ? `，常去${priceRange}价位` : ''}${traitText ? `，记录中常伴随${traitText}` : ''}${repeatShare >= .35 ? '，也更常回到稳定喜欢的店' : ''}。` }
function summarizePeriod(visits: Visit[], restaurantById: Map<string, RestaurantSummary>) { return { visitCount: visits.length, restaurantCount: new Set(visits.map((visit) => visit.restaurantId)).size, cityCount: new Set(visits.map((visit) => restaurantById.get(visit.restaurantId)?.city).filter(Boolean)).size, spend: Math.round(visits.reduce((sum, visit) => sum + (visit.myActualSpend ?? visit.totalPrice ?? 0), 0)) } }
function sameMonth(left: Date, right: Date) { return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() }
function average(values: number[]) { return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null }
function share(count: number, total: number) { return total ? count / total : 0 }
function shareOf(values: number[], predicate: (value: number) => boolean) { return share(values.filter(predicate).length, values.length) }
function round1(value: number) { return Math.round(value * 10) / 10 }
