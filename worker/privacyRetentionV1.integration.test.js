import restaurantFixture from '../contracts/fixtures/restaurant.v1.valid.json'
import { handleSyncV1Pull, handleSyncV1Push } from './syncV1'
import { describe, it, expect } from 'vitest'
import { makeDatabase } from './testSupport/privacyDatabase'
import { handleAccountDeletionV1 } from './accountDeletionV1'
import { runPrivacyRetention } from './privacyRetentionV1'

const date = new Date('2026-09-08T00:00:00Z')
class Bucket {
  constructor(keys=[]) { this.keys=new Set(keys); this.calls=0; this.failAt=0; this.proof=false }
  async delete(keys) {
    this.calls++
    for(const key of Array.isArray(keys)?keys:[keys]) {
      this.keys.delete(key)
      if(this.calls===this.failAt) throw new Error('partial deletion')
    }
  }
  async list({prefix,cursor,limit}) {
    const keys=[...this.keys].filter(x=>x.startsWith(prefix)&&(!cursor||x>cursor)).sort()
    const page=keys.slice(0,limit)
    const truncated=keys.length>page.length
    if(limit===1 && !page.length) this.proof=true
    return {objects:page.map(key=>({key})), truncated, ...(truncated?{cursor:page.at(-1)}:{})}
  }
}
function seed(db) {
  db.sqlite.exec(`INSERT INTO users(id,auth_provider,nickname,created_at,updated_at) VALUES
    ('tm_a','apple','Alice','2026-01-01','2026-01-01'),('tm_b','apple','Bob','2026-01-01','2026-01-01');
    INSERT INTO restaurants(id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,created_at,updated_at)
    VALUES('r','tm_a','poi-secret','Secret restaurant','Address','City',30,120,'visited','normal','2026-01-01','2026-01-01');
    INSERT INTO visits(id,user_id,restaurant_id,visited_at,note,created_at,updated_at)
    VALUES('v','tm_a','r','2026-01-01','Secret visit','2026-01-01','2026-01-01');`)
}
function request(body, retry=false) { return new Request('https://test/api/v1/account-deletion/'+(retry?'retry':'confirm'),{method:'POST',headers:{'Content-Type':'application/json','X-Taste-Map-Deletion-Token':body.statusToken},body:JSON.stringify(body)}) }
function body() {return {apiVersion:1,confirmation:'DELETE',requestId:crypto.randomUUID(),statusToken:'tm_delete_'+'a'.repeat(48)}}
async function remove(db,bucket,b,retry=false) {return handleAccountDeletionV1(request(b,retry),{DB:db,PHOTO_STORAGE:bucket},retry?null:{id:'tm_a',developmentIdentity:true},date)}

describe('Privacy deletion boundaries and owner isolation',()=>{
  it.each([0,1,999,1000,1001,2502])('completes %i owner objects only after an empty fresh listing',async count=>{
    const db=makeDatabase();seed(db)
    const keys=Array.from({length:count},(_,i)=>`users/tm_a/photos/p${String(i).padStart(5,'0')}/${i%2?'thumbnail':'display'}.jpg`)
    const bucket=new Bucket([...keys,'users/tm_b/photos/keep/display.jpg'])
    // Include queued originals + thumbnails as well as orphaned objects found by prefix listing.
    for(let i=0;i<Math.floor(count/2);i++) db.sqlite.prepare(`INSERT INTO photos
      (id,user_id,restaurant_id,storage_provider,drive_account_id,drive_file_id,kind,mime_type,file_size,visibility,sync_status,created_at,updated_at,storage_key,thumbnail_storage_key)
      VALUES(?,'tm_a','r','r2','','','visit','image/jpeg',1,'private','synced','2026-01-01','2026-01-01',?,?)`).run('p'+i,keys[i*2],keys[i*2+1])
    const b=body();let result=await remove(db,bucket,b)
    for(let attempts=0;result.retryable&&attempts<5;attempts++) result=await remove(db,bucket,b,true)
    expect(result.status).toBe('completed');expect(bucket.proof).toBe(true)
    expect([...bucket.keys]).toEqual(['users/tm_b/photos/keep/display.jpg'])
    expect(await remove(db,bucket,b)).toEqual(result)
    expect(db.get("SELECT deleted_at FROM users WHERE id='tm_b'").deleted_at).toBeNull()
    db.sqlite.close()
  })
  it('partial failure locks account immediately and remains retryable',async()=>{
    const db=makeDatabase();seed(db);const bucket=new Bucket(['users/tm_a/photos/1/display.jpg','users/tm_a/photos/2/thumbnail.jpg']);bucket.failAt=1
    const b=body();expect(await remove(db,bucket,b)).toMatchObject({status:'failed',completedAt:null,retryable:true})
    expect(db.get("SELECT deleted_at FROM users WHERE id='tm_a'").deleted_at).toBeTruthy()
    expect(await remove(db,bucket,b,true)).toMatchObject({status:'completed'})
  })
  it('never completes when final proof still sees an object',async()=>{
    const db=makeDatabase();seed(db);const bucket=new Bucket();bucket.list=async({limit})=>({objects:limit===1?[{key:'users/tm_a/photos/late/display.jpg'}]:[],truncated:false})
    expect(await remove(db,bucket,body())).toMatchObject({status:'failed',errorCode:'objects_remaining',completedAt:null})
  })
  it('rejects corrupted cross-owner object metadata',async()=>{
    const db=makeDatabase();seed(db)
    db.sqlite.exec(`INSERT INTO photos(id,user_id,restaurant_id,storage_provider,drive_account_id,drive_file_id,kind,mime_type,file_size,visibility,sync_status,created_at,updated_at,storage_key)
      VALUES('p','tm_a','r','r2','','','visit','image/jpeg',1,'private','synced','2026-01-01','2026-01-01','users/tm_b/photos/keep/display.jpg')`)
    const bucket=new Bucket(['users/tm_b/photos/keep/display.jpg'])
    expect(await remove(db,bucket,body())).toMatchObject({status:'failed',errorCode:'object_owner_mismatch'})
    expect(bucket.keys.size).toBe(1)
  })
})
describe('D1 retention on actual migrated SQLite schema',()=>{
  it('retains content inside window, removes payload after window without losing tombstone identity/version',async()=>{
    const db=makeDatabase();seed(db)
    db.sqlite.exec("UPDATE restaurants SET deleted_at='2026-08-20T00:00:00.000Z',server_version=7;UPDATE visits SET deleted_at='2026-08-20T00:00:00.000Z',server_version=9")
    await runPrivacyRetention(db,new Bucket(),date)
    expect(db.get("SELECT note FROM visits WHERE id='v'").note).toBe('Secret visit')
    await runPrivacyRetention(db,new Bucket(),new Date('2026-10-01T00:00:00Z'))
    expect(db.get("SELECT note,server_version,deleted_at FROM visits WHERE id='v'")).toMatchObject({note:'',server_version:9,deleted_at:'2026-08-20T00:00:00.000Z'})
    expect(db.get("SELECT latitude,address FROM restaurants WHERE id='r'")).toMatchObject({latitude:0,address:''})
    await runPrivacyRetention(db,new Bucket(),new Date('2026-10-02T00:00:00Z'))
  })
  it('purges closed account content at final window and preserves other account',async()=>{
    const db=makeDatabase();seed(db);await remove(db,new Bucket(),body())
    await runPrivacyRetention(db,new Bucket(),new Date('2027-10-01T00:00:00Z'))
    expect(db.get("SELECT COUNT(*) AS n FROM visits WHERE user_id='tm_a'").n).toBe(0)
    expect(db.get("SELECT nickname FROM users WHERE id='tm_b'").nickname).toBe('Bob')
    expect(db.get("SELECT COUNT(*) AS n FROM users WHERE id='tm_a'").n).toBe(0)
    await runPrivacyRetention(db,new Bucket(),new Date('2027-10-02T00:00:00Z'))
  })
})

describe('Retention dependency regressions',()=>{
  it('preserves pull tombstones and rejects old-device resurrection after payload cleanup',async()=>{
    const db=makeDatabase();seed(db)
    db.sqlite.exec("UPDATE restaurants SET deleted_at='2026-01-02T00:00:00.000Z',server_version=7;INSERT INTO sync_change_log_v6(user_id,entity_type,entity_id,operation,server_version,mutation_id,changed_at) VALUES('tm_a','restaurant','r','delete',7,'delete-r','2026-01-02T00:00:00.000Z')")
    await runPrivacyRetention(db,new Bucket(),date)
    const pulled=await handleSyncV1Pull(db,'tm_a',new Request('https://test/api/v1/sync/pull?schemaVersion=1&cursor=0'))
    expect(pulled.tombstones).toContainEqual(expect.objectContaining({entityId:'r',serverVersion:7}))
    const payload={...restaurantFixture,id:'r',userId:'tm_a'}
    const pushed=await handleSyncV1Push(db,'tm_a',new Request('https://test/api/v1/sync/push',{method:'POST',body:JSON.stringify({apiVersion:1,schemaVersion:1,mutations:[{mutationId:'resurrect-r',entityType:'restaurant',entityId:'r',operation:'upsert',baseVersion:7,clientTimestamp:payload.updatedAt,payload}]})}))
    expect(pushed.acknowledgements[0]).toMatchObject({status:'conflict',conflictReason:'entity_deleted'})
  })
  it('keeps R2 keys after physical-delete failure and retries both variants',async()=>{
    const db=makeDatabase();seed(db)
    const keys=['users/tm_a/photos/p/display.jpg','users/tm_a/photos/p/thumbnail.jpg']
    db.sqlite.prepare("INSERT INTO photos(id,user_id,restaurant_id,storage_provider,drive_account_id,drive_file_id,kind,mime_type,file_size,visibility,sync_status,created_at,updated_at,deleted_at,storage_key,thumbnail_storage_key) VALUES('p','tm_a','r','r2','','','visit','image/jpeg',1,'private','synced','2026-01-01','2026-01-01','2026-01-02',?,?)").run(...keys)
    const bucket=new Bucket([...keys,'users/tm_b/photos/keep/display.jpg']);bucket.failAt=1
    await expect(runPrivacyRetention(db,bucket,date)).rejects.toThrow()
    expect(db.get("SELECT storage_key FROM photos WHERE id='p'").storage_key).toBe(keys[0])
    await runPrivacyRetention(db,bucket,date)
    expect([...bucket.keys]).toEqual(['users/tm_b/photos/keep/display.jpg'])
    expect(db.get("SELECT storage_key FROM photos WHERE id='p'").storage_key).toBe('')
  })
  it('retains live Apple ownership then purges expired financial rows in FK order',async()=>{
    const db=makeDatabase();seed(db)
    db.sqlite.exec(`INSERT INTO app_store_accounts VALUES('tm_a','account-token','2026-01-01','2026-01-01');
      INSERT INTO app_store_owners_v2 VALUES('Sandbox','orig','tm_a','account-token','2026-01-01','2026-01-01');
      INSERT INTO app_store_transactions_v2(environment,transaction_id,original_transaction_id,user_id,app_account_token,product_id,purchase_at,expires_at,signed_transaction_digest,verification_source,verified_at,created_at,updated_at)
      VALUES('Sandbox','txn','orig','tm_a','account-token','monthly','2026-01-01','2028-01-01','digest','app_store_server_api','2026-01-01','2026-01-01','2026-01-01')`)
    db.sqlite.exec("INSERT INTO app_store_verification_audit(environment,transaction_id,original_transaction_id,user_id,signed_transaction_digest,verified_at) VALUES('Sandbox','txn','orig','tm_a','digest','2026-01-01')")
    expect(()=>db.sqlite.exec('DELETE FROM app_store_verification_audit')).toThrow('immutable verification audit')
    await remove(db,new Bucket(),body())
    await runPrivacyRetention(db,new Bucket(),new Date('2027-10-01T00:00:00Z'))
    expect(db.get('SELECT COUNT(*) AS n FROM app_store_transactions_v2').n).toBe(1)
    expect(db.get("SELECT COUNT(*) AS n FROM users WHERE id='tm_a'").n).toBe(1)
    await runPrivacyRetention(db,new Bucket(),new Date('2029-02-01T00:00:00Z'))
    expect(db.get('SELECT COUNT(*) AS n FROM app_store_transactions_v2').n).toBe(0)
    expect(db.get('SELECT COUNT(*) AS n FROM privacy_purge_authorization').n).toBe(0)
    expect(db.get("SELECT COUNT(*) AS n FROM users WHERE id='tm_a'").n).toBe(0)
  })
})

it('concurrent duplicate confirmation shares one durable job and cannot erase another owner',async()=>{
  const db=makeDatabase();seed(db);const bucket=new Bucket(['users/tm_a/photos/p/display.jpg','users/tm_b/photos/p/display.jpg']);const b=body()
  const results=await Promise.all([remove(db,bucket,b),remove(db,bucket,b)])
  expect(new Set(results.map(x=>x.jobId)).size).toBe(1)
  expect(db.get('SELECT COUNT(*) AS n FROM account_deletion_jobs').n).toBe(1)
  expect(db.get('SELECT status FROM account_deletion_jobs').status).toBe('completed')
  expect([...bucket.keys]).toEqual(['users/tm_b/photos/p/display.jpg'])
})
it('keeps another account reward until its benefit and audit window end',async()=>{
  const db=makeDatabase();seed(db)
  db.sqlite.exec(`INSERT INTO referrals(invitee_id,referrer_id,code,bound_at,actor) VALUES('tm_b','tm_a','code','2026-01-01','system');
    UPDATE referrals SET status='qualified',qualified_at='2026-01-02',qualifying_visit_id='v',slot=1 WHERE invitee_id='tm_b'`)
  await remove(db,new Bucket(),body())
  await runPrivacyRetention(db,new Bucket(),new Date('2027-10-01T00:00:00Z'))
  expect(db.get("SELECT COUNT(*) AS n FROM premium_rewards WHERE user_id='tm_b'").n).toBe(1)
  db.sqlite.exec("UPDATE premium_rewards SET state='active',starts_at='2026-01-02',expires_at='2026-02-02' WHERE user_id='tm_b'")
  await runPrivacyRetention(db,new Bucket(),new Date('2027-10-02T00:00:00Z'))
  expect(db.get("SELECT COUNT(*) AS n FROM users WHERE id='tm_a'").n).toBe(0)
  expect(db.get("SELECT nickname FROM users WHERE id='tm_b'").nickname).toBe('Bob')
})
