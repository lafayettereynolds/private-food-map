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
]) database.exec(readFileSync(resolve('migrations', file), 'utf8'))

const at = '2026-08-28T08:00:00.000Z'
database.prepare(`INSERT INTO dining_companions (
  id, owner_user_id, display_name, linked_user_id, created_at, updated_at, deleted_at
) VALUES ('companion-legacy', 'owner', '  大学室友  ', NULL, ?, ?, NULL)`).run(at, at)
database.prepare(`INSERT INTO restaurants (
  id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
  preference_level, created_at, updated_at, server_version
) VALUES ('restaurant-legacy', 'owner', '', '旧餐厅', '', '', 30, 120,
  'visited', 'normal', ?, ?, 2)`).run(at, at)
database.prepare(`INSERT INTO visits (
  id, user_id, restaurant_id, visited_at, companions_json, companion_ids_json,
  recommendation_source_type, recommendation_source_user_id,
  recommendation_source_text, created_at, updated_at, server_version
) VALUES ('visit-legacy', 'owner', 'restaurant-legacy', ?, '["大学室友"]',
  '["companion-legacy"]', 'friend', NULL, '朋友小李', ?, ?, 3)`).run(at, at, at)
database.prepare(`INSERT INTO sync_change_log_v3 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
) VALUES ('owner', 'visit', 'visit-legacy', 'upsert', 3, 'legacy:visit', ?)`).run(at)
database.prepare(`INSERT INTO sync_mutation_receipts_v3 (
  user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
  status, server_version, revision, conflict_reason, processed_at
) VALUES ('owner', 'legacy:visit', 'fingerprint', 'visit', 'visit-legacy', 'upsert',
  'applied', 3, 1, NULL, ?)`).run(at)

const before = {
  restaurants: count('restaurants'), visits: count('visits'), companions: count('dining_companions'),
  maxCursor: database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v3').get().value,
}
database.exec(readFileSync(resolve('migrations', '0021_companions_recommendation_sources_sync.sql'), 'utf8'))

assertEqual(count('restaurants'), before.restaurants, 'Restaurant rows preserved')
assertEqual(count('visits'), before.visits, 'Visit rows preserved')
assertEqual(count('dining_companions'), before.companions, 'Companion rows preserved')
assertEqual(count('recommendation_sources'), 0, 'Legacy free text is not guessed into a new identity')
assertEqual(
  database.prepare("SELECT display_name FROM dining_companions WHERE id = 'companion-legacy'").get().display_name,
  '  大学室友  ',
  'Original companion display name preserved',
)
assertEqual(
  database.prepare("SELECT normalized_name FROM dining_companions WHERE id = 'companion-legacy'").get().normalized_name,
  '大学室友',
  'Companion lookup name bootstrapped',
)
assertEqual(
  database.prepare("SELECT server_version FROM dining_companions WHERE id = 'companion-legacy'").get().server_version,
  1,
  'Companion sync version bootstrapped',
)
const legacyVisit = database.prepare(`SELECT companions_json, companion_ids_json,
  recommendation_source_type, recommendation_source_text, recommendation_source_id
  FROM visits WHERE id = 'visit-legacy'`).get()
assertEqual(legacyVisit.companions_json, '["大学室友"]', 'Legacy companion snapshots preserved')
assertEqual(legacyVisit.companion_ids_json, '["companion-legacy"]', 'Legacy companion identities preserved')
assertEqual(legacyVisit.recommendation_source_type, 'friend', 'Legacy source type preserved')
assertEqual(legacyVisit.recommendation_source_text, '朋友小李', 'Legacy source text preserved')
assertEqual(legacyVisit.recommendation_source_id, null, 'Legacy source is intentionally left unlinked')
assertEqual(
  database.prepare('SELECT COUNT(*) AS value FROM sync_change_log_v4 WHERE revision <= ?').get(before.maxCursor).value,
  1,
  'Existing cursor revisions retained',
)
assertEqual(
  database.prepare("SELECT COUNT(*) AS value FROM sync_mutation_receipts_v4 WHERE mutation_id = 'legacy:visit'").get().value,
  1,
  'Existing idempotency receipt retained',
)
if (database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v4').get().value <= before.maxCursor) {
  throw new Error('Companion bootstrap must advance the incremental cursor.')
}
assertEqual(database.prepare('PRAGMA foreign_key_check').all().length, 0, 'Foreign key integrity')

console.log('P2-F companion/source incremental migration test passed.')

function count(table) {
  return database.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}
