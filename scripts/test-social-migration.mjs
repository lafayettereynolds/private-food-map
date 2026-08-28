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
  '0021_companions_recommendation_sources_sync.sql', '0022_user_profiles_sync.sql',
]) database.exec(readFileSync(resolve('migrations', file), 'utf8'))

const at = '2026-08-28T12:00:00.000Z'
for (const id of ['tm_a', 'tm_b', 'tm_c']) {
  database.prepare(`INSERT INTO users (id, nickname, created_at, updated_at)
    VALUES (?, ?, ?, ?)`).run(id, id, at, at)
}
database.prepare(`INSERT INTO friendships (id, requester_id, addressee_id, status, created_at, updated_at)
  VALUES ('old-a-b', 'tm_a', 'tm_b', 'pending', ?, ?),
         ('old-b-a', 'tm_b', 'tm_a', 'accepted', ?, ?)`)
  .run(at, at, at, '2026-08-28T12:01:00.000Z')
database.prepare(`INSERT INTO follows (id, follower_id, followed_user_id, created_at)
  VALUES ('old-follow', 'tm_a', 'tm_c', ?)`).run(at)

const beforeFriendships = count('friendships')
const beforeFollows = count('follows')
database.exec(readFileSync(resolve('migrations', '0023_social_relationships_v1.sql'), 'utf8'))
database.exec(readFileSync(resolve('migrations', '0024_social_legacy_write_compat.sql'), 'utf8'))

assertEqual(count('friendships'), beforeFriendships, 'Legacy Friendship rows preserved')
assertEqual(count('follows'), beforeFollows, 'Legacy Follow rows preserved')
assertEqual(database.prepare(`SELECT COUNT(*) AS value FROM friendships
  WHERE pair_user_a = 'tm_a' AND pair_user_b = 'tm_b' AND status = 'accepted'
    AND deleted_at IS NULL`).get().value, 1, 'Accepted canonical pair retained')
assertEqual(database.prepare(`SELECT COUNT(*) AS value FROM friendships
  WHERE pair_user_a = 'tm_a' AND pair_user_b = 'tm_b' AND deleted_at IS NOT NULL`).get().value,
1, 'Reversed duplicate retained as inactive history')
assertEqual(database.prepare("SELECT updated_at FROM follows WHERE id = 'old-follow'").get().updated_at,
at, 'Legacy Follow updatedAt backfilled')
database.prepare(`INSERT INTO friendships (id, requester_id, addressee_id, status, created_at, updated_at)
  VALUES ('legacy-web-write', 'tm_a', 'tm_c', 'pending', ?, ?)`).run(at, at)
assertEqual(database.prepare("SELECT pair_user_a FROM friendships WHERE id = 'legacy-web-write'").get().pair_user_a,
'tm_a', 'Legacy Web Friendship write receives canonical pair')
database.prepare(`INSERT INTO follows (id, follower_id, followed_user_id, created_at)
  VALUES ('legacy-web-follow', 'tm_b', 'tm_c', ?)`).run(at)
assertEqual(database.prepare("SELECT updated_at FROM follows WHERE id = 'legacy-web-follow'").get().updated_at,
at, 'Legacy Web Follow write receives updatedAt')

assertThrows(() => database.prepare(`INSERT INTO friendships (
  id, requester_id, addressee_id, status, created_at, updated_at, pair_user_a, pair_user_b
) VALUES ('self-friend', 'tm_a', 'tm_a', 'pending', ?, ?, 'tm_a', 'tm_a')`).run(at, at),
'Database rejects self Friendship')
assertThrows(() => database.prepare(`INSERT INTO follows (
  id, follower_id, followed_user_id, created_at, updated_at
) VALUES ('self-follow', 'tm_a', 'tm_a', ?, ?)`).run(at, at),
'Database rejects self Follow')

assertEqual(database.prepare('PRAGMA foreign_key_check').all().length, 0, 'Foreign key integrity')
console.log('P3-B social relationship incremental migration test passed.')

function count(table) {
  return database.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}

function assertThrows(operation, label) {
  try { operation() } catch { return }
  throw new Error(`${label}: expected operation to throw`)
}
