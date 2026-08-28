import { createHash, randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (!baseURL) throw new Error('TASTEMAP_API_DEV_BASE_URL is required.')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error(`P3-A Development test refuses a non-Development URL: ${baseURL}`)
}

const runID = randomUUID()
const userA = `p3a:${runID}`
const userB = `p3a:${runID}:viewer`
const offlineUser = `p3a:${runID}:offline`
const restaurantID = `restaurant-${runID}`
const publicVisitID = `visit-public-${runID}`
const privateVisitID = `visit-private-${runID}`
const firstAvatarID = randomUUID()
const secondAvatarID = randomUUID()
const createdAt = new Date().toISOString()

// Exercise the real offline-first edge: authentication creates a server bootstrap,
// while the client already owns a local base-version-0 Profile and has never pulled it.
const offlineRecord = profile({
  userId: offlineUser, displayName: 'P3-A 离线用户', bio: 'Offline-first reconnect',
})
const offlineMutation = mutation(
  'offline-profile-create', 'profile', offlineUser, 0, offlineRecord,
)
const offlineAck = await push(offlineUser, offlineMutation)
const offlineRetry = await push(offlineUser, offlineMutation)
assert(offlineAck.status === 'applied' && offlineAck.serverVersion === 2,
  'Offline-first Profile did not adopt the untouched server bootstrap')
assert(offlineRetry.duplicate === true && offlineRetry.serverVersion === 2,
  'Offline-first Profile retry was not idempotent')
const offlineStale = await push(offlineUser, mutation(
  'offline-profile-stale', 'profile', offlineUser, 0,
  { ...offlineRecord, displayName: '不能覆盖', updatedAt: nextInstant(9) },
))
assert(offlineStale.status === 'conflict' && offlineStale.serverVersion === 2,
  'A second base-version-0 Profile overwrote an edited Profile')

const initial = await pull(userA, '0')
const initialProfile = findProfile(initial, userA)
assert(initialProfile.serverVersion === 1, 'Development Profile was not initialized at version 1')
const initialCursor = initial.nextCursor

const publicProfileRecord = profile({
  displayName: 'P3-A 开发用户', bio: 'Development E2E', city: '杭州', visibility: 'public',
  createdAt: initialProfile.record.createdAt,
})
const publicMutation = mutation('profile-public', 'profile', userA, 1, publicProfileRecord)
const publicAck = await push(userA, publicMutation)
const publicRetry = await push(userA, publicMutation)
assert(publicAck.status === 'applied' && publicAck.serverVersion === 2,
  'Profile public edit did not apply')
assert(publicRetry.duplicate === true && publicRetry.serverVersion === 2,
  'Profile mutation was not idempotent')

const restaurant = {
  schemaVersion: 1, id: restaurantID, userId: 'forged-owner',
  name: 'P3-A Public Statistics Restaurant', address: 'Development D1 only', city: 'Development',
  latitude: 37.3349, longitude: -122.009, status: 'visited', preferenceLevel: 'normal',
  overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
  valueRating: null, tags: [], longTermNote: '', pricePerPerson: null, phone: null,
  openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
  markerEmoji: '👤', placeIdentities: [{
    provider: 'apple_maps', externalId: `apple-p3a-${runID}`, isPrimary: true,
    createdAt, updatedAt: createdAt,
  }], createdAt, updatedAt: createdAt, deletedAt: null,
}
const restaurantAck = await push(userA, mutation(
  'restaurant-create', 'restaurant', restaurantID, 0, restaurant,
))
const publicVisitAck = await push(userA, mutation(
  'visit-public', 'visit', publicVisitID, 0, visit(publicVisitID, 'public'),
))
const privateVisitAck = await push(userA, mutation(
  'visit-private', 'visit', privateVisitID, 0, visit(privateVisitID, 'private'),
))

const publicWithoutAvatar = await publicQuery(userB, userA)
assertExactPublicKeys(publicWithoutAvatar)
assert(publicWithoutAvatar.statistics.publicVisitCount === 1,
  'Public Profile leaked the private Visit count')
assert(publicWithoutAvatar.statistics.publicRestaurantCount === 1,
  'Public Restaurant count was not derived from public Visits only')

const firstPhoto = await createAvatar(firstAvatarID, 'first')
const secondPhoto = await createAvatar(secondAvatarID, 'second')
const firstPhotoAck = await push(userA, mutation(
  'first-avatar-metadata', 'photo', firstAvatarID, 0, firstPhoto.record,
))
const secondPhotoAck = await push(userA, mutation(
  'second-avatar-metadata', 'photo', secondAvatarID, 0, secondPhoto.record,
))

const firstAvatarAck = await push(userA, mutation(
  'profile-first-avatar', 'profile', userA, 2,
  profile({ ...publicProfileRecord, avatarPhotoId: firstAvatarID, updatedAt: nextInstant(1) }),
))
assert(firstAvatarAck.status === 'applied' && firstAvatarAck.serverVersion === 3,
  'First custom Avatar did not attach to Profile')
const publicFirst = await publicQuery(userB, userA)
assert(publicFirst.avatarPhotoId === firstAvatarID, 'Public DTO did not expose the current Avatar Photo ID')
assertBuffersEqual(await download(firstAvatarID, 'thumbnail', userB), firstPhoto.thumbnail,
  'Another user could not read the authorized public Avatar thumbnail')

const replacementAck = await push(userA, mutation(
  'profile-replace-avatar', 'profile', userA, 3,
  profile({ ...publicProfileRecord, avatarPhotoId: secondAvatarID, updatedAt: nextInstant(2) }),
))
assert(replacementAck.status === 'applied' && replacementAck.serverVersion === 4,
  'Avatar replacement did not apply')
const oldAvatarDenied = await rawDownload(firstAvatarID, 'thumbnail', userB)
assert(oldAvatarDenied.status === 404,
  `The old/private Photo became public after Avatar replacement (${oldAvatarDenied.status})`)
assertBuffersEqual(await download(secondAvatarID, 'thumbnail', userB), secondPhoto.thumbnail,
  'Replacement Avatar thumbnail was not readable')

const incremental = await pull(userA, initialCursor)
assert(incremental.profiles.length >= 1 &&
  incremental.profiles.at(-1)?.record.avatarPhotoId === secondAvatarID,
'Incremental Profile pull did not advance from the existing cursor')

const stale = await push(userA, mutation(
  'profile-stale', 'profile', userA, 2,
  profile({ ...publicProfileRecord, displayName: '不能静默覆盖', updatedAt: nextInstant(3) }),
))
assert(stale.status === 'conflict' && stale.serverVersion === 4,
  'Stale Profile mutation did not return an explicit server-version conflict')
const takeover = await rawPush(userB, mutation(
  'profile-takeover', 'profile', userA, 4,
  profile({ ...publicProfileRecord, userId: userA, displayName: 'takeover', updatedAt: nextInstant(4) }),
))
assert(takeover.response.status === 403,
  `User B was able to edit User A Profile (${takeover.response.status})`)

const finalAck = await push(userA, mutation(
  'profile-final-private', 'profile', userA, 4,
  profile({
    ...publicProfileRecord, avatarPhotoId: null, visibility: 'private',
    bio: '', city: '', updatedAt: nextInstant(5),
  }),
))
assert(finalAck.status === 'applied' && finalAck.serverVersion === 5,
  'Final private Profile cleanup did not apply')
const privateQuery = await rawPublicQuery(userB, userA)
assert(privateQuery.response.status === 404,
  `Private Profile remained queryable by another user (${privateQuery.response.status})`)
const replacementDenied = await rawDownload(secondAvatarID, 'thumbnail', userB)
assert(replacementDenied.status === 404,
  'A Profile made private left its Avatar publicly readable')

await push(userA, deletion('first-avatar-delete', 'photo', firstAvatarID, firstPhotoAck.serverVersion))
await push(userA, deletion('second-avatar-delete', 'photo', secondAvatarID, secondPhotoAck.serverVersion))
await deleteBinary(firstAvatarID, userA)
await deleteBinary(secondAvatarID, userA)
await push(userA, deletion('public-visit-delete', 'visit', publicVisitID, publicVisitAck.serverVersion))
await push(userA, deletion('private-visit-delete', 'visit', privateVisitID, privateVisitAck.serverVersion))
await push(userA, deletion('restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion))

const freshClient = await pull(userA, '0')
const finalProfile = findProfile(freshClient, userA)
assert(finalProfile.serverVersion === 5 && finalProfile.record.visibility === 'private' &&
  finalProfile.record.avatarPhotoId === null,
'Fresh client did not receive the final owner Profile')

console.log(JSON.stringify({
  result: 'P3-A Development Profile/Avatar E2E passed',
  baseURL, userA, userB,
  profileServerVersion: finalProfile.serverVersion,
  profileMutationIdempotency: publicRetry.duplicate,
  incrementalCursor: incremental.nextCursor,
  publicStatistics: publicWithoutAvatar.statistics,
  publicDTOAllowlist: true,
  publicAvatarAuthorizedRead: true,
  oldAvatarPrivateAfterReplacement: oldAvatarDenied.status === 404,
  privateProfileStatus: privateQuery.response.status,
  staleConflict: stale.status,
  takeoverStatus: takeover.response.status,
  freshClientConsistent: true,
  offlineBootstrapAdoption: offlineAck.serverVersion === 2,
  offlineBootstrapRetryIdempotent: offlineRetry.duplicate,
  offlineBootstrapOverwriteBlocked: offlineStale.status === 'conflict',
  cleanup: 'test Restaurant/Visits/Photos tombstoned; Profile retained private for isolated test user',
}, null, 2))

function profile(overrides = {}) {
  return {
    schemaVersion: 1, userId: userA, displayName: 'P3-A 开发用户', bio: '', city: '',
    avatarPhotoId: null, avatarPresetId: 'otter', visibility: 'private',
    createdAt, updatedAt: createdAt, deletedAt: null, ...overrides,
  }
}

function visit(id, visibility) {
  return {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: restaurantID,
    visitedAt: createdAt, diningMode: 'dine_in', visibility, partySize: null,
    totalPrice: null, paymentMode: null, pricePerPerson: null, queueDuration: null,
    diningOccasions: [], diningOccasionText: null, rating: null, valueRating: null,
    environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [],
    serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null,
    transportConvenience: null, specialNotes: null, companions: [], companionIds: [],
    recommendationSourceId: null, recommendationSourceType: null,
    recommendationSourceUserId: null, recommendationSourceText: null, sharedMealId: null,
    note: null, myActualSpend: null, createdAt, updatedAt: createdAt, deletedAt: null,
  }
}

async function createAvatar(photoID, label) {
  const display = new TextEncoder().encode(`Taste Map P3-A ${label} display ${runID}`)
  const thumbnail = new TextEncoder().encode(`Taste Map P3-A ${label} thumbnail ${runID}`)
  const displayUpload = await upload(photoID, 'display', display)
  const thumbnailUpload = await upload(photoID, 'thumbnail', thumbnail)
  return {
    display, thumbnail,
    record: {
      schemaVersion: 1, id: photoID, userId: 'forged-owner',
      restaurantId: null, visitId: null, dishId: null, kind: 'avatar',
      storageProvider: 'r2', storageKey: displayUpload.storageKey,
      providerAccountId: null, thumbnailStorageKey: thumbnailUpload.storageKey,
      fileName: `${label}-avatar.jpg`, mimeType: 'image/jpeg', byteSize: display.byteLength,
      width: 512, height: 512, sortOrder: 0, visibility: 'private',
      createdAt, updatedAt: createdAt, deletedAt: null,
    },
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

async function push(viewerID, item) {
  const { response, body } = await rawPush(viewerID, item)
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

async function publicQuery(viewerID, targetID) {
  const { response, body } = await rawPublicQuery(viewerID, targetID)
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

async function rawPublicQuery(viewerID, targetID) {
  const response = await fetch(
    `${baseURL}/api/v1/public/profiles/${encodeURIComponent(targetID)}`,
    { headers: identityHeaders(viewerID) },
  )
  return { response, body: await response.json().catch(() => ({})) }
}

async function upload(photoID, variant, data) {
  const response = await fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=${variant}`, {
    method: 'PUT', headers: {
      ...identityHeaders(userA), 'Content-Type': 'image/jpeg',
      'X-Taste-Map-Content-SHA256': createHash('sha256').update(data).digest('hex'),
      'X-Taste-Map-Upload-ID': runID,
    }, body: data,
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${response.status} ${body.error ?? response.statusText}`)
  return body
}

async function download(photoID, variant, viewerID) {
  const response = await rawDownload(photoID, variant, viewerID)
  if (!response.ok) throw new Error(`${response.status} ${await response.text()}`)
  return new Uint8Array(await response.arrayBuffer())
}

function rawDownload(photoID, variant, viewerID) {
  return fetch(`${baseURL}/api/v1/photos/${photoID}/content?variant=${variant}`, {
    headers: identityHeaders(viewerID),
  })
}

async function deleteBinary(photoID, viewerID) {
  const response = await fetch(`${baseURL}/api/v1/photos/${photoID}/content`, {
    method: 'DELETE', headers: identityHeaders(viewerID),
  })
  if (!response.ok) throw new Error(`Photo binary cleanup failed (${response.status})`)
}

function findProfile(body, userID) {
  const item = body.profiles?.find((candidate) => candidate.record.userId === userID)
  if (!item) throw new Error(`Profile was not pulled for ${userID}`)
  return item
}

function assertExactPublicKeys(value) {
  const expected = [
    'apiVersion', 'userId', 'displayName', 'bio', 'city', 'avatarPhotoId',
    'avatarPresetId', 'joinedAt', 'statistics',
  ].sort()
  assert(JSON.stringify(Object.keys(value).sort()) === JSON.stringify(expected),
    `Public Profile returned a non-allowlisted shape: ${Object.keys(value).join(',')}`)
  for (const forbidden of [
    'email', 'appleSub', 'authIdentity', 'session', 'refreshToken', 'restaurants', 'visits',
    'companions', 'recommendationSources', 'storageKey', 'remoteRecordData',
  ]) assert(!(forbidden in value), `Public Profile leaked ${forbidden}`)
}

function assertBuffersEqual(actual, expected, message) {
  assert(Buffer.compare(Buffer.from(actual), Buffer.from(expected)) === 0, message)
}

function identityHeaders(viewerID) {
  return { Accept: 'application/json', 'X-Taste-Map-Test-User': viewerID }
}

function jsonHeaders(viewerID) {
  return { ...identityHeaders(viewerID), 'Content-Type': 'application/json' }
}

function nextInstant(offset) {
  return new Date(Date.now() + offset * 1000).toISOString()
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}
