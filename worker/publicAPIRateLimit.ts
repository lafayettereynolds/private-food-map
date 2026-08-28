const MINUTE = 60_000
const RETENTION = 24 * 60 * MINUTE

export type PublicAPIRateBucket =
  | 'public-profile-read'
  | 'social-read'
  | 'social-mutation'
  | 'community-read'
  | 'restaurant-list-read'
  | 'legacy-social-search'
  | 'legacy-community-read'
  | 'legacy-profile-read'
  | 'legacy-social-mutation'

export class PublicAPIRateLimitError extends Error {
  readonly status = 429
  constructor(message = '请求过于频繁，请稍后再试。') { super(message) }
}

/**
 * Authenticated actor quotas are derived exclusively from the verified Worker
 * identity. Client payload/query user IDs never select a quota or authority.
 */
export async function consumePublicAPIQuota(
  database: D1Database,
  userId: string,
  bucket: PublicAPIRateBucket,
  maximumPerMinute: number,
  now = Date.now(),
) {
  const actorKey = `user:${userId}`
  const window = new Date(now).toISOString().slice(0, 16)
  await database.prepare(`DELETE FROM public_api_rate_limits
    WHERE actor_key = ? AND window_started_at < ?`).bind(
    actorKey,
    new Date(now - RETENTION).toISOString().slice(0, 16),
  ).run()
  await database.prepare(`INSERT INTO public_api_rate_limits (
      actor_key, bucket, window_started_at, request_count
    ) VALUES (?, ?, ?, 1)
    ON CONFLICT(actor_key, bucket, window_started_at)
    DO UPDATE SET request_count = request_count + 1`)
    .bind(actorKey, bucket, window).run()
  const value = await database.prepare(`SELECT request_count FROM public_api_rate_limits
    WHERE actor_key = ? AND bucket = ? AND window_started_at = ?`)
    .bind(actorKey, bucket, window).first<{ request_count: number }>()
  if (Number(value?.request_count ?? 0) > maximumPerMinute) {
    throw new PublicAPIRateLimitError()
  }
}
