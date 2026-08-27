import { describe, expect, it } from 'vitest'
import type { AnalysisShareData } from '../types/analysisShare'
import type { DiningCompanion, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { buildCompanionShareData, buildRecommendationSourceShareData, filterAnalysisSharePrivacy } from './analysisShare'
import { analysisPosterFilename, prepareAnalysisPoster, renderAnalysisPosterSvg } from './analysisPosterRenderer'
import { collectAnalysisVisuals, cuisineFallback, restaurantVisual } from './foodVisualResolver'

const visual = (label: string, restaurantId = label) => ({
  source: `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg"><text>${label}</text></svg>`)}`,
  photoId: null,
  origin: 'restaurant' as const,
  label,
  restaurantId,
})

function restaurant(id: string, city = '杭州'): RestaurantSummary {
  return {
    id, userId: 'owner', amapPoiId: id, name: `餐厅 ${id}`, address: `${city}测试路 18 号`, city, latitude: 30, longitude: 120,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
    valueRating: null, tags: ['日料'], longTermNote: '', pricePerPerson: null, phone: null, openingHours: null, markerType: 'image',
    markerImageData: visual(`cover-${id}`).source, markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍴', createdAt: '', updatedAt: '',
    deletedAt: null, visitCount: 1, averageRating: 4, scoreOutOfTen: 8, latestVisitDate: null, latestVisit: null, visits: [],
    averagePricePerPerson: null, averageQueueMinutes: null,
  }
}

function visit(id: string, restaurantId: string, photos: string[] = []): Visit {
  return {
    id, userId: 'owner', restaurantId, visitedAt: '2026-08-20T12:00:00.000Z', rating: 4, visibility: 'private', diningMode: 'dine_in',
    totalPrice: null, myActualSpend: null, paymentMode: null, pricePerPerson: null, partySize: 2, queueDuration: null, diningOccasions: [],
    diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [],
    environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '',
    recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [],
    dishes: [], note: '', photos, photoIds: photos.map(() => null), createdAt: '', updatedAt: '', deletedAt: null,
  }
}

function user(): UserProfile {
  return {
    id: 'owner', nickname: 'Taste Map 用户', email: 'owner@example.com', bio: '', city: '杭州', avatarImageData: null, avatarPhotoId: null,
    avatarPresetId: 'polar-bear', membershipTier: 'member', mapSharingEnabled: false, mapVisibility: 'private', authProvider: 'local', authSubject: null,
    createdAt: '', updatedAt: '', deletedAt: null,
  }
}

function recommendationVisit(index: number, sourceId: string, sourceName: string, rating: Visit['rating'] = 2.5): Visit {
  return {
    ...visit(`source-visit-${index}`, `source-restaurant-${index}`),
    rating,
    recommendationSourceType: 'friend',
    recommendationSourceUserId: sourceId,
    recommendationSourceText: sourceName,
  }
}

function shareData(): AnalysisShareData {
  const restaurants = ['a', 'b', 'c'].map((id) => ({ restaurantId: id, name: `餐厅 ${id}`, meta: '杭州 · 真实到访', score: '8.0', image: visual(`tile-${id}`, id) }))
  return {
    reportId: 'TASTE_PROFILE:owner:2026-08', type: 'TASTE_PROFILE', userId: 'owner', title: '我的口味档案', eyebrow: 'MY TASTE PROFILE',
    subtitle: '基于真实到访生成', summary: '偏爱安静、稳定而有记忆点的餐厅。', metrics: [{ label: '到访', value: '18' }],
    insights: ['日料是最稳定的高分菜系', '安静环境更容易获得高分'], keywords: ['日料', '安静'], restaurants,
    heroCandidates: [visual('hero-a', 'a'), visual('hero-b', 'b')], footer: 'Taste Map · 记录真实味觉记忆',
    logoSource: '/icons/taste-map-icon-192.png', privacy: { companionNameIncluded: false, spendIncluded: false, exactLocationIncluded: false },
  }
}

describe('analysis share system', () => {
  it('prioritizes visit photos over restaurant covers', () => {
    const value = collectAnalysisVisuals([restaurant('r1')], [visit('v1', 'r1', [visual('visit').source as string])], 'MONTHLY_REVIEW', '2026-08')
    expect(value[0].origin).toBe('visit')
  })

  it('uses a stable restaurant cover before cuisine fallback', () => {
    const value = collectAnalysisVisuals([restaurant('r1')], [], 'ANNUAL_REVIEW', '2026')
    expect(value[0]).toMatchObject({ origin: 'restaurant', restaurantId: 'r1' })
    expect(value[value.length - 1]?.origin).toBe('fallback')
  })

  it('keeps the same report visual order stable', () => {
    const restaurants = ['a', 'b', 'c'].map((id) => restaurant(id))
    expect(collectAnalysisVisuals(restaurants, [], 'TASTE_PROFILE', 'same').map((item) => item.source))
      .toEqual(collectAnalysisVisuals(restaurants, [], 'TASTE_PROFILE', 'same').map((item) => item.source))
  })

  it('allows a different period to rotate within the real candidate pool', () => {
    const restaurants = ['a', 'b', 'c', 'd'].map((id) => restaurant(id))
    const firstSources = new Set(Array.from({ length: 12 }, (_, index) => collectAnalysisVisuals(restaurants, [], 'MONTHLY_REVIEW', `2026-${index + 1}`)[0]?.source))
    expect(firstSources.size).toBeGreaterThan(1)
  })

  it('creates cuisine-related deterministic fallbacks rather than unrelated random food', () => {
    expect(cuisineFallback('小馆', '日料', 'seed')).toEqual(cuisineFallback('小馆', '日料', 'seed'))
    expect(cuisineFallback('小馆', '日料', 'seed').source).toContain(encodeURIComponent('日料'))
  })

  it('keeps companion analysis phrasing scoped to current-user records', () => {
    const companion: DiningCompanion = { id: 'c1', ownerUserId: 'owner', displayName: '小王', linkedUserId: null, createdAt: '', updatedAt: '', deletedAt: null }
    const sharedVisit = { ...visit('v1', 'r1'), companions: ['小王'], companionIds: ['c1'] }
    const data = buildCompanionShareData(user(), [companion], [restaurant('r1')], [sharedVisit])
    expect(`${data.summary} ${data.insights.join(' ')}`).not.toContain('我们都喜欢')
    expect(data.summary).toContain('一起记录')
  })

  it('keeps the real person name in recommendation-source sharing and includes a qualified worst source', () => {
    const sourceUser = { ...user(), id: 'friend-1', nickname: '小王' }
    const restaurants = Array.from({ length: 6 }, (_, index) => restaurant(`source-restaurant-${index}`))
    const visits = restaurants.map((_, index) => recommendationVisit(index, sourceUser.id, '旧名字'))
    const data = buildRecommendationSourceShareData(user(), restaurants, visits, [sourceUser])

    expect(data.metrics).toContainEqual({ label: '最坑', value: '小王' })
    expect(`${data.summary} ${data.insights.join(' ')}`).toContain('小王')
    expect(`${data.summary} ${data.insights.join(' ')}`).not.toContain('旧名字')
  })

  it('omits the worst-source conclusion when fewer than six independent restaurants are rated', () => {
    const sourceUser = { ...user(), id: 'friend-2', nickname: '小李' }
    const restaurants = Array.from({ length: 5 }, (_, index) => restaurant(`source-restaurant-${index}`))
    const visits = restaurants.map((_, index) => recommendationVisit(index, sourceUser.id, sourceUser.nickname, 1))
    const data = buildRecommendationSourceShareData(user(), restaurants, visits, [sourceUser])

    expect(data.metrics.some((metric) => metric.label === '最坑')).toBe(false)
    expect(data.summary).not.toContain('最坑')
  })

  it('keeps each representative restaurant image matched to its restaurant id', () => {
    const data = shareData()
    expect(data.restaurants.every((item) => item.restaurantId === item.image.restaurantId)).toBe(true)
  })

  it('strips private email, account id, spend and exact street number from export data', () => {
    const data = shareData()
    data.summary = 'owner@example.com ID: private_123 花费 ¥388'
    data.restaurants[0].meta = '杭州市文三路 18 号'
    const safe = filterAnalysisSharePrivacy(data)
    expect(`${safe.summary} ${safe.restaurants[0].meta}`).not.toMatch(/owner@example|private_123|¥388|18 号/)
  })

  it('renders a clean 1080 by 1440 poster rather than a page screenshot', () => {
    const data = shareData()
    const svg = renderAnalysisPosterSvg({ data, hero: data.heroCandidates[0].source, logo: null, restaurantImages: data.restaurants.map((item) => item.image.source), heroIndex: 0 })
    expect(svg).toContain('width="1080" height="1440"')
    expect(svg).not.toMatch(/button|scrollbar|overflow/)
  })

  it('uses the official Taste Map application icon', () => {
    expect(shareData().logoSource).toBe('/icons/taste-map-icon-192.png')
  })

  it('generates a stable png filename for system sharing', () => {
    expect(analysisPosterFilename(shareData())).toBe('taste-map-taste-profile-2026-08.png')
  })

  it('avoids prohibited retro and dashboard visual language', () => {
    const svg = renderAnalysisPosterSvg({ data: shareData(), hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(svg).not.toMatch(/旧纸|木纹|胶带|飞书|dashboard|SaaS/i)
  })

  it('cycles only through the report real hero candidates', async () => {
    const data = shareData()
    const first = await prepareAnalysisPoster(data, 0)
    const third = await prepareAnalysisPoster(data, 2)
    expect(first.hero).toBe(data.heroCandidates[0].source)
    expect(third.hero).toBe(data.heroCandidates[0].source)
  })

  it('resolves representative restaurant pictures in the same display order', async () => {
    const data = shareData()
    const prepared = await prepareAnalysisPoster(data)
    expect(prepared.restaurantImages).toEqual(data.restaurants.map((item) => item.image.source))
  })

  it('keeps evidence builders tied to a real restaurant cover', () => {
    expect(restaurantVisual(restaurant('r9'))).toMatchObject({ restaurantId: 'r9', label: '餐厅 r9', origin: 'restaurant' })
  })
})
