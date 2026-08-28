import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'

const database = new DatabaseSync(':memory:')
database.exec('PRAGMA foreign_keys = ON;')
for (const file of [
  '0001_initial.sql', '0002_add_google_drive_photos.sql', '0003_social_visit_fields.sql',
  '0004_user_avatar_thumbnail.sql', '0005_visit_tags_and_map_privacy.sql',
  '0006_avatar_presets_and_membership.sql', '0007_multi_dining_occasions.sql',
  '0008_dining_companion_links.sql', '0009_discovery_follows_and_test_markers.sql',
  '0010_membership_entitlements.sql', '0011_photo_storage_metadata.sql',
  '0012_recommendation_events.sql', '0013_restaurant_lists.sql',
  '0014_restaurant_contact_details.sql', '0015_restaurant_place_identities.sql',
  '0016_sync_v1.sql', '0017_native_auth.sql', '0018_visit_core_fields.sql',
  '0019_dish_photo_sync.sql', '0020_visit_dish_associations.sql',
  '0021_companions_recommendation_sources_sync.sql',
]) database.exec(readFileSync(resolve('migrations', file), 'utf8'))

const at = '2026-08-28T08:00:00.000Z'
const longLegacyName = `Development ${'profile-migration-'.repeat(3)}`
database.prepare(`INSERT INTO users (
  id, auth_provider, email, nickname, bio, city, avatar_photo_id,
  avatar_preset_id, map_sharing_enabled, map_visibility, created_at, updated_at
) VALUES ('tm_profile_legacy', 'apple', 'private@example.test', ?, '旧版简介',
  '杭州', NULL, 'otter', 1, 'public', ?, ?)`)
  .run(longLegacyName, at, at)
database.prepare(`INSERT INTO auth_identities (
  id, user_id, provider, provider_subject, email, created_at, updated_at,
  last_authenticated_at
) VALUES ('identity-profile', 'tm_profile_legacy', 'apple', 'secret-apple-sub',
  'private@example.test', ?, ?, ?)`)
  .run(at, at, at)

const before = {
  users: count('users'),
  identities: count('auth_identities'),
  maxCursor: database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v4').get().value ?? 0,
}
database.exec(readFileSync(resolve('migrations', '0022_user_profiles_sync.sql'), 'utf8'))

assertEqual(count('users'), before.users, 'User rows preserved')
assertEqual(count('auth_identities'), before.identities, 'Auth identities preserved')
const profile = database.prepare(`SELECT * FROM user_profiles
  WHERE user_id = 'tm_profile_legacy'`).get()
assertEqual(profile.display_name, longLegacyName, 'Long legacy Display Name preserved without truncation')
assertEqual(profile.bio, '旧版简介', 'Bio preserved')
assertEqual(profile.city, '杭州', 'City preserved')
assertEqual(profile.avatar_preset_id, 'otter', 'Preset avatar preserved')
assertEqual(profile.visibility, 'public', 'Existing public visibility preserved')
assertEqual(profile.server_version, 1, 'Profile server version bootstrapped')
assertEqual(
  database.prepare("SELECT COUNT(*) AS value FROM sync_change_log_v5 WHERE entity_type = 'profile' AND entity_id = 'tm_profile_legacy'").get().value,
  1,
  'Profile bootstrap revision created',
)
assertEqual(
  database.prepare('SELECT COUNT(*) AS value FROM sync_change_log_v5 WHERE revision <= ?').get(before.maxCursor).value,
  before.maxCursor,
  'Existing cursor revisions retained',
)
assertEqual(
  database.prepare("SELECT COUNT(*) AS value FROM sync_mutation_receipts_v5").get().value,
  database.prepare("SELECT COUNT(*) AS value FROM sync_mutation_receipts_v4").get().value,
  'Existing idempotency receipts retained',
)
assertEqual(
  database.prepare("SELECT provider_subject FROM auth_identities WHERE id = 'identity-profile'").get().provider_subject,
  'secret-apple-sub',
  'Apple identity remains separate and unchanged',
)
assertEqual(database.prepare('PRAGMA foreign_key_check').all().length, 0, 'Foreign key integrity')

console.log('P3-A user profile incremental migration test passed.')

function count(table) {
  return database.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}
