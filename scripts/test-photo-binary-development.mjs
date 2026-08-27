import { createHash, randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (!baseURL) throw new Error('TASTEMAP_API_DEV_BASE_URL is required.')

const runID = randomUUID()
const userID = `p2b:${runID}`
const otherUserID = `${userID}:other`
const restaurantID = `restaurant-${runID}`
const visitID = `visit-${runID}`
const photoID = randomUUID()
const createdAt = new Date().toISOString()
const headers = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
  'X-Taste-Map-Test-User': userID,
}

const restaurant = {
  schemaVersion: 1, id: restaurantID, userId: 'forged-client',
  name: 'P2-B Development Photo Restaurant', address: 'Development D1 only', city: 'Development',
  latitude: 37.3349, longitude: -122.009, status: 'visited', preferenceLevel: 'normal',
  overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
  valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null,
  openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
  markerEmoji: '📷', placeIdentities: [{
    provider: 'apple_maps', externalId: `apple-photo-${runID}`, isPrimary: true,
    createdAt, updatedAt: createdAt,
  }], createdAt, updatedAt: createdAt, deletedAt: null,
}
const visit = {
  schemaVersion: 1, id: visitID, userId: 'forged-client', restaurantId: restaurantID,
  visitedAt: createdAt, diningMode: 'dine_in', partySize: null, rating: null,
  note: 'P2-B real Development R2 test', myActualSpend: null,
  createdAt, updatedAt: createdAt, deletedAt: null,
}

const restaurantAck = await push(mutation('restaurant', 'restaurant', restaurantID, 0, restaurant))
const visitAck = await push(mutation('visit', 'visit', visitID, 0, visit))
assert(restaurantAck.status === 'applied' && visitAck.status === 'applied', 'Parent records failed')

const display = new TextEncoder().encode(`Taste Map display ${runID}`)
const thumbnail = new TextEncoder().encode(`Taste Map thumbnail ${runID}`)
const displayUpload = await upload('display', display)
const duplicateUpload = await upload('display', display)
const thumbnailUpload = await upload('thumbnail', thumbnail)
assert(displayUpload.duplicate === false, 'First display upload was unexpectedly duplicate')
assert(duplicateUpload.duplicate === true, 'Repeated display upload was not idempotent')
assert(displayUpload.storageKey === duplicateUpload.storageKey, 'Idempotent key changed')

const photo = {
  schemaVersion: 1, id: photoID, userId: 'forged-client', restaurantId: restaurantID,
  visitId: visitID, dishId: null, kind: 'visit', storageProvider: 'r2',
  storageKey: displayUpload.storageKey, providerAccountId: null,
  thumbnailStorageKey: thumbnailUpload.storageKey, fileName: 'development-photo.jpg',
  mimeType: 'image/jpeg', byteSize: display.byteLength, width: 1200, height: 900,
  sortOrder: 0, visibility: 'private', createdAt, updatedAt: createdAt, deletedAt: null,
}
const photoAck = await push(mutation('photo', 'photo', photoID, 0, photo))
assert(photoAck.status === 'applied', 'Photo metadata did not sync')

const pulled = await pull('0')
const pulledPhoto = pulled.photos.find((item) => item.record.id === photoID)
assert(pulledPhoto?.record.storageKey === displayUpload.storageKey, 'Photo storage key did not round-trip')
assert(pulledPhoto.record.thumbnailStorageKey === thumbnailUpload.storageKey, 'Thumbnail key did not round-trip')

const downloaded = await download('display', userID)
assert(Buffer.compare(Buffer.from(downloaded), Buffer.from(display)) === 0, 'Authorized display bytes changed')
const denied = await fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=display`, {
  headers: { 'X-Taste-Map-Test-User': otherUserID },
})
assert(denied.status === 404, `Another user received photo content (${denied.status})`)

const photoDeleteAck = await push(deletion('photo-delete', 'photo', photoID, photoAck.serverVersion))
assert(photoDeleteAck.status === 'applied', 'Photo tombstone failed')
const binaryDelete = await fetch(`${baseURL}/api/v1/photos/${photoID}/content`, {
  method: 'DELETE', headers: { 'X-Taste-Map-Test-User': userID },
})
assert(binaryDelete.ok, `Binary cleanup failed (${binaryDelete.status})`)
const afterDelete = await fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=display`, {
  headers: { 'X-Taste-Map-Test-User': userID },
})
assert(afterDelete.status === 404, 'Deleted photo content remained downloadable')

await push(deletion('visit-delete', 'visit', visitID, visitAck.serverVersion))
await push(deletion('restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion))

console.log(JSON.stringify({
  result: 'P2-B Development Worker/D1/R2 photo flow passed',
  baseURL, userID, restaurantID, visitID, photoID,
  storageProvider: displayUpload.storageProvider,
  storageKey: displayUpload.storageKey,
  thumbnailStorageKey: thumbnailUpload.storageKey,
  uploadIdempotency: duplicateUpload.duplicate,
  privateDownloadIsolation: denied.status === 404,
  tombstoneCleanup: afterDelete.status === 404,
}, null, 2))

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
  const body = await jsonRequest('/api/v1/sync/push', {
    method: 'POST', headers,
    body: JSON.stringify({ apiVersion: 1, schemaVersion: 1, mutations: [item] }),
  })
  return body.acknowledgements[0]
}

function pull(cursor) {
  return jsonRequest(`/api/v1/sync/pull?schemaVersion=1&cursor=${encodeURIComponent(cursor)}&limit=200`, {
    headers,
  })
}

async function upload(variant, data) {
  return jsonRequest(`/api/v1/photos/${photoID}/content?variant=${variant}`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'image/jpeg',
      'X-Taste-Map-Content-SHA256': createHash('sha256').update(data).digest('hex'),
      'X-Taste-Map-Upload-ID': runID,
      'X-Taste-Map-Test-User': userID,
    },
    body: data,
  })
}

async function download(variant, viewer) {
  const response = await fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=${variant}`, {
    headers: { 'X-Taste-Map-Test-User': viewer },
  })
  if (!response.ok) throw new Error(`${response.status} ${await response.text()}`)
  return new Uint8Array(await response.arrayBuffer())
}

async function jsonRequest(path, options) {
  const response = await fetch(`${baseURL}${path}`, options)
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}
