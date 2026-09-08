import { describe, expect, it } from 'vitest'
import { renderToStaticMarkup } from 'react-dom/server'
import { FoodLibraryArtwork, resolveFoodLibraryArtwork } from './FoodLibraryArtwork'
import catalog from '../../public/food-library/catalog.json'

describe('supplied food artwork, distinct from restaurant avatars and real photos', () => {
  it.each([
    ['桂雨咖啡 7', ['早午餐'], 'coffee'], ['河岸牛排馆 4', ['西餐'], 'steak'],
    ['兰州拉面', ['中餐'], 'beef-noodles'], ['春日泰味 7', [], 'thai'],
    ['青岚寿司', [], 'sushi'], ['山茶烘焙', [], 'croissant'],
    ['秋水韩餐', [], 'korean'], ['野火烧鸟', [], 'yakitori'],
    ['Da Andrea', ['意大利菜'], 'pasta'], ['没有分类的店', [], 'dining'],
  ])('selects matching supplied art for %s', (name, tags, id) => {
    expect(resolveFoodLibraryArtwork({ name, tags }).id).toBe(id)
  })
  it('has valid cell bounds and every category default exists', () => {
    expect(new Set(catalog.entries.map(item => item.id)).size).toBe(catalog.entries.length)
    for (const item of catalog.entries) {
      expect(item.column).toBeGreaterThanOrEqual(0); expect(item.column).toBeLessThan(catalog.columns)
      expect(item.row).toBeGreaterThanOrEqual(0); expect(item.row).toBeLessThan(catalog.rows)
    }
    for (const id of Object.values(catalog.categoryDefaults)) expect(catalog.entries.some(entry => entry.id === id)).toBe(true)
    for (const [x, y, width, height] of Object.values(catalog.crops)) {
      expect(x).toBeGreaterThanOrEqual(0); expect(y).toBeGreaterThanOrEqual(0)
      expect(width).toBeGreaterThan(0); expect(height).toBeGreaterThan(0)
      expect(x + width).toBeLessThanOrEqual(catalog.sheetWidth)
      expect(y + height).toBeLessThanOrEqual(catalog.sheetHeight)
    }
  })
  it('labels illustration honestly and never renders emoji or a user-photo label', () => {
    const html = renderToStaticMarkup(<FoodLibraryArtwork name="桂雨咖啡" />)
    expect(html).toContain('/food-library/drinks-desserts.png')
    expect(html).toContain('非餐厅实拍')
    expect(html).not.toContain('我的餐厅头像')
    expect(html).not.toContain('☕')
    expect(html).toContain('overflow="hidden"')
  })
})
