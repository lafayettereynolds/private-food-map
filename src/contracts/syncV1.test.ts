import { describe, expect, it } from 'vitest'
import legacyRestaurant from '../../contracts/fixtures/restaurant.v0.legacy.json'
import appleRestaurant from '../../contracts/fixtures/restaurant.v1.valid.json'
import legacyVisit from '../../contracts/fixtures/visit.v0.legacy.json'
import validVisit from '../../contracts/fixtures/visit.v1.valid.json'
import { decodeSyncPushRequest, decodeVisitSyncContract, stableSyncMutationJSON } from './syncV1'

describe('Sync API V1 contract', () => {
  it('accepts an Apple Maps-only Restaurant mutation', () => {
    const request = decodeSyncPushRequest(pushRequest({
      mutationId: 'mutation-apple', entityType: 'restaurant', entityId: appleRestaurant.id,
      operation: 'upsert', baseVersion: 0, clientTimestamp: appleRestaurant.updatedAt,
      payload: appleRestaurant,
    }))
    expect(request.mutations[0].payload).not.toHaveProperty('amapPoiId')
  })

  it('keeps the P0-A legacy Restaurant payload compatible', () => {
    const request = decodeSyncPushRequest(pushRequest({
      mutationId: 'mutation-legacy', entityType: 'restaurant', entityId: legacyRestaurant.id,
      operation: 'upsert', baseVersion: 0, clientTimestamp: legacyRestaurant.updatedAt,
      payload: legacyRestaurant,
    }))
    expect(request.mutations[0].payload).toMatchObject({ schemaVersion: 1, amapPoiId: 'B0LEGACYPOI' })
  })

  it('requires entity and payload IDs to agree', () => {
    expect(() => decodeSyncPushRequest(pushRequest({
      mutationId: 'mutation-wrong-id', entityType: 'restaurant', entityId: 'different',
      operation: 'upsert', baseVersion: 0, clientTimestamp: appleRestaurant.updatedAt,
      payload: appleRestaurant,
    }))).toThrow(/entityId/)
  })

  it('requires tombstones to use the delete operation', () => {
    expect(() => decodeSyncPushRequest(pushRequest({
      mutationId: 'mutation-tombstone-as-upsert', entityType: 'restaurant', entityId: appleRestaurant.id,
      operation: 'upsert', baseVersion: 1, clientTimestamp: appleRestaurant.updatedAt,
      payload: { ...appleRestaurant, deletedAt: '2026-08-27T08:00:00.000Z' },
    }))).toThrow(/operation=delete/)
  })

  it('keeps mutation fingerprints stable across object key ordering', () => {
    expect(stableSyncMutationJSON({ mutationId: 'm', entityType: 'visit', entityId: 'v', operation: 'delete', baseVersion: 1, clientTimestamp: 't' }))
      .toBe(stableSyncMutationJSON({ operation: 'delete', clientTimestamp: 't', entityId: 'v', mutationId: 'm', baseVersion: 1, entityType: 'visit' }))
  })

  it('preserves nil Visit ratings', () => {
    expect(decodeVisitSyncContract(validVisit)).toMatchObject({
      rating: null,
      valueRating: null,
      environmentRating: null,
      serviceRating: null,
    })
  })

  it('decodes complete and partial multidimensional Visit ratings', () => {
    expect(decodeVisitSyncContract({
      ...validVisit,
      rating: 4.5,
      valueRating: 5,
      environmentRating: null,
      serviceRating: 0.5,
    })).toMatchObject({ rating: 4.5, valueRating: 5, environmentRating: null, serviceRating: 0.5 })
  })

  it('rejects out-of-range and non-half-step multidimensional ratings', () => {
    for (const [field, value] of [
      ['valueRating', 0],
      ['environmentRating', 5.5],
      ['serviceRating', 4.2],
    ] as const) {
      expect(() => decodeVisitSyncContract({ ...validVisit, [field]: value })).toThrow(new RegExp(field))
    }
  })

  it('decodes dining mode and nullable party size', () => {
    expect(decodeVisitSyncContract(validVisit)).toMatchObject({ diningMode: 'takeout', partySize: null })
  })

  it('normalizes the P0 Visit payload without new fields', () => {
    expect(decodeVisitSyncContract(legacyVisit)).toMatchObject({
      diningMode: 'dine_in', visibility: 'private', partySize: null,
      totalPrice: null, paymentMode: null, pricePerPerson: null, queueDuration: null,
      diningOccasions: [], diningOccasionText: null,
      valueTags: [], environmentTags: [], serviceTags: [], specialNotes: null,
      valueRating: null, environmentRating: null, serviceRating: null,
    })
  })

  it('rejects invalid party size, dining mode, and negative spend', () => {
    expect(() => decodeVisitSyncContract({ ...validVisit, partySize: 0 })).toThrow(/partySize/)
    expect(() => decodeVisitSyncContract({ ...validVisit, diningMode: 'delivery' })).toThrow(/diningMode/)
    expect(() => decodeVisitSyncContract({ ...validVisit, myActualSpend: -1 })).toThrow(/negative/)
  })

  it('round-trips complete, partial, and explicitly empty P2-E context', () => {
    const complete = decodeVisitSyncContract({
      ...validVisit,
      visibility: 'friends', totalPrice: 360, paymentMode: 'aa', pricePerPerson: 120,
      queueDuration: 'none', diningOccasions: ['friends', 'other'], diningOccasionText: '工作简餐',
      valueTags: ['合理'], environmentTags: ['舒适'], serviceTags: ['周到'],
      noiseLevel: 'normal', diningDuration: 'under30', portionLevel: 'generous',
      transportConvenience: 'very_convenient', specialNotes: '现场取号',
    })
    expect(complete).toMatchObject({
      visibility: 'friends', totalPrice: 360, queueDuration: 'none',
      diningOccasions: ['friends', 'other'], specialNotes: '现场取号',
    })
    expect(decodeVisitSyncContract({ ...complete, queueDuration: null, paymentMode: null }))
      .toMatchObject({ queueDuration: null, paymentMode: null })
  })

  it('keeps wait=nil distinct from explicit no wait and rejects invalid money', () => {
    expect(decodeVisitSyncContract({ ...validVisit, queueDuration: null }).queueDuration).toBeNull()
    expect(decodeVisitSyncContract({ ...validVisit, queueDuration: 'none' }).queueDuration).toBe('none')
    expect(() => decodeVisitSyncContract({ ...validVisit, queueDuration: -1 })).toThrow(/queueDuration/)
    expect(() => decodeVisitSyncContract({ ...validVisit, totalPrice: -1 })).toThrow(/totalPrice/)
    expect(() => decodeVisitSyncContract({ ...validVisit, pricePerPerson: Number.POSITIVE_INFINITY })).toThrow(/pricePerPerson/)
  })

  it('handles unknown legacy enum values without crashing or losing their raw value', () => {
    expect(decodeVisitSyncContract({
      ...validVisit,
      paymentMode: 'legacy_split', queueDuration: 'legacy_wait_bucket',
      diningOccasions: ['friends', 'legacy_scene'], noiseLevel: 'legacy_noise',
    })).toMatchObject({
      paymentMode: 'legacy_split', queueDuration: 'legacy_wait_bucket',
      diningOccasions: ['friends', 'legacy_scene'], noiseLevel: 'legacy_noise',
    })
    expect(() => decodeVisitSyncContract({ ...validVisit, visibility: 'unknown' })).toThrow(/visibility/)
  })

  it('normalizes duplicate tags and supports nullable clear semantics', () => {
    expect(decodeVisitSyncContract({
      ...validVisit,
      valueTags: ['合理', ' 合理 ', '超值'], diningOccasionText: '', specialNotes: '',
    })).toMatchObject({ valueTags: ['合理', '超值'], diningOccasionText: null, specialNotes: null })
  })
})

function pushRequest(mutation: Record<string, unknown>) {
  return { apiVersion: 1, schemaVersion: 1, mutations: [mutation] }
}
