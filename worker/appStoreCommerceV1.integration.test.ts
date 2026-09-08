// @ts-nocheck -- Vitest executes this Node-only D1 adapter; the Worker tsconfig
// intentionally excludes Node type declarations.
import { generateKeyPairSync, createHash } from 'node:crypto'
import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { verifyAppleSignedData } from './appleSignedData'
import {
  AppStoreCommerceV1Error,
  handleAppStoreCommerceV1,
  handleAppStoreServerNotificationV1,
  fetchVerifiedTransaction,
} from './appStoreCommerceV1'
import { applyAllMigrations } from './testSupport/migrations.js'
import { mutateMembership, readEffectiveMembership } from './index'
import worker from './index'

// Only this D1/API contract suite substitutes the cryptographic boundary.
// appleSignedData.test.ts exercises the real verifier's rejection boundary.
vi.mock('./appleSignedData', async importOriginal => ({
  ...await importOriginal(),
  verifyAppleSignedData: vi.fn(async signed => JSON.parse(Buffer.from(signed.split('.')[1],'base64url').toString())),
}))
const BUNDLE_ID = 'com.lafayette.tastemap'
const MONTHLY = 'dev.tastemap.storekit.monthly'
const YEARLY = 'dev.tastemap.storekit.yearly'
const FUTURE = Date.parse('2099-01-01T00:00:00.000Z')
const PAST = Date.parse('2020-01-01T00:00:00.000Z')

describe('App Store commerce V1 integration', () => {
  let database: SQLiteD1Database
  let environment: Record<string, string>

  beforeEach(() => {
    vi.mocked(verifyAppleSignedData).mockImplementation(async signed => JSON.parse(Buffer.from(signed.split('.')[1],'base64url').toString()))
    database = makeDatabase()
    seedUser(database, 'tm_a')
    seedUser(database, 'tm_b')
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
    environment = {
      APP_ENVIRONMENT: 'development',
      APP_STORE_BUNDLE_ID: BUNDLE_ID,
      APP_STORE_APP_APPLE_ID: '123456789',
      APP_STORE_MONTHLY_PRODUCT_ID: MONTHLY,
      APP_STORE_YEARLY_PRODUCT_ID: YEARLY,
      APP_STORE_API_ENVIRONMENT: 'sandbox',
      APP_STORE_ISSUER_ID: 'development-issuer',
      APP_STORE_KEY_ID: 'DEVKEY123',
      APP_STORE_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    }
  })

  it('refreshes Premium only in the verified authenticated session; logout/login and other accounts stay isolated',async()=>{
    environment.APP_ENVIRONMENT='production'
    const tokenA=seedSession(database,'session_a','tm_a')
    const tokenB=seedSession(database,'session_b','tm_b')
    const tokenNewA=seedSession(database,'session_new_a','tm_a')
    const account=await configuration(database,'tm_a',environment)
    const tx=transaction('555','999',account.appAccountToken,FUTURE)
    await handleAppStoreCommerceV1(new Request('https://api.tastemap.cn/api/v1/storekit/transactions/reconcile',{
      method:'POST',body:JSON.stringify({transactionId:'555',signedTransactionInfo:jws(tx)})
    }),database,'tm_a',environment,appleFetch(tx),'session_a')
    expect(database.get("SELECT store_environment FROM auth_sessions WHERE id='session_a'").store_environment).toBe('Sandbox')
    for(const [token,expected] of [[tokenA,true],[tokenB,false],[tokenNewA,false]]) {
      const response=await worker.fetch(new Request('https://api.tastemap.cn/api/v1/me/entitlements',{
        headers:{Authorization:`Bearer ${token}`,'X-Store-Environment':'Sandbox'}
      }),{...environment,DB:database})
      expect(response.status).toBe(200)
      expect((await response.json()).entitlement.isPremium).toBe(expected)
    }
    database.sqlite.exec("UPDATE auth_sessions SET revoked_at='2026-01-01' WHERE id='session_a'")
    const denied=await worker.fetch(new Request('https://api.tastemap.cn/api/v1/me/entitlements',{headers:{Authorization:`Bearer ${tokenA}`}}),{...environment,DB:database})
    expect(denied.status).toBe(401)
    expect(database.get("SELECT membership_tier FROM users WHERE id='tm_a'").membership_tier).toBe('free')
  })

  it('routes signed Sandbox and Production independently on the same Release server and isolates identical IDs', async () => {
    environment.APP_ENVIRONMENT='production'
    environment.APP_STORE_API_ENVIRONMENT='production'
    const account=await configuration(database,'tm_a',environment)
    const sandbox=transaction('555','999',account.appAccountToken,FUTURE)
    const production={...sandbox,environment:'Production'}
    await reconcile(database,'tm_a','555',environment,appleFetch(sandbox))
    expect((await readEffectiveMembership(database,'tm_a')).isPremium).toBe(false)
    expect((await readEffectiveMembership(database,'tm_a','Sandbox')).isPremium).toBe(true)
    await reconcile(database,'tm_a','555',environment,appleFetch(production))
    expect((await readEffectiveMembership(database,'tm_a')).isPremium).toBe(true)
    expect(database.get('SELECT count(*) AS n FROM app_store_transactions_v2 WHERE transaction_id=\'555\'').n).toBe(2)
    await reconcile(database,'tm_a','555',environment,appleFetch({...sandbox,revocationDate:Date.now()}))
    expect((await readEffectiveMembership(database,'tm_a','Sandbox')).isPremium).toBe(false)
    expect((await readEffectiveMembership(database,'tm_a')).isPremium).toBe(true)
  })

  it('falls back only for Apple TransactionIdNotFound, not generic errors or credential failures',async()=>{
    const account=await configuration(database,'tm_a',environment)
    const tx=transaction('555','999',account.appAccountToken,FUTURE)
    const calls:string[]=[]
    const fallback=async(url)=>{calls.push(String(url));return calls.length===1?Response.json({errorCode:4040010},{status:404}):Response.json({signedTransactionInfo:jws(tx)})}
    expect((await fetchVerifiedTransaction('555',environment,fallback)).environment).toBe('Sandbox')
    expect(calls).toEqual(['https://api.storekit.apple.com/inApps/v1/transactions/555','https://api.storekit-sandbox.apple.com/inApps/v1/transactions/555'])
    for(const status of [401,403,404,429,500]) {
      const failure=vi.fn(async()=>Response.json({errorCode:999},{status}))
      await expect(fetchVerifiedTransaction('555',environment,failure)).rejects.toMatchObject({code:'apple_verification_unavailable'})
      expect(failure).toHaveBeenCalledTimes(1)
    }
  })

  it('rejects endpoint/environment mismatch and spoofed client environment',async()=>{
    const account=await configuration(database,'tm_a',environment)
    const tx=transaction('555','999',account.appAccountToken,FUTURE)
    const wrong=async()=>Response.json({signedTransactionInfo:jws({...tx,environment:'Production'})})
    await expect(fetchVerifiedTransaction('555',environment,wrong,jws(tx))).rejects.toMatchObject({code:'apple_environment_mismatch'})
    const apple=vi.fn()
    await expect(handleAppStoreCommerceV1(new Request('https://api.tastemap.cn/api/v1/storekit/transactions/reconcile',{
      method:'POST',body:JSON.stringify({transactionId:'555',environment:'Sandbox'})
    }),database,'tm_a',environment,apple)).rejects.toMatchObject({code:'untrusted_environment'})
    expect(apple).not.toHaveBeenCalled()
    expect(database.get('SELECT count(*) AS n FROM app_store_transactions_v2').n).toBe(0)
  })

  it('safely records TEST and unknown verified notifications without changing entitlements',async()=>{
    for(const type of ['TEST','FUTURE_UNKNOWN_TYPE']) {
      const apple=vi.fn()
      const payload={notificationUUID:type,notificationType:type,data:{environment:'Sandbox',bundleId:BUNDLE_ID}}
      const request=()=>new Request('https://api.tastemap.cn/api/v1/storekit/notifications',{method:'POST',body:JSON.stringify({signedPayload:jws(payload)})})
      const first=await handleAppStoreServerNotificationV1(request(),database,environment,apple)
      expect(first.disposition).toBe(type==='TEST'?'test':'ignored')
      expect(await handleAppStoreServerNotificationV1(request(),database,environment,apple)).toMatchObject({duplicate:true})
      expect(apple).not.toHaveBeenCalled()
    }
    expect(database.get('SELECT count(*) AS n FROM membership_entitlements').n).toBe(0)
    expect(database.get('SELECT count(*) AS n FROM sandbox_membership_entitlements').n).toBe(0)
  })

  it('issues a stable, isolated appAccountToken and exposes no fake price', async () => {
    const a = await configuration(database, 'tm_a', environment)
    const repeated = await configuration(database, 'tm_a', environment)
    const b = await configuration(database, 'tm_b', environment)
    expect(a).toEqual(repeated)
    expect(a.purchaseReady).toBe(true)
    expect(a.appAccountToken).not.toBe(b.appAccountToken)
    expect(a.products).toEqual([
      { id: MONTHLY, period: 'monthly' },
      { id: YEARLY, period: 'annual' },
    ])
    expect(JSON.stringify(a)).not.toContain('price')
  })

  it('keeps catalog readable but disables purchase when verification credentials are absent', async () => {
    delete environment.APP_STORE_PRIVATE_KEY
    const result = await configuration(database, 'tm_a', environment)
    expect(result.configured).toBe(true)
    expect(result.purchaseReady).toBe(false)
    expect(result.products).toHaveLength(2)
    expect(JSON.stringify(result)).not.toContain('APP_STORE_PRIVATE_KEY')
  })

  it('reconciles verified Apple data idempotently and rejects cross-user claims', async () => {
    const account = await configuration(database, 'tm_a', environment)
    const apple = appleFetch(transaction('10001', '90001', account.appAccountToken, FUTURE))
    const first = await reconcile(database, 'tm_a', '10001', environment, apple)
    const retry = await reconcile(database, 'tm_a', '10001', environment, apple)
    expect(first).toEqual(retry)
    expect(database.get('SELECT COUNT(*) AS value FROM app_store_transactions_v2').value).toBe(1)
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('free')
    expect((await readEffectiveMembership(database as never, 'tm_a', 'Sandbox')).isPremium).toBe(true)
    expect((await readEffectiveMembership(database as never, 'tm_a')).isPremium).toBe(false)
    await expect(reconcile(database, 'tm_b', '10001', environment, apple))
      .rejects.toMatchObject({ status: 403, code: 'app_account_token_mismatch' })
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_b'").membership_tier).toBe('free')
  })

  it('does not let a stale retry regress a newer renewal', async () => {
    const account = await configuration(database, 'tm_a', environment)
    const old = appleFetch(transaction('10002', '90002', account.appAccountToken, PAST))
    const renewed = appleFetch(transaction('10003', '90002', account.appAccountToken, FUTURE, YEARLY))
    await reconcile(database, 'tm_a', '10002', environment, old)
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('free')
    await reconcile(database, 'tm_a', '10003', environment, renewed)
    await reconcile(database, 'tm_a', '10002', environment, old)
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('free')
    expect((await readEffectiveMembership(database as never, 'tm_a', 'Sandbox')).isPremium).toBe(true)
    expect((await readEffectiveMembership(database as never, 'tm_a')).isPremium).toBe(false)
    expect(database.get("SELECT expires_at FROM sandbox_membership_entitlements WHERE id = 'app-store:90002'").expires_at)
      .toBe(new Date(FUTURE).toISOString())
  })

  it('projects expiry and refund/revocation without deleting the account data', async () => {
    const account = await configuration(database, 'tm_a', environment)
    await reconcile(database, 'tm_a', '10004', environment,
      appleFetch(transaction('10004', '90004', account.appAccountToken, FUTURE)))
    await reconcile(database, 'tm_a', '10004', environment,
      appleFetch(transaction('10004', '90004', account.appAccountToken, FUTURE, MONTHLY, Date.now())))
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('free')
    expect(database.get("SELECT status FROM sandbox_membership_entitlements WHERE id = 'app-store:90004'").status).toBe('revoked')
    expect(database.get("SELECT COUNT(*) AS value FROM users WHERE id = 'tm_a'").value).toBe(1)
  })

  it.each(['gift_annual', 'gift_lifetime'])('purchase, refund and repeated reconciliation preserve %s', async (source) => {
    await mutateMembership(database as never, 'tm_b', new Request('https://dev.test', { method: 'POST', body: JSON.stringify({ action: 'grant', userId: 'tm_a', source, note: 'gift' }) }))
    const before = await readEffectiveMembership(database as never, 'tm_a')
    const account = await configuration(database, 'tm_a', environment)
    await reconcile(database, 'tm_a', '100099', environment, appleFetch(transaction('100099', '900099', account.appAccountToken, FUTURE, YEARLY)))
    expect((await readEffectiveMembership(database as never, 'tm_a')).source).toBe(source)
    expect(database.get("SELECT source FROM sandbox_membership_entitlements WHERE id='app-store:900099'").source).toBe('app_store_annual')
    const refunded = appleFetch(transaction('100099', '900099', account.appAccountToken, FUTURE, YEARLY, Date.now()))
    await reconcile(database, 'tm_a', '100099', environment, refunded)
    await reconcile(database, 'tm_a', '100099', environment, refunded)
    const after = await readEffectiveMembership(database as never, 'tm_a')
    expect(after).toMatchObject({ isPremium: true, source, expiresAt: before.expiresAt })
    expect(after.entitlements.find(x => x.source === source)).toEqual(before.entitlements[0])
  })

  it('keeps independent referral rewards after Apple reconciliation and refund',async()=>{
    database.sqlite.prepare(`INSERT INTO membership_entitlements(id,user_id,source,starts_at,expires_at,status,created_at,updated_at)
      VALUES('reward-a','tm_a','referral_reward',?,?,'active',?,?)`).run(new Date().toISOString(),new Date(FUTURE).toISOString(),new Date().toISOString(),new Date().toISOString())
    const account=await configuration(database,'tm_a',environment)
    await reconcile(database,'tm_a','100088',environment,appleFetch(transaction('100088','900088',account.appAccountToken,FUTURE,YEARLY)))
    expect((await readEffectiveMembership(database as never,'tm_a')).source).toBe('referral_reward')
    expect((await readEffectiveMembership(database as never,'tm_a','Sandbox')).source).toBe('app_store_annual')
    await reconcile(database,'tm_a','100088',environment,appleFetch(transaction('100088','900088',account.appAccountToken,FUTURE,YEARLY,Date.now())))
    expect((await readEffectiveMembership(database as never,'tm_a'))).toMatchObject({isPremium:true,source:'referral_reward'})
    expect(database.get("SELECT status FROM membership_entitlements WHERE id='reward-a'").status).toBe('active')
  })

  it('fails closed for bundle, product, environment and missing server secrets', async () => {
    const account = await configuration(database, 'tm_a', environment)
    for (const override of [
      { bundleId: 'com.attacker.fake' },
      { productId: 'fake.product' },

    ]) {
      await expect(reconcile(database, 'tm_a', '10005', environment,
        appleFetch({ ...transaction('10005', '90005', account.appAccountToken, FUTURE), ...override })))
        .rejects.toBeInstanceOf(AppStoreCommerceV1Error)
    }
    const withoutSecrets = { ...environment }
    delete withoutSecrets.APP_STORE_PRIVATE_KEY
    await expect(reconcile(database, 'tm_a', '10005', withoutSecrets,
      appleFetch(transaction('10005', '90005', account.appAccountToken, FUTURE))))
      .rejects.toMatchObject({ status: 503, code: 'app_store_server_not_configured' })
  })

  it('requires a configured Worker but accepts verified Sandbox on a Production host', async () => {
    const account = await configuration(database, 'tm_a', environment)
    const verified = appleFetch(transaction('10008', '90008', account.appAccountToken, FUTURE))
    const withoutAppEnvironment = { ...environment }
    delete withoutAppEnvironment.APP_ENVIRONMENT

    await expect(reconcile(database, 'tm_a', '10008', withoutAppEnvironment, verified))
      .rejects.toMatchObject({ status: 503, code: 'app_environment_not_configured' })
    await expect(reconcile(database, 'tm_a', '10008', {
      ...environment, APP_ENVIRONMENT: 'production', APP_STORE_API_ENVIRONMENT: 'production',
    }, verified)).resolves.toMatchObject({reconciled:true,environment:'Sandbox'})
    expect((await readEffectiveMembership(database as never,'tm_a')).isPremium).toBe(false)
  })

  it.each(['Sandbox','Production'])('reconciles renew, expire and revoke notifications in %s only', async storeEnvironment => {
    const account = await configuration(database,'tm_a',environment)
    for (const [index,type,expiry,revocation,expected] of [
      [0,'DID_RENEW',FUTURE,undefined,true],
      [1,'EXPIRED',PAST,undefined,false],
      [2,'REVOKE',FUTURE,PAST,false],
    ]) {
      const tx = {...transaction(`700${index}`,`800${index}`,account.appAccountToken,expiry,MONTHLY,revocation),environment:storeEnvironment}
      const request = new Request('https://api.tastemap.cn/api/v1/storekit/notifications',{
        method:'POST',body:JSON.stringify({signedPayload:jws({notificationUUID:`event-${index}`,
          notificationType:type,data:{environment:storeEnvironment,bundleId:BUNDLE_ID,signedTransactionInfo:jws(tx)}})}),
      })
      expect(await handleAppStoreServerNotificationV1(request,database,environment,appleFetch(tx)))
        .toMatchObject({accepted:true,linked:true,environment:storeEnvironment})
      const table=storeEnvironment==='Sandbox'?'sandbox_membership_entitlements':'membership_entitlements'
      const row=database.get(`SELECT status,expires_at,revoked_at FROM ${table} WHERE id=?`,`app-store:800${index}`)
      expect(row.status==='active' && !row.revoked_at && Date.parse(row.expires_at)>Date.now()).toBe(expected)
      const other=storeEnvironment==='Sandbox'?'membership_entitlements':'sandbox_membership_entitlements'
      expect(database.get(`SELECT count(*) AS n FROM ${other}`).n).toBe(0)
    }
  })

  it('deduplicates notifications and never links an unknown token to the first user', async () => {
    const account = await configuration(database, 'tm_a', environment)
    const linked = transaction('10006', '90006', account.appAccountToken, FUTURE)
    const body = notification('notification-10006', linked)
    const request = () => new Request('https://development.test/api/v1/storekit/notifications', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    })
    const first = await handleAppStoreServerNotificationV1(request(), database as never, environment, appleFetch(linked))
    const duplicate = await handleAppStoreServerNotificationV1(request(), database as never, environment, appleFetch(linked))
    expect(first).toMatchObject({ accepted: true, linked: true })
    expect(duplicate).toMatchObject({ duplicate: true })
    expect(database.get('SELECT COUNT(*) AS value FROM app_store_notification_events_v2').value).toBe(1)

    const unknown = transaction('10007', '90007', crypto.randomUUID(), FUTURE)
    const unknownRequest = new Request('https://development.test/api/v1/storekit/notifications', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(notification('notification-10007', unknown)),
    })
    expect(await handleAppStoreServerNotificationV1(
      unknownRequest, database as never, environment, appleFetch(unknown),
    )).toMatchObject({ accepted: true, linked: false })
    expect(database.get("SELECT COUNT(*) AS value FROM app_store_transactions_v2 WHERE transaction_id = '10007'").value).toBe(0)
  })
  it('Release production authority falls back only on Apple TransactionIdNotFound and persists Sandbox honestly', async () => {
    const account = await configuration(database,'tm_a',environment)
    const env={...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'}
    const calls:string[]=[]
    const apple=async (url,init)=>{
      calls.push(String(url))
      if(String(url).startsWith('https://api.storekit.apple.com/')) return Response.json({errorCode:4040010},{status:404})
      return appleFetch(transaction('80001','88001',account.appAccountToken,FUTURE))(url,init)
    }
    await reconcile(database,'tm_a','80001',env,apple)
    expect(calls).toHaveLength(2)
    expect(calls[1]).toContain('api.storekit-sandbox.apple.com')
    expect(database.get("SELECT environment FROM app_store_transactions_v2 WHERE transaction_id='80001'").environment).toBe('Sandbox')
    await expect(reconcile(database,'tm_b','80001',env,apple)).rejects.toMatchObject({code:'app_account_token_mismatch'})
    await reconcile(database,'tm_a','80001',env,apple)
    expect(database.get('SELECT COUNT(*) AS n FROM app_store_transactions_v2').n).toBe(1)
  })

  it.each([401,403,429,500,404])('does not turn generic Apple %s into a Sandbox fallback', async status => {
    const calls=vi.fn(async()=>Response.json({errorCode:0},{status}))
    await expect(reconcile(database,'tm_a','80002',{...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'},calls)).rejects.toBeInstanceOf(AppStoreCommerceV1Error)
    expect(calls).toHaveBeenCalledTimes(1)
    expect(database.get('SELECT COUNT(*) AS n FROM app_store_transactions_v2').n).toBe(0)
  })

  it('Production lookup verifies Production only and rejects a mismatched Apple payload', async()=>{
    const a=await configuration(database,'tm_a',environment)
    const env={...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'}
    await reconcile(database,'tm_a','80003',env,appleFetch({...transaction('80003','88003',a.appAccountToken,FUTURE),environment:'Production'}))
    const sandbox=appleFetch(transaction('80004','88004',a.appAccountToken,FUTURE))
    const knownProduction=async()=>Response.json({signedTransactionInfo:sandbox.signedTransactionInfo})
    await expect(reconcile(database,'tm_a','80004',env,knownProduction)).rejects.toMatchObject({code:'apple_environment_mismatch'})
  })

  it('signed Sandbox Release transaction selects Sandbox without a client environment override',async()=>{
    const a=await configuration(database,'tm_a',environment)
    const tx=transaction('80005','88005',a.appAccountToken,FUTURE)
    vi.mocked(verifyAppleSignedData).mockResolvedValue(tx)
    const calls=vi.fn(appleFetch(tx))
    await handleAppStoreCommerceV1(new Request('https://api.tastemap.cn/api/v1/storekit/transactions/reconcile',{
      method:'POST',body:JSON.stringify({transactionId:'80005',signedTransactionInfo:'verified-by-test-double'})
    }),database,'tm_a',{...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'},calls)
    expect(String(calls.mock.calls[0][0])).toContain('api.storekit-sandbox.apple.com')
  })

  it('does not trust a spoofed environment flag or a forged signed transaction',async()=>{
    const calls=vi.fn(async()=>Response.json({errorCode:4040010},{status:401}))
    const request=(extra)=>new Request('https://api.tastemap.cn/api/v1/storekit/transactions/reconcile',{
      method:'POST',body:JSON.stringify({transactionId:'80006',sandbox:true,environment:'Sandbox',...extra})
    })
    const env={...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'}
    await expect(handleAppStoreCommerceV1(request({}),database,'tm_a',env,calls)).rejects.toBeInstanceOf(AppStoreCommerceV1Error)
    expect(calls).not.toHaveBeenCalled()
    calls.mockClear()
    await expect(handleAppStoreCommerceV1(request({environment:undefined,signedTransactionInfo:'forged'}),database,'tm_a',env,calls)).rejects.toBeInstanceOf(AppStoreCommerceV1Error)
    expect(calls).not.toHaveBeenCalled()
  })

  it.each(['invitee', 'referrer_1', 'referrer_2', 'referrer_3', 'referrer_4', 'referrer_5'])('enforces Sandbox assignment ownership and idempotency for %s', async (offer) => {
    const invitee = offer === 'invitee' ? 'tm_a' : 'tm_b'
    const referrer = offer === 'invitee' ? 'tm_b' : 'tm_a'
    database.get(`INSERT INTO referrals(invitee_id,referrer_id,code,bound_at,actor) VALUES(?,?,?,'2020-01-01T00:00:00.000Z','test')`,invitee,referrer,'test-referral')
    database.get(`UPDATE referrals SET status='qualified',slot=?,qualified_at='2020-01-01T00:00:00.000Z',qualifying_visit_id='test-visit' WHERE invitee_id=?`, offer === 'invitee' ? 1 : Number(offer.slice(-1)),invitee)
    const reward = `referral:${invitee}:${offer === 'invitee' ? 'invitee' : 'referrer'}`
    database.get(`UPDATE premium_rewards SET state='active',starts_at='2020-01-01T00:00:00.000Z',expires_at='2099-01-01T00:00:00.000Z' WHERE id=?`,reward)
    database.get(`INSERT INTO sandbox_offer_assignments(assignment_id,user_id,reward_id,offer_identifier,assigned_at) VALUES('assignment','tm_a',?,?,'2020-01-01T00:00:00.000Z')`,reward,offer)
    const a=await configuration(database,'tm_a',environment), b=await configuration(database,'tm_b',environment)
    const offered=(id,original,token)=>({...transaction(id,original,token,FUTURE),offerType:3,offerIdentifier:offer})
    await expect(reconcile(database,'tm_b','12340',environment,appleFetch(offered('12340','92340',b.appAccountToken))))
      .rejects.toMatchObject({code:'sandbox_offer_assignment_mismatch'})
    expect(database.get('SELECT COUNT(*) AS n FROM app_store_transactions_v2').n).toBe(0)
    const races=await Promise.allSettled([
      reconcile(database,'tm_a','12341',environment,appleFetch(offered('12341','92341',a.appAccountToken))),
      reconcile(database,'tm_a','12342',environment,appleFetch(offered('12342','92342',a.appAccountToken))),
    ])
    expect(races.filter(r=>r.status==='fulfilled')).toHaveLength(1)
    const row=database.get("SELECT * FROM sandbox_offer_assignments WHERE assignment_id='assignment'")
    expect(row.state).toBe('redeemed')
    await reconcile(database,'tm_a',row.transaction_id,environment,appleFetch(offered(row.transaction_id,row.original_transaction_id,a.appAccountToken)))
    expect(database.get('SELECT COUNT(*) AS n FROM app_store_transactions_v2').n).toBe(1)
    expect(database.get("SELECT COUNT(*) AS n FROM sandbox_membership_entitlements WHERE source='app_store_monthly'").n).toBe(1)
    expect(database.get('SELECT COUNT(*) AS n FROM membership_entitlements WHERE id=?',reward).n).toBe(1)
  })

  it.each(['DID_RENEW','EXPIRED','REVOKE','REFUND','UNRECOGNIZED_TYPE'])('handles verified %s using current Apple state',async type=>{
    const a=await configuration(database,'tm_a',environment)
    const tx=transaction('81001','89001',a.appAccountToken,
      type==='EXPIRED'?PAST:FUTURE,MONTHLY,['REVOKE','REFUND'].includes(type)?Date.now():undefined)
    const payload={notificationUUID:'lifecycle-'+type,notificationType:type,data:{environment:'Sandbox',signedTransactionInfo:jws(tx)}}
    const request=()=>new Request('https://api.tastemap.cn/api/v1/storekit/notifications',{method:'POST',body:JSON.stringify({signedPayload:jws(payload)})})
    const env={...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'}
    await handleAppStoreServerNotificationV1(request(),database,env,appleFetch(tx))
    expect((await handleAppStoreServerNotificationV1(request(),database,env,appleFetch(tx))).duplicate).toBe(true)
    const active=['DID_RENEW','UNRECOGNIZED_TYPE'].includes(type)
    expect((await readEffectiveMembership(database,'tm_a','Sandbox')).isPremium).toBe(active)
    expect(database.get("SELECT membership_tier FROM users WHERE id='tm_a'").membership_tier).toBe('free')
  })

  it.each(['TEST','NEW_UNKNOWN_EVENT'])('acknowledges and deduplicates verified %s without any entitlement mutation',async type=>{
    const request=()=>new Request('https://api.tastemap.cn/api/v1/storekit/notifications',{method:'POST',body:JSON.stringify({signedPayload:jws({notificationUUID:'notification-'+type,notificationType:type,data:{environment:'Sandbox'}})})})
    const apple=vi.fn()
    expect((await handleAppStoreServerNotificationV1(request(),database,environment,apple)).accepted).toBe(true)
    expect((await handleAppStoreServerNotificationV1(request(),database,environment,apple)).duplicate).toBe(true)
    expect(apple).not.toHaveBeenCalled()
    expect(database.get('SELECT COUNT(*) AS n FROM membership_entitlements').n).toBe(0)
  })

  it('cannot overwrite a Sandbox transaction or subscription with a Production environment',async()=>{
    const a=await configuration(database,'tm_a',environment)
    const tx=transaction('81002','89002',a.appAccountToken,FUTURE)
    await reconcile(database,'tm_a','81002',environment,appleFetch(tx))
    await reconcile(database,'tm_a','81002',{...environment,APP_ENVIRONMENT:'production',APP_STORE_API_ENVIRONMENT:'production'},appleFetch({...tx,environment:'Production'}))
    expect(database.get("SELECT count(*) AS n FROM app_store_transactions_v2 WHERE transaction_id='81002'").n).toBe(2)
    expect(database.get("SELECT environment FROM app_store_transactions_v2 WHERE transaction_id='81002' AND environment='Sandbox'").environment).toBe('Sandbox')
  })
})

async function configuration(database: SQLiteD1Database, userId: string, environment: Record<string, string>) {
  return handleAppStoreCommerceV1(
    new Request('https://development.test/api/v1/storekit/config'),
    database as never, userId, environment,
  ) as Promise<any>
}

async function reconcile(
  database: SQLiteD1Database, userId: string, id: string,
  environment: Record<string, string>, fetcher: typeof fetch,
) {
  return handleAppStoreCommerceV1(new Request(
    'https://development.test/api/v1/storekit/transactions/reconcile',
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ transactionId: id, signedTransactionInfo: fetcher.signedTransactionInfo }) },
  ), database as never, userId, environment, fetcher) as Promise<any>
}

function transaction(
  transactionId: string, originalTransactionId: string, appAccountToken: string,
  expiresDate: number, productId = MONTHLY, revocationDate?: number,
) {
  return {
    transactionId, originalTransactionId, bundleId: BUNDLE_ID, productId,
    appAccountToken, type: 'Auto-Renewable Subscription', environment: 'Sandbox',
    purchaseDate: Date.parse('2026-01-01T00:00:00.000Z'),
    originalPurchaseDate: Date.parse('2026-01-01T00:00:00.000Z'),
    expiresDate, ...(revocationDate ? { revocationDate, revocationReason: 1 } : {}),
  }
}

function appleFetch(payload: Record<string, unknown>): typeof fetch {
  const fn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    expect(String(input)).toContain(payload.environment === 'Sandbox' ? 'api.storekit-sandbox.apple.com' : 'api.storekit.apple.com')
    expect((init?.headers as Record<string, string>)?.Authorization).toMatch(/^Bearer ey/)
    return Response.json({ signedTransactionInfo: jws(payload) })
  }) as typeof fetch
  fn.signedTransactionInfo=jws(payload)
  return fn
}

function notification(notificationUUID: string, payload: Record<string, unknown>) {
  return { signedPayload: jws({
    notificationUUID, notificationType: 'DID_RENEW',
    data: { environment: payload.environment, bundleId: BUNDLE_ID, signedTransactionInfo: jws(payload) },
  }) }
}

function jws(payload: Record<string, unknown>) {
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `eyJhbGciOiJFUzI1NiJ9.${encoded}.development-signature`
}

function seedUser(database: SQLiteD1Database, id: string) {
  const now = new Date().toISOString()
  database.get(`INSERT INTO users (id, auth_provider, nickname, created_at, updated_at)
    VALUES (?, 'apple', ?, ?, ?)`, id, id, now, now)
}

function seedSession(database: SQLiteD1Database,id:string,userID:string) {
  const token=`tm_access_${id.padEnd(40,'x')}`
  const now=new Date().toISOString(),end=new Date(FUTURE).toISOString()
  database.sqlite.prepare(`INSERT INTO auth_sessions(id,user_id,access_token_hash,access_expires_at,refresh_token_hash,refresh_expires_at,created_at,updated_at,last_used_at)
    VALUES(?,?,?,?,?,?,?,?,?)`).run(id,userID,createHash('sha256').update(token).digest('hex'),end,`refresh-${id}`,end,now,now,now)
  return token
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  applyAllMigrations(sqlite)
  return new SQLiteD1Database(sqlite)
}

class SQLiteD1Database {
  constructor(private sqlite: DatabaseSync) {}
  prepare(sql: string) { return new SQLiteD1Statement(this.sqlite, sql) }
  get(sql: string, ...values: any[]) { return this.sqlite.prepare(sql).get(...values) as Record<string, any> }
}

class SQLiteD1Statement {
  constructor(private sqlite: DatabaseSync, private sql: string, private values: any[] = []) {}
  bind(...values: any[]) { return new SQLiteD1Statement(this.sqlite, this.sql, values) }
  async first<T>() { return (this.sqlite.prepare(this.sql).get(...this.values) ?? null) as T | null }
  async all<T>() { return { results: this.sqlite.prepare(this.sql).all(...this.values) as T[], success: true, meta: {} } }
  async run() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes) } }
  }
}
