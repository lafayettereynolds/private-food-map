import { DatabaseSync } from 'node:sqlite'
import { describe, expect, it } from 'vitest'
import { applyAllMigrations, migrationFiles } from './testSupport/migrations.js'

describe('Worker integration migration fixture', () => {
  it('applies every production migration in order, including user_blocks', () => {
    const sqlite = new DatabaseSync(':memory:')
    sqlite.exec('PRAGMA foreign_keys = ON;')

    const applied = applyAllMigrations(sqlite)

    expect(applied).toEqual(migrationFiles())
    expect(applied.at(-1)).toBe('0037_signup_trial.sql')
    for (const table of ['referrals', 'premium_rewards', 'referral_audit_log',
      'private_directory_profiles', 'recommendation_preference_events']) {
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
