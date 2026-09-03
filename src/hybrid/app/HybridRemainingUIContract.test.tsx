import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
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
import { ProfilePage } from '../../components/ProfilePage'
import { RestaurantRoulette } from '../../components/RestaurantRoulette'
import { MyMapBrowsePage } from '../../components/MyMapBrowsePage'
import { TasteMapActivityCardFrame, TasteMapActivityRatingBadge } from '../../components/TasteMapDiscoveryShared'
import {
  hybridMapReactControlSelector,
  isRenderedHybridMapReactControl,
} from '../../components/NativeMapSurface'
vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))

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
    forYou: [{ id: 'for-you', mode: 'for_you', restaurant: { ...fixture.restaurants[0], referencePrice: 229, image }, viewerState: 'visited', sourceUser: { id: 'source-user', name: '林夏', city: '杭州', avatarPhotoID: null, avatarPresetID: 'otter', isFollowing: true }, activityRating: 4.5, activityVisitedAt: '2026-08-24T12:00:00Z', interaction: { activityID: null, visitID: 'visit-source', authorID: 'source-user', restaurantID: fixture.restaurants[0].id }, likedByViewer: false, likeCount: 8, commentCount: 2, communityRating: { valueOutOfFive: 4.45, sampleCount: 10 }, reason: '与你常吃的菜系接近', similarityPercent: 96, sharedRestaurantCount: 3, uniqueVisitorCount: null, wantToGoCount: null, rank: 1 }],
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
  it('keeps the fixed Hybrid bottom navigation outside the Native MapKit hit surface', () => {
    expect(hybridMapReactControlSelector.split(',')).toContain('.tm-hybrid-bottom-nav')
    expect(isRenderedHybridMapReactControl({ getClientRects: () => [{ width: 384, height: 56 }] as unknown as DOMRectList })).toBe(true)
    expect(isRenderedHybridMapReactControl({ getClientRects: () => [] as unknown as DOMRectList })).toBe(false)
  })

  it('uses one shared semantic icon-and-text primary scope component for Browser and Capacitor', () => {
    const TestMapSurface = () => <div data-map-engine="test" />
    const html = renderToStaticMarkup(<MyMapBrowsePage MapSurface={TestMapSurface} active onAddRestaurant={() => undefined} onOpenRestaurant={() => undefined} platform={platform} profile={profile} />)
    expect(html).toContain('aria-label="地图范围"')
    expect(html.match(/class="tm-primary-tab-bar__icon"/g)).toHaveLength(3)
    expect(html).toContain('aria-label="去过，3 家餐厅"')
    expect(html).toContain('aria-label="想吃，2 家餐厅"')
    expect(html).toContain('aria-label="推荐，0 家餐厅"')
    expect(html.match(/class="tm-primary-tab-bar__count"/g)).toHaveLength(3)
    const scopeTabs = html.match(/<nav aria-label="地图范围"[\s\S]*?<\/nav>/)?.[0] ?? ''
    expect(scopeTabs).toContain('data-tastemap-semantic-icon="visited"')
    expect(scopeTabs).toContain('lucide-check')
    expect(scopeTabs).not.toContain('lucide-footprints')
    expect(scopeTabs).toContain('>3</span>')
    expect(scopeTabs).toContain('>2</span>')
    expect(scopeTabs).toContain('>0</span>')
    expect(html).toContain('role="tab"')
    expect(html).not.toContain('适合你')
  })

  it('keeps the canonical visited checkmark on owner and public Profile surfaces', () => {
    const owner = renderToStaticMarkup(<ProfilePage restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const ownerStatistics = owner.match(/profile-dashboard__counts--primary">([\s\S]*?)<\/div>/)?.[1] ?? ''
    expect(ownerStatistics).toContain('data-tastemap-semantic-icon="visited"')
    expect(ownerStatistics).toContain('lucide-check')
    expect(ownerStatistics).not.toContain('lucide-map-pin')
    expect(ownerStatistics).not.toContain('lucide-footprints')

    const publicProfile = renderToStaticMarkup(<ProfilePage editable={false} restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const visitedEntry = publicProfile.match(/class="public-profile-footprint"[\s\S]*?<\/button>/)?.[0] ?? ''
    expect(visitedEntry).toContain('data-tastemap-semantic-icon="visited"')
    expect(visitedEntry).toContain('lucide-check')
  })

  it('keeps Profile relationship counts with identity and balances the currency statistic', () => {
    const owner = renderToStaticMarkup(<ProfilePage followerCount={9} followingCount={14} restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const nameIndex = owner.indexOf(profile.user.nickname)
    const userIDIndex = owner.indexOf('profile-user-id--under-name')
    const socialIndex = owner.indexOf('class="profile-dashboard__social-counts"')
    const actionsIndex = owner.indexOf('class="profile-dashboard__identity-actions"')
    const primaryStatsIndex = owner.indexOf('profile-dashboard__counts profile-dashboard__counts--primary')
    expect(owner.match(/profile-dashboard__social-counts/g)).toHaveLength(1)
    expect([nameIndex, userIDIndex, socialIndex, actionsIndex, primaryStatsIndex].every((index) => index >= 0)).toBe(true)
    expect(nameIndex).toBeLessThan(userIDIndex)
    expect(userIDIndex).toBeLessThan(socialIndex)
    expect(socialIndex).toBeLessThan(actionsIndex)
    expect(actionsIndex).toBeLessThan(primaryStatsIndex)
    expect(owner).toContain('class="is-currency"')
    expect(owner).toContain('aria-label="关注 14"')
    expect(owner).toContain('aria-label="被关注 9"')
    expect(owner).not.toContain(profile.user.bio)
  })

  it('keeps account, privacy and data controls behind the single top-right Settings entry', () => {
    const owner = renderToStaticMarkup(<ProfilePage onOpenSettings={() => undefined} restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    expect(owner.match(/aria-label="设置"/g)).toHaveLength(1)
    expect(owner).not.toContain('profile-settings-links')
    expect(owner).not.toContain('>数据与设置<')
    expect(owner).not.toContain('>账号与隐私<')
  })

  it('keeps every owner memory action free of the stray top-right chevron', () => {
    const owner = renderToStaticMarkup(<ProfilePage restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const memoryActions = owner.match(/class="profile-memory-grid"([\s\S]*?)<\/div>/)?.[0] ?? ''
    expect(memoryActions).toContain('本月回顾')
    expect(memoryActions).toContain('年度回顾')
    expect(memoryActions).toContain('那年今日')
    expect(memoryActions).not.toContain('lucide-chevron-right')
  })

  it('keeps Discovery at one five-tab product level and labels missing Visit ratings honestly', () => {
    const html = renderToStaticMarkup(<HybridDiscoveryPage content={content} onOpenRestaurant={() => undefined} platform={platform} />)
    for (const label of ['关注', '为你推荐', '同味之选', '最新', '趋势']) expect(html).toContain(label)
    expect(html).toContain('8.9')
    expect(html).not.toContain('发现餐厅')
    expect(html).not.toContain('DISCOVER')
    expect(html).toContain('data-product-contract="discovery-page"')
    expect(html).toContain('data-product-contract="activity-card"')
    for (const region of ['restaurant-image', 'restaurant-name-address-context', 'visit-rating', 'like-comment-more-share', 'restaurant-actions']) {
      expect(html).toContain(`data-activity-region="${region}"`)
    }
  })

  it('places an Activity Visit rating beside the Restaurant and colors it from that user rating', () => {
    const html = renderToStaticMarkup(<TasteMapActivityCardFrame
      activityRating={<TasteMapActivityRatingBadge rating={3.5} />}
      restaurant={<span>测试餐厅</span>}
      restaurantActions={<button type="button">记录</button>}
      variant="activity"
    />)
    const restaurantIndex = html.indexOf('data-activity-region="restaurant-name-address-context"')
    const ratingIndex = html.indexOf('data-activity-region="visit-rating"')
    expect(html).toContain('class="tm-activity-card__restaurant-row"')
    expect(ratingIndex).toBeGreaterThan(restaurantIndex)
    expect(html).toContain('aria-label="本次到访评分 3.5"')
    expect(html).toContain('--tm-activity-rating-color:#6594d3')
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
    expect(html).not.toContain('查看推荐来源用户')
    expect(html).not.toContain('class="tm-activity-card__source"')
    expect(html).not.toContain('aria-label="关注用户"')
    expect(html).not.toContain('分享动态</button>')
    expect(html).toContain('aria-label="记录 ')
    expect(html).toContain('aria-label="已去过 ')
    expect(html).toContain('aria-label="加入转盘 ')
    expect(html).toContain('lucide-plus')
    expect(html).not.toContain('lucide-notebook-pen')
    const restaurantActions = html.match(/data-activity-region="restaurant-actions">([\s\S]*?)<\/div><\/footer>/)?.[1] ?? ''
    expect(restaurantActions).toContain('data-tastemap-semantic-icon="visited"')
    expect(restaurantActions).toContain('lucide-check')
    expect(restaurantActions).not.toContain('lucide-bookmark')
    expect(html).not.toContain('aria-label="食单 ')
    expect(html).not.toContain('title="加入食单"')
    expect(html).not.toContain('lucide-circle-plus')
    expect(html).not.toContain('lucide-list-plus')
    expect(html).not.toContain('lucide-bookmark-plus')
    const socialActions = html.match(/data-activity-region="like-comment-more-share">([\s\S]*?)<\/div><div class="tm-activity-card__restaurant-actions"/)?.[1] ?? ''
    expect(socialActions).toContain('lucide-send')
    expect(socialActions).not.toContain('lucide-share-2')
    expect(socialActions.match(/<button/g)).toHaveLength(3)
    expect(restaurantActions.match(/<button/g)).toHaveLength(3)
  })

  it('shows a concise similar-taste rating label without repeating the known user name', () => {
    const similarTasteContent = structuredClone(content) as TasteMapHybridContentSnapshotDTO
    similarTasteContent.discovery.forYou = [{ ...similarTasteContent.discovery.forYou[0], mode: 'similar_taste' }]
    const html = renderToStaticMarkup(
      <HybridDiscoveryPage content={similarTasteContent} onOpenRestaurant={() => undefined} platform={platform} />,
    )
    expect(html).toContain('<small>评分</small>')
    expect(html).not.toContain('的评分</small>')
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
    )).toContain('大家评分')
  })

  it('only exposes Like and Comment when the recommendation carries a concrete Visit identity', () => {
    const systemRecommendation = structuredClone(content) as TasteMapHybridContentSnapshotDTO
    systemRecommendation.discovery.forYou[0].interaction = null
    const html = renderToStaticMarkup(
      <HybridDiscoveryPage content={systemRecommendation} onOpenRestaurant={() => undefined} platform={platform} />,
    )
    expect(html).not.toContain('aria-label="点赞"')
    expect(html).not.toContain('aria-label="评论"')
    expect(html).toContain('aria-label="分享动态 ')
  })

  it('keeps the approved stacked Add Restaurant acquisition order without a second tab layer', () => {
    const html = renderToStaticMarkup(<HybridAddRestaurantPage onOpenRestaurant={() => undefined} platform={platform} />)
    const indexes = ['search', 'nearby', 'share', 'manual'].map((capability) => html.indexOf(`data-acquisition-capability="${capability}"`))
    expect(indexes.every((value) => value >= 0)).toBe(true)
    expect(indexes).toEqual([...indexes].sort((a, b) => a - b))
    expect(html).not.toContain('role="tablist"')
    expect(html).not.toContain('ADD RESTAURANT')
    expect(html.match(/data-acquisition-capability="manual"/g)).toHaveLength(1)
    expect(html).toContain('data-shared-acquisition-component="search-city"')
    expect(html).toContain('data-shared-acquisition-component="nearby-status"')
    expect(html).toContain('data-location-semantic="city-not-gps"')
    expect(html.match(/data-acquisition-input=/g)).toHaveLength(2)
    expect(html).toContain('aria-label="城市"')
    expect(html).toContain('data-search-action="compact-icon"')
    expect(html).not.toContain('<span>搜索</span>')
    expect(html).not.toContain('tm-hybrid-add-city')
  })

  it('renders compact ranked/public Lists and the approved max-10 Roulette contract', () => {
    const lists = renderToStaticMarkup(<TasteMapListsPage lists={content.lists} onOpenRestaurant={() => undefined} platform={platform} />)
    expect(lists).toContain('年度 TOP 10')
    expect(lists).toContain('公开')
    const roulette = renderToStaticMarkup(<RestaurantRoulette onClose={() => undefined} onSelectRestaurant={() => undefined} onSelectedRestaurantIdsChange={() => undefined} onTemporaryItemsChange={() => undefined} restaurants={profile.restaurants} selectedRestaurantIds={profile.restaurants.slice(0, 5).map((item) => item.id)} temporaryItems={[]} />)
    expect(roulette).toContain('最多选择 10 家')
    expect(roulette).toContain('管理候选餐厅')
    expect(roulette).toContain('搜索已有餐厅，或输入自定义餐厅名称')
    expect(roulette).toContain('placeholder="搜索我的餐厅"')
    expect(roulette).toContain('placeholder="添加自定义餐厅"')
    expect(roulette).toContain('aria-label="添加自定义餐厅到候选"')
    expect(roulette).toContain('data-roulette-candidate-tools="shared"')
    expect(roulette).toContain('data-roulette-custom-candidate="temporary-only"')
    expect(roulette).toContain('maxLength="40"')
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
