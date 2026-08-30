import { readdirSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const migrationPattern = /^\d{4}.*\.sql$/

/**
 * Returns the production migration source in the same lexical order Wrangler
 * uses for the repository's zero-padded migration names.
 */
export function migrationFiles(migrationsDirectory = resolve('migrations')) {
  return readdirSync(migrationsDirectory)
    .filter((file) => migrationPattern.test(file))
    .sort()
}

/**
 * Builds an integration-test database from the real migration source. Tests
 * must not keep a second, hand-maintained schema or selectively skip newer
 * migrations.
 */
export function applyAllMigrations(sqlite, migrationsDirectory = resolve('migrations')) {
  const files = migrationFiles(migrationsDirectory)
  for (const file of files) {
    sqlite.exec(readFileSync(resolve(migrationsDirectory, file), 'utf8'))
  }
  return files
}
