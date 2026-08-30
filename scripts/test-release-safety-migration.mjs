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
  VALUES ('tm_release_a', 'Release A', ?, ?, 1), ('tm_release_b', 'Release B', ?, ?, 1)`)
  .run(at, at, at, at)

database.prepare(`INSERT INTO account_deletion_jobs (
  id, user_id, request_id, request_fingerprint, status_token_hash,
  status, requested_at, updated_at
) VALUES ('delete_release_a', 'tm_release_a', 'request-a', 'fingerprint-a',
  'token-hash-a', 'confirmed', ?, ?)`)
  .run(at, at)
database.prepare(`INSERT INTO account_deletion_objects (
  job_id, storage_key, status, updated_at
) VALUES ('delete_release_a', 'users/tm_release_a/photo.jpg', 'pending', ?)`)
  .run(at)
database.prepare(`INSERT INTO user_blocks (
  id, blocker_user_id, blocked_user_id, created_at, updated_at
) VALUES ('block-release', 'tm_release_a', 'tm_release_b', ?, ?)`)
  .run(at, at)
database.prepare(`INSERT INTO content_reports (
  id, reporter_user_id, content_type, content_id, reason,
  request_id, request_fingerprint, created_at, updated_at
) VALUES ('report-release', 'tm_release_a', 'user', 'tm_release_b', 'spam',
  'report-request', 'report-fingerprint', ?, ?)`)
  .run(at, at)

// The additive migration can be evaluated again without destructive effects.
database.exec(readFileSync(resolve('migrations/0032_release_safety.sql'), 'utf8'))
assert.equal(database.prepare('SELECT COUNT(*) AS value FROM account_deletion_jobs').get().value, 1)
assert.equal(database.prepare('SELECT COUNT(*) AS value FROM account_deletion_objects').get().value, 1)
assert.equal(database.prepare('SELECT COUNT(*) AS value FROM user_blocks').get().value, 1)
assert.equal(database.prepare('SELECT COUNT(*) AS value FROM content_reports').get().value, 1)

assert.throws(() => database.prepare(`INSERT INTO user_blocks (
  id, blocker_user_id, blocked_user_id, created_at, updated_at
) VALUES ('self-block', 'tm_release_a', 'tm_release_a', ?, ?)`)
  .run(at, at))
assert.throws(() => database.prepare(`INSERT INTO account_deletion_jobs (
  id, user_id, request_id, request_fingerprint, status_token_hash,
  status, requested_at, updated_at
) VALUES ('delete-release-b', 'tm_release_b', 'request-b', 'fingerprint-b',
  'token-hash-a', 'confirmed', ?, ?)`)
  .run(at, at))
assert.throws(() => database.prepare(`INSERT INTO content_reports (
  id, reporter_user_id, content_type, content_id, reason,
  request_id, request_fingerprint, created_at, updated_at
) VALUES ('bad-report', 'tm_release_a', 'private-note', 'x', 'spam',
  'bad-request', 'bad-fingerprint', ?, ?)`)
  .run(at, at))

console.log('0032 release safety incremental migration: PASS')
