import type {
  CompanionLinkActionV1,
  CompanionLinkPageV1,
  CompanionLinkRequestV1,
  CompanionLinkScopeV1,
  SharedMealInvitationV1,
  SharedMealInviteResponseV1,
  SharedMealPageV1,
  SharedMealScopeV1,
  SocialSuggestionPageV1,
} from '../src/contracts/socialCollaborationContract'
import type { PublicContentPlaceIdentityV1, PublicContentRestaurantV1 } from '../src/contracts/communityContract'
import type { ProfileAvatarPresetContract } from '../src/contracts/profileContract'
import type { SocialUserResultV1, SocialUserSummaryV1 } from '../src/contracts/socialContract'
import type { RestaurantPlaceProvider } from '../src/types/restaurantIdentity'
import { consumePublicAPIQuota } from './publicAPIRateLimit'

const API_VERSION = 1
const DEFAULT_LIMIT = 20
const MAX_LIMIT = 50

interface ProfileRow {
  user_id: string
  display_name: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract
  visibility: 'private' | 'friends' | 'public'
}

interface CompanionLinkRow {
  id: string
  companion_id: string
  companion_display_name: string
  requester_user_id: string
  target_user_id: string
  status: 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'unlinked'
  created_at: string
  updated_at: string
  deleted_at: string | null
  server_version: number
}

interface SharedMealRow {
  meal_id: string
  participant_id: string
  source_visit_id: string
  created_by_user_id: string
  participant_user_id: string
  restaurant_id: string
  occurred_at: string
  visibility: 'private' | 'friends' | 'public'
  status: 'pending' | 'accepted' | 'declined' | 'revoked'
  visit_id: string | null
  created_at: string
  updated_at: string
  revoked_at: string | null
  server_version: number
  restaurant_name: string
  address: string
  city: string
  latitude: number
  longitude: number
  tags_json: string
  price_per_person: number | null
  merchant_image_url: string | null
  marker_emoji: string
}

interface IdentityRow {
  restaurant_id: string
  provider: RestaurantPlaceProvider
  external_id: string
  is_primary: number
}

export class SocialCollaborationV1Error extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

export async function handleSocialCollaborationV1(
  request: Request,
  database: D1Database,
  viewerId: string,
): Promise<SocialSuggestionPageV1 | CompanionLinkPageV1 | CompanionLinkRequestV1 |
  SharedMealPageV1 | SharedMealInviteResponseV1 | SharedMealInvitationV1> {
  const url = new URL(request.url)
  await consumePublicAPIQuota(
    database, viewerId,
    request.method === 'GET' ? 'social-collaboration-read' : 'social-collaboration-mutation',
    request.method === 'GET' ? 180 : 60,
  )
  if (url.pathname === '/api/v1/social/suggestions' && request.method === 'GET') {
    return readSuggestions(database, viewerId, url)
  }
  if (url.pathname === '/api/v1/social/companion-links' && request.method === 'GET') {
    return readCompanionLinks(database, viewerId, url)
  }
  if (url.pathname === '/api/v1/social/companion-links' && request.method === 'POST') {
    return createCompanionLink(database, viewerId, request)
  }
  const companionMatch = url.pathname.match(/^\/api\/v1\/social\/companion-links\/([^/]+)$/)
  if (companionMatch && request.method === 'POST') {
    return mutateCompanionLink(database, viewerId, decodedID(companionMatch[1]), request)
  }
  if (url.pathname === '/api/v1/social/shared-meals' && request.method === 'GET') {
    return readSharedMeals(database, viewerId, url)
  }
  if (url.pathname === '/api/v1/social/shared-meals' && request.method === 'POST') {
    return createSharedMeal(database, viewerId, request)
  }
  const participantMatch = url.pathname.match(/^\/api\/v1\/social\/shared-meals\/participants\/([^/]+)$/)
  if (participantMatch && request.method === 'POST') {
    return mutateSharedMealParticipant(database, viewerId, decodedID(participantMatch[1]), request)
  }
  const mealMatch = url.pathname.match(/^\/api\/v1\/social\/shared-meals\/([^/]+)$/)
  if (mealMatch && request.method === 'DELETE') {
    return revokeSharedMeal(database, viewerId, decodedID(mealMatch[1]))
  }
  throw new SocialCollaborationV1Error('Social collaboration endpoint was not found.', 404)
}

async function readSuggestions(database: D1Database, viewerId: string, url: URL): Promise<SocialSuggestionPageV1> {
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const viewer = await profileByID(database, viewerId)
  const rows = await database.prepare(`SELECT p.*,
      CASE WHEN follow.id IS NULL THEN 0 ELSE 1 END AS is_following,
      (SELECT COUNT(*) FROM friendships mine
       JOIN friendships theirs ON theirs.status = 'accepted' AND theirs.deleted_at IS NULL
         AND (theirs.requester_id = CASE WHEN mine.requester_id = ? THEN mine.addressee_id ELSE mine.requester_id END
           OR theirs.addressee_id = CASE WHEN mine.requester_id = ? THEN mine.addressee_id ELSE mine.requester_id END)
       WHERE mine.status = 'accepted' AND mine.deleted_at IS NULL
         AND (mine.requester_id = ? OR mine.addressee_id = ?)
         AND (theirs.requester_id = p.user_id OR theirs.addressee_id = p.user_id)) AS mutual_count
    FROM user_profiles p
    LEFT JOIN follows follow ON follow.follower_id = ? AND follow.followed_user_id = p.user_id
      AND follow.deleted_at IS NULL
    WHERE p.user_id <> ? AND p.deleted_at IS NULL AND p.visibility = 'public'
      AND NOT EXISTS (SELECT 1 FROM friendships existing
        WHERE existing.deleted_at IS NULL AND existing.status IN ('pending', 'accepted')
          AND ((existing.requester_id = ? AND existing.addressee_id = p.user_id)
            OR (existing.requester_id = p.user_id AND existing.addressee_id = ?)))
      AND (LOWER(p.display_name) > ? OR (LOWER(p.display_name) = ? AND p.user_id > ?))
    ORDER BY mutual_count DESC,
      CASE WHEN trim(p.city) <> '' AND trim(p.city) = ? THEN 0 ELSE 1 END,
      LOWER(p.display_name), p.user_id LIMIT ?`).bind(
      viewerId, viewerId, viewerId, viewerId, viewerId, viewerId, viewerId, viewerId,
      cursor.primary, cursor.primary, cursor.secondary, viewer?.city.trim() ?? '', limit + 1,
    ).all<ProfileRow & { is_following: number; mutual_count: number }>()
  const visible = rows.results.slice(0, limit)
  return {
    apiVersion: API_VERSION,
    items: visible.map((row) => ({
      user: {
        profile: publicSummary(row), friendshipId: null, friendshipState: 'none',
        isFollowing: Boolean(row.is_following),
      } satisfies SocialUserResultV1,
      reasons: [
        ...(Number(row.mutual_count) ? [`共 ${Number(row.mutual_count)} 位共同好友`] : []),
        ...(viewer?.city.trim() && row.city.trim() === viewer.city.trim() ? [`都在 ${row.city.trim()}`] : []),
      ],
    })),
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.display_name.toLocaleLowerCase(), visible.at(-1)!.user_id) : null,
  }
}

async function readCompanionLinks(database: D1Database, viewerId: string, url: URL): Promise<CompanionLinkPageV1> {
  const scope = (url.searchParams.get('scope') ?? 'incoming') as CompanionLinkScopeV1
  if (!['incoming', 'outgoing', 'active'].includes(scope)) throw new SocialCollaborationV1Error('Companion link scope is invalid.', 400)
  const limit = pageLimit(url)
  const cursor = decodeDescendingCursor(url.searchParams.get('cursor'))
  const clause = scope === 'incoming'
    ? "target_user_id = ? AND status = 'pending'"
    : scope === 'outgoing'
      ? "requester_user_id = ? AND status = 'pending'"
      : "(requester_user_id = ? OR target_user_id = ?) AND status = 'accepted'"
  const bindings: unknown[] = scope === 'active' ? [viewerId, viewerId] : [viewerId]
  const rows = await database.prepare(`SELECT * FROM companion_link_requests
    WHERE ${clause} AND deleted_at IS NULL
      AND (updated_at < ? OR (updated_at = ? AND id > ?))
    ORDER BY updated_at DESC, id ASC LIMIT ?`).bind(
      ...bindings, cursor.primary, cursor.primary, cursor.secondary, limit + 1,
    ).all<CompanionLinkRow>()
  const visible = rows.results.slice(0, limit)
  return {
    apiVersion: API_VERSION, scope,
    items: await Promise.all(visible.map((row) => companionContract(database, viewerId, row))),
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.updated_at, visible.at(-1)!.id) : null,
  }
}

async function createCompanionLink(database: D1Database, viewerId: string, request: Request) {
  const body = await objectBody(request)
  const companionID = requiredString(body.companionId, 'Companion 无效。')
  const targetUserID = requiredString(body.targetUserId, '目标用户无效。')
  if (targetUserID === viewerId) throw new SocialCollaborationV1Error('不能把 Companion 关联到自己。', 400)
  await requireAcceptedFriend(database, viewerId, targetUserID)
  const companion = await database.prepare(`SELECT id, display_name, linked_user_id FROM dining_companions
    WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(companionID, viewerId)
    .first<{ id: string; display_name: string; linked_user_id: string | null }>()
  if (!companion) throw new SocialCollaborationV1Error('没有找到这个私有饭搭子。', 404)
  if (companion.linked_user_id && companion.linked_user_id !== targetUserID) {
    throw new SocialCollaborationV1Error('这个饭搭子已经关联其他用户。', 409)
  }
  const existing = await database.prepare(`SELECT * FROM companion_link_requests
    WHERE companion_id = ? AND requester_user_id = ? AND target_user_id = ?
      AND deleted_at IS NULL AND status IN ('pending', 'accepted')
    ORDER BY updated_at DESC LIMIT 1`).bind(companionID, viewerId, targetUserID).first<CompanionLinkRow>()
  if (existing) return companionContract(database, viewerId, existing)
  const now = new Date().toISOString()
  const id = crypto.randomUUID()
  await database.prepare(`INSERT INTO companion_link_requests (
    id, companion_id, companion_display_name, requester_user_id, target_user_id,
    status, created_at, updated_at, deleted_at, server_version, is_test_data
  ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, NULL, 1, 0)`)
    .bind(id, companionID, companion.display_name, viewerId, targetUserID, now, now).run()
  return companionContract(database, viewerId, (await companionLinkByID(database, id))!)
}

async function mutateCompanionLink(database: D1Database, viewerId: string, id: string, request: Request) {
  const body = await objectBody(request)
  const action = requiredString(body.action, 'Companion link action is invalid.') as CompanionLinkActionV1
  if (!['accept', 'reject', 'cancel', 'unlink'].includes(action)) throw new SocialCollaborationV1Error('Companion link action is invalid.', 400)
  const row = await companionLinkByID(database, id)
  if (!row || (row.requester_user_id !== viewerId && row.target_user_id !== viewerId)) {
    throw new SocialCollaborationV1Error('没有找到这条饭搭子关联请求。', 404)
  }
  if (action === 'accept' || action === 'reject') {
    if (row.target_user_id !== viewerId || row.status !== 'pending' || row.deleted_at) {
      if (action === 'accept' && row.status === 'accepted' && !row.deleted_at) return companionContract(database, viewerId, row)
      throw new SocialCollaborationV1Error('只有收件人可以处理待接受请求。', 409)
    }
    await requireAcceptedFriend(database, row.requester_user_id, row.target_user_id)
    if (action === 'accept') {
      const companion = await database.prepare(`SELECT linked_user_id FROM dining_companions
        WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL LIMIT 1`)
        .bind(row.companion_id, row.requester_user_id)
        .first<{ linked_user_id: string | null }>()
      if (!companion) throw new SocialCollaborationV1Error('这个私有饭搭子已不存在。', 404)
      if (companion.linked_user_id && companion.linked_user_id !== row.target_user_id) {
        throw new SocialCollaborationV1Error('这个饭搭子已经关联其他用户。', 409)
      }
    }
  }
  if (action === 'cancel' && (row.requester_user_id !== viewerId || row.status !== 'pending' || row.deleted_at)) {
    throw new SocialCollaborationV1Error('只有发件人可以取消待接受请求。', 409)
  }
  if (action === 'unlink' && (row.status !== 'accepted' || row.deleted_at)) {
    throw new SocialCollaborationV1Error('当前没有可解除的饭搭子关联。', 409)
  }
  const now = new Date().toISOString()
  const nextStatus = action === 'accept' ? 'accepted' : action === 'reject' ? 'rejected' : action === 'cancel' ? 'cancelled' : 'unlinked'
  const nextDeleted = nextStatus === 'accepted' ? null : now
  const linkStatement = action === 'accept'
    ? database.prepare(`UPDATE dining_companions SET linked_user_id = ?, updated_at = ?,
        server_version = server_version + 1, last_mutation_id = ?
      WHERE id = ? AND owner_user_id = ? AND deleted_at IS NULL
        AND (linked_user_id IS NULL OR linked_user_id = ?)`)
      .bind(row.target_user_id, now, `social:companion:${id}:accept`, row.companion_id, row.requester_user_id, row.target_user_id)
    : action === 'unlink'
      ? database.prepare(`UPDATE dining_companions SET linked_user_id = NULL, updated_at = ?,
          server_version = server_version + 1, last_mutation_id = ?
        WHERE id = ? AND owner_user_id = ? AND linked_user_id = ? AND deleted_at IS NULL`)
        .bind(now, `social:companion:${id}:unlink`, row.companion_id, row.requester_user_id, row.target_user_id)
      : null
  const statements: D1PreparedStatement[] = [database.prepare(`UPDATE companion_link_requests
    SET status = ?, updated_at = ?, deleted_at = ?, server_version = server_version + 1
    WHERE id = ? AND server_version = ?`).bind(nextStatus, now, nextDeleted, id, row.server_version)]
  if (linkStatement) {
    const mutationID = `social:companion:${id}:${action}`
    statements.push(linkStatement, database.prepare(`INSERT OR IGNORE INTO sync_change_log_v6 (
      user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
    ) SELECT owner_user_id, 'companion', id, 'upsert', server_version, ?, ?
      FROM dining_companions WHERE id = ? AND owner_user_id = ? AND last_mutation_id = ?`)
      .bind(mutationID, now, row.companion_id, row.requester_user_id, mutationID))
  }
  await database.batch(statements)
  return companionContract(database, viewerId, (await companionLinkByID(database, id))!)
}

async function readSharedMeals(database: D1Database, viewerId: string, url: URL): Promise<SharedMealPageV1> {
  const scope = (url.searchParams.get('scope') ?? 'incoming') as SharedMealScopeV1
  if (!['incoming', 'sent', 'accepted'].includes(scope)) throw new SocialCollaborationV1Error('Shared meal scope is invalid.', 400)
  const limit = pageLimit(url)
  const cursor = decodeDescendingCursor(url.searchParams.get('cursor'))
  const clause = scope === 'sent'
    ? 'sm.created_by_user_id = ?'
    : scope === 'accepted'
      ? "smp.user_id = ? AND smp.status = 'accepted'"
      : "smp.user_id = ? AND smp.status = 'pending'"
  const rows = await database.prepare(`${sharedMealProjection}
    WHERE ${clause} AND sm.deleted_at IS NULL AND smp.deleted_at IS NULL
      AND (smp.updated_at < ? OR (smp.updated_at = ? AND smp.id > ?))
    ORDER BY smp.updated_at DESC, smp.id ASC LIMIT ?`).bind(
      viewerId, cursor.primary, cursor.primary, cursor.secondary, limit + 1,
    ).all<SharedMealRow>()
  const visible = rows.results.slice(0, limit)
  return {
    apiVersion: API_VERSION, scope,
    items: await sharedMealContracts(database, visible),
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.updated_at, visible.at(-1)!.participant_id) : null,
  }
}

async function createSharedMeal(database: D1Database, viewerId: string, request: Request): Promise<SharedMealInviteResponseV1> {
  const body = await objectBody(request)
  const sourceVisitID = requiredString(body.sourceVisitId, 'Shared Meal source Visit is invalid.')
  const mutationID = requiredString(body.mutationId, 'Shared Meal mutation ID is required.')
  const participantUserIDs = uniqueStrings(body.participantUserIds)
  if (!participantUserIDs.length || participantUserIDs.length > 20) throw new SocialCollaborationV1Error('请选择 1 到 20 位饭搭子。', 400)
  if (participantUserIDs.includes(viewerId)) throw new SocialCollaborationV1Error('不能邀请自己。', 400)
  const source = await database.prepare(`SELECT v.id, v.restaurant_id, v.visited_at, v.visibility
    FROM visits v JOIN restaurants r ON r.id = v.restaurant_id
    WHERE v.id = ? AND v.user_id = ? AND v.deleted_at IS NULL
      AND r.user_id = ? AND r.deleted_at IS NULL LIMIT 1`).bind(sourceVisitID, viewerId, viewerId)
    .first<{ id: string; restaurant_id: string; visited_at: string; visibility: 'private' | 'friends' | 'public' }>()
  if (!source) throw new SocialCollaborationV1Error('源到访记录不存在或不属于当前用户。', 404)
  for (const participant of participantUserIDs) await requireAcceptedFriend(database, viewerId, participant)
  const existing = await database.prepare(`SELECT id FROM shared_meals
    WHERE created_by_user_id = ? AND mutation_id = ? LIMIT 1`).bind(viewerId, mutationID).first<{ id: string }>()
  if (existing) {
    return { apiVersion: API_VERSION, mealId: existing.id, duplicate: true,
      invitations: await invitationsForMeal(database, existing.id) }
  }
  const now = new Date().toISOString()
  // A deterministic server ID closes the race between two concurrent retries
  // that both arrive before either can observe the idempotency row.
  const mealID = await deterministicSharedMealID(viewerId, mutationID)
  const statements: D1PreparedStatement[] = [database.prepare(`INSERT OR IGNORE INTO shared_meals (
    id, restaurant_id, created_by_user_id, occurred_at, created_at, updated_at,
    deleted_at, source_visit_id, mutation_id, visibility, revoked_at, server_version, is_test_data
  ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, NULL, 1, 0)`)
    .bind(mealID, source.restaurant_id, viewerId, source.visited_at, now, now,
      sourceVisitID, mutationID, source.visibility)]
  for (const participant of participantUserIDs) {
    statements.push(database.prepare(`INSERT OR IGNORE INTO shared_meal_participants (
      id, shared_meal_id, user_id, visit_id, status, created_at, updated_at,
      inviter_user_id, deleted_at, server_version, is_test_data
    ) VALUES (?, ?, ?, NULL, 'pending', ?, ?, ?, NULL, 1, 0)`)
      .bind(`shared-meal-participant:${mealID}:${participant}`, mealID, participant, now, now, viewerId))
  }
  await database.batch(statements)
  return { apiVersion: API_VERSION, mealId: mealID, duplicate: false,
    invitations: await invitationsForMeal(database, mealID) }
}

async function mutateSharedMealParticipant(database: D1Database, viewerId: string, id: string, request: Request) {
  const body = await objectBody(request)
  const action = requiredString(body.action, 'Shared Meal action is invalid.')
  if (!['accept', 'decline', 'attach'].includes(action)) throw new SocialCollaborationV1Error('Shared Meal action is invalid.', 400)
  const row = await sharedMealByParticipantID(database, id)
  if (!row || row.participant_user_id !== viewerId) throw new SocialCollaborationV1Error('没有找到这条聚餐邀请。', 404)
  if (row.revoked_at || row.status === 'revoked') throw new SocialCollaborationV1Error('这条聚餐邀请已撤回。', 410)
  const now = new Date().toISOString()
  if (action === 'attach') {
    if (row.status !== 'accepted') throw new SocialCollaborationV1Error('请先接受聚餐邀请。', 409)
    const visitID = requiredString(body.visitId, 'Visit ID is required.')
    const visit = await database.prepare(`SELECT id, shared_meal_id FROM visits
      WHERE id = ? AND user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(visitID, viewerId)
      .first<{ id: string; shared_meal_id: string | null }>()
    if (!visit || visit.shared_meal_id !== row.meal_id) throw new SocialCollaborationV1Error('只能关联当前用户为此聚餐创建的 Visit。', 403)
    await database.prepare(`UPDATE shared_meal_participants SET visit_id = ?, updated_at = ?,
      server_version = server_version + 1 WHERE id = ? AND user_id = ?`)
      .bind(visitID, now, id, viewerId).run()
  } else {
    if (row.status !== 'pending') {
      if ((action === 'accept' && row.status === 'accepted') || (action === 'decline' && row.status === 'declined')) return sharedMealContract(database, row)
      throw new SocialCollaborationV1Error('这条邀请已经处理。', 409)
    }
    await requireAcceptedFriend(database, row.created_by_user_id, viewerId)
    const status = action === 'accept' ? 'accepted' : 'declined'
    await database.prepare(`UPDATE shared_meal_participants SET status = ?, updated_at = ?,
      deleted_at = ?, server_version = server_version + 1 WHERE id = ? AND user_id = ?`)
      .bind(status, now, status === 'declined' ? now : null, id, viewerId).run()
  }
  return sharedMealContract(database, (await sharedMealByParticipantID(database, id))!)
}

async function revokeSharedMeal(database: D1Database, viewerId: string, mealID: string) {
  const row = await database.prepare(`SELECT id, server_version, revoked_at FROM shared_meals
    WHERE id = ? AND created_by_user_id = ? LIMIT 1`).bind(mealID, viewerId)
    .first<{ id: string; server_version: number; revoked_at: string | null }>()
  if (!row) throw new SocialCollaborationV1Error('没有找到可撤回的聚餐邀请。', 404)
  if (!row.revoked_at) {
    const now = new Date().toISOString()
    await database.batch([
      database.prepare(`UPDATE shared_meals SET revoked_at = ?, deleted_at = ?, updated_at = ?,
        server_version = server_version + 1 WHERE id = ? AND created_by_user_id = ?`)
        .bind(now, now, now, mealID, viewerId),
      database.prepare(`UPDATE shared_meal_participants SET status = 'revoked', deleted_at = ?,
        updated_at = ?, server_version = server_version + 1 WHERE shared_meal_id = ? AND deleted_at IS NULL`)
        .bind(now, now, mealID),
    ])
  }
  const invitations = await invitationsForMeal(database, mealID, true)
  if (!invitations.length) throw new SocialCollaborationV1Error('聚餐已撤回。', 410)
  return invitations[0]
}

const sharedMealProjection = `SELECT sm.id AS meal_id, smp.id AS participant_id,
  sm.source_visit_id, sm.created_by_user_id, smp.user_id AS participant_user_id,
  sm.restaurant_id, sm.occurred_at, sm.visibility,
  CASE WHEN sm.revoked_at IS NOT NULL THEN 'revoked' ELSE smp.status END AS status,
  smp.visit_id, smp.created_at, smp.updated_at, sm.revoked_at,
  smp.server_version, r.name AS restaurant_name, r.address, r.city,
  r.latitude, r.longitude, r.tags_json, r.price_per_person,
  r.merchant_image_url, r.marker_emoji
FROM shared_meals sm JOIN shared_meal_participants smp ON smp.shared_meal_id = sm.id
JOIN restaurants r ON r.id = sm.restaurant_id`

async function invitationsForMeal(database: D1Database, mealID: string, includeDeleted = false) {
  const rows = await database.prepare(`${sharedMealProjection}
    WHERE sm.id = ? ${includeDeleted ? '' : 'AND sm.deleted_at IS NULL AND smp.deleted_at IS NULL'}
    ORDER BY smp.created_at ASC, smp.id ASC`).bind(mealID).all<SharedMealRow>()
  return sharedMealContracts(database, rows.results)
}

async function sharedMealByParticipantID(database: D1Database, id: string) {
  return database.prepare(`${sharedMealProjection} WHERE smp.id = ? LIMIT 1`).bind(id).first<SharedMealRow>()
}

async function sharedMealContracts(database: D1Database, rows: SharedMealRow[]) {
  if (!rows.length) return []
  const restaurantIDs = [...new Set(rows.map((row) => row.restaurant_id))]
  const identities = await database.prepare(`SELECT restaurant_id, provider, external_id, is_primary
    FROM restaurant_place_identities WHERE restaurant_id IN (${placeholders(restaurantIDs)})`)
    .bind(...restaurantIDs).all<IdentityRow>()
  const identityMap = new Map<string, PublicContentPlaceIdentityV1[]>()
  for (const identity of identities.results) identityMap.set(identity.restaurant_id, [
    ...(identityMap.get(identity.restaurant_id) ?? []),
    { provider: identity.provider, externalId: identity.external_id, isPrimary: identity.is_primary === 1 },
  ])
  return Promise.all(rows.map((row) => sharedMealContract(database, row, identityMap.get(row.restaurant_id) ?? [])))
}

async function sharedMealContract(database: D1Database, row: SharedMealRow, knownIdentities?: PublicContentPlaceIdentityV1[]): Promise<SharedMealInvitationV1> {
  const identities = knownIdentities ?? (await database.prepare(`SELECT restaurant_id, provider, external_id, is_primary
    FROM restaurant_place_identities WHERE restaurant_id = ?`).bind(row.restaurant_id).all<IdentityRow>()).results.map((value) => ({
      provider: value.provider, externalId: value.external_id, isPrimary: value.is_primary === 1,
    }))
  const inviter = await profileByID(database, row.created_by_user_id)
  const participant = await profileByID(database, row.participant_user_id)
  if (!inviter) throw new SocialCollaborationV1Error('邀请人资料已不可用。', 410)
  if (!participant) throw new SocialCollaborationV1Error('参与者资料已不可用。', 410)
  return {
    apiVersion: API_VERSION, mealId: row.meal_id, participantId: row.participant_id,
    sourceVisitId: row.source_visit_id, inviter: publicSummary(inviter),
    participant: publicSummary(participant),
    participantUserId: row.participant_user_id,
    restaurant: restaurantContract(row, identities), occurredAt: row.occurred_at,
    visibility: row.visibility, status: row.status, visitId: row.visit_id,
    createdAt: row.created_at, updatedAt: row.updated_at, revokedAt: row.revoked_at,
    serverVersion: Number(row.server_version),
  }
}

async function companionContract(database: D1Database, viewerId: string, row: CompanionLinkRow): Promise<CompanionLinkRequestV1> {
  const otherID = row.requester_user_id === viewerId ? row.target_user_id : row.requester_user_id
  const other = await profileByID(database, otherID)
  if (!other) throw new SocialCollaborationV1Error('关联用户资料已不可用。', 410)
  return {
    apiVersion: API_VERSION, id: row.id, companionId: row.companion_id,
    companionDisplayName: row.companion_display_name,
    requesterUserId: row.requester_user_id, targetUserId: row.target_user_id,
    status: row.status, otherUser: publicSummary(other), createdAt: row.created_at,
    updatedAt: row.updated_at, deletedAt: row.deleted_at, serverVersion: Number(row.server_version),
  }
}

function restaurantContract(row: SharedMealRow, identities: PublicContentPlaceIdentityV1[]): PublicContentRestaurantV1 {
  const normalized = identities.filter((value) => value.externalId.trim())
  const globalKey = normalized.length ? `place:${stableHash(normalized.map((value) => `${value.provider}:${value.externalId}`).sort().join('|'))}`
    : `place:${stableHash(`${row.restaurant_name}|${row.city}|${row.address}|${row.latitude}|${row.longitude}`.toLocaleLowerCase())}`
  return {
    globalKey, placeIdentities: normalized.length ? normalized : [{ provider: 'manual', externalId: `tastemap:${row.restaurant_id}`, isPrimary: true }],
    name: row.restaurant_name, address: row.address, city: row.city,
    latitude: Number(row.latitude), longitude: Number(row.longitude), tags: parseTags(row.tags_json).slice(0, 12),
    pricePerPerson: row.price_per_person === null ? null : Number(row.price_per_person),
    merchantImageUrl: safeHTTPSURL(row.merchant_image_url), markerEmoji: row.marker_emoji || '🍽️', photo: null,
  }
}

async function requireAcceptedFriend(database: D1Database, first: string, second: string) {
  const row = await database.prepare(`SELECT id FROM friendships WHERE status = 'accepted'
    AND deleted_at IS NULL AND ((requester_id = ? AND addressee_id = ?)
      OR (requester_id = ? AND addressee_id = ?)) LIMIT 1`).bind(first, second, second, first).first()
  if (!row) throw new SocialCollaborationV1Error('只有已接受好友可以使用这个协作功能。', 403)
}

function profileByID(database: D1Database, userID: string) {
  return database.prepare(`SELECT user_id, display_name, bio, city, avatar_photo_id,
    avatar_preset_id, visibility FROM user_profiles WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`)
    .bind(userID).first<ProfileRow>()
}

function publicSummary(row: ProfileRow): SocialUserSummaryV1 {
  return { userId: row.user_id, displayName: row.display_name, bio: row.bio.trim() || null,
    city: row.city.trim() || null, avatarPhotoId: row.avatar_photo_id,
    avatarPresetId: row.avatar_preset_id ?? 'polar-bear' }
}

function companionLinkByID(database: D1Database, id: string) {
  return database.prepare(`SELECT * FROM companion_link_requests WHERE id = ? LIMIT 1`).bind(id).first<CompanionLinkRow>()
}

async function objectBody(request: Request) {
  const value = await request.json().catch(() => null)
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new SocialCollaborationV1Error('Request body is invalid.', 400)
  return value as Record<string, unknown>
}

function requiredString(value: unknown, message: string) {
  if (typeof value !== 'string' || !value.trim() || value.length > 200) throw new SocialCollaborationV1Error(message, 400)
  return value.trim()
}

function uniqueStrings(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.filter((item): item is string => typeof item === 'string').map((item) => item.trim()).filter(Boolean))]
}

function decodedID(value: string) { return requiredString(decodeURIComponent(value), 'Identifier is invalid.') }
function pageLimit(url: URL) {
  const value = Number(url.searchParams.get('limit') ?? DEFAULT_LIMIT)
  return Number.isInteger(value) ? Math.min(MAX_LIMIT, Math.max(1, value)) : DEFAULT_LIMIT
}
function encodeCursor(primary: string, secondary: string) {
  return btoa(JSON.stringify([primary, secondary])).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}
function decodeCursor(raw: string | null) {
  if (!raw) return { primary: '', secondary: '' }
  return decodeCursorValue(raw)
}
function decodeDescendingCursor(raw: string | null) {
  if (!raw) return { primary: '9999-12-31T23:59:59.999Z', secondary: '' }
  return decodeCursorValue(raw)
}
function decodeCursorValue(raw: string) {
  try {
    const normalized = raw.replaceAll('-', '+').replaceAll('_', '/')
    const bytes = Uint8Array.from(atob(normalized), (value) => value.charCodeAt(0))
    const decoded = JSON.parse(new TextDecoder().decode(bytes))
    if (Array.isArray(decoded) && decoded.length === 2 && decoded.every((item) => typeof item === 'string')) {
      return { primary: decoded[0], secondary: decoded[1] }
    }
  } catch { /* invalid cursor */ }
  throw new SocialCollaborationV1Error('Pagination cursor is invalid.', 400)
}
function placeholders(values: unknown[]) { return values.map(() => '?').join(',') }
function parseTags(value: string) {
  try { const decoded = JSON.parse(value); return Array.isArray(decoded) ? decoded.filter((item): item is string => typeof item === 'string' && Boolean(item.trim())).map((item) => item.trim()) : [] } catch { return [] }
}
function safeHTTPSURL(value: string | null) {
  if (!value) return null
  try { const url = new URL(value); return url.protocol === 'https:' ? url.toString() : null } catch { return null }
}
function stableHash(source: string) {
  let hash = 2166136261
  for (let index = 0; index < source.length; index += 1) { hash ^= source.charCodeAt(index); hash = Math.imul(hash, 16777619) }
  return (hash >>> 0).toString(16).padStart(8, '0')
}

async function deterministicSharedMealID(viewerId: string, mutationId: string) {
  const bytes = new TextEncoder().encode(`${viewerId}\u0000${mutationId}`)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  const hex = [...digest].map((value) => value.toString(16).padStart(2, '0')).join('')
  return `shared-meal:${hex.slice(0, 40)}`
}
