import { randomBytes, randomUUID } from 'node:crypto'

const baseURL = process.env.TASTEMAP_API_DEV_BASE_URL?.trim().replace(/\/$/, '')
if (baseURL !== 'https://api-dev.tastemap.cn') {
  throw new Error('Task 12 Development smoke only accepts https://api-dev.tastemap.cn')
}

const runID = randomUUID()
const userA = `task12:${runID}:a`
const userB = `task12:${runID}:b`
const restaurantID = `task12-restaurant-${runID}`
const timestamp = new Date().toISOString()

await pull(userA)
await pull(userB)

const restaurantMutation = {
  mutationId: `${runID}:restaurant-create`,
  entityType: 'restaurant',
  entityId: restaurantID,
  operation: 'upsert',
  baseVersion: 0,
  clientTimestamp: timestamp,
  payload: {
    schemaVersion: 1,
    id: restaurantID,
    userId: userB,
    name: 'Task 12 Development deletion fixture',
    address: 'Development D1 only',
    city: 'Development',
    latitude: 30.2741,
    longitude: 120.1551,
    status: 'wantToGo',
    preferenceLevel: 'normal',
    overallRating: null,
    foodRating: null,
    environmentRating: null,
    serviceRating: null,
    valueRating: null,
    tags: [],
    longTermNote: '',
    pricePerPerson: null,
    phone: null,
    openingHours: null,
    markerType: 'emoji',
    markerPhotoId: null,
    merchantImageUrl: null,
    markerEmoji: '🧪',
    placeIdentities: [{
      provider: 'apple_maps',
      externalId: `task12-apple-${runID}`,
      isPrimary: true,
      createdAt: timestamp,
      updatedAt: timestamp,
    }],
    createdAt: timestamp,
    updatedAt: timestamp,
    deletedAt: null,
  },
}
const pushed = await json(userA, '/api/v1/sync/push', 'POST', {
  apiVersion: 1, schemaVersion: 1, mutations: [restaurantMutation],
})
assert(pushed.acknowledgements[0]?.status === 'applied', 'Development Restaurant was not created')
const owned = (await pull(userA)).restaurants.find((item) => item.record.id === restaurantID)
assert(owned?.record.userId === userA, 'Worker did not override forged ownership')
assert(!(await pull(userB)).restaurants.some((item) => item.record.id === restaurantID), 'User B read user A data')

const reportRequest = {
  apiVersion: 1,
  requestId: randomUUID(),
  contentType: 'user',
  contentId: userB,
  reason: 'other',
  details: 'Task 12 isolated Development verification',
}
const report = await json(userA, '/api/v1/community/reports', 'POST', reportRequest)
const repeatedReport = await json(userA, '/api/v1/community/reports', 'POST', reportRequest)
assert(report.status === 'pending' && repeatedReport.reportId === report.reportId && repeatedReport.duplicate,
  'Development report idempotency failed')

const block = await json(userA, `/api/v1/community/blocks/${encodeURIComponent(userB)}`, 'PUT')
const repeatedBlock = await json(userA, `/api/v1/community/blocks/${encodeURIComponent(userB)}`, 'PUT')
assert(block.blocked && repeatedBlock.blocked && repeatedBlock.duplicate, 'Development block idempotency failed')
const unblock = await json(userA, `/api/v1/community/blocks/${encodeURIComponent(userB)}`, 'DELETE')
assert(!unblock.blocked, 'Development unblock failed')

const preview = await json(userA, '/api/v1/account-deletion/preview')
assert(preview.userId === userA && preview.entityCounts.restaurants === 1,
  'Account deletion preview did not remain current-user scoped')

const deletionToken = `tm_delete_${randomBytes(32).toString('base64url')}`
const deletion = await json(userA, '/api/v1/account-deletion/confirm', 'POST', {
  apiVersion: 1,
  requestId: randomUUID(),
  statusToken: deletionToken,
  confirmation: 'DELETE',
})
assert(deletion.status === 'completed' && deletion.completedAt, 'Development account deletion did not complete')

const status = await json(null, '/api/v1/account-deletion/status', 'GET', undefined, deletionToken)
const repeatedStatus = await json(null, '/api/v1/account-deletion/status', 'GET', undefined, deletionToken)
assert(status.jobId === deletion.jobId && repeatedStatus.jobId === deletion.jobId,
  'Durable deletion status lookup was not stable')
assert((await raw(userA, '/api/v1/sync/pull?schemaVersion=1&cursor=0')).status === 401,
  'Deleted Development identity could still access sync')

// Remove the second isolated fixture user through the same production-shaped
// path. Durable job/report audit rows remain intentionally in Development.
const tokenB = `tm_delete_${randomBytes(32).toString('base64url')}`
const deletionB = await json(userB, '/api/v1/account-deletion/confirm', 'POST', {
  apiVersion: 1,
  requestId: randomUUID(),
  statusToken: tokenB,
  confirmation: 'DELETE',
})
assert(deletionB.status === 'completed', 'Second isolated Development fixture was not deleted')

console.log(JSON.stringify({
  result: 'Task 12 Development release-safety E2E passed',
  baseURL,
  deletionJobID: deletion.jobId,
  moderationReportID: report.reportId,
  ownershipIsolation: 'passed',
  productionAccessed: false,
}, null, 2))

function pull(userID) {
  return json(userID, '/api/v1/sync/pull?schemaVersion=1&cursor=0&limit=200')
}

async function json(userID, path, method = 'GET', body, deletionToken) {
  const response = await raw(userID, path, method, body, deletionToken)
  const value = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${value.error ?? response.statusText}`)
  return value
}

function raw(userID, path, method = 'GET', body, deletionToken) {
  const headers = new Headers({ Accept: 'application/json' })
  if (userID) headers.set('X-Taste-Map-Test-User', userID)
  if (deletionToken) headers.set('X-Taste-Map-Deletion-Token', deletionToken)
  if (body !== undefined) headers.set('Content-Type', 'application/json')
  return fetch(`${baseURL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}
