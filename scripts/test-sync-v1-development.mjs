import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (!baseURL) throw new Error('TASTEMAP_API_DEV_BASE_URL is required.')

const testRun = randomUUID()
const userID = `p0b2a:${testRun}`
const restaurantID = `restaurant-${testRun}`
const visitID = `visit-${testRun}`
const timestamp = new Date().toISOString()
const headers = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
  'X-Taste-Map-Test-User': userID,
}

const restaurant = {
  schemaVersion: 1,
  id: restaurantID,
  userId: 'forged-client-user',
  name: 'P0-B2-A Apple Maps Test Restaurant',
  address: 'Development D1 only',
  city: 'Development',
  latitude: 37.3349,
  longitude: -122.009,
  status: 'visited',
  preferenceLevel: 'normal',
  overallRating: null,
  foodRating: null,
  environmentRating: null,
  serviceRating: null,
  valueRating: null,
  tags: [],
  longTermNote: '',
  pricePerPerson: null,
  phone: null,
  openingHours: null,
  markerType: 'emoji',
  markerPhotoId: null,
  merchantImageUrl: null,
  markerEmoji: '🍽️',
  placeIdentities: [{
    provider: 'apple_maps',
    externalId: `apple-maps-${testRun}`,
    isPrimary: true,
    createdAt: timestamp,
    updatedAt: timestamp,
  }],
  createdAt: timestamp,
  updatedAt: timestamp,
  deletedAt: null,
}

const visit = {
  schemaVersion: 1,
  id: visitID,
  userId: 'forged-client-user',
  restaurantId: restaurantID,
  visitedAt: timestamp,
  rating: null,
  note: 'P0-B2-A real Development D1 test',
  myActualSpend: null,
  createdAt: timestamp,
  updatedAt: timestamp,
  deletedAt: null,
}

const restaurantMutation = mutation('restaurant-create', 'restaurant', restaurantID, 0, restaurant)
const restaurantAck = await push(restaurantMutation)
assert(restaurantAck.status === 'applied' && restaurantAck.serverVersion === 1, 'Restaurant create failed')

const duplicateAck = await push(restaurantMutation)
assert(duplicateAck.duplicate === true && duplicateAck.serverVersion === 1, 'Mutation was not idempotent')

const visitAck = await push(mutation('visit-create', 'visit', visitID, 0, visit))
assert(visitAck.status === 'applied' && visitAck.serverVersion === 1, 'Visit create failed')

const initial = await pull('0')
const pulledRestaurant = initial.restaurants.find((item) => item.record.id === restaurantID)
const pulledVisit = initial.visits.find((item) => item.record.id === visitID)
assert(pulledRestaurant?.record.placeIdentities[0]?.provider === 'apple_maps', 'Apple Maps identity was not preserved')
assert(!Object.hasOwn(pulledRestaurant.record, 'amapPoiId'), 'Apple Maps-only Restaurant unexpectedly contains amapPoiId')
assert(pulledRestaurant.record.userId === userID, 'Server did not override the forged Restaurant userId')
assert(pulledVisit?.record.restaurantId === restaurantID, 'Visit relationship was not preserved')
assert(pulledVisit.record.userId === userID, 'Server did not override the forged Visit userId')

const incrementalEmpty = await pull(initial.nextCursor)
assert(incrementalEmpty.restaurants.length === 0 && incrementalEmpty.visits.length === 0 && incrementalEmpty.tombstones.length === 0,
  'Incremental pull returned unchanged records')

const visitDelete = await push(deletion('visit-delete', 'visit', visitID, visitAck.serverVersion))
assert(visitDelete.status === 'applied', 'Visit tombstone failed')
const restaurantDelete = await push(deletion('restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion))
assert(restaurantDelete.status === 'applied', 'Restaurant tombstone failed')

const deleted = await pull(initial.nextCursor)
assert(deleted.tombstones.some((item) => item.entityType === 'visit' && item.entityId === visitID), 'Visit tombstone missing')
assert(deleted.tombstones.some((item) => item.entityType === 'restaurant' && item.entityId === restaurantID), 'Restaurant tombstone missing')

const stalePayload = { ...restaurant, name: 'Stale resurrection attempt', updatedAt: new Date().toISOString() }
const staleAck = await push(mutation('restaurant-stale-resurrection', 'restaurant', restaurantID, 1, stalePayload))
assert(staleAck.status === 'conflict', 'Stale update resurrected a tombstoned Restaurant')

const otherUser = await request('/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200', {
  headers: { ...headers, 'X-Taste-Map-Test-User': `${userID}:other` },
})
assert(!otherUser.restaurants.some((item) => item.record.id === restaurantID), 'Another user read the test Restaurant')
assert(!otherUser.visits.some((item) => item.record.id === visitID), 'Another user read the test Visit')

console.log(JSON.stringify({
  result: 'P0-B2-A Development Worker/D1 sync passed',
  baseURL,
  userID,
  restaurantID,
  visitID,
  initialCursor: initial.nextCursor,
  finalCursor: deleted.nextCursor,
}, null, 2))

function mutation(suffix, entityType, entityId, baseVersion, payload) {
  return {
    mutationId: `${testRun}:${suffix}`,
    entityType,
    entityId,
    operation: 'upsert',
    baseVersion,
    clientTimestamp: payload.updatedAt,
    payload,
  }
}

function deletion(suffix, entityType, entityId, baseVersion) {
  return {
    mutationId: `${testRun}:${suffix}`,
    entityType,
    entityId,
    operation: 'delete',
    baseVersion,
    clientTimestamp: new Date().toISOString(),
  }
}

async function push(item) {
  const body = await request('/api/v1/sync/push', {
    method: 'POST',
    headers,
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations: [item] }),
  })
  return body.acknowledgements[0]
}

function pull(cursor) {
  return request(`/api/v1/sync/pull?schemaVersion=1&cursor=${encodeURIComponent(cursor)}&limit=200`, { headers })
}

async function request(path, options) {
  const response = await fetch(`${baseURL}${path}`, options)
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}
