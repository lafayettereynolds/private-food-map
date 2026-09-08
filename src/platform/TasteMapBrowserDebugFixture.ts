import type { RestaurantSummary, StarRating, UserProfile, Visit } from '../types/domain'
import fixtureSource from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type {
  TasteMapHybridActivityItemDTO,
  TasteMapCommunityCommentDTO,
  TasteMapHybridContentRestaurantDTO,
  TasteMapHybridContentSnapshotDTO,
  TasteMapHybridDiscoveryItemDTO,
  TasteMapHybridListDTO,
  TasteMapImageDescriptor,
  TasteMapProfileDashboardViewModel,
} from './TasteMapPlatform'
import { isDiscoveryFeedActivityEligible } from './TasteMapDiscoveryPolicy'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'
import { recommendationHistoryReasons } from '../services/recommendationHistoryReasons'

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
  commentsByVisit: Record<string, TasteMapCommunityCommentDTO[]>
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
  const content = buildContent(profile)
  return { profile, content, commentsByVisit: buildComments(content) }
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
  const historyReasons = (candidate: RestaurantSummary) => recommendationHistoryReasons(
    { tags: candidate.tags, pricePerPerson: candidate.pricePerPerson ?? null },
    profile.restaurants.filter((restaurant) => restaurant.id !== candidate.id).map((restaurant) => {
      const visits = restaurant.visits.filter((visit) => !visit.deletedAt)
      const ratings = visits.flatMap((visit) => visit.rating != null ? [visit.rating] : [])
      return { tags: restaurant.tags, pricePerPerson: restaurant.pricePerPerson ?? null,
        ratingCount: ratings.length, ratingSumOutOfFive: ratings.reduce((sum, rating) => sum + rating, 0), visitCount: visits.length }
    }),
  )
  const sourceUsers = profile.restaurants.slice(0, 12).map((restaurant, index) => ({
    id: `tm_demo_${index}`,
    name: names[index % names.length],
    city: restaurant.city,
    avatarPhotoID: null,
    avatarPresetID: (['otter', 'polar-bear', 'fox', 'capybara'][index % 4] ?? 'otter') as UserProfile['avatarPresetId'],
    isFollowing: index % 2 === 0,
  }))
  const discovery: TasteMapHybridDiscoveryItemDTO[] = profile.restaurants.slice(0, 12).map((restaurant, index) => {
    const sourceUser = sourceUsers[index]
    return {
      id: `hybrid-discovery-${index}`,
      mode: 'for_you',
      restaurant: {
        ...contentRestaurant(profile, restaurant),
        image: index === 0
          ? profile.restaurantImages[restaurant.id]
          : index % 2 === 0
            ? categoryDescriptor(restaurant)
            : fixtureUGCDescriptor(restaurant, sourceUsers[index].id, 'publicUGC', index),
      },
      viewerState: restaurant.status === 'visited' ? 'visited' : 'want_to_go',
      sourceUser: null,
      activityRating: null,
      activityVisitedAt: null,
      interaction: null,
      likedByViewer: index === 1,
      likeCount: 12 + index * 5,
      commentCount: 2 + index,
      personalTastePercent: 88 - index,
      communityRating: {
        valueOutOfFive: restaurant.averageRating == null ? null : Math.max(0, restaurant.averageRating - 0.05),
        sampleCount: restaurant.averageRating == null ? 0 : 10 + index,
      },
      reasons: [{
        code: 'TASTE_TAG_MATCH',
        text: `与你去过的「${profile.restaurants[(index + 1) % profile.restaurants.length]?.name ?? '历史高分餐厅'}」相似 ${88 - index}%`,
      }, ...historyReasons(restaurant)].slice(0, 3),
      reason: `与你去过的「${profile.restaurants[(index + 1) % profile.restaurants.length]?.name ?? '历史高分餐厅'}」相似 ${88 - index}%`,
      similarityPercent: null,
      sharedRestaurantCount: null,
      trendWindowDays: null,
      uniqueVisitorCount: null,
      wantToGoCount: null,
      rank: index + 1,
    }
  })
  const similarTaste: TasteMapHybridDiscoveryItemDTO[] = discovery.map((item, index) => ({
    ...item,
    id: `similar-${item.id}`,
    mode: 'similar_taste',
    restaurant: {
      ...item.restaurant,
      image: index % 2 === 0
        ? fixtureUGCDescriptor(profile.restaurants[index], sourceUsers[index].id, 'activityPhoto', index)
        : categoryDescriptor(profile.restaurants[index]),
    },
    sourceUser: sourceUsers[index],
    activityImages: fixtureActivityAlbum(profile.restaurants[index], sourceUsers[index].id, `demo-visit-similar-${index}`, index),
    activityRating: [4.5, 4, 5, 4.5][index % 4] ?? 4.5,
    activityVisitedAt: profile.restaurants[index]?.latestVisitDate ?? generatedAt,
    interaction: {
      activityID: `similar-activity-${index}`,
      visitID: `demo-visit-similar-${index}`,
      authorID: sourceUsers[index].id,
      restaurantID: item.restaurant.id,
    },
    reasons: [{ code: 'SIMILAR_USERS', text: `基于 ${6 + index} 家共同评分餐厅，你与这位用户的口味相似度为 ${82 - index * 3}%` },
      { code: 'SOURCE_VISIT_RATING', text: `这位同味用户在本次到访给这家餐厅 ${([4.5, 4, 5, 4.5][index % 4] ?? 4.5) * 2}/10 分` },
      ...historyReasons(profile.restaurants[index]).slice(0, 1)],
    reason: `基于 ${6 + index} 家共同评分餐厅，你与这位用户的口味相似度为 ${82 - index * 3}%`,
    similarityPercent: 82 - index * 3,
    sharedRestaurantCount: 6 + index,
    trendWindowDays: null,
    uniqueVisitorCount: null,
    wantToGoCount: null,
  }))
  const trending: TasteMapHybridDiscoveryItemDTO[] = discovery.map((item, index) => ({
    ...item,
    id: `trending-${item.id}`,
    mode: 'trending',
    restaurant: {
      ...item.restaurant,
      image: index % 2 === 0
        ? fixtureUGCDescriptor(profile.restaurants[index], sourceUsers[index].id, 'publicUGC', index)
        : categoryDescriptor(profile.restaurants[index]),
    },
    interaction: null,
    reasons: [
      { code: 'TRENDING_UNIQUE_USERS', text: `近 7 天有 ${18 + index * 4} 位用户到访` },
      { code: 'RECENT_WANT_TO_GO', text: `近期有 ${9 + index} 位用户加入想吃` },
    ],
    reason: `近 7 天有 ${18 + index * 4} 位用户到访`,
    similarityPercent: null,
    sharedRestaurantCount: null,
    trendWindowDays: 7,
    uniqueVisitorCount: 18 + index * 4,
    wantToGoCount: 9 + index,
  }))
  // These are concrete public Visit ratings, not Restaurant averages. The last
  // Visit intentionally has no rating so fixtures exercise the real exclusion
  // rule without surfacing an unreliable card in Discovery.
  const activityVisitRatings: Array<number | null> = [4.5, 4, 4.8, 4.3, null, 4.6, 4.5, 4.7, 3.9, null, 4.4, null]
  const activities: TasteMapHybridActivityItemDTO[] = discovery.map((item, index) => ({
    id: `hybrid-activity-${index}`,
    kind: index % 5 === 4 ? 'want_to_go' : 'visit',
    eventAt: profile.restaurants[index]?.latestVisitDate ?? generatedAt,
    user: sourceUsers[index],
    restaurant: {
      ...item.restaurant,
      image: index % 2 === 0
        ? fixtureUGCDescriptor(profile.restaurants[index], sourceUsers[index].id, 'activityPhoto', index)
        : categoryDescriptor(profile.restaurants[index]),
    },
    visitID: index % 5 === 4 ? null : `demo-visit-${index}`,
    activityImages: index % 5 === 4 ? undefined
      : fixtureActivityAlbum(profile.restaurants[index], sourceUsers[index].id, `demo-visit-${index}`, index === 6 ? 4 : index),
    interaction: index % 5 === 4 ? null : {
      activityID: `hybrid-activity-${index}`,
      visitID: `demo-visit-${index}`,
      authorID: sourceUsers[index].id,
      restaurantID: item.restaurant.id,
    },
    visitRating: index % 5 === 4 ? null : (activityVisitRatings[index] ?? null),
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
    community: {
      following: activities.filter(isDiscoveryFeedActivityEligible).filter((item) => item.user.isFollowing),
      latest: activities.filter(isDiscoveryFeedActivityEligible),
    },
    lists,
  }
}

function buildComments(content: TasteMapHybridContentSnapshotDTO): Record<string, TasteMapCommunityCommentDTO[]> {
  const names = ['周予安', '林夏', '陈屿', '西湖小柚']
  const bodies = [
    '招牌菜很好吃，下次还会再来。',
    '环境舒服，适合和朋友一起吃。',
    '这家已经收藏，准备再试其他菜。',
    '服务很细致，整体体验不错。',
  ]
  const generatedAt = new Date(content.generatedAt).getTime()
  const interactiveItems = [
    ...content.discovery.forYou,
    ...content.discovery.similarTaste,
    ...content.discovery.trending,
    ...content.community.latest,
  ].filter((item, index, values) => {
    const visitID = item.interaction?.visitID
    return Boolean(visitID) && values.findIndex((candidate) => candidate.interaction?.visitID === visitID) === index
  })
  return Object.fromEntries(interactiveItems.flatMap((item, itemIndex) => {
    const visitID = item.interaction?.visitID
    if (!visitID) return []
    const comments = Array.from({ length: item.commentCount }, (_, commentIndex): TasteMapCommunityCommentDTO => ({
      id: `demo-comment-${itemIndex}-${commentIndex}`,
      visitID,
      body: bodies[commentIndex % bodies.length],
      author: {
        id: `tm_demo_commenter_${commentIndex % names.length}`,
        name: names[commentIndex % names.length],
        city: item.restaurant.city,
        avatarPhotoID: null,
        avatarPresetID: (['fox', 'otter', 'capybara', 'polar-bear'][commentIndex % 4] ?? 'otter') as UserProfile['avatarPresetId'],
        isFollowing: commentIndex % 2 === 0,
      },
      createdAt: new Date(generatedAt - (itemIndex * 24 + commentIndex + 1) * 3_600_000).toISOString(),
    }))
    return [[visitID, comments] as const]
  }))
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
  const visitPhoto = restaurant.visits.flatMap((visit) => visit.photos.map((resourceURL, index) => ({
    resourceURL,
    photoID: visit.photoIds[index] ?? `debug-owner-${visit.id}-${index}`,
    visit,
  }))).find((value) => value.resourceURL)
  if (visitPhoto) {
    return {
      kind: 'ownerPhoto', resourceURL: visitPhoto.resourceURL, photoID: visitPhoto.photoID,
      restaurantID: restaurant.id, visitID: visitPhoto.visit.id, sourceOwnerID: restaurant.userId,
      visibility: visitPhoto.visit.visibility, exportAllowed: true, attributionRequired: false,
      accessibilityLabel: `${restaurant.name} 用户实拍`,
    }
  }
  if (restaurant.markerPhotoId) {
    return {
      kind: 'ownerPhoto',
      resourceURL: `tastemap-resource://public-photo/${encodeURIComponent(restaurant.markerPhotoId)}/display`,
      photoID: restaurant.markerPhotoId,
      restaurantID: restaurant.id,
      visitID: null,
      sourceOwnerID: restaurant.userId,
      visibility: 'private',
      exportAllowed: true,
      attributionRequired: false,
      accessibilityLabel: `${restaurant.name} 餐厅图片`,
    }
  }
  return {
    kind: 'foodCategoryVisual', categoryVisualID: resolveFoodCategoryVisualID(restaurant), stableSeed: restaurant.id,
    exportAllowed: false, accessibilityLabel: `${restaurant.name} 餐饮分类图示`,
  }
}

function categoryDescriptor(restaurant: RestaurantSummary): TasteMapImageDescriptor {
  return {
    kind: 'foodCategoryVisual', categoryVisualID: resolveFoodCategoryVisualID(restaurant), stableSeed: restaurant.id,
    exportAllowed: false, accessibilityLabel: `${restaurant.name} 餐饮分类图示`,
  }
}

function fixtureUGCDescriptor(
  restaurant: RestaurantSummary,
  sourceOwnerID: string,
  kind: 'activityPhoto' | 'publicUGC',
  index: number,
): TasteMapImageDescriptor {
  const assets = ['chinese.png', 'japanese.png', 'hotpot-grill.png', 'western.png', 'cafe.png']
  return {
    kind,
    resourceURL: `/food-heroes/${assets[index % assets.length]}`,
    photoID: `debug-${kind}-${index}`,
    restaurantID: restaurant.id,
    visitID: kind === 'activityPhoto' ? `debug-visit-${index}` : null,
    sourceOwnerID,
    visibility: 'public',
    exportAllowed: false,
    attributionRequired: false,
    accessibilityLabel: `${restaurant.name} 用户实拍`,
  }
}

/** Isolated layout albums: distinct bundled test artwork, never production Visit data. */
function fixtureActivityAlbum(restaurant: RestaurantSummary, sourceOwnerID: string, visitID: string, index: number): TasteMapImageDescriptor[] {
  const resources = ['chinese.png', 'japanese.png', 'hotpot-grill.png', 'western.png', 'cafe.png', 'mixed.png'].map((asset) => `/food-heroes/${asset}`)
  resources.push('data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="320" height="320"><rect width="320" height="320" fill="#d9e9e6"/><text x="160" y="165" text-anchor="middle" font-size="36" fill="#244c43">QA PHOTO 7</text></svg>'))
  const count = [1, 2, 4, 5, 6, 7, 0, 3][index] ?? 0
  return resources.slice(0, count).map((resourceURL, slot) => ({
    kind: 'activityPhoto', resourceURL, photoID: `debug-album-${visitID}-${slot}`,
    restaurantID: restaurant.id, visitID, sourceOwnerID, visibility: 'public',
    exportAllowed: false, attributionRequired: false, accessibilityLabel: `${restaurant.name} 隔离布局测试图 ${slot + 1}`,
  }))
}
