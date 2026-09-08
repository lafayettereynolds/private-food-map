/** Server-only referral attribution, qualification and reward settlement. */
const STORE = "source IN ('app_store_monthly','app_store_annual','app_store_yearly')"
const stamp = (date: Date) => date.toISOString()

export function normalizeReferralCode(value: unknown): string | null {
  return typeof value === 'string' && /^[a-f0-9]{24}$/i.test(value.trim()) ? value.trim().toLowerCase() : null
}

export async function registrationReferral(database: D1Database, value: unknown, userID: string, now: Date) {
  if (value == null || value === '') return []
  const code = normalizeReferralCode(value)
  const row = code && await database.prepare(`SELECT c.user_id FROM referral_codes c JOIN users u ON u.id=c.user_id
    WHERE c.code=? AND u.deleted_at IS NULL`).bind(code).first<{user_id:string}>()
  if (!row || row.user_id === userID) throw new Error('invalid_referral_code')
  return [database.prepare(`INSERT INTO referrals(invitee_id,referrer_id,code,bound_at,actor)
    VALUES(?,?,?,?,?)`).bind(userID,row.user_id,code,stamp(now),'system:registration')]
}

export async function qualifyReferral(database: D1Database, userID: string, now = new Date()) {
  // One UPDATE + DB triggers atomically reserve a lifetime slot and award both sides.
  // A revoked qualified invitation keeps its slot forever. No read/then-increment race.
  await database.prepare(`UPDATE referrals SET
    status=CASE WHEN (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id=referrals.referrer_id AND r.slot IS NOT NULL)<5 THEN 'qualified' ELSE 'capped' END,
    slot=CASE WHEN (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id=referrals.referrer_id AND r.slot IS NOT NULL)<5
      THEN 1+(SELECT COUNT(*) FROM referrals r WHERE r.referrer_id=referrals.referrer_id AND r.slot IS NOT NULL) ELSE NULL END,
    qualified_at=?, qualifying_visit_id=(SELECT v.id FROM visits v JOIN restaurants p ON p.id=v.restaurant_id AND p.user_id=v.user_id
      WHERE v.user_id=? AND v.deleted_at IS NULL AND p.deleted_at IS NULL AND p.is_test_data=0
        AND julianday(v.visited_at) IS NOT NULL AND julianday(v.visited_at)<=julianday(?) ORDER BY v.created_at,v.id LIMIT 1), actor='system:referral'
    WHERE invitee_id=? AND status='pending' AND EXISTS(SELECT 1 FROM visits v JOIN restaurants p ON p.id=v.restaurant_id AND p.user_id=v.user_id
      WHERE v.user_id=? AND v.deleted_at IS NULL AND p.deleted_at IS NULL AND p.is_test_data=0
        AND julianday(v.visited_at) IS NOT NULL AND julianday(v.visited_at)<=julianday(?))`)
    .bind(stamp(now),userID,stamp(now),userID,userID,stamp(now)).run()
}

export async function settlePremiumRewards(database: D1Database, userID: string, now = new Date()) {
  const at = stamp(now)
  const pending = await database.prepare("SELECT id FROM premium_rewards WHERE user_id=? AND state='pending' ORDER BY granted_at,id").bind(userID).all<{id:string}>()
  for (const row of pending.results) {
    // Lifetime at grant consumes the referral normally but never adds duration.
    await database.prepare(`UPDATE premium_rewards SET state='lifetime',changed_at=? WHERE id=? AND state='pending'
      AND EXISTS(SELECT 1 FROM membership_entitlements e WHERE e.user_id=premium_rewards.user_id AND e.is_lifetime=1
        AND e.starts_at<=premium_rewards.granted_at AND (e.revoked_at IS NULL OR e.revoked_at>premium_rewards.granted_at))`).bind(at,row.id).run()
    // Rewards have their own interval. Never rewrite an Apple or administrator's grant.
    // Pending Apple rewards start at its recorded end, not the next app launch.
    await database.prepare(`UPDATE premium_rewards SET state='active',changed_at=?,
      starts_at=strftime('%Y-%m-%dT%H:%M:%fZ',max(julianday(granted_at),
        COALESCE((SELECT MAX(julianday(CASE WHEN status='revoked' THEN COALESCE(revoked_at,expires_at) ELSE expires_at END))
          FROM membership_entitlements WHERE user_id=premium_rewards.user_id AND ${STORE}),0),
        COALESCE((SELECT MAX(julianday(expires_at)) FROM membership_entitlements
          WHERE user_id=premium_rewards.user_id AND status='active' AND is_lifetime=0 AND NOT (${STORE})),0))),
      expires_at=strftime('%Y-%m-%dT%H:%M:%fZ',max(julianday(granted_at),
        COALESCE((SELECT MAX(julianday(CASE WHEN status='revoked' THEN COALESCE(revoked_at,expires_at) ELSE expires_at END))
          FROM membership_entitlements WHERE user_id=premium_rewards.user_id AND ${STORE}),0),
        COALESCE((SELECT MAX(julianday(expires_at)) FROM membership_entitlements
          WHERE user_id=premium_rewards.user_id AND status='active' AND is_lifetime=0 AND NOT (${STORE})),0))+days)
      WHERE id=? AND state='pending' AND NOT EXISTS(SELECT 1 FROM membership_entitlements
        WHERE user_id=premium_rewards.user_id AND status='active' AND ${STORE} AND starts_at<=? AND expires_at>?)`)
      .bind(at,row.id,at,at).run()
  }
}

export async function referralDashboard(database: D1Database, userID: string, origin: string, now = new Date()) {
  await qualifyReferral(database,userID,now)
  await settlePremiumRewards(database,userID,now)
  await database.prepare('INSERT OR IGNORE INTO referral_codes(user_id,code,created_at) VALUES(?,?,?)')
    .bind(userID,crypto.randomUUID().replaceAll('-','').slice(0,24),stamp(now)).run()
  const code = (await database.prepare('SELECT code FROM referral_codes WHERE user_id=?').bind(userID).first<{code:string}>())!.code
  const records = await database.prepare(`SELECT r.invitee_id AS id,r.status,r.bound_at AS boundAt,r.qualified_at AS qualifiedAt,
    r.revoked_at AS revokedAt,r.slot FROM referrals r WHERE r.referrer_id=? ORDER BY r.bound_at DESC,r.invitee_id`).bind(userID).all()
  const totals = await database.prepare(`SELECT COALESCE(SUM(CASE WHEN role='referrer' THEN days ELSE 0 END),0) AS earnedDays,
    COALESCE(SUM(CASE WHEN state='pending' THEN days ELSE 0 END),0) AS pendingDays FROM premium_rewards WHERE user_id=? AND state<>'revoked'`).bind(userID).first<{earnedDays:number,pendingDays:number}>()
  return {apiVersion:1,userID,code,inviteLink:`${origin}/invite/${code}`,qualifiedCount:records.results.filter(r=>r.slot!=null).length,
    maxQualified:5,...totals,records:records.results.map(({slot,...r})=>r)}
}

export async function revokeReferral(database: D1Database, inviteeID: string, actor: string, note: string, now = new Date()) {
  if (!note.trim()) throw new Error('A revocation reason is required.')
  return database.prepare("UPDATE referrals SET status='revoked',revoked_at=?,actor=?,note=? WHERE invitee_id=? AND status<>'revoked'")
    .bind(stamp(now),actor,note.trim().slice(0,500),inviteeID).run()
}

export async function settleAllPremiumRewards(database: D1Database) {
  // Only ready owners enter the batch; long-running subscriptions cannot starve the queue.
  const at=new Date().toISOString()
  const users = await database.prepare(`SELECT DISTINCT user_id FROM premium_rewards r WHERE state='pending'
    AND NOT EXISTS(SELECT 1 FROM membership_entitlements e WHERE e.user_id=r.user_id AND e.status='active'
      AND ${STORE} AND e.starts_at<=? AND e.expires_at>?) LIMIT 500`).bind(at,at).all<{user_id:string}>()
  for (const user of users.results) await settlePremiumRewards(database,user.user_id)
}
