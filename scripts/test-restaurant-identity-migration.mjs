import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const repositoryRoot = resolve(fileURLToPath(new URL('..', import.meta.url)))
const temporaryDirectory = mkdtempSync(join(tmpdir(), 'taste-map-p0a-'))
const databasePath = join(temporaryDirectory, 'migration.sqlite')

try {
  const baselineMigrations = Array.from({ length: 14 }, (_, index) => {
    const prefix = String(index + 1).padStart(4, '0')
    const fileName = migrationFileName(prefix)
    return readFileSync(join(repositoryRoot, 'migrations', fileName), 'utf8')
  }).join('\n')

  executeSQL(`${baselineMigrations}\n${legacyFixtureSQL()}`)
  executeSQL(readFileSync(join(repositoryRoot, 'migrations', '0015_restaurant_place_identities.sql'), 'utf8'))
  executeSQL(`
    UPDATE restaurant_place_identities
    SET is_primary = 0, updated_at = '2026-08-27T05:00:00.000Z'
    WHERE restaurant_id = 'restaurant-1' AND is_primary = 1;
    INSERT INTO restaurant_place_identities (
      restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
    ) VALUES (
      'restaurant-1', 'owner', 'apple_maps', 'apple-place-1', 1,
      '2026-08-27T05:00:00.000Z', '2026-08-27T05:00:00.000Z'
    );
  `)

  const counts = queryRow(`
    SELECT
      (SELECT COUNT(*) FROM restaurants) AS restaurants,
      (SELECT COUNT(*) FROM visits) AS visits,
      (SELECT COUNT(*) FROM restaurant_place_identities) AS identities,
      (SELECT COUNT(*) FROM restaurant_place_identities WHERE provider = 'amap') AS amap_identities,
      (SELECT COUNT(*) FROM restaurant_place_identities WHERE provider = 'apple_maps') AS apple_identities,
      (SELECT COUNT(*) FROM visits v LEFT JOIN restaurants r ON r.id = v.restaurant_id WHERE r.id IS NULL) AS orphan_visits;
  `)
  assertEqual(counts, ['3', '2', '4', '3', '1', '0'], 'migration counts')

  const duplicateMappings = queryRow(`
    SELECT COUNT(*) FROM restaurant_place_identities
    WHERE provider = 'amap' AND external_id = 'B0DUPLICATE';
  `)
  assertEqual(duplicateMappings, ['3'], 'duplicate provider mappings are preserved')

  const primaryMapping = queryRow(`
    SELECT provider, external_id, COUNT(*) OVER ()
    FROM restaurant_place_identities
    WHERE restaurant_id = 'restaurant-1' AND is_primary = 1;
  `)
  assertEqual(primaryMapping, ['apple_maps', 'apple-place-1', '1'], 'one primary mapping per Restaurant')

  const visitLinks = queryRow(`
    SELECT group_concat(restaurant_id, ',') FROM (
      SELECT restaurant_id FROM visits ORDER BY id
    );
  `)
  assertEqual(visitLinks, ['restaurant-1,restaurant-2'], 'Visit.restaurant_id links')

  const foreignKeyErrors = executeSQL('PRAGMA foreign_key_check;').trim()
  if (foreignKeyErrors) throw new Error(`foreign_key_check failed: ${foreignKeyErrors}`)
  console.log('P0-A Restaurant identity migration test passed.')
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true })
}

function migrationFileName(prefix) {
  const names = {
    '0001': '0001_initial.sql',
    '0002': '0002_add_google_drive_photos.sql',
    '0003': '0003_social_visit_fields.sql',
    '0004': '0004_user_avatar_thumbnail.sql',
    '0005': '0005_visit_tags_and_map_privacy.sql',
    '0006': '0006_avatar_presets_and_membership.sql',
    '0007': '0007_multi_dining_occasions.sql',
    '0008': '0008_dining_companion_links.sql',
    '0009': '0009_discovery_follows_and_test_markers.sql',
    '0010': '0010_membership_entitlements.sql',
    '0011': '0011_photo_storage_metadata.sql',
    '0012': '0012_recommendation_events.sql',
    '0013': '0013_restaurant_lists.sql',
    '0014': '0014_restaurant_contact_details.sql',
  }
  return names[prefix]
}

function legacyFixtureSQL() {
  return `
    INSERT INTO restaurants (
      id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
      preference_level, created_at, updated_at
    ) VALUES
      ('restaurant-1', 'owner', 'B0DUPLICATE', '餐厅一', '地址一', '杭州', 30, 120, 'visited', 'normal', '2026-08-20T00:00:00.000Z', '2026-08-20T00:00:00.000Z'),
      ('restaurant-2', 'owner', 'B0DUPLICATE', '餐厅一重复记录', '地址一', '杭州', 30, 120, 'visited', 'normal', '2026-08-20T00:00:00.000Z', '2026-08-20T00:00:00.000Z'),
      ('restaurant-3', 'another-user', 'B0DUPLICATE', '另一用户的同店记录', '地址一', '杭州', 30, 120, 'visited', 'normal', '2026-08-20T00:00:00.000Z', '2026-08-20T00:00:00.000Z');
    INSERT INTO visits (
      id, user_id, restaurant_id, visited_at, party_size, created_at, updated_at
    ) VALUES
      ('visit-1', 'owner', 'restaurant-1', '2026-08-20T01:00:00.000Z', 1, '2026-08-20T01:00:00.000Z', '2026-08-20T01:00:00.000Z'),
      ('visit-2', 'owner', 'restaurant-2', '2026-08-21T01:00:00.000Z', 1, '2026-08-21T01:00:00.000Z', '2026-08-21T01:00:00.000Z');
  `
}

function queryRow(sql) {
  const output = executeSQL(`.mode list\n.separator |\n${sql}`).trim()
  return output.split('|')
}

function executeSQL(sql) {
  const result = spawnSync('/usr/bin/sqlite3', [databasePath], {
    input: `PRAGMA foreign_keys = ON;\n${sql}`,
    encoding: 'utf8',
  })
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || 'sqlite3 failed')
  return result.stdout
}

function assertEqual(actual, expected, label) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`)
  }
}
