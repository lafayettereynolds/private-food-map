import { describe, expect, it } from 'vitest'
import type { RestaurantSummary } from '../types/domain'
import {
  OWNER_PROFILE_STAT_LABELS,
  PUBLIC_PROFILE_STAT_LABELS,
  publicProfileTabLabels,
  selectUniqueProfileRestaurants,
  shouldShowMutualWant,
  shouldShowPremiumBurger,
  visibleProfileBio,
} from './profileTopStats'

function restaurant(overrides: Partial<RestaurantSummary>): RestaurantSummary {
  return {
    id: overrides.id ?? crypto.randomUUID(),
    amapPoiId: overrides.amapPoiId ?? '',
    name: overrides.name ?? '同一家餐厅',
    address: overrides.address ?? '测试路 1 号',
    city: overrides.city ?? '杭州',
    latitude: overrides.latitude ?? 30.25,
    longitude: overrides.longitude ?? 120.16,
    status: overrides.status ?? 'visited',
    preferenceLevel: overrides.preferenceLevel ?? null,
    scoreOutOfTen: overrides.scoreOutOfTen ?? null,
    visitCount: overrides.visitCount ?? 0,
    latestVisitDate: overrides.latestVisitDate ?? null,
    latestVisit: overrides.latestVisit ?? null,
    visits: overrides.visits ?? [],
    tags: overrides.tags ?? [],
    markerImageData: overrides.markerImageData ?? '',
    markerPhotoId: overrides.markerPhotoId ?? null,
    merchantImageUrl: overrides.merchantImageUrl ?? '',
  } as RestaurantSummary
}

describe('selectUniqueProfileRestaurants', () => {
  it('counts a visited restaurant only once when records share an AMap POI id', () => {
    const result = selectUniqueProfileRestaurants([
      restaurant({ id: 'visit-a', amapPoiId: 'POI-1' }),
      restaurant({ id: 'visit-b', amapPoiId: 'poi-1', visitCount: 3 }),
    ], 'visited')
    expect(result).toHaveLength(1)
  })

  it('deduplicates want-to-go restaurants by city, name and address without a POI id', () => {
    const result = selectUniqueProfileRestaurants([
      restaurant({ id: 'want-a', status: 'wantToGo', name: '小馆', address: '湖滨路 1 号' }),
      restaurant({ id: 'want-b', status: 'wantToGo', name: '小馆', address: '湖滨路 1 号' }),
    ], 'wantToGo')
    expect(result).toHaveLength(1)
  })

  it('keeps visited and want-to-go status calculations separate', () => {
    const restaurants = [restaurant({ id: 'visited' }), restaurant({ id: 'want', status: 'wantToGo' })]
    expect(selectUniqueProfileRestaurants(restaurants, 'visited').map((item) => item.id)).toEqual(['visited'])
    expect(selectUniqueProfileRestaurants(restaurants, 'wantToGo').map((item) => item.id)).toEqual(['want'])
  })
})

describe('profile information architecture', () => {
  it('uses the four agreed top-level stats without public visit counts', () => {
    expect(OWNER_PROFILE_STAT_LABELS).toEqual(['我关注的', '关注我的', '去过', '想吃'])
    expect(PUBLIC_PROFILE_STAT_LABELS).toEqual(['关注', '粉丝', '去过餐厅', '想去餐厅'])
    expect([...OWNER_PROFILE_STAT_LABELS, ...PUBLIC_PROFILE_STAT_LABELS]).not.toContain('公开记录')
  })

  it('shows an actual bio only when it contains content', () => {
    expect(visibleProfileBio('  喜欢寻找值得回去的小店  ')).toBe('喜欢寻找值得回去的小店')
    expect(visibleProfileBio('   ')).toBeNull()
    expect(visibleProfileBio(null)).toBeNull()
  })

  it('keeps a single public-profile navigation and hides unavailable taste', () => {
    expect(publicProfileTabLabels(true)).toEqual(['动态', '口味', '食单'])
    expect(publicProfileTabLabels(false)).toEqual(['动态', '食单'])
  })

  it('only exposes mutual wants when the intersection is not empty', () => {
    expect(shouldShowMutualWant(0)).toBe(false)
    expect(shouldShowMutualWant(2)).toBe(true)
  })

  it('shows the burger badge to members only', () => {
    expect(shouldShowPremiumBurger('member')).toBe(true)
    expect(shouldShowPremiumBurger('free')).toBe(false)
    expect(shouldShowPremiumBurger(null)).toBe(false)
  })
})
