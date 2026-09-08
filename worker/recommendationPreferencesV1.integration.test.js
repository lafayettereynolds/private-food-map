import { DatabaseSync } from 'node:sqlite'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import worker from './index'
import { handleRecommendationPreferencesV1 } from './recommendationPreferencesV1'
import { applyAllMigrations } from './testSupport/migrations.js'

const root = '/api/v1/recommendation-preferences/'
const sample = (eventID = 'event-a', aliases = ['AMAP:A']) => ({ eventID, aliases, source: 'explicit_dismissal', occurredAt: '2026-09-07T08:00:00.000Z', intent: null })
describe('Private recommendation preference sync V1', () => {
  let db
  beforeEach(async () => {
    db = new SQLiteD1Database()
    for (const owner of ['tm_a', 'tm_b']) expect((await api(db, owner, `${root}pull?apiVersion=1`)).status).toBe(200)
  })
  afterEach(() => db.sqlite.close())

  it('stores owner-private append facts and never permits body/query account selection', async () => {
    const ack = await pushed(db, 'tm_a', [sample()])
    expect(ack).toMatchObject({ apiVersion: 1, ownerID: 'tm_a', receipts: [{ eventID: 'event-a' }] })
    expect((await pulled(db, 'tm_a')).events[0]).toMatchObject({ aliases: ['amap:a'], revision: ack.receipts[0].revision, intent: null })
    expect((await pulled(db, 'tm_b')).events).toEqual([])
    for (const ownerField of ['ownerID', 'userId']) {
      expect((await api(db, 'tm_a', `${root}push`, 'POST', { apiVersion: 1, events: [sample()], [ownerField]: 'tm_b' })).status).toBe(400)
      expect((await api(db, 'tm_a', `${root}pull?apiVersion=1&${ownerField}=tm_b`)).status).toBe(400)
    }
    expect((await api(db, '', `${root}pull?apiVersion=1`)).status).toBe(401)
    expect((await api(db, '', `${root}push`, 'POST', { apiVersion: 1, events: [sample()] })).status).toBe(401)
  })

  it('rejects production test headers instead of creating a private preference identity', async () => {
    const response = await worker.fetch(new Request(`https://api.example.test${root}pull?apiVersion=1`, {
      headers: { 'X-Taste-Map-Test-User': 'tm_a' },
    }), { DB: db, PHOTO_STORAGE: {list: async()=>({objects:[],truncated:false}),delete:async()=>{}}, ASSETS: { fetch: () => new Response() }, APP_ENVIRONMENT: 'production', SYNC_AUTH_MODE: 'cloudflare-access' })
    expect(response.status).toBe(401)
  })

  it('checks expected owner against authentication before a queued upload can cross an account switch', async () => {
    const response = await worker.fetch(new Request(`https://development.example.test${root}push`, {
      method: 'POST', headers: { 'X-Taste-Map-Test-User': 'tm_b', 'X-Taste-Map-Preference-Owner': 'tm_a', 'Content-Type': 'application/json' },
      body: JSON.stringify({ apiVersion: 1, events: [sample()] }),
    }), { DB: db, PHOTO_STORAGE: {list: async()=>({objects:[],truncated:false}),delete:async()=>{}}, ASSETS: { fetch: () => new Response() }, APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test' })
    expect(response.status).toBe(409)
    expect(await response.json()).toMatchObject({ code: 'account_changed' })
    expect((await pulled(db, 'tm_b')).events).toEqual([])
  })

  it('replays canonical-equivalent events idempotently, including concurrent requests', async () => {
    const first = await pushed(db, 'tm_a', [sample('same', ['b', 'AMAP:A'])])
    const second = await pushed(db, 'tm_a', [sample('same', ['amap:a', 'b', 'b'])])
    expect(second).toEqual(first)
    const concurrent = await Promise.all(Array.from({ length: 3 }, () => pushed(db, 'tm_a', [sample('racing')])) )
    expect(concurrent[1]).toEqual(concurrent[0])
    expect((await pulled(db, 'tm_a')).events).toHaveLength(2)
    expect((await pushed(db, 'tm_b', [sample('same')])).ownerID).toBe('tm_b')
  })

  it('rejects same ID with changed content and atomically rolls back other new events in the batch', async () => {
    await pushed(db, 'tm_a', [sample('same')])
    const response = await api(db, 'tm_a', `${root}push`, 'POST', { apiVersion: 1, events: [sample('new'), sample('same', ['different'])] })
    expect(response.status).toBe(409)
    expect(await response.json()).toMatchObject({ code: 'idempotency_conflict' })
    expect((await pulled(db, 'tm_a')).events.map(event => event.eventID)).toEqual(['same'])
    expect(() => db.sqlite.prepare("UPDATE recommendation_preference_events SET payload_json = '{}' WHERE event_id = 'same'").run()).toThrow(/immutable/)
  })

  it('retains both devices additions and checkpoint pulls later arrivals without whole-snapshot replacement', async () => {
    const initial = await pulled(db, 'tm_a')
    await pushed(db, 'tm_a', [sample('device-a'), sample('device-b', ['amap:b']), sample('device-c', ['amap:c'])])
    let page = await pulled(db, 'tm_a', initial.cursor, 2)
    expect(page.events.map(event => event.eventID)).toEqual(['device-a', 'device-b'])
    expect(page.hasMore).toBe(true)
    const firstCursor = page.cursor
    await pushed(db, 'tm_a', [sample('late', ['amap:d'])])
    page = await pulled(db, 'tm_a', firstCursor, 2)
    expect(page.events.map(event => event.eventID)).toEqual(['device-c', 'late'])
    expect(page.hasMore).toBe(false)
    const empty = await pulled(db, 'tm_a', page.cursor)
    expect(empty).toMatchObject({ events: [], hasMore: false, cursor: page.cursor })
    expect((await pulled(db, 'tm_a')).events).toHaveLength(4)
  })

  it('rejects cross-account, legacy, malformed, future and non-owner revision cursors', async () => {
    await pushed(db, 'tm_a', [sample()])
    await pushed(db, 'tm_b', [sample()])
    const page = await pulled(db, 'tm_a')
    for (const cursor of [page.cursor, '0', '', 'rp1.bad']) {
      expect((await api(db, 'tm_b', `${root}pull?apiVersion=1&cursor=${encodeURIComponent(cursor)}`)).status).toBe(400)
    }
    const decoded = JSON.parse(atob(page.cursor.slice(4).replace(/-/g, '+').replace(/_/g, '/')))
    for (const revision of [999999, (await pulled(db, 'tm_b')).events[0].revision]) {
      const forged = `rp1.${btoa(JSON.stringify([1, decoded[1], revision])).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`
      expect((await api(db, 'tm_a', `${root}pull?apiVersion=1&cursor=${forged}`)).status).toBe(400)
    }
  })

  it('accepts the bounded 100-event batch and rejects oversized or unsupported wire input without a write', async () => {
    expect((await pushed(db, 'tm_a', Array.from({ length: 100 }, (_, i) => sample(`e-${i}`)))).receipts).toHaveLength(100)
    for (const query of ['apiVersion=2', 'apiVersion=1&limit=101', 'apiVersion=1&limit=0', 'apiVersion=1&limit=1&limit=2', 'limit=1']) {
      expect((await api(db, 'tm_a', `${root}pull?${query}`)).status).toBe(400)
    }
    const oversized = await api(db, 'tm_a', `${root}push`, 'POST', { apiVersion: 1, events: [sample()], padding: 'x'.repeat(132000) })
    expect(oversized.status).toBe(413)
    expect(db.get("SELECT COUNT(*) AS count FROM recommendation_preference_events WHERE user_id = 'tm_a'").count).toBe(100)
  })

  it('preserves legacy exclusions without fabricated dates or learning, and existing legacy intent separately', async () => {
    await pushed(db, 'tm_a', [
      { ...sample('old'), source: 'legacy_exclusion', occurredAt: null },
      { ...sample('old-vote'), source: 'legacy_intent', occurredAt: null, intent: { classifierVersion: 1, brandID: 'kfc', context: 'everyday_fast_food' } },
    ])
    expect((await pulled(db, 'tm_a')).events).toMatchObject([
      { eventID: 'old', source: 'legacy_exclusion', occurredAt: null, intent: null },
      { eventID: 'old-vote', source: 'legacy_intent', occurredAt: null, intent: { brandID: 'kfc' } },
    ])
  })

  it('does not require a saved Restaurant or cancel an exclusion when a Restaurant is removed', async () => {
    await pushed(db, 'tm_a', [sample('unsaved', ['apple:never-saved'])])
    db.sqlite.prepare("DELETE FROM restaurants WHERE user_id = 'tm_a'").run()
    expect((await pulled(db, 'tm_a')).events[0].aliases).toEqual(['apple:never-saved'])
  })

  it('account deletion removes only that owner events and old queued writes cannot resurrect them', async () => {
    await pushed(db, 'tm_a', [sample()])
    await pushed(db, 'tm_b', [sample()])
    const deleted = await api(db, 'tm_a', '/api/v1/account-deletion/confirm', 'POST', {
      apiVersion: 1, requestId: crypto.randomUUID(), statusToken: `tm_delete_${'p'.repeat(48)}`, confirmation: 'DELETE',
    })
    expect(await deleted.json()).toMatchObject({ status: 'completed' })
    expect(db.get("SELECT COUNT(*) AS count FROM recommendation_preference_events WHERE user_id = 'tm_a'").count).toBe(0)
    expect((await pulled(db, 'tm_b')).events).toHaveLength(1)
    expect((await api(db, 'tm_a', `${root}push`, 'POST', { apiVersion: 1, events: [sample()] })).status).toBe(401)
    await expect(handleRecommendationPreferencesV1(new Request(`https://test${root}pull?apiVersion=1`), db, 'tm_a')).rejects.toMatchObject({ status: 403, code: 'account_unavailable' })
  })

  it('denies reads and inserts as soon as account deletion starts, including the write-transaction race', async () => {
    const insertJob = () => db.sqlite.prepare(`INSERT INTO account_deletion_jobs
      (id, user_id, request_id, request_fingerprint, status_token_hash, status, requested_at, updated_at)
      VALUES ('delete-a', 'tm_a', 'request-a', 'hash', 'token', 'confirmed', ?, ?)`)
      .run(new Date().toISOString(), new Date().toISOString())
    db.beforeBatch = insertJob
    const response = await api(db, 'tm_a', `${root}push`, 'POST', { apiVersion: 1, events: [sample()] })
    expect(response.status).toBe(403)
    expect(await response.json()).toMatchObject({ code: 'account_unavailable' })
    expect(db.get('SELECT COUNT(*) AS count FROM recommendation_preference_events').count).toBe(0)
    expect((await api(db, 'tm_a', `${root}pull?apiVersion=1`)).status).toBe(403)
  })

  it('does not disguise missing migration or storage errors as an empty preference snapshot', async () => {
    db.sqlite.exec('DROP TABLE recommendation_preference_events')
    const response = await api(db, 'tm_a', `${root}pull?apiVersion=1`)
    expect(response.status).toBe(503)
    expect(await response.json()).toMatchObject({ code: 'preference_storage_unavailable' })
  })
})

async function pushed(db, owner, events) { return json(await api(db, owner, `${root}push`, 'POST', { apiVersion: 1, events })) }
async function pulled(db, owner, cursor, limit) {
  return json(await api(db, owner, `${root}pull?apiVersion=1${cursor === undefined ? '' : `&cursor=${encodeURIComponent(cursor)}`}${limit ? `&limit=${limit}` : ''}`))
}
async function json(response) { const value = await response.json(); expect(response.status, JSON.stringify(value)).toBe(200); return value }
function api(db, owner, path, method = 'GET', body) {
  const headers = new Headers({ 'Content-Type': 'application/json' })
  if (owner) headers.set('X-Taste-Map-Test-User', owner)
  if (owner && path === `${root}push`) headers.set('X-Taste-Map-Preference-Owner', owner)
  return worker.fetch(new Request(`https://development.example.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }), {
    DB: db, PHOTO_STORAGE: {list: async()=>({objects:[],truncated:false}),delete:async()=>{}}, ASSETS: { fetch: () => new Response() }, APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test',
  })
}
class SQLiteD1Database {
  constructor() { this.sqlite = new DatabaseSync(':memory:'); this.sqlite.exec('PRAGMA foreign_keys = ON;'); applyAllMigrations(this.sqlite) }
  prepare(sql) { return new SQLiteD1Statement(this.sqlite, sql) }
  async batch(statements) {
    if (this.beforeBatch) { const run = this.beforeBatch; this.beforeBatch = null; run() }
    this.sqlite.exec('BEGIN IMMEDIATE')
    try { const results = statements.map(statement => statement.batchSync()); this.sqlite.exec('COMMIT'); return results }
    catch (error) { this.sqlite.exec('ROLLBACK'); throw error }
  }
  get(sql, ...values) { return this.sqlite.prepare(sql).get(...values) }
}
class SQLiteD1Statement {
  constructor(sqlite, sql, values = []) { this.sqlite = sqlite; this.sql = sql; this.values = values }
  bind(...values) { if (values.length > 100) throw new Error('D1 bind limit'); return new SQLiteD1Statement(this.sqlite, this.sql, values) }
  async first() { return this.sqlite.prepare(this.sql).get(...this.values) ?? null }
  async all() { return { results: this.sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} } }
  async run() { return this.runSync() }
  batchSync() { return /^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql) ? { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} } : this.runSync() }
  runSync() { const result = this.sqlite.prepare(this.sql).run(...this.values); return { success: true, results: [], meta: { changes: Number(result.changes) } } }
}
