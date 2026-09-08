import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import { restaurantAvatarSelection } from './restaurantAvatarSelection'

const original = fixture.restaurants[0] as unknown as RestaurantSummary
const restaurant = { ...original, markerType: 'image' as const, markerImageData: null, markerPhotoId: null, markerEmoji: '', merchantImageUrl: 'https://example.test/merchant.jpg', visits: [] }
const visit = { ...original.visits[0], id: 'real-visit', photos: ['https://example.test/visit.jpg'], photoIds: ['visit-photo'], dishes: [], deletedAt: null }

describe('automatic avatar candidates', () => {
  it('uses an actual Visit photo, not merchant artwork', () => {
    const result = restaurantAvatarSelection({ ...restaurant, visits: [visit] })
    expect(result?.source).toBe('https://example.test/visit.jpg')
    expect(result?.visit?.id).toBe('real-visit')
    expect(restaurantAvatarSelection(restaurant)).toBeNull()
  })
  it('preserves explicit owner photo and emoji choices', () => {
    expect(restaurantAvatarSelection({ ...restaurant, markerImageData: 'custom-owner-photo', visits: [visit] })?.source).toBe('custom-owner-photo')
    expect(restaurantAvatarSelection({ ...restaurant, markerType: 'emoji', markerEmoji: '🧑🏽‍🍳', visits: [visit] })).toBeNull()
  })
  it('accepts ID-only actual Visit photos and skips deleted visits', () => {
    expect(restaurantAvatarSelection({ ...restaurant, visits: [{ ...visit, photos: [] }] })?.photoId).toBe('visit-photo')
    expect(restaurantAvatarSelection({ ...restaurant, visits: [{ ...visit, deletedAt: '2026-09-01' }] })).toBeNull()
  })
  it('uses actual dish photos when the Visit album is absent', () => {
    expect(restaurantAvatarSelection({ ...restaurant, visits: [{ ...visit, photos: [], photoIds: [], dishes: [{ id: 'dish', name: '牛排', taste: '', rating: null, price: null, imageData: 'dish-photo', photoId: 'dish-id' }] }] })?.source).toBe('dish-photo')
  })
})
