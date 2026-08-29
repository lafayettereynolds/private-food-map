import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'

const database = new DatabaseSync(':memory:')
database.exec('PRAGMA foreign_keys = ON;')
for (const file of readdirSync(resolve('migrations')).filter((item) => /^\d{4}.*\.sql$/.test(item)).sort()) {
  database.exec(readFileSync(resolve('migrations', file), 'utf8'))
}
database.exec(readFileSync(resolve('migrations/0030_app_store_commerce.sql'), 'utf8'))

const now = new Date().toISOString()
database.prepare(`INSERT INTO users (id, auth_provider, nickname, created_at, updated_at)
  VALUES ('tm_storekit_migration', 'apple', 'StoreKit Migration', ?, ?)`).run(now, now)
database.prepare(`INSERT INTO app_store_accounts (user_id, app_account_token, created_at, updated_at)
  VALUES ('tm_storekit_migration', '11111111-1111-4111-8111-111111111111', ?, ?)`).run(now, now)
assert.equal(database.prepare("SELECT COUNT(*) AS value FROM app_store_accounts").get().value, 1)
assert.throws(() => database.prepare(`INSERT INTO app_store_accounts
  (user_id, app_account_token, created_at, updated_at) VALUES
  ('owner', '11111111-1111-4111-8111-111111111111', ?, ?)`).run(now, now))
for (const table of [
  'app_store_accounts', 'app_store_subscription_owners',
  'app_store_transactions', 'app_store_notification_events',
]) assert.equal(database.prepare(`SELECT COUNT(*) AS value FROM sqlite_master WHERE type='table' AND name=?`).get(table).value, 1)

console.log('0030 App Store commerce migration: PASS')
