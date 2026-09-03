import { describe, expect, it } from 'vitest'
import { FOOD_CATEGORY_VISUAL_IDS, resolveFoodCategoryVisualID } from './FoodCategoryVisualContract'

describe('FoodCategoryVisual contract', () => {
  it('keeps a bounded stable taxonomy', () => {
    expect(FOOD_CATEGORY_VISUAL_IDS).toEqual([
      'chinese', 'japaneseKorean', 'western', 'hotpotBBQ', 'noodles',
      'cafeBakery', 'drinksDessert', 'seafood', 'fastFood', 'vegetarianLight', 'other',
    ])
  })

  it.each([
    ['川味小馆', ['川菜'], 'chinese'],
    ['湖滨二十八号', ['杭帮菜'], 'chinese'],
    ['牛New寿喜烧', ['日料'], 'japaneseKorean'],
    ['街角 Bistro', [], 'western'],
    ['木屋烧烤', [], 'hotpotBBQ'],
    ['兰州拉面', [], 'noodles'],
    ['Manner Coffee', [], 'cafeBakery'],
    ['桂花甜品铺', [], 'drinksDessert'],
    ['蒸汽海鲜', [], 'seafood'],
    ['Shake Shack 汉堡', [], 'fastFood'],
    ['绿野轻食', [], 'vegetarianLight'],
    ['无分类餐厅', [], 'other'],
  ] as const)('maps %s to %s', (name, tags, expected) => {
    expect(resolveFoodCategoryVisualID({ name, tags })).toBe(expected)
  })
})
