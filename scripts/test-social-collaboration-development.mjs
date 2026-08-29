import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('Task 06 Development E2E only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const city = `Task06-${runID.slice(0, 8)}`
const userA = `task06:${runID}:a`
const userB = `task06:${runID}:b`
const userC = `task06:${runID}:c`
const companionID = `task06-companion-${runID}`
const restaurantAID = `task06-restaurant-a-${runID}`
const restaurantBID = `task06-restaurant-b-${runID}`
const visitAID = `task06-visit-a-${runID}`
const visitBID = `task06-visit-b-${runID}`
const appleIdentity = `apple-task06-${runID}`
const records = new Map([[userA, []], [userB, []], [userC, []]])
const profileVersions = new Map()
const commentIDs = []
let friendshipID = null
let companionLinkID = null
let mealID = null

try {
  for (const [userID, name] of [[userA, 'Task 06 Alpha'], [userB, 'Task 06 Beta'], [userC, 'Task 06 Gamma']]) {
    const initial = await pull(userID)
    const current = initial.profiles.find((item) => item.record.userId === userID)
    assert(current, `Profile bootstrap missing for ${userID}`)
    const ack = await push(userID, mutation(
      userID, `profile-${userID.at(-1)}`, 'profile', userID, current.serverVersion,
      profile(userID, name),
    ))
    profileVersions.set(userID, ack.serverVersion)
  }

  const request = await post(userA, '/api/v1/social/friendships', { targetUserId: userB })
  friendshipID = request.friendship.id
  await post(userB, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, { action: 'accept' })

  const companion = companionPayload(companionID, 'Task 06 Explicit Friend')
  const companionAck = await push(userA, mutation(
    userA, 'companion-create', 'companion', companionID, 0, companion,
  ))
  records.get(userA).push({ entityType: 'companion', entityId: companionID,
    serverVersion: companionAck.serverVersion, payload: companion, deleted: false })

  const link = await post(userA, '/api/v1/social/companion-links', {
    companionId: companionID, targetUserId: userB,
  })
  companionLinkID = link.id
  assert(link.status === 'pending' && link.otherUser.userId === userB,
    'Explicit Companion link request was not created')
  const incomingLinks = await get(userB, '/api/v1/social/companion-links?scope=incoming&limit=50')
  assert(incomingLinks.items.some((item) => item.id === companionLinkID),
    'Companion link request did not reach B inbox')
  assert((await raw(userC, '/api/v1/social/companion-links', 'POST', {
    companionId: companionID, targetUserId: userB,
  })).status >= 400, 'Unrelated C unexpectedly linked A private Companion')
  await post(userB, `/api/v1/social/companion-links/${encodeURIComponent(companionLinkID)}`, { action: 'accept' })
  const afterLink = await pull(userA)
  assert(afterLink.companions.find((item) => item.record.id === companionID)?.record.linkedTasteMapUserId === userB,
    'Accepted Companion link did not converge through sync')

  const restaurantA = restaurantPayload(restaurantAID, 'Task 06 Apple Maps Restaurant')
  const restaurantAAck = await push(userA, mutation(
    userA, 'restaurant-a', 'restaurant', restaurantAID, 0, restaurantA,
  ))
  records.get(userA).push({ entityType: 'restaurant', entityId: restaurantAID,
    serverVersion: restaurantAAck.serverVersion, payload: restaurantA, deleted: false })
  const visitA = visitPayload(visitAID, restaurantAID, 'friends', null, 'Task 06 source Visit')
  const visitAAck = await push(userA, mutation(userA, 'visit-a', 'visit', visitAID, 0, visitA))
  records.get(userA).push({ entityType: 'visit', entityId: visitAID,
    serverVersion: visitAAck.serverVersion, payload: visitA, deleted: false })

  const inviteBody = { sourceVisitId: visitAID, participantUserIds: [userB], mutationId: `task06:${runID}:meal` }
  const invitation = await post(userA, '/api/v1/social/shared-meals', inviteBody)
  mealID = invitation.mealId
  const invitationRetry = await post(userA, '/api/v1/social/shared-meals', inviteBody)
  assert(invitationRetry.duplicate === true && invitationRetry.mealId === mealID,
    'Shared Meal idempotency failed after a simulated lost response')
  assert(invitation.invitations[0]?.restaurant.placeIdentities.some((identity) =>
    identity.provider === 'apple_maps' && identity.externalId === appleIdentity),
  'Apple Maps-only Restaurant identity was lost in Shared Meal')
  assert(invitation.invitations[0]?.participant.userId === userB,
    'Shared Meal participant projection was missing')
  assert((await raw(userC, '/api/v1/social/shared-meals', 'POST', {
    sourceVisitId: visitAID, participantUserIds: [userB], mutationId: `forged:${runID}`,
  })).status === 404, 'C created a Shared Meal from A Visit by direct ID')

  const incomingMeals = await get(userB, '/api/v1/social/shared-meals?scope=incoming&limit=50')
  const received = incomingMeals.items.find((item) => item.mealId === mealID)
  assert(received?.inviter.userId === userA && received.status === 'pending',
    'B did not receive the Shared Meal invitation')
  const accepted = await post(userB,
    `/api/v1/social/shared-meals/participants/${encodeURIComponent(received.participantId)}`,
    { action: 'accept' })
  assert(accepted.status === 'accepted', 'B could not accept Shared Meal')

  const restaurantB = restaurantPayload(restaurantBID, 'Task 06 Receiver Restaurant')
  const restaurantBAck = await push(userB, mutation(
    userB, 'restaurant-b', 'restaurant', restaurantBID, 0, restaurantB,
  ))
  records.get(userB).push({ entityType: 'restaurant', entityId: restaurantBID,
    serverVersion: restaurantBAck.serverVersion, payload: restaurantB, deleted: false })
  const visitB = visitPayload(visitBID, restaurantBID, 'private', mealID, 'Task 06 receiver own Visit')
  const visitBAck = await push(userB, mutation(userB, 'visit-b', 'visit', visitBID, 0, visitB))
  records.get(userB).push({ entityType: 'visit', entityId: visitBID,
    serverVersion: visitBAck.serverVersion, payload: visitB, deleted: false })
  const attached = await post(userB,
    `/api/v1/social/shared-meals/participants/${encodeURIComponent(received.participantId)}`,
    { action: 'attach', visitId: visitBID })
  assert(attached.visitId === visitBID, 'B own Visit was not attached to Shared Meal')
  assert((await raw(userA,
    `/api/v1/social/shared-meals/participants/${encodeURIComponent(received.participantId)}`,
    'POST', { action: 'attach', visitId: visitBID })).status === 404,
  'Sender modified receiver-owned Shared Meal participant')

  const liked = await put(userB, `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/like`)
  const likedAgain = await put(userB, `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/like`)
  assert(liked.likedByViewer && liked.likeCount === 1 && likedAgain.duplicate,
    'Like was not idempotent')
  assert((await raw(userC,
    `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/comments`)).status === 404,
  'C read friends-only comments by direct Visit ID')
  for (const body of ['First Task 06 comment', 'Second Task 06 comment', 'Third Task 06 comment']) {
    const response = await post(userB,
      `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/comments`, { body })
    commentIDs.push(response.comment.id)
  }
  const firstPage = await get(userB,
    `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/comments?limit=2`)
  assert(firstPage.items.length === 2 && firstPage.nextCursor,
    'Comment first page or cursor was missing')
  const secondPage = await get(userB,
    `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/comments?limit=2&cursor=${encodeURIComponent(firstPage.nextCursor)}`)
  assert(secondPage.items.length === 1, 'Comment pagination duplicated or lost an item')
  assert((await raw(userA, `/api/v1/community/comments/${encodeURIComponent(commentIDs[0])}`, 'DELETE')).status === 404,
    'A deleted B own comment')
  await del(userB, `/api/v1/community/comments/${encodeURIComponent(commentIDs.shift())}`)
  const unliked = await del(userB, `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/like`)
  const unlikedAgain = await del(userB, `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/like`)
  assert(!unliked.likedByViewer && unliked.likeCount === 0 && unlikedAgain.duplicate,
    'Unlike was not idempotent')

  const overview = await get(userB, `/api/v1/community/users/${encodeURIComponent(userA)}/overview`)
  assert(overview.friendCount >= 1 && Array.isArray(overview.footprints) && overview.tasteSummary,
    'Public Profile overview did not expose authorized social/taste/footprint projection')

  const privateVisit = { ...visitA, visibility: 'private', updatedAt: new Date().toISOString() }
  const privateAck = await push(userA, mutation(
    userA, 'visit-a-private', 'visit', visitAID, visitAAck.serverVersion, privateVisit,
  ))
  records.get(userA).find((item) => item.entityId === visitAID).serverVersion = privateAck.serverVersion
  records.get(userA).find((item) => item.entityId === visitAID).payload = privateVisit
  assert((await raw(userB,
    `/api/v1/community/content/visit/${encodeURIComponent(visitAID)}/comments`)).status === 404,
  'Interactions remained visible after content became private')
  for (const id of commentIDs.splice(0)) await del(userB, `/api/v1/community/comments/${encodeURIComponent(id)}`)

  await del(userA, `/api/v1/social/shared-meals/${encodeURIComponent(mealID)}`)
  const receiverPull = await pull(userB)
  assert(receiverPull.visits.some((item) => item.record.id === visitBID && item.record.deletedAt === null),
    'Revoking Shared Meal deleted receiver own Visit')

  await post(userA, `/api/v1/social/companion-links/${encodeURIComponent(companionLinkID)}`, { action: 'unlink' })
  const unlinkedPull = await pull(userA)
  const unlinkedCompanion = unlinkedPull.companions.find((item) => item.record.id === companionID)
  assert(unlinkedCompanion?.record.linkedTasteMapUserId === null,
    'Companion unlink did not converge')
  records.get(userA).find((item) => item.entityId === companionID).serverVersion = unlinkedCompanion.serverVersion

  console.log(JSON.stringify({
    result: 'Task 06 Development Social/Community E2E passed', baseURL,
    users: { A: userA, B: userB, C: userC },
    companionExplicitConsent: true, companionNameAutoMerge: false,
    sharedMealIdempotent: invitationRetry.duplicate, receiverOwnVisit: true,
    appleMapsOnly: true, senderCannotEditReceiver: true, revokePreservesReceiverVisit: true,
    likeCommentAuthenticated: true, commentPagination: true, directIDDenied: true,
    visibilityInherited: true, publicProfileOverview: true,
    productionAccessed: false,
    cleanup: 'finally tombstones isolated business records, removes social links, and privatizes test profiles',
  }, null, 2))
} finally {
  await cleanup().catch((error) => {
    console.error(`Task 06 cleanup failed: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}

async function cleanup() {
  for (const commentID of commentIDs.splice(0)) {
    await raw(userB, `/api/v1/community/comments/${encodeURIComponent(commentID)}`, 'DELETE')
  }
  if (mealID) await raw(userA, `/api/v1/social/shared-meals/${encodeURIComponent(mealID)}`, 'DELETE')
  if (companionLinkID) {
    await raw(userA, `/api/v1/social/companion-links/${encodeURIComponent(companionLinkID)}`, 'POST', { action: 'unlink' })
    await raw(userA, `/api/v1/social/companion-links/${encodeURIComponent(companionLinkID)}`, 'POST', { action: 'cancel' })
  }
  if (friendshipID) await raw(userA, `/api/v1/social/friendships/${encodeURIComponent(friendshipID)}`, 'POST', { action: 'remove' })
  for (const userID of [userA, userB, userC]) {
    for (const type of ['visit', 'restaurant', 'companion']) {
      for (const record of records.get(userID).filter((item) => item.entityType === type && !item.deleted)) {
        const response = await push(userID, deletion(
          userID, `cleanup-${type}-${record.entityId}`, type, record.entityId, record.serverVersion,
        )).catch(() => null)
        if (response?.status === 'applied') record.deleted = true
      }
    }
    const version = profileVersions.get(userID)
    if (version !== undefined) {
      await push(userID, mutation(
        userID, 'cleanup-profile', 'profile', userID, version,
        { ...profile(userID, 'Task 06 Development Test'), visibility: 'private', updatedAt: new Date().toISOString() },
      )).catch(() => null)
    }
  }
}

function profile(userID, displayName) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, userId: userID, displayName, bio: 'Task 06 Development E2E',
    city, avatarPhotoId: null, avatarPresetId: 'otter', visibility: 'public',
    createdAt: now, updatedAt: now, deletedAt: null }
}

function companionPayload(id, displayName) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, id, userId: 'forged-owner', displayName,
    linkedTasteMapUserId: null, createdAt: now, updatedAt: now, deletedAt: null }
}

function restaurantPayload(id, name) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, id, userId: 'forged-owner', name,
    address: `${city} Development D1 only`, city, latitude: 30.2, longitude: 120.1,
    status: 'visited', preferenceLevel: 'normal', overallRating: null, foodRating: null,
    environmentRating: null, serviceRating: null, valueRating: null, tags: ['Task 06'],
    longTermNote: '', pricePerPerson: null, phone: null, openingHours: null,
    markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍜',
    placeIdentities: [{ provider: 'apple_maps', externalId: appleIdentity, isPrimary: true,
      createdAt: now, updatedAt: now }], createdAt: now, updatedAt: now, deletedAt: null }
}

function visitPayload(id, restaurantId, visibility, sharedMealId, note) {
  const now = new Date().toISOString()
  return { schemaVersion: 1, id, userId: 'forged-owner', restaurantId,
    visitedAt: now, diningMode: 'dine_in', visibility, partySize: 2, totalPrice: null,
    paymentMode: null, pricePerPerson: null, queueDuration: null, diningOccasions: [],
    diningOccasionText: null, rating: null, valueRating: null, environmentRating: null,
    serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null,
    diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: null,
    companions: [], companionIds: [], recommendationSourceId: null,
    recommendationSourceType: null, recommendationSourceUserId: null,
    recommendationSourceText: null, sharedMealId, note, myActualSpend: null,
    createdAt: now, updatedAt: now, deletedAt: null }
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
    throw new Error(`Mutation ${item.mutationId} failed: ${ack?.conflictReason ?? 'missing acknowledgement'}`)
  }
  return ack
}

function pull(userID) { return get(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=500') }
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
  return fetch(`${baseURL}${path}`, { method, headers: {
    'X-Taste-Map-Test-User': userID,
    ...(body ? { 'Content-Type': 'application/json' } : {}),
  }, ...(body ? { body: JSON.stringify(body) } : {}) })
}

function assert(condition, message) { if (!condition) throw new Error(message) }
