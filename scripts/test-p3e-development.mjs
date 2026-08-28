import { createHash, randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('P3-E Development test only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const city = `P3E-${runID.slice(0, 8)}`
const userA = `p3e:${runID}:a`
const userB = `p3e:${runID}:b`
const userC = `p3e:${runID}:c`
const records = new Map([[userA, []], [userB, []], [userC, []]])
const profileVersions = new Map()
let friendshipID = null

try {
  for (const [userID, name] of [
    [userA, 'P3-E Alpha'], [userB, 'P3-E Beta'], [userC, 'P3-E Gamma'],
  ]) {
    const initial = profileEnvelope(await pull(userID), userID)
    const ack = await push(userID, mutation(
      userID, `profile-${userID.at(-1)}`, 'profile', userID, initial.serverVersion,
      profile(userID, name, 'public'),
    ))
    profileVersions.set(userID, ack.serverVersion)
  }

  const publicRecord = await createRestaurantAndVisit(userA, 'public', 'public', 1)
  const friendsRecord = await createRestaurantAndVisit(userA, 'friends', 'friends', 2)
  await createRestaurantAndVisit(userA, 'private', 'private', 3)
  const publicPhoto = await createPhoto(userA, publicRecord, 'public')
  const friendsPhoto = await createPhoto(userA, friendsRecord, 'friends')
  const privateRecord = records.get(userA).find((item) => item.entityType === 'visit' && item.suffix === 'private')
  const privateRestaurant = records.get(userA).find((item) => item.entityType === 'restaurant' && item.suffix === 'private')
  const privatePhoto = await createPhoto(userA, {
    restaurant: privateRestaurant, visit: privateRecord,
  }, 'private')

  const emptyLegacySearch = await get(userB, '/api/users/search?q=')
  assert(emptyLegacySearch.users.length === 0, 'Legacy search still enumerated users with an empty query')
  assert((await get(userB, `/api/users/search?q=${encodeURIComponent(runID)}`)).users.length === 0,
    'Legacy search exposed internal Taste Map user IDs')
  const search = await get(userB, '/api/v1/social/users/search?q=P3-E%20Alpha')
  assert(search.items.some((item) => item.profile.userId === userA), 'B could not search A by Display Name')
  assertSafePublicDTO(search, 'User Search')

  let page = await get(userB, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits&limit=50`)
  assert(page.items.some((item) => item.visit?.id === publicRecord.visit.entityId), 'B missed A public Visit')
  assert(!page.items.some((item) => item.visit?.id === friendsRecord.visit.entityId), 'Non-friend B received friends-only Visit')
  assert(page.statistics.visibleVisitCount === 1, 'Stranger statistics exposed non-public activity')
  assertSafePublicDTO(page, 'Public Profile content')
  assert((await pull(userB)).restaurants.length === 0, 'Browsing A profile created B Restaurant state')

  assert((await raw(userB, `/api/v1/photos/${publicPhoto.entityId}/content?variant=thumbnail`)).status === 200,
    'B could not read A public Photo')
  assert((await raw(userB, `/api/v1/photos/${friendsPhoto.entityId}/content?variant=thumbnail`)).status === 404,
    'B read friends-only Photo before friendship')
  assert((await raw(userC, `/api/v1/photos/${privatePhoto.entityId}/content?variant=thumbnail`)).status === 404,
    'C read A private Photo by direct ID')

  const requested = await post(userB, '/api/v1/social/friendships', { targetUserId: userA, userId: userC })
  friendshipID = requested.friendship.id
  assert((await raw(userB, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits`)).status === 200,
    'Pending request unexpectedly removed public access')
  page = await get(userB, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits&limit=50`)
  assert(!page.items.some((item) => item.visit?.id === friendsRecord.visit.entityId),
    'Pending request granted friends-only Visit')

  await post(userA, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'accept' })
  page = await get(userB, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits&limit=50`)
  assert(page.items.some((item) => item.visit?.id === friendsRecord.visit.entityId),
    'Accepted friend did not receive friends-only Visit')
  assert(page.statistics.visibleVisitCount === 2, 'Friend statistics did not match authorized records')
  assert((await raw(userB, `/api/v1/photos/${friendsPhoto.entityId}/content?variant=thumbnail`)).status === 200,
    'Accepted friend could not read friends-only Photo')
  assert((await raw(userC, `/api/v1/photos/${friendsPhoto.entityId}/content?variant=thumbnail`)).status === 404,
    'Unrelated C read A friends-only Photo')

  let feed = await get(userB, '/api/v1/community/feed?scope=latest&limit=50')
  assert(feed.items.some((item) => item.visit?.id === friendsRecord.visit.entityId),
    'Friend Community Feed missed friends-only Visit')

  const hiddenPayload = {
    ...friendsRecord.visit.payload,
    visibility: 'private',
    updatedAt: new Date().toISOString(),
  }
  const hiddenAck = await push(userA, mutation(
    userA, 'friends-to-private', 'visit', friendsRecord.visit.entityId,
    friendsRecord.visit.serverVersion, hiddenPayload,
  ))
  friendsRecord.visit.serverVersion = hiddenAck.serverVersion
  friendsRecord.visit.payload = hiddenPayload
  page = await get(userB, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits&limit=50`)
  feed = await get(userB, '/api/v1/community/feed?scope=latest&limit=50')
  assert(!page.items.some((item) => item.visit?.id === friendsRecord.visit.entityId),
    'Visibility friends→private remained on Public Profile')
  assert(!feed.items.some((item) => item.visit?.id === friendsRecord.visit.entityId),
    'Visibility friends→private remained in Community Feed')
  assert((await raw(userB, `/api/v1/photos/${friendsPhoto.entityId}/content?variant=thumbnail`)).status === 404,
    'Visit visibility change did not revoke Photo access')

  const profileAck = await push(userA, mutation(
    userA, 'profile-refresh', 'profile', userA, profileVersions.get(userA),
    { ...profile(userA, 'P3-E Alpha Updated', 'public'), bio: 'Updated P3-E biography' },
  ))
  profileVersions.set(userA, profileAck.serverVersion)
  const updatedSearch = await get(userB, '/api/v1/social/users/search?q=Alpha%20Updated')
  assert(updatedSearch.items[0]?.profile.bio === 'Updated P3-E biography',
    'Profile edit did not propagate to Search projection')
  const updatedFeed = await get(userB, '/api/v1/community/feed?scope=latest&limit=50')
  assert(updatedFeed.items.find((item) => item.user.userId === userA)?.user.displayName === 'P3-E Alpha Updated',
    'Profile edit did not propagate to Community projection')

  const bWant = await createRestaurant(userB, 'explicit-want', 'wantToGo', 0,
    publicRecord.restaurant.payload.placeIdentities[0].externalId)
  const discovery = await get(userB, `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}&limit=50`)
  const sharedCard = discovery.items.find((item) => item.restaurant.placeIdentities.some((identity) =>
    identity.externalId === publicRecord.restaurant.payload.placeIdentities[0].externalId))
  assert(sharedCard?.viewerState === 'want_to_go', 'Global identity did not preserve B explicit WantToGo state')
  assert(!JSON.stringify(sharedCard).includes('Private Companion'), 'A private Visit context copied into B WantToGo')
  assert(bWant.entityId !== publicRecord.restaurant.entityId, 'User-specific Restaurant state reused A owner ID')

  await post(userB, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'remove' })
  friendshipID = null
  assert((await raw(userB, `/api/v1/photos/${friendsPhoto.entityId}/content?variant=thumbnail`)).status === 404,
    'Unfriend did not immediately revoke friends-only Photo')
  assert((await raw(userC, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits`)).status === 200,
    'C unexpectedly lost ordinary public access')
  const cPage = await get(userC, `/api/v1/community/users/${encodeURIComponent(userA)}/content?section=visits&limit=50`)
  assert(cPage.items.every((item) => item.visit?.visibility === 'public'),
    'C received restricted A content')

  const deleteAck = await push(userA, deletion(
    userA, 'public-tombstone', 'visit', publicRecord.visit.entityId, publicRecord.visit.serverVersion,
  ))
  publicRecord.visit.deleted = true
  publicRecord.visit.serverVersion = deleteAck.serverVersion
  feed = await get(userC, '/api/v1/community/feed?scope=latest&limit=50')
  assert(!feed.items.some((item) => item.visit?.id === publicRecord.visit.entityId),
    'Visit tombstone remained visible to another client')

  console.log(JSON.stringify({
    result: 'P3-E Development three-user Social E2E passed', baseURL, city,
    users: { A: userA, B: userB, C: userC },
    publicProfileAllowlist: true, statisticsNoSideChannel: true,
    searchNoEnumeration: true, pendingIsNotFriend: true, acceptedFriendVisibility: true,
    visibilityChangeImmediate: true, unfriendImmediate: true, directPhotoIDDenied: true,
    communityServerFiltered: true, profileProjectionRefresh: true,
    globalRestaurantIdentity: true, explicitWantToGoIsViewerOwned: true,
    tombstoneConverged: true, productionAccessed: false,
    cleanup: 'finally tombstones isolated records, removes relationships, deletes R2 bytes, and makes test profiles private',
  }, null, 2))
} finally {
  await cleanup().catch((error) => {
    console.error(`P3-E cleanup failed: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}

async function createRestaurantAndVisit(userID, suffix, visibility, minutesAgo) {
  const restaurant = await createRestaurant(userID, suffix, 'visited', minutesAgo)
  const timestamp = new Date(Date.now() - minutesAgo * 60_000).toISOString()
  const payload = {
    schemaVersion: 1, id: `p3e-visit-${runID}-${suffix}`, userId: 'forged-owner',
    restaurantId: restaurant.entityId, visitedAt: timestamp, diningMode: 'dine_in', visibility,
    partySize: 2, totalPrice: 688, paymentMode: null, pricePerPerson: null,
    queueDuration: null, diningOccasions: [], diningOccasionText: null, rating: 4.5,
    valueRating: null, environmentRating: null, serviceRating: null, valueTags: [],
    environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null,
    portionLevel: null, transportConvenience: null, specialNotes: 'private context',
    companions: ['Private Companion'], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: 'friend', recommendationSourceUserId: null,
    recommendationSourceText: 'Private Source', sharedMealId: null,
    note: `${suffix} visible note`, myActualSpend: 688,
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `visit-${suffix}`, 'visit', payload.id, 0, payload))
  const visit = { entityType: 'visit', entityId: payload.id, suffix, payload, serverVersion: ack.serverVersion, deleted: false }
  records.get(userID).push(visit)
  return { restaurant, visit }
}

async function createRestaurant(userID, suffix, status, minutesAgo, identity) {
  const timestamp = new Date(Date.now() - minutesAgo * 60_000).toISOString()
  const payload = {
    schemaVersion: 1, id: `p3e-restaurant-${runID}-${userID.at(-1)}-${suffix}`,
    userId: 'forged-owner', name: `P3-E ${suffix}`, address: `${city} Development D1 only`,
    city, latitude: 30.2 + suffix.length / 10_000, longitude: 120.1 + suffix.length / 10_000,
    status, preferenceLevel: 'normal', overallRating: null, foodRating: null,
    environmentRating: null, serviceRating: null, valueRating: null, tags: ['P3-E'],
    longTermNote: '', pricePerPerson: null, phone: null, openingHours: null,
    markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍜',
    placeIdentities: [{ provider: 'apple_maps', externalId: identity ?? `apple-p3e-${runID}-${suffix}`,
      isPrimary: true, createdAt: timestamp, updatedAt: timestamp }],
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `restaurant-${suffix}`, 'restaurant', payload.id, 0, payload))
  const record = { entityType: 'restaurant', entityId: payload.id, suffix, payload, serverVersion: ack.serverVersion, deleted: false }
  records.get(userID).push(record)
  return record
}

async function createPhoto(userID, source, visibility) {
  const id = randomUUID()
  const bytes = new TextEncoder().encode(`Taste Map P3-E ${visibility} ${runID}`)
  const upload = await jsonRequest(userID, `/api/v1/photos/${id}/content?variant=thumbnail`, {
    method: 'PUT', headers: {
      'Content-Type': 'image/jpeg',
      'X-Taste-Map-Content-SHA256': createHash('sha256').update(bytes).digest('hex'),
    }, body: bytes,
  })
  const timestamp = new Date().toISOString()
  const payload = {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: source.restaurant.entityId,
    visitId: source.visit.entityId, dishId: null, kind: 'visit', storageProvider: 'r2',
    storageKey: upload.storageKey, providerAccountId: null, thumbnailStorageKey: upload.storageKey,
    fileName: `p3e-${visibility}.jpg`, mimeType: 'image/jpeg', byteSize: bytes.byteLength,
    width: 320, height: 240, sortOrder: 0, visibility,
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `photo-${visibility}`, 'photo', id, 0, payload))
  const record = { entityType: 'photo', entityId: id, suffix: visibility, payload, serverVersion: ack.serverVersion, deleted: false }
  records.get(userID).push(record)
  return record
}

async function cleanup() {
  if (friendshipID) await raw(userB, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, 'POST', { action: 'remove' })
  for (const userID of [userA, userB, userC]) {
    for (const type of ['photo', 'visit', 'restaurant']) {
      for (const record of records.get(userID).filter((item) => item.entityType === type && !item.deleted)) {
        const ack = await push(userID, deletion(
          userID, `cleanup-${type}-${record.entityId}`, type, record.entityId, record.serverVersion,
        ))
        if (ack.status !== 'applied') throw new Error(`Cleanup failed for ${type}:${record.entityId}`)
        record.deleted = true
        if (type === 'photo') await raw(userID, `/api/v1/photos/${record.entityId}/content`, 'DELETE')
      }
    }
    const version = profileVersions.get(userID)
    if (version !== undefined) await push(userID, mutation(
      userID, 'cleanup-profile-private', 'profile', userID, version,
      profile(userID, 'P3-E Development Test', 'private'),
    ))
  }
}

function profileEnvelope(body, userID) {
  const value = body.profiles.find((item) => item.record.userId === userID)
  if (!value) throw new Error(`Profile bootstrap missing for ${userID}`)
  return value
}
function profile(userID, displayName, visibility) {
  const timestamp = new Date().toISOString()
  return { schemaVersion: 1, userId: userID, displayName, bio: 'P3-E Development E2E',
    city, avatarPhotoId: null, avatarPresetId: 'otter', visibility,
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null }
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
  const body = await post(userID, '/api/v1/sync/push', {
    apiVersion: 1, schemaVersion: 1, mutations: [item],
  })
  const ack = body.acknowledgements[0]
  if (!ack || ack.status !== 'applied') {
    throw new Error(`Mutation ${item.mutationId} failed: ${ack?.conflictReason ?? 'missing'}`)
  }
  return ack
}
function pull(userID) { return get(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200') }
function get(userID, path) { return checked(userID, path) }
function post(userID, path, body) { return checked(userID, path, 'POST', body) }
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
function assertSafePublicDTO(value, label) {
  const text = JSON.stringify(value)
  for (const forbidden of [
    'appleSub', 'authSubject', 'identityToken', 'accessToken', 'refreshToken',
    'storageKey', 'remoteRecordData', 'myActualSpend', 'Private Companion', 'Private Source',
  ]) assert(!text.includes(forbidden), `${label} leaked ${forbidden}`)
}
function assert(condition, message) { if (!condition) throw new Error(message) }
