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
  '0019_dish_photo_sync.sql',
]) database.exec(readFileSync(resolve('migrations', file), 'utf8'))

const at = '2026-08-27T08:00:00.000Z'
database.prepare(`INSERT INTO restaurants (
  id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
  preference_level, created_at, updated_at, server_version
) VALUES ('restaurant-legacy', 'owner', 'B0LEGACY', '旧餐厅', '', '', 30, 120,
  'visited', 'normal', ?, ?, 2)`).run(at, at)
database.prepare(`INSERT INTO visits (
  id, user_id, restaurant_id, visited_at, dishes_json, photo_ids_json,
  created_at, updated_at, server_version
) VALUES ('visit-legacy', 'owner', 'restaurant-legacy', ?, '[]', '[]', ?, ?, 3)`)
  .run(at, at, at)
for (const [id, deletedAt] of [['dish-active', null], ['dish-deleted', at]]) {
  database.prepare(`INSERT INTO dishes (
    id, user_id, restaurant_id, visit_id, name, taste, rating, price, sort_order,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  ) VALUES (?, 'owner', 'restaurant-legacy', 'visit-legacy', ?, '', NULL, NULL, 0,
    ?, ?, ?, 4, ?)`).run(id, id, at, at, deletedAt, `old:${id}`)
}
database.prepare(`INSERT INTO sync_change_log_v2 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
) VALUES ('owner', 'dish', 'dish-active', 'upsert', 4, 'old:dish-active', ?)`)
  .run(at)

const before = {
  restaurants: count('restaurants'), visits: count('visits'), dishes: count('dishes'),
  maxCursor: database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v2').get().value,
}
database.exec(readFileSync(resolve('migrations', '0020_visit_dish_associations.sql'), 'utf8'))

assertEqual(count('restaurants'), before.restaurants, 'Restaurant rows preserved')
assertEqual(count('visits'), before.visits, 'Visit rows preserved')
assertEqual(count('dishes'), before.dishes, 'Dish rows preserved')
assertEqual(count('visit_dishes'), 2, 'Every legacy Dish received an association')
assertEqual(
  database.prepare("SELECT id FROM visit_dishes WHERE dish_id = 'dish-active'").get().id,
  'legacy:dish-active:visit-legacy',
  'Legacy association ID is deterministic',
)
assertEqual(
  database.prepare("SELECT deleted_at FROM visit_dishes WHERE dish_id = 'dish-deleted'").get().deleted_at,
  at,
  'Deleted Dish remains deleted through its compatibility association',
)
assertEqual(
  database.prepare("SELECT COUNT(*) AS value FROM sync_change_log_v3 WHERE revision <= ?").get(before.maxCursor).value,
  1,
  'Existing cursor revisions are retained',
)
if (database.prepare('SELECT MAX(revision) AS value FROM sync_change_log_v3').get().value <= before.maxCursor) {
  throw new Error('VisitDish bootstrap changes must advance the incremental cursor.')
}
assertEqual(database.prepare('PRAGMA foreign_key_check').all().length, 0, 'Foreign key integrity')

console.log('P2-C VisitDish migration test passed.')

function count(table) {
  return database.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}
