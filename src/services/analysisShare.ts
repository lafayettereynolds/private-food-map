import type { DiningCompanion, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import type { AnalysisRestaurantEvidence, AnalysisShareData, AnalysisShareType, AnalysisVisualRef } from '../types/analysisShare'
import type { OnThisDayReview, PeriodReview, ReviewMemory, ReviewPhoto } from './reviewService'
import type { buildProfileInsights } from './profileInsights'
import { buildCompanionDirectory, buildCompanionInsights } from './companionInsights'
import { buildRecommendationSourceInsights, selectWorstRecommendationSource } from './recommendationSourceInsights'
import { collectAnalysisVisuals, cuisineFallback, restaurantVisual } from './foodVisualResolver'

type TasteProfile = ReturnType<typeof buildProfileInsights>['tasteProfile']

function reportId(type: AnalysisShareType, userId: string, period: string) {
  return `${type}:${userId}:${period}`
}

function photoVisual(photo: ReviewPhoto, label: string, restaurantId?: string): AnalysisVisualRef {
  return { source: photo.source, photoId: photo.photoId, origin: photo.origin === 'placeholder' ? 'fallback' : photo.origin, label, restaurantId }
}

function memoryEvidence(memory: ReviewMemory): AnalysisRestaurantEvidence {
  return {
    restaurantId: memory.restaurantId,
    name: memory.restaurantName,
    meta: [memory.city, memory.visitCount > 1 ? `${memory.visitCount} 次到访` : '', memory.note].filter(Boolean).join(' · '),
    score: memory.scoreOutOfTen === null ? undefined : memory.scoreOutOfTen.toFixed(1),
    image: photoVisual(memory.photo, memory.restaurantName, memory.restaurantId),
  }
}

function base(type: AnalysisShareType, user: UserProfile, period: string): Pick<AnalysisShareData, 'reportId' | 'type' | 'userId' | 'logoSource' | 'privacy' | 'footer'> {
  return {
    reportId: reportId(type, user.id, period),
    type,
    userId: user.id,
    logoSource: '/icons/taste-map-icon-192.png',
    footer: 'Taste Map · 记录每一次真实的味觉记忆',
    privacy: { companionNameIncluded: false, spendIncluded: false, exactLocationIncluded: false },
  }
}

export function buildTasteProfileShareData(user: UserProfile, profile: TasteProfile, restaurants: RestaurantSummary[], visits: Visit[]): AnalysisShareData {
  const type: AnalysisShareType = 'TASTE_PROFILE'
  const heroes = collectAnalysisVisuals(restaurants, visits, type, `${profile.validVisitCount}`)
  const preferred = profile.preferredCuisines.slice(0, 4)
  return {
    ...base(type, user, `${profile.validVisitCount}`),
    title: '我的口味档案',
    eyebrow: 'MY TASTE PROFILE',
    subtitle: `基于 ${profile.validVisitCount} 次真实到访生成`,
    summary: profile.summary,
    metrics: [
      { label: '有效记录', value: `${profile.validVisitCount}` },
      { label: '平均评分', value: profile.ratingBehavior.average?.toFixed(1) || '—' },
      { label: '复购倾向', value: `${Math.round(profile.repeatVisit.share * 100)}%` },
      { label: '常见预算', value: profile.preferredPriceRange },
    ],
    insights: [
      preferred.length ? `偏爱 ${preferred.map((item) => item.label).join('、')}` : '口味偏好仍在形成',
      profile.highRatingTraits.length ? `加分体验：${profile.highRatingTraits.slice(0, 3).map((item) => item.label).join('、')}` : '继续记录体验维度后生成加分项',
      profile.pitfallTraits.length ? `更容易减分：${profile.pitfallTraits.slice(0, 3).map((item) => item.label).join('、')}` : '暂未发现稳定踩雷因素',
      `${Math.round(profile.diningMode.dineInShare * 100)}% 的记录来自到店用餐`,
    ],
    keywords: [...preferred.map((item) => item.label), ...profile.highRatingTraits.slice(0, 3).map((item) => item.label)].slice(0, 7),
    restaurants: profile.repeatVisit.preferences.slice(0, 4).map((item) => {
      const restaurant = restaurants.find((candidate) => candidate.name === item.label)
      return {
        restaurantId: restaurant?.id || item.label,
        name: item.label,
        meta: `${item.count} 次到访 · 平均 ${item.averageRating.toFixed(1)}`,
        score: item.averageRating.toFixed(1),
        image: restaurant ? restaurantVisual(restaurant) : cuisineFallback(item.label, item.label, item.label),
      }
    }),
    heroCandidates: heroes,
  }
}

export function buildCompanionShareData(user: UserProfile, companions: DiningCompanion[], restaurants: RestaurantSummary[], visits: Visit[], revealName = false): AnalysisShareData {
  const type: AnalysisShareType = 'COMPANION_ANALYSIS'
  const insights = buildCompanionDirectory(companions, visits, user.id).map((companion) => buildCompanionInsights(companion, restaurants, visits)).sort((a, b) => b.sharedVisitCount - a.sharedVisitCount)
  const lead = insights[0]
  const companionLabel = lead ? revealName ? lead.companion.displayName : '最常一起吃的人' : '共同记录仍在形成'
  const restaurantIds = new Set(insights.flatMap((item) => item.topRestaurants.map((restaurant) => restaurant.restaurantId)))
  const evidenceRestaurants = restaurants.filter((item) => restaurantIds.has(item.id)).slice(0, 4)
  return {
    ...base(type, user, `${visits.length}:${insights.length}`),
    privacy: { companionNameIncluded: revealName, spendIncluded: false, exactLocationIncluded: false },
    title: '最佳饭搭子',
    eyebrow: 'DINING COMPANION',
    subtitle: `基于 ${visits.length} 条真实到访中的共同记录`,
    summary: lead ? `你和${companionLabel}一起记录了 ${lead.sharedVisitCount} 次用餐，去过 ${lead.restaurantCount} 家餐厅。` : '记录饭搭子后，共同口味会逐渐形成。',
    metrics: [
      { label: '饭搭子', value: `${insights.length}` },
      { label: '共同到访', value: `${insights.reduce((sum, item) => sum + item.sharedVisitCount, 0)}` },
      { label: '共同餐厅', value: `${new Set(insights.flatMap((item) => item.topRestaurants.map((restaurant) => restaurant.restaurantId))).size}` },
      { label: '重复餐厅', value: `${insights.reduce((sum, item) => sum + item.repeatRestaurantCount, 0)}` },
    ],
    insights: insights.slice(0, 5).map((item) => `${revealName ? item.companion.displayName : '一位常见饭搭子'}：一起吃过 ${item.sharedVisitCount} 次，常吃 ${item.topCuisines[0]?.label || '不同菜系'}`),
    keywords: [...new Set(insights.flatMap((item) => item.topCuisines.map((cuisine) => cuisine.label)))].slice(0, 7),
    restaurants: evidenceRestaurants.map((restaurant) => ({ restaurantId: restaurant.id, name: restaurant.name, meta: `${restaurant.city} · 共同到访餐厅`, score: restaurant.scoreOutOfTen?.toFixed(1), image: restaurantVisual(restaurant) })),
    heroCandidates: collectAnalysisVisuals(evidenceRestaurants.length ? evidenceRestaurants : restaurants, visits, type, `${insights.length}:${visits.length}`),
  }
}

export function buildRecommendationSourceShareData(user: UserProfile, restaurants: RestaurantSummary[], visits: Visit[], sourceUsers: UserProfile[]): AnalysisShareData {
  const type: AnalysisShareType = 'RECOMMENDATION_SOURCE'
  const names = new Map(sourceUsers.map((item) => [item.id, item.nickname]))
  const insights = buildRecommendationSourceInsights(restaurants, visits, names)
  const accuracy = (item: typeof insights[number]) => item.ratedRestaurantCount ? Math.round(((item.highRatingHitRate || 0) * .75 + (item.repeatRestaurantRate || 0) * .25) * 100) : null
  const ranked = [...insights].sort((a, b) => (accuracy(b) ?? -1) - (accuracy(a) ?? -1))
  const lead = ranked[0]
  const mostFrequent = insights[0]
  const mostStable = [...insights].filter((item) => item.ratedRestaurantCount >= 10).sort((a, b) => (accuracy(b) ?? -1) - (accuracy(a) ?? -1) || b.ratedRestaurantCount - a.ratedRestaurantCount)[0] ?? lead
  const worst = selectWorstRecommendationSource(insights)
  const evidenceIds = [...new Set([
    ...(worst?.insight.restaurants.slice().sort((a, b) => (a.averageRating ?? 11) - (b.averageRating ?? 11)).slice(0, 2).map((item) => item.restaurantId) ?? []),
    ...ranked.flatMap((item) => item.restaurants.map((restaurant) => restaurant.restaurantId)),
  ])].slice(0, 4)
  const restaurantById = new Map(restaurants.map((restaurant) => [restaurant.id, restaurant]))
  const evidence = evidenceIds.flatMap((id) => restaurantById.get(id) ? [restaurantById.get(id)!] : [])
  const metrics = [
    { label: '最懂我', value: lead?.label ?? '继续记录' },
    { label: '最容易种草', value: mostFrequent?.label ?? '继续记录' },
    { label: '最稳定', value: mostStable?.label ?? '继续记录' },
    ...(worst ? [{ label: '最坑', value: worst.insight.label }] : []),
  ]
  return {
    ...base(type, user, `${visits.length}:${insights.length}`),
    title: '谁最会种草',
    eyebrow: 'RECOMMENDATION SOURCES',
    subtitle: '推荐的价值，由真实到访结果验证',
    summary: lead ? `目前最懂你的来源是「${lead.label}」${worst ? `；「${worst.insight.label}」过去对你的实际结果相对较差。` : '。'}` : '填写推荐来源并实际到访后，这里会判断谁更懂你的口味。',
    metrics,
    insights: [
      ...ranked.slice(0, 4).map((item) => `${item.label}：用 ${item.ratedRestaurantCount} 家独立评分餐厅验证${accuracy(item) === null ? '' : `，推荐准确度 ${accuracy(item)}%`}`),
      ...(worst ? [`最坑「${worst.insight.label}」：${worst.insight.ratedRestaurantCount} 家独立评分餐厅，平均 ${worst.insight.averagePostVisitRating?.toFixed(1) ?? '—'} 分，低分比例 ${Math.round((worst.insight.lowRatingRate ?? 0) * 100)}%`] : []),
    ].slice(0, 5),
    keywords: ranked.slice(0, 6).map((item) => item.label),
    restaurants: evidence.map((restaurant) => ({ restaurantId: restaurant.id, name: restaurant.name, meta: `${restaurant.city} · 已验证推荐`, score: restaurant.scoreOutOfTen?.toFixed(1), image: restaurantVisual(restaurant) })),
    heroCandidates: collectAnalysisVisuals(evidence.length ? evidence : restaurants, visits, type, `${insights.length}:${visits.length}`),
  }
}

export function buildPeriodReviewShareData(user: UserProfile, review: PeriodReview): AnalysisShareData {
  const type: AnalysisShareType = review.kind === 'month' ? 'MONTHLY_REVIEW' : 'ANNUAL_REVIEW'
  const period = review.kind === 'month' ? `${review.year}-${review.month}` : `${review.year}`
  const restaurants = review.memories.slice(0, 5).map(memoryEvidence)
  const heroCandidates = review.heroPhotos.map((photo, index) => photoVisual(photo, review.memories[index]?.restaurantName || '回味照片', review.memories[index]?.restaurantId))
  return {
    ...base(type, user, period),
    title: review.kind === 'month' ? `${review.month} 月回味` : `${review.year} 食味年鉴`,
    eyebrow: review.kind === 'month' ? 'MONTHLY REVIEW' : 'ANNUAL REVIEW',
    subtitle: `${review.visitCount} 次用餐 · ${review.restaurantCount} 家餐厅`,
    summary: review.summary,
    periodLabel: period,
    metrics: [
      { label: '用餐', value: `${review.visitCount}` },
      { label: '餐厅', value: `${review.restaurantCount}` },
      { label: '新餐厅', value: `${review.newRestaurantCount}` },
      { label: '城市', value: `${review.cityCount}` },
    ],
    insights: [...review.highlights, ...review.diningPatterns, ...review.tasteChanges, ...review.milestones].filter(Boolean).slice(0, 7),
    keywords: [...review.mapFootprint.map((item) => item.city), ...review.recommendationSources.slice(0, 3).map((item) => item.label)].filter(Boolean).slice(0, 7),
    restaurants,
    heroCandidates: heroCandidates.length ? heroCandidates : restaurants.map((item) => item.image),
  }
}

export function buildOnThisDayShareData(user: UserProfile, review: OnThisDayReview): AnalysisShareData {
  const type: AnalysisShareType = 'ON_THIS_DAY'
  const restaurants = review.memories.slice(0, 5).map(memoryEvidence)
  return {
    ...base(type, user, `${review.month}-${review.day}`),
    title: '那年今日',
    eyebrow: 'ON THIS DAY',
    subtitle: `${review.month} 月 ${review.day} 日的味觉记忆`,
    summary: review.memories.length ? `这一天，你留下过 ${review.memories.length} 段真实到访记忆。` : '今天还没有往年到访记录。',
    periodLabel: `${review.month}.${review.day}`,
    metrics: [
      { label: '往年记忆', value: `${review.memories.length}` },
      { label: '餐厅', value: `${new Set(review.memories.map((item) => item.restaurantId)).size}` },
      { label: '城市', value: `${new Set(review.memories.map((item) => item.city).filter(Boolean)).size}` },
      { label: '最久以前', value: review.memories.length ? `${Math.max(...review.memories.map((item) => item.yearsAgo))} 年` : '—' },
    ],
    insights: review.memories.filter((item) => item.note).map((item) => `${item.restaurantName}：${item.note}`).slice(0, 6),
    keywords: [...new Set(review.memories.map((item) => item.city).filter(Boolean))].slice(0, 7),
    restaurants,
    heroCandidates: restaurants.map((item) => item.image),
  }
}

export function filterAnalysisSharePrivacy(data: AnalysisShareData, options?: { includeCompanionName?: boolean; includeSpend?: boolean }) {
  const clean = (value: string) => value
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '已隐藏邮箱')
    .replace(/\b(?:ID|id)\s*[:：-]?\s*[A-Za-z0-9_-]{4,}\b/g, '已隐藏账号')
    .replace(/¥\s?[\d,.]+/g, options?.includeSpend ? '$&' : '已隐藏消费')
  return {
    ...data,
    title: clean(data.title),
    subtitle: clean(data.subtitle),
    summary: clean(data.summary),
    insights: data.insights.map(clean),
    restaurants: data.restaurants.map((item) => ({ ...item, meta: clean(item.meta.replace(/(?:路|街|巷|号|弄)\s*\d+[\w\u4e00-\u9fff-]*/g, '附近')) })),
    privacy: {
      companionNameIncluded: Boolean(options?.includeCompanionName && data.privacy.companionNameIncluded),
      spendIncluded: Boolean(options?.includeSpend),
      exactLocationIncluded: false as const,
    },
  }
}
