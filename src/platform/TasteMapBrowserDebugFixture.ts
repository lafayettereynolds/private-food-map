import type { RestaurantSummary, StarRating, UserProfile, Visit } from '../types/domain'
import fixtureSource from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type {
  TasteMapHybridActivityItemDTO,
  TasteMapHybridContentRestaurantDTO,
  TasteMapHybridContentSnapshotDTO,
  TasteMapHybridDiscoveryItemDTO,
  TasteMapHybridListDTO,
  TasteMapImageDescriptor,
  TasteMapProfileDashboardViewModel,
} from './TasteMapPlatform'

interface DebugFixtureRoot {
  profile: {
    user: UserProfile
    followerCount: number
    followingCount: number
  }
  restaurants: RestaurantSummary[]
}

export interface TasteMapBrowserDebugFixtureSnapshot {
  profile: TasteMapProfileDashboardViewModel
  content: TasteMapHybridContentSnapshotDTO
}

let snapshotPromise: Promise<TasteMapBrowserDebugFixtureSnapshot> | null = null

export function loadTasteMapBrowserDebugFixture() {
  snapshotPromise ??= Promise.resolve(buildSnapshot(fixtureSource as unknown as DebugFixtureRoot))
  return snapshotPromise
}

function buildSnapshot(fixture: DebugFixtureRoot): TasteMapBrowserDebugFixtureSnapshot {
  const restaurants = expandRichMapRestaurants(fixture.restaurants)
  const visits = restaurants.flatMap((restaurant) => restaurant.visits) as Visit[]
  const restaurantImages = Object.fromEntries(restaurants.map((restaurant) => [restaurant.id, imageDescriptor(restaurant)]))
  const profile: TasteMapProfileDashboardViewModel = {
    user: fixture.profile.user,
    restaurants,
    visits,
    followerCount: fixture.profile.followerCount,
    followingCount: fixture.profile.followingCount,
    restaurantImages,
  }
  return { profile, content: buildContent(profile) }
}

/** Mirrors the Native Debug fixture scale without adding any Release data. */
export function expandRichMapRestaurants(source: RestaurantSummary[]) {
  if (!source.length) return []
  const seedVisit = source.flatMap((restaurant) => restaurant.visits)[0]
  if (!seedVisit) return source
  const visitedCount = 90
  const totalCount = visitedCount + 25
  const anchors = [
    [30.2741, 120.1551], [30.2676, 120.1474], [30.2819, 120.1628],
    [30.2558, 120.1692], [30.2912, 120.1398], [30.2449, 120.1825],
  ] as const
  return Array.from({ length: totalCount }, (_, index): RestaurantSummary => {
    const template = source[index % source.length]
    const id = index < source.length ? template.id : fixtureUUID(10_000 + index)
    const visited = index < visitedCount
    const anchor = anchors[index % anchors.length]
    const ring = (Math.floor(index / anchors.length) % 7)
    const angle = index * 137 * Math.PI / 180
    const latitude = anchor[0] + Math.sin(angle) * (0.00018 + ring * 0.00008)
    const longitude = anchor[1] + Math.cos(angle) * (0.00018 + ring * 0.00009)
    const visitCount = visited ? (index < 5 ? 4 : 3) : 0
    const visits = Array.from({ length: visitCount }, (_, visitIndex): Visit => {
      const templateVisit = template.visits[0] ?? seedVisit
      const visitedAt = new Date(new Date(templateVisit.visitedAt).getTime() - (index * 4 + visitIndex) * 86_400_000).toISOString()
      const rating = (index + visitIndex) % 7 === 0 ? null : fixtureRating(index + visitIndex)
      return {
        ...templateVisit,
        id: fixtureUUID(100_000 + index * 10 + visitIndex),
        restaurantId: id,
        visitedAt,
        rating,
        valueRating: rating == null ? null : fixtureRating(index + visitIndex + 2),
        environmentRating: rating == null ? null : fixtureRating(index + visitIndex + 1),
        serviceRating: rating,
        createdAt: visitedAt,
        updatedAt: visitedAt,
      }
    })
    const ratings = visits.flatMap((visit) => visit.rating == null ? [] : [visit.rating])
    const averageRating = ratings.length ? ratings.reduce((sum, value) => sum + value, 0) / ratings.length : null
    return {
      ...template,
      id,
      name: index < source.length ? template.name : `${template.name} · ${index + 1}`,
      latitude,
      longitude,
      status: visited ? 'visited' : 'wantToGo',
      visits,
      visitCount,
      averageRating,
      scoreOutOfTen: averageRating == null ? null : averageRating * 2,
      latestVisitDate: visits[0]?.visitedAt ?? null,
      createdAt: new Date(new Date(template.createdAt).getTime() - index * 43_200_000).toISOString(),
      updatedAt: new Date(new Date(template.updatedAt).getTime() - (index % 9) * 3_600_000).toISOString(),
    }
  })
}

function fixtureRating(seed: number): StarRating {
  const ratings: StarRating[] = [3.5, 4, 4.5, 5, 4.5, 4, 3.5, 4]
  return ratings[Math.abs(seed) % ratings.length]
}

function fixtureUUID(value: number) {
  return `00000000-0000-4000-8000-${String(value).padStart(12, '0')}`
}

function buildContent(profile: TasteMapProfileDashboardViewModel): TasteMapHybridContentSnapshotDTO {
  const generatedAt = new Date().toISOString()
  const names = ['林夏', '周舟', '陈一碗', '江南胃', '阿岚', '西湖小柚', '陆小满', '一只饭团']
  const discovery: TasteMapHybridDiscoveryItemDTO[] = profile.restaurants.slice(0, 12).map((restaurant, index) => {
    const sourceUser = {
      id: `tm_demo_${index}`,
      name: names[index % names.length],
      city: restaurant.city,
      avatarPhotoID: null,
      avatarPresetID: (['otter', 'polar-bear', 'fox', 'capybara'][index % 4] ?? 'otter') as UserProfile['avatarPresetId'],
      isFollowing: index % 2 === 0,
    }
    return {
      id: `hybrid-discovery-${index}`,
      mode: 'for_you',
      restaurant: contentRestaurant(profile, restaurant),
      viewerState: restaurant.status === 'visited' ? 'visited' : 'want_to_go',
      sourceUser,
      activityRating: restaurant.averageRating,
      activityVisitedAt: restaurant.latestVisitDate,
      communityRating: {
        valueOutOfFive: restaurant.averageRating == null ? null : Math.max(0, restaurant.averageRating - 0.05),
        sampleCount: restaurant.averageRating == null ? 0 : 10 + index,
      },
      reason: index % 2 === 0 ? '与你常吃的菜系很接近' : '同城高质量真实记录',
      similarityPercent: 82 - index * 3,
      sharedRestaurantCount: 6 + index,
      uniqueVisitorCount: 18 + index * 4,
      wantToGoCount: 9 + index,
      rank: index + 1,
    }
  })
  const similarTaste: TasteMapHybridDiscoveryItemDTO[] = discovery.map((item) => ({
    ...item,
    id: `similar-${item.id}`,
    mode: 'similar_taste',
    reason: `与这位用户有 ${item.sharedRestaurantCount ?? 0} 家共同到访`,
    uniqueVisitorCount: null,
    wantToGoCount: null,
  }))
  const trending: TasteMapHybridDiscoveryItemDTO[] = discovery.map((item) => ({
    ...item,
    id: `trending-${item.id}`,
    mode: 'trending',
    reason: `最近 7 天有 ${item.uniqueVisitorCount ?? 0} 位用户到访`,
    similarityPercent: null,
    sharedRestaurantCount: null,
  }))
  const activities: TasteMapHybridActivityItemDTO[] = discovery.map((item, index) => ({
    id: `hybrid-activity-${index}`,
    kind: index % 5 === 4 ? 'want_to_go' : 'visit',
    eventAt: item.activityVisitedAt ?? generatedAt,
    user: item.sourceUser!,
    restaurant: item.restaurant,
    visitID: index % 5 === 4 ? null : `demo-visit-${index}`,
    visitRating: index % 5 === 4 ? null : item.activityRating,
    note: index % 5 === 4 ? null : ['值得专程来吃，服务也很细致。', '今天最惊喜的是招牌菜。', '和朋友一起吃很舒服。', '会为了这道菜再来一次。'][index % 4],
    viewerState: item.viewerState,
    likedByViewer: index === 1,
    likeCount: 12 + index * 5,
    commentCount: 2 + index,
  }))
  const lists: TasteMapHybridListDTO[] = Array.from({ length: 5 }, (_, index) => {
    const values = profile.restaurants.flatMap((restaurant, position) => position % 5 === index ? [{
      id: restaurant.id,
      name: restaurant.name,
      address: restaurant.address,
      city: restaurant.city,
      position,
      note: index === 1 ? '本月想去' : '',
      image: profile.restaurantImages[restaurant.id],
    }] : [])
    return {
      id: `hybrid-list-${index}`,
      title: ['杭州私藏餐厅', '周末想吃', '年度 TOP 10', '适合约会', '朋友来杭带吃'][index],
      description: index === 2 ? '按我的真实到访评分排序。' : '基于真实记录整理的食单。',
      visibility: index === 4 ? 'public' : index === 3 ? 'friends' : 'private',
      isRanked: index === 2,
      isOwnedByViewer: true,
      ownerName: 'Lafayette',
      restaurantCount: values.length,
      restaurants: values,
      updatedAt: generatedAt,
    }
  })
  return {
    generatedAt,
    discovery: { forYou: discovery, similarTaste, trending },
    community: { following: activities.filter((item) => item.user.isFollowing), latest: activities },
    lists,
  }
}

function contentRestaurant(profile: TasteMapProfileDashboardViewModel, restaurant: RestaurantSummary): TasteMapHybridContentRestaurantDTO {
  return {
    id: restaurant.id,
    name: restaurant.name,
    address: restaurant.address,
    city: restaurant.city,
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    tags: restaurant.tags,
    referencePrice: restaurant.averagePricePerPerson ?? restaurant.pricePerPerson,
    image: profile.restaurantImages[restaurant.id],
  }
}

function imageDescriptor(restaurant: RestaurantSummary): TasteMapImageDescriptor {
  if (restaurant.markerPhotoId) {
    return {
      kind: 'publicOrCached',
      resourceURL: `tastemap-resource://public-photo/${encodeURIComponent(restaurant.markerPhotoId)}/display`,
      photoID: restaurant.markerPhotoId,
      accessibilityLabel: `${restaurant.name} 餐厅图片`,
    }
  }
  if (restaurant.merchantImageUrl) {
    return { kind: 'providerMerchant', resourceURL: restaurant.merchantImageUrl, accessibilityLabel: `${restaurant.name} 餐厅图片` }
  }
  return { kind: 'foodDiningFallback', stableSeed: restaurant.id, accessibilityLabel: `${restaurant.name} 餐饮图示` }
}
