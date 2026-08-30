// @ts-nocheck -- Vitest executes this Node-only D1 adapter; the Worker tsconfig
// intentionally excludes Node type declarations.
import { generateKeyPairSync } from 'node:crypto'
import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import {
  AppStoreCommerceV1Error,
  handleAppStoreCommerceV1,
  handleAppStoreServerNotificationV1,
} from './appStoreCommerceV1'
import { applyAllMigrations } from './testSupport/migrations.js'

const BUNDLE_ID = 'com.lafayette.tastemap'
const MONTHLY = 'dev.tastemap.storekit.monthly'
const YEARLY = 'dev.tastemap.storekit.yearly'
const FUTURE = Date.parse('2099-01-01T00:00:00.000Z')
const PAST = Date.parse('2020-01-01T00:00:00.000Z')

describe('App Store commerce V1 integration', () => {
  let database: SQLiteD1Database
  let environment: Record<string, string>

  beforeEach(() => {
    database = makeDatabase()
    seedUser(database, 'tm_a')
    seedUser(database, 'tm_b')
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
    environment = {
      APP_ENVIRONMENT: 'development',
      APP_STORE_BUNDLE_ID: BUNDLE_ID,
      APP_STORE_MONTHLY_PRODUCT_ID: MONTHLY,
      APP_STORE_YEARLY_PRODUCT_ID: YEARLY,
      APP_STORE_API_ENVIRONMENT: 'sandbox',
      APP_STORE_ISSUER_ID: 'development-issuer',
      APP_STORE_KEY_ID: 'DEVKEY123',
      APP_STORE_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    }
  })

  it('issues a stable, isolated appAccountToken and exposes no fake price', async () => {
    const a = await configuration(database, 'tm_a', environment)
    const repeated = await configuration(database, 'tm_a', environment)
    const b = await configuration(database, 'tm_b', environment)
    expect(a).toEqual(repeated)
    expect(a.appAccountToken).not.toBe(b.appAccountToken)
    expect(a.products).toEqual([
      { id: MONTHLY, period: 'monthly' },
      { id: YEARLY, period: 'annual' },
    ])
    expect(JSON.stringify(a)).not.toContain('price')
  })

  it('reconciles verified Apple data idempotently and rejects cross-user claims', async () => {
    const account = await configuration(database, 'tm_a', environment)
    const apple = appleFetch(transaction('10001', '90001', account.appAccountToken, FUTURE))
    const first = await reconcile(database, 'tm_a', '10001', environment, apple)
    const retry = await reconcile(database, 'tm_a', '10001', environment, apple)
    expect(first).toEqual(retry)
    expect(database.get('SELECT COUNT(*) AS value FROM app_store_transactions').value).toBe(1)
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('member')
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
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('member')
    expect(database.get("SELECT expires_at FROM membership_entitlements WHERE id = 'app-store:90002'").expires_at)
      .toBe(new Date(FUTURE).toISOString())
  })

  it('projects expiry and refund/revocation without deleting the account data', async () => {
    const account = await configuration(database, 'tm_a', environment)
    await reconcile(database, 'tm_a', '10004', environment,
      appleFetch(transaction('10004', '90004', account.appAccountToken, FUTURE)))
    await reconcile(database, 'tm_a', '10004', environment,
      appleFetch(transaction('10004', '90004', account.appAccountToken, FUTURE, MONTHLY, Date.now())))
    expect(database.get("SELECT membership_tier FROM users WHERE id = 'tm_a'").membership_tier).toBe('free')
    expect(database.get("SELECT status FROM membership_entitlements WHERE id = 'app-store:90004'").status).toBe('revoked')
    expect(database.get("SELECT COUNT(*) AS value FROM users WHERE id = 'tm_a'").value).toBe(1)
  })

  it('fails closed for bundle, product, environment and missing server secrets', async () => {
    const account = await configuration(database, 'tm_a', environment)
    for (const override of [
      { bundleId: 'com.attacker.fake' },
      { productId: 'fake.product' },
      { environment: 'Production' },
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
    expect(database.get('SELECT COUNT(*) AS value FROM app_store_notification_events').value).toBe(1)

    const unknown = transaction('10007', '90007', crypto.randomUUID(), FUTURE)
    const unknownRequest = new Request('https://development.test/api/v1/storekit/notifications', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(notification('notification-10007', unknown)),
    })
    expect(await handleAppStoreServerNotificationV1(
      unknownRequest, database as never, environment, appleFetch(unknown),
    )).toMatchObject({ accepted: true, linked: false })
    expect(database.get("SELECT COUNT(*) AS value FROM app_store_transactions WHERE transaction_id = '10007'").value).toBe(0)
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
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ transactionId: id }) },
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
  return (async (_input: RequestInfo | URL, init?: RequestInit) => {
    expect((init?.headers as Record<string, string>)?.Authorization).toMatch(/^Bearer ey/)
    return Response.json({ signedTransactionInfo: jws(payload) })
  }) as typeof fetch
}

function notification(notificationUUID: string, payload: Record<string, unknown>) {
  return { signedPayload: jws({
    notificationUUID, notificationType: 'DID_RENEW',
    data: { signedTransactionInfo: jws(payload) },
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
