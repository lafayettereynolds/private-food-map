import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'

const database = new DatabaseSync(':memory:')
database.exec('PRAGMA foreign_keys = ON;')
for (const file of readdirSync(resolve('migrations')).filter((value) => /^\d{4}.*\.sql$/.test(value)).sort()) {
  database.exec(readFileSync(resolve('migrations', file), 'utf8'))
}

const at = new Date().toISOString()
database.prepare(`INSERT INTO users (id, nickname, created_at, updated_at, is_test_user)
  VALUES ('tm_share_migration', 'Share Migration', ?, ?, 1)`).run(at, at)
database.prepare(`INSERT INTO public_share_links (
  share_id, owner_user_id, entity_type, entity_id, created_at, updated_at
) VALUES ('12345678901234567890123456789012', 'tm_share_migration', 'profile',
  'tm_share_migration', ?, ?)`).run(at, at)

database.exec(readFileSync(resolve('migrations/0031_public_sharing.sql'), 'utf8'))
assert.equal(database.prepare('SELECT COUNT(*) AS value FROM public_share_links').get().value, 1)
assert.throws(() => database.prepare(`INSERT INTO public_share_links (
  share_id, owner_user_id, entity_type, entity_id, created_at, updated_at
) VALUES ('abcdefghijklmnopqrstuvwxyzABCDEF', 'tm_share_migration', 'private-note', 'x', ?, ?)`).run(at, at))
assert.throws(() => database.prepare(`INSERT INTO public_share_links (
  share_id, owner_user_id, entity_type, entity_id, created_at, updated_at
) VALUES ('abcdefghijklmnopqrstuvwxyzABCDEG', 'tm_missing', 'profile', 'tm_missing', ?, ?)`).run(at, at))
assert.throws(() => database.prepare(`INSERT INTO public_share_links (
  share_id, owner_user_id, entity_type, entity_id, created_at, updated_at
) VALUES ('abcdefghijklmnopqrstuvwxyzABCDEH', 'tm_share_migration', 'profile', 'tm_share_migration', ?, ?)`).run(at, at))

console.log('0031 public sharing incremental migration: PASS')
