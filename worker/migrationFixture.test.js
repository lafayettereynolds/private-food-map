import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { applyAllMigrations, migrationFiles } from './testSupport/migrations.js'

describe('Worker integration migration fixture', () => {
  it('isolates historical Sandbox while preserving Production, gifts, legacy audit and ownership', () => {
    const sqlite = new DatabaseSync(':memory:')
    sqlite.exec('PRAGMA foreign_keys = ON')
    const files = migrationFiles()
    for (const file of files.slice(0, files.indexOf('0038_storekit_environment_isolation.sql'))) sqlite.exec(readFileSync(`migrations/${file}`, 'utf8'))
    for (const user of ['sandbox_only', 'mixed']) {
      sqlite.prepare(`INSERT INTO users(id,auth_provider,nickname,membership_tier,created_at,updated_at)
        VALUES(?,'apple',?,'member','2020-01-01','2020-01-01')`).run(user,user)
      sqlite.prepare(`INSERT INTO app_store_accounts VALUES(?,?,?,?)`).run(user,`token-${user}`,'2020','2020')
    }
    for (const [id,user,environment] of [['s1','sandbox_only','Sandbox'],['s2','mixed','Sandbox'],['p1','mixed','Production']]) {
      sqlite.prepare(`INSERT INTO app_store_subscription_owners VALUES(?,?,?,?,?)`).run(id,user,`token-${user}`,'2020','2020')
      sqlite.prepare(`INSERT INTO app_store_transactions(transaction_id,original_transaction_id,user_id,app_account_token,
        product_id,environment,purchase_at,expires_at,signed_transaction_digest,verification_source,verified_at,created_at,updated_at)
        VALUES(?,?,?,?,?,?,'2020-01-01','2099-01-01','digest','app_store_server_api','2020','2020','2020')`)
        .run(id,id,user,`token-${user}`,'monthly',environment)
      sqlite.prepare(`INSERT INTO membership_entitlements(id,user_id,source,starts_at,expires_at,created_at,updated_at)
        VALUES(?,?,'app_store_monthly','2020-01-01','2099-01-01','2020','2020')`).run(`app-store:${id}`,user)
    }
    sqlite.exec(`INSERT INTO membership_entitlements(id,user_id,source,starts_at,is_lifetime,created_at,updated_at)
      VALUES('gift','mixed','gift','2020-01-01',1,'2020','2020')`)
    const retained = sqlite.prepare("SELECT * FROM membership_entitlements WHERE id IN ('gift','app-store:p1') ORDER BY id").all()
    const legacy = sqlite.prepare('SELECT * FROM app_store_transactions ORDER BY transaction_id').all()
    sqlite.exec(readFileSync('migrations/0038_storekit_environment_isolation.sql', 'utf8'))
    expect(sqlite.prepare('SELECT * FROM membership_entitlements ORDER BY id').all()).toEqual(retained)
    expect(sqlite.prepare('SELECT id FROM sandbox_membership_entitlements ORDER BY id').all().map(x=>x.id)).toEqual(['app-store:s1','app-store:s2'])
    expect(sqlite.prepare('SELECT * FROM app_store_transactions ORDER BY transaction_id').all()).toEqual(legacy)
    expect(sqlite.prepare('SELECT count(*) AS n FROM app_store_transactions_v2').get().n).toBe(3)
    expect(sqlite.prepare("SELECT membership_tier FROM users WHERE id='sandbox_only'").get().membership_tier).toBe('free')
    expect(sqlite.prepare("SELECT membership_tier FROM users WHERE id='mixed'").get().membership_tier).toBe('member')
    sqlite.exec(`INSERT INTO app_store_verification_audit(environment,transaction_id,original_transaction_id,user_id,signed_transaction_digest,verified_at)
      VALUES('Sandbox','s1','s1','sandbox_only','digest','2020')`)
    expect(()=>sqlite.exec('DELETE FROM app_store_verification_audit')).toThrow('immutable verification audit')
    expect(()=>sqlite.exec("UPDATE app_store_verification_audit SET user_id='mixed'")).toThrow('immutable verification audit')
    expect(sqlite.prepare('PRAGMA foreign_key_check').all()).toEqual([])
    sqlite.close()
  })
  it('applies every production migration in order, including user_blocks', () => {
    const sqlite = new DatabaseSync(':memory:')
    sqlite.exec('PRAGMA foreign_keys = ON;')

    const applied = applyAllMigrations(sqlite)

    expect(applied).toEqual(migrationFiles())
    expect(applied.at(-2)).toBe('0041_discovery_candidate_indexes.sql')
    expect(applied.at(-1)).toBe('0042_photo_deletion_fences.sql')
    expect(sqlite.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='photo_deletion_fences'").get()?.name).toBe('photo_deletion_fences')
    for (const name of ['idx_restaurants_discovery_trimmed_city', 'idx_visits_discovery_candidate', 'idx_wants_discovery_candidate']) {
      expect(sqlite.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name=?").get(name)?.name).toBe(name)
    }
    for (const table of ['referrals', 'premium_rewards', 'referral_audit_log',
      'private_directory_profiles', 'recommendation_preference_events',
      'app_store_owners_v2', 'app_store_transactions_v2', 'app_store_notification_events_v2', 'sandbox_membership_entitlements', 'sandbox_offer_assignments']) {
      expect(sqlite.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?").get(table)?.name).toBe(table)
    }
    expect(sqlite.prepare('PRAGMA foreign_key_check').all()).toEqual([])
    expect(sqlite.prepare('PRAGMA quick_check').get()?.quick_check).toBe('ok')
    expect(sqlite.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'user_blocks'`).get()?.name).toBe('user_blocks')
    expect(sqlite.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'app_store_transactions'`).get()?.name)
      .toBe('app_store_transactions')
    expect(sqlite.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'public_share_links'`).get()?.name).toBe('public_share_links')
    expect(sqlite.prepare(`SELECT website_url FROM restaurants LIMIT 1`).columns()[0]?.name).toBe('website_url')
  })
})
