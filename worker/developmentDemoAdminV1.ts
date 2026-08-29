const DEMO_NAMESPACE = 'tm_demo_v2'
const DEMO_ADMIN_USER_ID = `${DEMO_NAMESPACE}_admin`
const DEMO_USER_IDS = Array.from(
  { length: 50 },
  (_, index) => `${DEMO_NAMESPACE}_user_${String(index + 1).padStart(2, '0')}`,
)
const DEMO_USER_PLACEHOLDERS = DEMO_USER_IDS.map(() => '?').join(', ')
const MAX_CURRENT_ENTITY_COUNT = 1_500

type DemoEntityType =
  | 'restaurant'
  | 'visit'
  | 'dish'
  | 'visitDish'
  | 'photo'
  | 'companion'
  | 'recommendationSource'
  | 'restaurantList'
  | 'restaurantListItem'

interface DevelopmentEnvironment {
  APP_ENVIRONMENT?: 'development' | 'production'
  SYNC_AUTH_MODE?: 'cloudflare-access' | 'development-test'
}

interface CleanupEntity {
  entityType: DemoEntityType
  entityId: string
}

export class DevelopmentDemoAdminV1Error extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
    this.name = 'DevelopmentDemoAdminV1Error'
  }
}

export async function handleDevelopmentDemoAdminV1(
  request: Request,
  database: D1Database,
  viewerId: string,
  environment: DevelopmentEnvironment,
) {
  requireIsolatedDevelopmentRequest(request, viewerId, environment)
  const url = new URL(request.url)
  if (url.pathname === '/api/v1/development/demo-data/summary' && request.method === 'GET') {
    return readDevelopmentDemoSummary(database)
  }
  if (url.pathname === '/api/v1/development/demo-data' && request.method === 'DELETE') {
    const body = await cleanupBody(request)
    const before = await readDevelopmentDemoSummary(database)
    await clearCurrentManifest(database, body.currentUserId, body.currentEntities)
    await clearDemoNamespace(database, body.currentUserId)
    return {
      apiVersion: 1,
      namespace: DEMO_NAMESPACE,
      currentUserId: body.currentUserId,
      clearedCurrentEntityCount: body.currentEntities.length,
      before,
      after: await readDevelopmentDemoSummary(database),
    }
  }
  throw new DevelopmentDemoAdminV1Error('Development demo-data route was not found.', 404)
}

export function requireIsolatedDevelopmentRequest(
  request: Request,
  viewerId: string,
  environment: DevelopmentEnvironment,
) {
  if (environment.APP_ENVIRONMENT !== 'development' || environment.SYNC_AUTH_MODE !== 'development-test') {
    throw new DevelopmentDemoAdminV1Error('Development demo administration is disabled.', 404)
  }
  if (new URL(request.url).hostname !== 'api-dev.tastemap.cn') {
    throw new DevelopmentDemoAdminV1Error('Development demo administration requires the exact Development host.', 404)
  }
  if (viewerId !== DEMO_ADMIN_USER_ID) {
    throw new DevelopmentDemoAdminV1Error('Development demo administrator identity is required.', 403)
  }
}

async function cleanupBody(request: Request): Promise<{
  currentUserId: string
  currentEntities: CleanupEntity[]
}> {
  const raw: unknown = await request.json().catch(() => {
    throw new DevelopmentDemoAdminV1Error('Development demo cleanup body is invalid.', 400)
  })
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new DevelopmentDemoAdminV1Error('Development demo cleanup body is invalid.', 400)
  }
  const body = raw as Record<string, unknown>
  const currentUserId = typeof body.currentUserId === 'string' ? body.currentUserId : ''
  if (!validCurrentUserId(currentUserId)) {
    throw new DevelopmentDemoAdminV1Error('Development current user identity is invalid.', 400)
  }
  if (!Array.isArray(body.currentEntities) || body.currentEntities.length > MAX_CURRENT_ENTITY_COUNT) {
    throw new DevelopmentDemoAdminV1Error('Development current-user manifest is invalid.', 400)
  }
  const expectedPrefix = currentManifestPrefix(currentUserId)
  const unique = new Set<string>()
  const currentEntities = body.currentEntities.map((value): CleanupEntity => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new DevelopmentDemoAdminV1Error('Development current-user manifest entity is invalid.', 400)
    }
    const item = value as Record<string, unknown>
    if (!isEntityType(item.entityType) || typeof item.entityId !== 'string' ||
      !item.entityId.startsWith(`${expectedPrefix}_`)) {
      throw new DevelopmentDemoAdminV1Error('Development current-user manifest escaped its exact namespace.', 400)
    }
    const key = `${item.entityType}:${item.entityId}`
    if (unique.has(key)) throw new DevelopmentDemoAdminV1Error('Development current-user manifest contains duplicates.', 400)
    unique.add(key)
    return { entityType: item.entityType, entityId: item.entityId }
  })
  return { currentUserId, currentEntities }
}

async function clearCurrentManifest(
  database: D1Database,
  currentUserId: string,
  entities: CleanupEntity[],
) {
  const byType = new Map<DemoEntityType, string[]>()
  for (const entity of entities) {
    byType.set(entity.entityType, [...(byType.get(entity.entityType) ?? []), entity.entityId])
  }
  const statements: D1PreparedStatement[] = []
  const restaurantIds = byType.get('restaurant') ?? []
  const dishIds = byType.get('dish') ?? []
  statements.push(...deleteByIds(database, 'restaurant_place_identities', 'restaurant_id', restaurantIds))
  // Dish upserts create one compatibility VisitDish whose ID is server-owned.
  // Select it only through exact manifest Dish IDs before deleting the Dish.
  for (const chunk of chunks(dishIds, 40)) {
    const placeholders = chunk.map(() => '?').join(', ')
    for (const table of ['sync_mutation_receipts_v6', 'sync_change_log_v6']) {
      statements.push(database.prepare(`DELETE FROM ${table} WHERE user_id = ?
        AND entity_type = 'visitDish' AND entity_id IN (
          SELECT id FROM visit_dishes WHERE user_id = ? AND dish_id IN (${placeholders})
        )`).bind(currentUserId, currentUserId, ...chunk))
    }
    statements.push(database.prepare(`DELETE FROM visit_dishes WHERE user_id = ?
      AND dish_id IN (${placeholders})`).bind(currentUserId, ...chunk))
  }
  for (const [entityType, table, ownerColumn] of [
    ['restaurantListItem', 'restaurant_list_items', 'user_id'],
    ['restaurantList', 'restaurant_lists', 'user_id'],
    ['visitDish', 'visit_dishes', 'user_id'],
    ['dish', 'dishes', 'user_id'],
    ['photo', 'photos', 'user_id'],
    ['visit', 'visits', 'user_id'],
    ['recommendationSource', 'recommendation_sources', 'user_id'],
    ['companion', 'dining_companions', 'owner_user_id'],
    ['restaurant', 'restaurants', 'user_id'],
  ] as const) {
    statements.push(...deleteByIds(database, table, 'id', byType.get(entityType) ?? [], ownerColumn, currentUserId))
  }
  for (const table of ['sync_mutation_receipts_v6', 'sync_change_log_v6']) {
    for (const chunk of chunks(entities, 40)) {
      const clauses = chunk.map(() => '(entity_type = ? AND entity_id = ?)').join(' OR ')
      statements.push(database.prepare(`DELETE FROM ${table} WHERE user_id = ? AND (${clauses})`)
        .bind(currentUserId, ...chunk.flatMap((entity) => [entity.entityType, entity.entityId])))
    }
  }
  // Only edges to the exact demo-user set belong to this seed manifest.
  statements.push(
    database.prepare(`DELETE FROM follows WHERE follower_id = ? AND
      followed_user_id IN (${DEMO_USER_PLACEHOLDERS})`).bind(currentUserId, ...DEMO_USER_IDS),
    database.prepare(`DELETE FROM follows WHERE followed_user_id = ? AND
      follower_id IN (${DEMO_USER_PLACEHOLDERS})`).bind(currentUserId, ...DEMO_USER_IDS),
    database.prepare(`DELETE FROM friendships WHERE requester_id = ? AND
      addressee_id IN (${DEMO_USER_PLACEHOLDERS})`).bind(currentUserId, ...DEMO_USER_IDS),
    database.prepare(`DELETE FROM friendships WHERE addressee_id = ? AND
      requester_id IN (${DEMO_USER_PLACEHOLDERS})`).bind(currentUserId, ...DEMO_USER_IDS),
  )
  if (statements.length) await database.batch(statements)
}

async function clearDemoNamespace(database: D1Database, currentUserId: string) {
  const inDemo = (column: string) => `${column} IN (${DEMO_USER_PLACEHOLDERS})`
  const statements = [
    database.prepare(`DELETE FROM social_search_rate_limits WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM discovery_rate_limits WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM public_api_rate_limits WHERE ${inDemo('actor_key')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM recommendation_events WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM companion_link_requests WHERE ${inDemo('requester_user_id')} OR ${inDemo('target_user_id')}`)
      .bind(...DEMO_USER_IDS, ...DEMO_USER_IDS),
    database.prepare(`DELETE FROM shared_meal_participants WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM shared_meal_participants WHERE shared_meal_id IN
      (SELECT id FROM shared_meals WHERE ${inDemo('created_by_user_id')})`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM shared_meals WHERE ${inDemo('created_by_user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM follows WHERE ${inDemo('follower_id')} OR ${inDemo('followed_user_id')}`)
      .bind(...DEMO_USER_IDS, ...DEMO_USER_IDS),
    database.prepare(`DELETE FROM friendships WHERE ${inDemo('requester_id')} OR ${inDemo('addressee_id')}`)
      .bind(...DEMO_USER_IDS, ...DEMO_USER_IDS),
    database.prepare(`DELETE FROM restaurant_list_items WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM restaurant_lists WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM visit_dishes WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM dishes WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM photos WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM visits WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM want_to_go WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM restaurant_place_identities WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM recommendation_sources WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM dining_companions WHERE ${inDemo('owner_user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM restaurants WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM sync_mutation_receipts_v6 WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM sync_change_log_v6 WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM user_profiles WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM membership_entitlements WHERE ${inDemo('user_id')}`).bind(...DEMO_USER_IDS),
    database.prepare(`DELETE FROM users WHERE ${inDemo('id')}`).bind(...DEMO_USER_IDS),
  ]
  await database.batch(statements)

  // A second, explicit assertion turns a partial cleanup into a visible error.
  const remaining = await database.prepare(`SELECT COUNT(*) AS count FROM users WHERE ${inDemo('id')}`)
    .bind(...DEMO_USER_IDS).first<{ count: number }>()
  if (Number(remaining?.count ?? 0) !== 0) {
    throw new DevelopmentDemoAdminV1Error('Development demo user cleanup was incomplete.', 500)
  }
  // The authenticated real/dev current user must survive every cleanup.
  const current = await database.prepare('SELECT id FROM users WHERE id = ? LIMIT 1').bind(currentUserId).first()
  if (!current) throw new DevelopmentDemoAdminV1Error('Development current user was removed unexpectedly.', 500)
}

async function readDevelopmentDemoSummary(database: D1Database) {
  const inDemo = (column: string) => `${column} IN (${DEMO_USER_PLACEHOLDERS})`
  const queries = [
    ['users', `SELECT COUNT(*) AS count FROM users WHERE ${inDemo('id')}`],
    ['profiles', `SELECT COUNT(*) AS count FROM user_profiles WHERE ${inDemo('user_id')} AND deleted_at IS NULL`],
    ['restaurants', `SELECT COUNT(*) AS count FROM restaurants WHERE ${inDemo('user_id')} AND deleted_at IS NULL`],
    ['visits', `SELECT COUNT(*) AS count FROM visits WHERE ${inDemo('user_id')} AND deleted_at IS NULL`],
    ['dishes', `SELECT COUNT(*) AS count FROM dishes WHERE ${inDemo('user_id')} AND deleted_at IS NULL`],
    ['lists', `SELECT COUNT(*) AS count FROM restaurant_lists WHERE ${inDemo('user_id')} AND deleted_at IS NULL`],
    ['friendships', `SELECT COUNT(*) AS count FROM friendships WHERE deleted_at IS NULL AND
      (${inDemo('requester_id')} OR ${inDemo('addressee_id')})`],
    ['follows', `SELECT COUNT(*) AS count FROM follows WHERE deleted_at IS NULL AND
      (${inDemo('follower_id')} OR ${inDemo('followed_user_id')})`],
  ] as const
  const values = await Promise.all(queries.map(async ([key, sql]) => {
    const repeats = sql.split(DEMO_USER_PLACEHOLDERS).length - 1
    const result = await database.prepare(sql).bind(...Array.from({ length: repeats }, () => DEMO_USER_IDS).flat())
      .first<{ count: number }>()
    return [key, Number(result?.count ?? 0)] as const
  }))
  return { namespace: DEMO_NAMESPACE, ...Object.fromEntries(values) }
}

function deleteByIds(
  database: D1Database,
  table: string,
  idColumn: string,
  ids: string[],
  ownerColumn?: string,
  ownerId?: string,
) {
  return chunks(ids, 50).map((chunk) => {
    const ownerClause = ownerColumn ? `${ownerColumn} = ? AND ` : ''
    return database.prepare(`DELETE FROM ${table} WHERE ${ownerClause}${idColumn} IN (${chunk.map(() => '?').join(', ')})`)
      .bind(...(ownerColumn ? [ownerId, ...chunk] : chunk))
  })
}

function chunks<T>(values: T[], size: number) {
  const result: T[][] = []
  for (let index = 0; index < values.length; index += size) result.push(values.slice(index, index + size))
  return result
}

function isEntityType(value: unknown): value is DemoEntityType {
  return [
    'restaurant', 'visit', 'dish', 'visitDish', 'photo', 'companion',
    'recommendationSource', 'restaurantList', 'restaurantListItem',
  ].includes(String(value))
}

function validCurrentUserId(value: string) {
  return /^[a-zA-Z0-9:_-]{1,80}$/.test(value) && value !== DEMO_ADMIN_USER_ID && !DEMO_USER_IDS.includes(value)
}

function currentManifestPrefix(userId: string) {
  return `${DEMO_NAMESPACE}_current_${hash32(userId).toString(16).padStart(8, '0')}`
}

function hash32(value: string) {
  let hash = 2166136261
  for (const character of value) {
    hash ^= character.codePointAt(0) ?? 0
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}
