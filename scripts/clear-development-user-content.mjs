const EXPECTED_BASE_URL = 'https://api-dev.tastemap.cn'
const COLLECTIONS = {
  restaurant: 'restaurants',
  visit: 'visits',
  dish: 'dishes',
  visitDish: 'visitDishes',
  photo: 'photos',
  companion: 'companions',
  recommendationSource: 'recommendationSources',
  restaurantList: 'restaurantLists',
  restaurantListItem: 'restaurantListItems',
}
const DELETE_ORDER = [
  'photo', 'visitDish', 'dish', 'restaurantListItem', 'visit',
  'restaurantList', 'companion', 'recommendationSource', 'restaurant',
]

const options = parseArguments(process.argv.slice(2))
const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (options.environment !== 'development') fail('This cleanup requires --environment development.')
if (baseURL !== EXPECTED_BASE_URL || new URL(baseURL).hostname !== 'api-dev.tastemap.cn') {
  fail(`This cleanup only accepts ${EXPECTED_BASE_URL}; no fallback is allowed.`)
}
if (!/^tm_[A-Za-z0-9_-]{8,}$/.test(options.userID) || options.userID.startsWith('tm_demo_')) {
  fail('A valid non-demo Taste Map user ID is required with --user-id.')
}

const before = await pullAll(options.userID)
const live = DELETE_ORDER.flatMap((entityType) =>
  [...before[COLLECTIONS[entityType]].values()].map((envelope) => ({
    entityType,
    entityId: envelope.record.id,
    baseVersion: envelope.serverVersion,
  })),
)
const beforeCounts = counts(before)

if (!options.execute) {
  console.log(JSON.stringify({
    mode: 'dry-run', environment: 'development', baseURL, userID: options.userID,
    preserved: { profile: before.profiles.size }, delete: beforeCounts,
    deletionCount: live.length,
    instruction: 'Re-run with --execute after confirming this exact user and count.',
  }, null, 2))
  process.exit(0)
}

const runID = `private-cleanup-${Date.now()}`
let applied = 0
for (let index = 0; index < live.length; index += 10) {
  const mutations = live.slice(index, index + 10).map((entity, batchIndex) => ({
    mutationId: `${runID}-${entity.entityType}-${index + batchIndex}`,
    entityType: entity.entityType,
    entityId: entity.entityId,
    operation: 'delete',
    baseVersion: entity.baseVersion,
    clientTimestamp: new Date().toISOString(),
  }))
  const response = await api(options.userID, '/api/v1/sync/push', {
    method: 'POST', body: { apiVersion: 1, schemaVersion: 1, mutations },
  })
  for (const acknowledgement of response.acknowledgements ?? []) {
    if (acknowledgement.status !== 'applied') {
      fail(`Cleanup conflict for ${acknowledgement.entityType}:${acknowledgement.entityId}: ${acknowledgement.conflictReason ?? 'unknown'}`)
    }
    applied += 1
  }
}

const after = await pullAll(options.userID)
const afterCounts = counts(after)
const remaining = Object.values(afterCounts).reduce((sum, value) => sum + value, 0)
if (remaining !== 0) fail(`Cleanup verification found ${remaining} live records: ${JSON.stringify(afterCounts)}`)

console.log(JSON.stringify({
  mode: 'executed', environment: 'development', baseURL, userID: options.userID,
  preserved: { profile: after.profiles.size }, before: beforeCounts, after: afterCounts,
  deletionCount: live.length, applied, finalCursor: after.cursor,
}, null, 2))

async function pullAll(userID) {
  let cursor = '0'
  const collected = Object.fromEntries([
    ...Object.values(COLLECTIONS), 'profiles',
  ].map((collection) => [collection, new Map()]))
  while (true) {
    const page = await api(userID, `/api/v1/sync/pull?schemaVersion=1&cursor=${encodeURIComponent(cursor)}&limit=200`)
    for (const collection of [...Object.values(COLLECTIONS), 'profiles']) {
      for (const envelope of page[collection] ?? []) {
        const id = envelope.record.id ?? envelope.record.userId
        collected[collection].set(id, envelope)
      }
    }
    for (const tombstone of page.tombstones ?? []) {
      const collection = COLLECTIONS[tombstone.entityType]
      if (collection) collected[collection].delete(tombstone.entityId)
    }
    if (!page.hasMore) return { ...collected, cursor: page.nextCursor }
    if (page.nextCursor === cursor) fail(`Sync cursor did not advance for ${userID}.`)
    cursor = page.nextCursor
  }
}

function counts(state) {
  return Object.fromEntries(Object.entries(COLLECTIONS).map(([type, collection]) => [type, state[collection].size]))
}

async function api(userID, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      'X-Taste-Map-Test-User': userID,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  })
  const payload = await response.json().catch(() => ({ error: 'non-JSON response' }))
  if (!response.ok) fail(`${method} ${path} failed (${response.status}): ${JSON.stringify(payload)}`)
  return payload
}

function parseArguments(args) {
  const options = { environment: '', userID: '', execute: false }
  for (let index = 0; index < args.length; index += 1) {
    const name = args[index]
    if (name === '--execute') options.execute = true
    else if (name === '--environment') options.environment = args[++index] ?? ''
    else if (name === '--user-id') options.userID = args[++index] ?? ''
    else fail(`Unknown argument: ${name}`)
  }
  return options
}

function fail(message) {
  throw new Error(message)
}
