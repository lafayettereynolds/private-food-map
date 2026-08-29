import Ajv2020 from 'ajv/dist/2020'
import { describe, expect, it } from 'vitest'
import schema from '../../contracts/backup/backup.v1.schema.json'
import companionFixture from '../../contracts/backup/fixtures/backup.v1.companion.json'
import dishVisitDishFixture from '../../contracts/backup/fixtures/backup.v1.dish-visit-dish.json'
import fullFixture from '../../contracts/backup/fixtures/backup.v1.full.valid.json'
import listFixture from '../../contracts/backup/fixtures/backup.v1.list.ordered-items.json'
import minimalFixture from '../../contracts/backup/fixtures/backup.v1.minimal.valid.json'
import photoFixture from '../../contracts/backup/fixtures/backup.v1.photo.metadata-only.json'
import profileFixture from '../../contracts/backup/fixtures/backup.v1.profile.sanitized.json'
import amapRestaurantFixture from '../../contracts/backup/fixtures/backup.v1.restaurant.amap.json'
import appleRestaurantFixture from '../../contracts/backup/fixtures/backup.v1.restaurant.apple-maps.json'
import manualRestaurantFixture from '../../contracts/backup/fixtures/backup.v1.restaurant.manual.json'
import providerNeutralRestaurantFixture from '../../contracts/backup/fixtures/backup.v1.restaurant.provider-neutral.json'
import recommendationSourceFixture from '../../contracts/backup/fixtures/backup.v1.recommendation-source.json'
import tombstoneFixture from '../../contracts/backup/fixtures/backup.v1.tombstone.json'
import nilHeavyVisitFixture from '../../contracts/backup/fixtures/backup.v1.visit.nil-heavy.json'
import legacyWebV4Fixture from '../../contracts/backup/fixtures/legacy.web.v4.json'
import forbiddenFieldFixtures from '../../contracts/backup/fixtures/security.forbidden-fields.json'
import {
  backupIntegrityPayloadV1,
  canonicalizeBackupJSONV1,
  sha256HexV1,
  type BackupEnvelopeV1,
} from './backupV1'
import type { LegacyWebBackupV4 } from './legacyWebBackupV4'

const ajv = new Ajv2020({ allErrors: true, strict: true, multipleOfPrecision: 12 })
ajv.addSchema(schema)
const validateEnvelope = ajv.getSchema<BackupEnvelopeV1>(schema.$id)

function validateDefinition(name: string, value: unknown) {
  const validate = ajv.compile({ $ref: `${schema.$id}#/$defs/${name}` })
  const valid = validate(value)
  if (!valid) throw new Error(ajv.errorsText(validate.errors, { separator: '\n' }))
}

describe('Taste Map Backup v1 contract', () => {
  it('validates full and minimal golden envelopes against the strict JSON Schema', () => {
    expect(validateEnvelope).toBeDefined()
    expect(validateEnvelope?.(fullFixture)).toBe(true)
    expect(validateEnvelope?.errors).toBeNull()
    expect(validateEnvelope?.(minimalFixture)).toBe(true)
    expect(validateEnvelope?.errors).toBeNull()
  })

  it('validates every entity golden fixture against the same schema definitions', () => {
    validateDefinition('visit', nilHeavyVisitFixture)
    validateDefinition('restaurant', providerNeutralRestaurantFixture)
    validateDefinition('restaurant', appleRestaurantFixture)
    validateDefinition('restaurant', amapRestaurantFixture)
    validateDefinition('restaurant', manualRestaurantFixture)
    validateDefinition('tombstone', tombstoneFixture)
    validateDefinition('dish', dishVisitDishFixture.dish)
    validateDefinition('visitDish', dishVisitDishFixture.visitDish)
    validateDefinition('photo', photoFixture)
    validateDefinition('companion', companionFixture)
    validateDefinition('recommendationSource', recommendationSourceFixture)
    validateDefinition('profile', profileFixture)
    validateDefinition('restaurantList', listFixture.list)
    listFixture.items.forEach((item) => validateDefinition('restaurantListItem', item))
  })

  it('keeps Legacy Web v4 in a separate lineage', () => {
    const legacy = legacyWebV4Fixture as LegacyWebBackupV4
    expect(legacy.app).toBe('Taste Map')
    expect(legacy.version).toBe(4)
    expect(legacy).not.toHaveProperty('format')
    expect(validateEnvelope?.(legacy)).toBe(false)
  })

  it('preserves explicit null instead of applying implicit defaults', () => {
    validateDefinition('visit', nilHeavyVisitFixture)
    expect(nilHeavyVisitFixture.rating).toBeNull()
    expect(nilHeavyVisitFixture.myActualSpend).toBeNull()

    const missingRating = structuredClone(nilHeavyVisitFixture) as Record<string, unknown>
    delete missingRating.rating
    const validateVisit = ajv.compile({ $ref: `${schema.$id}#/$defs/visit` })
    expect(validateVisit(missingRating)).toBe(false)
  })

  it('locks money to two-place decimal strings and timestamps to UTC milliseconds', () => {
    expect(() => validateDefinition('visit', { ...nilHeavyVisitFixture, myActualSpend: '128.50' })).not.toThrow()
    expect(() => validateDefinition('visit', { ...nilHeavyVisitFixture, myActualSpend: 128.5 })).toThrow()
    expect(() => validateDefinition('visit', { ...nilHeavyVisitFixture, myActualSpend: '128.5' })).toThrow()
    expect(() => validateDefinition('visit', { ...nilHeavyVisitFixture, visitedAt: '2026-08-21T20:00:00+08:00' })).toThrow()
    expect(() => validateDefinition('visit', { ...nilHeavyVisitFixture, visitedAt: '2026-08-21T12:00:00Z' })).toThrow()
  })

  it('requires provider-neutral Restaurant IDs and exactly one primary identity', () => {
    expect(providerNeutralRestaurantFixture.id).not.toBe(providerNeutralRestaurantFixture.placeIdentities[0].externalId)
    expect(providerNeutralRestaurantFixture.placeIdentities.filter((identity) => identity.isPrimary)).toHaveLength(1)
    expect(providerNeutralRestaurantFixture).not.toHaveProperty('amapPoiId')
    expect(providerNeutralRestaurantFixture).not.toHaveProperty('appleMapItemIdentifier')

    const noPrimary = structuredClone(providerNeutralRestaurantFixture)
    noPrimary.placeIdentities.forEach((identity) => { identity.isPrimary = false })
    expect(() => validateDefinition('restaurant', noPrimary)).toThrow()
  })

  it('keeps Dish and VisitDish as separate Restaurant/Visit associations', () => {
    expect(dishVisitDishFixture.dish.restaurantId).toBe(dishVisitDishFixture.visitDish.restaurantId)
    expect(dishVisitDishFixture.visitDish.dishId).toBe(dishVisitDishFixture.dish.id)
    expect(nilHeavyVisitFixture).not.toHaveProperty('dishes')
  })

  it('keeps Photo v1 metadata-only with a typed parent', () => {
    expect(minimalFixture.scope.includesPhotoBinaries).toBe(false)
    expect(photoFixture.parent).toEqual({ entityType: 'visit', entityId: 'visit-fixture' })
    for (const forbidden of ['storageKey', 'providerAccountId', 'localPath', 'cachePath', 'uploadState', 'binary']) {
      expect(photoFixture).not.toHaveProperty(forbidden)
    }
  })

  it('keeps Profile and private directories sanitized', () => {
    for (const forbidden of ['userId', 'appleSub', 'authSubject', 'email', 'membershipTier', 'role']) {
      expect(profileFixture).not.toHaveProperty(forbidden)
    }
    expect(companionFixture).not.toHaveProperty('linkedTasteMapUserId')
    expect(recommendationSourceFixture).not.toHaveProperty('linkedTasteMapUserId')
  })

  it('rejects every denylist field through the schema instead of relying on review', () => {
    for (const fixture of forbiddenFieldFixtures) {
      const candidate = structuredClone(fullFixture) as Record<string, unknown>
      const entities = candidate.entities as Record<string, unknown[]>
      const target = fixture.target === 'root'
        ? candidate
        : fixture.target === 'profile'
          ? entities.profiles[0] as Record<string, unknown>
          : fixture.target === 'photo'
            ? entities.photos[0] as Record<string, unknown>
            : entities.restaurants[0] as Record<string, unknown>
      target[fixture.field] = fixture.value
      expect(validateEnvelope?.(candidate), fixture.name).toBe(false)
    }
  })

  it('has counts that exactly match the golden entity arrays', () => {
    const counts = fullFixture.metadata.entityCounts
    expect(counts.restaurants).toBe(fullFixture.entities.restaurants.length)
    expect(counts.visits).toBe(fullFixture.entities.visits.length)
    expect(counts.dishes).toBe(fullFixture.entities.dishes.length)
    expect(counts.visitDishes).toBe(fullFixture.entities.visitDishes.length)
    expect(counts.photos).toBe(fullFixture.entities.photos.length)
    expect(counts.companions).toBe(fullFixture.entities.companions.length)
    expect(counts.recommendationSources).toBe(fullFixture.entities.recommendationSources.length)
    expect(counts.profiles).toBe(fullFixture.entities.profiles.length)
    expect(counts.restaurantLists).toBe(fullFixture.entities.restaurantLists.length)
    expect(counts.restaurantListItems).toBe(fullFixture.entities.restaurantListItems.length)
    expect(fullFixture.metadata.tombstoneCount).toBe(fullFixture.tombstones.length)
  })

  it('canonicalizes object keys deterministically and verifies the shared SHA-256 digest', async () => {
    expect(canonicalizeBackupJSONV1({ z: 1, a: { y: 2, b: 3 } }))
      .toBe('{"a":{"b":3,"y":2},"z":1}')
    expect(canonicalizeBackupJSONV1([-0, 0.000001, 0.0000001, 1e20, 1e21]))
      .toBe('[0,0.000001,1e-7,100000000000000000000,1e+21]')
    const envelope = fullFixture as BackupEnvelopeV1
    const canonical = canonicalizeBackupJSONV1(backupIntegrityPayloadV1(envelope))
    expect(await sha256HexV1(canonical)).toBe(envelope.integrity.digest)
  })

  it('round-trips the shared JSON without changing Decimal, Date, null, or identities', () => {
    const roundTrip = JSON.parse(JSON.stringify(fullFixture)) as BackupEnvelopeV1
    expect(roundTrip).toEqual(fullFixture)
    expect(roundTrip.entities.visits[0].myActualSpend).toBe('328.50')
    expect(roundTrip.entities.visits[0].visitedAt).toBe('2026-08-18T11:45:00.000Z')
    expect(roundTrip.entities.restaurants[1].placeIdentities[0].provider).toBe('apple_maps')
  })
})
