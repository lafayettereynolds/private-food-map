import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'

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
]) database.exec(readFileSync(resolve('migrations', migration), 'utf8'))

database.exec(`
  INSERT INTO users (id, auth_provider, nickname, created_at, updated_at)
  VALUES ('tm_migration', 'test', 'Migration', '2026-08-28T00:00:00Z', '2026-08-28T00:00:00Z');
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, created_at, updated_at
  ) VALUES (
    'restaurant-existing', 'tm_migration', '', 'Existing', 'Address', '杭州', 30.2, 120.1,
    'visited', 'normal', 'emoji', '🍜', '2026-08-28T00:00:00Z', '2026-08-28T00:00:00Z'
  );
  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, party_size, note, created_at, updated_at, visibility
  ) VALUES (
    'visit-existing', 'tm_migration', 'restaurant-existing', '2026-08-28T00:00:00Z', 4.5,
    1, '', '2026-08-28T00:00:00Z', '2026-08-28T00:00:00Z', 'public'
  );
`)
database.exec(readFileSync(resolve('migrations', '0025_discovery_v1_indexes.sql'), 'utf8'))
database.exec(readFileSync(resolve('migrations', '0025_discovery_v1_indexes.sql'), 'utf8'))

assert.equal(database.prepare("SELECT restaurant_id FROM visits WHERE id = 'visit-existing'").get().restaurant_id, 'restaurant-existing')
assert.equal(database.prepare("SELECT COUNT(*) AS count FROM discovery_rate_limits").get().count, 0)
const indexes = new Set(database.prepare("SELECT name FROM sqlite_master WHERE type = 'index'").all().map((row) => row.name))
for (const name of [
  'idx_visits_discovery_public', 'idx_visits_discovery_owner',
  'idx_restaurants_discovery_city', 'idx_want_to_go_discovery',
  'idx_restaurant_identity_discovery',
]) assert(indexes.has(name), `missing ${name}`)

console.log('P3-C incremental migration preserves existing Restaurant/Visit links and is idempotent.')
