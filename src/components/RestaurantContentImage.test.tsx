import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import type { TasteMapImageDescriptor, TasteMapRestaurantDTO, TasteMapRestaurantDetailDTO } from '../platform/TasteMapPlatform'
import { projectBridgeRestaurant } from '../platform/TasteMapBridgeProjection'
import { HybridRestaurantContentImage, RestaurantContentImage, restaurantContentResolution } from './RestaurantContentImage'
import { HybridRestaurantImage } from './TasteMapHybridShared'
import { resolvedImageDescriptor } from './TasteMapImageResolution'

vi.mock('../services/photoAssets', () => ({ resolvePhotoSource: vi.fn() }))

const avatar: TasteMapImageDescriptor = { kind: 'ownerPhoto', resourceURL: 'https://example.test/custom-avatar.jpg',
  photoID: 'avatar', restaurantID: 'r1', visitID: null, sourceOwnerID: 'owner', visibility: 'private',
  exportAllowed: true, attributionRequired: false, accessibilityLabel: '自定义头像' }
const photo: TasteMapImageDescriptor = { ...avatar, resourceURL: 'https://example.test/visit.jpg', photoID: 'visit-photo', visitID: 'visit-1', accessibilityLabel: '用户实拍' }
const restaurant = { id: 'r1', name: '桂雨咖啡', tags: ['咖啡'], image: avatar } as TasteMapRestaurantDTO

describe('Restaurant content and avatar source separation', () => {
  it('never promotes a custom avatar into a Discovery content image', () => {
    const html = renderToStaticMarkup(<HybridRestaurantContentImage restaurant={restaurant} />)
    expect(html).toContain('data-food-library-artwork="coffee"')
    expect(html).not.toContain('custom-avatar.jpg')
    expect(html).not.toContain('restaurant-food-emoji')
  })
  it('keeps the independent avatar renderer unchanged', () => {
    expect(renderToStaticMarkup(<HybridRestaurantImage image={avatar} name={restaurant.name} />)).toContain('custom-avatar.jpg')
  })
  it('uses a real owner Visit photograph before illustration even with a custom avatar', () => {
    const html = renderToStaticMarkup(<HybridRestaurantContentImage restaurant={{ ...restaurant, contentImage: photo }} />)
    expect(html).toContain('visit.jpg')
    expect(html).not.toContain('custom-avatar.jpg')
    expect(html).not.toContain('data-food-library-artwork')
  })
  it('preserves exact authorized activity albums, without substituting the Restaurant avatar', () => {
    const activity = { ...photo, kind: 'activityPhoto' as const, visibility: 'friends' as const, exportAllowed: false }
    expect(renderToStaticMarkup(<HybridRestaurantContentImage restaurant={restaurant} activityImage={activity} />)).toContain('visit.jpg')
  })
  it('accepts explicit newly authorized content photographs without requiring a Visit link', () => {
    expect(restaurantContentResolution({ ...restaurant, contentImage: { ...photo, visitID: null } }).sources).toHaveLength(1)
    expect(restaurantContentResolution({ ...restaurant, image: { ...photo, kind: 'publicUGC', visitID: null } }).sources).toHaveLength(0)
  })
  it('retains the platform photo ordering and artwork after all photos fail', () => {
    const base = restaurantContentResolution(restaurant)
    const plan = { ...base, sources: [photo, { ...photo, photoID: 'photo2', resourceURL: 'https://example.test/second.jpg' }] }
    const resolved = restaurantContentResolution({ ...restaurant, contentImageResolution: plan })
    expect(resolvedImageDescriptor(resolved, 0)).toBe(photo)
    expect(resolvedImageDescriptor(resolved, 1)).toBe(plan.sources[1])
    expect(resolvedImageDescriptor(resolved, 2)).toBe(plan.fallback)
  })
  it('uses Browser real Visit/dish refs for a content cover and art only when absent', () => {
    const actual = renderToStaticMarkup(<RestaurantContentImage name="河岸牛排馆" tags={['西餐']} photos={[{ source: 'https://example.test/steak.jpg', photoId: 'photo' }]} />)
    expect(actual).toContain('steak.jpg')
    expect(actual).not.toContain('data-food-library-artwork')
    const fallback = renderToStaticMarkup(<RestaurantContentImage name="河岸牛排馆" tags={['西餐']} />)
    expect(fallback).toContain('data-food-library-artwork="steak"')
    expect(fallback).toContain('非餐厅实拍')
  })
  it('preserves additive bridge content fields without changing the avatar projection', () => {
    const resolution = { ...restaurantContentResolution(restaurant), sources: [photo] }
    const detail = projectBridgeRestaurant({ restaurant: { ...restaurant, city: '杭州', address: '实拍测试地址', visits: [], contentImage: photo, contentImageResolution: resolution },
      viewerState: 'visited', editableVisitIDs: [], capabilities: {},
    } as unknown as TasteMapRestaurantDetailDTO)
    expect(detail.image).toBe(avatar)
    expect(detail.restaurant.markerImageData).toBe(avatar.resourceURL)
    expect(detail.contentImage).toBe(photo)
    expect(detail.contentImageResolution).toBe(resolution)
  })
})
