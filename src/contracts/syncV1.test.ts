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
    expect(decodeVisitSyncContract(validVisit).rating).toBeNull()
  })

  it('decodes dining mode and nullable party size', () => {
    expect(decodeVisitSyncContract(validVisit)).toMatchObject({ diningMode: 'takeout', partySize: null })
  })

  it('normalizes the P0 Visit payload without new fields', () => {
    expect(decodeVisitSyncContract(legacyVisit)).toMatchObject({ diningMode: 'dine_in', partySize: null })
  })

  it('rejects invalid party size, dining mode, and negative spend', () => {
    expect(() => decodeVisitSyncContract({ ...validVisit, partySize: 0 })).toThrow(/partySize/)
    expect(() => decodeVisitSyncContract({ ...validVisit, diningMode: 'delivery' })).toThrow(/diningMode/)
    expect(() => decodeVisitSyncContract({ ...validVisit, myActualSpend: -1 })).toThrow(/negative/)
  })
})

function pushRequest(mutation: Record<string, unknown>) {
  return { apiVersion: 1, schemaVersion: 1, mutations: [mutation] }
}
