import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { RestaurantQuickActions } from './RestaurantQuickActions'

describe('RestaurantQuickActions', () => {
  it('keeps the restaurant actions in plus, want, wheel order', () => {
    const markup = renderToStaticMarkup(<RestaurantQuickActions
      onRecordVisit={vi.fn()}
      onToggleWant={vi.fn()}
      onToggleWheel={vi.fn()}
      restaurantName="测试餐厅"
    />)

    const visitIndex = markup.indexOf('记录这家餐厅 测试餐厅')
    const wantIndex = markup.indexOf('加入想吃 测试餐厅')
    const wheelIndex = markup.indexOf('加入抽签 测试餐厅')

    expect(visitIndex).toBeGreaterThan(-1)
    expect(wantIndex).toBeGreaterThan(visitIndex)
    expect(wheelIndex).toBeGreaterThan(wantIndex)
    expect(markup).toContain('data-action-type="ADD_VISIT"')
    expect(markup).toContain('lucide-plus')
  })

  it('uses the same plus action for another visit without turning it into a toggle', () => {
    const markup = renderToStaticMarkup(<RestaurantQuickActions
      onRecordVisit={vi.fn()}
      restaurantName="测试餐厅"
      visitedActive
    />)

    expect(markup).toContain('再次记录到访 测试餐厅')
    expect(markup).not.toContain('aria-pressed')
  })
})
