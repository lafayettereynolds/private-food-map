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
  '0027_social_hardening.sql',
]) database.exec(readFileSync(resolve('migrations', migration), 'utf8'))

const at = '2026-08-28T18:00:00.000Z'
database.exec(`
  INSERT INTO users (id, nickname, created_at, updated_at)
  VALUES ('tm_p4f_migration', 'P4-F Migration', '${at}', '${at}');
  INSERT INTO user_profiles (
    user_id, display_name, bio, city, avatar_preset_id, visibility,
    created_at, updated_at, server_version, last_mutation_id
  ) VALUES (
    'tm_p4f_migration', 'P4-F Migration', '', '杭州', 'otter', 'public',
    '${at}', '${at}', 1, 'bootstrap:profile:tm_p4f_migration'
  );
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude,
    status, preference_level, marker_type, marker_emoji, created_at, updated_at,
    server_version, last_mutation_id
  ) VALUES (
    'restaurant-existing-list', 'tm_p4f_migration', '', 'Existing Apple Place',
    '西湖边', '杭州', 30.25, 120.16, 'visited', 'normal', 'emoji', '🍣',
    '${at}', '${at}', 1, 'bootstrap:restaurant:restaurant-existing-list'
  );
  INSERT INTO restaurant_place_identities (
    restaurant_id, user_id, provider, external_id, is_primary,
    created_at, updated_at
  ) VALUES (
    'restaurant-existing-list', 'tm_p4f_migration',
    'apple_maps', 'apple-existing-list', 1, '${at}', '${at}'
  );
  INSERT INTO restaurant_lists (
    id, user_id, title, description, visibility, is_ranked, cover_mode,
    created_at, updated_at
  ) VALUES (
    'list-existing', 'tm_p4f_migration', 'Existing List', 'must survive',
    'public', 1, 'automatic', '${at}', '${at}'
  );
  INSERT INTO restaurant_list_items (
    id, list_id, restaurant_id, position, note, created_at, updated_at
  ) VALUES (
    'list-item-existing', 'list-existing', 'restaurant-existing-list', 0,
    'legacy Web note', '${at}', '${at}'
  );
`)

const previousMaxRevision = database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v5').get().value ?? 0
database.exec(readFileSync(resolve('migrations', '0028_restaurant_lists_v1.sql'), 'utf8'))

const migratedList = database.prepare("SELECT * FROM restaurant_lists WHERE id = 'list-existing'").get()
const migratedItem = database.prepare("SELECT * FROM restaurant_list_items WHERE id = 'list-item-existing'").get()
assert.equal(migratedList.title, 'Existing List')
assert.equal(migratedList.description, 'must survive')
assert.equal(migratedList.active_item_count, 1)
assert.equal(migratedList.server_version, 1)
assert.equal(migratedItem.list_id, 'list-existing')
assert.equal(migratedItem.restaurant_id, 'restaurant-existing-list')
assert.equal(migratedItem.user_id, 'tm_p4f_migration')
assert.equal(migratedItem.restaurant_global_key, 'apple_maps:apple-existing-list')
assert.equal(migratedItem.note, 'legacy Web note')
assert.equal(database.prepare(`SELECT COUNT(*) AS value FROM sync_change_log_v6
  WHERE entity_type IN ('restaurantList', 'restaurantListItem')`).get().value, 2)
assert(database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v6').get().value > previousMaxRevision)
assert.equal(database.prepare('PRAGMA foreign_key_check').all().length, 0)

const indexes = new Set(database.prepare("SELECT name FROM sqlite_master WHERE type = 'index'").all().map((row) => row.name))
for (const name of [
  'idx_restaurant_lists_owner_visibility_updated',
  'idx_restaurant_list_items_owner_list_position',
  'idx_restaurant_list_items_global_identity',
  'idx_sync_change_log_v6_pull',
]) assert(indexes.has(name), `missing ${name}`)

console.log('P4-F incremental migration preserves legacy Web list/item relationships and adds Sync V1 metadata.')
