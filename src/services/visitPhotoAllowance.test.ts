import { describe, expect, it } from 'vitest'
import { assertDishPhotoAccess, assertVisitPhotoAllowance, visitPhotoCount } from './visitPhotoAllowance'

describe('per-Visit photo allowance, including dish photos', () => {
  it('requires Premium for dish photos even under the visit quota, retaining old photos', () => {
    const previous={photos:[],dishes:[{imageData:'old',photoId:null}]}
    expect(()=>assertDishPhotoAccess(previous,false)).toThrow('Premium')
    expect(()=>assertDishPhotoAccess(previous,true)).not.toThrow()
    expect(()=>assertDishPhotoAccess(previous,false,previous)).not.toThrow()
    expect(()=>assertDishPhotoAccess({photos:[],dishes:[]},false,previous)).not.toThrow()
    expect(()=>assertDishPhotoAccess({photos:[],dishes:[{imageData:'new',photoId:null}]},false,previous)).toThrow('Premium')
  })
  it('permits two free and twenty Premium photos, but not the next addition', () => {
    for (const limit of [2, 20]) {
      expect(() => assertVisitPhotoAllowance({ photos: Array.from({ length: limit }, (_, i) => `photo-${i}`) }, limit)).not.toThrow()
      expect(() => assertVisitPhotoAllowance({ photos: Array.from({ length: limit + 1 }, (_, i) => `photo-${i}`) }, limit)).toThrow()
    }
  })
  it('preserves historical three and twenty photos during unrelated edits, reorder and explicit removal', () => {
    for (const count of [3, 20]) {
      const previous = { photos: Array.from({ length: count }, (_, i) => `old-${i}`) }
      expect(() => assertVisitPhotoAllowance(previous, 2, previous)).not.toThrow()
      expect(() => assertVisitPhotoAllowance({ photos: [...previous.photos].reverse() }, 2, previous)).not.toThrow()
      expect(() => assertVisitPhotoAllowance({ photos: previous.photos.slice(1) }, 2, previous)).not.toThrow()
      expect(previous.photos).toHaveLength(count)
      expect(() => assertVisitPhotoAllowance({ photos: [...previous.photos, 'new'] }, 2, previous)).toThrow()
    }
  })
  it('uses stable IDs across URL refreshes, but not duplicate old raw sources as new material', () => {
    const previous = { photos: ['a', 'b', 'c'], photoIds: ['a', 'b', 'c'] }
    expect(() => assertVisitPhotoAllowance({ ...previous, photos: ['a', 'b', 'refreshed-url'] }, 2, previous)).not.toThrow()
    expect(() => assertVisitPhotoAllowance({ ...previous, photoIds: ['a', 'b', 'new-id'] }, 2, previous)).toThrow()
    expect(() => assertVisitPhotoAllowance({ photos: ['a', 'b', 'c', 'a'] }, 2, { photos: previous.photos })).toThrow()
    expect(() => assertVisitPhotoAllowance({ photos: ['a', 'new'] }, 2, previous)).not.toThrow()
  })
  it('counts ID-only and trailing ID photos before their URLs load', () => {
    const previous = { photos: [], photoIds: ['a', 'b', 'c'] }
    expect(visitPhotoCount(previous)).toBe(3)
    expect(visitPhotoCount({ photos: ['url-a'], photoIds: ['a', 'b', 'c'] })).toBe(3)
    expect(() => assertVisitPhotoAllowance(previous, 2)).toThrow()
    expect(() => assertVisitPhotoAllowance(previous, 2, previous)).not.toThrow()
    expect(() => assertVisitPhotoAllowance({ ...previous, photos: ['new-url-a', 'new-url-b', 'new-url-c'] }, 2, previous)).not.toThrow()
  })
  it('counts dish photos in the same budget, but a linked real Photo only once', () => {
    expect(() => assertVisitPhotoAllowance({ photos: ['a', 'b'], dishes: [{ imageData: 'c', photoId: null }] }, 2)).toThrow()
    expect(visitPhotoCount({ photos: ['a', 'b'], photoIds: ['a', 'b'], dishes: [{ imageData: 'a', photoId: 'a' }] })).toBe(2)
    const legacy = { photos: ['a', 'b'], dishes: [{ imageData: 'c', photoId: 'c' }] }
    expect(() => assertVisitPhotoAllowance(legacy, 2, legacy)).not.toThrow()
    expect(() => assertVisitPhotoAllowance({ ...legacy, dishes: [{ imageData: 'd', photoId: 'd' }] }, 2, legacy)).toThrow()
  })
})
