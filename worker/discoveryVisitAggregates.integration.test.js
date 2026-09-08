import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import { applyAllMigrations } from './testSupport/migrations.js'
import { calculateTasteSimilarities } from './tasteSimilarity'
import {
  DISCOVERY_AGGREGATE_CAPACITY,
  readDiscoveryVisitAggregates,
  ratingFromDiscoveryAggregates,
  tasteSignalsFromDiscoveryAggregates,
  trendFromDiscoveryAggregates,
} from './discoveryVisitAggregates'

const now = Date.now()
const date = (days = 0) => new Date(now - days * 86_400_000).toISOString()
let sqlite
let database
let raw
let identities

beforeEach(() => {
  sqlite = new DatabaseSync(':memory:')
  applyAllMigrations(sqlite)
  raw = []
  identities = new Map()
  database = {
    prepare(sql) {
      return {
        bind(...values) {
          return { all: async () => ({ results: sqlite.prepare(sql).all(...values) }) }
        },
      }
    },
  }
  for (const id of ['viewer', 'bob', 'carol']) {
    sql('INSERT INTO users (id,nickname,created_at,updated_at) VALUES (?,?,?,?)', id, id, date(90), date())
    sql("INSERT INTO user_profiles (user_id,display_name,city,visibility,created_at,updated_at) VALUES (?,?,'杭州','public',?,?)", id, id, date(90), date())
  }
  sql("INSERT INTO friendships (id,requester_id,addressee_id,status,created_at,updated_at,pair_user_a,pair_user_b,server_version) VALUES ('friend','viewer','bob','accepted',?,?,'bob','viewer',1)", date(), date())
})

describe('bounded Discovery aggregate reader used by the shipping endpoint', () => {
  it('preserves raw small-sample ratings, real source Visits and 7/30-day counts across aliases/visibilities', async () => {
    restaurant('bob-a', 'bob', 'place')
    restaurant('bob-alias', 'bob', 'place')
    restaurant('carol-a', 'carol', 'place')
    visit('bob-a', 'b-high', 5, 10)
    visit('bob-a', 'b-latest-rated', 1, 2)
    visit('bob-a', 'b-latest-unrated', null, 1)
    visit('bob-a', 'b-friend', 4, 2, 'friends')
    visit('bob-alias', 'b-alias-1', 3.5, 3)
    visit('bob-alias', 'b-alias-2', 3.5, 4)
    visit('carol-a', 'c-recent', 4.5, 1)
    visit('carol-a', 'c-old', 5, 40)
    const aggregates = await read()
    expect(aggregates).toHaveLength(4)
    const publicRows = aggregates.filter(row => row.visibility === 'public')
    const oldPublic = raw.filter(row => row.visibility === 'public')
    expect(ratingFromDiscoveryAggregates(publicRows)).toEqual(rawRating(oldPublic))
    expect(ratingFromDiscoveryAggregates(aggregates)).toEqual(rawRating(raw))
    const main = publicRows.find(row => row.restaurantID === 'bob-a')
    expect(main).toMatchObject({ visitCount: 3, ratingCount: 2, ratingSum: 6,
      qualifiedRatingCount: 1, qualifiedRatingSum: 5,
      latestVisit: { id: 'b-latest-unrated', rating: null, visitedAt: date(1) },
      latestQualifiedVisit: { id: 'b-high', rating: 5, visitedAt: date(10) } })
    for (const days of [7, 30]) {
      const recent = oldPublic.filter(row => now - Date.parse(row.visitedAt) <= days * 86_400_000)
      expect(trendFromDiscoveryAggregates(aggregates, now, days)).toEqual({
        uniqueVisitorCount: new Set(recent.map(row => row.userID)).size,
        highRatingUserCount: new Set(recent.filter(row => row.rating >= 3.75).map(row => row.userID)).size,
      })
    }
  })

  it('preserves five-restaurant relative Pearson evidence including duplicate-provider Visit weights', async () => {
    for (const user of ['viewer', 'bob', 'carol']) {
      for (let place = 0; place < 5; place++) {
        for (let alias = 0; alias < 2; alias++) {
          const restaurantID = `${user}-${place}-${alias}`
          restaurant(restaurantID, user, `place-${place}`)
          for (let repeat = 0; repeat <= place + alias; repeat++) {
            visit(restaurantID, `${restaurantID}-${repeat}`,
              user === 'carol' ? place + 1 : 5 - place / 2 - alias / 4, 1 + repeat,
              user === 'bob' && alias ? 'friends' : 'public')
          }
        }
      }
    }
    const placeForRestaurant = id => ({ key: identities.get(id).place, tags: ['日料', identities.get(id).place] })
    const rawSignals = raw.map(row => ({ userId: row.userID,
      poiId: placeForRestaurant(row.restaurantID).key,
      tags: placeForRestaurant(row.restaurantID).tags, ratingOutOfTen: row.rating * 2 }))
    const aggregateSignals = tasteSignalsFromDiscoveryAggregates(await read(), placeForRestaurant)
    expect(aggregateSignals.length).toBeLessThan(rawSignals.length)
    const expected = calculateTasteSimilarities(rawSignals, 'viewer')
    const actual = calculateTasteSimilarities(aggregateSignals, 'viewer')
    expect(actual).toHaveLength(2)
    expect(actual.map(row => row.userId)).toEqual(expected.map(row => row.userId))
    for (const row of actual) {
      const original = expected.find(value => value.userId === row.userId)
      expect(row.sharedRestaurantCount).toBe(original.sharedRestaurantCount)
      expect(row.signalCount).toBe(original.signalCount)
      expect(row.similarity).toBeCloseTo(original.similarity, 12)
      expect(row.weightedSimilarity).toBeCloseTo(original.weightedSimilarity, 12)
      expect(row.userMeanOutOfTen).toBeCloseTo(original.userMeanOutOfTen, 12)
    }
  })

  it('retains the full 902-row noise fixture with only three aggregate rows', async () => {
    restaurant('noise', 'bob', 'noise')
    restaurant('popular-viewer', 'viewer', 'popular')
    restaurant('popular-carol', 'carol', 'popular')
    for (let index = 0; index < 900; index++) visit('noise', `noise-${index}`, 5, 1)
    visit('popular-viewer', 'popular-a', 5, 5)
    visit('popular-carol', 'popular-c', 5, 5)
    const aggregates = await read()
    expect(aggregates).toHaveLength(3)
    expect(aggregates.reduce((sum, row) => sum + row.visitCount, 0)).toBe(902)
    const popular = aggregates.filter(row => identities.get(row.restaurantID).place === 'popular')
    expect(trendFromDiscoveryAggregates(popular, now, 7).uniqueVisitorCount).toBe(2)
    expect(trendFromDiscoveryAggregates(aggregates.filter(row => row.restaurantID === 'noise'), now, 7).uniqueVisitorCount).toBe(1)
  })

  it('rejects an incomplete aggregate prefix with a structured capacity error', async () => {
    for (let index = 0; index < DISCOVERY_AGGREGATE_CAPACITY; index++) {
      restaurant(`place-${index}`, 'bob', `place-${index}`)
      visit(`place-${index}`, `visit-${index}`, 5, 1)
    }
    expect(await read()).toHaveLength(DISCOVERY_AGGREGATE_CAPACITY)
    restaurant('overflow-place', 'bob', 'overflow-place')
    visit('overflow-place', 'overflow-visit', 5, 1)
    await expect(read()).rejects.toMatchObject({
      name: 'DiscoveryAggregateCapacityError', status: 503, code: 'DISCOVERY_AGGREGATE_CAPACITY',
    })
  })

  it('applies authorization, both block directions, provider cities and dates before aggregation', async () => {
    restaurant('canonical', 'bob', 'canonical')
    restaurant('suffix', 'carol', 'suffix', '杭州市')
    restaurant('own-private', 'viewer', 'own-private', '北京')
    visit('canonical', 'private', 5, 1, 'private')
    visit('canonical', 'friend', 5, 1, 'friends')
    visit('canonical', 'future', 5, -2)
    visit('canonical', 'invalid-date', 5, 2)
    sql("UPDATE visits SET visited_at='invalid' WHERE id='invalid-date'")
    visit('suffix', 'suffix-visit', 5, 1)
    visit('own-private', 'own-visit', 5, 1, 'private')
    expect((await read()).map(row => row.latestVisit.id).sort()).toEqual(['friend', 'own-visit', 'suffix-visit'])
    sql("INSERT INTO user_blocks (id,blocker_user_id,blocked_user_id,created_at,updated_at) VALUES ('forward','viewer','bob',?,?),('reverse','carol','viewer',?,?)", date(), date(), date(), date())
    expect((await read()).map(row => row.latestVisit.id)).toEqual(['own-visit'])
  })
})

function read() { return readDiscoveryVisitAggregates(database, { viewerID: 'viewer', city: '杭州市', now }) }
function sql(statement, ...values) { return sqlite.prepare(statement).run(...values) }
function restaurant(id, userID, place, city = '杭州') {
  identities.set(id, { userID, place })
  sql("INSERT INTO restaurants (id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,created_at,updated_at) VALUES (?,?,'',?,'路1号',?,30,120,'visited','normal',?,?)", id, userID, place, city, date(90), date())
  sql("INSERT INTO restaurant_place_identities (restaurant_id,user_id,provider,external_id,is_primary,created_at,updated_at) VALUES (?,?,'apple_maps',?,1,?,?)", id, userID, place, date(90), date())
}
function visit(restaurantID, id, rating, days, visibility = 'public') {
  const userID = identities.get(restaurantID).userID
  const visitedAt = date(days)
  sql('INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,visibility,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)', id, userID, restaurantID, visitedAt, rating, visibility, visitedAt, visitedAt)
  raw.push({ id, userID, restaurantID, visitedAt, rating, visibility })
}
function rawRating(rows) {
  const users = new Map()
  for (const row of rows) if (row.rating !== null) users.set(row.userID, [...(users.get(row.userID) ?? []), row.rating])
  const means = [...users.values()].map(ratings => ratings.reduce((sum, value) => sum + value, 0) / ratings.length)
  return { value: means.length ? Math.round(means.reduce((sum, value) => sum + value, 0) / means.length * 100) / 100 : null,
    sampleCount: means.length }
}
