import type {
  FollowV1,
  FriendshipV1,
  SocialRelationshipStateV1,
  SocialUserResultV1,
  SocialUserSummaryV1,
} from '../src/contracts/socialContract'
import type { ProfileAvatarPresetContract } from '../src/contracts/profileContract'
import { readPublicProfile } from './profileV1'

const API_VERSION = 1
const DEFAULT_LIMIT = 20
const MAX_LIMIT = 50
const SEARCH_REQUESTS_PER_MINUTE = 60

interface ProfileRow {
  user_id: string
  display_name: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract
  visibility: 'private' | 'friends' | 'public'
  deleted_at: string | null
}

interface FriendshipRow {
  id: string
  requester_id: string
  addressee_id: string
  status: 'pending' | 'accepted' | 'rejected' | 'removed'
  created_at: string
  updated_at: string
  deleted_at: string | null
  server_version: number
}

interface FollowRow {
  id: string
  follower_id: string
  followed_user_id: string
  created_at: string
  updated_at: string
  deleted_at: string | null
  server_version: number
}

interface SocialUserRow extends ProfileRow {
  friendship_id: string | null
  friendship_requester_id: string | null
  friendship_addressee_id: string | null
  friendship_status: FriendshipRow['status'] | null
  is_following: number
}

export class SocialV1RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

export async function handleSocialV1(
  request: Request,
  database: D1Database,
  viewerId: string,
) {
  const url = new URL(request.url)
  if (url.pathname === '/api/v1/social/users/search' && request.method === 'GET') {
    return searchUsers(database, viewerId, url)
  }
  if (url.pathname === '/api/v1/social/friendships' && request.method === 'GET') {
    return readFriendships(database, viewerId, url)
  }
  if (url.pathname === '/api/v1/social/friendships' && request.method === 'POST') {
    const body = await objectBody(request)
    return requestFriend(database, viewerId, requiredString(body.targetUserId, '好友用户无效。'))
  }
  const friendshipMatch = url.pathname.match(/^\/api\/v1\/social\/friendships\/([^/]+)$/)
  if (friendshipMatch && request.method === 'POST') {
    const body = await objectBody(request)
    return mutateFriendship(
      database, viewerId, decodeURIComponent(friendshipMatch[1]),
      requiredString(body.action, '好友操作无效。'),
    )
  }
  if (url.pathname === '/api/v1/social/follows' && request.method === 'GET') {
    return readFollows(database, viewerId, url)
  }
  const followMatch = url.pathname.match(/^\/api\/v1\/social\/follows\/([^/]+)$/)
  if (followMatch && (request.method === 'PUT' || request.method === 'DELETE')) {
    return mutateFollow(database, viewerId, decodeURIComponent(followMatch[1]), request.method === 'PUT')
  }
  const contextMatch = url.pathname.match(/^\/api\/v1\/social\/users\/([^/]+)\/context$/)
  if (contextMatch && request.method === 'GET') {
    const target = decodeURIComponent(contextMatch[1])
    return {
      apiVersion: API_VERSION,
      profile: await readPublicProfile(database, viewerId, target),
      relationship: await relationshipContext(database, viewerId, target),
    }
  }
  throw new SocialV1RequestError('Social API route was not found.', 404)
}

async function searchUsers(database: D1Database, viewerId: string, url: URL) {
  const query = (url.searchParams.get('q') ?? '').trim()
  if ([...query].length < 2) {
    throw new SocialV1RequestError('请输入至少 2 个字符后搜索。', 400)
  }
  await consumeSearchQuota(database, viewerId)
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'))
  const normalized = query.toLocaleLowerCase()
  const like = `%${escapeLike(normalized)}%`
  const rows = await database.prepare(`SELECT p.*,
      f.id AS friendship_id, f.requester_id AS friendship_requester_id,
      f.addressee_id AS friendship_addressee_id, f.status AS friendship_status,
      CASE WHEN follow.id IS NULL THEN 0 ELSE 1 END AS is_following
    FROM user_profiles p
    LEFT JOIN friendships f ON f.pair_user_a = CASE WHEN p.user_id < ? THEN p.user_id ELSE ? END
      AND f.pair_user_b = CASE WHEN p.user_id < ? THEN ? ELSE p.user_id END
      AND f.deleted_at IS NULL AND f.status IN ('pending', 'accepted')
    LEFT JOIN follows follow ON follow.follower_id = ? AND follow.followed_user_id = p.user_id
      AND follow.deleted_at IS NULL
    WHERE p.deleted_at IS NULL AND p.user_id <> ?
      AND p.visibility = 'public'
      AND (LOWER(p.display_name) LIKE ? ESCAPE '\\' OR LOWER(p.city) LIKE ? ESCAPE '\\')
      AND (LOWER(p.display_name) > ? OR (LOWER(p.display_name) = ? AND p.user_id > ?))
    ORDER BY LOWER(p.display_name), p.user_id
    LIMIT ?`).bind(
      viewerId, viewerId, viewerId, viewerId, viewerId, viewerId,
      like, like, cursor.primary, cursor.primary, cursor.secondary, limit + 1,
    ).all<SocialUserRow>()
  return userPage(rows.results, viewerId, limit)
}

async function readFriendships(database: D1Database, viewerId: string, url: URL) {
  const scope = url.searchParams.get('scope') ?? 'friends'
  if (!['friends', 'incoming', 'outgoing'].includes(scope)) {
    throw new SocialV1RequestError('好友列表类型无效。', 400)
  }
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'), true)
  const stateClause = scope === 'friends'
    ? "f.status = 'accepted'"
    : scope === 'incoming'
      ? "f.status = 'pending' AND f.addressee_id = ?"
      : "f.status = 'pending' AND f.requester_id = ?"
  const rows = await database.prepare(`SELECT p.*,
      f.id AS friendship_id, f.requester_id AS friendship_requester_id,
      f.addressee_id AS friendship_addressee_id, f.status AS friendship_status,
      CASE WHEN follow.id IS NULL THEN 0 ELSE 1 END AS is_following,
      f.updated_at AS relationship_updated_at
    FROM friendships f
    JOIN user_profiles p ON p.user_id = CASE WHEN f.requester_id = ? THEN f.addressee_id ELSE f.requester_id END
    LEFT JOIN follows follow ON follow.follower_id = ? AND follow.followed_user_id = p.user_id
      AND follow.deleted_at IS NULL
    WHERE f.deleted_at IS NULL AND (f.requester_id = ? OR f.addressee_id = ?)
      AND ${stateClause}
      AND (f.updated_at < ? OR (f.updated_at = ? AND f.id > ?))
      AND p.deleted_at IS NULL
    ORDER BY f.updated_at DESC, f.id ASC LIMIT ?`).bind(
      viewerId, viewerId, viewerId, viewerId,
      ...(scope === 'friends' ? [] : [viewerId]),
      cursor.primary, cursor.primary, cursor.secondary, limit + 1,
    ).all<SocialUserRow & { relationship_updated_at: string }>()
  const visible = rows.results.slice(0, limit)
  return {
    apiVersion: API_VERSION,
    items: visible.map((row) => resultFromRow(row, viewerId)),
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.relationship_updated_at, visible.at(-1)!.friendship_id ?? '')
      : null,
  }
}

async function requestFriend(database: D1Database, viewerId: string, targetUserId: string) {
  await requireTarget(database, viewerId, targetUserId)
  const [pairA, pairB] = canonicalPair(viewerId, targetUserId)
  const existing = await database.prepare(`SELECT * FROM friendships
    WHERE pair_user_a = ? AND pair_user_b = ? ORDER BY server_version DESC LIMIT 1`)
    .bind(pairA, pairB).first<FriendshipRow>()
  const now = new Date().toISOString()
  if (existing?.deleted_at === null && existing.status === 'accepted') {
    return { friendship: friendshipContract(existing), duplicate: true }
  }
  if (existing?.deleted_at === null && existing.status === 'pending') {
    if (existing.requester_id === viewerId) {
      return { friendship: friendshipContract(existing), duplicate: true }
    }
    await database.prepare(`UPDATE friendships SET status = 'accepted', deleted_at = NULL,
      updated_at = ?, server_version = server_version + 1 WHERE id = ? AND status = 'pending'`)
      .bind(now, existing.id).run()
    return { friendship: friendshipContract((await friendshipById(database, existing.id))!), duplicate: false, crossRequestAccepted: true }
  }
  const id = existing?.id ?? `friendship:${pairA}:${pairB}`
  if (existing) {
    await database.prepare(`UPDATE friendships SET requester_id = ?, addressee_id = ?,
      pair_user_a = ?, pair_user_b = ?, status = 'pending', deleted_at = NULL,
      updated_at = ?, server_version = server_version + 1 WHERE id = ?`)
      .bind(viewerId, targetUserId, pairA, pairB, now, id).run()
  } else {
    const inserted = await database.prepare(`INSERT OR IGNORE INTO friendships (
      id, requester_id, addressee_id, status, created_at, updated_at,
      pair_user_a, pair_user_b, deleted_at, server_version
    ) VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, NULL, 1)`)
      .bind(id, viewerId, targetUserId, now, now, pairA, pairB).run()
    if (Number(inserted.meta.changes ?? 0) === 0) {
      const raced = await database.prepare(`SELECT * FROM friendships
        WHERE pair_user_a = ? AND pair_user_b = ? AND deleted_at IS NULL
          AND status IN ('pending', 'accepted') LIMIT 1`).bind(pairA, pairB).first<FriendshipRow>()
      if (!raced) throw new SocialV1RequestError('好友关系正在变化，请重试。', 409)
      if (raced.status === 'pending' && raced.requester_id !== viewerId) {
        await database.prepare(`UPDATE friendships SET status = 'accepted', updated_at = ?,
          server_version = server_version + 1 WHERE id = ? AND status = 'pending'`)
          .bind(now, raced.id).run()
        return { friendship: friendshipContract((await friendshipById(database, raced.id))!), duplicate: false, crossRequestAccepted: true }
      }
      return { friendship: friendshipContract(raced), duplicate: true }
    }
  }
  return { friendship: friendshipContract((await friendshipById(database, id))!), duplicate: false }
}

async function mutateFriendship(
  database: D1Database,
  viewerId: string,
  friendshipId: string,
  action: string,
) {
  const existing = await friendshipById(database, friendshipId)
  if (!existing || (existing.requester_id !== viewerId && existing.addressee_id !== viewerId)) {
    throw new SocialV1RequestError('没有找到这条好友关系。', 404)
  }
  if (!['accept', 'reject', 'cancel', 'remove'].includes(action)) {
    throw new SocialV1RequestError('好友操作无效。', 400)
  }
  if (action === 'accept' || action === 'reject') {
    if (existing.addressee_id !== viewerId || existing.status !== 'pending' || existing.deleted_at) {
      if (action === 'accept' && existing.status === 'accepted' && !existing.deleted_at) {
        return { friendship: friendshipContract(existing), duplicate: true }
      }
      throw new SocialV1RequestError('只有收件人可以处理待接受的好友请求。', 409)
    }
  }
  if (action === 'cancel' && (
    existing.requester_id !== viewerId || existing.status !== 'pending' || existing.deleted_at
  )) throw new SocialV1RequestError('只有发件人可以取消待处理请求。', 409)
  if (action === 'remove' && (existing.status !== 'accepted' || existing.deleted_at)) {
    if (existing.status === 'removed' || existing.deleted_at) {
      return { friendship: friendshipContract(existing), duplicate: true }
    }
    throw new SocialV1RequestError('当前不是可解除的好友关系。', 409)
  }
  const nextState = action === 'accept' ? 'accepted' : action === 'reject' ? 'rejected' : 'removed'
  const now = new Date().toISOString()
  const deletedAt = nextState === 'accepted' ? null : now
  const result = await database.prepare(`UPDATE friendships SET status = ?, deleted_at = ?,
    updated_at = ?, server_version = server_version + 1
    WHERE id = ? AND server_version = ?`)
    .bind(nextState, deletedAt, now, existing.id, existing.server_version).run()
  if (Number(result.meta.changes ?? 0) !== 1) {
    throw new SocialV1RequestError('关系已在另一台设备发生变化，请刷新后重试。', 409)
  }
  return { friendship: friendshipContract((await friendshipById(database, existing.id))!), duplicate: false }
}

async function readFollows(database: D1Database, viewerId: string, url: URL) {
  const scope = url.searchParams.get('scope') ?? 'following'
  if (scope !== 'following' && scope !== 'followers') {
    throw new SocialV1RequestError('关注列表类型无效。', 400)
  }
  const limit = pageLimit(url)
  const cursor = decodeCursor(url.searchParams.get('cursor'), true)
  const actorColumn = scope === 'following' ? 'f.follower_id' : 'f.followed_user_id'
  const otherColumn = scope === 'following' ? 'f.followed_user_id' : 'f.follower_id'
  const rows = await database.prepare(`SELECT p.*,
      NULL AS friendship_id, NULL AS friendship_requester_id,
      NULL AS friendship_addressee_id, NULL AS friendship_status,
      CASE WHEN mine.id IS NULL THEN 0 ELSE 1 END AS is_following,
      f.updated_at AS relationship_updated_at, f.id AS follow_id
    FROM follows f JOIN user_profiles p ON p.user_id = ${otherColumn}
    LEFT JOIN follows mine ON mine.follower_id = ? AND mine.followed_user_id = p.user_id
      AND mine.deleted_at IS NULL
    WHERE ${actorColumn} = ? AND f.deleted_at IS NULL AND p.deleted_at IS NULL
      AND (f.updated_at < ? OR (f.updated_at = ? AND f.id > ?))
    ORDER BY f.updated_at DESC, f.id ASC LIMIT ?`).bind(
      viewerId, viewerId, cursor.primary, cursor.primary, cursor.secondary, limit + 1,
    ).all<SocialUserRow & { relationship_updated_at: string; follow_id: string }>()
  const visible = rows.results.slice(0, limit)
  return {
    apiVersion: API_VERSION,
    items: await Promise.all(visible.map(async (row) => {
      const context = await relationshipContext(database, viewerId, row.user_id)
      return { ...resultFromRow(row, viewerId), ...context }
    })),
    nextCursor: rows.results.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.relationship_updated_at, visible.at(-1)!.follow_id)
      : null,
  }
}

async function mutateFollow(database: D1Database, viewerId: string, targetUserId: string, follow: boolean) {
  await requireTarget(database, viewerId, targetUserId)
  const now = new Date().toISOString()
  const existing = await database.prepare(`SELECT * FROM follows
    WHERE follower_id = ? AND followed_user_id = ? LIMIT 1`)
    .bind(viewerId, targetUserId).first<FollowRow>()
  if (follow) {
    if (existing && !existing.deleted_at) return { follow: followContract(existing), duplicate: true }
    const id = existing?.id ?? `follow:${viewerId}:${targetUserId}`
    if (existing) {
      await database.prepare(`UPDATE follows SET deleted_at = NULL, updated_at = ?,
        server_version = server_version + 1 WHERE id = ?`).bind(now, id).run()
    } else {
      const inserted = await database.prepare(`INSERT OR IGNORE INTO follows (
        id, follower_id, followed_user_id, created_at, updated_at, deleted_at, server_version
      ) VALUES (?, ?, ?, ?, ?, NULL, 1)`).bind(id, viewerId, targetUserId, now, now).run()
      if (Number(inserted.meta.changes ?? 0) === 0) {
        const raced = await database.prepare(`SELECT * FROM follows
          WHERE follower_id = ? AND followed_user_id = ? LIMIT 1`)
          .bind(viewerId, targetUserId).first<FollowRow>()
        if (!raced) throw new SocialV1RequestError('关注状态正在变化，请重试。', 409)
        return { follow: followContract(raced), duplicate: !raced.deleted_at }
      }
    }
    return { follow: followContract((await followById(database, id))!), duplicate: false }
  }
  if (!existing || existing.deleted_at) {
    return { follow: existing ? followContract(existing) : null, duplicate: true }
  }
  const result = await database.prepare(`UPDATE follows SET deleted_at = ?, updated_at = ?,
    server_version = server_version + 1 WHERE id = ? AND server_version = ?`)
    .bind(now, now, existing.id, existing.server_version).run()
  if (Number(result.meta.changes ?? 0) !== 1) {
    throw new SocialV1RequestError('关注状态已在另一台设备发生变化，请刷新后重试。', 409)
  }
  return { follow: followContract((await followById(database, existing.id))!), duplicate: false }
}

async function relationshipContext(database: D1Database, viewerId: string, targetUserId: string) {
  if (viewerId === targetUserId) {
    return { friendshipId: null, friendshipState: 'none' as const, isFollowing: false }
  }
  const [pairA, pairB] = canonicalPair(viewerId, targetUserId)
  const [friendship, follow] = await Promise.all([
    database.prepare(`SELECT * FROM friendships WHERE pair_user_a = ? AND pair_user_b = ?
      AND deleted_at IS NULL AND status IN ('pending', 'accepted') LIMIT 1`)
      .bind(pairA, pairB).first<FriendshipRow>(),
    database.prepare(`SELECT id FROM follows WHERE follower_id = ? AND followed_user_id = ?
      AND deleted_at IS NULL LIMIT 1`).bind(viewerId, targetUserId).first(),
  ])
  return {
    friendshipId: friendship?.id ?? null,
    friendshipState: relationshipState(friendship ?? null, viewerId),
    isFollowing: Boolean(follow),
  }
}

async function requireTarget(database: D1Database, viewerId: string, targetUserId: string) {
  if (!targetUserId || targetUserId === viewerId) {
    throw new SocialV1RequestError('不能与自己的账号建立关系。', 400)
  }
  const target = await database.prepare(`SELECT user_id FROM user_profiles
    WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`).bind(targetUserId).first()
  if (!target) throw new SocialV1RequestError('没有找到这个用户。', 404)
}

async function consumeSearchQuota(database: D1Database, viewerId: string) {
  const window = new Date().toISOString().slice(0, 16)
  await database.prepare(`INSERT INTO social_search_rate_limits (
    user_id, window_started_at, request_count
  ) VALUES (?, ?, 1) ON CONFLICT(user_id, window_started_at)
    DO UPDATE SET request_count = request_count + 1`).bind(viewerId, window).run()
  const value = await database.prepare(`SELECT request_count FROM social_search_rate_limits
    WHERE user_id = ? AND window_started_at = ?`).bind(viewerId, window)
    .first<{ request_count: number }>()
  if (Number(value?.request_count ?? 0) > SEARCH_REQUESTS_PER_MINUTE) {
    throw new SocialV1RequestError('搜索过于频繁，请稍后再试。', 429)
  }
}

function userPage(rows: SocialUserRow[], viewerId: string, limit: number) {
  const visible = rows.slice(0, limit)
  return {
    apiVersion: API_VERSION,
    items: visible.map((row) => resultFromRow(row, viewerId)),
    nextCursor: rows.length > limit && visible.length
      ? encodeCursor(visible.at(-1)!.display_name.toLocaleLowerCase(), visible.at(-1)!.user_id)
      : null,
  }
}

function resultFromRow(row: SocialUserRow, viewerId: string): SocialUserResultV1 {
  const friendship = row.friendship_id ? {
    id: row.friendship_id,
    requester_id: row.friendship_requester_id!,
    addressee_id: row.friendship_addressee_id!,
    status: row.friendship_status!,
  } as FriendshipRow : null
  return {
    profile: publicSummary(row),
    friendshipId: row.friendship_id,
    friendshipState: relationshipState(friendship, viewerId),
    isFollowing: Boolean(row.is_following),
  }
}

function publicSummary(row: ProfileRow): SocialUserSummaryV1 {
  return {
    userId: row.user_id,
    displayName: row.display_name,
    bio: row.bio.trim() || null,
    city: row.city.trim() || null,
    avatarPhotoId: row.avatar_photo_id,
    avatarPresetId: row.avatar_preset_id,
  }
}

function relationshipState(row: FriendshipRow | null, viewerId: string): SocialRelationshipStateV1 {
  if (!row || row.deleted_at || row.status === 'rejected' || row.status === 'removed') return 'none'
  if (row.status === 'accepted') return 'friends'
  return row.requester_id === viewerId ? 'outgoing_request' : 'incoming_request'
}

function friendshipContract(row: FriendshipRow): FriendshipV1 {
  return {
    apiVersion: API_VERSION,
    id: row.id,
    requesterUserId: row.requester_id,
    addresseeUserId: row.addressee_id,
    state: row.status === 'accepted' ? 'friends'
      : row.status === 'pending' ? 'outgoing_request' : row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    serverVersion: row.server_version,
  }
}

function followContract(row: FollowRow): FollowV1 {
  return {
    apiVersion: API_VERSION,
    id: row.id,
    followerUserId: row.follower_id,
    followedUserId: row.followed_user_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    serverVersion: row.server_version,
  }
}

function friendshipById(database: D1Database, id: string) {
  return database.prepare('SELECT * FROM friendships WHERE id = ? LIMIT 1').bind(id).first<FriendshipRow>()
}

function followById(database: D1Database, id: string) {
  return database.prepare('SELECT * FROM follows WHERE id = ? LIMIT 1').bind(id).first<FollowRow>()
}

function canonicalPair(first: string, second: string): [string, string] {
  return first < second ? [first, second] : [second, first]
}

function pageLimit(url: URL) {
  const requested = Number(url.searchParams.get('limit') ?? DEFAULT_LIMIT)
  return Number.isInteger(requested) ? Math.min(MAX_LIMIT, Math.max(1, requested)) : DEFAULT_LIMIT
}

function encodeCursor(primary: string, secondary: string) {
  const bytes = new TextEncoder().encode(JSON.stringify([primary, secondary]))
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

function decodeCursor(raw: string | null, descending = false) {
  if (!raw) return { primary: descending ? '9999-12-31T23:59:59.999Z' : '', secondary: '' }
  try {
    const normalized = raw.replaceAll('-', '+').replaceAll('_', '/')
    const bytes = Uint8Array.from(atob(normalized), (value) => value.charCodeAt(0))
    const value = JSON.parse(new TextDecoder().decode(bytes))
    if (Array.isArray(value) && value.length === 2 && value.every((item) => typeof item === 'string')) {
      return { primary: value[0], secondary: value[1] }
    }
  } catch { /* invalid cursor */ }
  throw new SocialV1RequestError('分页游标无效。', 400)
}

function escapeLike(value: string) {
  return value.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')
}

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  const value = await request.json().catch(() => null)
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new SocialV1RequestError('请求内容无效。', 400)
  }
  return value as Record<string, unknown>
}

function requiredString(value: unknown, message: string) {
  if (typeof value !== 'string' || !value.trim()) throw new SocialV1RequestError(message, 400)
  return value.trim()
}
