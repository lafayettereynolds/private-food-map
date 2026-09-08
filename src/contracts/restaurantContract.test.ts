import { describe, expect, it } from 'vitest'
import schema from '../../contracts/restaurant.v1.schema.json'
import validFixture from '../../contracts/fixtures/restaurant.v1.valid.json'
import legacyFixture from '../../contracts/fixtures/restaurant.v0.legacy.json'
import type { Restaurant } from '../types/domain'
import {
  decodeRestaurantJSONContract,
  restaurantToJSONContract,
} from './restaurantContract'

describe('Restaurant JSON contract V1', () => {
  it('decodes the shared Apple Maps fixture without a legacy Amap ID', () => {
    const restaurant = decodeRestaurantJSONContract(validFixture)

    expect(restaurant.schemaVersion).toBe(1)
    expect(restaurant.id).not.toBe(restaurant.placeIdentities[0].externalId)
    expect(restaurant.placeIdentities).toEqual([expect.objectContaining({
      provider: 'apple_maps',
      externalId: 'apple-place-2B34C5D6',
      isPrimary: true,
    })])
    expect(restaurant).not.toHaveProperty('amapPoiId')
  })

  it('upgrades a legacy Web Restaurant to an explicit Amap identity', () => {
    const restaurant = decodeRestaurantJSONContract(legacyFixture)

    expect(restaurant.schemaVersion).toBe(1)
    expect(restaurant.amapPoiId).toBe('B0LEGACYPOI')
    expect(restaurant.placeIdentities).toEqual([{
      provider: 'amap',
      externalId: 'B0LEGACYPOI',
      isPrimary: true,
      createdAt: legacyFixture.createdAt,
      updatedAt: legacyFixture.updatedAt,
    }])
  })

  it('encodes the existing Web model through the same contract adapter', () => {
    const contract = restaurantToJSONContract(makeRestaurant())

    expect(contract.schemaVersion).toBe(1)
    expect(contract.amapPoiId).toBe('B0WEBPOI')
    expect(contract.placeIdentities[0]).toMatchObject({ provider: 'amap', externalId: 'B0WEBPOI' })
    expect(contract).not.toHaveProperty('markerImageData')
  })

  it('distinguishes required nullable fields from optional compatibility fields', () => {
    const missingRequiredNullable = { ...validFixture } as Record<string, unknown>
    delete missingRequiredNullable.phone
    expect(() => decodeRestaurantJSONContract(missingRequiredNullable)).toThrow(/phone is required/)

    expect(() => decodeRestaurantJSONContract({ ...validFixture, phone: null })).not.toThrow()
    expect(() => decodeRestaurantJSONContract({ ...validFixture, amapPoiId: null })).toThrow(/amapPoiId/)
  })

  it('keeps required, optional, nullable semantics documented in JSON Schema', () => {
    expect(schema.required).toContain('phone')
    expect(schema.required).toContain('deletedAt')
    expect(schema.required).not.toContain('amapPoiId')
    expect(schema.properties.phone.type).toEqual(['string', 'null'])
    expect(schema.properties.websiteUrl.type).toEqual(['string', 'null'])
    expect(schema.required).not.toContain('websiteUrl')
    expect(schema.properties.amapPoiId.type).toBe('string')
    expect(schema.properties.id.description).toContain('never a provider POI ID')
  })
})

function makeRestaurant(): Restaurant {
  return {
    id: 'rest_web_owned_id', userId: 'owner', amapPoiId: 'B0WEBPOI',
    name: 'Web 合同餐厅', address: '', city: '杭州', latitude: 30, longitude: 120,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null,
    environmentRating: null, serviceRating: null, valueRating: null, tags: [],
    longTermNote: '', pricePerPerson: null, phone: null, openingHours: null,
    markerType: 'emoji', markerImageData: null, markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: '🍽️', createdAt: '2026-08-27T05:00:00.000Z',
    updatedAt: '2026-08-27T05:00:00.000Z', deletedAt: null,
  }
}
