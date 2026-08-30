import { consumePublicAPIQuota } from './publicAPIRateLimit'

export const PUBLIC_SHARING_API_VERSION = 1 as const

type ShareEntityType = 'restaurant' | 'profile' | 'list'

export interface PublicSharingEnvironment {
  PUBLIC_SHARE_ORIGIN?: string
}

interface ShareRow {
  share_id: string
  owner_user_id: string
  entity_type: ShareEntityType
  entity_id: string
}

interface PublicRestaurantRow {
  name: string
  address: string
  city: string
  tags_json: string
  price_per_person: number | null
  merchant_image_url: string | null
}

interface PublicProfileRow {
  display_name: string
  bio: string
  city: string
}

interface PublicListRow {
  title: string
  description: string
  is_ranked: number
  restaurant_count: number
  display_name: string
}

interface PublicListItemRow {
  note: string
  restaurant_snapshot_json: string | null
  name: string | null
  address: string | null
  city: string | null
  merchant_image_url: string | null
}

export class PublicSharingV1Error extends Error {
  constructor(message: string, readonly status: number, readonly code: string) {
    super(message)
    this.name = 'PublicSharingV1Error'
  }
}

export async function createPublicShareV1(
  request: Request,
  database: D1Database,
  ownerUserId: string,
  environment: PublicSharingEnvironment,
) {
  if (request.method !== 'POST') throw shareError('Sharing method is not supported.', 405, 'method_not_allowed')
  const body = await request.json().catch(() => null) as Record<string, unknown> | null
  const entityType = body?.entityType
  const entityId = typeof body?.entityId === 'string' ? body.entityId.trim() : ''
  if (!isEntityType(entityType) || !isEntityIdentifier(entityId)) {
    throw shareError('分享对象无效。', 400, 'invalid_share_entity')
  }
  // Eligibility is checked before issuing a URL and on every anonymous read.
  await publicProjection(database, ownerUserId, entityType, entityId, 'eligibility-check')
  const existing = await database.prepare(`SELECT share_id, owner_user_id, entity_type, entity_id
    FROM public_share_links WHERE owner_user_id = ? AND entity_type = ? AND entity_id = ?
      AND revoked_at IS NULL LIMIT 1`)
    .bind(ownerUserId, entityType, entityId).first<ShareRow>()
  const now = new Date().toISOString()
  const row = existing ?? {
    share_id: randomShareID(), owner_user_id: ownerUserId, entity_type: entityType, entity_id: entityId,
  }
  if (!existing) {
    await database.prepare(`INSERT INTO public_share_links (
      share_id, owner_user_id, entity_type, entity_id, created_at, updated_at, revoked_at
    ) VALUES (?, ?, ?, ?, ?, ?, NULL)`)
      .bind(row.share_id, ownerUserId, entityType, entityId, now, now).run()
  }
  return {
    apiVersion: PUBLIC_SHARING_API_VERSION,
    shareId: row.share_id,
    entityType,
    url: `${shareOrigin(request, environment)}/share/${row.share_id}`,
  }
}

export async function readPublicShareV1(request: Request, database: D1Database, shareId: string) {
  if (request.method !== 'GET') throw shareError('Sharing method is not supported.', 405, 'method_not_allowed')
  if (!/^[A-Za-z0-9_-]{32}$/.test(shareId)) {
    throw shareError('公开分享不存在或已经失效。', 404, 'share_not_found')
  }
  await consumePublicAPIQuota(database, await anonymousActor(request), 'public-share-read', 240)
  const row = await database.prepare(`SELECT share_id, owner_user_id, entity_type, entity_id
    FROM public_share_links WHERE share_id = ? AND revoked_at IS NULL LIMIT 1`)
    .bind(shareId).first<ShareRow>()
  if (!row) throw shareError('公开分享不存在或已经失效。', 404, 'share_not_found')
  const entity = await publicProjection(database, row.owner_user_id, row.entity_type, row.entity_id, shareId)
  return { apiVersion: PUBLIC_SHARING_API_VERSION, shareId, entityType: row.entity_type, entity }
}

async function publicProjection(
  database: D1Database,
  ownerUserId: string,
  entityType: ShareEntityType,
  entityId: string,
  shareId: string,
) {
  switch (entityType) {
  case 'restaurant': {
    const row = await database.prepare(`SELECT r.name, r.address, r.city, r.tags_json,
        r.price_per_person, r.merchant_image_url
      FROM restaurants r
      JOIN user_profiles p ON p.user_id = r.user_id AND p.deleted_at IS NULL AND p.visibility = 'public'
      WHERE r.id = ? AND r.user_id = ? AND r.deleted_at IS NULL
        AND EXISTS (SELECT 1 FROM visits v WHERE v.restaurant_id = r.id AND v.user_id = r.user_id
          AND v.visibility = 'public' AND v.deleted_at IS NULL)
      LIMIT 1`).bind(entityId, ownerUserId).first<PublicRestaurantRow>()
    if (!row) throw unavailable()
    return {
      shareId, name: row.name, address: row.address, city: row.city,
      cuisines: parseStringArray(row.tags_json).slice(0, 4),
      pricePerPerson: row.price_per_person,
      merchantImageUrl: safeHTTPSURL(row.merchant_image_url),
    }
  }
  case 'profile': {
    if (entityId !== ownerUserId) throw unavailable()
    const row = await database.prepare(`SELECT display_name, bio, city FROM user_profiles
      WHERE user_id = ? AND visibility = 'public' AND deleted_at IS NULL LIMIT 1`)
      .bind(ownerUserId).first<PublicProfileRow>()
    if (!row) throw unavailable()
    const stats = await database.prepare(`SELECT COUNT(DISTINCT restaurant_id) AS restaurants,
        COUNT(*) AS visits FROM visits WHERE user_id = ? AND visibility = 'public' AND deleted_at IS NULL`)
      .bind(ownerUserId).first<{ restaurants: number; visits: number }>()
    return {
      shareId, displayName: row.display_name, bio: row.bio.trim() || null, city: row.city.trim() || null,
      statistics: { restaurantCount: Number(stats?.restaurants ?? 0), visitCount: Number(stats?.visits ?? 0) },
    }
  }
  case 'list': {
    const row = await database.prepare(`SELECT rl.title, rl.description, rl.is_ranked,
        COUNT(rli.id) AS restaurant_count, p.display_name
      FROM restaurant_lists rl
      JOIN user_profiles p ON p.user_id = rl.user_id AND p.deleted_at IS NULL AND p.visibility = 'public'
      LEFT JOIN restaurant_list_items rli ON rli.list_id = rl.id AND rli.deleted_at IS NULL
      WHERE rl.id = ? AND rl.user_id = ? AND rl.visibility = 'public' AND rl.deleted_at IS NULL
      GROUP BY rl.id LIMIT 1`).bind(entityId, ownerUserId).first<PublicListRow>()
    if (!row) throw unavailable()
    const result = await database.prepare(`SELECT rli.note, rli.restaurant_snapshot_json,
        r.name, r.address, r.city, r.merchant_image_url
      FROM restaurant_list_items rli
      LEFT JOIN restaurants r ON r.id = rli.restaurant_id AND r.user_id = rli.user_id AND r.deleted_at IS NULL
      WHERE rli.list_id = ? AND rli.deleted_at IS NULL
      ORDER BY rli.position ASC, rli.created_at ASC LIMIT 100`).bind(entityId).all<PublicListItemRow>()
    return {
      shareId, title: row.title, description: row.description, ownerDisplayName: row.display_name,
      isRanked: Boolean(row.is_ranked), restaurantCount: Number(row.restaurant_count),
      restaurants: result.results.map(publicListItem),
    }
  }
  }
}

function publicListItem(row: PublicListItemRow) {
  let snapshot: Record<string, unknown> = {}
  try { snapshot = row.restaurant_snapshot_json ? JSON.parse(row.restaurant_snapshot_json) : {} } catch { snapshot = {} }
  const text = (key: string, fallback: string | null) =>
    typeof snapshot[key] === 'string' ? String(snapshot[key]).trim() : fallback?.trim() ?? ''
  return {
    name: text('name', row.name), address: text('address', row.address), city: text('city', row.city),
    note: row.note.trim() || null,
    merchantImageUrl: safeHTTPSURL(
      typeof snapshot.merchantImageUrl === 'string' ? snapshot.merchantImageUrl : row.merchant_image_url,
    ),
  }
}

function shareOrigin(request: Request, environment: PublicSharingEnvironment) {
  const configured = environment.PUBLIC_SHARE_ORIGIN?.trim()
  const value = configured || new URL(request.url).origin
  const parsed = new URL(value)
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.pathname !== '/') {
    throw shareError('公开分享域名尚未安全配置。', 503, 'public_share_origin_not_configured')
  }
  return parsed.origin
}

function randomShareID() {
  const bytes = crypto.getRandomValues(new Uint8Array(24))
  let value = ''
  for (const byte of bytes) value += String.fromCharCode(byte)
  return btoa(value).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function anonymousActor(request: Request) {
  const raw = request.headers.get('CF-Connecting-IP') || 'unknown'
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`public-share:${raw}`))
  return `public:${[...new Uint8Array(digest)].slice(0, 12).map((byte) => byte.toString(16).padStart(2, '0')).join('')}`
}

function parseStringArray(value: string) {
  try { const parsed = JSON.parse(value); return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === 'string') : [] }
  catch { return [] }
}

function safeHTTPSURL(value: string | null) {
  if (!value) return null
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password ? url.toString() : null }
  catch { return null }
}

function isEntityType(value: unknown): value is ShareEntityType {
  return value === 'restaurant' || value === 'profile' || value === 'list'
}

function isEntityIdentifier(value: string) {
  return value.length >= 1 && value.length <= 160 && !/[\0\r\n]/.test(value)
}

function unavailable() { return shareError('公开内容不存在、不可见或已经删除。', 404, 'share_content_unavailable') }
function shareError(message: string, status: number, code: string) { return new PublicSharingV1Error(message, status, code) }
