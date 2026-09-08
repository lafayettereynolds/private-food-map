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
import { analysisDataShareText, TasteMapAnalyticsPage } from '../../components/TasteMapAnalyticsPage'
import { HybridDiscoveryPage } from './HybridDiscoveryPage'
import { HybridProfileListsPreview, TasteMapListsPage } from '../../components/TasteMapListsPage'
import { TasteMapPremiumPage, TasteMapSettingsPage } from '../../components/TasteMapPremiumSettingsPages'
import { ProfilePage } from '../../components/ProfilePage'
import { TasteFootprintPreview, TasteFootprints } from '../../components/TasteFootprints'
import { RestaurantRoulette } from '../../components/RestaurantRoulette'
import { RestaurantPreviewCard } from '../../components/RestaurantPreviewCard'
import { RestaurantAvatarEditorSheet } from '../../components/RestaurantAvatarEditorSheet'
import { MyMapBrowsePage, MyRestaurantList } from '../../components/MyMapBrowsePage'
import { TasteMapActivityCardFrame, TasteMapActivityRatingBadge } from '../../components/TasteMapDiscoveryShared'
import {
  hybridMapReactControlSelector,
  isRenderedHybridMapReactControl,
} from '../../components/NativeMapSurface'
import { scoreColor } from '../../types/domain'
import { ZoomablePosterPreview } from '../../components/ZoomablePosterPreview'
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
    forYou: [{ id: 'for-you', mode: 'for_you', restaurant: { ...fixture.restaurants[0], referencePrice: 229, image }, viewerState: 'visited', sourceUser: null, activityRating: null, activityVisitedAt: null, interaction: null, likedByViewer: false, likeCount: 0, commentCount: 0, communityRating: { valueOutOfFive: 4.45, sampleCount: 10 }, reasons: [{ code: 'TASTE_TAG_MATCH', text: '与你去过的「西湖小馆」相似 88%' }], reason: '与你去过的「西湖小馆」相似 88%', similarityPercent: null, sharedRestaurantCount: null, trendWindowDays: null, uniqueVisitorCount: null, wantToGoCount: null, rank: 1 }],
    similarTaste: [{ id: 'similar', mode: 'similar_taste', restaurant: { ...fixture.restaurants[0], referencePrice: 229, image }, viewerState: 'visited', sourceUser: { id: 'source-user', name: '林夏', city: '杭州', avatarPhotoID: null, avatarPresetID: 'otter', isFollowing: true }, activityRating: 4.5, activityVisitedAt: '2026-08-24T12:00:00Z', interaction: { activityID: 'similar-activity', visitID: 'visit-source', authorID: 'source-user', restaurantID: fixture.restaurants[0].id }, likedByViewer: false, likeCount: 8, commentCount: 2, communityRating: { valueOutOfFive: 4.45, sampleCount: 10 }, reasons: [{ code: 'SIMILAR_USERS', text: '基于 6 家共同评分餐厅，林夏在这家给过高分' }], reason: '基于 6 家共同评分餐厅，林夏在这家给过高分', similarityPercent: 82, sharedRestaurantCount: 6, trendWindowDays: null, uniqueVisitorCount: null, wantToGoCount: null, rank: 1 }],
    trending: [{ id: 'trending', mode: 'trending', restaurant: { ...fixture.restaurants[0], referencePrice: 229, image }, viewerState: 'none', sourceUser: null, activityRating: null, activityVisitedAt: null, interaction: null, likedByViewer: false, likeCount: 0, commentCount: 0, communityRating: { valueOutOfFive: 4.45, sampleCount: 10 }, reasons: [{ code: 'TRENDING_UNIQUE_USERS', text: '近 7 天有 18 位用户到访' }, { code: 'RECENT_WANT_TO_GO', text: '近期有 9 位用户加入想吃' }], reason: '近 7 天有 18 位用户到访', similarityPercent: null, sharedRestaurantCount: null, trendWindowDays: 7, uniqueVisitorCount: 18, wantToGoCount: 9, rank: 1 }],
  },
  community: { following: [], latest: [] },
  lists: [{ id: 'list-1', title: '年度 TOP 10', description: '真实记录', visibility: 'public', isRanked: true, isOwnedByViewer: true, ownerName: 'Lafayette', restaurantCount: 1, updatedAt: '2026-09-02T00:00:00Z', restaurants: [{ id: fixture.restaurants[0].id, name: fixture.restaurants[0].name, address: fixture.restaurants[0].address, city: fixture.restaurants[0].city, position: 0, note: '第一名', image }] }],
}

content.discovery.forYou[0].personalTastePercent = 88

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
  it('places one owner-only restaurant trash icon in the visit overview, never over the hero', () => {
    const restaurant = profile.restaurants[0]
    for (const status of ['visited', 'wantToGo'] as const) {
      const html = renderToStaticMarkup(<RestaurantPreviewCard onClose={() => undefined} onDelete={() => undefined} restaurant={{ ...restaurant, status }} remoteStatsEnabled={false} />)
      expect(html.match(/aria-label="删除餐厅"/g)).toHaveLength(1)
      expect(html).toMatch(/<header><strong>我的到访概览<\/strong><button aria-label="删除餐厅"/)
      expect(html.slice(0, html.indexOf('restaurant-visit-overview'))).not.toContain('restaurant-delete-button')
      expect(html).not.toContain('is-after-avatar')
    }
    const publicDetail = renderToStaticMarkup(<RestaurantPreviewCard onClose={() => undefined} onDelete={() => undefined} readOnly restaurant={restaurant} remoteStatsEnabled={false} />)
    expect(publicDetail).not.toContain('aria-label="删除餐厅"')
  })
  it('places the private Taste Footprint after insights and includes visits plus want-to-go saves', () => {
    const owner = renderToStaticMarkup(<ProfilePage restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const insightIndex = owner.indexOf('发现与洞察')
    const footprintIndex = owner.indexOf('味觉足迹')
    expect(insightIndex).toBeGreaterThanOrEqual(0)
    expect(footprintIndex).toBeGreaterThan(insightIndex)
    expect(owner).toContain('记录去过')
    expect(owner).toContain('加入想去')

    const timeline = renderToStaticMarkup(<TasteFootprints onSelectRestaurant={() => undefined} restaurants={profile.restaurants} visits={profile.visits} />)
    expect(timeline).toContain('记录去过')
    expect(timeline).toContain('加入想去')
    expect(timeline).toContain('分')
  })

  it('renders every Taste Footprint directly on the Profile page without a view-all entry', () => {
    const restaurant = { ...profile.restaurants[0], visits: [] }
    const sourceVisit = profile.visits[0]
    const visits = Array.from({ length: 300 }, (_, index) => ({
      ...sourceVisit,
      id: `direct-footprint-${index}`,
      restaurantId: restaurant.id,
      visitedAt: new Date(Date.UTC(2026, 8, 1) - index * 60_000).toISOString(),
    }))
    const timeline = renderToStaticMarkup(
      <TasteFootprintPreview onSelectRestaurant={() => undefined} restaurants={[restaurant]} visits={visits} />,
    )

    expect(timeline.match(/data-product-contract="activity-card"/g)).toHaveLength(300)
    expect(timeline).not.toContain('profile-taste-footprints-preview__row')
    expect(timeline).not.toContain('timeline__rail')
    expect(timeline).toContain('300 条')
    expect(timeline).not.toContain('查看全部')
  })

  it('uses a concise CTA under the Taste Profile entry instead of previewing cuisine data', () => {
    const owner = renderToStaticMarkup(<ProfilePage restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const tasteEntry = owner.match(/profile-quick-card profile-quick-card--taste[\s\S]*?<\/button>/)?.[0] ?? ''
    expect(tasteEntry).toContain('<strong>我的口味档案</strong><small>看看我爱吃什么</small>')
    expect(tasteEntry).not.toContain('<em>')
    expect(tasteEntry).not.toContain('西餐')
  })

  it('places one owner-only avatar editor at the upper-left of Restaurant imagery', () => {
    const restaurant = profile.restaurants[0]
    const detail = {
      restaurant,
      image,
      socialStats: null,
      viewerState: 'visited' as const,
      editableVisitIDs: restaurant.visits.map((visit) => visit.id),
      capabilities: {
        canEditRestaurant: true, canDeleteRestaurant: true, canRecordVisit: true,
        canAddToWantToGo: true, canAddToList: true, canAddToRoulette: true, canShare: true,
      },
    }
    const card = renderToStaticMarkup(<RestaurantPreviewCard onClose={() => undefined} onEditAvatar={() => undefined} restaurant={restaurant} />)
    const gallery = card.match(/restaurant-detail-gallery__merchant[\s\S]*?<\/div>/)?.[0] ?? ''
    expect(gallery).toContain('aria-label="修改餐厅头像"')
    expect(gallery).toContain('restaurant-avatar-edit-button')
    expect(gallery.indexOf('修改餐厅头像')).toBeLessThan(gallery.indexOf('用户实拍'))

    const sheet = renderToStaticMarkup(<RestaurantAvatarEditorSheet detail={detail} onClose={() => undefined} onSaved={() => undefined} platform={platform} />)
    expect(sheet).toContain('修改餐厅头像')
    expect(sheet).toContain('上传图片')
    expect(sheet).toContain('从 iOS 照片中选择一张')
    expect(sheet).toContain('使用表情')
    expect(sheet).toContain('支持任意 iOS Emoji')
  })

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
    expect(scopeTabs).toContain('lucide-circle-check')
    expect(scopeTabs).not.toContain('lucide-footprints')
    expect(scopeTabs).toContain('>3</span>')
    expect(scopeTabs).toContain('>2</span>')
    expect(scopeTabs).toContain('>0</span>')
    expect(html).toContain('role="tab"')
    expect(html).not.toContain('适合你')
    expect(html).toContain('aria-label="口味数据进度，1 / 5，再评分 4 家，开始形成你的口味判断"')
    expect(html).toContain('（1 / 5 · 再评分 4 家，开始形成你的口味判断）')
    expect(html).toContain('class="tm-taste-data-progress"')
    expect(hybridMapReactControlSelector.split(',')).not.toContain('.tm-taste-data-progress')
  })

  it('renders My List as information-rich Restaurant entries backed by real fields', () => {
    const restaurant = {
      ...profile.restaurants[0],
      scoreOutOfTen: 9,
      visitCount: 3,
      averagePricePerPerson: 229,
      latestVisitDate: '2026-08-24T11:30:00.000Z',
      tags: ['杭帮菜', '江景', '适合约会'],
      longTermNote: '西湖边很稳定的一餐。',
    }
    const html = renderToStaticMarkup(<MyRestaurantList images={{ [restaurant.id]: image }} items={[restaurant]} loading={false} onOpen={() => undefined} scope="visited" />)
    expect(html).toContain('aria-label="去过的餐厅"')
    expect(html).toContain('MY TASTE MAP')
    expect(html).toContain('去过的餐厅')
    expect(html).toContain('aria-label="查看餐厅 ')
    expect(html).toContain('9.0 分，3 次到访，人均 229 元，最近到访')
    expect(html).toContain('tm-restaurant-image')
    expect(html).toContain('>9.0</b> 分')
    expect(html).toContain('3 次到访')
    expect(html).toContain('人均 ¥229')
    expect(html).toContain('最近到访')
    for (const value of ['杭帮菜', '江景', '适合约会', '我的印象 · 西湖边很稳定的一餐。']) expect(html).toContain(value)
  })

  it('keeps the canonical visited checkmark on owner and public Profile surfaces', () => {
    const owner = renderToStaticMarkup(<ProfilePage restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const ownerStatistics = owner.match(/profile-dashboard__counts--primary">([\s\S]*?)<\/div>/)?.[1] ?? ''
    expect(ownerStatistics).toContain('data-tastemap-semantic-icon="visited"')
    expect(ownerStatistics).toContain('lucide-circle-check')
    expect(ownerStatistics).not.toContain('lucide-map-pin')
    expect(ownerStatistics).not.toContain('lucide-footprints')

    const publicProfile = renderToStaticMarkup(<ProfilePage editable={false} restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const visitedEntry = publicProfile.match(/class="public-profile-footprint"[\s\S]*?<\/button>/)?.[0] ?? ''
    expect(visitedEntry).toContain('data-tastemap-semantic-icon="visited"')
    expect(visitedEntry).toContain('lucide-circle-check')
  })

  it('keeps Profile relationship counts with identity and balances the currency statistic', () => {
    const owner = renderToStaticMarkup(<ProfilePage followerCount={9} followingCount={14} restaurants={profile.restaurants} user={profile.user} visits={profile.visits} />)
    const nameIndex = owner.indexOf(profile.user.nickname)
    const userIDIndex = owner.indexOf('profile-user-id--under-name')
    const socialIndex = owner.indexOf('class="profile-dashboard__social-counts"')
    const joinedIndex = owner.indexOf('class="profile-joined-at"')
    const primaryStatsIndex = owner.indexOf('profile-dashboard__counts profile-dashboard__counts--primary')
    expect(owner.match(/profile-dashboard__social-counts/g)).toHaveLength(1)
    expect([nameIndex, userIDIndex, socialIndex, joinedIndex, primaryStatsIndex].every((index) => index >= 0)).toBe(true)
    expect(nameIndex).toBeLessThan(userIDIndex)
    expect(userIDIndex).toBeLessThan(socialIndex)
    expect(socialIndex).toBeLessThan(joinedIndex)
    expect(joinedIndex).toBeLessThan(primaryStatsIndex)
    expect(owner).not.toContain('profile-edit-button')
    expect(owner).toContain('class="is-currency"')
    expect(owner).toContain('aria-label="关注 14"')
    expect(owner).toContain('aria-label="粉丝 9"')
    expect(owner).not.toContain('被关注')
    expect(owner).not.toContain('关注我的')
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

  it('keeps Discovery at one five-tab product level and labels uncalibrated matching honestly', () => {
    const html = renderToStaticMarkup(<HybridDiscoveryPage content={content} onOpenRestaurant={() => undefined} platform={platform} />)
    for (const label of ['关注', '为你推荐', '同味之选', '最新', '趋势']) expect(html).toContain(label)
    expect(html).toContain('口味匹配度 88%')
    expect(html).not.toContain('喜欢度')
    expect(html).not.toContain('发现餐厅')
    expect(html).not.toContain('DISCOVER')
    expect(html).toContain('data-product-contract="discovery-page"')
    expect(html).toContain('data-product-contract="activity-card"')
    expect(html).toContain('data-recommendation-signal="match"')
    expect(html).toContain('--tm-taste-prediction-progress:88%')
    for (const region of ['restaurant-image', 'restaurant-name-address-context', 'visit-rating', 'like-comment-more-share', 'restaurant-actions']) {
      expect(html).toContain(`data-activity-region="${region}"`)
    }
  })

  it('retains a neutral matching signal when the heuristic percentage increases', () => {
    const stronger = structuredClone(content) as TasteMapHybridContentSnapshotDTO
    stronger.discovery.forYou[0].personalTastePercent = 96
    const html = renderToStaticMarkup(
      <HybridDiscoveryPage content={stronger} onOpenRestaurant={() => undefined} platform={platform} />,
    )
    expect(html).toContain('aria-label="口味匹配度 96%，查看说明"')
    expect(html).toContain('data-recommendation-signal="match"')
    expect(html).toContain('--tm-taste-prediction-progress:96%')
  })

  it.each(['activity', 'recommendation'] as const)('keeps %s single media compact without a hero escape hatch', (variant) => {
    const html = renderToStaticMarkup(<TasteMapActivityCardFrame
      media={<img src="/test.png" alt="餐厅图片" />}
      restaurant={<span>测试餐厅</span>}
      restaurantActions={<button type="button">记录</button>}
      variant={variant}
    />)
    expect(html).toContain('data-media-layout="compact"')
    expect(html).not.toContain('data-media-layout="wide"')
    expect(html).toContain('data-activity-region="restaurant-image"')
  })

  it('places an Activity Visit rating beside the Restaurant and colors it from that user rating', () => {
    const html = renderToStaticMarkup(<TasteMapActivityCardFrame
      activityRating={<TasteMapActivityRatingBadge rating={4.5} />}
      restaurant={<span>测试餐厅</span>}
      restaurantActions={<button type="button">记录</button>}
      variant="activity"
    />)
    const restaurantIndex = html.indexOf('data-activity-region="restaurant-name-address-context"')
    const ratingIndex = html.indexOf('data-activity-region="visit-rating"')
    expect(html).toContain('class="tm-activity-card__restaurant-row"')
    expect(html).toContain('data-media-layout="compact"')
    expect(html).not.toContain('data-media-layout="wide"')
    expect(ratingIndex).toBeGreaterThan(restaurantIndex)
    expect(html).toContain('aria-label="本次到访评分 9.0"')
    expect(html).toContain('>9.0</strong>')
    expect(html).toContain(`--tm-activity-rating-color:${scoreColor(9)}`)
  })

  it('labels a genuinely unrated Visit explicitly instead of showing an ambiguous dash', () => {
    const html = renderToStaticMarkup(<TasteMapActivityRatingBadge rating={null} />)
    expect(html).toContain('aria-label="本次到访未评分"')
    expect(html).toContain('>未评分</strong>')
    expect(html).not.toContain('>—</strong>')
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
    expect(html).toContain('class="tm-activity-card__restaurant-row"')
    expect(html).toContain('aria-label="推荐理由"')
    expect(html).toContain('class="tm-activity-card__recommendation-reasons is-for-you"')
    expect(html).not.toContain('为什么适合你')
    expect(html).toContain('aria-label="口味匹配度 88%，查看说明"')
    expect(html).toContain('class="tm-activity-card__taste-prediction is-match"')
    expect(html).not.toContain('大家评分')
    expect(html).not.toContain('优先推荐')
    expect(html).not.toContain('推荐给你')
    expect(html).not.toContain('查看推荐来源用户')
    expect(html).not.toContain('class="tm-activity-card__source"')
    expect(html).not.toContain('aria-label="关注用户"')
    expect(html).not.toContain('分享动态</button>')
    expect(html).toContain('aria-label="再次添加 ')
    expect(html).toContain('aria-label="已收藏餐厅 ')
    expect(html).toContain('aria-label="加入转盘 ')
    expect(html).toContain('lucide-plus')
    expect(html).not.toContain('lucide-notebook-pen')
    const restaurantActions = html.match(/data-activity-region="restaurant-actions">([\s\S]*?)<\/div><\/footer>/)?.[1] ?? ''
    expect(restaurantActions).toContain('lucide-bookmark')
    expect(html).not.toContain('aria-label="食单 ')
    expect(html).not.toContain('title="加入食单"')
    expect(html).not.toContain('lucide-circle-plus')
    expect(html).not.toContain('lucide-list-plus')
    expect(html).not.toContain('lucide-bookmark-plus')
    const socialActions = html.match(/data-activity-region="like-comment-more-share">([\s\S]*?)<\/div><div class="tm-activity-card__restaurant-actions"/)?.[1] ?? ''
    expect(socialActions).toContain('lucide-send')
    expect(socialActions).not.toContain('lucide-share-2')
    expect(socialActions.match(/<button/g)).toHaveLength(1)
    expect(restaurantActions.match(/<button/g)).toHaveLength(3)
  })

  it('shows only the rating badge when the similar-taste user is already identified', () => {
    const similarTasteContent = structuredClone(content) as TasteMapHybridContentSnapshotDTO
    similarTasteContent.discovery.forYou = [similarTasteContent.discovery.similarTaste[0]]
    const html = renderToStaticMarkup(
      <HybridDiscoveryPage content={similarTasteContent} onOpenRestaurant={() => undefined} platform={platform} />,
    )
    const similarRating = html.match(/class="tm-activity-card__similar-rating">([\s\S]*?)<\/span><\/div>/)?.[1] ?? ''
    expect(similarRating).toContain('tm-activity-rating-badge')
    expect(similarRating).not.toContain('<small>')
    expect(html).not.toContain('<small>评分</small>')
    expect(html).not.toContain('的评分</small>')
    expect(html).toContain('aria-label="林夏本次到访评分 9.0"')
    expect(html).toContain('>9.0</strong>')
    expect(html).toContain(`--tm-activity-rating-color:${scoreColor(9)}`)
    expect(html).not.toContain('tm-activity-card__restaurant-avatar')
    expect(html).toContain('tm-activity-card__restaurant-detail-icon')
    expect(html).toContain('lucide-store')
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
    )).toContain(' aria-label="口味匹配度 88%，查看说明"')
  })

  it('only exposes Like and Comment when the recommendation carries a concrete Visit identity', () => {
    const systemRecommendation = structuredClone(content) as TasteMapHybridContentSnapshotDTO
    systemRecommendation.discovery.forYou[0].interaction = null
    const html = renderToStaticMarkup(
      <HybridDiscoveryPage content={systemRecommendation} onOpenRestaurant={() => undefined} platform={platform} />,
    )
    expect(html).not.toContain('aria-label="点赞"')
    expect(html).not.toContain('aria-label="评论"')
    expect(html).toContain('aria-label="分享餐厅 ')
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

  it('projects the two newest owned Native Lists into Profile and opens the same DTO directly', () => {
    const base = content.lists[0]
    const lists = [
      { ...base, id: 'older-owned', title: '较早的食单', updatedAt: '2026-08-01T00:00:00Z' },
      { ...base, id: 'newest-owned', title: '刚刚更新的食单', updatedAt: '2026-09-05T00:00:00Z' },
      { ...base, id: 'second-owned', title: '第二新的食单', updatedAt: '2026-09-04T00:00:00Z' },
      { ...base, id: 'other-public', title: '别人的公开食单', isOwnedByViewer: false, updatedAt: '2026-09-06T00:00:00Z' },
    ]
    const preview = renderToStaticMarkup(<HybridProfileListsPreview lists={lists} onCreate={() => undefined} onOpenList={() => undefined} />)
    expect(preview).toContain('data-owned-list-count="3"')
    expect(preview).toContain('刚刚更新的食单')
    expect(preview).toContain('第二新的食单')
    expect(preview).not.toContain('较早的食单')
    expect(preview).not.toContain('别人的公开食单')
    expect(preview.match(/aria-label="查看食单 /g)).toHaveLength(2)

    const detail = renderToStaticMarkup(<TasteMapListsPage initialSelectedID="newest-owned" lists={lists} onInitialDetailBack={() => undefined} onOpenRestaurant={() => undefined} platform={platform} />)
    expect(detail).toContain('刚刚更新的食单')
    expect(detail).toContain('aria-label="返回上一页"')
    expect(detail).toContain('lucide-arrow-left')
    expect(detail).not.toContain('返回食单')
    expect(detail).toContain(base.restaurants[0].name)
  })

  it('renders only real Roulette candidates and restores the winning Restaurant identity', () => {
    const candidates = profile.restaurants.slice(0, 3)
    const winner = candidates[1]
    const roulette = renderToStaticMarkup(<RestaurantRoulette
      onClose={() => undefined}
      onSelectRestaurant={() => undefined}
      onSelectedRestaurantIdsChange={() => undefined}
      onSessionStateChange={() => undefined}
      onTemporaryItemsChange={() => undefined}
      restaurants={profile.restaurants}
      selectedRestaurantIds={candidates.map((item) => item.id)}
      sessionState={{ rotation: 1_980, winnerId: winner.id }}
      temporaryItems={[]}
    />)

    expect(roulette).toContain('aria-label="当前轮盘有 3 个扇区"')
    expect(roulette.match(/class="roulette-wheel-label"/g)).toHaveLength(3)
    expect(roulette).not.toContain('添加更多餐厅')
    const winnerCard = roulette.match(/class="roulette-winner"[\s\S]*?class="roulette-manage-button"/)?.[0] ?? ''
    expect(winnerCard).toContain('class="restaurant-avatar restaurant-avatar--small"')
    expect(winnerCard).toContain(winner.name)
    expect(winnerCard).not.toContain('lucide-sparkles')
  })

  it('uses the five approved Analytics names and readable full-report data anatomy', () => {
    const html = renderToStaticMarkup(<TasteMapAnalyticsPage onOpenRestaurant={() => undefined} platform={platform} profile={profile} />)
    for (const label of ['我的口味档案', '最佳饭搭子', '谁最会种草', '本月回顾', '年度回顾']) expect(html).toContain(label)
    expect(html).toContain('aria-label="分析模块"')
    expect(html).toContain('数据</button>')
    expect(html).toContain('画报</button>')
    expect(html).toContain('分享数据')
    expect(html).toContain('aria-label="我的口味档案数据报告"')
    expect(html).not.toContain('tm-taste-profile-replica')
    for (const label of ['data-explore-page="F01"', '最常记录', '常见时段', '主要城市', '查看完整分析']) expect(html).toContain(label)
    expect(html).not.toContain('查看章节')
    expect(html).not.toContain('data-analysis-section=')
  })

  it('shares the selected data module as readable real-data text', () => {
    const text = analysisDataShareText({
      reportId: 'report', type: 'MONTHLY_REVIEW', userId: 'owner',
      title: '本月回顾', eyebrow: 'MONTHLY REVIEW', subtitle: '2026 年 9 月',
      summary: '本月留下 4 次真实到访',
      metrics: [{ label: '餐厅', value: '3 家' }, { label: '消费', value: '¥520' }],
      insights: ['最常吃江浙菜'], keywords: [], restaurants: [], heroCandidates: [],
      footer: 'Taste Map · 基于真实记录生成', logoSource: '/icon.png',
      privacy: { companionNameIncluded: false, spendIncluded: true, exactLocationIncluded: false },
    })
    expect(text).toContain('数据\n餐厅：3 家\n消费：¥520')
    expect(text).toContain('洞察\n• 最常吃江浙菜')
  })

  it('keeps poster zoom controls inside the current preview surface', () => {
    const html = renderToStaticMarkup(<ZoomablePosterPreview alt="本月回顾分享海报" src="blob:poster" />)
    expect(html).toContain('class="poster-zoom-surface"')
    expect(html).toContain('data-poster-scale="1.00"')
    expect(html).toContain('aria-roledescription="可缩放海报"')
    expect(html).toContain('双指张合缩放，放大后拖动查看，双击恢复')
    expect(html).toContain('tabindex="0"')
  })

  it('opens a Profile Analytics entry as one dedicated report', () => {
    const html = renderToStaticMarkup(<TasteMapAnalyticsPage initialMode="monthly" onOpenRestaurant={() => undefined} platform={platform} profile={profile} singleReport />)
    expect(html).toContain('data-report-presentation="dedicated"')
    expect(html).toContain('class="tm-analysis-data__intro"')
    expect(html).toContain('aria-label="选择历史周期"')
    expect(html).toContain('<h1 tabindex="-1">本月回顾</h1>')
    expect(html.match(/<h1[^>]*>本月回顾<\/h1>/g)).toHaveLength(1)
    expect(html).not.toContain('class="tm-hybrid-page-header"')
    expect(html).not.toContain('<h1>数据分析</h1>')
    expect(html).toContain('aria-label="分析模块"')
    expect(html).toContain('aria-label="选择数据或画报"')
    expect(html).not.toContain('aria-label="分析类型"')
    expect(html).not.toContain('class="tm-hybrid-analysis-tabs"')
  })

  it('keeps Premium factual and Settings actions in the native service boundary', () => {
    const premium = renderToStaticMarkup(<TasteMapPremiumPage platform={platform} />)
    expect(premium).toContain('商品价格始终由 StoreKit')
    expect(premium).not.toMatch(/¥\s*\d/)
    const settings = renderToStaticMarkup(<TasteMapSettingsPage platform={{ ...platform, kind: 'native' }} profile={profile} />)
    expect(settings).toContain('账户与安全')
    expect(settings).not.toContain('账户与资料')
    expect(settings).not.toContain('>账户安全<')
    expect(settings).toContain('清除本机数据')
    expect(settings).toContain('保留账号、个人资料和云端数据')
    expect(settings).toContain('Backup v1 不包含照片原图')
    expect(settings).toContain('高风险操作继续由正式 Native service 承载')
    expect(settings).not.toContain('tm-hybrid-settings__logout')
    expect(settings).not.toContain('>删除账户<')
  })

  it.each(['member', 'free'] as const)('keeps %s membership benefits immediately after Account and separate from Storage', (membershipTier) => {
    const html = renderToStaticMarkup(<TasteMapSettingsPage platform={platform} profile={{ ...profile, user: { ...profile.user, membershipTier } }} />)
    const headings = [...html.matchAll(/<h2>([^<]+)<\/h2>/g)].map((match) => match[1])
    expect(headings).toEqual(['账户', '会员权益', '邀请奖励', '私人资料', '数据与备份', '同步', '隐私与权限', '存储', '帮助与关于'])
    expect(html.match(/<strong>饭搭子与推荐来源<\/strong>/g)).toHaveLength(1)
    expect(html.match(/<strong>邀请好友<\/strong>/g)).toHaveLength(1)
    expect(html.match(/<strong>Premium<\/strong>/g)).toHaveLength(1)
    expect(html).not.toContain('存储与 Premium')
    expect(html).toContain(membershipTier === 'member' ? '查看当前权益与订阅管理' : '查看会员能力')
  })

  it('gives every full-page drill-in one icon-only back action', () => {
    const onBack = vi.fn()
    const pages = [
      renderToStaticMarkup(<HybridAddRestaurantPage onBack={onBack} onOpenRestaurant={() => undefined} platform={platform} />),
      renderToStaticMarkup(<TasteMapListsPage lists={content.lists} onBack={onBack} onOpenRestaurant={() => undefined} platform={platform} />),
      renderToStaticMarkup(<TasteMapListsPage initialSelectedID="list-1" lists={content.lists} onInitialDetailBack={onBack} onOpenRestaurant={() => undefined} platform={platform} />),
      renderToStaticMarkup(<TasteMapAnalyticsPage initialMode="monthly" onBack={onBack} onOpenRestaurant={() => undefined} platform={platform} profile={profile} singleReport />),
      renderToStaticMarkup(<TasteMapPremiumPage onBack={onBack} platform={platform} />),
      renderToStaticMarkup(<TasteMapSettingsPage onBack={onBack} platform={platform} profile={profile} />),
    ]
    for (const html of pages) {
      expect(html.match(/aria-label="返回上一页"/g)).toHaveLength(1)
      expect(html.match(/class="tm-hybrid-page-navigation"/g)).toHaveLength(1)
      const backContent = html.match(/<button aria-label="返回上一页"[^>]*>([\s\S]*?)<\/button>/)?.[1] ?? ''
      expect(backContent).toContain('lucide-arrow-left')
      expect(backContent).not.toContain('返回')
    }
  })

})
