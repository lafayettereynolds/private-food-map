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
]) database.exec(readFileSync(resolve('migrations', file), 'utf8'))

const at = '2026-08-27T08:00:00.000Z'
database.prepare(`INSERT INTO restaurants (
  id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
  preference_level, created_at, updated_at, server_version
) VALUES (?, ?, ?, ?, '', '', 30, 120, 'visited', 'normal', ?, ?, 1)`)
  .run('restaurant-legacy', 'owner', 'B0LEGACY', '旧餐厅', at, at)
database.prepare(`INSERT INTO visits (
  id, user_id, restaurant_id, visited_at, dishes_json, photo_ids_json,
  created_at, updated_at, server_version
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)`)
  .run('visit-legacy', 'owner', 'restaurant-legacy', at, JSON.stringify([{
    id: 'dish-legacy', name: '东坡肉', taste: '甜香', rating: 4.5,
    price: 88, photoId: 'photo-dish',
  }]), JSON.stringify(['photo-visit']), at, at)
for (const photo of [
  ['photo-visit', 'visit', null],
  ['photo-dish', 'dish', 'dish-legacy'],
]) database.prepare(`INSERT INTO photos (
  id, user_id, restaurant_id, visit_id, storage_provider, drive_account_id,
  drive_file_id, storage_key, kind, mime_type, file_size, created_at, updated_at
) VALUES (?, 'owner', 'restaurant-legacy', 'visit-legacy', 'google-drive',
  'account', ?, ?, ?, 'image/jpeg', 100, ?, ?)`)
  .run(photo[0], `drive-${photo[0]}`, `drive-${photo[0]}`, photo[1], at, at)

database.exec(readFileSync(resolve('migrations', '0019_dish_photo_sync.sql'), 'utf8'))

assertEqual(database.prepare("SELECT visit_id FROM dishes WHERE id = 'dish-legacy'").get().visit_id, 'visit-legacy', 'Dish visit mapping')
assertEqual(database.prepare("SELECT restaurant_id FROM dishes WHERE id = 'dish-legacy'").get().restaurant_id, 'restaurant-legacy', 'Dish restaurant mapping')
assertEqual(database.prepare("SELECT sort_order FROM dishes WHERE id = 'dish-legacy'").get().sort_order, 0, 'Dish order')
assertEqual(database.prepare("SELECT dish_id FROM photos WHERE id = 'photo-dish'").get().dish_id, 'dish-legacy', 'Dish photo mapping')
assertEqual(database.prepare("SELECT sort_order FROM photos WHERE id = 'photo-visit'").get().sort_order, 0, 'Visit photo order')
assertEqual(database.prepare("SELECT COUNT(*) AS value FROM sync_change_log_v2").get().value,
  database.prepare("SELECT COUNT(*) AS value FROM sync_change_log").get().value + 3, 'Copied and bootstrapped revisions')
assertEqual(database.prepare('PRAGMA foreign_key_check').all().length, 0, 'Foreign key integrity')
assertEqual(database.prepare("SELECT COUNT(*) AS value FROM visits WHERE id = 'visit-legacy'").get().value, 1, 'Visit preserved')

console.log('P2-A Dish/Photo migration test passed.')

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}
