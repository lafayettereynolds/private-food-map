import type {
  AppleTokenExchangeRequestV1,
  AuthChallengeResponseV1,
  AuthSessionResponseV1,
  LogoutRequestV1,
  RefreshSessionRequestV1,
} from '../src/contracts/authV1'
import { AUTH_API_VERSION } from '../src/contracts/authV1'

const APPLE_ISSUER = 'https://appleid.apple.com'
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys'
const CHALLENGE_LIFETIME_MS = 10 * 60 * 1000
const ACCESS_LIFETIME_MS = 15 * 60 * 1000
const REFRESH_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000
const CLOCK_SKEW_SECONDS = 60

export interface AuthV1Env {
  DB: D1Database
  APPLE_CLIENT_IDS?: string
}

export interface AuthenticatedUser {
  id: string
  email: string | null
  sessionId?: string
  authenticatedAt?: string
  storeEnvironment?: 'Sandbox' | 'Production'
}

interface AuthDependencies {
  now?: () => Date
  verifyAppleToken?: typeof verifyAppleIdentityToken
}

interface AppleClaims {
  iss: string
  aud: string | string[]
  exp: number
  iat?: number
  nbf?: number
  sub: string
  nonce: string
  email?: string
}

interface AppleJWK extends JsonWebKey {
  alg?: string
  kid?: string
}

interface AppleJWKSet {
  keys: AppleJWK[]
}

interface ChallengeRow {
  state_hash: string
  nonce_hash: string
  expires_at: string
  used_at: string | null
}

interface IdentityRow {
  id: string
  user_id: string
  email: string | null
}

interface SessionRow {
  id: string
  user_id: string
  email: string | null
  access_token_hash: string
  access_expires_at: string
  refresh_token_hash: string
  refresh_expires_at: string
  refresh_generation: number
  revoked_at: string | null
  created_at: string
  store_environment?: 'Sandbox' | 'Production'
}

interface HistoryRow {
  session_id: string
}

let cachedAppleKeys: { expiresAt: number; value: AppleJWKSet } | null = null

export class AuthV1RequestError extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message)
    this.name = 'AuthV1RequestError'
  }
}

import { registrationReferral } from './referralsV1'

export async function handleAuthV1Request(
  request: Request,
  env: AuthV1Env,
  dependencies: AuthDependencies = {},
): Promise<unknown> {
  const path = new URL(request.url).pathname
  const now = dependencies.now?.() ?? new Date()
  if (path === '/api/v1/auth/challenge' && request.method === 'POST') {
    return createChallenge(env.DB, now)
  }
  if (path === '/api/v1/auth/apple/exchange' && request.method === 'POST') {
    return exchangeAppleToken(env, request, now, dependencies.verifyAppleToken ?? verifyAppleIdentityToken)
  }
  if (path === '/api/v1/auth/refresh' && request.method === 'POST') {
    return refreshSession(env.DB, request, now)
  }
  if (path === '/api/v1/auth/logout' && request.method === 'POST') {
    return logoutSession(env.DB, request, now)
  }
  throw new AuthV1RequestError('Authentication route not found.', 404, 'route_not_found')
}

export async function authenticateAccessToken(request: Request, database: D1Database, now = new Date()): Promise<AuthenticatedUser | null> {
  const header = request.headers.get('Authorization')
  if (!header) return null
  const match = /^Bearer\s+(.+)$/i.exec(header)
  if (!match || !isOpaqueToken(match[1], 'tm_access_')) {
    throw unauthorized('Access token is invalid.', 'invalid_access_token')
  }
  const tokenHash = await sha256(match[1])
  const row = await database.prepare(`SELECT s.*, u.email
    FROM auth_sessions s JOIN users u ON u.id = s.user_id
    WHERE s.access_token_hash = ? AND u.deleted_at IS NULL LIMIT 1`).bind(tokenHash).first<SessionRow>()
  if (!row || row.revoked_at || Date.parse(row.access_expires_at) <= now.getTime()) {
    throw unauthorized('Access token is expired or revoked.', 'invalid_access_token')
  }
  await database.prepare('UPDATE auth_sessions SET last_used_at = ? WHERE id = ?')
    .bind(now.toISOString(), row.id).run()
  return { id: row.user_id, email: row.email, sessionId: row.id, authenticatedAt: row.created_at, storeEnvironment: row.store_environment === 'Sandbox' ? 'Sandbox' : 'Production' }
}

async function createChallenge(database: D1Database, now: Date): Promise<AuthChallengeResponseV1> {
  const state = randomToken('tm_state_', 24)
  const nonce = randomToken('tm_nonce_', 32)
  const expiresAt = new Date(now.getTime() + CHALLENGE_LIFETIME_MS)
  await database.batch([
    database.prepare('DELETE FROM auth_challenges WHERE expires_at <= ?').bind(now.toISOString()),
    database.prepare(`INSERT INTO auth_challenges (
      state_hash, nonce_hash, created_at, expires_at, used_at
    ) VALUES (?, ?, ?, ?, NULL)`).bind(
      await sha256(state), await sha256(nonce), now.toISOString(), expiresAt.toISOString(),
    ),
  ])
  return { apiVersion: AUTH_API_VERSION, state, nonce, expiresAt: expiresAt.toISOString() }
}

async function exchangeAppleToken(
  env: AuthV1Env,
  request: Request,
  now: Date,
  verifier: typeof verifyAppleIdentityToken,
): Promise<AuthSessionResponseV1> {
  const payload = await readJSON<AppleTokenExchangeRequestV1>(request)
  requireVersion(payload.apiVersion)
  if (!isOpaqueToken(payload.state, 'tm_state_') || !isOpaqueToken(payload.nonce, 'tm_nonce_') || typeof payload.identityToken !== 'string') {
    throw badRequest('Apple token exchange payload is invalid.', 'invalid_exchange_payload')
  }
  const stateHash = await sha256(payload.state)
  const nonceHash = await sha256(payload.nonce)
  const challenge = await env.DB.prepare('SELECT * FROM auth_challenges WHERE state_hash = ? LIMIT 1')
    .bind(stateHash).first<ChallengeRow>()
  if (!challenge || challenge.used_at || challenge.nonce_hash !== nonceHash || Date.parse(challenge.expires_at) <= now.getTime()) {
    throw unauthorized('Authentication challenge is invalid, expired, or already used.', 'invalid_challenge')
  }
  const audiences = configuredAudiences(env.APPLE_CLIENT_IDS)
  const expectedAppleNonce = await sha256(payload.nonce)
  const claims = await verifier(payload.identityToken, audiences, expectedAppleNonce, now)
  const tokenHash = await sha256(payload.identityToken)
  if (await env.DB.prepare('SELECT token_hash FROM auth_identity_token_uses WHERE token_hash = ? LIMIT 1').bind(tokenHash).first()) {
    throw unauthorized('Apple identity token was already used.', 'identity_token_replay')
  }

  let identity = await env.DB.prepare(`SELECT id, user_id, email FROM auth_identities
    WHERE provider = 'apple' AND provider_subject = ? LIMIT 1`).bind(claims.sub).first<IdentityRow>()
  if (!identity) {
    identity = await createTasteMapUser(env.DB, claims, payload, now)
  } else {
    const email = normalizedEmail(claims.email) ?? identity.email
    await env.DB.batch([
      env.DB.prepare(`UPDATE auth_identities SET email = ?, updated_at = ?, last_authenticated_at = ? WHERE id = ?`)
        .bind(email, now.toISOString(), now.toISOString(), identity.id),
      env.DB.prepare('UPDATE users SET email = COALESCE(?, email), updated_at = ? WHERE id = ?')
        .bind(email, now.toISOString(), identity.user_id),
    ])
    identity.email = email
  }

  const acceptance = await env.DB.batch([
    env.DB.prepare(`UPDATE auth_challenges SET used_at = ?
      WHERE state_hash = ? AND used_at IS NULL AND expires_at > ? AND nonce_hash = ?`)
      .bind(now.toISOString(), stateHash, now.toISOString(), nonceHash),
    env.DB.prepare(`INSERT OR IGNORE INTO auth_identity_token_uses (token_hash, identity_id, used_at)
      VALUES (?, ?, ?)`).bind(tokenHash, identity.id, now.toISOString()),
  ])
  if (changes(acceptance[0]) !== 1 || changes(acceptance[1]) !== 1) {
    throw unauthorized('Authentication response was replayed.', 'authentication_replay')
  }
  return issueSession(env.DB, { id: identity.user_id, email: identity.email }, now)
}

async function createTasteMapUser(
  database: D1Database,
  claims: AppleClaims,
  payload: AppleTokenExchangeRequestV1,
  now: Date,
): Promise<IdentityRow> {
  const userID = randomToken('tm_', 18)
  const identityID = randomToken('tm_identity_', 18)
  const email = normalizedEmail(claims.email)
  const displayName = [cleanName(payload.givenName), cleanName(payload.familyName)].filter(Boolean).join(' ') || 'Taste Map 用户'
  const attribution = await registrationReferral(database, payload.referralCode, userID, now)
    .catch(() => { throw badRequest('邀请码无效，请检查后重试。', 'invalid_referral_code') })
  await database.batch([
    database.prepare(`INSERT INTO users (
      id, auth_provider, auth_subject, email, nickname, bio, city, created_at, updated_at
    ) VALUES (?, 'apple', NULL, ?, ?, '', '', ?, ?)`)
      .bind(userID, email, displayName, now.toISOString(), now.toISOString()),
    database.prepare(`INSERT INTO auth_identities (
      id, user_id, provider, provider_subject, email, created_at, updated_at, last_authenticated_at
    ) VALUES (?, ?, 'apple', ?, ?, ?, ?, ?)`)
      .bind(identityID, userID, claims.sub, email, now.toISOString(), now.toISOString(), now.toISOString()),
    ...attribution,
  ])
  return { id: identityID, user_id: userID, email }
}

async function issueSession(database: D1Database, user: AuthenticatedUser, now: Date): Promise<AuthSessionResponseV1> {
  const sessionID = randomToken('tm_session_', 18)
  const accessToken = randomToken('tm_access_', 32)
  const refreshToken = randomToken('tm_refresh_', 48)
  const accessExpiresAt = new Date(now.getTime() + ACCESS_LIFETIME_MS)
  const refreshExpiresAt = new Date(now.getTime() + REFRESH_LIFETIME_MS)
  await database.prepare(`INSERT INTO auth_sessions (
    id, user_id, access_token_hash, access_expires_at, refresh_token_hash, refresh_expires_at,
    refresh_generation, created_at, updated_at, last_used_at, revoked_at, revoke_reason
  ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, NULL, NULL)`).bind(
    sessionID, user.id, await sha256(accessToken), accessExpiresAt.toISOString(),
    await sha256(refreshToken), refreshExpiresAt.toISOString(),
    now.toISOString(), now.toISOString(), now.toISOString(),
  ).run()
  return response(user, accessToken, accessExpiresAt, refreshToken, refreshExpiresAt)
}

async function refreshSession(database: D1Database, request: Request, now: Date): Promise<AuthSessionResponseV1> {
  const payload = await readJSON<RefreshSessionRequestV1>(request)
  requireVersion(payload.apiVersion)
  if (!isOpaqueToken(payload.refreshToken, 'tm_refresh_')) throw unauthorized('Refresh token is invalid.', 'invalid_refresh_token')
  const oldHash = await sha256(payload.refreshToken)
  let session = await database.prepare(`SELECT s.*, u.email FROM auth_sessions s
    JOIN users u ON u.id = s.user_id WHERE s.refresh_token_hash = ? AND u.deleted_at IS NULL LIMIT 1`)
    .bind(oldHash).first<SessionRow>()
  if (!session) {
    const reused = await database.prepare('SELECT session_id FROM auth_refresh_token_history WHERE token_hash = ? LIMIT 1')
      .bind(oldHash).first<HistoryRow>()
    if (reused) {
      await revoke(database, reused.session_id, now, 'refresh_token_reuse')
      throw unauthorized('Refresh token reuse was detected; session revoked.', 'refresh_token_reuse')
    }
    throw unauthorized('Refresh token is invalid.', 'invalid_refresh_token')
  }
  if (session.revoked_at || Date.parse(session.refresh_expires_at) <= now.getTime()) {
    if (!session.revoked_at) await revoke(database, session.id, now, 'refresh_token_expired')
    throw unauthorized('Refresh session is expired or revoked.', 'invalid_refresh_token')
  }

  const accessToken = randomToken('tm_access_', 32)
  const refreshToken = randomToken('tm_refresh_', 48)
  const accessExpiresAt = new Date(now.getTime() + ACCESS_LIFETIME_MS)
  const refreshExpiresAt = new Date(now.getTime() + REFRESH_LIFETIME_MS)
  const nextGeneration = session.refresh_generation + 1
  const results = await database.batch([
    database.prepare(`INSERT OR IGNORE INTO auth_refresh_token_history (
      token_hash, session_id, generation, consumed_at
    ) VALUES (?, ?, ?, ?)`).bind(oldHash, session.id, session.refresh_generation, now.toISOString()),
    database.prepare(`UPDATE auth_sessions SET
      access_token_hash = ?, access_expires_at = ?, refresh_token_hash = ?, refresh_expires_at = ?,
      refresh_generation = ?, updated_at = ?, last_used_at = ?
      WHERE id = ? AND refresh_token_hash = ? AND revoked_at IS NULL`)
      .bind(await sha256(accessToken), accessExpiresAt.toISOString(), await sha256(refreshToken),
        refreshExpiresAt.toISOString(), nextGeneration, now.toISOString(), now.toISOString(), session.id, oldHash),
  ])
  if (changes(results[0]) !== 1 || changes(results[1]) !== 1) {
    await revoke(database, session.id, now, 'refresh_token_reuse')
    throw unauthorized('Refresh token reuse was detected; session revoked.', 'refresh_token_reuse')
  }
  session = { ...session, refresh_generation: nextGeneration }
  return response({ id: session.user_id, email: session.email }, accessToken, accessExpiresAt, refreshToken, refreshExpiresAt)
}

async function logoutSession(database: D1Database, request: Request, now: Date): Promise<{ apiVersion: 1; revoked: true }> {
  const payload = await readJSON<LogoutRequestV1>(request)
  requireVersion(payload.apiVersion)
  let sessionID: string | null = null
  const accessHeader = request.headers.get('Authorization')
  if (accessHeader) {
    const token = /^Bearer\s+(.+)$/i.exec(accessHeader)?.[1]
    if (token) {
      const row = await database.prepare('SELECT id FROM auth_sessions WHERE access_token_hash = ? LIMIT 1')
        .bind(await sha256(token)).first<{ id: string }>()
      sessionID = row?.id ?? null
    }
  }
  if (!sessionID && isOpaqueToken(payload.refreshToken, 'tm_refresh_')) {
    const row = await database.prepare('SELECT id FROM auth_sessions WHERE refresh_token_hash = ? LIMIT 1')
      .bind(await sha256(payload.refreshToken as string)).first<{ id: string }>()
    sessionID = row?.id ?? null
  }
  if (sessionID) await revoke(database, sessionID, now, 'logout')
  return { apiVersion: AUTH_API_VERSION, revoked: true }
}

async function revoke(database: D1Database, sessionID: string, now: Date, reason: string) {
  await database.prepare(`UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, ?),
    revoke_reason = COALESCE(revoke_reason, ?), updated_at = ? WHERE id = ?`)
    .bind(now.toISOString(), reason, now.toISOString(), sessionID).run()
}

export async function verifyAppleIdentityToken(
  token: string,
  acceptedAudiences: string[],
  expectedNonce: string,
  now = new Date(),
  jwks?: AppleJWKSet,
): Promise<AppleClaims> {
  const parts = token.split('.')
  if (parts.length !== 3) throw unauthorized('Apple identity token is malformed.', 'invalid_apple_token')
  const header = decodeJSON<{ alg?: string; kid?: string }>(parts[0])
  const claims = decodeJSON<AppleClaims>(parts[1])
  if (header.alg !== 'RS256' || !header.kid) throw unauthorized('Apple token algorithm is invalid.', 'invalid_apple_signature')
  const keys = jwks ?? await appleKeys()
  const jwk = keys.keys.find((key) => key.kid === header.kid && (!key.alg || key.alg === 'RS256'))
  if (!jwk) throw unauthorized('Apple signing key is unknown.', 'invalid_apple_signature')
  const publicKey = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'])
  const validSignature = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5', publicKey, decodeBase64URL(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  )
  if (!validSignature) throw unauthorized('Apple token signature is invalid.', 'invalid_apple_signature')
  const nowSeconds = Math.floor(now.getTime() / 1000)
  if (claims.iss !== APPLE_ISSUER) throw unauthorized('Apple token issuer is invalid.', 'invalid_apple_issuer')
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud]
  if (!audiences.some((audience) => acceptedAudiences.includes(audience))) {
    throw unauthorized('Apple token audience is invalid.', 'invalid_apple_audience')
  }
  if (!Number.isFinite(claims.exp) || claims.exp <= nowSeconds) throw unauthorized('Apple token is expired.', 'expired_apple_token')
  if (claims.iat !== undefined && claims.iat > nowSeconds + CLOCK_SKEW_SECONDS) throw unauthorized('Apple token issued-at is invalid.', 'invalid_apple_time')
  if (claims.nbf !== undefined && claims.nbf > nowSeconds + CLOCK_SKEW_SECONDS) throw unauthorized('Apple token is not active.', 'invalid_apple_time')
  if (typeof claims.sub !== 'string' || !claims.sub || claims.nonce !== expectedNonce) {
    throw unauthorized('Apple token subject or nonce is invalid.', 'invalid_apple_nonce')
  }
  return claims
}

async function appleKeys(): Promise<AppleJWKSet> {
  if (cachedAppleKeys && cachedAppleKeys.expiresAt > Date.now()) return cachedAppleKeys.value
  const response = await fetch(APPLE_JWKS_URL)
  if (!response.ok) throw new AuthV1RequestError('Apple signing keys are unavailable.', 503, 'apple_keys_unavailable')
  const value = await response.json() as AppleJWKSet
  if (!Array.isArray(value.keys)) throw new AuthV1RequestError('Apple signing keys are invalid.', 503, 'apple_keys_unavailable')
  cachedAppleKeys = { value, expiresAt: Date.now() + 60 * 60 * 1000 }
  return value
}

function configuredAudiences(value: string | undefined): string[] {
  const audiences = (value ?? '').split(',').map((item) => item.trim()).filter(Boolean)
  if (!audiences.length) throw new AuthV1RequestError('Apple authentication audience is not configured.', 503, 'apple_auth_not_configured')
  return audiences
}

function response(user: AuthenticatedUser, accessToken: string, accessExpiresAt: Date, refreshToken: string, refreshExpiresAt: Date): AuthSessionResponseV1 {
  return {
    apiVersion: AUTH_API_VERSION,
    user,
    session: {
      accessToken,
      accessTokenExpiresAt: accessExpiresAt.toISOString(),
      refreshToken,
      refreshTokenExpiresAt: refreshExpiresAt.toISOString(),
    },
  }
}

function randomToken(prefix: string, byteCount: number) {
  const bytes = crypto.getRandomValues(new Uint8Array(byteCount))
  return `${prefix}${encodeBase64URL(bytes)}`
}

export async function sha256(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function decodeJSON<T>(value: string): T {
  try {
    return JSON.parse(new TextDecoder().decode(decodeBase64URL(value))) as T
  } catch {
    throw unauthorized('Apple identity token is malformed.', 'invalid_apple_token')
  }
}

function decodeBase64URL(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
  try {
    const binary = atob(padded)
    return Uint8Array.from(binary, (character) => character.charCodeAt(0))
  } catch {
    throw unauthorized('Apple identity token is malformed.', 'invalid_apple_token')
  }
}

function encodeBase64URL(value: Uint8Array) {
  let binary = ''
  value.forEach((byte) => { binary += String.fromCharCode(byte) })
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

async function readJSON<T>(request: Request): Promise<T> {
  return request.json().catch(() => { throw badRequest('Request body is not valid JSON.', 'invalid_json') }) as Promise<T>
}

function requireVersion(version: unknown) {
  if (version !== AUTH_API_VERSION) throw badRequest('Unsupported authentication API version.', 'unsupported_auth_version')
}

function cleanName(value: unknown) {
  return typeof value === 'string' ? value.trim().slice(0, 80) : ''
}

function normalizedEmail(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim().toLowerCase().slice(0, 320) : null
}

function isOpaqueToken(value: unknown, prefix: string): value is string {
  return typeof value === 'string' && value.startsWith(prefix) && value.length > prefix.length + 20 && value.length < 512
}

function changes(result: D1Result<unknown>) {
  return Number(result.meta?.changes ?? 0)
}

function badRequest(message: string, code: string) {
  return new AuthV1RequestError(message, 400, code)
}

function unauthorized(message: string, code: string) {
  return new AuthV1RequestError(message, 401, code)
}
