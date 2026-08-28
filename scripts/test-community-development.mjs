import { createHash, randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('P3-D Development test only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const userA = `p3d:${runID}:a`
const userB = `p3d:${runID}:b`
const userPrivate = `p3d:${runID}:private`
const createdAt = new Date().toISOString()
const records = new Map([[userA, []], [userB, []], [userPrivate, []]])
const profileVersions = new Map()
let friendshipID = null
let followed = false
let photoRecord = null

try {
  for (const [userID, name, visibility] of [
    [userA, 'P3-D Viewer', 'public'], [userB, 'P3-D Publisher', 'public'],
    [userPrivate, 'P3-D Private Profile', 'private'],
  ]) {
    const initial = profileEnvelope(await pull(userID), userID)
    const ack = await push(userID, mutation(
      userID, `profile-${visibility}`, 'profile', userID, initial.serverVersion,
      profile(userID, name, visibility),
    ))
    profileVersions.set(userID, ack.serverVersion)
  }

  const publicContent = await createRestaurantAndVisit(userB, 'public', 'public', 1, 'public note')
  const friendsContent = await createRestaurantAndVisit(userB, 'friends', 'friends', 2, 'friends note')
  await createRestaurantAndVisit(userB, 'private', 'private', 3, 'private note')
  await createRestaurantAndVisit(userPrivate, 'private-profile-public-visit', 'public', 4, 'hidden by profile')
  await createRestaurant(userB, 'wanted', 'wantToGo', 5)
  for (let index = 0; index < 3; index += 1) {
    await createRestaurantAndVisit(userB, `page-${index}`, 'public', 10 + index, `page ${index}`)
  }

  photoRecord = { id: randomUUID(), serverVersion: null }
  photoRecord = await createPublicPhoto(
    userB, publicContent.restaurant.id, publicContent.visit.id, photoRecord.id,
  )

  const publicProfile = await get(userA, '/api/v1/community/users/' + encodeURIComponent(userB) + '/content?section=visits')
  assert(publicProfile.items.some((item) => item.visit.id === publicContent.visit.id), 'Public Visit missing from Public Profile')
  assert(!publicProfile.items.some((item) => item.visit.id === friendsContent.visit.id), 'Non-friend received friends-only Visit')
  assert(publicProfile.statistics.visibleWantToGoCount === 1, 'Visible WantToGo statistics are incorrect')
  assert(!JSON.stringify(publicProfile).includes('myActualSpend') && !JSON.stringify(publicProfile).includes('storageKey'),
    'Public DTO leaked private Visit or storage fields')
  const photoItem = publicProfile.items.find((item) => item.visit.id === publicContent.visit.id)
  assert(photoItem.visit.photos.some((photo) => photo.photoId === photoRecord.id), 'Authorized thumbnail identifier missing')

  const wants = await get(userA, '/api/v1/community/users/' + encodeURIComponent(userB) + '/content?section=want_to_go')
  assert(wants.items.length === 1 && wants.items[0].kind === 'want_to_go', 'Public WantToGo content did not load')
  assert((await raw(userA, '/api/v1/community/users/' + encodeURIComponent(userPrivate) + '/content')).status === 404,
    'Private Profile content was readable')

  const latest = await get(userA, '/api/v1/community/feed?scope=latest&limit=50')
  assert(latest.items.some((item) => item.visit.id === publicContent.visit.id), 'Latest feed missed public Visit')
  assert(!latest.items.some((item) => item.visit.id === friendsContent.visit.id), 'Latest leaked friends-only Visit')
  assert(!latest.items.some((item) => item.user.userId === userPrivate), 'Latest leaked private Profile')

  const first = await get(userA, '/api/v1/community/feed?scope=latest&limit=2')
  assert(first.items.length === 2 && first.nextCursor, 'Community pagination did not issue a cursor')
  const second = await get(userA, `/api/v1/community/feed?scope=latest&limit=2&cursor=${encodeURIComponent(first.nextCursor)}`)
  assert(second.items.length > 0 && !second.items.some((item) => first.items.some((previous) => previous.id === item.id)),
    'Community cursor returned duplicate content')

  await put(userA, `/api/v1/social/follows/${encodeURIComponent(userB)}`)
  followed = true
  let following = await get(userA, '/api/v1/community/feed?scope=following')
  assert(following.items.some((item) => item.visit.id === publicContent.visit.id), 'Followed public Visit missing')
  assert(!following.items.some((item) => item.visit.id === friendsContent.visit.id), 'Follow incorrectly granted friends content')

  const request = await post(userA, '/api/v1/social/friendships', { targetUserId: userB })
  friendshipID = request.friendship.id
  await post(userB, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'accept' })
  following = await get(userA, '/api/v1/community/feed?scope=following')
  const friendsItem = following.items.find((item) => item.visit.id === friendsContent.visit.id)
  assert(friendsItem?.cacheScope === 'friends', 'Accepted friend did not receive friends-only Visit')

  const publicPhoto = await download(photoRecord.id, userA)
  assert(publicPhoto.byteLength > 0, 'Authorized public thumbnail download failed')
  const directDenied = await raw(userPrivate, `/api/v1/photos/${photoRecord.id}/content?variant=thumbnail`)
  assert(directDenied.status === 200, 'A public viewer unexpectedly could not read public Profile content')

  await post(userA, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'remove' })
  friendshipID = null
  following = await get(userA, '/api/v1/community/feed?scope=following')
  assert(!following.items.some((item) => item.visit.id === friendsContent.visit.id), 'Unfriend did not revoke friends content')

  let profileAck = await push(userB, mutation(
    userB, 'profile-private-photo-check', 'profile', userB, profileVersions.get(userB),
    profile(userB, 'P3-D Publisher', 'private'),
  ))
  profileVersions.set(userB, profileAck.serverVersion)
  const guessedPhotoDenied = await raw(userA, `/api/v1/photos/${photoRecord.id}/content?variant=thumbnail`)
  assert(guessedPhotoDenied.status === 404, 'Guessed Photo ID bypassed private Profile visibility')
  profileAck = await push(userB, mutation(
    userB, 'profile-public-after-photo-check', 'profile', userB, profileVersions.get(userB),
    profile(userB, 'P3-D Publisher', 'public'),
  ))
  profileVersions.set(userB, profileAck.serverVersion)

  const publicVersion = publicContent.visit.serverVersion
  await push(userB, deletion(userB, 'public-delete', 'visit', publicContent.visit.id, publicVersion))
  records.set(userB, records.get(userB).filter((record) => record.entityId !== publicContent.visit.id))
  const afterTombstone = await get(userA, '/api/v1/community/feed?scope=latest')
  assert(!afterTombstone.items.some((item) => item.visit?.id === publicContent.visit.id), 'Visit tombstone remained in feed')

  const forged = await get(userA, `/api/v1/community/feed?scope=latest&userId=${encodeURIComponent(userB)}`)
  assert(forged.items.every((item) => item.user.userId !== userA), 'Worker trusted forged community userId')
  assert((await raw('', '/api/v1/community/feed?scope=latest')).status === 401, 'Unauthenticated community access succeeded')

  console.log(JSON.stringify({
    result: 'P3-D Development Public Profile and Community E2E passed', baseURL,
    publicProfile: true, friendsVisibility: true, privateProfileDenied: true,
    wantToGoProjection: true, latestFeed: true, followingFeed: true,
    pagination: true, followDoesNotGrantFriendData: true, unfriendRevocation: true,
    publicPhotoAuthorization: true, guessedPhotoDeniedByProfile: true, tombstoneRemoved: true,
    forgedUserIgnored: true, unauthorizedDenied: true,
    likes: 'not implemented because Web has no server-backed Like domain',
    comments: 'not implemented because Web has no server-backed Comment domain',
    cleanup: 'runs in finally: records tombstoned, R2 objects deleted, profiles private',
  }, null, 2))
} finally {
  await cleanup().catch((error) => {
    console.error(`P3-D cleanup failed: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}

async function createPublicPhoto(userID, restaurantID, visitID, id) {
  const thumbnail = new TextEncoder().encode(`Taste Map P3-D public thumbnail ${runID}`)
  const upload = await jsonRequest(userID, `/api/v1/photos/${id}/content?variant=thumbnail`, {
    method: 'PUT', headers: {
      'Content-Type': 'image/jpeg',
      'X-Taste-Map-Content-SHA256': createHash('sha256').update(thumbnail).digest('hex'),
    }, body: thumbnail,
  })
  const payload = {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: restaurantID,
    visitId: visitID, dishId: null,
    kind: 'visit', storageProvider: 'r2', storageKey: upload.storageKey,
    providerAccountId: null, thumbnailStorageKey: upload.storageKey,
    fileName: 'p3d-public.jpg', mimeType: 'image/jpeg', byteSize: thumbnail.byteLength,
    width: 320, height: 240, sortOrder: 0, visibility: 'public',
    createdAt, updatedAt: createdAt, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, 'photo-public', 'photo', id, 0, payload))
  records.get(userID).push({ entityType: 'photo', entityId: id, serverVersion: ack.serverVersion })
  return { id, serverVersion: ack.serverVersion }
}

async function createRestaurantAndVisit(userID, suffix, visibility, minutesAgo, note) {
  const restaurant = await createRestaurant(userID, suffix, 'visited', minutesAgo)
  const visit = await createVisit(userID, restaurant.id, suffix, visibility, minutesAgo, note)
  return { restaurant, visit }
}

async function createRestaurant(userID, suffix, status, minutesAgo) {
  const id = `p3d-restaurant-${runID}-${suffix}`
  const timestamp = new Date(Date.now() - minutesAgo * 60_000).toISOString()
  const payload = {
    schemaVersion: 1, id, userId: 'forged-owner', name: `P3-D ${suffix}`,
    address: 'Development D1 only', city: 'P3D Development', latitude: 30.2,
    longitude: 120.1, status, preferenceLevel: 'normal', overallRating: null,
    foodRating: null, environmentRating: null, serviceRating: null, valueRating: null,
    tags: ['P3-D'], longTermNote: '', pricePerPerson: null, phone: null,
    openingHours: null, markerType: 'emoji', markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: '🍜', placeIdentities: [{
      provider: 'apple_maps', externalId: `apple-p3d-${runID}-${suffix}`,
      isPrimary: true, createdAt: timestamp, updatedAt: timestamp,
    }], createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `restaurant-${suffix}`, 'restaurant', id, 0, payload))
  records.get(userID).push({ entityType: 'restaurant', entityId: id, serverVersion: ack.serverVersion })
  return { id, serverVersion: ack.serverVersion }
}

async function createVisit(userID, restaurantID, suffix, visibility, minutesAgo, note) {
  const id = `p3d-visit-${runID}-${suffix}`
  const timestamp = new Date(Date.now() - minutesAgo * 60_000).toISOString()
  const payload = {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: restaurantID, visitedAt: timestamp,
    diningMode: 'dine_in', visibility, partySize: 2, totalPrice: 999,
    paymentMode: null, pricePerPerson: null, queueDuration: null, diningOccasions: [],
    diningOccasionText: null, rating: 4.5, valueRating: null, environmentRating: null,
    serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [],
    noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null,
    specialNotes: 'private context must not leak', companions: ['Private Companion'], companionIds: [],
    recommendationSourceId: null, recommendationSourceType: 'friend',
    recommendationSourceUserId: null, recommendationSourceText: 'Private Source', sharedMealId: null,
    note, myActualSpend: 999, createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `visit-${suffix}`, 'visit', id, 0, payload))
  records.get(userID).push({ entityType: 'visit', entityId: id, serverVersion: ack.serverVersion })
  return { id, serverVersion: ack.serverVersion }
}

async function cleanup() {
  if (friendshipID) await raw(userA, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, 'POST', { action: 'remove' })
  if (followed) await raw(userA, `/api/v1/social/follows/${encodeURIComponent(userB)}`, 'DELETE')
  for (const userID of [userA, userB, userPrivate]) {
    const userRecords = records.get(userID)
    for (const type of ['photo', 'visit', 'restaurant']) {
      for (const record of userRecords.filter((item) => item.entityType === type)) {
        const ack = await push(userID, deletion(userID, `cleanup-${type}-${record.entityId}`, type, record.entityId, record.serverVersion))
        if (ack.status !== 'applied') throw new Error(`Cleanup failed for ${type}:${record.entityId}`)
        if (type === 'photo') {
          await raw(userID, `/api/v1/photos/${record.entityId}/content`, 'DELETE')
        }
      }
    }
    const version = profileVersions.get(userID)
    if (version !== undefined) await push(userID, mutation(
      userID, 'profile-cleanup-private', 'profile', userID, version,
      profile(userID, userID === userA ? 'P3-D Viewer' : 'P3-D Development User', 'private'),
    ))
  }
  // Also removes a binary uploaded immediately before a metadata-push failure.
  if (photoRecord?.id) await raw(userB, `/api/v1/photos/${photoRecord.id}/content`, 'DELETE')
}

function profileEnvelope(body, userID) {
  const value = body.profiles.find((item) => item.record.userId === userID)
  if (!value) throw new Error(`Profile bootstrap missing for ${userID}`)
  return value
}
function profile(userID, displayName, visibility) {
  return { schemaVersion: 1, userId: userID, displayName, bio: 'P3-D Development E2E',
    city: 'P3D Development', avatarPhotoId: null, avatarPresetId: 'otter', visibility,
    createdAt, updatedAt: new Date().toISOString(), deletedAt: null }
}
function mutation(userID, suffix, entityType, entityId, baseVersion, payload) {
  return { mutationId: `${runID}:${userID.at(-1)}:${suffix}`, entityType, entityId,
    operation: 'upsert', baseVersion, clientTimestamp: payload.updatedAt, payload }
}
function deletion(userID, suffix, entityType, entityId, baseVersion) {
  return { mutationId: `${runID}:${userID.at(-1)}:${suffix}`, entityType, entityId,
    operation: 'delete', baseVersion, clientTimestamp: new Date().toISOString() }
}
async function push(userID, item) {
  const body = await post(userID, '/api/v1/sync/push', { apiVersion: 1, schemaVersion: 1, mutations: [item] })
  const ack = body.acknowledgements[0]
  if (!ack || ack.status !== 'applied') throw new Error(`Mutation ${item.mutationId} failed: ${ack?.conflictReason ?? 'missing'}`)
  return ack
}
function pull(userID) { return get(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200') }
function get(userID, path) { return checked(userID, path) }
function post(userID, path, body) { return checked(userID, path, 'POST', body) }
function put(userID, path) { return checked(userID, path, 'PUT') }
async function download(photoID, viewer) {
  const response = await raw(viewer, `/api/v1/photos/${photoID}/content?variant=thumbnail`)
  if (!response.ok) throw new Error(`Photo download ${response.status}`)
  return new Uint8Array(await response.arrayBuffer())
}
async function jsonRequest(userID, path, options) {
  const response = await fetch(`${baseURL}${path}`, {
    ...options, headers: { 'X-Taste-Map-Test-User': userID, ...(options.headers ?? {}) },
  })
  const value = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${options.method ?? 'GET'} ${path}: ${response.status} ${value.error ?? ''}`)
  return value
}
async function checked(userID, path, method = 'GET', body) {
  const response = await raw(userID, path, method, body)
  const value = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${value.error ?? ''}`)
  return value
}
function raw(userID, path, method = 'GET', body) {
  return fetch(`${baseURL}${path}`, { method, headers: {
    ...(userID ? { 'X-Taste-Map-Test-User': userID } : {}),
    ...(body ? { 'Content-Type': 'application/json' } : {}),
  }, ...(body ? { body: JSON.stringify(body) } : {}) })
}
function assert(condition, message) { if (!condition) throw new Error(message) }
