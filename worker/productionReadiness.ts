import { checkStoreKitInfrastructure, type AppStoreCommerceEnvironment } from './appStoreCommerceV1'

interface ReadinessEnv extends AppStoreCommerceEnvironment {
  DB: D1Database
  PHOTO_STORAGE?: R2Bucket
  APPLE_CLIENT_IDS?: string
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
      '0036_private_directory_profiles.sql','0036_recommendation_preferences.sql','0037_signup_trial.sql',
      '0038_sandbox_offer_assignments.sql','0038_storekit_environment_isolation.sql')`).first<{count:number}>()
    database = row?.count === 7
  } catch { /* unavailable; no infrastructure error or data exposed */ }
  try {
    if (env.PHOTO_STORAGE) { await env.PHOTO_STORAGE.head('tastemap-readiness-probe'); photos = true }
  } catch { /* private bucket read authorization unavailable */ }
  const checks = {
    worker: true, database, photos,
    authConfigured: env.APP_ENVIRONMENT === 'production' && Boolean(env.APPLE_CLIENT_IDS?.trim()),
    storeKitConfigured: await checkStoreKitInfrastructure(env),
  }
  const ready = Object.values(checks).every(Boolean)
  // Optional admin status is boolean-only diagnostic information, never an ID
  // or a prerequisite for normal users. Reuse /ready; no new public route.
  const optional = { giftAdmin: { configured: Boolean(env.MEMBERSHIP_ADMIN_USER_IDS?.trim()), blocking: false } }
  return Response.json({status: ready ? 'ready' : 'not_ready', checks, optional}, {
    status: ready ? 200 : 503, headers: {'Cache-Control':'no-store'},
  })
}
