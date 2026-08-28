import type {
  PublicUserProfileV1,
  ProfileAvatarPresetContract,
  ProfileVisibilityContract,
} from '../src/contracts/profileContract'

const PROFILE_CHANGE_LOG_TABLE = 'sync_change_log_v5'

interface ProfileRow {
  user_id: string
  display_name: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract
  visibility: ProfileVisibilityContract
  created_at: string
  updated_at: string
  deleted_at: string | null
  server_version: number
  last_mutation_id: string | null
}

interface UserSeedRow {
  id: string
  nickname: string
  bio: string
  city: string
  avatar_photo_id: string | null
  avatar_preset_id: ProfileAvatarPresetContract | null
  map_sharing_enabled: number
  map_visibility: ProfileVisibilityContract
  created_at: string
  updated_at: string
  deleted_at: string | null
}

export class ProfileV1RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message) }
}

/** Idempotently materializes a one-to-one Profile for an authenticated User. */
export async function ensureUserProfile(database: D1Database, userId: string) {
  const existing = await database.prepare('SELECT * FROM user_profiles WHERE user_id = ? LIMIT 1')
    .bind(userId).first<ProfileRow>()
  if (existing) return existing
  const user = await database.prepare('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL LIMIT 1')
    .bind(userId).first<UserSeedRow>()
  if (!user) throw new ProfileV1RequestError('Authenticated Taste Map user was not found.', 401)
  const mutationId = `bootstrap:profile:${userId}`
  const visibility = user.map_sharing_enabled === 1 && user.map_visibility !== 'private'
    ? user.map_visibility
    : 'private'
  await database.batch([
    database.prepare(`INSERT OR IGNORE INTO user_profiles (
      user_id, display_name, bio, city, avatar_photo_id, avatar_preset_id,
      visibility, created_at, updated_at, deleted_at, server_version,
      last_mutation_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, ?)`)
      .bind(
        userId, user.nickname.trim() || 'Taste Map 用户', user.bio ?? '', user.city ?? '',
        user.avatar_photo_id, user.avatar_preset_id ?? 'polar-bear', visibility,
        user.created_at, user.updated_at, mutationId,
      ),
    database.prepare(`INSERT OR IGNORE INTO ${PROFILE_CHANGE_LOG_TABLE} (
      user_id, entity_type, entity_id, operation, server_version, mutation_id,
      changed_at
    ) SELECT user_id, 'profile', user_id,
      CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
      server_version, last_mutation_id, updated_at
      FROM user_profiles WHERE user_id = ? AND last_mutation_id = ?`)
      .bind(userId, mutationId),
  ])
  const created = await database.prepare('SELECT * FROM user_profiles WHERE user_id = ? LIMIT 1')
    .bind(userId).first<ProfileRow>()
  if (!created) throw new ProfileV1RequestError('Unable to initialize User Profile.', 500)
  return created
}

export async function readPublicProfile(
  database: D1Database,
  viewerId: string,
  targetUserId: string,
): Promise<PublicUserProfileV1> {
  const profile = await database.prepare(`SELECT * FROM user_profiles
    WHERE user_id = ? AND deleted_at IS NULL LIMIT 1`)
    .bind(targetUserId).first<ProfileRow>()
  if (!profile) throw new ProfileV1RequestError('Public Profile was not found.', 404)

  const friend = targetUserId === viewerId || Boolean(await database.prepare(`SELECT id FROM friendships
    WHERE status = 'accepted' AND (
      (requester_id = ? AND addressee_id = ?) OR
      (requester_id = ? AND addressee_id = ?)
    ) LIMIT 1`).bind(viewerId, targetUserId, targetUserId, viewerId).first())
  const permitted = targetUserId === viewerId || profile.visibility === 'public' ||
    (profile.visibility === 'friends' && friend)
  if (!permitted) throw new ProfileV1RequestError('Public Profile was not found.', 404)

  const [visitResult, restaurantResult, avatar] = await database.batch([
    database.prepare(`SELECT COUNT(*) AS count FROM visits
      WHERE user_id = ? AND visibility = 'public' AND deleted_at IS NULL`).bind(targetUserId),
    database.prepare(`SELECT COUNT(DISTINCT restaurant_id) AS count FROM visits
      WHERE user_id = ? AND visibility = 'public' AND deleted_at IS NULL`).bind(targetUserId),
    database.prepare(`SELECT id FROM photos
      WHERE id = ? AND user_id = ? AND kind = 'avatar' AND deleted_at IS NULL LIMIT 1`)
      .bind(profile.avatar_photo_id, targetUserId),
  ])
  const publicVisitCount = countResult(visitResult)
  const publicRestaurantCount = countResult(restaurantResult)
  const avatarPhotoId = profile.avatar_photo_id && avatar.results.length > 0
    ? profile.avatar_photo_id
    : null
  return {
    apiVersion: 1,
    userId: profile.user_id,
    displayName: profile.display_name,
    bio: profile.bio.trim() || null,
    city: profile.city.trim() || null,
    avatarPhotoId,
    avatarPresetId: profile.avatar_preset_id,
    joinedAt: profile.created_at,
    statistics: { publicRestaurantCount, publicVisitCount },
  }
}

function countResult(result: D1Result<unknown>) {
  const row = result.results[0] as { count?: number | string } | undefined
  return Number(row?.count ?? 0)
}
