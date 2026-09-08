export const APP_STORE_COMMERCE_API_VERSION = 1 as const

const APP_STORE_PRODUCTION_API = 'https://api.storekit.apple.com'
const APP_STORE_SANDBOX_API = 'https://api.storekit-sandbox.apple.com'
const APP_STORE_JWT_AUDIENCE = 'appstoreconnect-v1'
const APP_STORE_SUBSCRIPTION_TYPE = 'Auto-Renewable Subscription'

export interface AppStoreCommerceEnvironment {
  APP_ENVIRONMENT?: 'development' | 'production'
  APP_STORE_BUNDLE_ID?: string
  APP_STORE_MONTHLY_PRODUCT_ID?: string
  APP_STORE_YEARLY_PRODUCT_ID?: string
  APP_STORE_API_ENVIRONMENT?: 'sandbox' | 'production'
  APP_STORE_ISSUER_ID?: string
  APP_STORE_KEY_ID?: string
  APP_STORE_PRIVATE_KEY?: string
}

interface AppStoreTransactionInfoResponse {
  signedTransactionInfo?: string
}

interface AppStoreTransactionPayload {
  transactionId?: string
  originalTransactionId?: string
  bundleId?: string
  productId?: string
  appAccountToken?: string
  type?: string
  environment?: string
  purchaseDate?: number
  originalPurchaseDate?: number
  expiresDate?: number
  revocationDate?: number
  revocationReason?: number
  inAppOwnershipType?: string
  transactionReason?: string
  offerType?: number
  offerIdentifier?: string
}

interface AppStoreNotificationPayload {
  notificationUUID?: string
  notificationType?: string
  subtype?: string
  data?: {
    signedTransactionInfo?: string
  }
}

interface AppStoreTransactionRow {
  transaction_id: string
  original_transaction_id: string
  user_id: string
  product_id: string
  purchase_at: string
  original_purchase_at: string | null
  expires_at: string | null
  revocation_at: string | null
  verified_at: string
}

interface AppStoreAccountRow {
  user_id: string
  app_account_token: string
}

interface AppStoreOwnerRow {
  original_transaction_id: string
  user_id: string
  app_account_token: string
}

export class AppStoreCommerceV1Error extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message)
    this.name = 'AppStoreCommerceV1Error'
  }
}

export async function handleAppStoreCommerceV1(
  request: Request,
  database: D1Database,
  userId: string,
  environment: AppStoreCommerceEnvironment,
  appleFetch: typeof fetch = fetch,
) {
  const url = new URL(request.url)
  if (url.pathname === '/api/v1/storekit/config' && request.method === 'GET') {
    const products = configuredProducts(environment)
    const account = await ensureAppStoreAccount(database, userId)
    let purchaseReady = false
    try { requireServerConfiguration(environment); purchaseReady = true } catch { /* Catalog remains readable before server credentials are configured. */ }
    return {
      apiVersion: APP_STORE_COMMERCE_API_VERSION,
      configured: products.length > 0,
      purchaseReady,
      appAccountToken: account.app_account_token,
      products,
    }
  }

  if (url.pathname === '/api/v1/storekit/transactions/reconcile' && request.method === 'POST') {
    const body = await request.json().catch(() => null) as Record<string, unknown> | null
    const transactionId = typeof body?.transactionId === 'string' ? body.transactionId.trim() : ''
    if (!/^\d{1,32}$/.test(transactionId)) {
      throw commerceError('交易标识无效。', 400, 'invalid_transaction_id')
    }
    const result = await verifyAndReconcileTransaction(
      database, userId, transactionId, environment, appleFetch,
    )
    return { apiVersion: APP_STORE_COMMERCE_API_VERSION, ...result }
  }

  throw commerceError('没有找到这个 StoreKit API。', 404, 'storekit_route_not_found')
}

export async function handleAppStoreServerNotificationV1(
  request: Request,
  database: D1Database,
  environment: AppStoreCommerceEnvironment,
  appleFetch: typeof fetch = fetch,
) {
  if (request.method !== 'POST') {
    throw commerceError('StoreKit notification method is not supported.', 405, 'method_not_allowed')
  }
  const contentLength = Number(request.headers.get('content-length') ?? 0)
  if (contentLength > 512_000) {
    throw commerceError('StoreKit notification is too large.', 413, 'notification_too_large')
  }
  const body = await request.json().catch(() => null) as Record<string, unknown> | null
  const signedPayload = typeof body?.signedPayload === 'string' ? body.signedPayload : ''
  if (!signedPayload) {
    throw commerceError('StoreKit notification payload is missing.', 400, 'missing_signed_payload')
  }

  // The decoded notification is routing evidence only. No entitlement decision
  // trusts it. The transaction is fetched again from Apple's authenticated API.
  const notification = decodeJWSPayload<AppStoreNotificationPayload>(signedPayload)
  const nested = notification.data?.signedTransactionInfo
  const hintedTransaction = nested ? decodeJWSPayload<AppStoreTransactionPayload>(nested) : null
  const transactionId = hintedTransaction?.transactionId?.trim() ?? ''
  const notificationUUID = notification.notificationUUID?.trim() ?? ''
  if (!/^\d{1,32}$/.test(transactionId) || !isSafeIdentifier(notificationUUID)) {
    throw commerceError('StoreKit notification does not identify a transaction.', 400, 'invalid_notification')
  }

  const existing = await database.prepare(
    'SELECT notification_uuid FROM app_store_notification_events WHERE notification_uuid = ?',
  ).bind(notificationUUID).first()
  if (existing) return { apiVersion: APP_STORE_COMMERCE_API_VERSION, duplicate: true }

  const verified = await fetchVerifiedTransaction(transactionId, environment, appleFetch)
  const account = await database.prepare(
    'SELECT user_id, app_account_token FROM app_store_accounts WHERE app_account_token = ?',
  ).bind(normalizeUUID(verified.appAccountToken ?? '')).first<AppStoreAccountRow>()
  if (!account) {
    // Never auto-claim an App Store purchase to an arbitrary or first user.
    return { apiVersion: APP_STORE_COMMERCE_API_VERSION, accepted: true, linked: false }
  }
  const result = await reconcileVerifiedTransaction(database, account.user_id, verified, environment)
  await database.prepare(`INSERT INTO app_store_notification_events (
    notification_uuid, notification_type, subtype, transaction_id, signed_payload_digest, processed_at
  ) VALUES (?, ?, ?, ?, ?, ?)`)
    .bind(
      notificationUUID,
      safeText(notification.notificationType, 80) || 'UNKNOWN',
      safeText(notification.subtype, 80) || null,
      transactionId,
      await sha256(signedPayload),
      new Date().toISOString(),
    ).run()
  return { apiVersion: APP_STORE_COMMERCE_API_VERSION, accepted: true, linked: true, ...result }
}

export async function verifyAndReconcileTransaction(
  database: D1Database,
  userId: string,
  transactionId: string,
  environment: AppStoreCommerceEnvironment,
  appleFetch: typeof fetch = fetch,
) {
  const transaction = await fetchVerifiedTransaction(transactionId, environment, appleFetch)
  return reconcileVerifiedTransaction(database, userId, transaction, environment)
}

export async function fetchVerifiedTransaction(
  transactionId: string,
  environment: AppStoreCommerceEnvironment,
  appleFetch: typeof fetch,
) {
  const configuration = requireServerConfiguration(environment)
  const token = await createAppStoreServerJWT(configuration)
  const baseURL = configuration.apiEnvironment === 'sandbox'
    ? APP_STORE_SANDBOX_API
    : APP_STORE_PRODUCTION_API
  const response = await appleFetch(
    `${baseURL}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
    { headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' } },
  )
  if (response.status === 404) {
    throw commerceError('Apple 没有找到这笔交易。', 404, 'apple_transaction_not_found')
  }
  if (!response.ok) {
    throw commerceError('Apple 交易验证暂时不可用。', 503, 'apple_verification_unavailable')
  }
  const result = await response.json() as AppStoreTransactionInfoResponse
  if (!result.signedTransactionInfo) {
    throw commerceError('Apple 交易验证响应不完整。', 502, 'invalid_apple_response')
  }
  const transaction = decodeJWSPayload<AppStoreTransactionPayload>(result.signedTransactionInfo)
  validateAppleTransaction(transaction, configuration)
  if (transaction.transactionId !== transactionId) {
    throw commerceError('Apple 返回了不匹配的交易。', 409, 'transaction_mismatch')
  }
  return { ...transaction, signedTransactionInfo: result.signedTransactionInfo }
}

async function reconcileVerifiedTransaction(
  database: D1Database,
  userId: string,
  transaction: AppStoreTransactionPayload & { signedTransactionInfo: string },
  environment: AppStoreCommerceEnvironment,
) {
  const configuration = requireCatalogConfiguration(environment)
  const account = await ensureAppStoreAccount(database, userId)
  const transactionToken = normalizeUUID(transaction.appAccountToken ?? '')
  if (transactionToken !== account.app_account_token) {
    throw commerceError('这笔购买不属于当前 Taste Map 账户。', 403, 'app_account_token_mismatch')
  }

  const originalTransactionId = transaction.originalTransactionId as string
  const existingOwner = await database.prepare(`SELECT original_transaction_id, user_id, app_account_token
    FROM app_store_subscription_owners WHERE original_transaction_id = ?`)
    .bind(originalTransactionId).first<AppStoreOwnerRow>()
  if (existingOwner &&
      (existingOwner.user_id !== userId || existingOwner.app_account_token !== account.app_account_token)) {
    throw commerceError('这组 App Store 订阅已关联其他 Taste Map 账户。', 409, 'subscription_owner_conflict')
  }

  const now = new Date().toISOString()
  await database.prepare(`INSERT INTO app_store_subscription_owners (
    original_transaction_id, user_id, app_account_token, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?)
  ON CONFLICT(original_transaction_id) DO UPDATE SET updated_at = excluded.updated_at
  WHERE app_store_subscription_owners.user_id = excluded.user_id
    AND app_store_subscription_owners.app_account_token = excluded.app_account_token`)
    .bind(originalTransactionId, userId, account.app_account_token, now, now).run()

  await database.prepare(`INSERT INTO app_store_transactions (
    transaction_id, original_transaction_id, user_id, app_account_token, product_id, environment,
    purchase_at, original_purchase_at, expires_at, revocation_at, revocation_reason,
    ownership_type, transaction_reason, signed_transaction_digest, verification_source,
    verified_at, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'app_store_server_api', ?, ?, ?)
  ON CONFLICT(transaction_id) DO UPDATE SET
    expires_at = excluded.expires_at,
    revocation_at = excluded.revocation_at,
    revocation_reason = excluded.revocation_reason,
    ownership_type = excluded.ownership_type,
    transaction_reason = excluded.transaction_reason,
    signed_transaction_digest = excluded.signed_transaction_digest,
    verification_source = excluded.verification_source,
    verified_at = excluded.verified_at,
    updated_at = excluded.updated_at
  WHERE app_store_transactions.user_id = excluded.user_id
    AND app_store_transactions.original_transaction_id = excluded.original_transaction_id`)
    .bind(
      transaction.transactionId,
      originalTransactionId,
      userId,
      account.app_account_token,
      transaction.productId,
      transaction.environment,
      millisecondsISO(transaction.purchaseDate),
      optionalMillisecondsISO(transaction.originalPurchaseDate),
      optionalMillisecondsISO(transaction.expiresDate),
      optionalMillisecondsISO(transaction.revocationDate),
      transaction.revocationReason == null ? null : String(transaction.revocationReason),
      safeText(transaction.inAppOwnershipType, 40) || null,
      safeText(transaction.transactionReason, 40) || null,
      await sha256(transaction.signedTransactionInfo),
      now,
      now,
      now,
    ).run()

  await reconcileMembershipProjection(database, userId, originalTransactionId, configuration)
  return {
    reconciled: true,
    transactionId: transaction.transactionId as string,
    originalTransactionId,
  }
}

async function reconcileMembershipProjection(
  database: D1Database,
  userId: string,
  originalTransactionId: string,
  configuration: ReturnType<typeof requireCatalogConfiguration>,
) {
  const result = await database.prepare(`SELECT transaction_id, original_transaction_id, user_id,
      product_id, purchase_at, original_purchase_at, expires_at, revocation_at, verified_at
    FROM app_store_transactions WHERE original_transaction_id = ? AND user_id = ?
    ORDER BY COALESCE(expires_at, purchase_at) DESC, purchase_at DESC`)
    .bind(originalTransactionId, userId).all<AppStoreTransactionRow>()
  if (result.results.length === 0) return

  const nowMilliseconds = Date.now()
  const usable = result.results.filter((item) => item.revocation_at === null &&
    item.expires_at !== null && new Date(item.expires_at).getTime() > nowMilliseconds)
  const current = usable[0] ?? result.results[0]
  const source = current.product_id === configuration.monthlyProductId
    ? 'app_store_monthly'
    : 'app_store_annual'
  const status = usable.length > 0 ? 'active' : result.results.every((item) => item.revocation_at !== null)
    ? 'revoked'
    : 'active'
  const startsAt = current.original_purchase_at ?? current.purchase_at
  const expiresAt = usable[0]?.expires_at ?? current.expires_at
  const metadata = JSON.stringify({
    originalTransactionId,
    latestTransactionId: current.transaction_id,
    productId: current.product_id,
    verificationSource: 'app_store_server_api',
  })
  const entitlementId = `app-store:${originalTransactionId}`
  const now = new Date().toISOString()
  await database.prepare(`INSERT INTO membership_entitlements (
    id, user_id, source, starts_at, expires_at, is_lifetime, status, note, metadata_json,
    created_by_user_id, created_at, updated_at, revoked_at, revoked_by_user_id
  ) VALUES (?, ?, ?, ?, ?, 0, ?, '', ?, NULL, ?, ?, ?, NULL)
  ON CONFLICT(id) DO UPDATE SET
    source = excluded.source,
    starts_at = excluded.starts_at,
    expires_at = excluded.expires_at,
    status = excluded.status,
    metadata_json = excluded.metadata_json,
    updated_at = excluded.updated_at,
    revoked_at = excluded.revoked_at,
    revoked_by_user_id = NULL
  WHERE membership_entitlements.user_id = excluded.user_id`)
    .bind(
      entitlementId, userId, source, startsAt, expiresAt, status, metadata, now, now,
      status === 'revoked' ? now : null,
    ).run()
  await refreshUserMembershipTier(database, userId)
}

async function refreshUserMembershipTier(database: D1Database, userId: string) {
  const now = new Date().toISOString()
  const active = await database.prepare(`SELECT id FROM membership_entitlements
    WHERE user_id = ? AND status = 'active' AND starts_at <= ?
      AND (is_lifetime = 1 OR (expires_at IS NOT NULL AND expires_at > ?))
    LIMIT 1`).bind(userId, now, now).first()
  await database.prepare('UPDATE users SET membership_tier = ?, updated_at = ? WHERE id = ?')
    .bind(active ? 'member' : 'free', now, userId).run()
}

async function ensureAppStoreAccount(database: D1Database, userId: string) {
  const existing = await database.prepare(`SELECT user_id, app_account_token
    FROM app_store_accounts WHERE user_id = ?`).bind(userId).first<AppStoreAccountRow>()
  if (existing) return existing
  const token = crypto.randomUUID().toLowerCase()
  const now = new Date().toISOString()
  await database.prepare(`INSERT OR IGNORE INTO app_store_accounts (
    user_id, app_account_token, created_at, updated_at
  ) VALUES (?, ?, ?, ?)`)
    .bind(userId, token, now, now).run()
  const created = await database.prepare(`SELECT user_id, app_account_token
    FROM app_store_accounts WHERE user_id = ?`).bind(userId).first<AppStoreAccountRow>()
  if (!created) throw commerceError('无法建立 App Store 账户映射。', 500, 'account_mapping_failed')
  return created
}

function configuredProducts(environment: AppStoreCommerceEnvironment) {
  const configuration = optionalCatalogConfiguration(environment)
  if (!configuration) return []
  return [
    { id: configuration.monthlyProductId, period: 'monthly' as const },
    { id: configuration.yearlyProductId, period: 'annual' as const },
  ]
}

function optionalCatalogConfiguration(environment: AppStoreCommerceEnvironment) {
  const monthlyProductId = environment.APP_STORE_MONTHLY_PRODUCT_ID?.trim() ?? ''
  const yearlyProductId = environment.APP_STORE_YEARLY_PRODUCT_ID?.trim() ?? ''
  const bundleId = environment.APP_STORE_BUNDLE_ID?.trim() ?? ''
  if (!monthlyProductId && !yearlyProductId && !bundleId) return null
  if (!isProductIdentifier(monthlyProductId) || !isProductIdentifier(yearlyProductId) ||
      bundleId !== 'com.lafayette.tastemap' || monthlyProductId === yearlyProductId) {
    throw commerceError('StoreKit 商品配置不完整。', 503, 'storekit_catalog_not_configured')
  }
  return { monthlyProductId, yearlyProductId, bundleId }
}

function requireCatalogConfiguration(environment: AppStoreCommerceEnvironment) {
  const configuration = optionalCatalogConfiguration(environment)
  if (!configuration) {
    throw commerceError('StoreKit 商品尚未配置。', 503, 'storekit_catalog_not_configured')
  }
  return configuration
}

function requireServerConfiguration(environment: AppStoreCommerceEnvironment) {
  const catalog = requireCatalogConfiguration(environment)
  const issuerId = environment.APP_STORE_ISSUER_ID?.trim() ?? ''
  const keyId = environment.APP_STORE_KEY_ID?.trim() ?? ''
  const privateKey = environment.APP_STORE_PRIVATE_KEY?.trim() ?? ''
  const apiEnvironment = environment.APP_STORE_API_ENVIRONMENT
  if (!isSafeIdentifier(issuerId) || !isSafeIdentifier(keyId) ||
      !privateKey.includes('BEGIN PRIVATE KEY') ||
      (apiEnvironment !== 'sandbox' && apiEnvironment !== 'production')) {
    throw commerceError('App Store Server API 尚未安全配置。', 503, 'app_store_server_not_configured')
  }
  if (environment.APP_ENVIRONMENT !== 'development' && environment.APP_ENVIRONMENT !== 'production') {
    throw commerceError('Worker 发布环境尚未明确配置。', 503, 'app_environment_not_configured')
  }
  if (environment.APP_ENVIRONMENT === 'development' && apiEnvironment !== 'sandbox') {
    throw commerceError('Development 只能验证 Sandbox 交易。', 503, 'unsafe_store_environment')
  }
  if (environment.APP_ENVIRONMENT === 'production' && apiEnvironment !== 'production') {
    throw commerceError('Production 只能验证 Production 交易。', 503, 'unsafe_store_environment')
  }
  return { ...catalog, issuerId, keyId, privateKey, apiEnvironment }
}

function validateAppleTransaction(
  transaction: AppStoreTransactionPayload,
  configuration: ReturnType<typeof requireServerConfiguration>,
) {
  if (!/^\d{1,32}$/.test(transaction.transactionId ?? '') ||
      !/^\d{1,32}$/.test(transaction.originalTransactionId ?? '') ||
      transaction.bundleId !== configuration.bundleId ||
      ![configuration.monthlyProductId, configuration.yearlyProductId].includes(transaction.productId ?? '') ||
      transaction.type !== APP_STORE_SUBSCRIPTION_TYPE ||
      !isUUID(transaction.appAccountToken ?? '') ||
      !Number.isFinite(transaction.purchaseDate) ||
      !Number.isFinite(transaction.expiresDate)) {
    throw commerceError('Apple 交易内容不符合 Taste Map 商品合同。', 422, 'invalid_apple_transaction')
  }
  const expectedEnvironment = configuration.apiEnvironment === 'sandbox' ? 'Sandbox' : 'Production'
  if (transaction.environment !== expectedEnvironment) {
    throw commerceError('Apple 交易环境不匹配。', 409, 'apple_environment_mismatch')
  }
}

async function createAppStoreServerJWT(
  configuration: ReturnType<typeof requireServerConfiguration>,
  now = new Date(),
) {
  const header = base64URL(JSON.stringify({ alg: 'ES256', kid: configuration.keyId, typ: 'JWT' }))
  const issuedAt = Math.floor(now.getTime() / 1000)
  const payload = base64URL(JSON.stringify({
    iss: configuration.issuerId,
    iat: issuedAt,
    exp: issuedAt + 300,
    aud: APP_STORE_JWT_AUDIENCE,
    bid: configuration.bundleId,
  }))
  const signingInput = `${header}.${payload}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemBytes(configuration.privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  ).catch(() => {
    throw commerceError('App Store Server API 私钥无效。', 503, 'invalid_app_store_private_key')
  })
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  )
  return `${signingInput}.${base64URL(new Uint8Array(signature))}`
}

function decodeJWSPayload<T>(value: string): T {
  const parts = value.split('.')
  if (parts.length !== 3 || parts.some((item) => !item)) {
    throw commerceError('签名数据格式无效。', 400, 'invalid_jws')
  }
  try {
    return JSON.parse(new TextDecoder().decode(base64URLBytes(parts[1]))) as T
  } catch {
    throw commerceError('签名数据内容无效。', 400, 'invalid_jws_payload')
  }
}

function pemBytes(value: string) {
  const normalized = value.replace(/\\n/g, '\n')
  const base64 = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  if (!base64) throw commerceError('App Store Server API 私钥无效。', 503, 'invalid_app_store_private_key')
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))
}

function base64URL(value: string | Uint8Array) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

function base64URLBytes(value: string) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0))
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function millisecondsISO(value: number | undefined) {
  if (!Number.isFinite(value)) throw commerceError('Apple 交易日期无效。', 422, 'invalid_transaction_date')
  return new Date(value as number).toISOString()
}

function optionalMillisecondsISO(value: number | undefined) {
  return value == null ? null : millisecondsISO(value)
}

function normalizeUUID(value: string) {
  return value.trim().toLowerCase()
}

function isUUID(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

function isProductIdentifier(value: string) {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{2,199}$/.test(value)
}

function isSafeIdentifier(value: string) {
  return /^[A-Za-z0-9:_-]{1,160}$/.test(value)
}

function safeText(value: string | undefined, maximum: number) {
  return typeof value === 'string' ? value.trim().slice(0, maximum) : ''
}

function commerceError(message: string, status: number, code: string) {
  return new AppStoreCommerceV1Error(message, status, code)
}
