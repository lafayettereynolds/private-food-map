import { describe, expect, it } from 'vitest'
import { FOOD_CATEGORY_VISUAL_IDS, resolveFoodCategoryVisualID, resolveRestaurantFoodEmoji } from './FoodCategoryVisualContract'

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

  it.each([
    ['街角咖啡', [], '☕️'],
    ['经典牛排馆', [], '🥩'],
    ['青岚寿司', [], '🍣'],
    ['春日泰味', [], '🍛'],
    ['湖滨粤菜', [], '🥟'],
    ['木屋烧烤', [], '🍢'],
    ['无分类餐厅', [], '🍽️'],
  ] as const)('uses a matching food emoji for %s', (name, tags, expected) => {
    expect(resolveRestaurantFoodEmoji({ name, tags })).toBe(expected)
  })

  it('preserves an explicit non-generic Restaurant emoji but replaces generic tableware when evidence is specific', () => {
    expect(resolveRestaurantFoodEmoji({ name: '山岚小馆' }, '🌮')).toBe('🌮')
    expect(resolveRestaurantFoodEmoji({ name: '山岚咖啡' }, '🍽️')).toBe('☕️')
    expect(resolveRestaurantFoodEmoji({ name: '山岚咖啡' }, '🍴')).toBe('☕️')
  })
})
