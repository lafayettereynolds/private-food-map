import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'

const database = new DatabaseSync(':memory:')
database.exec('PRAGMA foreign_keys = ON;')
for (const migration of readdirSync(resolve('migrations'))
  .filter((name) => /^\d{4}_.+\.sql$/.test(name) && name < '0029_')
  .sort()) {
  database.exec(readFileSync(resolve('migrations', migration), 'utf8'))
}

const at = '2026-08-29T08:00:00.000Z'
for (const id of ['tm_task06_a', 'tm_task06_b']) {
  database.prepare(`INSERT INTO users (id, nickname, created_at, updated_at)
    VALUES (?, ?, ?, ?)`).run(id, id, at, at)
}
database.exec(`
  INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, created_at, updated_at
  ) VALUES
    ('task06-restaurant-a', 'tm_task06_a', '', 'Legacy Shared Restaurant', 'Address', '杭州',
      30.2, 120.1, 'visited', 'normal', 'emoji', '🍜', '${at}', '${at}'),
    ('task06-restaurant-b', 'tm_task06_b', '', 'Receiver Copy', 'Address', '杭州',
      30.2, 120.1, 'visited', 'normal', 'emoji', '🍜', '${at}', '${at}');

  INSERT INTO shared_meals (
    id, restaurant_id, created_by_user_id, occurred_at, created_at, updated_at, deleted_at
  ) VALUES ('task06-meal', 'task06-restaurant-a', 'tm_task06_a', '${at}', '${at}', '${at}', NULL);

  INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, party_size, note,
    created_at, updated_at, visibility, shared_meal_id
  ) VALUES
    ('task06-source-visit', 'tm_task06_a', 'task06-restaurant-a', '${at}', 4.5, 2, 'source',
      '${at}', '${at}', 'friends', 'task06-meal'),
    ('task06-receiver-visit', 'tm_task06_b', 'task06-restaurant-b', '${at}', NULL, 2, 'receiver',
      '${at}', '${at}', 'private', 'task06-meal');

  INSERT INTO shared_meal_participants (
    id, shared_meal_id, user_id, visit_id, status, created_at, updated_at
  ) VALUES (
    'task06-participant', 'task06-meal', 'tm_task06_b', 'task06-receiver-visit',
    'accepted', '${at}', '${at}'
  );

  INSERT INTO dining_companions (
    id, owner_user_id, display_name, linked_user_id, created_at, updated_at, deleted_at
  ) VALUES ('task06-companion', 'tm_task06_a', 'Old Friend Name', 'tm_task06_b', '${at}', '${at}', NULL);

  INSERT INTO companion_link_requests (
    id, companion_id, companion_display_name, requester_user_id, target_user_id,
    status, created_at, updated_at
  ) VALUES (
    'task06-link', 'task06-companion', 'Old Friend Name', 'tm_task06_a', 'tm_task06_b',
    'accepted', '${at}', '${at}'
  );
`)

const beforeMeal = database.prepare("SELECT * FROM shared_meals WHERE id = 'task06-meal'").get()
const beforeParticipant = database.prepare("SELECT * FROM shared_meal_participants WHERE id = 'task06-participant'").get()
const beforeLink = database.prepare("SELECT * FROM companion_link_requests WHERE id = 'task06-link'").get()

database.exec(readFileSync(resolve('migrations', '0029_social_collaboration_and_interactions.sql'), 'utf8'))

const meal = database.prepare("SELECT * FROM shared_meals WHERE id = 'task06-meal'").get()
const participant = database.prepare("SELECT * FROM shared_meal_participants WHERE id = 'task06-participant'").get()
const link = database.prepare("SELECT * FROM companion_link_requests WHERE id = 'task06-link'").get()

for (const key of Object.keys(beforeMeal)) assert.equal(meal[key], beforeMeal[key], `shared_meals.${key} changed`)
for (const key of Object.keys(beforeParticipant)) {
  assert.equal(participant[key], beforeParticipant[key], `shared_meal_participants.${key} changed`)
}
for (const key of Object.keys(beforeLink)) assert.equal(link[key], beforeLink[key], `companion_link_requests.${key} changed`)

assert.equal(meal.source_visit_id, 'task06-source-visit')
assert.equal(meal.visibility, 'friends')
assert.equal(meal.server_version, 1)
assert.equal(participant.inviter_user_id, 'tm_task06_a')
assert.equal(participant.visit_id, 'task06-receiver-visit')
assert.equal(participant.server_version, 1)
assert.equal(link.status, 'accepted')
assert.equal(link.server_version, 1)
assert.equal(database.prepare("SELECT restaurant_id FROM visits WHERE id = 'task06-source-visit'").get().restaurant_id,
  'task06-restaurant-a')
assert.equal(database.prepare("SELECT visit_id FROM shared_meal_participants WHERE id = 'task06-participant'").get().visit_id,
  'task06-receiver-visit')

const tables = new Set(database.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all().map((row) => row.name))
assert(tables.has('content_likes'))
assert(tables.has('content_comments'))
const indexes = new Set(database.prepare("SELECT name FROM sqlite_master WHERE type = 'index'").all().map((row) => row.name))
for (const name of [
  'idx_shared_meals_creator_mutation', 'idx_shared_meal_participant_inbox',
  'idx_companion_link_requests_inbox_v1', 'idx_content_likes_active_content',
  'idx_content_comments_active_content',
]) assert(indexes.has(name), `missing ${name}`)
assert.equal(database.prepare('PRAGMA foreign_key_check').all().length, 0)

console.log('Task 06 additive migration preserves legacy Shared Meal, Visit and Companion relationships.')
