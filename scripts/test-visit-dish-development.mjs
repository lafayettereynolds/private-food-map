import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (!baseURL) throw new Error('TASTEMAP_API_DEV_BASE_URL is required.')

const runID = randomUUID()
const userID = `p2c:${runID}`
const otherUserID = `${userID}:other`
const restaurantID = `restaurant-${runID}`
const firstVisitID = `visit-first-${runID}`
const secondVisitID = `visit-second-${runID}`
const dishID = `dish-${runID}`
const originAssociationID = `legacy:${dishID}:${firstVisitID}`
const secondAssociationID = `visit-dish-${runID}`
const createdAt = new Date().toISOString()
const headers = headersFor(userID)

const restaurant = {
  schemaVersion: 1, id: restaurantID, userId: 'forged-client-user',
  name: 'P2-C Development Dish Restaurant', address: 'Development D1 only', city: 'Development',
  latitude: 37.3349, longitude: -122.009, status: 'visited', preferenceLevel: 'normal',
  overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
  valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null,
  openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
  markerEmoji: '🍲', placeIdentities: [{
    provider: 'apple_maps', externalId: `apple-p2c-${runID}`, isPrimary: true,
    createdAt, updatedAt: createdAt,
  }], createdAt, updatedAt: createdAt, deletedAt: null,
}
const firstVisit = visit(firstVisitID, 'P2-C first Visit')
const secondVisit = visit(secondVisitID, 'P2-C second Visit')
const dish = {
  schemaVersion: 1, id: dishID, userId: 'forged-client-user', restaurantId: restaurantID,
  visitId: firstVisitID, name: '招牌牛肉', taste: '值得再点', rating: 4.5,
  price: 88, photoId: null, sortOrder: 0, createdAt, updatedAt: createdAt, deletedAt: null,
}
const originAssociation = association(originAssociationID, firstVisitID, 0)
const secondAssociation = association(secondAssociationID, secondVisitID, 0)

const restaurantAck = await push(mutation('restaurant-create', 'restaurant', restaurantID, 0, restaurant))
const firstVisitAck = await push(mutation('visit-first-create', 'visit', firstVisitID, 0, firstVisit))
const secondVisitAck = await push(mutation('visit-second-create', 'visit', secondVisitID, 0, secondVisit))
const dishCreate = mutation('dish-create', 'dish', dishID, 0, dish)
const dishAck = await push(dishCreate)
assert([restaurantAck, firstVisitAck, secondVisitAck, dishAck].every((ack) => ack.status === 'applied'),
  'Restaurant, Visit, or Dish parent creation failed')

const dishRetry = await push(dishCreate)
assert(dishRetry.duplicate === true && dishRetry.serverVersion === 1,
  'Retried Dish mutation was not idempotent')

// A Dish create writes this deterministic P2-A compatibility association. The
// iOS queue can still send the explicit relation and receives a semantic duplicate.
const originAck = await push(mutation(
  'origin-association-explicit', 'visitDish', originAssociationID, 0, originAssociation,
))
assert(originAck.status === 'applied' && originAck.duplicate === true && originAck.serverVersion === 1,
  'The deterministic P2-A origin association was not recognized')

const secondCreate = mutation(
  'second-association-create', 'visitDish', secondAssociationID, 0, secondAssociation,
)
const secondAssociationAck = await push(secondCreate)
const secondAssociationRetry = await push(secondCreate)
assert(secondAssociationAck.status === 'applied' && secondAssociationAck.serverVersion === 1,
  'Second Visit association creation failed')
assert(secondAssociationRetry.duplicate === true && secondAssociationRetry.serverVersion === 1,
  'Retried VisitDish mutation was not idempotent')

const initial = await pull(userID, '0')
assert(initial.dishes.filter((item) => item.record.id === dishID).length === 1,
  'Fresh client did not receive exactly one Restaurant Dish')
assert(initial.visitDishes.some((item) => item.record.id === originAssociationID),
  'Fresh client did not receive the origin Visit association')
assert(initial.visitDishes.some((item) => item.record.id === secondAssociationID),
  'Fresh client did not receive the reused Dish association')
assert(initial.dishes.find((item) => item.record.id === dishID)?.record.userId === userID,
  'Worker did not replace the Dish payload userId with authenticated identity')
assert(initial.visitDishes.filter((item) => item.record.dishId === dishID).length === 2,
  'One Restaurant Dish was not reused by both Visits')

const noChanges = await pull(userID, initial.nextCursor)
assert(noChanges.dishes.length === 0 && noChanges.visitDishes.length === 0 && noChanges.tombstones.length === 0,
  'Incremental cursor returned unchanged Dish data')

const editedAt = new Date(Date.now() + 1_000).toISOString()
const editedDish = { ...dish, taste: '第二台客户端更新：依然值得再点', rating: null, price: null, updatedAt: editedAt }
const editedAck = await push(mutation('dish-edit', 'dish', dishID, 1, editedDish))
assert(editedAck.status === 'applied' && editedAck.serverVersion === 2, 'Dish edit failed')
const clientBAfterEdit = await pull(userID, initial.nextCursor)
const clientBDish = clientBAfterEdit.dishes.find((item) => item.record.id === dishID)
assert(clientBDish?.serverVersion === 2 && clientBDish.record.taste === editedDish.taste,
  'Second client did not converge on the edited Dish')
assert(clientBDish.record.rating === null && clientBDish.record.price === null,
  'Nullable Dish rating/price did not round-trip')

const otherPull = await pull(otherUserID, '0')
assert(!otherPull.dishes.some((item) => item.record.id === dishID) &&
  !otherPull.visitDishes.some((item) => item.record.dishId === dishID),
  'Another user read the Dish or its Visit associations')
const takeover = await rawPush(otherUserID, mutation(
  'other-user-takeover', 'visitDish', secondAssociationID, 1,
  { ...secondAssociation, userId: otherUserID },
))
assert(takeover.response.status === 403, `Another user modified the association (${takeover.response.status})`)

const beforeRemoveCursor = clientBAfterEdit.nextCursor
const secondDeleteAck = await push(deletion(
  'second-association-delete', 'visitDish', secondAssociationID, secondAssociationAck.serverVersion,
))
assert(secondDeleteAck.status === 'applied' && secondDeleteAck.serverVersion === 2,
  'Removing the Dish from the second Visit failed')
const removed = await pull(userID, beforeRemoveCursor)
assert(removed.tombstones.some((item) => item.entityType === 'visitDish' &&
  item.entityId === secondAssociationID && item.serverVersion === 2),
  'Second client did not receive the VisitDish tombstone')
assert(!removed.tombstones.some((item) => item.entityType === 'dish' && item.entityId === dishID),
  'Removing a Visit association incorrectly deleted the Restaurant Dish')

const staleRevive = await push(mutation(
  'stale-association-revive', 'visitDish', secondAssociationID, 1,
  { ...secondAssociation, updatedAt: new Date(Date.now() + 2_000).toISOString() },
))
assert(staleRevive.status === 'conflict' && staleRevive.serverVersion === 2,
  'A stale VisitDish mutation revived a tombstoned association')

// Leave only tombstones in Development D1 so the run remains auditable without
// polluting active product data.
const cleanupCursor = removed.nextCursor
await push(deletion('origin-association-delete', 'visitDish', originAssociationID, 1))
await push(deletion('dish-delete', 'dish', dishID, editedAck.serverVersion))
await push(deletion('visit-first-delete', 'visit', firstVisitID, firstVisitAck.serverVersion))
await push(deletion('visit-second-delete', 'visit', secondVisitID, secondVisitAck.serverVersion))
await push(deletion('restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion))
const cleanup = await pull(userID, cleanupCursor)
for (const [entityType, entityId] of [
  ['visitDish', originAssociationID], ['dish', dishID], ['visit', firstVisitID],
  ['visit', secondVisitID], ['restaurant', restaurantID],
]) {
  assert(cleanup.tombstones.some((item) => item.entityType === entityType && item.entityId === entityId),
    `Cleanup tombstone missing for ${entityType}:${entityId}`)
}

console.log(JSON.stringify({
  result: 'P2-C Development Worker/D1 Dish flow passed', baseURL, userID,
  restaurantID, firstVisitID, secondVisitID, dishID,
  originAssociationID, secondAssociationID,
  dishCreateRetryIdempotent: dishRetry.duplicate,
  associationRetryIdempotent: secondAssociationRetry.duplicate,
  freshClientAssociations: 2,
  twoClientEditServerVersion: clientBDish.serverVersion,
  userIsolationStatus: takeover.response.status,
  staleReviveStatus: staleRevive.status,
  finalCursor: cleanup.nextCursor,
  cleanup: 'all active test entities tombstoned',
}, null, 2))

function visit(id, note) {
  return {
    schemaVersion: 1, id, userId: 'forged-client-user', restaurantId: restaurantID,
    visitedAt: createdAt, diningMode: 'dine_in', partySize: null, rating: null,
    note, myActualSpend: null, createdAt, updatedAt: createdAt, deletedAt: null,
  }
}

function association(id, visitId, sortOrder) {
  return {
    schemaVersion: 1, id, userId: 'forged-client-user', restaurantId: restaurantID,
    visitId, dishId: dishID, sortOrder, createdAt, updatedAt: createdAt, deletedAt: null,
  }
}

function mutation(suffix, entityType, entityId, baseVersion, payload) {
  return {
    mutationId: `${runID}:${suffix}`, entityType, entityId, operation: 'upsert', baseVersion,
    clientTimestamp: payload.updatedAt, payload,
  }
}

function deletion(suffix, entityType, entityId, baseVersion) {
  return {
    mutationId: `${runID}:${suffix}`, entityType, entityId, operation: 'delete', baseVersion,
    clientTimestamp: new Date().toISOString(),
  }
}

async function push(item) {
  const { response, body } = await rawPush(userID, item)
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body.acknowledgements[0]
}

async function rawPush(viewerID, item) {
  const response = await fetch(`${baseURL}/api/v1/sync/push`, {
    method: 'POST', headers: headersFor(viewerID),
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations: [item] }),
  })
  return { response, body: await response.json().catch(() => ({})) }
}

async function pull(viewerID, cursor) {
  const response = await fetch(
    `${baseURL}/api/v1/sync/pull?schemaVersion=1&cursor=${encodeURIComponent(cursor)}&limit=200`,
    { headers: headersFor(viewerID) },
  )
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

function headersFor(viewerID) {
  return {
    Accept: 'application/json', 'Content-Type': 'application/json',
    'X-Taste-Map-Test-User': viewerID,
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}
