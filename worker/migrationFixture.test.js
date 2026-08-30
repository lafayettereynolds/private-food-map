import { DatabaseSync } from 'node:sqlite'
import { describe, expect, it } from 'vitest'
import { applyAllMigrations, migrationFiles } from './testSupport/migrations.js'

describe('Worker integration migration fixture', () => {
  it('applies every production migration in order, including user_blocks', () => {
    const sqlite = new DatabaseSync(':memory:')
    sqlite.exec('PRAGMA foreign_keys = ON;')

    const applied = applyAllMigrations(sqlite)

    expect(applied).toEqual(migrationFiles())
    expect(applied.at(-1)).toBe('0032_release_safety.sql')
    expect(sqlite.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'user_blocks'`).get()?.name).toBe('user_blocks')
    expect(sqlite.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'app_store_transactions'`).get()?.name)
      .toBe('app_store_transactions')
    expect(sqlite.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'public_share_links'`).get()?.name).toBe('public_share_links')
  })
})
