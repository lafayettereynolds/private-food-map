import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('Task 09 Development smoke only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const userA = `task09:${runID}:a`
const userB = `task09:${runID}:b`
const restaurantID = `task09-restaurant-${runID}`
const visitID = `task09-visit-${runID}`
const listID = `task09-list-${runID}`
const itemID = `task09-item-${runID}`
const versions = { profiles: new Map(), restaurant: 0, visit: 0, list: 0, item: 0 }
let restaurantDeleted = false
let visitDeleted = false
let listDeleted = false

try {
  for (const [userID, name] of [[userA, 'Task 09 Share Owner'], [userB, 'Task 09 Other User']]) {
    const initial = profileEnvelope(await pull(userID), userID)
    const ack = await push(userID, mutation(`profile-${userID.at(-1)}`, 'profile', userID, initial.serverVersion,
      profile(userID, name, 'public')))
    versions.profiles.set(userID, ack.serverVersion)
  }

  versions.restaurant = (await push(userA, mutation('restaurant-create', 'restaurant', restaurantID, 0,
    restaurantPayload()))).serverVersion
  versions.visit = (await push(userA, mutation('visit-create', 'visit', visitID, 0,
    visitPayload('public')))).serverVersion
  versions.list = (await push(userA, mutation('list-create', 'restaurantList', listID, 0,
    listPayload('public')))).serverVersion
  versions.item = (await push(userA, mutation('item-create', 'restaurantListItem', itemID, 0,
    listItemPayload()))).serverVersion

  const restaurantShare = await post(userA, '/api/v1/public-shares', {
    entityType: 'restaurant', entityId: restaurantID,
  })
  const restaurantRetry = await post(userA, '/api/v1/public-shares', {
    entityType: 'restaurant', entityId: restaurantID,
  })
  assert(restaurantShare.shareId === restaurantRetry.shareId, 'Restaurant public URL was not stable')
  assert(restaurantShare.url === `${baseURL}/share/${restaurantShare.shareId}`, 'Public URL origin is incorrect')
  assert(!restaurantShare.url.includes(restaurantID) && restaurantShare.shareId.length === 32,
    'Public URL exposed an internal Restaurant ID')
  const restaurantPublic = await anonymous(`/api/public/shares/${restaurantShare.shareId}`)
  assert(restaurantPublic.entity.name === 'Task 09 Apple-only 餐厅', 'Public Restaurant projection missing')
  for (const forbidden of [userA, restaurantID, visitID, 'apple-task09-', 'private note']) {
    assert(!JSON.stringify(restaurantPublic).includes(forbidden), `Restaurant public DTO leaked ${forbidden}`)
  }

  const profileShare = await post(userA, '/api/v1/public-shares', { entityType: 'profile', entityId: userA })
  const profilePublic = await anonymous(`/api/public/shares/${profileShare.shareId}`)
  assert(profilePublic.entity.displayName === 'Task 09 Share Owner', 'Public Profile projection missing')
  assert(!JSON.stringify(profilePublic).includes(userA), 'Public Profile leaked Taste Map user ID')

  const listShare = await post(userA, '/api/v1/public-shares', { entityType: 'list', entityId: listID })
  const listPublic = await anonymous(`/api/public/shares/${listShare.shareId}`)
  assert(listPublic.entity.restaurants.length === 1, 'Public List projection missed its Restaurant')
  assert(!JSON.stringify(listPublic).includes('apple_maps:'), 'Public List leaked Global Restaurant Identity')

  const forged = await raw(userB, '/api/v1/public-shares', 'POST', {
    entityType: 'restaurant', entityId: restaurantID,
  })
  assert(forged.status === 404, 'User B issued a public link for User A content')

  versions.visit = (await push(userA, mutation('visit-private', 'visit', visitID, versions.visit,
    visitPayload('private')))).serverVersion
  assert((await raw('', `/api/public/shares/${restaurantShare.shareId}`)).status === 404,
    'Restaurant public link remained readable after Visit privacy revocation')
  versions.list = (await push(userA, mutation('list-private', 'restaurantList', listID, versions.list,
    listPayload('private')))).serverVersion
  assert((await raw('', `/api/public/shares/${listShare.shareId}`)).status === 404,
    'List public link remained readable after privacy revocation')

  console.log(JSON.stringify({
    result: 'Task 09 Development Share Extension/Public Sharing smoke passed',
    baseURL, stableOpaqueURL: true, appleMapsOnly: true, profileShare: true,
    restaurantShare: true, listShare: true, dynamicPrivacyRevocation: true,
    forgedOwnerDenied: true, anonymousAllowlist: true, productionAccessed: false,
    cleanup: 'finally tombstones isolated records and returns profiles private',
  }, null, 2))
} finally {
  await cleanup().catch((error) => {
    console.error(`Task 09 cleanup failed: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}

async function cleanup() {
  if (!listDeleted && versions.list > 0) {
    const response = await rawPush(userA, deletion('cleanup-list', 'restaurantList', listID, versions.list))
    listDeleted = response.ok
  }
  if (!visitDeleted && versions.visit > 0) {
    const response = await rawPush(userA, deletion('cleanup-visit', 'visit', visitID, versions.visit))
    visitDeleted = response.ok
  }
  if (!restaurantDeleted && versions.restaurant > 0) {
    const response = await rawPush(userA, deletion('cleanup-restaurant', 'restaurant', restaurantID, versions.restaurant))
    restaurantDeleted = response.ok
  }
  for (const userID of [userA, userB]) {
    const version = versions.profiles.get(userID)
    if (version) await push(userID, mutation(`cleanup-profile-${userID.at(-1)}`, 'profile', userID, version,
      profile(userID, 'Task 09 Development User', 'private')))
  }
}

function profileEnvelope(body, userID) {
  const value = body.profiles.find((entry) => entry.record.userId === userID)
  if (!value) throw new Error(`Profile bootstrap missing for ${userID}`)
  return value
}

function profile(userID, displayName, visibility) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, userId: userID, displayName, bio: 'Task 09 Development', city: '杭州',
    avatarPhotoId: null, avatarPresetId: 'otter', visibility, createdAt: now, updatedAt: now, deletedAt: null }
}

function restaurantPayload() {
  const now = new Date().toISOString()
  return { schemaVersion: 1, id: restaurantID, userId: 'forged-owner', name: 'Task 09 Apple-only 餐厅',
    address: 'Development D1 only', city: '杭州', latitude: 30.25, longitude: 120.16,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null,
    environmentRating: null, serviceRating: null, valueRating: null, tags: ['日料'], longTermNote: '',
    pricePerPerson: null, phone: null, openingHours: null, markerType: 'emoji', markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: '🍣', placeIdentities: [{
      provider: 'apple_maps', externalId: `apple-task09-${runID}`, isPrimary: true, createdAt: now, updatedAt: now,
    }], createdAt: now, updatedAt: now, deletedAt: null }
}

function visitPayload(visibility) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, id: visitID, userId: 'forged-owner', restaurantId: restaurantID,
    visitedAt: now, diningMode: 'dine_in', visibility, partySize: 2, totalPrice: null,
    paymentMode: null, pricePerPerson: null, queueDuration: null, diningOccasions: [],
    diningOccasionText: null, rating: 4.5, valueRating: null, environmentRating: null,
    serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null,
    diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: null,
    companions: [], companionIds: [], recommendationSourceId: null, recommendationSourceType: null,
    recommendationSourceUserId: null, recommendationSourceText: null, sharedMealId: null,
    note: 'private note must never leak', myActualSpend: null, createdAt: now, updatedAt: now, deletedAt: null }
}

function listPayload(visibility) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, id: listID, userId: 'forged-owner', title: 'Task 09 公开榜单',
    description: 'Development public list', visibility, isRanked: true, coverMode: 'automatic',
    customCoverPhotoId: null, createdAt: now, updatedAt: now, deletedAt: null }
}

function listItemPayload() {
  const now = new Date().toISOString()
  const externalId = `apple-task09-${runID}`
  return { schemaVersion: 1, id: itemID, userId: 'forged-owner', listId: listID,
    restaurantId: restaurantID, restaurantGlobalKey: `apple_maps:${externalId}`, position: 0,
    note: '值得回去', restaurant: { globalKey: `apple_maps:${externalId}`, restaurantId: restaurantID,
      placeIdentities: [{ provider: 'apple_maps', externalId, isPrimary: true }],
      name: 'Task 09 Apple-only 餐厅', address: 'Development D1 only', city: '杭州',
      latitude: 30.25, longitude: 120.16, markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍣' },
    createdAt: now, updatedAt: now, deletedAt: null }
}

function mutation(suffix, entityType, entityId, baseVersion, payload) {
  return { mutationId: `${runID}:${suffix}`, entityType, entityId, operation: 'upsert', baseVersion,
    clientTimestamp: payload.updatedAt, payload }
}
function deletion(suffix, entityType, entityId, baseVersion) {
  return { mutationId: `${runID}:${suffix}`, entityType, entityId, operation: 'delete', baseVersion,
    clientTimestamp: new Date().toISOString() }
}
async function push(userID, item) {
  const response = await post(userID, '/api/v1/sync/push', { apiVersion: 1, schemaVersion: 1, mutations: [item] })
  const ack = response.acknowledgements[0]
  if (!ack || ack.status !== 'applied') throw new Error(`Mutation failed: ${ack?.conflictReason ?? 'missing ack'}`)
  return ack
}
async function rawPush(userID, item) {
  return raw(userID, '/api/v1/sync/push', 'POST', { apiVersion: 1, schemaVersion: 1, mutations: [item] })
}
function pull(userID) { return get(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200') }
function get(userID, path) { return checked(userID, path) }
function post(userID, path, body) { return checked(userID, path, 'POST', body) }
async function anonymous(path) { return checked('', path) }
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
