import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('P3-B Development test only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const userA = `p3b:${runID}:a`
const userB = `p3b:${runID}:b`
const userC = `p3b:${runID}:c`
const at = new Date().toISOString()
const restaurantID = `p3b-restaurant-${runID}`
const visitID = `p3b-visit-${runID}`
const companionID = `p3b-companion-${runID}`

const initialA = profileEnvelope(await pull(userA), userA)
const initialB = profileEnvelope(await pull(userB), userB)
const initialC = profileEnvelope(await pull(userC), userC)
let versionA = (await push(userA, profileMutation(userA, initialA.serverVersion, 'P3-B Alpha', '杭州', 'public', 'profile-a-public'))).serverVersion
let versionB = (await push(userB, profileMutation(userB, initialB.serverVersion, 'P3-B Beta', '上海', 'public', 'profile-b-public'))).serverVersion
let versionC = (await push(userC, profileMutation(userC, initialC.serverVersion, 'P3-B Gamma', '杭州', 'public', 'profile-c-public'))).serverVersion

const firstSearch = await get(userA, '/api/v1/social/users/search?q=P3-B&limit=1')
assert(firstSearch.items.length === 1 && firstSearch.nextCursor, 'Search pagination did not return a first cursor')
const secondSearch = await get(userA, `/api/v1/social/users/search?q=P3-B&limit=1&cursor=${encodeURIComponent(firstSearch.nextCursor)}`)
assert(secondSearch.items.length === 1 && secondSearch.items[0].profile.userId !== firstSearch.items[0].profile.userId,
  'Search cursor repeated the first result')
const betaSearch = await get(userA, '/api/v1/social/users/search?q=Beta')
assert(betaSearch.items.some((item) => item.profile.userId === userB), 'A could not search B by Display Name')
assert(!JSON.stringify(betaSearch).includes('email') && !JSON.stringify(betaSearch).includes('authSubject'),
  'Search response leaked a private identity field')
assert((await raw(userA, '/api/v1/social/users/search?q=')).status === 400,
  'Empty query enumerated Development users')

versionB = (await push(userB, profileMutation(userB, versionB, 'P3-B Beta', '上海', 'friends', 'profile-b-friends'))).serverVersion
const restaurantAck = await push(userB, mutation('restaurant-create', 'restaurant', restaurantID, 0, restaurant()))
const visitAck = await push(userB, mutation('visit-create', 'visit', visitID, 0, visit()))

const requested = await post(userA, '/api/v1/social/friendships', { targetUserId: userB, actorUserId: userC })
const repeated = await post(userA, '/api/v1/social/friendships', { targetUserId: userB })
assert(repeated.duplicate === true && repeated.friendship.id === requested.friendship.id,
  'Duplicate friend request created a second logical relation')
assert((await raw(userA, `/api/v1/social/users/${encodeURIComponent(userB)}/context`)).status === 404,
  'Pending request granted friends-only Profile access')
const incoming = await get(userB, '/api/v1/social/friendships?scope=incoming')
assert(incoming.items.some((item) => item.profile.userId === userA && item.friendshipState === 'incoming_request'),
  'B did not receive A request')
assert((await raw(userC, `/api/v1/social/friendships/${encodeURIComponent(requested.friendship.id)}`, 'POST', { action: 'accept' })).status === 404,
  'C forged acceptance of A/B relationship')

const accepted = await post(userB, `/api/v1/social/friendships/${encodeURIComponent(requested.friendship.id)}`, { action: 'accept', actorUserId: userA })
assert(accepted.friendship.state === 'friends', 'B did not accept A')
const acceptedContext = await get(userA, `/api/v1/social/users/${encodeURIComponent(userB)}/context`)
assert(acceptedContext.profile.statistics.publicVisitCount === 1 && acceptedContext.profile.statistics.publicRestaurantCount === 1,
  'Accepted friend could not access the friends-only Visit aggregate')
assert((await raw(userC, `/api/v1/social/users/${encodeURIComponent(userB)}/context`)).status === 404,
  'Unrelated C read B friends-only Profile')
const companionAck = await push(userA, mutation('companion-link', 'companion', companionID, 0, companion(userB, '大学室友')))

const followed = await put(userA, `/api/v1/social/follows/${encodeURIComponent(userB)}`)
const repeatedFollow = await put(userA, `/api/v1/social/follows/${encodeURIComponent(userB)}`)
assert(followed.follow.followerUserId === userA && repeatedFollow.duplicate === true,
  'Follow was not actor-scoped and idempotent')

const removed = await post(userA, `/api/v1/social/friendships/${encodeURIComponent(requested.friendship.id)}`, { action: 'remove' })
assert(removed.friendship.state === 'removed', 'A did not remove accepted Friendship')
assert((await raw(userA, `/api/v1/social/users/${encodeURIComponent(userB)}/context`)).status === 404,
  'Follow or stale relation still granted friends-only permission after removal')
const companionRenameAck = await push(userA, mutation(
  'companion-rename-after-unfriend', 'companion', companionID, companionAck.serverVersion,
  companion(userB, '老同学'),
))
const companionUnlinkAck = await push(userA, mutation(
  'companion-unlink', 'companion', companionID, companionRenameAck.serverVersion,
  companion(null, '老同学'),
))
const unfollowed = await del(userA, `/api/v1/social/follows/${encodeURIComponent(userB)}`)
assert(unfollowed.follow.deletedAt, 'Unfollow did not create an inactive server tombstone')

const [crossBC, crossCB] = await Promise.all([
  post(userB, '/api/v1/social/friendships', { targetUserId: userC }),
  post(userC, '/api/v1/social/friendships', { targetUserId: userB }),
])
const crossAccepted = [crossBC, crossCB].find((item) => item.friendship.state === 'friends')
assert(crossAccepted && crossBC.friendship.id === crossCB.friendship.id,
  'Concurrent cross friend requests did not converge to one accepted canonical pair')
await post(userB, `/api/v1/social/friendships/${encodeURIComponent(crossBC.friendship.id)}`, { action: 'remove' })

await push(userB, deletion('visit-delete', 'visit', visitID, visitAck.serverVersion))
await push(userB, deletion('restaurant-delete', 'restaurant', restaurantID, restaurantAck.serverVersion))
await push(userA, deletion('companion-delete', 'companion', companionID, companionUnlinkAck.serverVersion))
versionA = (await push(userA, profileMutation(userA, versionA, 'P3-B Alpha', '杭州', 'private', 'profile-a-private'))).serverVersion
versionB = (await push(userB, profileMutation(userB, versionB, 'P3-B Beta', '上海', 'private', 'profile-b-private'))).serverVersion
versionC = (await push(userC, profileMutation(userC, versionC, 'P3-B Gamma', '杭州', 'private', 'profile-c-private'))).serverVersion

console.log(JSON.stringify({
  result: 'P3-B Development social E2E passed', baseURL, userA, userB, userC,
  searchAllowlist: true, pagination: true, duplicateFriendRequestIdempotent: repeated.duplicate,
  pendingDenied: true, acceptedFriendsVisitAccess: true, permissionRevokedAfterRemove: true,
  forgedAcceptStatus: 404, followIndependent: true, duplicateFollowIdempotent: repeatedFollow.duplicate,
  crossRequestAccepted: Boolean(crossAccepted), concurrentCanonicalPair: true,
  companionLinkedToAcceptedFriend: true, companionPreservedAfterUnfriend: true, companionUnlinked: true,
  cleanup: 'Restaurant/Visit tombstoned; friendships removed; follow tombstoned; isolated profiles returned private',
  finalProfileVersions: { userA: versionA, userB: versionB, userC: versionC },
}, null, 2))

function profileEnvelope(body, userID) {
  const value = body.profiles.find((item) => item.record.userId === userID)
  if (!value) throw new Error(`Profile bootstrap missing for ${userID}`)
  return value
}

function profileMutation(userID, baseVersion, displayName, city, visibility, suffix) {
  return mutation(suffix, 'profile', userID, baseVersion, {
    schemaVersion: 1, userId: userID, displayName, bio: `${displayName} Development E2E`, city,
    avatarPhotoId: null, avatarPresetId: 'otter', visibility,
    createdAt: at, updatedAt: new Date().toISOString(), deletedAt: null,
  })
}

function restaurant() {
  return {
    schemaVersion: 1, id: restaurantID, userId: 'forged-owner', name: 'P3-B Friends Restaurant',
    address: 'Development D1 only', city: '上海', latitude: 31.2, longitude: 121.5,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null,
    environmentRating: null, serviceRating: null, valueRating: null, tags: [], longTermNote: '',
    pricePerPerson: null, phone: null, openingHours: null, markerType: 'emoji', markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: '👥', placeIdentities: [{ provider: 'apple_maps',
      externalId: `apple-p3b-${runID}`, isPrimary: true, createdAt: at, updatedAt: at }],
    createdAt: at, updatedAt: at, deletedAt: null,
  }
}

function visit() {
  return {
    schemaVersion: 1, id: visitID, userId: 'forged-owner', restaurantId: restaurantID,
    visitedAt: at, diningMode: 'dine_in', visibility: 'friends', partySize: 2,
    totalPrice: null, paymentMode: null, pricePerPerson: null, queueDuration: null,
    diningOccasions: [], diningOccasionText: null, rating: 4.5, valueRating: null,
    environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [],
    noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null,
    specialNotes: null, companions: [], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId: null, note: null, myActualSpend: null,
    createdAt: at, updatedAt: at, deletedAt: null,
  }
}

function companion(linkedTasteMapUserId, displayName) {
  return {
    schemaVersion: 1, id: companionID, userId: 'forged-owner', displayName,
    linkedTasteMapUserId, createdAt: at, updatedAt: new Date().toISOString(), deletedAt: null,
  }
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
  const body = await post(userID, '/api/v1/sync/push', { apiVersion: 1, schemaVersion: 1, mutations: [item] })
  const ack = body.acknowledgements[0]
  if (ack.status !== 'applied') throw new Error(`Mutation ${item.mutationId} failed: ${ack.conflictReason}`)
  return ack
}

function pull(userID) { return get(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200') }
function get(userID, path) { return checked(userID, path) }
function post(userID, path, body) { return checked(userID, path, 'POST', body) }
function put(userID, path) { return checked(userID, path, 'PUT') }
function del(userID, path) { return checked(userID, path, 'DELETE') }

async function checked(userID, path, method = 'GET', body) {
  const response = await raw(userID, path, method, body)
  const value = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${value.error ?? ''}`)
  return value
}

function raw(userID, path, method = 'GET', body) {
  return fetch(`${baseURL}${path}`, {
    method,
    headers: { 'X-Taste-Map-Test-User': userID, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  })
}

function assert(condition, message) { if (!condition) throw new Error(message) }
