import { DatabaseSync } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { migrationFiles } from './testSupport/migrations.js'

const name = '0042_photo_deletion_fences.sql'
const sql = () => readFileSync(`migrations/${name}`, 'utf8')

function baseline() {
  const db = new DatabaseSync(':memory:')
  db.exec('PRAGMA foreign_keys = ON')
  const files = migrationFiles()
  expect(files.at(-2)).toBe('0041_discovery_candidate_indexes.sql')
  expect(files.at(-1)).toBe(name)
  for (const file of files.slice(0, -1)) db.exec(readFileSync(`migrations/${file}`, 'utf8'))
  expect(db.prepare("SELECT id FROM users WHERE id='owner'").get()?.id).toBe('owner')
  for (const id of ['other']) db.prepare(`INSERT INTO users
    (id,auth_provider,nickname,created_at,updated_at) VALUES(?,'apple',?,'2026','2026')`).run(id, id)
  for (const [id, deleted] of [['active-photo', null], ['deleted-photo', '2026-09-01']]) {
    db.prepare(`INSERT INTO photos(id,user_id,drive_account_id,drive_file_id,kind,mime_type,file_size,
      created_at,updated_at,deleted_at,server_version) VALUES(?,'owner','','','visit','image/jpeg',10,'2026','2026',?,7)`).run(id, deleted)
  }
  db.exec(`INSERT INTO sync_mutation_receipts_v6(user_id,mutation_id,request_fingerprint,entity_type,
    entity_id,operation,status,server_version,processed_at)
    VALUES('owner','old-receipt','old-fingerprint','photo','active-photo','upsert','applied',7,'2026')`)
  return db
}

describe('0042 local photo deletion migration acceptance', () => {
  it('preserves existing active/tombstoned PhotoAsset data, schema and sync receipts', () => {
    const db = baseline()
    try {
      const photos = db.prepare('SELECT * FROM photos ORDER BY id').all()
      const receipts = db.prepare('SELECT * FROM sync_mutation_receipts_v6').all()
      const columns = db.prepare('PRAGMA table_info(photos)').all()
      db.exec(sql())
      expect(db.prepare('SELECT * FROM photos ORDER BY id').all()).toEqual(photos)
      expect(db.prepare('SELECT * FROM sync_mutation_receipts_v6').all()).toEqual(receipts)
      expect(db.prepare('PRAGMA table_info(photos)').all()).toEqual(columns)
      expect(db.prepare('SELECT * FROM photo_deletion_fences').all()).toEqual([])
      expect(db.prepare('PRAGMA foreign_key_check').all()).toEqual([])
      expect(db.prepare('PRAGMA integrity_check').get().integrity_check).toBe('ok')
    } finally { db.close() }
  })

  it('enforces owner foreign keys, non-null fields, owner/photo uniqueness and account cascade', () => {
    const db = baseline()
    try {
      db.exec(sql())
      const insert = db.prepare('INSERT INTO photo_deletion_fences(user_id,photo_id,deleted_at) VALUES(?,?,?)')
      insert.run('owner', 'never-uploaded', '2026-09-09')
      insert.run('other', 'never-uploaded', '2026-09-09')
      expect(() => insert.run('owner', 'never-uploaded', '2099')).toThrow()
      expect(() => insert.run('unknown', 'id', '2026')).toThrow()
      expect(() => insert.run('owner', null, '2026')).toThrow()
      expect(() => insert.run('owner', 'null-date', null)).toThrow()
      db.exec("INSERT OR IGNORE INTO photo_deletion_fences(user_id,photo_id,deleted_at) VALUES('owner','never-uploaded','2099')")
      expect(db.prepare("SELECT deleted_at,checked_at FROM photo_deletion_fences WHERE user_id='owner'").get())
        .toEqual({ deleted_at: '2026-09-09', checked_at: '' })
      db.exec("DELETE FROM users WHERE id='other'")
      expect(db.prepare('SELECT user_id FROM photo_deletion_fences').all()).toEqual([{ user_id: 'owner' }])
      expect(db.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='photo_deletion_fences_cleanup'").get()?.name)
        .toBe('photo_deletion_fences_cleanup')
    } finally { db.close() }
  })

  it('rolls back a failed transaction and supports a migration-ledger retry without losing fences', () => {
    const db = baseline()
    try {
      db.exec('BEGIN')
      db.exec(sql())
      db.exec('ROLLBACK')
      expect(db.prepare("SELECT name FROM sqlite_master WHERE name='photo_deletion_fences'").get()).toBeUndefined()
      // Model the migration runner ledger, not a claim that raw CREATE TABLE is replayable.
      db.exec('CREATE TABLE local_migration_ledger(name TEXT PRIMARY KEY)')
      const apply = () => {
        if (db.prepare('SELECT name FROM local_migration_ledger WHERE name=?').get(name)) return false
        db.exec('BEGIN')
        db.exec(sql())
        db.prepare('INSERT INTO local_migration_ledger VALUES(?)').run(name)
        db.exec('COMMIT')
        return true
      }
      expect(apply()).toBe(true)
      db.exec("INSERT INTO photo_deletion_fences(user_id,photo_id,deleted_at) VALUES('owner','retained','2026')")
      expect(apply()).toBe(false)
      expect(db.prepare('SELECT photo_id FROM photo_deletion_fences').all()).toEqual([{ photo_id: 'retained' }])
      expect(db.prepare('SELECT count(*) AS n FROM photos').get().n).toBe(2)
    } finally { db.close() }
  })
})
