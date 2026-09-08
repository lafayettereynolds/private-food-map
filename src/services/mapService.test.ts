import { describe, expect, it, vi } from 'vitest'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))

import { amapCategoryHints } from './amap'
import { rankRestaurantSearchMatches } from './restaurantSearchRelevance'

describe('Restaurant search relevance', () => {
  const values = [
    { name: '青岚寿司', address: '杭州市美食街 1 号', city: '杭州', district: '上城区' },
    { name: '牛 New 寿喜烧', address: '杭州市延安路 88 号', city: '杭州', district: '上城区' },
    { name: '山茶烘焙', address: '杭州市美食街 81 号', city: '杭州', district: '上城区' },
  ]

  it('keeps only genuine mixed CJK/Latin name matches', () => {
    expect(rankRestaurantSearchMatches(values, '牛new').map((value) => value.name)).toEqual(['牛 New 寿喜烧'])
  })

  it('supports address search and removes unrelated provider suggestions', () => {
    expect(rankRestaurantSearchMatches(values, '延安路 88').map((value) => value.name)).toEqual(['牛 New 寿喜烧'])
    expect(rankRestaurantSearchMatches(values, '完全不存在')).toEqual([])
  })

  it('matches a restaurant name and its neighbourhood across actual provider fields, never another branch', () => {
    const values = [
      { name: 'Da Andrea', address: '160 8th Ave', city: 'New York', district: 'Chelsea' },
      { name: 'Top Thai Greenwich', address: '235 Sullivan St', city: 'New York', district: 'Greenwich Village' },
      { name: 'Da Andrea', address: '35 W 13th St', city: 'New York', district: 'Greenwich Village' },
    ]
    expect(rankRestaurantSearchMatches(values, 'Da Andrea Greenwich Village').map((value) => value.address))
      .toEqual(['35 W 13th St'])
    expect(rankRestaurantSearchMatches(values, 'Da Andrea').map((value) => value.address))
      .toEqual(['160 8th Ave', '35 W 13th St'])
  })

  it('keeps the Lanzhou noodle shorthand without admitting unrelated shops or arbitrary subsequences', () => {
    const candidates = ['兰州牛肉拉面（凯旋门商业中心店）', '兰州拉面（另一分店）', '杭州牛肉拉面', '兰州烧烤', '兰州某个很长很长很长的商城拉面'].map((name) => ({ name, address: '', city: '杭州', district: '' }))
    expect(rankRestaurantSearchMatches(candidates, '兰州拉面').map((value) => value.name)).toEqual([
      '兰州拉面（另一分店）', '兰州牛肉拉面（凯旋门商业中心店）',
    ])
  })
})

describe('AMap Provider category projection', () => {
  it('keeps real hierarchy and food tags while removing only the universal root', () => {
    expect(amapCategoryHints(
      '餐饮服务;外国餐厅;西餐厅(综合风味)',
      '牛排、烧烤',
    )).toEqual(['外国餐厅', '西餐厅(综合风味)', '牛排', '烧烤'])
  })

  it('returns no category when the Provider supplies none', () => {
    expect(amapCategoryHints(undefined, null)).toEqual([])
  })
})
