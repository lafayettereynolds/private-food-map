import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (!baseURL) throw new Error('TASTEMAP_API_DEV_BASE_URL is required.')

const runID = randomUUID()
const userID = 'p2f-development-user'
const otherUserID = 'p2f-development-other'
const restaurantID = `restaurant-${runID}`
const visitID = `visit-${runID}`
const companionAID = `companion-a-${runID}`
const companionBID = `companion-b-${runID}`
const sourceID = `source-${runID}`
const createdAt = new Date().toISOString()

const restaurant = {
  schemaVersion: 1, id: restaurantID, userId: 'forged-owner',
  name: 'P2-F Development Companion Restaurant', address: 'Development D1 only', city: 'Development',
  latitude: 37.3349, longitude: -122.009, status: 'visited', preferenceLevel: 'normal',
  overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
  valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null,
  openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
  markerEmoji: '🍽️', placeIdentities: [{
    provider: 'apple_maps', externalId: `apple-p2f-${runID}`, isPrimary: true,
    createdAt, updatedAt: createdAt,
  }], createdAt, updatedAt: createdAt, deletedAt: null,
}
const companionA = companion(companionAID, '小王')
const companionB = companion(companionBID, '妈妈')
const source = recommendationSource(sourceID, '朋友小李', 'friend')
const visit = visitPayload({
  companions: [companionA.displayName, companionB.displayName],
  companionIds: [companionAID, companionBID],
  recommendationSourceId: sourceID,
  recommendationSourceType: source.sourceType,
  recommendationSourceText: source.displayName,
})

const restaurantAck = await push(userID, mutation('restaurant-create', 'restaurant', restaurantID, 0, restaurant))
const companionAAck = await push(userID, mutation('companion-a-create', 'companion', companionAID, 0, companionA))
const companionBMutation = mutation('companion-b-create', 'companion', companionBID, 0, companionB)
const companionBAck = await push(userID, companionBMutation)
const companionBRetry = await push(userID, companionBMutation)
const sourceAck = await push(userID, mutation('source-create', 'recommendationSource', sourceID, 0, source))
const visitAck = await push(userID, mutation('visit-create', 'visit', visitID, 0, visit))
assert([restaurantAck, companionAAck, companionBAck, sourceAck, visitAck]
  .every((ack) => ack.status === 'applied' && ack.serverVersion === 1),
'Initial Restaurant, directories, or Visit creation failed')
assert(companionBRetry.duplicate === true && companionBRetry.serverVersion === 1,
  'Repeated companion mutation was not idempotent')

const duplicateNameID = `companion-duplicate-${runID}`
const duplicateName = await push(userID, mutation(
  'companion-duplicate-name', 'companion', duplicateNameID, 0,
  companion(duplicateNameID, '  小王  '),
))
assert(duplicateName.status === 'conflict' && duplicateName.conflictReason.startsWith('duplicate_name:'),
  'Normalized duplicate name was not rejected safely')

const initial = await pull(userID, '0')
const pulledVisit = initial.visits.find((item) => item.record.id === visitID)
assert(initial.companions.filter((item) => [companionAID, companionBID].includes(item.record.id)).length === 2,
  'Fresh client did not pull both companions')
assert(initial.recommendationSources.some((item) => item.record.id === sourceID),
  'Fresh client did not pull the recommendation source')
assert(pulledVisit?.record.companionIds.join(',') === `${companionAID},${companionBID}`,
  'Visit companion associations did not round-trip')
assert(pulledVisit.record.recommendationSourceId === sourceID &&
  pulledVisit.record.recommendationSourceText === source.displayName,
'Visit recommendation source did not round-trip')
assert(pulledVisit.record.userId === userID &&
  initial.companions.find((item) => item.record.id === companionAID)?.record.userId === userID,
'Worker trusted a forged payload owner')

const noChanges = await pull(userID, initial.nextCursor)
assert(noChanges.companions.length === 0 && noChanges.recommendationSources.length === 0 &&
  noChanges.visits.length === 0 && noChanges.tombstones.length === 0,
'Incremental cursor returned unchanged P2-F data')

const renamedAt = new Date(Date.now() + 1_000).toISOString()
const renamedCompanion = { ...companionA, displayName: '王宇', updatedAt: renamedAt }
const renameAck = await push(userID, mutation(
  'companion-a-rename', 'companion', companionAID, companionAAck.serverVersion, renamedCompanion,
))
assert(renameAck.status === 'applied' && renameAck.serverVersion === 2, 'Companion rename failed')
const secondClientRename = await pull(userID, initial.nextCursor)
assert(secondClientRename.companions.find((item) => item.record.id === companionAID)?.record.displayName === '王宇',
  'Second client did not receive the stable-identity rename')

const editedAt = new Date(Date.now() + 2_000).toISOString()
const associationRemoved = {
  ...visit,
  companions: ['小王'], companionIds: [companionAID],
  recommendationSourceId: null, recommendationSourceType: null,
  recommendationSourceUserId: null, recommendationSourceText: null,
  updatedAt: editedAt,
}
const visitEditAck = await push(userID, mutation(
  'visit-remove-associations', 'visit', visitID, visitAck.serverVersion, associationRemoved,
))
assert(visitEditAck.status === 'applied' && visitEditAck.serverVersion === 2,
  'Removing Visit associations failed')
const afterAssociationRemoval = await pull(userID, secondClientRename.nextCursor)
const editedVisit = afterAssociationRemoval.visits.find((item) => item.record.id === visitID)?.record
assert(editedVisit?.companionIds.length === 1 && editedVisit.recommendationSourceId === null,
  'Second client did not converge after association removal')
assert(afterAssociationRemoval.tombstones.length === 0,
  'Removing an association incorrectly deleted a directory entity')

const companionBDelete = await push(userID, deletion(
  'companion-b-delete', 'companion', companionBID, companionBAck.serverVersion,
))
const sourceDelete = await push(userID, deletion(
  'source-delete', 'recommendationSource', sourceID, sourceAck.serverVersion,
))
const afterDirectoryDeletes = await pull(userID, afterAssociationRemoval.nextCursor)
assert(afterDirectoryDeletes.tombstones.some((item) => item.entityType === 'companion' && item.entityId === companionBID),
  'Companion tombstone was not pulled')
assert(afterDirectoryDeletes.tombstones.some((item) => item.entityType === 'recommendationSource' && item.entityId === sourceID),
  'Recommendation source tombstone was not pulled')
const staleRevive = await push(userID, mutation(
  'companion-b-stale-revive', 'companion', companionBID, 1,
  { ...companionB, updatedAt: new Date(Date.now() + 3_000).toISOString() },
))
assert(staleRevive.status === 'conflict' && staleRevive.serverVersion === companionBDelete.serverVersion,
  'Stale mutation revived a deleted companion')

const otherPull = await pull(otherUserID, '0')
assert(!otherPull.companions.some((item) => item.record.id === companionAID) &&
  !otherPull.recommendationSources.some((item) => item.record.id === sourceID) &&
  !otherPull.visits.some((item) => item.record.id === visitID),
'Another user read private P2-F data')
const takeover = await rawPush(otherUserID, mutation(
  'other-user-takeover', 'companion', companionAID, renameAck.serverVersion,
  { ...renamedCompanion, userId: otherUserID, displayName: '被篡改' },
))
assert(takeover.response.status === 403, `Another user modified a companion (${takeover.response.status})`)

// Leave auditable tombstones instead of active P2-F test records.
const cleanupCursor = afterDirectoryDeletes.nextCursor
await push(userID, deletion('visit-delete', 'visit', visitID, visitEditAck.serverVersion))
await push(userID, deletion('companion-a-delete', 'companion', companionAID, renameAck.serverVersion))
await push(userID, deletion('restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion))
const cleanup = await pull(userID, cleanupCursor)
for (const [entityType, entityID] of [
  ['visit', visitID], ['companion', companionAID], ['restaurant', restaurantID],
]) {
  assert(cleanup.tombstones.some((item) => item.entityType === entityType && item.entityId === entityID),
    `Cleanup tombstone missing for ${entityType}:${entityID}`)
}

console.log(JSON.stringify({
  result: 'P2-F Development Worker/D1 companion and source flow passed',
  baseURL, userID, restaurantID, visitID, companionAID, companionBID, sourceID,
  companionMutationRetryIdempotent: companionBRetry.duplicate,
  duplicateNameStatus: duplicateName.status,
  renameServerVersion: renameAck.serverVersion,
  associationRemovalServerVersion: visitEditAck.serverVersion,
  staleReviveStatus: staleRevive.status,
  userIsolationStatus: takeover.response.status,
  finalCursor: cleanup.nextCursor,
  cleanup: 'all active test entities tombstoned',
}, null, 2))

function companion(id, displayName) {
  return {
    schemaVersion: 1, id, userId: 'forged-owner', displayName,
    linkedTasteMapUserId: null, createdAt, updatedAt: createdAt, deletedAt: null,
  }
}

function recommendationSource(id, displayName, sourceType) {
  return {
    schemaVersion: 1, id, userId: 'forged-owner', displayName, sourceType,
    linkedTasteMapUserId: null, createdAt, updatedAt: createdAt, deletedAt: null,
  }
}

function visitPayload(overrides = {}) {
  return {
    schemaVersion: 1, id: visitID, userId: 'forged-owner', restaurantId: restaurantID,
    visitedAt: createdAt, diningMode: 'dine_in', visibility: 'private', partySize: 3,
    totalPrice: 300, paymentMode: 'aa', pricePerPerson: 100, queueDuration: null,
    diningOccasions: ['friends'], diningOccasionText: null,
    rating: 4.5, valueRating: 4, environmentRating: 5, serviceRating: 4.5,
    valueTags: ['合理'], environmentTags: ['舒适'], serviceTags: ['周到'],
    noiseLevel: 'normal', diningDuration: 'under30', portionLevel: 'generous',
    transportConvenience: 'very_convenient', specialNotes: null,
    companions: [], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId: null,
    note: 'P2-F Development E2E', myActualSpend: 100,
    createdAt, updatedAt: createdAt, deletedAt: null,
    ...overrides,
  }
}

function mutation(suffix, entityType, entityId, baseVersion, payload) {
  return {
    mutationId: `${runID}:${suffix}`, entityType, entityId, operation: 'upsert',
    baseVersion, clientTimestamp: payload.updatedAt, payload,
  }
}

function deletion(suffix, entityType, entityId, baseVersion) {
  return {
    mutationId: `${runID}:${suffix}`, entityType, entityId, operation: 'delete',
    baseVersion, clientTimestamp: new Date().toISOString(),
  }
}

async function push(viewerID, item) {
  const { response, body } = await rawPush(viewerID, item)
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
