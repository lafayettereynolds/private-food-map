import { describe, expect, it } from 'vitest'
import type { RestaurantSummary } from '../types/domain'
import { buildRestaurantShareModel, isShareCancellation, presentablePublicRating, publicRestaurantIdFor } from './restaurantShare'

const restaurant = {
  id: 'private-db-id-123',
  amapPoiId: 'B0PRIVATEPOI',
  name: '浅草君日式烧肉（来福士店）',
  city: '杭州市',
  address: '来福士中心附近 22 号',
  tags: ['日料', '烧烤', '饭搭子:小王', '私密标签'],
  merchantImageUrl: 'https://images.example.com/merchant.jpg',
  markerImageData: 'data:image/jpeg;base64,PRIVATE_USER_PHOTO',
  averagePricePerPerson: 168,
  pricePerPerson: 180,
} as RestaurantSummary

describe('restaurant sharing', () => {
  it('builds a stable opaque public restaurant id', async () => {
    expect(await publicRestaurantIdFor(restaurant)).toBe(await publicRestaurantIdFor({ ...restaurant }))
    expect(await publicRestaurantIdFor(restaurant)).toMatch(/^[a-f0-9]{24}$/)
  })

  it('does not expose the database id or provider POI id in the public URL', async () => {
    const model = await buildRestaurantShareModel(restaurant, null, 'https://taste.example')
    expect(model.url).not.toContain(restaurant.id)
    expect(model.url).not.toContain(restaurant.amapPoiId)
  })

  it('uses only the discover share referral parameter', async () => {
    const model = await buildRestaurantShareModel(restaurant, null, 'https://taste.example')
    const url = new URL(model.url)
    expect([...url.searchParams.entries()]).toEqual([['ref', 'discover_share']])
  })

  it('uses the stable merchant cover rather than a private marker photo', async () => {
    const model = await buildRestaurantShareModel(restaurant, null, 'https://taste.example')
    expect(model.coverImageUrl).toBe(restaurant.merchantImageUrl)
    expect(JSON.stringify(model)).not.toContain('PRIVATE_USER_PHOTO')
  })

  it('shares only public cuisine tags', async () => {
    const model = await buildRestaurantShareModel(restaurant, null, 'https://taste.example')
    expect(model.cuisines).toEqual(['日料', '烧烤'])
    expect(JSON.stringify(model)).not.toContain('小王')
    expect(JSON.stringify(model)).not.toContain('私密标签')
  })

  it('hides public ratings with fewer than five independent users', () => {
    expect(presentablePublicRating({ value: 9.8, sampleCount: 4 })).toBeNull()
  })

  it('marks five to nine independent users as low confidence', () => {
    expect(presentablePublicRating({ value: 8.3, sampleCount: 9 })).toEqual({ value: 8.3, sampleCount: 9, confidence: 'low' })
  })

  it('shows ten or more independent users normally', () => {
    expect(presentablePublicRating({ value: 8.6, sampleCount: 24 })).toEqual({ value: 8.6, sampleCount: 24, confidence: 'normal' })
  })

  it('supports a restaurant without an image', async () => {
    const model = await buildRestaurantShareModel({ ...restaurant, merchantImageUrl: null }, null, 'https://taste.example')
    expect(model.coverImageUrl).toBeNull()
  })

  it('recognizes a cancelled system share without treating it as an error', () => {
    expect(isShareCancellation(new DOMException('cancelled', 'AbortError'))).toBe(true)
    expect(isShareCancellation(new Error('network failed'))).toBe(false)
  })
})
