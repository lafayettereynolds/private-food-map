import { randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('P4-F Development test only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const userA = `p4f:${runID}:a`
const userB = `p4f:${runID}:b`
const listID = `p4f-list-${runID}`
const itemIDs = Array.from({ length: 5 }, (_, index) => `p4f-item-${runID}-${index}`)
const sharedExternalID = `apple-p4f-${runID}-0`
const bRestaurantID = `p4f-want-${runID}`
const versions = { profiles: new Map(), list: 0, items: new Map(), bRestaurant: 0 }
let listDeleted = false
let bRestaurantDeleted = false

try {
  for (const [userID, displayName] of [[userA, 'P4-F Alpha'], [userB, 'P4-F Beta']]) {
    const initial = profileEnvelope(await pull(userID, 0), userID)
    const ack = await pushOne(userID, mutation(
      `${userID}:profile-public`, 'profile', userID, initial.serverVersion,
      profile(userID, displayName, 'public'),
    ))
    versions.profiles.set(userID, ack.serverVersion)
  }

  const cursorBeforeCreate = Number((await pull(userA, 0)).nextCursor)
  const createListMutation = mutation(
    'create-list', 'restaurantList', listID, 0,
    listPayload('杭州日料 Top 5', 'public'),
  )
  const firstListAck = await pushOne(userA, createListMutation)
  const repeatedListAck = await pushOne(userA, createListMutation)
  versions.list = firstListAck.serverVersion
  assert(repeatedListAck.duplicate === true, 'Repeated list mutation was not idempotent')
  assert(repeatedListAck.serverVersion === firstListAck.serverVersion,
    'Repeated list mutation changed serverVersion')

  for (let index = 0; index < itemIDs.length; index += 1) {
    const ack = await pushOne(userA, mutation(
      `create-item-${index}`, 'restaurantListItem', itemIDs[index], 0,
      itemPayload(index, index),
    ))
    versions.items.set(itemIDs[index], ack.serverVersion)
  }

  const delta = await pull(userA, cursorBeforeCreate)
  assert(delta.restaurantLists.some((entry) => entry.record.id === listID),
    'Incremental pull missed the new RestaurantList')
  assert(delta.restaurantListItems.filter((entry) => entry.record.listId === listID).length === 5,
    'Incremental pull missed RestaurantListItems')
  const fresh = await pull(userA, 0)
  const freshItems = fresh.restaurantListItems
    .filter((entry) => entry.record.listId === listID)
    .sort((left, right) => left.record.position - right.record.position)
  assert(freshItems.length === 5, 'Fresh same-user client did not hydrate five items')
  assert(freshItems[0].record.restaurant.placeIdentities[0].provider === 'apple_maps',
    'Apple Maps-only item lost its provider identity')
  assert(!freshItems[0].record.restaurant.placeIdentities.some((identity) => identity.provider === 'amap'),
    'Apple Maps-only item unexpectedly depends on amapPoiId')

  const cursorBeforeReorder = Number(fresh.nextCursor)
  const order = [4, 0, 1, 2, 3]
  for (let position = 0; position < order.length; position += 1) {
    const index = order[position]
    const itemID = itemIDs[index]
    const ack = await pushOne(userA, mutation(
      `reorder-${index}`, 'restaurantListItem', itemID, versions.items.get(itemID),
      itemPayload(index, position),
    ))
    versions.items.set(itemID, ack.serverVersion)
  }
  const reorderDelta = await pull(userA, cursorBeforeReorder)
  const reordered = reorderDelta.restaurantListItems
    .filter((entry) => entry.record.listId === listID)
    .sort((left, right) => left.record.position - right.record.position)
  assert(reordered.map((entry) => entry.record.id).join(',') === order.map((index) => itemIDs[index]).join(','),
    'Reorder did not converge to the explicit deterministic order')

  const bSummary = await get(userB, `/api/v1/lists/users/${encodeURIComponent(userA)}?limit=20`)
  assert(bSummary.items.some((entry) => entry.id === listID && entry.restaurantCount === 5),
    'User B could not read User A public list summary')
  const bDetail = await get(userB, `/api/v1/lists/${encodeURIComponent(listID)}?limit=3`)
  assert(bDetail.items.map((entry) => entry.id).join(',') === order.slice(0, 3).map((index) => itemIDs[index]).join(','),
    'Public detail did not preserve ranking order')
  assert(bDetail.nextCursor, 'Public detail did not paginate')
  for (const forbidden of ['myActualSpend', 'longTermNote', 'storageKey', 'remoteRecordData', 'authSubject']) {
    assert(!JSON.stringify(bDetail).includes(forbidden), `Public DTO leaked ${forbidden}`)
  }

  const wantAck = await pushOne(userB, mutation(
    'b-add-want-to-go', 'restaurant', bRestaurantID, 0,
    restaurantPayload(bRestaurantID, sharedExternalID),
  ))
  versions.bRestaurant = wantAck.serverVersion
  const bPull = await pull(userB, 0)
  const bWant = bPull.restaurants.filter((entry) => entry.record.id === bRestaurantID)
  assert(bWant.length === 1 && bWant[0].record.status === 'wantToGo',
    'Public List → WantToGo did not create exactly one viewer-owned state')
  assert(bWant[0].record.placeIdentities[0].externalId === sharedExternalID,
    'Public List → WantToGo split Global Restaurant Identity')

  const forged = await rawPush(userB, mutation(
    'b-forged-edit', 'restaurantListItem', itemIDs[0], versions.items.get(itemIDs[0]),
    itemPayload(0, 99),
  ))
  assert(forged.status === 403, 'Non-owner forged ListItem edit was not denied')

  const privateAck = await pushOne(userA, mutation(
    'list-public-to-private', 'restaurantList', listID, versions.list,
    listPayload('杭州日料 Top 5', 'private'),
  ))
  versions.list = privateAck.serverVersion
  assert((await raw(userB, `/api/v1/lists/${encodeURIComponent(listID)}`)).status === 404,
    'Public → private did not revoke User B direct access')
  const afterPrivate = await get(userB, `/api/v1/lists/users/${encodeURIComponent(userA)}?limit=20`)
  assert(!afterPrivate.items.some((entry) => entry.id === listID),
    'Public → private remained visible on Public Profile')

  const deleteAck = await pushOne(userA, deletion('delete-list', 'restaurantList', listID, versions.list))
  versions.list = deleteAck.serverVersion
  listDeleted = true
  const tombstonePull = await pull(userA, cursorBeforeReorder)
  assert(tombstonePull.tombstones.some((entry) => entry.entityType === 'restaurantList' && entry.entityId === listID),
    'List tombstone was not pulled')
  assert(tombstonePull.tombstones.filter((entry) =>
    entry.entityType === 'restaurantListItem' && itemIDs.includes(entry.entityId)).length === 5,
    'Cascade ListItem tombstones were not pulled')
  const staleRevive = await rawPush(userA, mutation(
    'stale-revive-item', 'restaurantListItem', itemIDs[0], versions.items.get(itemIDs[0]),
    itemPayload(0, 0),
  ))
  assert(staleRevive.status === 403, 'Stale client revived an item after parent List deletion')

  console.log(JSON.stringify({
    result: 'P4-F Development Restaurant Lists E2E passed',
    baseURL, users: { A: userA, B: userB }, listID,
    isolatedDevelopmentUsers: true, listCreate: true, itemCreate: true,
    appleMapsOnly: true, incrementalCursor: true, idempotency: true,
    freshSameUserClient: true, reorder: true, publicRead: true,
    publicPagination: true, publicDTOAllowlist: true, publicToWantToGo: true,
    globalRestaurantIdentity: true, forgedOwnerDenied: true,
    visibilityRevoked: true, tombstones: true, staleRevivalDenied: true,
    productionAccessed: false,
    cleanup: 'finally tombstones isolated data and returns test profiles private',
  }, null, 2))
} finally {
  await cleanup().catch((error) => {
    console.error(`P4-F cleanup failed: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  })
}

async function cleanup() {
  if (!listDeleted && versions.list > 0) {
    const response = await rawPush(userA, deletion('cleanup-list', 'restaurantList', listID, versions.list))
    if (response.ok) listDeleted = true
  }
  if (!bRestaurantDeleted && versions.bRestaurant > 0) {
    const response = await rawPush(userB, deletion(
      'cleanup-b-restaurant', 'restaurant', bRestaurantID, versions.bRestaurant,
    ))
    if (response.ok) bRestaurantDeleted = true
  }
  for (const userID of [userA, userB]) {
    const version = versions.profiles.get(userID)
    if (version) {
      await pushOne(userID, mutation(
        `${userID}:cleanup-profile-private`, 'profile', userID, version,
        profile(userID, 'P4-F Development Test', 'private'),
      ))
    }
  }
}

function profileEnvelope(body, userID) {
  const value = body.profiles.find((entry) => entry.record.userId === userID)
  if (!value) throw new Error(`Profile bootstrap missing for ${userID}`)
  return value
}

function profile(userID, displayName, visibility) {
  const timestamp = new Date().toISOString()
  return {
    schemaVersion: 1, userId: userID, displayName, bio: 'P4-F Development E2E', city: '杭州',
    avatarPhotoId: null, avatarPresetId: 'otter', visibility,
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
}

function listPayload(title, visibility) {
  const timestamp = new Date().toISOString()
  return {
    schemaVersion: 1, id: listID, userId: 'forged-owner', title,
    description: 'Development D1 isolated Restaurant List', visibility,
    isRanked: true, coverMode: 'automatic', customCoverPhotoId: null,
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
}

function itemPayload(index, position) {
  const timestamp = new Date().toISOString()
  const externalId = `apple-p4f-${runID}-${index}`
  const globalKey = `apple_maps:${externalId}`
  const restaurantId = `place-ref:${globalKey}`
  return {
    schemaVersion: 1, id: itemIDs[index], userId: 'forged-owner', listId: listID,
    restaurantId, restaurantGlobalKey: globalKey, position,
    note: index === 0 ? 'Development 公开榜单备注' : '',
    restaurant: {
      globalKey, restaurantId,
      placeIdentities: [{ provider: 'apple_maps', externalId, isPrimary: true }],
      name: `P4-F Development 餐厅 ${index + 1}`, address: `Development D1 only ${index + 1}`,
      city: '杭州', latitude: 30.25 + index / 1000, longitude: 120.16,
      markerPhotoId: null, merchantImageUrl: null, markerEmoji: ['🍣', '🍲', '🍢', '🥘', '🍜'][index],
    },
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
  }
}

function restaurantPayload(id, externalId) {
  const timestamp = new Date().toISOString()
  return {
    schemaVersion: 1, id, userId: 'forged-owner', name: 'P4-F Viewer WantToGo',
    address: 'Development D1 only', city: '杭州', latitude: 30.25, longitude: 120.16,
    status: 'wantToGo', preferenceLevel: 'normal', overallRating: null,
    foodRating: null, environmentRating: null, serviceRating: null, valueRating: null,
    tags: [], longTermNote: '', pricePerPerson: null, phone: null, openingHours: null,
    markerType: 'emoji', markerPhotoId: null, merchantImageUrl: null, markerEmoji: '🍣',
    placeIdentities: [{ provider: 'apple_maps', externalId, isPrimary: true,
      createdAt: timestamp, updatedAt: timestamp }],
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null, isTestData: true,
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

async function pushOne(userID, item) {
  const response = await post(userID, '/api/v1/sync/push', {
    apiVersion: 1, schemaVersion: 1, mutations: [item],
  })
  const acknowledgement = response.acknowledgements[0]
  if (!acknowledgement || acknowledgement.status !== 'applied') {
    throw new Error(`Mutation ${item.mutationId} failed: ${acknowledgement?.conflictReason ?? 'missing'}`)
  }
  return acknowledgement
}

async function rawPush(userID, item) {
  const response = await raw(userID, '/api/v1/sync/push', 'POST', {
    apiVersion: 1, schemaVersion: 1, mutations: [item],
  })
  const value = await response.json().catch(() => ({}))
  return { status: response.status, ok: response.ok, ...value }
}

function pull(userID, cursor) {
  return get(userID, `/api/v1/sync/pull?schemaVersion=1&cursor=${cursor}&limit=200`)
}
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
    headers: {
      'X-Taste-Map-Test-User': userID,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  })
}
function assert(condition, message) { if (!condition) throw new Error(message) }
