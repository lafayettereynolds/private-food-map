import {
  buildDevelopmentDemoDataset,
  DEVELOPMENT_DEMO_ADMIN_USER_ID,
  entityMutation,
} from './development-demo-data.mjs'

const EXPECTED_BASE_URL = 'https://api-dev.tastemap.cn'
const REMOTE_MUTATION_BATCH_SIZE = 10
const ENTITY_COLLECTIONS = {
  restaurant: 'restaurants', visit: 'visits', dish: 'dishes', visitDish: 'visitDishes',
  photo: 'photos', companion: 'companions', recommendationSource: 'recommendationSources',
  profile: 'profiles', restaurantList: 'restaurantLists', restaurantListItem: 'restaurantListItems',
}

const options = parseArguments(process.argv.slice(2))
const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (options.environment !== 'development') fail('The demo seeder requires --environment development.')
if (baseURL !== EXPECTED_BASE_URL || new URL(baseURL).hostname !== 'api-dev.tastemap.cn') {
  fail(`The demo seeder only accepts ${EXPECTED_BASE_URL}; no fallback is allowed.`)
}
const currentUserID = options.currentUserID || process.env.TASTEMAP_DEVELOPMENT_CURRENT_USER_ID?.trim()
const dataset = buildDevelopmentDemoDataset({ currentUserID, referenceNow: options.referenceNow })

const startedAt = performance.now()
const report = {
  action: options.action,
  environment: 'development',
  baseURL,
  productionAccessed: false,
  referenceDay: dataset.referenceDay,
  currentUserID: dataset.currentUserID,
  expected: dataset.summary,
  timings: {},
}

if (options.action === 'clear') {
  report.cleanup = await clearDataset()
} else if (options.action === 'seed') {
  report.seed = await seedDataset()
  report.verification = await verifyDataset()
} else if (options.action === 'reseed') {
  report.cleanup = await clearDataset()
  report.seed = await seedDataset()
  report.verification = await verifyDataset()
} else if (options.action === 'verify') {
  report.verification = await verifyDataset()
} else {
  fail('Command must be one of seed, clear, reseed, or verify.')
}
report.timings.totalSeconds = secondsSince(startedAt)
console.log(JSON.stringify(report, null, 2))

async function clearDataset() {
  const start = performance.now()
  const result = await api(DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data', {
    method: 'DELETE',
    body: {
      currentUserId: dataset.currentUserID,
      currentEntities: dataset.currentUser.records.map((record) => ({
        entityType: record.entityType,
        entityId: record.entityID,
      })),
    },
  })
  if (Object.entries(result.after).some(([key, value]) => key !== 'namespace' && Number(value) !== 0)) {
    throw new Error(`Development namespace cleanup was incomplete: ${JSON.stringify(result.after)}`)
  }
  report.timings.cleanupSeconds = secondsSince(start)
  return result
}

async function seedDataset() {
  const currentStart = performance.now()
  const current = await pushAccount(dataset.currentUser)
  report.timings.currentUserSeedSeconds = secondsSince(currentStart)

  const demoStart = performance.now()
  const demoResults = await concurrentMap(dataset.demoUsers, 6, async (account, index) => {
    const result = await pushAccount(account)
    process.stderr.write(`[demo-seed] ${index + 1}/${dataset.demoUsers.length} ${account.ownerID} complete\n`)
    return result
  })
  report.timings.serverDemoSeedSeconds = secondsSince(demoStart)

  const socialStart = performance.now()
  const relationshipResult = await seedRelationships()
  report.timings.relationshipSeedSeconds = secondsSince(socialStart)
  return { current, demo: combinePushResults(demoResults), relationships: relationshipResult }
}

async function pushAccount(account) {
  let applied = 0
  let duplicate = 0
  let batches = 0
  for (let index = 0; index < account.records.length; index += REMOTE_MUTATION_BATCH_SIZE) {
    const mutations = account.records.slice(index, index + REMOTE_MUTATION_BATCH_SIZE)
      .map((record) => entityMutation(record, dataset.referenceDay))
    const result = await api(account.ownerID, '/api/v1/sync/push', {
      method: 'POST', body: { apiVersion: 1, schemaVersion: 1, mutations },
    })
    batches += 1
    for (const acknowledgement of result.acknowledgements) {
      if (acknowledgement.status !== 'applied') {
        throw new Error(`Sync conflict for ${account.ownerID}/${acknowledgement.entityType}/${acknowledgement.entityId}: ${acknowledgement.conflictReason ?? 'unknown conflict'}. Run reseed for a new reference day.`)
      }
      if (acknowledgement.duplicate) duplicate += 1
      else applied += 1
    }
  }
  return { ownerID: account.ownerID, records: account.records.length, batches, applied, duplicate }
}

async function seedRelationships() {
  let friendshipsApplied = 0
  let friendshipsDuplicate = 0
  await concurrentMap(dataset.relationships.friendships, 6, async (relationship) => {
    const requested = await api(relationship.requesterID, '/api/v1/social/friendships', {
      method: 'POST', body: { targetUserId: relationship.addresseeID },
    })
    const accepted = await api(
      relationship.addresseeID,
      `/api/v1/social/friendships/${encodeURIComponent(requested.friendship.id)}`,
      { method: 'POST', body: { action: 'accept' } },
    )
    if (requested.duplicate && accepted.duplicate) friendshipsDuplicate += 1
    else friendshipsApplied += 1
  })
  let followsApplied = 0
  let followsDuplicate = 0
  await concurrentMap(dataset.relationships.follows, 8, async (relationship) => {
    const result = await api(
      relationship.followerID,
      `/api/v1/social/follows/${encodeURIComponent(relationship.followedUserID)}`,
      { method: 'PUT' },
    )
    if (result.duplicate) followsDuplicate += 1
    else followsApplied += 1
  })
  return {
    friendships: { total: dataset.relationships.friendships.length, applied: friendshipsApplied, duplicate: friendshipsDuplicate },
    follows: { total: dataset.relationships.follows.length, applied: followsApplied, duplicate: followsDuplicate },
  }
}

async function verifyDataset() {
  const start = performance.now()
  let verifiedAccountCount = 0
  const accounts = await concurrentMap(dataset.accounts, 3, async (account) => {
    const pulled = await pullAll(account.ownerID)
    const actual = new Map()
    for (const [entityType, collection] of Object.entries(ENTITY_COLLECTIONS)) {
      for (const envelope of pulled[collection].values()) {
        actual.set(`${entityType}:${envelope.record.id ?? envelope.record.userId}`, envelope)
      }
    }
    const missing = account.records.filter((record) => !actual.has(`${record.entityType}:${record.entityID}`))
    if (missing.length) {
      throw new Error(`${account.ownerID} is missing ${missing.length} manifest records; first=${missing[0].entityType}:${missing[0].entityID}`)
    }
    verifiedAccountCount += 1
    process.stderr.write(
      `[demo-verify] ${verifiedAccountCount}/${dataset.accounts.length} ${account.ownerID} ` +
      `${account.records.length} records complete\n`,
    )
    return {
      ownerID: account.ownerID,
      expectedRecordCount: account.records.length,
      verifiedRecordCount: account.records.length,
      pages: pulled.pages,
      cursor: pulled.cursor,
    }
  })
  const summary = await api(DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data/summary')
  const algorithms = await verifyProductAlgorithms()
  report.timings.syncVerificationSeconds = secondsSince(start)
  return { summary, currentUser: accounts[0], demoAccounts: accounts.slice(1), algorithms }
}

async function pullAll(userID) {
  let cursor = '0'
  let pages = 0
  const collected = Object.fromEntries(Object.values(ENTITY_COLLECTIONS).map((key) => [key, new Map()]))
  while (true) {
    const page = await api(userID, `/api/v1/sync/pull?schemaVersion=1&cursor=${encodeURIComponent(cursor)}&limit=50`)
    pages += 1
    for (const collection of Object.values(ENTITY_COLLECTIONS)) {
      for (const envelope of page[collection]) {
        const id = envelope.record.id ?? envelope.record.userId
        collected[collection].set(id, envelope)
      }
    }
    for (const tombstone of page.tombstones) collected[ENTITY_COLLECTIONS[tombstone.entityType]]?.delete(tombstone.entityId)
    if (!page.hasMore) return { ...collected, pages, cursor: page.nextCursor }
    if (page.nextCursor === cursor) throw new Error(`Sync cursor did not advance for ${userID}.`)
    cursor = page.nextCursor
  }
}

async function verifyProductAlgorithms() {
  const [similarTaste, trending7Day, trending30Day, community] = await Promise.all([
    '/api/v1/discovery/similar-taste?city=%E6%9D%AD%E5%B7%9E&limit=50',
    '/api/v1/discovery/trending?city=%E6%9D%AD%E5%B7%9E&window=7&limit=50',
    '/api/v1/discovery/trending?city=%E6%9D%AD%E5%B7%9E&window=30&limit=50',
    '/api/v1/community/feed?scope=latest&limit=50',
  ].map((path) => api(dataset.currentUserID, path)))
  // Include public personas plus Demo 31, whose friends-only profile is
  // intentionally accessible through the seeded accepted friendship.
  const profileIDs = [1, 18, 31, 45].map((index) => dataset.demoUsers[index - 1].ownerID)
  const profiles = await Promise.all(profileIDs.map(async (userID) => ({
    userID,
    profile: await api(dataset.currentUserID, `/api/v1/public/profiles/${encodeURIComponent(userID)}`),
    content: await api(dataset.currentUserID, `/api/v1/community/users/${encodeURIComponent(userID)}/content?section=visits&limit=10`),
  })))
  const sevenKeys = new Set(trending7Day.items.map((item) => item.restaurant.globalKey))
  const thirtyKeys = new Set(trending30Day.items.map((item) => item.restaurant.globalKey))
  const differentWindows = [...sevenKeys].some((key) => !thirtyKeys.has(key)) || [...thirtyKeys].some((key) => !sevenKeys.has(key))
  if (!similarTaste.items.length) throw new Error('Real Similar Taste returned no Development results.')
  if (!trending7Day.items.length || !trending30Day.items.length || !differentWindows) {
    throw new Error('Real Trending did not produce distinct non-empty 7-day and 30-day results.')
  }
  if (community.items.length < 20 || new Set(community.items.map((item) => item.user.userId)).size < 10) {
    throw new Error('Real Community did not produce a sufficiently varied first page.')
  }
  return {
    similarTaste: summarizeDiscovery(similarTaste),
    trending7Day: summarizeDiscovery(trending7Day),
    trending30Day: summarizeDiscovery(trending30Day),
    trendingWindowsDistinct: differentWindows,
    community: {
      itemCount: community.items.length,
      distinctUserCount: new Set(community.items.map((item) => item.user.userId)).size,
      kinds: countBy(community.items, (item) => item.kind),
    },
    publicProfiles: profiles.map(({ userID, profile, content }) => ({
      userID, displayName: profile.displayName, visibility: profile.visibility,
      visibleVisitCount: content.statistics.visibleVisitCount, returnedVisitCount: content.items.length,
    })),
  }
}

function summarizeDiscovery(page) {
  return {
    itemCount: page.items.length,
    top: page.items.slice(0, 10).map((item) => ({
      rank: item.rank,
      restaurant: item.restaurant.name,
      globalKey: item.restaurant.globalKey,
      sourceUserID: item.sourceUser?.userId ?? null,
      similarity: item.similarity ?? null,
      trend: item.trend ?? null,
    })),
  }
}

async function api(userID, path, { method = 'GET', body } = {}) {
  let lastError
  for (let attempt = 0; attempt < 12; attempt += 1) {
    try {
      const response = await fetch(`${baseURL}${path}`, {
        method,
        headers: {
          'X-Taste-Map-Test-User': userID,
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      })
      const payload = await response.json().catch(() => ({ error: 'non-JSON response' }))
      if (response.ok) return payload
      const error = new Error(`${method} ${path} failed (${response.status}): ${JSON.stringify(payload)}`)
      if (response.status < 500 && response.status !== 429) throw error
      lastError = error
    } catch (error) {
      lastError = error
      if (String(error).includes('failed (4') && !String(error).includes('429')) throw error
    }
    await new Promise((resolve) => setTimeout(resolve, Math.min(5_000, 500 * 2 ** attempt)))
  }
  throw lastError
}

async function concurrentMap(values, concurrency, operation) {
  const results = new Array(values.length)
  let nextIndex = 0
  const workers = Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (nextIndex < values.length) {
      const index = nextIndex
      nextIndex += 1
      results[index] = await operation(values[index], index)
    }
  })
  await Promise.all(workers)
  return results
}

function combinePushResults(results) {
  return results.reduce((combined, result) => ({
    accounts: combined.accounts + 1, records: combined.records + result.records,
    batches: combined.batches + result.batches, applied: combined.applied + result.applied,
    duplicate: combined.duplicate + result.duplicate,
  }), { accounts: 0, records: 0, batches: 0, applied: 0, duplicate: 0 })
}

function countBy(values, key) {
  return values.reduce((counts, value) => {
    const item = key(value)
    counts[item] = (counts[item] ?? 0) + 1
    return counts
  }, {})
}

function secondsSince(start) { return Math.round((performance.now() - start) / 10) / 100 }

function parseArguments(args) {
  const options = { action: args[0] ?? '', environment: '', currentUserID: '', referenceNow: undefined }
  for (let index = 1; index < args.length; index += 1) {
    const name = args[index]
    const value = args[index + 1]
    if (name === '--environment') options.environment = value
    else if (name === '--current-user-id') options.currentUserID = value
    else if (name === '--reference-now') options.referenceNow = value
    else fail(`Unknown argument: ${name}`)
    index += 1
  }
  return options
}

function fail(message) { throw new Error(message) }
