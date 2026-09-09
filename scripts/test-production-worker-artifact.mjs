// Local-only compiled-artifact regression. Never connects to a remote service.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { createHash } from 'node:crypto'
import { DatabaseSync } from 'node:sqlite'
import { applyAllMigrations } from '../worker/testSupport/migrations.js'

const [candidatePath, baselinePath, developmentPath] = process.argv.slice(2).map(p => path.resolve(p))
assert(candidatePath && baselinePath, 'Pass candidate and pre-isolation bundle paths')
const source = fs.readFileSync(candidatePath, 'utf8')
const forbidden = [
  'tm_demo_v2', 'free-tester', 'local-premium-owner', 'X-Taste-Map-Test-User',
  '/api/v1/development/demo-data', 'api-dev.tastemap.cn',
  'ensureDevelopmentSyncUser', 'handleDevelopmentDemoAdminV1',
  '.private/', 'tm_access_fixture',
]
for (const marker of forbidden) assert(!source.includes(marker), 'Forbidden artifact marker: ' + marker)
// PEM delimiters in the official server-side key parser are required code;
// a delimiter followed by actual encoded key material is forbidden.
assert(!/-----BEGIN (?:EC |RSA )?PRIVATE KEY-----[\s\\n]*[A-Za-z0-9+/]{40}/.test(source), 'Embedded private key material')
// Localhost literals are permitted only in the existing private-host rejection
// function. Actual compiled route tests below prove they cannot grant identity.
assert(source.includes('metadata.google.internal'), 'SSRF host protection must remain')
const candidates = [
  (await import(pathToFileURL(candidatePath))).default,
  (await import(pathToFileURL(baselinePath))).default,
]
globalThis.fetch = async () => { throw new Error('Network is forbidden in artifact tests') }
const hash = value => createHash('sha256').update(value).digest('hex')
class Statement {
  constructor(db, sql, args = []) { Object.assign(this, { db, sql, args }) }
  bind(...args) { return new Statement(this.db, this.sql, args) }
  async first() { return this.db.prepare(this.sql).get(...this.args) ?? null }
  async all() { return { success: true, results: this.db.prepare(this.sql).all(...this.args), meta: {} } }
  async run() { return { success: true, results: [], meta: { changes: Number(this.db.prepare(this.sql).run(...this.args).changes) } } }
}
function database() {
  const db = new DatabaseSync(':memory:')
  db.exec('PRAGMA foreign_keys=ON')
  applyAllMigrations(db)
  const now = new Date().toISOString(), future = new Date(Date.now() + 3600000).toISOString()
  for (const id of ['artifact_a', 'artifact_b']) {
    db.prepare("INSERT INTO users (id,nickname,bio,city,created_at,updated_at) VALUES (?,?,'','',?,?)").run(id,id,now,now)
    db.prepare(`INSERT INTO auth_sessions (id,user_id,access_token_hash,access_expires_at,
      refresh_token_hash,refresh_expires_at,created_at,updated_at,last_used_at)
      VALUES (?,?,?,?,?,?,?,?,?)`).run(id,id,hash('tm_access_' + id.repeat(4)),future,
        hash('tm_refresh_' + id.repeat(4)),future,now,now,now)
  }
  return { raw: db, prepare: sql => new Statement(db, sql), batch: statements => Promise.all(statements.map(s => s.run())) }
}
const cases = [
  ['/health', 'GET', {}, undefined, 200],
  ['/api/v1/sync/pull', 'GET', {}, undefined, 401],
  ['/api/v1/photos/00000000-0000-4000-8000-000000000000/content', 'DELETE', {}, undefined, 401],
  ['/api/v1/discovery/feed', 'GET', {}, undefined, 401],
  ['/api/v1/account-deletion/preview', 'GET', {}, undefined, 401],
  ['/api/v1/me/entitlements', 'GET', { 'X-Taste-Map-Test-User': 'owner' }, undefined, 401],
  ['/api/v1/sync/pull', 'GET', { Authorization: 'Bearer malformed' }, undefined, 401],
  ['/api/v1/admin/memberships', 'GET', { 'Cf-Access-Authenticated-User-Email': 'admin@example.test', 'Cf-Access-Jwt-Assertion': 'forged' }, undefined, 401],
  ['/api/v1/storekit/notifications', 'POST', {}, { signedPayload: 'invalid' }, 400],
  ['/api/v1/auth/refresh', 'POST', {}, { apiVersion: 1, refreshToken: 'invalid' }, 401],
]
let passed = 0
for (const [route, method, headers, body, expected] of cases) {
  const outputs = []
  for (const worker of candidates) {
    const DB = database()
    const response = await worker.fetch(new Request('https://api.tastemap.cn' + route, {
      method, headers: { 'Content-Type': 'application/json', ...headers },
      ...(body ? { body: JSON.stringify(body) } : {}),
    }), { APP_ENVIRONMENT: 'production', SYNC_AUTH_MODE: 'cloudflare-access', DB })
    assert.equal(response.status, expected, route)
    outputs.push(await response.json())
    DB.raw.close()
  }
  assert.deepEqual(outputs[0], outputs[1], 'Production contract changed: ' + route)
  passed++
}
for (const worker of candidates) {
  const DB = database()
  const env = { APP_ENVIRONMENT: 'production', SYNC_AUTH_MODE: 'cloudflare-access', DB }
  const request = route => new Request('https://api.tastemap.cn' + route, {
    headers: { Authorization: 'Bearer tm_access_' + 'artifact_a'.repeat(4) },
  })
  const member = await worker.fetch(request('/api/v1/me/entitlements'), env)
  assert.equal(member.status, 200)
  const payload = await member.json()
  assert.equal(payload.userId, 'artifact_a')
  assert.equal(payload.entitlement.isPremium, false)
  const admin = await worker.fetch(request('/api/v1/admin/memberships'), env)
  assert.equal(admin.status, 403)
  DB.raw.prepare("UPDATE auth_sessions SET revoked_at=? WHERE id='artifact_a'").run(new Date().toISOString())
  assert.equal((await worker.fetch(request('/api/v1/me/entitlements'), env)).status, 401)
  assert.equal(DB.raw.prepare("SELECT revoked_at FROM auth_sessions WHERE id='artifact_b'").get().revoked_at, null)
  DB.raw.close()
  passed += 4
}
if (developmentPath) {
  const devSource = fs.readFileSync(developmentPath, 'utf8')
  for (const marker of ['tm_demo_v2', 'free-tester', 'local-premium-owner', '/api/v1/development/demo-data'])
    assert(devSource.includes(marker), 'Development capability removed: ' + marker)
  const dev = (await import(pathToFileURL(developmentPath))).default
  const DB = database()
  for (const [identity, premium] of [['owner', true], ['free-tester', false]]) {
    const response = await dev.fetch(new Request('http://localhost/api/v1/me/entitlements', {
      headers: { 'X-Taste-Map-Test-User': identity },
    }), { APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test', DB })
    assert.equal(response.status, 200)
    assert.equal((await response.json()).entitlement.isPremium, premium)
    passed++
  }
  DB.raw.close()
}
console.log(JSON.stringify({ artifactPurity: 'PASS', differentialChecks: passed, remoteRequests: 0,
  sha256: hash(source), productionAuthBehaviorChanged: false }))
