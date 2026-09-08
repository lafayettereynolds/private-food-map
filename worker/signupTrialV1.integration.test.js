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

describe('Signup trial through authenticated production routes', () => {
  const eligible = (actor='a', extra={}) => request(null,actor,'/api/v1/me/premium-trial-eligibility',extra)
  const claim = (actor='a', body={}) => request(body,actor,'/api/v1/me/premium-trial/claim')
  const trials = () => sqlite.prepare("SELECT * FROM membership_entitlements WHERE source='signup_trial'").all()
  it('new authenticated account is eligible, anonymous and forged identities cannot claim',async()=>{
    expect(await (await eligible()).json()).toMatchObject({userId:'a',eligible:true,trialDays:7})
    expect((await claim('unknown')).status).toBe(401)
    expect((await eligible('unknown',{'X-Taste-Map-Test-User':'a','Cf-Access-Authenticated-User-Email':'a@test.com'})).status).toBe(401)
  })
  it('first claim grants exactly seven server days and returns authoritative fixed-term Premium',async()=>{
    const response=await claim();expect(response.status).toBe(200)
    expect(await response.json()).toMatchObject({isPremium:true,source:'signup_trial',expiresAt:'2028-03-07T12:34:56.789Z',membership:{userId:'a',entitlement:{isPremium:true,source:'signup_trial',kind:'fixed_term',isLifetime:false}}})
    expect(trials()).toHaveLength(1)
    expect(trials()[0]).toMatchObject({starts_at:NOW.toISOString(),expires_at:'2028-03-07T12:34:56.789Z',is_lifetime:0,revoked_at:null})
  })
  it('duplicate requests cannot extend or duplicate the original claim',async()=>{
    await claim();vi.setSystemTime(new Date(NOW.getTime()+100000))
    expect((await claim()).status).toBe(409);expect(trials()).toHaveLength(1)
    expect(trials()[0].starts_at).toBe(NOW.toISOString())
    expect((await (await eligible()).json()).eligible).toBe(false)
  })
  it('a second session/device for the same user cannot claim again; another account is independent',async()=>{
    await claim()
    sqlite.prepare("UPDATE auth_sessions SET access_token_hash=? WHERE user_id='a'").run(await sha256('tm_access_testing_long_enough_device2'))
    expect((await claim('device2')).status).toBe(409)
    expect((await claim('b')).status).toBe(200);expect(trials()).toHaveLength(2)
  })
  it('expires at the exact seven-day boundary and never becomes eligible again',async()=>{
    await claim();vi.setSystemTime(new Date(NOW.getTime()+7*86400000-1));expect((await readEffectiveMembership(db,'a')).isPremium).toBe(true)
    vi.setSystemTime(new Date(NOW.getTime()+7*86400000));expect((await readEffectiveMembership(db,'a')).isPremium).toBe(false)
    expect((await (await eligible()).json()).eligible).toBe(false);expect((await claim()).status).toBe(409)
  })
  it('retains Apple subscription precedence and access after trial expiry',async()=>{
    subscription();const response=await (await claim()).json()
    expect(response.membership.entitlement).toMatchObject({isPremium:true,source:'app_store_annual',expiresAt:'2035-01-01T00:00:00Z'})
    vi.setSystemTime(new Date(NOW.getTime()+8*86400000));expect((await readEffectiveMembership(db,'a')).source).toBe('app_store_annual')
  })
  it('rejects client-owned eligibility, userId, dates, source and claim-state writes',async()=>{
    for(const body of [{userId:'b'},{trial_claimed_at:null},{eligible:true},{expiresAt:'2099-01-01'},{source:'admin_grant'}]) expect((await claim('a',body)).status).toBe(400)
    expect(trials()).toHaveLength(0)
    expect((await request({trial_claimed_at:null},'a','/api/v1/me/premium-trial-eligibility')).status).toBe(405)
  })
  it('twenty concurrent claims produce exactly one entitlement and one success',async()=>{
    const results=await Promise.all(Array.from({length:20},()=>claim()))
    expect(results.filter(r=>r.status===200)).toHaveLength(1);expect(results.filter(r=>r.status===409)).toHaveLength(19);expect(trials()).toHaveLength(1)
  })
  it('revoked history still blocks claims and cannot be deleted or rewritten',async()=>{
    await claim();sqlite.prepare("UPDATE membership_entitlements SET status='revoked',revoked_at=? WHERE source='signup_trial'").run(NOW.toISOString())
    expect((await (await eligible()).json()).eligible).toBe(false);expect((await claim()).status).toBe(409)
    expect((await readEffectiveMembership(db,'a')).isPremium).toBe(false)
    expect(()=>sqlite.exec("DELETE FROM membership_entitlements WHERE source='signup_trial'")).toThrow()
    expect(()=>sqlite.exec("UPDATE membership_entitlements SET source='promo' WHERE source='signup_trial'")).toThrow()
  })
  it('a revocation timestamp alone denies trial access and cannot reopen eligibility',async()=>{
    await claim()
    sqlite.prepare("UPDATE membership_entitlements SET revoked_at=? WHERE source='signup_trial'").run(NOW.toISOString())
    expect((await readEffectiveMembership(db,'a')).isPremium).toBe(false)
    expect((await (await eligible()).json()).eligible).toBe(false)
  })
  it('all required entitlement sources independently grant access', async()=>{
    for (const source of ['signup_trial','app_store_subscription','admin_grant','referral_reward','promotion']) {
      sqlite.prepare(`INSERT INTO membership_entitlements (id,user_id,source,starts_at,expires_at,is_lifetime,status,created_at,updated_at)
        VALUES (?, 'b', ?, ?, '2030-01-01T00:00:00Z', 0, 'active', ?, ?)`).run(source,source,NOW.toISOString(),NOW.toISOString(),NOW.toISOString())
      expect((await readEffectiveMembership(db,'b')).isPremium).toBe(true)
      sqlite.prepare("UPDATE membership_entitlements SET status='revoked',revoked_at=? WHERE id=?").run(NOW.toISOString(),source)
      expect((await readEffectiveMembership(db,'b')).isPremium).toBe(false)
    }
  })
  it('claim makes no outbound Apple/payment call and writes no Apple transactions',async()=>{
    const outbound=vi.spyOn(globalThis,'fetch').mockRejectedValue(new Error('No network expected'))
    try { expect((await claim()).status).toBe(200);expect(outbound).not.toHaveBeenCalled();expect(sqlite.prepare('SELECT COUNT(*) n FROM app_store_transactions').get().n).toBe(0) }
    finally { outbound.mockRestore() }
  })
})
