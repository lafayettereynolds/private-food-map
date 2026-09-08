import { describe, expect, it } from 'vitest'
import {
  RestaurantUGCImagePool,
  resolveRestaurantVisualSelection,
  type RestaurantUGCPhotoRecord,
} from './restaurantUGCImagePool'

const base: RestaurantUGCPhotoRecord = {
  id: 'photo-public', restaurant_id: 'restaurant-a', visit_id: 'visit-a', user_id: 'author', kind: 'visit',
  visibility: 'public', visit_visibility: 'public', profile_visibility: 'public',
  created_at: '2026-08-01T00:00:00.000Z', sort_order: 0, marker_photo_id: null,
  deleted_at: null, moderation_eligible: true,
}

describe('RestaurantUGCImagePool', () => {
  it('rejects pending, missing and wrong-owner binary metadata on shipping projections', () => {
    const photo = { ...base, sync_status: 'synced', storage_key: 'users/author/photos/photo-public/display.jpg', thumbnail_storage_key: 'users/author/photos/photo-public/thumbnail.jpg' }
    expect(new RestaurantUGCImagePool([photo]).publicUGC(['restaurant-a'])?.photo.id).toBe(base.id)
    for (const override of [{ sync_status: 'uploading' }, { storage_key: null }, { thumbnail_storage_key: null },
      { storage_key: 'users/another-person/photos/photo-public/display.jpg' },
      { thumbnail_storage_key: 'users/author/photos/different-photo/thumbnail.jpg' }]) {
      expect(new RestaurantUGCImagePool([{ ...photo, ...override }]).publicUGC(['restaurant-a'])).toBeNull()
    }
  })
  it('excludes custom Restaurant avatars from every automatic and public content pool', () => {
    const marker = { ...base, id: 'custom-avatar', kind: 'restaurant-marker', marker_photo_id: 'custom-avatar' }
    const avatar = { ...base, id: 'profile-avatar', kind: 'avatar' }
    const pool = new RestaurantUGCImagePool([marker, avatar, base])
    expect(pool.currentOwner(['restaurant-a'], 'author')?.photo.id).toBe(base.id)
    expect(pool.publicUGC(['restaurant-a'])?.photo.id).toBe(base.id)
    expect(pool.activityPhotos('visit-a', 'author', 'viewer', true).map(x => x.photo.id)).toEqual([base.id])
    expect(new RestaurantUGCImagePool([marker]).publicUGC(['restaurant-a'])).toBeNull()
  })
  it('keeps complete ordered albums scoped to one Visit/author without marker preference or duplicates', () => {
    const ordered = Array.from({ length: 12 }, (_, index) => ({ ...base, id: `photo-${index}`, sort_order: index,
      marker_photo_id: 'photo-11' }))
    const pool = new RestaurantUGCImagePool([
      ...[...ordered].reverse(), ordered[0],
      { ...base, id: 'another-visit', visit_id: 'visit-other' },
      { ...base, id: 'wrong-author', user_id: 'another-author' },
      { ...base, id: 'restaurant-only', visit_id: null },
      { ...base, id: 'deleted', deleted_at: '2026-09-01' },
      { ...base, id: 'binary-deleted', binary_deleted_at: '2026-09-01' },
      { ...base, id: 'moderated', moderation_eligible: false },
      { ...base, id: 'private', visibility: 'private' },
    ])
    const album = pool.activityPhotos('visit-a', 'author', 'viewer', false)
    expect(album.map((item) => item.photo.id)).toEqual(ordered.map((item) => item.id))
    expect(album.every((item) => item.sourceType === 'activityAuthorPhoto' && item.exportAllowed === false)).toBe(true)
    expect(pool.activityPhotos('missing', 'author', 'viewer', true)).toEqual([])
  })

  it('keeps friends-photo eligibility and owner export distinct from publicly reusable UGC', () => {
    const pool = new RestaurantUGCImagePool([{ ...base, visibility: 'friends', visit_visibility: 'friends', profile_visibility: 'friends' }])
    expect(pool.activityPhotos('visit-a', 'author', 'viewer', false)).toEqual([])
    expect(pool.activityPhotos('visit-a', 'author', 'viewer', true)).toHaveLength(1)
    expect(pool.activityPhotos('visit-a', 'author', 'viewer', true)[0].exportAllowed).toBe(false)
    expect(pool.activityPhotos('visit-a', 'author', 'author', true)[0].exportAllowed).toBe(true)
    expect(pool.publicUGC(['restaurant-a'])).toBeNull()
  })

  it('uses current-owner photos before public UGC and preserves export boundary', () => {
    const owner = { ...base, id: 'owner-photo', user_id: 'viewer', visibility: 'private' as const, visit_visibility: 'private' as const }
    const pool = new RestaurantUGCImagePool([base, owner])
    expect(pool.currentOwner(['restaurant-a'], 'viewer')).toMatchObject({ sourceType: 'currentOwnerPhoto', exportAllowed: true, photo: { id: 'owner-photo' } })
    expect(pool.publicUGC(['restaurant-a'])).toMatchObject({ sourceType: 'publicUGC', exportAllowed: false, photo: { id: 'photo-public' } })
  })

  it('never admits friends-only content into the public pool', () => {
    const friend = { ...base, id: 'friend-photo', visibility: 'friends' as const, visit_visibility: 'friends' as const }
    const pool = new RestaurantUGCImagePool([friend])
    expect(pool.publicUGC(['restaurant-a'])).toBeNull()
    expect(pool.activity('visit-a', 'viewer', true)?.photo.id).toBe('friend-photo')
    expect(pool.activity('visit-a', 'viewer', false)).toBeNull()
  })

  it('allows a public photo on a friends-visible activity only for an authorized friend', () => {
    const friendVisit = { ...base, id: 'friend-visit-photo', visit_visibility: 'friends' as const, profile_visibility: 'friends' as const }
    const pool = new RestaurantUGCImagePool([friendVisit])
    expect(pool.activity('visit-a', 'viewer', true)?.photo.id).toBe('friend-visit-photo')
    expect(pool.activity('visit-a', 'viewer', false)).toBeNull()
    expect(pool.publicUGC(['restaurant-a'])).toBeNull()
  })

  it('admits a public Restaurant-level photo without a Visit but still requires a public profile', () => {
    const restaurantPhoto = { ...base, id: 'restaurant-photo', visit_id: null, visit_visibility: null }
    const hiddenProfile = { ...restaurantPhoto, id: 'hidden-profile', profile_visibility: 'private' as const }
    const pool = new RestaurantUGCImagePool([hiddenProfile, restaurantPhoto])
    expect(pool.publicUGC(['restaurant-a'])?.photo.id).toBe('restaurant-photo')
  })

  it('fails closed for deletion and moderation and selects deterministically', () => {
    const deleted = { ...base, id: 'deleted', deleted_at: '2026-08-02T00:00:00.000Z' }
    const moderated = { ...base, id: 'moderated', moderation_eligible: false }
    const marker = { ...base, id: 'marker', marker_photo_id: 'marker', created_at: '2026-07-01T00:00:00.000Z' }
    const newer = { ...base, id: 'newer', created_at: '2026-09-01T00:00:00.000Z' }
    const pool = new RestaurantUGCImagePool([deleted, moderated, newer, marker])
    expect(pool.publicUGC(['restaurant-a'])?.photo.id).toBe('marker')
  })

  it('applies one explicit surface matrix and leaves category fallback to the renderer', () => {
    const owner = { ...base, id: 'owner', user_id: 'viewer', visibility: 'private' as const, visit_visibility: 'private' as const }
    const activity = { ...base, id: 'activity', visit_id: 'visit-activity', created_at: '2026-09-02T00:00:00.000Z' }
    const pool = new RestaurantUGCImagePool([base, owner, activity])
    const resolve = (surface: Parameters<typeof resolveRestaurantVisualSelection>[1]['surface']) =>
      resolveRestaurantVisualSelection(pool, {
        surface, restaurantIDs: ['restaurant-a'], viewerID: 'viewer', activityVisitID: 'visit-activity',
      })
    expect(resolve('map')?.sourceType).toBe('currentOwnerPhoto')
    expect(resolve('search')?.sourceType).toBe('currentOwnerPhoto')
    expect(resolve('nearby')?.sourceType).toBe('currentOwnerPhoto')
    expect(resolve('for_you')?.sourceType).toBe('currentOwnerPhoto')
    expect(resolve('trending')?.sourceType).toBe('currentOwnerPhoto')
    expect(resolve('following')?.sourceType).toBe('activityAuthorPhoto')
    expect(resolve('similar_taste')?.sourceType).toBe('activityAuthorPhoto')
    expect(resolve('latest')?.sourceType).toBe('activityAuthorPhoto')
    expect(resolveRestaurantVisualSelection(new RestaurantUGCImagePool([]), {
      surface: 'for_you', restaurantIDs: ['restaurant-a'], viewerID: 'viewer',
    })).toBeNull()
  })
})
