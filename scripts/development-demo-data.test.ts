import { describe, expect, it } from 'vitest'
import { decodeRestaurantJSONContract } from '../src/contracts/restaurantContract'
import {
  decodeSyncPushRequest,
  decodeVisitSyncContract,
} from '../src/contracts/syncV1'
import {
  decodeDishJSONContract,
  decodeVisitDishJSONContract,
} from '../src/contracts/dishPhotoContract'
import {
  decodeDiningCompanionSyncContract,
  decodeRecommendationSourceSyncContract,
} from '../src/contracts/companionSourceContract'
import { decodeOwnProfileSyncContract } from '../src/contracts/profileContract'
import {
  decodeRestaurantListItemSyncContract,
  decodeRestaurantListSyncContract,
} from '../src/contracts/restaurantListContract'
import {
  buildDevelopmentDemoDataset,
  DEVELOPMENT_DEMO_ADMIN_USER_ID,
  DEVELOPMENT_DEMO_NAMESPACE,
  DEVELOPMENT_DEMO_PLACE_PREFIX,
  DEVELOPMENT_DEMO_USER_PREFIX,
  entityMutation,
  normalizedReferenceNow,
} from './development-demo-data.mjs'

const CURRENT_USER = 'tm_development_current_user'
const REFERENCE = '2026-08-29T01:23:45.000Z'

describe('Development Demo Seed Data v2', () => {
  it('builds the required 50-user tier, entity and relationship scale', () => {
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    expect(dataset.namespace).toBe(DEVELOPMENT_DEMO_NAMESPACE)
    expect(dataset.adminUserID).toBe(DEVELOPMENT_DEMO_ADMIN_USER_ID)
    expect(dataset.demoUsers).toHaveLength(50)
    expect(dataset.demoUsers.map((user) => user.ownerID)).toEqual(
      Array.from({ length: 50 }, (_, index) => `${DEVELOPMENT_DEMO_USER_PREFIX}${String(index + 1).padStart(2, '0')}`),
    )
    expect(dataset.summary.tiers).toEqual({ heavy: 8, normal: 22, light: 12, sparse: 8 })
    expect(dataset.summary.restaurantUniverseCount).toBeGreaterThanOrEqual(300)
    expect(dataset.summary.restaurantUniverseCount).toBeLessThanOrEqual(400)
    expect(dataset.summary.currentUser).toMatchObject({
      restaurantCount: 90, visitCount: 275, wantToGoCount: 28,
      recommendationSourceCount: 11, companionCount: 9,
    })
    expect(dataset.summary.demo.visitCount).toBeGreaterThanOrEqual(4_500)
    expect(dataset.summary.demo.visitCount).toBeLessThanOrEqual(7_000)
    expect(dataset.summary.demo.wantToGoCount).toBeGreaterThanOrEqual(800)
    expect(dataset.summary.demo.wantToGoCount).toBeLessThanOrEqual(1_200)
    expect(dataset.summary.demo.dishCount).toBeGreaterThanOrEqual(1_000)
    expect(dataset.summary.demo.dishCount).toBeLessThanOrEqual(1_800)
    expect(dataset.summary.demo.listCount).toBeGreaterThanOrEqual(70)
    expect(dataset.summary.demo.listCount).toBeLessThanOrEqual(120)
    expect(dataset.summary.demo.relationshipCount).toBeGreaterThanOrEqual(150)
    expect(dataset.summary.demo.relationshipCount).toBeLessThanOrEqual(250)

    for (const user of dataset.demoUsers) {
      const expected = user.tier === 'heavy'
        ? { restaurants: [70, 100], visits: [140, 200], wants: [20, 40] }
        : user.tier === 'normal'
          ? { restaurants: [45, 75], visits: [80, 130], wants: [15, 30] }
          : user.tier === 'light'
            ? { restaurants: [20, 45], visits: [30, 70], wants: [15, 30] }
            : { restaurants: [3, 20], visits: [3, 25], wants: [3, 20] }
      expect(user.visitedPlaceIDs.length).toBeGreaterThanOrEqual(expected.restaurants[0])
      expect(user.visitedPlaceIDs.length).toBeLessThanOrEqual(expected.restaurants[1])
      expect(user.visits.length).toBeGreaterThanOrEqual(expected.visits[0])
      expect(user.visits.length).toBeLessThanOrEqual(expected.visits[1])
      expect(user.wantedPlaceIDs.length).toBeGreaterThanOrEqual(expected.wants[0])
      expect(user.wantedPlaceIDs.length).toBeLessThanOrEqual(expected.wants[1])
    }
  })

  it('uses a synthetic shared Restaurant universe with the requested city distribution', () => {
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    expect(dataset.places.every((place) =>
      place.id.startsWith(DEVELOPMENT_DEMO_PLACE_PREFIX) &&
      place.name.includes('虚构') && place.address.includes('虚构'))).toBe(true)
    expect(dataset.places.every((place) => !place.name.includes('外婆家') && !place.name.includes('王品'))).toBe(true)
    expect(dataset.places.every((place) => place.phone === undefined && place.merchantImageUrl === undefined)).toBe(true)
    const cities = Object.groupBy(dataset.places, (place) => place.city)
    expect(cities['杭州']).toHaveLength(207)
    expect(cities['上海']).toHaveLength(36)
    expect(cities['北京']).toHaveLength(18)
    expect(cities['成都']).toHaveLength(18)
    expect(cities['广州']).toHaveLength(18)
    expect(cities['东京']).toHaveLength(18)
    expect(cities['大阪']).toHaveLength(18)
    expect(dataset.places.filter((place) => place.popularity === 'high')).toHaveLength(40)
    expect(dataset.places.filter((place) => place.popularity === 'medium')).toHaveLength(130)
    expect(dataset.places.filter((place) => place.popularity === 'niche')).toHaveLength(190)

    const sharedOwners = new Map<string, Set<string>>()
    dataset.demoUsers.forEach((user) => user.restaurants.forEach((restaurant) => {
      const externalID = restaurant.placeIdentities[0].externalId
      sharedOwners.set(externalID, new Set([...(sharedOwners.get(externalID) ?? []), user.ownerID]))
    }))
    expect([...sharedOwners.values()].filter((owners) => owners.size >= 20).length).toBeGreaterThanOrEqual(35)
    expect([...sharedOwners.values()].some((owners) => owners.size <= 5)).toBe(true)
  })

  it('creates a strong-to-insufficient overlap gradient without writing similarity results', () => {
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    const averages = Object.fromEntries(Object.entries(dataset.summary.overlapInputs).map(([group, rows]) => [
      group,
      rows.reduce((sum, row) => sum + row.sharedRestaurantCount, 0) / rows.length,
    ]))
    expect(averages.S).toBeGreaterThan(averages.A)
    expect(averages.A).toBeGreaterThan(averages.B)
    expect(averages.B).toBeGreaterThan(averages.C)
    expect(averages.C).toBeGreaterThan(averages.D)
    expect(averages.D).toBeGreaterThan(averages.E)
    expect(dataset.summary.overlapInputs.S[0].sharedRestaurantCount)
      .toBeGreaterThan(dataset.summary.overlapInputs.S[2].sharedRestaurantCount)
    expect(dataset.summary.overlapInputs.S[1].sharedRestaurantCount)
      .toBeGreaterThan(dataset.summary.overlapInputs.S[2].sharedRestaurantCount)
    const serialized = JSON.stringify(dataset)
    for (const forbidden of [
      'similarityPercent', 'similarityScore', 'trendingScore', 'discoveryRank',
      'forYouReason', 'fitLabel', 'cautionLabel',
    ]) expect(serialized).not.toContain(forbidden)
  })

  it('creates distinct 7-day, 30-day and historical activity from raw Visit dates', () => {
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    expect(dataset.summary.demo.activeRestaurant7DayCount).toBeGreaterThanOrEqual(35)
    expect(dataset.summary.demo.activeRestaurant7DayCount).toBeLessThan(dataset.summary.demo.activeRestaurant30DayCount)
    expect(dataset.summary.demo.activeRestaurant30DayCount).toBeGreaterThanOrEqual(55)
    const placeByID = new Map(dataset.places.map((place) => [place.id, place]))
    const restaurantPlace = new Map(dataset.demoUsers.flatMap((user) =>
      user.restaurants.map((restaurant) => [restaurant.id, restaurant.placeIdentities[0].externalId])))
    const historical = dataset.demoUsers.flatMap((user) => user.visits).filter((visit) =>
      placeByID.get(restaurantPlace.get(visit.restaurantId))?.trendCohort === 'historical')
    expect(historical.length).toBeGreaterThan(0)
    expect(historical.every((visit) =>
      new Date(dataset.referenceNow).getTime() - new Date(visit.visitedAt).getTime() > 30 * 86_400_000)).toBe(true)
  })

  it('preserves rating, spend and visibility personas instead of one random distribution', () => {
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    const usersByPersona = Object.groupBy(dataset.demoUsers, (user) => user.ratingPersona)
    const average = (users) => {
      const ratings = users.flatMap((user) => user.visits.map((visit) => visit.rating)).filter((value) => value !== null)
      return ratings.reduce((sum, value) => sum + value, 0) / ratings.length
    }
    expect(usersByPersona.generous).toHaveLength(10)
    expect(usersByPersona.balanced).toHaveLength(20)
    expect(usersByPersona.strict).toHaveLength(12)
    expect(usersByPersona.sparse).toHaveLength(8)
    expect(average(usersByPersona.generous)).toBeGreaterThan(average(usersByPersona.balanced))
    expect(average(usersByPersona.balanced)).toBeGreaterThan(average(usersByPersona.strict))
    const sparseVisits = usersByPersona.sparse.flatMap((user) => user.visits)
    expect(sparseVisits.filter((visit) => visit.rating === null).length / sparseVisits.length).toBeGreaterThan(0.6)

    const visibility = dataset.summary.demo.visibility
    expect(visibility.public / dataset.summary.demo.visitCount).toBeGreaterThan(0.5)
    expect(visibility.public / dataset.summary.demo.visitCount).toBeLessThan(0.6)
    expect(visibility.friends / dataset.summary.demo.visitCount).toBeGreaterThan(0.2)
    expect(visibility.private / dataset.summary.demo.visitCount).toBeGreaterThan(0.15)

    for (const user of dataset.demoUsers) for (const visit of user.visits) {
      const restaurant = user.restaurants.find((item) => item.id === visit.restaurantId)
      if (restaurant?.tags.includes('面馆') || restaurant?.tags.includes('小吃')) {
        expect(visit.myActualSpend).toBeLessThanOrEqual(120)
        expect(visit.totalPrice).toBeLessThanOrEqual(600)
      }
    }
  })

  it('is byte-deterministic on the same day and moves only relative time windows across days', () => {
    const first = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: '2026-08-29T00:01:00Z' })
    const second = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: '2026-08-29T23:59:00Z' })
    expect(JSON.stringify(second)).toBe(JSON.stringify(first))
    const nextDay = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: '2026-08-30T00:01:00Z' })
    expect(nextDay.referenceDay).toBe('2026-08-30')
    expect(nextDay.demoUsers.map((user) => user.visitedPlaceIDs))
      .toEqual(first.demoUsers.map((user) => user.visitedPlaceIDs))
    expect(new Date(nextDay.demoUsers[0].visits[0].visitedAt).getTime() -
      new Date(first.demoUsers[0].visits[0].visitedAt).getTime()).toBe(86_400_000)
    expect(normalizedReferenceNow('2026-08-29T23:59:59Z').toISOString()).toBe('2026-08-29T12:00:00.000Z')
  })

  it('produces unique manifest IDs and payloads accepted by every existing Sync V1 decoder', () => {
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    const entityKeys = new Set()
    for (const account of dataset.accounts) {
      for (const record of account.records) {
        const key = `${record.entityType}:${record.entityID}`
        expect(entityKeys.has(key), key).toBe(false)
        entityKeys.add(key)
        switch (record.entityType) {
          case 'restaurant': decodeRestaurantJSONContract(record.payload); break
          case 'visit': decodeVisitSyncContract(record.payload); break
          case 'dish': decodeDishJSONContract(record.payload); break
          case 'visitDish': decodeVisitDishJSONContract(record.payload); break
          case 'companion': decodeDiningCompanionSyncContract(record.payload); break
          case 'recommendationSource': decodeRecommendationSourceSyncContract(record.payload); break
          case 'profile': decodeOwnProfileSyncContract(record.payload); break
          case 'restaurantList': decodeRestaurantListSyncContract(record.payload); break
          case 'restaurantListItem': decodeRestaurantListItemSyncContract(record.payload); break
          default: throw new Error(`Unexpected entity type: ${record.entityType}`)
        }
      }
      for (let index = 0; index < account.records.length; index += 100) {
        decodeSyncPushRequest({
          apiVersion: 1,
          schemaVersion: 1,
          mutations: account.records.slice(index, index + 100).map((record) =>
            entityMutation(record, dataset.referenceDay)),
        })
      }
    }
  })

  it('fails closed for missing, malformed, admin or demo current-user identities', () => {
    for (const currentUserID of [undefined, '', 'has spaces', DEVELOPMENT_DEMO_ADMIN_USER_ID,
      `${DEVELOPMENT_DEMO_USER_PREFIX}01`]) {
      expect(() => buildDevelopmentDemoDataset({ currentUserID, referenceNow: REFERENCE })).toThrow()
    }
  })
})
