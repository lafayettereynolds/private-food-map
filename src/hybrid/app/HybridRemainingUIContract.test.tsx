import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import fixture from '../../../hybrid/fixtures/profile-restaurant-rich.json'
import type {
  TasteMapHybridContentSnapshotDTO,
  TasteMapPlatform,
  TasteMapProfileDashboardViewModel,
} from '../../platform/TasteMapPlatform'
import type { RestaurantSummary, UserProfile, Visit } from '../../types/domain'
import { HybridAddRestaurantPage } from './HybridAddRestaurantPage'
import { TasteMapAnalyticsPage } from '../../components/TasteMapAnalyticsPage'
import { HybridDiscoveryPage } from './HybridDiscoveryPage'
import { TasteMapListsPage } from '../../components/TasteMapListsPage'
import { TasteMapPremiumPage, TasteMapSettingsPage } from '../../components/TasteMapPremiumSettingsPages'
import { RestaurantRoulette } from '../../components/RestaurantRoulette'

const profile: TasteMapProfileDashboardViewModel = {
  user: fixture.profile.user as unknown as UserProfile,
  restaurants: fixture.restaurants as unknown as RestaurantSummary[],
  visits: fixture.restaurants.flatMap((restaurant) => restaurant.visits) as unknown as Visit[],
  followerCount: fixture.profile.followerCount,
  followingCount: fixture.profile.followingCount,
  restaurantImages: Object.fromEntries(fixture.restaurants.map((restaurant) => [restaurant.id, restaurant.merchantImageUrl
    ? { kind: 'providerMerchant' as const, resourceURL: restaurant.merchantImageUrl, accessibilityLabel: restaurant.name }
    : { kind: 'foodDiningFallback' as const, stableSeed: restaurant.id, accessibilityLabel: restaurant.name },
  ])),
}

const image = profile.restaurantImages[fixture.restaurants[0].id]
const content: TasteMapHybridContentSnapshotDTO = {
  generatedAt: '2026-09-02T00:00:00Z',
  discovery: {
    forYou: [{ id: 'for-you', mode: 'for_you', restaurant: { ...fixture.restaurants[0], referencePrice: 229, image }, viewerState: 'visited', sourceUser: { id: 'source-user', name: '林夏', city: '杭州', avatarPhotoID: null, avatarPresetID: 'otter', isFollowing: true }, activityRating: 4.5, activityVisitedAt: '2026-08-24T12:00:00Z', communityRating: { valueOutOfFive: 4.45, sampleCount: 10 }, reason: '与你常吃的菜系接近', similarityPercent: 96, sharedRestaurantCount: 3, uniqueVisitorCount: null, wantToGoCount: null, rank: 1 }],
    similarTaste: [],
    trending: [],
  },
  community: { following: [], latest: [] },
  lists: [{ id: 'list-1', title: '年度 TOP 10', description: '真实记录', visibility: 'public', isRanked: true, isOwnedByViewer: true, ownerName: 'Lafayette', restaurantCount: 1, updatedAt: '2026-09-02T00:00:00Z', restaurants: [{ id: fixture.restaurants[0].id, name: fixture.restaurants[0].name, address: fixture.restaurants[0].address, city: fixture.restaurants[0].city, position: 0, note: '第一名', image }] }],
}

const platform = {
  kind: 'browser',
  premium: { status: async () => ({ state: 'premium', expiresAt: null }) },
  sync: { status: async () => ({ state: 'unavailable', pendingMutationCount: 0, lastSuccessfulSyncAt: null, errorCode: null }) },
  restaurant: { list: async () => [] },
  navigation: { openNative: async () => undefined, openHybrid: async () => ({ route: { surface: 'profile' }, owner: 'hybrid', canGoBack: false }) },
  location: { current: async () => { throw new Error('not requested during server render') } },
  share: { open: async () => undefined },
  haptics: { selection: async () => undefined },
  auth: { logout: async () => undefined },
} as unknown as TasteMapPlatform

describe('Hybrid remaining product UI contract', () => {
  it('keeps Discovery at one five-tab product level and preserves the Visit rating', () => {
    const html = renderToStaticMarkup(<HybridDiscoveryPage content={content} onOpenRestaurant={() => undefined} platform={platform} />)
    for (const label of ['关注', '为你推荐', '同味之选', '最新', '趋势']) expect(html).toContain(label)
    expect(html).toContain('4.5')
    expect(html).not.toContain('发现餐厅')
    expect(html).not.toContain('DISCOVER')
    expect(html).toContain('data-product-contract="discovery-page"')
    expect(html).toContain('data-product-contract="activity-card"')
    for (const region of ['restaurant-image', 'restaurant-name-address-context', 'visit-rating', 'like-comment-more-share', 'restaurant-actions']) {
      expect(html).toContain(`data-activity-region="${region}"`)
    }
  })

  it('locks the approved high-density feed-card topology and separates rating semantics', () => {
    const html = renderToStaticMarkup(<HybridDiscoveryPage content={content} onOpenRestaurant={() => undefined} platform={platform} />)
    const regions = [
      'restaurant-name-address-context',
      'visit-rating',
      'restaurant-image',
      'recommendation-reason',
      'like-comment-more-share',
      'restaurant-actions',
    ].map((region) => html.indexOf(`data-activity-region="${region}"`))
    expect(regions.every((index) => index >= 0)).toBe(true)
    expect(regions).toEqual([...regions].sort((left, right) => left - right))
    expect(html).toContain('为什么适合你')
    expect(html).toContain('大家评分')
    expect(html).toContain('8.9')
    expect(html).toContain('10 人')
    expect(html).toContain('查看推荐来源用户 林夏')
    expect(html).not.toContain('class="tm-activity-card__source"')
    expect(html).not.toContain('分享动态</button>')
  })

  it('treats Swift JSONEncoder omitted optionals as honest missing values instead of crashing', () => {
    const omittedOptionals = structuredClone(content) as TasteMapHybridContentSnapshotDTO
    const item = omittedOptionals.discovery.forYou[0] as unknown as Record<string, unknown>
    for (const key of ['activityRating', 'similarityPercent', 'sharedRestaurantCount', 'uniqueVisitorCount']) delete item[key]
    expect(() => renderToStaticMarkup(
      <HybridDiscoveryPage content={omittedOptionals} onOpenRestaurant={() => undefined} platform={platform} />,
    )).not.toThrow()
    expect(renderToStaticMarkup(
      <HybridDiscoveryPage content={omittedOptionals} onOpenRestaurant={() => undefined} platform={platform} />,
    )).toContain('未评分')
  })

  it('keeps the approved stacked Add Restaurant acquisition order without a second tab layer', () => {
    const html = renderToStaticMarkup(<HybridAddRestaurantPage onOpenRestaurant={() => undefined} platform={platform} />)
    const indexes = ['search', 'nearby', 'share', 'manual'].map((capability) => html.indexOf(`data-acquisition-capability="${capability}"`))
    expect(indexes.every((value) => value >= 0)).toBe(true)
    expect(indexes).toEqual([...indexes].sort((a, b) => a - b))
    expect(html).not.toContain('role="tablist"')
    expect(html).not.toContain('ADD RESTAURANT')
    expect(html.match(/data-acquisition-capability="manual"/g)).toHaveLength(1)
  })

  it('renders compact ranked/public Lists and the approved max-10 Roulette contract', () => {
    const lists = renderToStaticMarkup(<TasteMapListsPage lists={content.lists} onOpenRestaurant={() => undefined} platform={platform} />)
    expect(lists).toContain('年度 TOP 10')
    expect(lists).toContain('公开')
    const roulette = renderToStaticMarkup(<RestaurantRoulette onClose={() => undefined} onSelectRestaurant={() => undefined} onSelectedRestaurantIdsChange={() => undefined} onTemporaryItemsChange={() => undefined} restaurants={profile.restaurants} selectedRestaurantIds={profile.restaurants.slice(0, 5).map((item) => item.id)} temporaryItems={[]} />)
    expect(roulette).toContain('最多选择 10 家')
    expect(roulette).toContain('管理候选餐厅')
  })

  it('uses the five approved Analytics names and infographic anatomy', () => {
    const html = renderToStaticMarkup(<TasteMapAnalyticsPage onOpenRestaurant={() => undefined} platform={platform} profile={profile} />)
    for (const label of ['我的口味档案', '最佳饭搭子', '谁最会种草', '本月回顾', '年度回顾']) expect(html).toContain(label)
    expect(html).toContain('周边分析节点')
    expect(html).toContain('核心洞察')
    expect(html).toContain('代表餐厅')
  })

  it('keeps Premium factual and Settings actions in the native service boundary', () => {
    const premium = renderToStaticMarkup(<TasteMapPremiumPage platform={platform} />)
    expect(premium).toContain('商品价格始终由 StoreKit')
    expect(premium).not.toMatch(/¥\s*\d/)
    const settings = renderToStaticMarkup(<TasteMapSettingsPage platform={platform} profile={profile} />)
    expect(settings).toContain('Backup v1 不包含照片原图')
    expect(settings).toContain('高风险操作继续由正式 Native service 承载')
  })

})
