import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import type { RestaurantSummary } from '../types/domain'
import { RestaurantAvatar } from './RestaurantAvatar'
import { RestaurantSummarySection } from './RestaurantRecordSummary'
import { HybridRestaurantImage } from './TasteMapHybridShared'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))

describe('RestaurantAvatar real image priority', () => {
  it('never automatically uses a provider image as the Restaurant avatar', () => {
    const html = renderToStaticMarkup(<RestaurantAvatar restaurant={restaurant({
      markerType: 'image',
      merchantImageUrl: 'https://images.example.test/merchant.jpg',
      markerEmoji: '🍽️',
    })} />)

    expect(html).not.toContain('src="https://images.example.test/merchant.jpg"')
    expect(html).toContain('🥩')
  })

  it('preserves an explicit owner emoji choice', () => {
    const html = renderToStaticMarkup(<RestaurantAvatar restaurant={restaurant({
      markerType: 'emoji',
      merchantImageUrl: 'https://images.example.test/merchant.jpg',
      markerEmoji: '🍣',
    })} />)

    expect(html).not.toContain('merchant.jpg')
    expect(html).toContain('🍣')
  })

  it('renders the exact iOS emoji carried by a Hybrid fallback descriptor', () => {
    const html = renderToStaticMarkup(<HybridRestaurantImage
      image={{
        kind: 'foodCategoryVisual', categoryVisualID: 'other', stableSeed: 'restaurant-1',
        preferredEmoji: '🧑🏽‍🍳', exportAllowed: false, accessibilityLabel: '我的餐厅表情',
      }}
      name="真实餐厅"
    />)

    expect(html).toContain('🧑🏽‍🍳')
  })

  it('keeps Detail content independent of the custom emoji and merchant image', () => {
    const html = renderToStaticMarkup(<RestaurantSummarySection restaurant={restaurant({
      markerType: 'emoji', markerEmoji: '🍜',
      merchantImageUrl: 'https://images.example.test/merchant.jpg',
    })} />)

    expect(html).toContain('data-food-library-artwork')
    expect(html).not.toContain('我的餐厅表情')
    expect(html).not.toContain('🍜')
    expect(html).not.toContain('src="https://images.example.test/merchant.jpg"')
  })
})

function restaurant(overrides: Partial<RestaurantSummary>): RestaurantSummary {
  return {
    id: 'restaurant-1', userId: 'owner', amapPoiId: 'amap-1', name: '真实餐厅', address: '真实地址', city: '杭州',
    latitude: 30.25, longitude: 120.16, status: 'visited', preferenceLevel: 'normal', overallRating: null,
    foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, tags: ['西餐'], longTermNote: '',
    pricePerPerson: null, phone: null, openingHours: null, markerType: 'emoji', markerImageData: null, markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: '🍽️', createdAt: '', updatedAt: '', deletedAt: null, visitCount: 0,
    averageRating: null, scoreOutOfTen: null, latestVisitDate: null, latestVisit: null, visits: [],
    averagePricePerPerson: null, averageQueueMinutes: null, ...overrides,
  }
}
