import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'

const database = new DatabaseSync(':memory:')
database.exec('PRAGMA foreign_keys = ON;')
const files = [
  '0001_initial.sql', '0002_add_google_drive_photos.sql', '0003_social_visit_fields.sql',
  '0004_user_avatar_thumbnail.sql', '0005_visit_tags_and_map_privacy.sql',
  '0006_avatar_presets_and_membership.sql', '0007_multi_dining_occasions.sql',
  '0008_dining_companion_links.sql', '0009_discovery_follows_and_test_markers.sql',
  '0010_membership_entitlements.sql', '0011_photo_storage_metadata.sql',
  '0012_recommendation_events.sql', '0013_restaurant_lists.sql',
  '0014_restaurant_contact_details.sql', '0015_restaurant_place_identities.sql',
]
for (const file of files) database.exec(readFileSync(resolve('migrations', file), 'utf8'))

database.exec(`
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, created_at, updated_at
  ) VALUES
    ('legacy-empty-provider', 'owner', '', '旧餐厅', '', '', 30, 120, 'visited', 'normal', '2026-08-20T00:00:00.000Z', '2026-08-20T00:00:00.000Z'),
    ('legacy-deleted', 'owner', 'B0DELETED', '已删除餐厅', '', '', 30, 120, 'visited', 'normal', '2026-08-20T00:00:00.000Z', '2026-08-20T00:00:00.000Z');
  UPDATE restaurants SET deleted_at = '2026-08-21T00:00:00.000Z' WHERE id = 'legacy-deleted';
  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, created_at, updated_at
  ) VALUES (
    'legacy-visit', 'owner', 'legacy-empty-provider', '2026-08-20T01:00:00.000Z',
    '2026-08-20T01:00:00.000Z', '2026-08-20T01:00:00.000Z'
  );
`)

database.exec(readFileSync(resolve('migrations', '0016_sync_v1.sql'), 'utf8'))
database.exec(readFileSync(resolve('migrations', '0018_visit_core_fields.sql'), 'utf8'))

assertEqual(database.prepare('SELECT COUNT(*) AS value FROM restaurants').get().value, 2, 'Restaurant count')
assertEqual(database.prepare('SELECT COUNT(*) AS value FROM visits').get().value, 1, 'Visit count')
assertEqual(database.prepare('SELECT COUNT(*) AS value FROM sync_change_log').get().value, 3, 'bootstrap change count')
assertEqual(database.prepare("SELECT operation FROM sync_change_log WHERE entity_id = 'legacy-deleted'").get().operation, 'delete', 'deleted bootstrap event')
assertEqual(database.prepare("SELECT provider FROM restaurant_place_identities WHERE restaurant_id = 'legacy-empty-provider'").get().provider, 'manual', 'manual fallback identity')
assertEqual(database.prepare("SELECT party_size_optional AS value FROM visits WHERE id = 'legacy-visit'").get().value, 1, 'legacy party size backfill')

database.exec(`
  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, party_size, created_at, updated_at
  ) VALUES (
    'rolling-worker-visit', 'owner', 'legacy-empty-provider', '2026-08-22T01:00:00.000Z', 4,
    '2026-08-22T01:00:00.000Z', '2026-08-22T01:00:00.000Z'
  );
  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, party_size, party_size_optional, created_at, updated_at
  ) VALUES (
    'native-null-visit', 'owner', 'legacy-empty-provider', '2026-08-23T01:00:00.000Z', 0, NULL,
    '2026-08-23T01:00:00.000Z', '2026-08-23T01:00:00.000Z'
  );
`)
assertEqual(database.prepare("SELECT party_size_optional AS value FROM visits WHERE id = 'rolling-worker-visit'").get().value, 4, 'rolling Worker trigger')
assertEqual(database.prepare("SELECT party_size_optional AS value FROM visits WHERE id = 'native-null-visit'").get().value, null, 'native nullable party size')
assertEqual(database.prepare('PRAGMA foreign_key_check').all().length, 0, 'foreign key integrity')

console.log('P0-B1/P1-C Sync V1 migration test passed.')

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}
