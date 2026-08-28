import { createHash, randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (!baseURL) throw new Error('TASTEMAP_API_DEV_BASE_URL is required.')

const runID = randomUUID()
const userID = `p2g:${runID}`
const otherUserID = `${userID}:other`
const restaurantID = `restaurant-${runID}`
const firstVisitID = `visit-full-${runID}`
const secondVisitID = `visit-reuse-${runID}`
const dishID = `dish-${runID}`
const originAssociationID = `legacy:${dishID}:${firstVisitID}`
const reusedAssociationID = `visit-dish-${runID}`
const companionID = `companion-${runID}`
const sourceID = `source-${runID}`
const photoID = randomUUID()
const createdAt = new Date().toISOString()

const restaurant = {
  schemaVersion: 1, id: restaurantID, userId: 'forged-owner',
  name: 'P2-G Development Full E2E', address: 'Development D1 only', city: 'Development',
  latitude: 37.3349, longitude: -122.009, status: 'visited', preferenceLevel: 'normal',
  overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
  valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null,
  openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
  markerEmoji: '🍽️', placeIdentities: [{
    provider: 'apple_maps', externalId: `apple-p2g-${runID}`, isPrimary: true,
    createdAt, updatedAt: createdAt,
  }], createdAt, updatedAt: createdAt, deletedAt: null,
}
const companion = {
  schemaVersion: 1, id: companionID, userId: 'forged-owner', displayName: 'P2-G 饭搭子',
  linkedTasteMapUserId: null, createdAt, updatedAt: createdAt, deletedAt: null,
}
const source = {
  schemaVersion: 1, id: sourceID, userId: 'forged-owner', displayName: 'P2-G 推荐来源',
  sourceType: 'blogger', linkedTasteMapUserId: null, createdAt, updatedAt: createdAt, deletedAt: null,
}
const firstVisit = fullVisit(firstVisitID, {
  companions: [companion.displayName], companionIds: [companionID],
  recommendationSourceId: sourceID, recommendationSourceType: source.sourceType,
  recommendationSourceText: source.displayName,
})
const secondVisit = fullVisit(secondVisitID, {
  visitedAt: new Date(Date.now() + 1_000).toISOString(),
  rating: 5, valueRating: 4.5, environmentRating: null, serviceRating: 5,
  totalPrice: 240, myActualSpend: 120, pricePerPerson: 120, partySize: 2,
  companions: [companion.displayName], companionIds: [companionID],
  recommendationSourceId: sourceID, recommendationSourceType: source.sourceType,
  recommendationSourceText: source.displayName,
  note: 'P2-G reusable directories and Dish',
})
const dish = {
  schemaVersion: 1, id: dishID, userId: 'forged-owner', restaurantId: restaurantID,
  visitId: firstVisitID, name: 'P2-G 招牌菜', taste: '鲜香', rating: 4.5,
  price: 88, photoId: photoID, sortOrder: 0, createdAt, updatedAt: createdAt, deletedAt: null,
}
const reusedAssociation = association(reusedAssociationID, secondVisitID)

const restaurantAck = await push(mutation('restaurant-create', 'restaurant', restaurantID, 0, restaurant))
const companionMutation = mutation('companion-create', 'companion', companionID, 0, companion)
const companionAck = await push(companionMutation)
const companionRetry = await push(companionMutation)
const sourceAck = await push(mutation('source-create', 'recommendationSource', sourceID, 0, source))
const firstVisitAck = await push(mutation('visit-full-create', 'visit', firstVisitID, 0, firstVisit))
const secondVisitAck = await push(mutation('visit-reuse-create', 'visit', secondVisitID, 0, secondVisit))
const dishAck = await push(mutation('dish-create', 'dish', dishID, 0, dish))
const reusedAssociationMutation = mutation(
  'visit-dish-reuse-create', 'visitDish', reusedAssociationID, 0, reusedAssociation,
)
const reusedAssociationAck = await push(reusedAssociationMutation)
const reusedAssociationRetry = await push(reusedAssociationMutation)

assert([
  restaurantAck, companionAck, sourceAck, firstVisitAck, secondVisitAck, dishAck, reusedAssociationAck,
].every((ack) => ack.status === 'applied' && ack.serverVersion === 1), 'P2-G parent graph creation failed')
assert(companionRetry.duplicate === true && reusedAssociationRetry.duplicate === true,
  'Repeated P2-G mutations were not idempotent')

const display = new TextEncoder().encode(`Taste Map P2-G display ${runID}`)
const thumbnail = new TextEncoder().encode(`Taste Map P2-G thumbnail ${runID}`)
const displayUpload = await upload('display', display)
const displayUploadRetry = await upload('display', display)
const thumbnailUpload = await upload('thumbnail', thumbnail)
assert(displayUploadRetry.duplicate === true && displayUploadRetry.storageKey === displayUpload.storageKey,
  'Photo response-loss retry was not idempotent')
const photo = {
  schemaVersion: 1, id: photoID, userId: 'forged-owner', restaurantId: restaurantID,
  visitId: firstVisitID, dishId: dishID, kind: 'dish', storageProvider: 'r2',
  storageKey: displayUpload.storageKey, providerAccountId: null,
  thumbnailStorageKey: thumbnailUpload.storageKey, fileName: 'p2g-development.jpg',
  mimeType: 'image/jpeg', byteSize: display.byteLength, width: 1200, height: 900,
  sortOrder: 0, visibility: 'private', createdAt, updatedAt: createdAt, deletedAt: null,
}
const photoAck = await push(mutation('photo-create', 'photo', photoID, 0, photo))
assert(photoAck.status === 'applied' && photoAck.serverVersion === 1, 'Photo metadata creation failed')

const initial = await pull(userID, '0')
const firstPulled = findRecord(initial.visits, firstVisitID)
const secondPulled = findRecord(initial.visits, secondVisitID)
const pulledRestaurant = findRecord(initial.restaurants, restaurantID)
const pulledDish = findRecord(initial.dishes, dishID)
const pulledPhoto = findRecord(initial.photos, photoID)
assert(pulledRestaurant.placeIdentities[0]?.provider === 'apple_maps' &&
  !Object.hasOwn(pulledRestaurant, 'amapPoiId'), 'Apple Maps-only Restaurant identity changed')
assert(firstPulled.userId === userID && pulledDish.userId === userID && pulledPhoto.userId === userID,
  'Worker trusted a forged payload owner')
assert(firstPulled.restaurantId === restaurantID && pulledDish.visitId === firstVisitID &&
  pulledPhoto.dishId === dishID, 'Restaurant / Visit / Dish / Photo relationships changed')
assert(initial.visitDishes.filter((item) => item.record.dishId === dishID).length === 2,
  'One Dish was not reusable across both Visits')
assert(firstPulled.companionIds[0] === companionID && secondPulled.companionIds[0] === companionID,
  'Companion was not reusable across both Visits')
assert(firstPulled.recommendationSourceId === sourceID && secondPulled.recommendationSourceId === sourceID,
  'Recommendation source was not reusable across both Visits')
assert(firstPulled.rating === 4.5 && firstPulled.valueRating === 5 &&
  firstPulled.environmentRating === 4 && firstPulled.serviceRating === 3.5,
  'Detailed ratings lost precision')
assert(firstPulled.queueDuration === 'under60' && firstPulled.paymentMode === 'aa' &&
  firstPulled.diningOccasions.join(',') === 'friends,other', 'Visit context fields changed')
assert(pulledPhoto.storageKey === displayUpload.storageKey &&
  pulledPhoto.thumbnailStorageKey === thumbnailUpload.storageKey, 'Photo storage contract changed')

const noChanges = await pull(userID, initial.nextCursor)
assert(['restaurants', 'visits', 'dishes', 'visitDishes', 'photos', 'companions', 'recommendationSources']
  .every((key) => noChanges[key].length === 0) && noChanges.tombstones.length === 0,
'Incremental cursor returned unchanged P2 data')

const editedAt = new Date(Date.now() + 3_000).toISOString()
const clearedVisit = {
  ...firstVisit, rating: null, totalPrice: null, paymentMode: null, pricePerPerson: null,
  queueDuration: null, diningOccasions: [], diningOccasionText: null,
  valueTags: [], noiseLevel: null, specialNotes: null, note: null,
  updatedAt: editedAt,
}
const firstVisitEditAck = await push(mutation(
  'visit-full-clear', 'visit', firstVisitID, firstVisitAck.serverVersion, clearedVisit,
))
assert(firstVisitEditAck.status === 'applied' && firstVisitEditAck.serverVersion === 2,
  'Full Visit nullable clear failed')
const secondClient = await pull(userID, initial.nextCursor)
const edited = findRecord(secondClient.visits, firstVisitID)
assert(edited.rating === null && edited.totalPrice === null && edited.paymentMode === null &&
  edited.queueDuration === null && edited.note === null, 'Nullable fields did not clear')
assert(edited.valueRating === 5 && edited.environmentRating === 4 && edited.serviceRating === 3.5 &&
  edited.companionIds[0] === companionID && edited.recommendationSourceId === sourceID,
  'Clearing one Visit module erased unrelated P2 modules')
assert(secondClient.dishes.length === 0 && pulledDish.id === dishID,
  'Editing Visit unexpectedly rewrote or invalidated its Dish')

const staleConflict = await push(mutation(
  'visit-stale-conflict', 'visit', firstVisitID, 1,
  { ...firstVisit, note: 'stale overwrite', updatedAt: new Date(Date.now() + 4_000).toISOString() },
))
assert(staleConflict.status === 'conflict' && staleConflict.serverVersion === 2,
  'Stale full Visit update overwrote the server record')

const otherPull = await pull(otherUserID, '0')
for (const key of ['restaurants', 'visits', 'dishes', 'visitDishes', 'photos', 'companions', 'recommendationSources']) {
  assert(!otherPull[key].some((item) => [
    restaurantID, firstVisitID, secondVisitID, dishID, reusedAssociationID,
    photoID, companionID, sourceID,
  ].includes(item.record.id)), `Another user read private ${key} data`)
}
const takeover = await rawPush(otherUserID, mutation(
  'other-user-takeover', 'visit', firstVisitID, firstVisitEditAck.serverVersion,
  { ...clearedVisit, userId: otherUserID, note: 'takeover' },
))
assert(takeover.response.status === 403, `Another user modified the Visit (${takeover.response.status})`)

const cleanupCursor = secondClient.nextCursor
const photoDeleteAck = await push(deletion('photo-delete', 'photo', photoID, photoAck.serverVersion))
assert(photoDeleteAck.status === 'applied', 'Photo tombstone failed')
const binaryDelete = await fetch(`${baseURL}/api/v1/photos/${photoID}/content`, {
  method: 'DELETE', headers: identityHeaders(userID),
})
assert(binaryDelete.ok, `Photo binary cleanup failed (${binaryDelete.status})`)
const deletedBinary = await fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=display`, {
  headers: identityHeaders(userID),
})
assert(deletedBinary.status === 404, 'Tombstoned photo binary remained downloadable')

const originDeleteAck = await push(deletion('origin-association-delete', 'visitDish', originAssociationID, 1))
const reusedDeleteAck = await push(deletion(
  'reuse-association-delete', 'visitDish', reusedAssociationID, reusedAssociationAck.serverVersion,
))
const dishDeleteAck = await push(deletion('dish-delete', 'dish', dishID, dishAck.serverVersion))
const firstVisitDeleteAck = await push(deletion(
  'visit-full-delete', 'visit', firstVisitID, firstVisitEditAck.serverVersion,
))
const secondVisitDeleteAck = await push(deletion(
  'visit-reuse-delete', 'visit', secondVisitID, secondVisitAck.serverVersion,
))
const staleRevive = await push(mutation(
  'visit-stale-revive', 'visit', firstVisitID, firstVisitEditAck.serverVersion,
  { ...clearedVisit, updatedAt: new Date(Date.now() + 5_000).toISOString() },
))
assert(staleRevive.status === 'conflict' && staleRevive.serverVersion === firstVisitDeleteAck.serverVersion,
  'A stale mutation revived the tombstoned Visit')
const companionDeleteAck = await push(deletion('companion-delete', 'companion', companionID, companionAck.serverVersion))
const sourceDeleteAck = await push(deletion('source-delete', 'recommendationSource', sourceID, sourceAck.serverVersion))
const restaurantDeleteAck = await push(deletion(
  'restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion,
))
assert([
  originDeleteAck, reusedDeleteAck, dishDeleteAck, firstVisitDeleteAck, secondVisitDeleteAck,
  companionDeleteAck, sourceDeleteAck, restaurantDeleteAck,
].every((ack) => ack.status === 'applied'), 'P2-G cleanup tombstone failed')

const cleanup = await pull(userID, cleanupCursor)
for (const [entityType, entityID] of [
  ['photo', photoID], ['visitDish', originAssociationID], ['visitDish', reusedAssociationID],
  ['dish', dishID], ['visit', firstVisitID], ['visit', secondVisitID],
  ['companion', companionID], ['recommendationSource', sourceID], ['restaurant', restaurantID],
]) {
  assert(cleanup.tombstones.some((item) => item.entityType === entityType && item.entityId === entityID),
    `Cleanup tombstone missing for ${entityType}:${entityID}`)
}

console.log(JSON.stringify({
  result: 'P2-G Development full rich Visit graph passed', baseURL, userID,
  restaurantID, firstVisitID, secondVisitID, dishID, photoID, companionID, sourceID,
  appleMapsOnly: true,
  fullVisitServerVersion: firstVisitEditAck.serverVersion,
  companionReuseCount: 2,
  recommendationSourceReuseCount: 2,
  dishVisitAssociationCount: 2,
  mutationIdempotency: companionRetry.duplicate && reusedAssociationRetry.duplicate,
  photoUploadIdempotency: displayUploadRetry.duplicate,
  incrementalCursorEmpty: true,
  conflictStatus: staleConflict.status,
  staleReviveStatus: staleRevive.status,
  userIsolationStatus: takeover.response.status,
  binaryTombstoneStatus: deletedBinary.status,
  finalCursor: cleanup.nextCursor,
  cleanup: 'all active P2-G entities tombstoned and private binary deleted',
}, null, 2))

function fullVisit(id, overrides = {}) {
  return {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: restaurantID,
    visitedAt: createdAt, diningMode: 'dine_in', visibility: 'friends', partySize: 3,
    totalPrice: 360, myActualSpend: 120, paymentMode: 'aa', pricePerPerson: 120,
    queueDuration: 'under60', diningOccasions: ['friends', 'other'], diningOccasionText: '生日聚餐',
    rating: 4.5, valueRating: 5, environmentRating: 4, serviceRating: 3.5,
    valueTags: ['合理'], environmentTags: ['舒适'], serviceTags: ['周到'],
    noiseLevel: 'normal', diningDuration: 'under30', portionLevel: 'generous',
    transportConvenience: 'very_convenient', specialNotes: '靠窗位',
    companions: [], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId: null,
    note: 'P2-G full Development E2E', createdAt, updatedAt: createdAt, deletedAt: null,
    ...overrides,
  }
}

function association(id, visitId) {
  return {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: restaurantID,
    visitId, dishId: dishID, sortOrder: 0, createdAt, updatedAt: createdAt, deletedAt: null,
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
    method: 'POST', headers: jsonHeaders(viewerID),
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations: [item] }),
  })
  return { response, body: await response.json().catch(() => ({})) }
}

async function pull(viewerID, cursor) {
  const response = await fetch(
    `${baseURL}/api/v1/sync/pull?schemaVersion=1&cursor=${encodeURIComponent(cursor)}&limit=200`,
    { headers: identityHeaders(viewerID) },
  )
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

async function upload(variant, data) {
  const response = await fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=${variant}`, {
    method: 'PUT',
    headers: {
      ...identityHeaders(userID), 'Content-Type': 'image/jpeg',
      'X-Taste-Map-Content-SHA256': createHash('sha256').update(data).digest('hex'),
      'X-Taste-Map-Upload-ID': runID,
    },
    body: data,
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

function identityHeaders(viewerID) {
  return { Accept: 'application/json', 'X-Taste-Map-Test-User': viewerID }
}

function jsonHeaders(viewerID) {
  return { ...identityHeaders(viewerID), 'Content-Type': 'application/json' }
}

function findRecord(items, id) {
  const item = items.find((candidate) => candidate.record.id === id)
  if (!item) throw new Error(`Pulled record missing: ${id}`)
  return item.record
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}
