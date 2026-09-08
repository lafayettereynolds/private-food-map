import { describe, expect, it } from 'vitest'
import type { TasteMapHybridDiscoveryItemDTO, TasteMapMapBrowseRequest } from '../platform/TasteMapPlatform'
import {
  canonicalForYouRecommendations,
  filterForYouMapRecommendations,
  forYouRecommendationDataVersion,
  projectForYouRecommendationsToMap,
  recommendationMapOptions,
} from './mapRecommendationSnapshot'

function recommendation(
  id: string,
  rank: number,
  overrides: Partial<TasteMapHybridDiscoveryItemDTO> = {},
): TasteMapHybridDiscoveryItemDTO {
  return {
    id: `placement-${id}-${rank}`,
    mode: 'for_you',
    restaurant: {
      id,
      name: `餐厅 ${id}`,
      address: `${rank} 号`,
      city: rank === 1 ? '杭州' : '上海',
      latitude: 30.27 + rank * 0.001,
      longitude: 120.15 + rank * 0.001,
      tags: rank === 1 ? ['泰国菜'] : ['咖啡'],
      referencePrice: rank === 1 ? 132 : 68,
      image: {
        kind: 'foodDiningFallback',
        stableSeed: id,
        accessibilityLabel: `餐厅 ${id} 图示`,
      },
    },
    viewerState: 'none',
    sourceUser: null,
    activityRating: null,
    activityVisitedAt: null,
    interaction: null,
    likedByViewer: false,
    likeCount: 0,
    commentCount: 0,
    communityRating: { valueOutOfFive: rank === 1 ? 4.45 : 4.1, sampleCount: 20 },
    reasons: [{ code: 'TASTE_TAG_MATCH', text: '符合你的口味' }],
    reason: '符合你的口味',
    similarityPercent: null,
    sharedRestaurantCount: null,
    trendWindowDays: null,
    uniqueVisitorCount: null,
    wantToGoCount: null,
    rank,
    ...overrides,
  }
}

function request(overrides: Partial<TasteMapMapBrowseRequest> = {}): TasteMapMapBrowseRequest {
  return {
    requestID: 'recommendation-snapshot-test',
    scope: 'recommended',
    filters: {},
    sort: 'recent',
    search: '',
    limit: 300,
    ...overrides,
  }
}

describe('shared For You recommendation snapshot', () => {
  it('takes city options only from the full eligible recommendation set, not personal cities or filtered markers', () => {
    const shanghai = recommendation('shanghai', 2)
    const alias = recommendation('alias', 3, { restaurant: { ...shanghai.restaurant, id: 'alias', city: '上海市' } })
    const excluded = recommendation('excluded', 4, { activityVisitedAt: '2026-09-06', activityRating: 1,
      restaurant: { ...shanghai.restaurant, id: 'excluded', city: '广州' } })
    const items = [recommendation('hangzhou', 1), shanghai, alias, excluded]
    const inherited = { cities: ['东京', '北京'], companions: [], cuisines: [], recommendationSources: [] }
    const options = recommendationMapOptions(inherited, items)
    expect(new Set(options.cities)).toEqual(new Set(['杭州', '上海']))
    expect(recommendationMapOptions(inherited, []).cities).toEqual([])
    const projected = projectForYouRecommendationsToMap(items, 'owner', '2026-09-06')
    expect(filterForYouMapRecommendations(projected, request({ filters: { city: '上海' } })).map((value) => value.restaurant.id))
      .toEqual(['shanghai', 'alias'])
    expect(filterForYouMapRecommendations(projected, request({ filters: { city: '上海市' } })).map((value) => value.restaurant.id))
      .toEqual(['shanghai', 'alias'])
    expect(recommendationMapOptions(inherited, items).cities).toEqual(options.cities)
    expect(alias.restaurant.city).toBe('上海市')
  })

  it('invalidates recommendation cache identity when a same-timestamp snapshot edits a city', () => {
    const first = recommendation('same', 1)
    const changed = { ...first, restaurant: { ...first.restaurant, city: '温州' } }
    expect(forYouRecommendationDataVersion('same-timestamp', [first]))
      .not.toBe(forYouRecommendationDataVersion('same-timestamp', [changed]))
  })

  it('keeps one canonical rank order and de-duplicates Restaurant identities for both surfaces', () => {
    const values = [recommendation('b', 2), recommendation('a', 1), recommendation('A', 3)]
    expect(canonicalForYouRecommendations(values).map((item) => item.restaurant.id)).toEqual(['a', 'b'])
  })

  it('projects public aggregate ratings onto the current ten-point Map scale', () => {
    const [value] = projectForYouRecommendationsToMap([recommendation('spring-thai', 1)], 'owner', '2026-09-04T00:00:00.000Z')
    expect(value.restaurant.id).toBe('spring-thai')
    expect(value.restaurant.scoreOutOfTen).toBe(8.9)
    expect(value.restaurant.isRecommendation).toBe(true)
    expect(value.restaurant.visitCount).toBe(0)
    expect(value.image.accessibilityLabel).toContain('spring-thai')
  })

  it('only narrows the shared members by Map viewport/filter and preserves rank by default', () => {
    const projected = projectForYouRecommendationsToMap(
      [recommendation('shanghai', 2), recommendation('hangzhou', 1)],
      'owner',
      '2026-09-04T00:00:00.000Z',
    )
    expect(filterForYouMapRecommendations(projected, request()).map((item) => item.restaurant.id))
      .toEqual(['hangzhou', 'shanghai'])
    expect(filterForYouMapRecommendations(projected, request({ filters: { city: '杭州' } })).map((item) => item.restaurant.id))
      .toEqual(['hangzhou'])
  })
})
