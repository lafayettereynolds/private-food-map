import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'

const database = new DatabaseSync(':memory:')
database.exec('PRAGMA foreign_keys = ON;')
for (const migration of [
  '0001_initial.sql', '0002_add_google_drive_photos.sql', '0003_social_visit_fields.sql',
  '0004_user_avatar_thumbnail.sql', '0005_visit_tags_and_map_privacy.sql',
  '0006_avatar_presets_and_membership.sql', '0007_multi_dining_occasions.sql',
  '0008_dining_companion_links.sql', '0009_discovery_follows_and_test_markers.sql',
  '0010_membership_entitlements.sql', '0011_photo_storage_metadata.sql',
  '0012_recommendation_events.sql', '0013_restaurant_lists.sql',
  '0014_restaurant_contact_details.sql', '0015_restaurant_place_identities.sql',
  '0016_sync_v1.sql', '0017_native_auth.sql', '0018_visit_core_fields.sql',
  '0019_dish_photo_sync.sql', '0020_visit_dish_associations.sql',
  '0021_companions_recommendation_sources_sync.sql', '0022_user_profiles_sync.sql',
  '0023_social_relationships_v1.sql', '0024_social_legacy_write_compat.sql',
  '0025_discovery_v1_indexes.sql', '0026_public_community_v1_indexes.sql',
]) database.exec(readFileSync(resolve('migrations', migration), 'utf8'))

const at = '2026-08-28T16:00:00.000Z'
for (const id of ['tm_p3e_a', 'tm_p3e_b']) {
  database.prepare(`INSERT INTO users (id, nickname, created_at, updated_at)
    VALUES (?, ?, ?, ?)`).run(id, id, at, at)
}
database.prepare(`INSERT INTO friendships (
  id, requester_id, addressee_id, status, created_at, updated_at,
  pair_user_a, pair_user_b, deleted_at, server_version
) VALUES ('p3e-existing-friend', 'tm_p3e_a', 'tm_p3e_b', 'accepted', ?, ?,
  'tm_p3e_a', 'tm_p3e_b', NULL, 4)`).run(at, at)

const before = database.prepare("SELECT * FROM friendships WHERE id = 'p3e-existing-friend'").get()
const migration = readFileSync(resolve('migrations', '0027_social_hardening.sql'), 'utf8')
database.exec(migration)
database.exec(migration)
const after = database.prepare("SELECT * FROM friendships WHERE id = 'p3e-existing-friend'").get()

assert.deepEqual(after, before)
assert(database.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'public_api_rate_limits'").get())
assert(database.prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_public_api_rate_limits_expiry'").get())
assert.equal(database.prepare('PRAGMA foreign_key_check').all().length, 0)

console.log('P3-E additive social hardening migration is idempotent and preserves existing relationships.')
