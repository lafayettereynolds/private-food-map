import { DatabaseSync } from 'node:sqlite'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import worker, { readEffectiveMembership } from './index'
import { sha256 } from './authV1'
import { applyAllMigrations } from './testSupport/migrations.js'

const NOW = new Date('2028-02-29T12:34:56.789Z')
let sqlite, db
beforeEach(async () => {
  vi.useFakeTimers(); vi.setSystemTime(NOW)
  sqlite = new DatabaseSync(':memory:'); sqlite.exec('PRAGMA foreign_keys=ON'); applyAllMigrations(sqlite)
  db = { prepare: sql => statement(sql) }
  for (const id of ['admin', 'a', 'b']) {
    sqlite.prepare("INSERT INTO users (id, nickname, auth_provider, created_at, updated_at) VALUES (?, ?, 'apple', ?, ?)").run(id,id,NOW.toISOString(),NOW.toISOString())
    sqlite.prepare(`INSERT INTO auth_sessions (id,user_id,access_token_hash,access_expires_at,refresh_token_hash,refresh_expires_at,created_at,updated_at,last_used_at)
      VALUES (?,?,?,'2099-01-01T00:00:00Z',?,'2099-01-01T00:00:00Z',?,?,?)`)
      .run(id,id,await sha256('tm_access_testing_long_enough_'+id),'refresh-'+id,NOW.toISOString(),NOW.toISOString(),NOW.toISOString())
  }
})
afterEach(() => { sqlite.close(); vi.useRealTimers() })
function statement(sql, values=[]) { return {
  bind: (...v)=>statement(sql,v), first: async()=>sqlite.prepare(sql).get(...values)??null,
  all: async()=>({results:sqlite.prepare(sql).all(...values)}),
  run: async()=>({meta:{changes:Number(sqlite.prepare(sql).run(...values).changes)}}),
} }
async function request(body, actor='admin', path='/api/v1/admin/memberships', extra={}) {
  return worker.fetch(new Request('https://api.test'+path, {method:body?'POST':'GET', headers:{Authorization:'Bearer tm_access_testing_long_enough_'+actor,'Content-Type':'application/json',...extra},...(body?{body:JSON.stringify(body)}:{})}),
    { DB:db, APP_ENVIRONMENT:'production', MEMBERSHIP_ADMIN_USER_IDS:'admin', ASSETS:{fetch:()=>new Response('unused')} })
}
async function mutate(body) { const response=await request(body); expect(response.status).toBe(200); return (await response.json()).entitlement }
const gift = (source='gift_annual',userId='a') => mutate({action:'grant',source,userId,note:'开发者感谢赠送'})
const audits = () => sqlite.prepare('SELECT * FROM membership_audit_log ORDER BY rowid').all()
function subscription(){ sqlite.prepare(`INSERT INTO membership_entitlements (id,user_id,source,starts_at,expires_at,is_lifetime,status,created_at,updated_at)
 VALUES ('apple-a','a','app_store_annual',?,'2035-01-01T00:00:00Z',0,'active',?,?)`).run(NOW.toISOString(),NOW.toISOString(),NOW.toISOString()) }

describe('Premium gifts through authenticated production routes', () => {
  it('grants a calendar year including leap-day clamping with complete atomic audit', async()=>{
    const e=await gift(); expect(e).toMatchObject({isPremium:true,source:'gift_annual',startedAt:NOW.toISOString(),expiresAt:'2029-02-28T12:34:56.789Z'})
    expect(JSON.parse(audits()[0].after_json)).toEqual({userID:'a',source:'gift_annual',startedAt:NOW.toISOString(),grantedAt:NOW.toISOString(),expiresAt:e.expiresAt,grantedBy:'admin',note:'开发者感谢赠送',revokedAt:null})
    const own=await request(null,'a','/api/v1/me/entitlements?userId=b'); expect((await own.json()).entitlement.source).toBe('gift_annual')
    vi.setSystemTime(new Date(e.expiresAt)); expect((await readEffectiveMembership(db,'a')).isPremium).toBe(false)
  })
  it('lifetime needs no StoreKit transaction and cannot leak from A to B',async()=>{
    await gift('gift_lifetime'); vi.setSystemTime(new Date('2080-01-01T00:00:00Z'))
    for(const actor of ['a','b','a']) { const r=await request(null,actor,'/api/v1/me/entitlements'); const data=await r.json();expect(data.userId).toBe(actor);expect(data.entitlement.isPremium).toBe(actor==='a');if(actor==='a')expect(data.entitlement).toMatchObject({source:'gift_lifetime',expiresAt:null}) }
    expect(sqlite.prepare('SELECT COUNT(*) n FROM app_store_transactions').get().n).toBe(0)
  })
  it('uses lifetime gift > annual gift > subscription and falls back after revoke',async()=>{
    subscription(); const annual=await gift(); const lifetime=await gift('gift_lifetime')
    expect(lifetime.source).toBe('gift_lifetime')
    const lifeID=lifetime.entitlements.find(x=>x.source==='gift_lifetime').id
    expect((await mutate({action:'revoke',entitlementId:lifeID})).source).toBe('gift_annual')
    expect((await mutate({action:'revoke',entitlementId:annual.entitlements.find(x=>x.source==='gift_annual').id})).source).toBe('app_store_annual')
    expect(audits().map(x=>x.action)).toEqual(['grant','grant','revoke','revoke'])
    expect(JSON.parse(audits()[2].after_json).revokedAt).toBe(NOW.toISOString())
    expect((await request({action:'revoke',entitlementId:'apple-a'})).status).toBe(404)
  })
  it('revokes a gift-only user to free immediately',async()=>{
    const e=await gift('gift_lifetime');expect((await mutate({action:'revoke',entitlementId:e.entitlements[0].id})).isPremium).toBe(false)
    expect((await request({action:'extend',entitlementId:e.entitlements[0].id})).status).toBe(404)
  })
  it('extends from max(now, expiry), preserves grant facts and audits notes',async()=>{
    const e=await gift(); const id=e.entitlements[0].id
    expect((await mutate({action:'extend',entitlementId:id,note:'延期'})).expiresAt).toBe('2030-02-28T12:34:56.789Z')
    vi.setSystemTime(new Date('2031-03-01T00:00:00.000Z'))
    const next=await mutate({action:'extend',entitlementId:id}); expect(next.expiresAt).toBe('2032-03-01T00:00:00.000Z');expect(next.startedAt).toBe(NOW.toISOString())
    await mutate({action:'note',entitlementId:id,note:'新的备注'})
    expect(audits().map(x=>x.action)).toEqual(['grant','extend','extend','note'])
    expect(JSON.parse(audits()[3].after_json)).toMatchObject({grantedBy:'admin',grantedAt:NOW.toISOString(),note:'新的备注'})
  })
  it('rejects unauthorized, forged Access headers, unsupported durations and nonexistent users',async()=>{
    for(const actor of ['b','unknown']) expect((await request({action:'grant',source:'gift_lifetime',userId:'a'},actor)).status).toBe(actor==='b'?403:401)
    expect((await request(null,'unknown','/api/admin/memberships',{'Cf-Access-Authenticated-User-Email':'admin@example.com','Cf-Access-Jwt-Assertion':'fake','X-Taste-Map-Test-User':'admin'})).status).toBe(401)
    expect((await request({action:'grant',duration:'1m',userId:'a'})).status).toBe(400)
    expect((await request({action:'grant',source:'gift_annual',userId:'missing'})).status).toBe(404)
    expect(audits()).toHaveLength(0)
  })
  it('searches exact userID and rejects extending lifetime or changing Gift through legacy update',async()=>{
    const list=await request(null,'admin','/api/v1/admin/memberships?q=a');expect((await list.json()).users.some(u=>u.id==='a')).toBe(true)
    const e=await gift('gift_lifetime'); const id=e.entitlements[0].id
    expect((await request({action:'extend',entitlementId:id})).status).toBe(400)
    expect((await request({action:'update',entitlementId:id,isLifetime:false})).status).toBe(404)
  })
  it('rolls back granting if audit insertion fails',async()=>{
    sqlite.exec("CREATE TRIGGER reject_audit BEFORE INSERT ON membership_audit_log BEGIN SELECT RAISE(ABORT,'audit unavailable'); END")
    expect((await request({action:'grant',source:'gift_lifetime',userId:'a'})).status).toBe(500)
    expect((await readEffectiveMembership(db,'a')).isPremium).toBe(false)
    expect(audits()).toHaveLength(0)
  })
})
