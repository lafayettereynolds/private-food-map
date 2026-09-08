import { DatabaseSync } from 'node:sqlite'
import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest'
import { applyAllMigrations } from './testSupport/migrations.js'
import { registrationReferral, qualifyReferral, settlePremiumRewards, referralDashboard, revokeReferral } from './referralsV1'
import { readEffectiveMembership } from './index'

const NOW=new Date('2026-09-07T00:00:00.000Z'), code='0123456789abcdef01234567'
let sql,db
function statement(query,values=[]) { return {bind:(...v)=>statement(query,v),first:async()=>sql.prepare(query).get(...values)??null,
  all:async()=>({results:sql.prepare(query).all(...values)}),run:async()=>({meta:{changes:Number(sql.prepare(query).run(...values).changes)}})} }
beforeEach(()=>{vi.useFakeTimers();vi.setSystemTime(NOW);sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');applyAllMigrations(sql);
  db={prepare:statement,batch:async statements=>{sql.exec('BEGIN');try{const result=[];for(const s of statements)result.push(await s.run());sql.exec('COMMIT');return result}catch(e){sql.exec('ROLLBACK');throw e}}};
  for(const id of ['a','b',...Array.from({length:7},(_,i)=>`n${i}`)])sql.prepare("INSERT INTO users(id,nickname,created_at,updated_at) VALUES(?,?,?,?)").run(id,id,NOW.toISOString(),NOW.toISOString());
  sql.prepare('INSERT INTO referral_codes VALUES(?,?,?)').run('a',code,NOW.toISOString())
})
afterEach(()=>{sql.close();vi.useRealTimers()})
async function bind(id='n0'){await db.batch(await registrationReferral(db,code,id,NOW))}
function visit(id='n0',deleted=false){sql.prepare(`INSERT INTO restaurants(id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,created_at,updated_at)
  VALUES(?,?,'','餐厅','','',1,1,'visited','normal',?,?)`).run('r'+id,id,NOW.toISOString(),NOW.toISOString());
  sql.prepare(`INSERT INTO visits(id,user_id,restaurant_id,visited_at,created_at,updated_at,deleted_at) VALUES(?,?,?,?,?,?,?)`)
    .run('v'+id,id,'r'+id,NOW.toISOString(),NOW.toISOString(),NOW.toISOString(),deleted?NOW.toISOString():null)
}
function entitlement(source,expiry,user='a') {sql.prepare(`INSERT INTO membership_entitlements(id,user_id,source,starts_at,expires_at,is_lifetime,status,created_at,updated_at,created_by_user_id)
  VALUES(?,?,?,?,?,?,'active',?,?,'admin')`).run(source+user,user,source,NOW.toISOString(),expiry,expiry==null?1:0,NOW.toISOString(),NOW.toISOString())}
async function qualify(id='n0'){await bind(id);visit(id);await qualifyReferral(db,id,NOW)}
const rows=()=>sql.prepare('SELECT * FROM premium_rewards ORDER BY role').all()
describe('Referral Premium Reward',()=>{
  it('requires a valid Visit before qualification and awards exactly 30 + 14 once',async()=>{
    await bind();await qualifyReferral(db,'n0',NOW);expect(rows()).toHaveLength(0);visit();
    await Promise.all(Array.from({length:6},()=>qualifyReferral(db,'n0',NOW)));expect(rows().map(r=>r.days)).toEqual([14,30]);
    await settlePremiumRewards(db,'a',NOW);await settlePremiumRewards(db,'n0',NOW);
    expect((await readEffectiveMembership(db,'a')).expiresAt).toBe('2026-10-07T00:00:00.000Z');
    expect((await readEffectiveMembership(db,'n0')).expiresAt).toBe('2026-09-21T00:00:00.000Z');
    expect(sql.prepare("SELECT count(*) n FROM referral_audit_log WHERE action='reward_granted'").get().n).toBe(2)
  })
  it('enforces five lifetime slots under racing requests, even after revocation',async()=>{
    for(let i=0;i<7;i++){await bind('n'+i);visit('n'+i)}
    await Promise.all(Array.from({length:7},(_,i)=>qualifyReferral(db,'n'+i,NOW)));
    expect(rows()).toHaveLength(10);expect(sql.prepare("SELECT COUNT(*) n FROM referrals WHERE status='capped'").get().n).toBe(2);
    expect((await referralDashboard(db,'a','https://test',NOW))).toMatchObject({qualifiedCount:5,earnedDays:150,pendingDays:0});
    expect((await readEffectiveMembership(db,'a')).expiresAt).toBe('2027-02-04T00:00:00.000Z');
    await revokeReferral(db,'n0','admin','fraud',NOW);await qualifyReferral(db,'n5',NOW);
    expect((await referralDashboard(db,'a','https://test',NOW)).qualifiedCount).toBe(5);expect(rows()).toHaveLength(10)
  })
  it('rejects self invitation, invalid codes and duplicate attribution',async()=>{
    await expect(registrationReferral(db,code,'a',NOW)).rejects.toThrow();
    await expect(registrationReferral(db,'bad','n0',NOW)).rejects.toThrow();
    await bind();await expect(bind()).rejects.toThrow();expect(rows()).toHaveLength(0)
  })
  it('compacts remaining rewards after revoke without opening a Premium gap',async()=>{
    await qualify('n0');await qualify('n1');await settlePremiumRewards(db,'a',NOW)
    await revokeReferral(db,'n0','admin','duplicate',NOW)
    expect((await readEffectiveMembership(db,'a'))).toMatchObject({isPremium:true,expiresAt:'2026-10-07T00:00:00.000Z'})
    expect(sql.prepare("SELECT count(*) n FROM referral_audit_log WHERE action='reward_rescheduled'").get().n).toBe(1)
  })
  it('does not qualify deleted Visits or test-data restaurants',async()=>{
    await bind();visit('n0',true);await qualifyReferral(db,'n0',NOW);expect(rows()).toHaveLength(0);
    sql.exec("UPDATE visits SET deleted_at=NULL; UPDATE restaurants SET is_test_data=1");
    await qualifyReferral(db,'n0',NOW);expect(rows()).toHaveLength(0)
  })
  it('extends ordinary Gift seamlessly without overwriting the original grant',async()=>{
    entitlement('gift_annual','2027-09-07T00:00:00.000Z');await qualify();await settlePremiumRewards(db,'a',NOW);
    expect((await readEffectiveMembership(db,'a'))).toMatchObject({source:'gift_annual',expiresAt:'2027-10-07T00:00:00.000Z'});
    expect(sql.prepare("SELECT expires_at FROM membership_entitlements WHERE source='gift_annual'").get().expires_at).toBe('2027-09-07T00:00:00.000Z');
    vi.setSystemTime(new Date('2027-09-08T00:00:00Z'));expect((await readEffectiveMembership(db,'a')).source).toBe('referral_reward')
  })
  it('queues during Apple renewals, starts at actual entitlement end even on late reads',async()=>{
    entitlement('app_store_annual','2026-10-01T00:00:00.000Z');await qualify();
    expect((await referralDashboard(db,'a','https://test',NOW))).toMatchObject({earnedDays:30,pendingDays:30});
    expect((await readEffectiveMembership(db,'a')).expiresAt).toBe('2026-10-01T00:00:00.000Z');
    sql.exec("UPDATE membership_entitlements SET expires_at='2026-11-01T00:00:00.000Z' WHERE source='app_store_annual'");
    await settlePremiumRewards(db,'a',new Date('2026-10-02'));expect(rows().find(r=>r.role==='referrer').state).toBe('pending');
    vi.setSystemTime(new Date('2026-11-10'));expect((await readEffectiveMembership(db,'a'))).toMatchObject({source:'referral_reward',startsAt:'2026-11-01T00:00:00.000Z',expiresAt:'2026-12-01T00:00:00.000Z'});
    expect(sql.prepare("SELECT expires_at FROM membership_entitlements WHERE source='app_store_annual'").get().expires_at).toBe('2026-11-01T00:00:00.000Z')
  })
  it('counts lifetime invitations but does not create a duration entitlement',async()=>{
    entitlement('gift_lifetime',null);await qualify();expect((await referralDashboard(db,'a','https://test',NOW))).toMatchObject({qualifiedCount:1,earnedDays:30,pendingDays:0});
    expect(rows().find(r=>r.role==='referrer').state).toBe('lifetime');expect((await readEffectiveMembership(db,'a')).expiresAt).toBeNull()
  })
  it('revokes both rewards with audits without removing Apple or Gift',async()=>{
    await qualify();await settlePremiumRewards(db,'a',NOW);await settlePremiumRewards(db,'n0',NOW);await revokeReferral(db,'n0','admin','重复账号',NOW);
    expect((await readEffectiveMembership(db,'a')).isPremium).toBe(false);expect((await readEffectiveMembership(db,'n0')).isPremium).toBe(false);
    expect(rows().every(r=>r.state==='revoked')).toBe(true);expect(sql.prepare("SELECT count(*) n FROM referral_audit_log WHERE action='reward_revoked'").get().n).toBe(2)
  })
  it('rolls back qualification and both rewards when audit write fails',async()=>{
    await bind();visit();sql.exec("CREATE TRIGGER fail_reward_audit BEFORE INSERT ON referral_audit_log WHEN NEW.action='reward_granted' BEGIN SELECT RAISE(ABORT,'audit unavailable'); END");
    await expect(qualifyReferral(db,'n0',NOW)).rejects.toThrow();expect(rows()).toHaveLength(0);
    expect(sql.prepare('SELECT status FROM referrals').get().status).toBe('pending')
  })
  it('isolates A / B / A and never accepts another owner in a dashboard',async()=>{
    await qualify();for(const id of ['a','b','a']) {const d=await referralDashboard(db,id,'https://test',NOW);expect(d.userID).toBe(id);expect(d.qualifiedCount).toBe(id==='a'?1:0)}
    expect((await readEffectiveMembership(db,'b')).isPremium).toBe(false)
  })
})
