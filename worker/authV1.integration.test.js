import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import appleRestaurant from '../contracts/fixtures/restaurant.v1.valid.json'
import worker from './index'
import {
  authenticateAccessToken,
  AuthV1RequestError,
  handleAuthV1Request,
  sha256,
  verifyAppleIdentityToken,
} from './authV1'

const NOW = new Date('2026-08-27T10:00:00.000Z')
const AUDIENCE = 'com.lafayette.tastemap'

describe('Native Auth V1', () => {
  it('verifies Apple signature, issuer, audience, expiration, and nonce', async () => {
    const signing = await appleSigningFixture()
    const valid = await signing.token()
    await expect(verifyAppleIdentityToken(valid, [AUDIENCE], 'expected-nonce', NOW, signing.jwks))
      .resolves.toMatchObject({ sub: 'apple-subject-a' })

    await expect(verifying(signing, { iss: 'https://attacker.example' }))
      .rejects.toMatchObject({ code: 'invalid_apple_issuer' })
    await expect(verifying(signing, { aud: 'wrong.bundle' }))
      .rejects.toMatchObject({ code: 'invalid_apple_audience' })
    await expect(verifying(signing, { exp: Math.floor(NOW.getTime() / 1000) - 1 }))
      .rejects.toMatchObject({ code: 'expired_apple_token' })
    await expect(verifying(signing, { nonce: 'wrong-nonce' }))
      .rejects.toMatchObject({ code: 'invalid_apple_nonce' })
  })

  it('exchanges Apple identity once and keeps Apple sub outside business ownership', async () => {
    const database = makeDatabase()
    const first = await exchange(database, 'apple-token-one', 'apple-subject-a')
    expect(first.user.id).toMatch(/^tm_[A-Za-z0-9_-]+$/)
    expect(first.user.id).not.toBe('apple-subject-a')
    expect(database.get("SELECT provider_subject, user_id FROM auth_identities WHERE provider = 'apple'"))
      .toMatchObject({ provider_subject: 'apple-subject-a', user_id: first.user.id })
    expect(database.get('SELECT auth_subject FROM users WHERE id = ?', first.user.id).auth_subject).toBeNull()
    const storedSession = database.get('SELECT access_token_hash, refresh_token_hash FROM auth_sessions')
    expect(storedSession.access_token_hash).not.toBe(first.session.accessToken)
    expect(storedSession.refresh_token_hash).not.toBe(first.session.refreshToken)
    expect(database.get('SELECT token_hash FROM auth_identity_token_uses').token_hash).not.toBe('apple-token-one')

    await expect(exchange(database, 'apple-token-one', 'apple-subject-a'))
      .rejects.toMatchObject({ code: 'identity_token_replay' })
  })

  it('uses access tokens for sync and isolates user A from user B', async () => {
    const database = makeDatabase()
    const userA = await exchange(database, 'apple-token-a', 'apple-subject-a')
    const userB = await exchange(database, 'apple-token-b', 'apple-subject-b')
    const restaurant = { ...appleRestaurant, id: 'auth-restaurant-a', userId: userB.user.id }
    const create = mutation('auth-create-a', restaurant.id, 0, restaurant)

    const pushA = await sync(database, userA.session.accessToken, '/api/v1/sync/push', 'POST', {
      apiVersion: 1, schemaVersion: 1, mutations: [create],
    })
    expect(pushA.status).toBe(200)
    expect(database.get('SELECT user_id FROM restaurants WHERE id = ?', restaurant.id).user_id).toBe(userA.user.id)

    const pullB = await sync(database, userB.session.accessToken, '/api/v1/sync/pull?schemaVersion=1&cursor=0', 'GET')
    expect((await pullB.json()).restaurants).toEqual([])

    const takeover = await sync(database, userB.session.accessToken, '/api/v1/sync/push', 'POST', {
      apiVersion: 1, schemaVersion: 1,
      mutations: [mutation('auth-takeover-b', restaurant.id, 1, restaurant)],
    })
    expect(takeover.status).toBe(403)
  })

  it('expires access, rotates refresh, detects reuse, and revokes logout', async () => {
    const database = makeDatabase()
    const initial = await exchange(database, 'apple-token-session', 'apple-session-subject')
    const authenticated = await authenticateAccessToken(bearerRequest(initial.session.accessToken), database, NOW)
    expect(authenticated?.id).toBe(initial.user.id)

    await expect(authenticateAccessToken(
      bearerRequest(initial.session.accessToken), database, new Date(NOW.getTime() + 16 * 60 * 1000),
    )).rejects.toMatchObject({ code: 'invalid_access_token' })

    const rotated = await auth(database, '/api/v1/auth/refresh', {
      apiVersion: 1, refreshToken: initial.session.refreshToken,
    }, new Date(NOW.getTime() + 60_000))
    expect(rotated.session.refreshToken).not.toBe(initial.session.refreshToken)
    expect(database.get('SELECT refresh_generation FROM auth_sessions').refresh_generation).toBe(1)

    await expect(auth(database, '/api/v1/auth/refresh', {
      apiVersion: 1, refreshToken: initial.session.refreshToken,
    }, new Date(NOW.getTime() + 120_000))).rejects.toMatchObject({ code: 'refresh_token_reuse' })
    await expect(authenticateAccessToken(bearerRequest(rotated.session.accessToken), database, NOW))
      .rejects.toMatchObject({ code: 'invalid_access_token' })

    const fresh = await exchange(database, 'apple-token-logout', 'apple-session-subject')
    await handleAuthV1Request(new Request('https://dev.test/api/v1/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${fresh.session.accessToken}` },
      body: JSON.stringify({ apiVersion: 1, refreshToken: fresh.session.refreshToken }),
    }), environment(database), { now: () => NOW })
    await expect(authenticateAccessToken(bearerRequest(fresh.session.accessToken), database, NOW))
      .rejects.toMatchObject({ code: 'invalid_access_token' })
  })

  it('never enables the Development identity header in Production', async () => {
    const response = await worker.fetch(new Request(
      'https://api.example.test/api/v1/sync/pull?schemaVersion=1&cursor=0',
      { headers: { 'X-Taste-Map-Test-User': 'forged-user' } },
    ), {
      ...environment(makeDatabase()), APP_ENVIRONMENT: 'production', SYNC_AUTH_MODE: 'development-test',
      ASSETS: { fetch: () => new Response('not used') },
    })
    expect(response.status).toBe(503)
  })
})

async function verifying(signing, overrides) {
  const token = await signing.token(overrides)
  return verifyAppleIdentityToken(token, [AUDIENCE], 'expected-nonce', NOW, signing.jwks)
}

async function appleSigningFixture() {
  const keyPair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  )
  const publicJWK = await crypto.subtle.exportKey('jwk', keyPair.publicKey)
  publicJWK.kid = 'test-apple-key'
  publicJWK.alg = 'RS256'
  return {
    jwks: { keys: [publicJWK] },
    async token(overrides = {}) {
      const header = base64url(JSON.stringify({ alg: 'RS256', kid: publicJWK.kid }))
      const payload = base64url(JSON.stringify({
        iss: 'https://appleid.apple.com', aud: AUDIENCE,
        exp: Math.floor(NOW.getTime() / 1000) + 600, iat: Math.floor(NOW.getTime() / 1000) - 5,
        sub: 'apple-subject-a', nonce: 'expected-nonce', ...overrides,
      }))
      const input = `${header}.${payload}`
      const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keyPair.privateKey, new TextEncoder().encode(input))
      return `${input}.${base64url(new Uint8Array(signature))}`
    },
  }
}

async function exchange(database, identityToken, subject) {
  const challenge = await handleAuthV1Request(
    new Request('https://dev.test/api/v1/auth/challenge', { method: 'POST' }),
    environment(database), { now: () => NOW },
  )
  return handleAuthV1Request(new Request('https://dev.test/api/v1/auth/apple/exchange', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiVersion: 1, identityToken, state: challenge.state, nonce: challenge.nonce }),
  }), environment(database), {
    now: () => NOW,
    verifyAppleToken: async (_token, audiences, expectedNonce) => {
      expect(audiences).toEqual([AUDIENCE])
      expect(expectedNonce).toBe(await sha256(challenge.nonce))
      return {
        iss: 'https://appleid.apple.com', aud: AUDIENCE,
        exp: Math.floor(NOW.getTime() / 1000) + 600,
        sub: subject, nonce: expectedNonce, email: `${subject}@privaterelay.appleid.com`,
      }
    },
  })
}

async function auth(database, path, body, now) {
  return handleAuthV1Request(new Request(`https://dev.test${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }), environment(database), { now: () => now })
}

function sync(database, token, path, method, body) {
  return worker.fetch(new Request(`https://dev.test${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), { ...environment(database), APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test', ASSETS: { fetch: () => new Response('not used') } })
}

function bearerRequest(token) {
  return new Request('https://dev.test/api/v1/sync/pull', { headers: { Authorization: `Bearer ${token}` } })
}

function environment(database) {
  return { DB: database, APPLE_CLIENT_IDS: AUDIENCE }
}

function mutation(mutationId, entityId, baseVersion, payload) {
  return { mutationId, entityType: 'restaurant', entityId, operation: 'upsert', baseVersion, clientTimestamp: payload.updatedAt, payload }
}

function base64url(value) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  return Buffer.from(bytes).toString('base64url')
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
    '0016_sync_v1.sql', '0017_native_auth.sql',
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
