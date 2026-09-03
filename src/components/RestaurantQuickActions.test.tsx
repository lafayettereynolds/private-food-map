import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { RestaurantQuickActions } from './RestaurantQuickActions'

describe('RestaurantQuickActions', () => {
  it('keeps the restaurant actions in add, save, roulette order', () => {
    const markup = renderToStaticMarkup(<RestaurantQuickActions
      onRecordVisit={vi.fn()}
      onToggleWant={vi.fn()}
      onToggleWheel={vi.fn()}
      restaurantName="测试餐厅"
    />)

    const visitIndex = markup.indexOf('加入餐厅 测试餐厅')
    const wantIndex = markup.indexOf('收藏餐厅 测试餐厅')
    const wheelIndex = markup.indexOf('加入转盘 测试餐厅')

    expect(visitIndex).toBeGreaterThan(-1)
    expect(wantIndex).toBeGreaterThan(visitIndex)
    expect(wheelIndex).toBeGreaterThan(wantIndex)
    expect(markup).toContain('data-action-type="ADD_VISIT"')
    expect(markup).toContain('lucide-plus')
  })

  it('keeps all three actions for a visited restaurant and uses plus for another visit', () => {
    const markup = renderToStaticMarkup(<RestaurantQuickActions
      onRecordVisit={vi.fn()}
      onToggleWheel={vi.fn()}
      restaurantName="测试餐厅"
      visitedActive
    />)

    const visitIndex = markup.indexOf('再次添加 测试餐厅')
    const saveIndex = markup.indexOf('已收藏餐厅 测试餐厅')
    const wheelIndex = markup.indexOf('加入转盘 测试餐厅')

    expect(visitIndex).toBeGreaterThan(-1)
    expect(saveIndex).toBeGreaterThan(visitIndex)
    expect(wheelIndex).toBeGreaterThan(saveIndex)
    expect(markup).toContain('data-action-type="ADD_VISIT"')
    expect(markup).toContain('aria-pressed="true"')
    expect(markup).toContain('disabled=""')
  })

  it('lets a want-to-go restaurant remove its saved state without hiding the action', () => {
    const markup = renderToStaticMarkup(<RestaurantQuickActions
      onToggleWant={vi.fn()}
      restaurantName="测试餐厅"
      wantActive
    />)

    expect(markup).toContain('取消收藏餐厅 测试餐厅')
    expect(markup).toContain('aria-pressed="true"')
    expect(markup).not.toContain('disabled=""')
  })
})
