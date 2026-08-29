import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import worker from './index'
import {
  buildDevelopmentDemoDataset,
  DEVELOPMENT_DEMO_ADMIN_USER_ID,
  entityMutation,
} from '../scripts/development-demo-data.mjs'

const BASE_URL = 'https://api-dev.tastemap.cn'
const CURRENT_USER = 'tm_development_current_user'
const REFERENCE = '2026-08-29T12:00:00.000Z'

describe('Development demo-data administration', () => {
  it('fails closed outside the exact isolated Development deployment', async () => {
    const database = makeDatabase()
    expect((await call(database, DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data/summary', {
      baseURL: 'https://wrong-development.example',
    })).status).toBe(404)
    expect((await call(database, DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data/summary', {
      environment: 'production',
    })).status).toBe(503)
    expect((await call(database, CURRENT_USER, '/api/v1/development/demo-data/summary')).status).toBe(403)
  })

  it('clears only exact demo and current-manifest records while preserving unrelated data', async () => {
    const database = makeDatabase()
    const dataset = buildDevelopmentDemoDataset({ currentUserID: CURRENT_USER, referenceNow: REFERENCE })
    const currentRestaurant = dataset.currentUser.records.find((record) => record.entityType === 'restaurant')
    const demo = dataset.demoUsers[0]
    const demoRecords = [
      demo.records.find((record) => record.entityType === 'profile'),
      demo.records.find((record) => record.entityType === 'restaurant'),
    ]
    await push(database, CURRENT_USER, [currentRestaurant], dataset.referenceDay)
    await push(database, demo.ownerID, demoRecords, dataset.referenceDay)

    await pushRaw(database, 'unrelated-user', [{
      ...entityMutation(currentRestaurant, dataset.referenceDay),
      mutationId: 'unrelated-restaurant-mutation',
      entityId: 'unrelated-restaurant',
      payload: {
        ...currentRestaurant.payload,
        id: 'unrelated-restaurant', userId: 'unrelated-user',
        placeIdentities: [{
          ...currentRestaurant.payload.placeIdentities[0], externalId: 'unrelated-place',
        }],
      },
    }])

    const request = await json(database, CURRENT_USER, '/api/v1/social/friendships', {
      method: 'POST', body: { targetUserId: demo.ownerID },
    })
    await json(database, demo.ownerID, `/api/v1/social/friendships/${encodeURIComponent(request.friendship.id)}`, {
      method: 'POST', body: { action: 'accept' },
    })

    const before = await json(database, DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data/summary')
    expect(before).toMatchObject({ users: 1, profiles: 1, restaurants: 1, friendships: 1 })

    const result = await json(database, DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data', {
      method: 'DELETE',
      body: {
        currentUserId: CURRENT_USER,
        currentEntities: [{ entityType: currentRestaurant.entityType, entityId: currentRestaurant.entityID }],
      },
    })
    expect(result.after).toMatchObject({ users: 0, profiles: 0, restaurants: 0, friendships: 0, follows: 0 })
    expect(database.get('SELECT id FROM users WHERE id = ?', CURRENT_USER)).toMatchObject({ id: CURRENT_USER })
    expect(database.get('SELECT user_id FROM user_profiles WHERE user_id = ?', CURRENT_USER)).toMatchObject({ user_id: CURRENT_USER })
    expect(database.get('SELECT id FROM restaurants WHERE id = ?', currentRestaurant.entityID)).toBeUndefined()
    expect(database.get("SELECT id FROM restaurants WHERE id = 'unrelated-restaurant'")).toMatchObject({ id: 'unrelated-restaurant' })
    expect(database.get("SELECT id FROM users WHERE id = 'unrelated-user'")).toMatchObject({ id: 'unrelated-user' })
  })

  it('rejects a current-user cleanup manifest that escapes its derived namespace', async () => {
    const database = makeDatabase()
    await call(database, CURRENT_USER, '/api/v1/sync/pull?schemaVersion=1&cursor=0')
    const response = await call(database, DEVELOPMENT_DEMO_ADMIN_USER_ID, '/api/v1/development/demo-data', {
      method: 'DELETE',
      body: {
        currentUserId: CURRENT_USER,
        currentEntities: [{ entityType: 'restaurant', entityId: 'unrelated-restaurant' }],
      },
    })
    expect(response.status).toBe(400)
    await expect(response.json()).resolves.toMatchObject({ error: expect.stringContaining('exact namespace') })
  })
})

async function push(database, userID, records, referenceDay) {
  return pushRaw(database, userID, records.map((record) => entityMutation(record, referenceDay)))
}

async function pushRaw(database, userID, mutations) {
  const result = await json(database, userID, '/api/v1/sync/push', {
    method: 'POST', body: { apiVersion: 1, schemaVersion: 1, mutations },
  })
  expect(result.acknowledgements.every((ack) => ack.status === 'applied')).toBe(true)
  return result
}

async function json(database, userID, path, options = {}) {
  const response = await call(database, userID, path, options)
  const result = await response.json()
  if (!response.ok) throw new Error(`${response.status}: ${JSON.stringify(result)}`)
  return result
}

function call(database, userID, path, {
  method = 'GET', body, baseURL = BASE_URL, environment = 'development',
} = {}) {
  return worker.fetch(new Request(`${baseURL}${path}`, {
    method,
    headers: {
      ...(userID ? { 'X-Taste-Map-Test-User': userID } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), {
    DB: database,
    ASSETS: { fetch: () => new Response('not used') },
    APP_ENVIRONMENT: environment,
    SYNC_AUTH_MODE: 'development-test',
  })
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  for (const migration of migrationFiles()) sqlite.exec(readFileSync(resolve('migrations', migration), 'utf8'))
  return new SQLiteD1Database(sqlite)
}

function migrationFiles() {
  return [
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
    '0027_social_hardening.sql', '0028_restaurant_lists_v1.sql',
  ]
}

class SQLiteD1Database {
  constructor(sqlite) { this.sqlite = sqlite }
  prepare(sql) { return new SQLiteD1Statement(this.sqlite, sql) }
  async batch(statements) {
    this.sqlite.exec('BEGIN IMMEDIATE')
    try {
      const results = statements.map((statement) => statement.batchSync())
      this.sqlite.exec('COMMIT')
      return results
    } catch (error) {
      this.sqlite.exec('ROLLBACK')
      throw error
    }
  }
  get(sql, ...values) { return this.sqlite.prepare(sql).get(...values) }
}

class SQLiteD1Statement {
  constructor(sqlite, sql, values = []) { this.sqlite = sqlite; this.sql = sql; this.values = values }
  bind(...values) { return new SQLiteD1Statement(this.sqlite, this.sql, values) }
  async first() { return this.sqlite.prepare(this.sql).get(...this.values) ?? null }
  async all() { return { results: this.sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} } }
  async run() { return this.runSync() }
  batchSync() {
    if (/^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)) {
      return { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} }
    }
    return this.runSync()
  }
  runSync() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes) } }
  }
}
