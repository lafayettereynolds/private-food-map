import { describe, it, expect, afterEach } from 'vitest'
import { DatabaseSync } from 'node:sqlite'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { randomBytes } from 'node:crypto'
import { openInventory, parseCodes, importCSV, mapBatch, assign, handoff, markFailed, verifyRedemption, summary, serverAssignmentSQL, syncServerRedemption } from './sandbox-offers.mjs'
import { applyAllMigrations } from '../worker/testSupport/migrations.js'
import { registrationReferral, qualifyReferral, settlePremiumRewards } from '../worker/referralsV1'

const resources = []
afterEach(() => { for (const r of resources.splice(0)) r.close() })
function setup() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tastemap-offer-test-'))
  const db = openInventory(dir); resources.push(db)
  const ledger = new DatabaseSync(':memory:'); resources.push(ledger)
  ledger.exec('PRAGMA foreign_keys=ON'); applyAllMigrations(ledger)
  const now = new Date().toISOString()
  for (const id of ['a', 'b']) ledger.prepare('INSERT INTO users(id,nickname,created_at,updated_at) VALUES(?,?,?,?)').run(id, id, now, now)
  const code = randomBytes(12).toString('hex')
  ledger.prepare('INSERT INTO referral_codes VALUES(?,?,?)').run('a', code, now)
  function statement(q, values=[]) { return { bind:(...v)=>statement(q,v),first:async()=>ledger.prepare(q).get(...values)??null,
    all:async()=>({results:ledger.prepare(q).all(...values)}),run:async()=>ledger.prepare(q).run(...values) } }
  const adapter = { prepare: statement }
  const csv = path.join(dir, 'synthetic.csv')
  // Generated, non-Apple test values; no real inventory is read by automated tests.
  fs.writeFileSync(csv, Array.from({length:3},()=>randomBytes(9).toString('hex').toUpperCase()).join('\n'), {mode:0o600})
  const imported = importCSV(db,csv,dir)
  const qualify = async (settle = true) => {
    for (const s of await registrationReferral(adapter,code,'b',new Date())) await s.run()
    ledger.prepare(`INSERT INTO restaurants(id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,created_at,updated_at)
      VALUES('r','b','','','','',1,1,'visited','normal',?,?)`).run(now,now)
    ledger.prepare("INSERT INTO visits(id,user_id,restaurant_id,visited_at,created_at,updated_at) VALUES('v','b','r',?,?,?)").run(now,now,now)
    await qualifyReferral(adapter,'b'); if (settle) { await settlePremiumRewards(adapter,'a'); await settlePremiumRewards(adapter,'b') }
  }
  return {db,ledger,dir,csv,imported,qualify}
}
describe('private Sandbox offer inventory', () => {
  it('parses safely and rejects invalid layouts without disclosing input', () => {
    expect(()=>parseCodes('not,a,supported,layout')).toThrow('sandbox_offer_operation_rejected')
    expect(()=>parseCodes('')).toThrow()
  })
  it('imports privately and idempotently with all inventory unused and unmapped', () => {
    const s=setup()
    expect(importCSV(s.db,s.csv,s.dir).imported).toBe(0)
    expect(summary(s.db)[0]).toMatchObject({total:3,unused:3,assigned:0,redeemed:0,failed:0,offerKey:null})
    expect(fs.statSync(s.dir).mode & 0o777).toBe(0o700)
    expect(fs.statSync(path.join(s.dir,'inventory.sqlite')).mode & 0o777).toBe(0o600)
    expect(()=>openInventory(s.dir,'production')).toThrow()
  })
  it('requires qualified Visit and confirmed mapping, assigns once per reward', async () => {
    const s=setup(), reward='referral:b:invitee'
    expect(()=>assign(s.db,s.ledger,reward)).toThrow()
    await s.qualify()
    expect(()=>assign(s.db,s.ledger,reward)).toThrow()
    mapBatch(s.db,s.imported.batchID,'invitee','test-offer-reference')
    const a=assign(s.db,s.ledger,reward), b=assign(s.db,s.ledger,reward)
    expect(a.days).toBe(14); expect(b.assignmentID).toBe(a.assignmentID)
    expect(summary(s.db)[0]).toMatchObject({assigned:1,unused:2})
    const second=openInventory(s.dir);resources.push(second)
    expect(assign(second,s.ledger,reward).assignmentID).toBe(a.assignmentID)
    expect(()=>mapBatch(s.db,s.imported.batchID,'referrer_1','other')).toThrow()
  })
  it('uses referrer qualification slot and never assigns a pending reward',async()=>{
    const s=setup();await s.qualify();mapBatch(s.db,s.imported.batchID,'referrer_1','test-slot-1')
    const a=assign(s.db,s.ledger,'referral:b:referrer'); expect(a.days).toBe(30)
    expect(a.offer).toBe('邀请奖励 1')
    const pending=setup();await pending.qualify(false)
    mapBatch(pending.db,pending.imported.batchID,'invitee','test-pending')
    expect(()=>assign(pending.db,pending.ledger,'referral:b:invitee')).toThrow()
  })
  it('never recycles failed codes and handoffs stay private',async()=>{
    const s=setup();await s.qualify();mapBatch(s.db,s.imported.batchID,'invitee','test-offer')
    const a=assign(s.db,s.ledger,'referral:b:invitee')
    const file=handoff(s.db,s.ledger,a.assignmentID,s.dir)
    expect(fs.statSync(file.privateFile).mode&0o777).toBe(0o600)
    expect(()=>handoff(s.db,s.ledger,a.assignmentID,s.dir)).toThrow()
    markFailed(s.db,a.assignmentID,'cancelled')
    expect(assign(s.db,s.ledger,'referral:b:invitee').state).toBe('failed')
    expect(summary(s.db)[0]).toMatchObject({unused:2,failed:1})
    expect(()=>markFailed(s.db,a.assignmentID,'arbitrary-secret-note')).toThrow()
    expect(()=>s.db.exec('DELETE FROM audit')).toThrow()
  })
  it('rolls assignment back if audit fails',async()=>{
    const s=setup();await s.qualify();mapBatch(s.db,s.imported.batchID,'invitee','test-offer')
    s.db.exec("CREATE TRIGGER fail_audit BEFORE INSERT ON audit BEGIN SELECT RAISE(ABORT,'test failure'); END")
    expect(()=>assign(s.db,s.ledger,'referral:b:invitee')).toThrow()
    expect(summary(s.db)[0]).toMatchObject({unused:3,assigned:0})
  })
  it('denies lifetime gifts and revoked rewards even after assignment',async()=>{
    const s=setup();await s.qualify();mapBatch(s.db,s.imported.batchID,'invitee','test-offer')
    const a=assign(s.db,s.ledger,'referral:b:invitee')
    const now=new Date().toISOString()
    s.ledger.prepare(`INSERT INTO membership_entitlements(id,user_id,source,starts_at,expires_at,is_lifetime,status,created_at,updated_at,created_by_user_id)
      VALUES('gift','b','gift_lifetime',?,NULL,1,'active',?,?,'admin')`).run(now,now,now)
    expect(()=>handoff(s.db,s.ledger,a.assignmentID,s.dir)).toThrow()
    s.ledger.exec("UPDATE premium_rewards SET state='revoked',revoked_at=changed_at WHERE role='invitee'")
    expect(()=>assign(s.db,s.ledger,'referral:b:invitee')).toThrow()
  })
  it('publishes only qualified owner metadata and syncs only verified Sandbox server receipts',async()=>{
    const s=setup();await s.qualify();mapBatch(s.db,s.imported.batchID,'invitee','test-offer')
    const a=assign(s.db,s.ledger,'referral:b:invitee')
    const sql=serverAssignmentSQL(s.db,s.ledger,a.assignmentID)
    for(const row of s.db.prepare('SELECT secret FROM codes').all()) expect(sql).not.toContain(row.secret)
    s.ledger.exec(sql)
    expect(()=>syncServerRedemption(s.db,s.ledger,a.assignmentID)).toThrow()
    const now=new Date().toISOString(), token='11111111-1111-4111-8111-111111111111'
    s.ledger.prepare('INSERT INTO app_store_accounts VALUES(?,?,?,?)').run('b',token,now,now)
    s.ledger.prepare("INSERT INTO app_store_owners_v2(environment,original_transaction_id,user_id,app_account_token,created_at,updated_at) VALUES('Production',?,?,?,?,?)").run('900','b',token,now,now)
    s.ledger.prepare(`INSERT INTO app_store_transactions_v2(transaction_id,original_transaction_id,user_id,app_account_token,product_id,environment,purchase_at,signed_transaction_digest,verification_source,verified_at,created_at,updated_at)
      VALUES('100','900','b',?,'test-product','Production',?,'test-digest','app_store_server_api',?,?,?)`).run(token,now,now,now,now)
    s.ledger.prepare("UPDATE sandbox_offer_assignments SET state='redeemed',transaction_id='100',original_transaction_id='900' WHERE assignment_id=?").run(a.assignmentID)
    expect(()=>syncServerRedemption(s.db,s.ledger,a.assignmentID)).toThrow()
    s.ledger.exec("INSERT INTO app_store_owners_v2 SELECT 'Sandbox',original_transaction_id,user_id,app_account_token,created_at,updated_at FROM app_store_owners_v2 WHERE environment='Production'")
    s.ledger.exec("UPDATE app_store_transactions_v2 SET environment='Sandbox'")
    expect(syncServerRedemption(s.db,s.ledger,a.assignmentID).state).toBe('redeemed')
    expect(syncServerRedemption(s.db,s.ledger,a.assignmentID).duplicate).toBe(true)
    expect(summary(s.db)[0].redeemed).toBe(1)
  })

  it('verifies Sandbox, owner, offer and transaction; rejects production and replay',async()=>{
    const s=setup();await s.qualify();mapBatch(s.db,s.imported.batchID,'invitee','test-offer')
    const a=assign(s.db,s.ledger,'referral:b:invitee')
    const token=randomBytes(16).toString('hex')
    s.ledger.prepare('INSERT INTO app_store_accounts(user_id,app_account_token,created_at,updated_at) VALUES(?,?,?,?)').run('b',token,new Date().toISOString(),new Date().toISOString())
    const env={APP_ENVIRONMENT:'development',APP_STORE_API_ENVIRONMENT:'sandbox'}
    const tx={transactionId:'123',environment:'Sandbox',offerType:3,offerIdentifier:'test-offer',appAccountToken:token,purchaseDate:Date.now()+1}
    for (const bad of [{environment:'Production'},{appAccountToken:'another-account'},{offerIdentifier:'wrong-offer'},{offerType:1},{revocationDate:1},{purchaseDate:0}]) {
      await expect(verifyRedemption(s.db,s.ledger,a.assignmentID,'123',env,async()=>({...tx,...bad}))).rejects.toThrow()
    }
    await expect(verifyRedemption(s.db,s.ledger,a.assignmentID,'123',{...env,APP_STORE_API_ENVIRONMENT:'production'},async()=>tx)).rejects.toThrow()
    expect((await verifyRedemption(s.db,s.ledger,a.assignmentID,'123',env,async()=>tx)).state).toBe('redeemed')
    await expect(verifyRedemption(s.db,s.ledger,a.assignmentID,'123',env,async()=>tx)).rejects.toThrow()
    expect(summary(s.db)[0].redeemed).toBe(1)
  })
})
