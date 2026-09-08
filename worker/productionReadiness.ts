interface ReadinessEnv {
  DB: D1Database
  PHOTO_STORAGE?: R2Bucket
  APP_ENVIRONMENT?: string
  MEMBERSHIP_ADMIN_USER_IDS?: string
  APP_STORE_ISSUER_ID?: string
  APP_STORE_KEY_ID?: string
  APP_STORE_PRIVATE_KEY?: string
}

export async function productionReadiness(env: ReadinessEnv): Promise<Response> {
  let database = false, photos = false
  try {
    const row = await env.DB.prepare(`SELECT COUNT(*) AS count FROM d1_migrations
      WHERE name IN ('0034_premium_gifts.sql','0035_referral_rewards.sql',
      '0036_private_directory_profiles.sql','0036_recommendation_preferences.sql','0037_signup_trial.sql')`).first<{count:number}>()
    database = row?.count === 5
  } catch { /* unavailable; no infrastructure error or data exposed */ }
  try {
    if (env.PHOTO_STORAGE) { await env.PHOTO_STORAGE.head('tastemap-readiness-probe'); photos = true }
  } catch { /* private bucket read authorization unavailable */ }
  const checks = {
    database, photos,
    storeKitConfigured: Boolean(env.APP_STORE_ISSUER_ID?.trim() && env.APP_STORE_KEY_ID?.trim() && env.APP_STORE_PRIVATE_KEY?.trim()),
    administratorConfigured: Boolean(env.MEMBERSHIP_ADMIN_USER_IDS?.trim()),
  }
  const ready = Object.values(checks).every(Boolean)
  return Response.json({status: ready ? 'ready' : 'not_ready', checks}, {
    status: ready ? 200 : 503, headers: {'Cache-Control':'no-store'},
  })
}
