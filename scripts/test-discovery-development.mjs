import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('P3-C Development test only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const userA = `p3c:${runID}:a`
const userB = `p3c:${runID}:b`
const userC = `p3c:${runID}:c`
const city = `P3C-${runID.slice(0, 8)}`
const createdAt = new Date().toISOString()
const records = new Map([[userA, []], [userB, []], [userC, []]])
const profileVersions = new Map()
let friendshipID = null

try {
  for (const [userID, displayName] of [
    [userA, 'P3-C Alpha'], [userB, 'P3-C Beta'], [userC, 'P3-C Gamma'],
  ]) {
    const initial = profileEnvelope(await pull(userID), userID)
    const ack = await push(userID, mutation(
      userID, `profile-public-${userID.at(-1)}`, 'profile', userID, initial.serverVersion,
      profile(userID, displayName, 'public'),
    ))
    profileVersions.set(userID, ack.serverVersion)
  }

  // Three genuinely shared, rated places establish a conservative taste sample.
  for (const [index, ratings] of [[0, [5, 5, 1]], [1, [4.5, 4.5, 1.5]], [2, [4, 4, 2]]]) {
    const identity = `apple-p3c-${runID}-shared-${index}`
    await createRestaurantAndVisit(userA, `shared-a-${index}`, identity, ratings[0], 'public', ['日料'])
    await createRestaurantAndVisit(userB, `shared-b-${index}`, identity, ratings[1], 'public', ['日料'])
    await createRestaurantAndVisit(userC, `shared-c-${index}`, identity, ratings[2], 'public', ['日料'])
  }

  const pickIdentity = `apple-p3c-${runID}-beta-pick`
  await createRestaurantAndVisit(userB, 'beta-pick', pickIdentity, 5, 'public', ['日料', '寿司'])
  // A second owner row for the same Apple Maps place must collapse to one card.
  await createRestaurantAndVisit(userC, 'beta-pick-copy', pickIdentity, 4.5, 'public', ['日料'])
  await createRestaurantAndVisit(userC, 'gamma-pick', `apple-p3c-${runID}-gamma-pick`, 4.5, 'public', ['咖啡'])
  const friendIdentity = `apple-p3c-${runID}-friends`
  await createRestaurantAndVisit(userB, 'friends-pick', friendIdentity, 5, 'friends', ['火锅'])
  const privateIdentity = `apple-p3c-${runID}-private`
  await createRestaurantAndVisit(userB, 'private-pick', privateIdentity, 5, 'private', ['私密'])

  // Repeated activity by one actor must count once, while two actors rank as two unique users.
  const repeat = await createRestaurant(userB, 'repeat', `apple-p3c-${runID}-repeat`, 'visited', ['烧烤'])
  for (let index = 0; index < 3; index += 1) {
    await createVisit(userB, repeat.id, `repeat-${index}`, 5, 'public', new Date(Date.now() - index * 60_000).toISOString())
  }
  const uniqueIdentity = `apple-p3c-${runID}-unique`
  await createRestaurantAndVisit(userB, 'unique-b', uniqueIdentity, 5, 'public', ['面馆'])
  await createRestaurantAndVisit(userC, 'unique-c', uniqueIdentity, 4.5, 'public', ['面馆'])

  // Two isolated WantToGo records create an anonymous aggregate cohort.
  const wantedIdentity = `apple-p3c-${runID}-wanted`
  await createRestaurant(userB, 'wanted-b', wantedIdentity, 'wantToGo', ['川菜'])
  await createRestaurant(userC, 'wanted-c', wantedIdentity, 'wantToGo', ['川菜'])

  const forYou = await get(userA, `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}&limit=20`)
  const pickCards = cardsWithIdentity(forYou, pickIdentity)
  assert(pickCards.length === 1, 'Global Apple Maps identity produced duplicate For You cards')
  assert(pickCards[0].reasons.some((reason) => reason.code === 'SIMILAR_USERS'),
    'For You recommendation reason was not backed by the aligned user')
  assert(pickCards[0].sourceUser?.userId === userB, 'For You did not expose the allowlisted public source user')
  assert(!forYou.items.some((item) => hasIdentity(item, privateIdentity)), 'Private Visit entered For You')
  assert(!forYou.items.some((item) => hasIdentity(item, friendIdentity)), 'Non-friend saw friends-only Visit')
  assert(!JSON.stringify(forYou).includes('storageKey') && !JSON.stringify(forYou).includes('note'),
    'Discovery DTO leaked storage or Visit note fields')

  const similar = await get(userA, `/api/v1/discovery/similar-taste?city=${encodeURIComponent(city)}`)
  const similarPick = cardsWithIdentity(similar, pickIdentity)[0]
  assert(similarPick?.sourceUser?.userId === userB,
    `Aligned user did not produce a Similar Taste recommendation: ${JSON.stringify(similar)}`)
  assert(similarPick.similarity.sharedRestaurantCount >= 3 && similarPick.similarity.percent >= 85,
    'Similar Taste minimum sample or threshold was not enforced')
  assert(!similar.items.some((item) => item.sourceUser?.userId === userA), 'Similar Taste recommended the viewer')
  assert(!similar.items.some((item) => item.sourceUser?.userId === userC), 'Divergent user was labelled Similar Taste')

  const trend = await get(userA, `/api/v1/discovery/trending?city=${encodeURIComponent(city)}&window=7&limit=20`)
  const repeatCard = trend.items.find((item) => hasIdentity(item, `apple-p3c-${runID}-repeat`))
  const uniqueCard = trend.items.find((item) => hasIdentity(item, uniqueIdentity))
  const wantedCard = trend.items.find((item) => hasIdentity(item, wantedIdentity))
  assert(repeatCard?.trend.uniqueVisitorCount === 1, 'Repeated Visits inflated unique-user trend count')
  assert(uniqueCard?.trend.uniqueVisitorCount === 2, 'Two unique trend actors were not counted')
  assert(uniqueCard.rank < repeatCard.rank, 'Unique-user trend signal did not outrank one repeated actor')
  assert(wantedCard?.trend.wantToGoCount === 2, 'Anonymous WantToGo cohort did not enter Trending')

  const firstPage = await get(userA, `/api/v1/discovery/trending?city=${encodeURIComponent(city)}&window=7&limit=1`)
  assert(firstPage.items.length === 1 && firstPage.nextCursor, 'Development pagination did not return an opaque cursor')
  const secondPage = await get(userA,
    `/api/v1/discovery/trending?city=${encodeURIComponent(city)}&window=7&limit=1&cursor=${encodeURIComponent(firstPage.nextCursor)}`)
  assert(secondPage.items.length === 1 &&
    secondPage.items[0].restaurant.globalKey !== firstPage.items[0].restaurant.globalKey,
  'Development cursor repeated the previous Restaurant')

  const request = await post(userA, '/api/v1/social/friendships', { targetUserId: userB })
  friendshipID = request.friendship.id
  await post(userB, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'accept' })
  const friendsPage = await get(userA, `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}`)
  const friendsCard = friendsPage.items.find((item) => hasIdentity(item, friendIdentity))
  assert(friendsCard?.cacheScope === 'friends' && friendsCard.sourceUser?.friendshipState === 'friends',
    'Accepted friendship did not authorize the friends-only Discovery card')
  await post(userA, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'remove' })
  const revokedPage = await get(userA, `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}`)
  assert(!revokedPage.items.some((item) => hasIdentity(item, friendIdentity)),
    'Removed friendship retained friends-only Discovery access')

  const ownWant = await createRestaurant(userA, 'own-want', pickIdentity, 'wantToGo', ['日料'])
  const wantedForYou = await get(userA, `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}`)
  const wantedPick = cardsWithIdentity(wantedForYou, pickIdentity)
  assert(wantedPick.length === 1 && wantedPick[0].viewerState === 'want_to_go',
    'Discovery did not resolve viewer WantToGo state through global identity')

  const forged = await get(userA,
    `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}&userId=${encodeURIComponent(userB)}`)
  assert(cardsWithIdentity(forged, pickIdentity)[0]?.viewerState === 'want_to_go',
    'Worker trusted a forged Discovery userId instead of the authenticated actor')
  assert((await raw('', `/api/v1/discovery/for-you?city=${encodeURIComponent(city)}`)).status === 401,
    'Unauthenticated Development caller entered Discovery')

  console.log(JSON.stringify({
    result: 'P3-C Development Discovery E2E passed', baseURL, city, userA, userB, userC,
    forYou: true, similarTaste: true, trending: true, pagination: true,
    uniqueUserAntiSpam: true, publicProfileAllowlist: true,
    friendsOnlyAccepted: true, unfriendRevoked: true, privateExcluded: true,
    globalIdentityCollapsed: true, wantToGoLinked: ownWant.id,
    forgedUserIgnored: true, unauthorizedDenied: true,
    cleanup: 'runs in finally: Visits/Restaurants tombstoned, friendship removed, profiles private',
  }, null, 2))
} finally {
  await cleanup().catch((error) => {
    console.error(`P3-C cleanup failed: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}

async function createRestaurantAndVisit(userID, suffix, identity, rating, visibility, tags) {
  const restaurant = await createRestaurant(userID, suffix, identity, 'visited', tags)
  await createVisit(userID, restaurant.id, suffix, rating, visibility, createdAt)
  return restaurant
}

async function createRestaurant(userID, suffix, identity, status, tags) {
  const id = `p3c-restaurant-${runID}-${suffix}`
  const payload = {
    schemaVersion: 1, id, userId: 'forged-owner', name: `P3-C ${suffix}`,
    address: `${city} Development D1 only`, city, latitude: 30.2 + suffix.length / 10_000,
    longitude: 120.1 + suffix.length / 10_000, status, preferenceLevel: 'normal',
    overallRating: null, foodRating: null, environmentRating: null, serviceRating: null,
    valueRating: null, tags, longTermNote: '', pricePerPerson: null, phone: null,
    openingHours: null, markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null,
    markerEmoji: '🍜', placeIdentities: [{ provider: 'apple_maps', externalId: identity,
      isPrimary: true, createdAt, updatedAt: createdAt }],
    createdAt, updatedAt: createdAt, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `restaurant-${suffix}`, 'restaurant', id, 0, payload))
  records.get(userID).push({ entityType: 'restaurant', entityId: id, serverVersion: ack.serverVersion })
  return { id, ack }
}

async function createVisit(userID, restaurantID, suffix, rating, visibility, visitedAt) {
  const id = `p3c-visit-${runID}-${suffix}`
  const payload = {
    schemaVersion: 1, id, userId: 'forged-owner', restaurantId: restaurantID,
    visitedAt, diningMode: 'dine_in', visibility, partySize: 2, totalPrice: null,
    paymentMode: null, pricePerPerson: null, queueDuration: null, diningOccasions: [],
    diningOccasionText: null, rating, valueRating: null, environmentRating: null,
    serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [],
    noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null,
    specialNotes: null, companions: [], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId: null, note: null, myActualSpend: null,
    createdAt, updatedAt: createdAt, deletedAt: null,
  }
  const ack = await push(userID, mutation(userID, `visit-${suffix}`, 'visit', id, 0, payload))
  records.get(userID).push({ entityType: 'visit', entityId: id, serverVersion: ack.serverVersion })
  return { id, ack }
}

async function cleanup() {
  if (friendshipID) {
    const context = await raw(userA, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, 'POST', { action: 'remove' })
    if (![200, 404, 409].includes(context.status)) throw new Error(`Friendship cleanup ${context.status}`)
  }
  for (const userID of [userA, userB, userC]) {
    const userRecords = records.get(userID)
    for (const record of [...userRecords].sort((left, right) =>
      (left.entityType === 'visit' ? -1 : 1) - (right.entityType === 'visit' ? -1 : 1))) {
      const ack = await push(userID, deletion(userID, record.entityType, record.entityId, record.serverVersion))
      if (ack.status !== 'applied') throw new Error(`Cleanup failed for ${record.entityType}:${record.entityId}`)
    }
    const version = profileVersions.get(userID)
    if (version !== undefined) {
      const displayName = userID === userA ? 'P3-C Alpha' : userID === userB ? 'P3-C Beta' : 'P3-C Gamma'
      const ack = await push(userID, mutation(
        userID, `profile-private-${userID.at(-1)}`, 'profile', userID, version,
        profile(userID, displayName, 'private'),
      ))
      profileVersions.set(userID, ack.serverVersion)
    }
  }
}

function cardsWithIdentity(page, externalID) {
  return page.items.filter((item) => hasIdentity(item, externalID))
}
function hasIdentity(card, externalID) {
  return card.restaurant.placeIdentities.some((identity) => identity.externalId === externalID)
}
function profileEnvelope(body, userID) {
  const value = body.profiles.find((item) => item.record.userId === userID)
  if (!value) throw new Error(`Profile bootstrap missing for ${userID}`)
  return value
}
function profile(userID, displayName, visibility) {
  return {
    schemaVersion: 1, userId: userID, displayName, bio: `${displayName} Development E2E`,
    city, avatarPhotoId: null, avatarPresetId: 'otter', visibility,
    createdAt, updatedAt: new Date().toISOString(), deletedAt: null,
  }
}
function mutation(userID, suffix, entityType, entityId, baseVersion, payload) {
  return { mutationId: `${runID}:${userID.at(-1)}:${suffix}`, entityType, entityId,
    operation: 'upsert', baseVersion, clientTimestamp: payload.updatedAt, payload }
}
function deletion(userID, entityType, entityId, baseVersion) {
  return { mutationId: `${runID}:${userID.at(-1)}:delete:${entityType}:${entityId}`,
    entityType, entityId, operation: 'delete', baseVersion, clientTimestamp: new Date().toISOString() }
}
async function push(userID, item) {
  const body = await post(userID, '/api/v1/sync/push', {
    apiVersion: 1, schemaVersion: 1, mutations: [item],
  })
  const ack = body.acknowledgements[0]
  if (!ack || !['applied', 'conflict'].includes(ack.status)) {
    throw new Error(`Mutation ${item.mutationId} failed: ${ack?.conflictReason ?? 'missing acknowledgement'}`)
  }
  if (ack.status !== 'applied') throw new Error(`Mutation ${item.mutationId} conflicted: ${ack.conflictReason}`)
  return ack
}
function pull(userID) { return get(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200') }
function get(userID, path) { return checked(userID, path) }
function post(userID, path, body) { return checked(userID, path, 'POST', body) }
async function checked(userID, path, method = 'GET', body) {
  const response = await raw(userID, path, method, body)
  const value = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${value.error ?? ''}`)
  return value
}
function raw(userID, path, method = 'GET', body) {
  return fetch(`${baseURL}${path}`, {
    method,
    headers: { ...(userID ? { 'X-Taste-Map-Test-User': userID } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  })
}
function assert(condition, message) { if (!condition) throw new Error(message) }
