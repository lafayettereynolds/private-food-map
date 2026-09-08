/** Server-owned, account-scoped trial. This module has no StoreKit dependency. */
export const SIGNUP_TRIAL_DAYS = 7
export async function signupTrialEligibility(database: D1Database, userId: string) {
  const prior = await database.prepare("SELECT id FROM membership_entitlements WHERE user_id = ? AND source = 'signup_trial' LIMIT 1").bind(userId).first()
  return { apiVersion: 1, userId, eligible: !prior, trialDays: SIGNUP_TRIAL_DAYS }
}

export async function claimSignupTrial(database: D1Database, userId: string) {
  const startsAt = new Date().toISOString()
  const expiresAt = new Date(Date.parse(startsAt) + SIGNUP_TRIAL_DAYS * 86400000).toISOString()
  // A single write and a partial UNIQUE index serialize claims across devices/workers.
  // No preflight eligibility check is relied on, and retries cannot extend the term.
  const inserted = await database.prepare(`INSERT INTO membership_entitlements
    (id,user_id,source,starts_at,expires_at,is_lifetime,status,created_at,updated_at,revoked_at)
    VALUES (?,?,'signup_trial',?,?,0,'active',?,?,NULL)
    ON CONFLICT(user_id) WHERE source = 'signup_trial' DO NOTHING RETURNING id`)
    .bind(crypto.randomUUID(),userId,startsAt,expiresAt,startsAt,startsAt).first()
  if (!inserted) return null
  return { isPremium: true, source: 'signup_trial' as const, expiresAt }
}
