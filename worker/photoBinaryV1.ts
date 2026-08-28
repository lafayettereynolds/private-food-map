const API_VERSION = 1
const MAX_DISPLAY_BYTES = 8 * 1024 * 1024
const MAX_THUMBNAIL_BYTES = 1024 * 1024
const PHOTO_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const SHA256_PATTERN = /^[0-9a-f]{64}$/i
const ALLOWED_CONTENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/heic', 'image/heif'])

export interface PhotoBinaryV1Env {
  DB: D1Database
  PHOTO_STORAGE?: R2Bucket
}

export class PhotoBinaryV1Error extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

interface OwnedPhotoRow {
  id: string
  user_id: string
  storage_provider: string
  storage_key: string | null
  thumbnail_storage_key: string | null
  deleted_at: string | null
}

type PhotoVariant = 'display' | 'thumbnail'

export async function handlePhotoBinaryV1(
  request: Request,
  env: PhotoBinaryV1Env,
  viewerId: string,
  photoId: string,
): Promise<Response> {
  try {
    return await handlePhotoBinaryRequest(request, env, viewerId, photoId)
  } catch (error) {
    if (error instanceof PhotoBinaryV1Error) {
      return Response.json({ error: error.message }, { status: error.status })
    }
    throw error
  }
}

async function handlePhotoBinaryRequest(
  request: Request,
  env: PhotoBinaryV1Env,
  viewerId: string,
  photoId: string,
): Promise<Response> {
  const bucket = env.PHOTO_STORAGE
  if (!bucket) throw new PhotoBinaryV1Error('Photo storage is not configured for this environment.', 503)
  if (!PHOTO_ID_PATTERN.test(photoId)) throw new PhotoBinaryV1Error('Photo ID is invalid.', 400)

  if (request.method === 'PUT') return uploadPhotoVariant(request, bucket, viewerId, photoId)
  if (request.method === 'GET') return downloadPhotoVariant(request, env.DB, bucket, viewerId, photoId)
  if (request.method === 'DELETE') return deletePhotoObjects(env.DB, bucket, viewerId, photoId)
  throw new PhotoBinaryV1Error('Photo content method is not supported.', 405)
}

async function uploadPhotoVariant(
  request: Request,
  bucket: R2Bucket,
  viewerId: string,
  photoId: string,
): Promise<Response> {
  const variant = readVariant(request)
  const contentType = request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() ?? ''
  if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
    throw new PhotoBinaryV1Error('Photo content type is not supported.', 415)
  }
  const expectedHash = request.headers.get('X-Taste-Map-Content-SHA256')?.trim().toLowerCase() ?? ''
  if (!SHA256_PATTERN.test(expectedHash)) {
    throw new PhotoBinaryV1Error('A valid photo SHA-256 digest is required.', 400)
  }
  const data = await request.arrayBuffer()
  const maximum = variant === 'thumbnail' ? MAX_THUMBNAIL_BYTES : MAX_DISPLAY_BYTES
  if (data.byteLength === 0 || data.byteLength > maximum) {
    throw new PhotoBinaryV1Error(`Photo ${variant} payload exceeds the allowed size.`, 413)
  }
  const actualHash = await sha256(data)
  if (actualHash !== expectedHash) throw new PhotoBinaryV1Error('Photo checksum does not match the payload.', 400)

  const key = objectKey(viewerId, photoId, variant, contentType)
  const existing = await bucket.head(key)
  if (existing) {
    if (existing.customMetadata?.sha256 !== actualHash) {
      throw new PhotoBinaryV1Error('This photo upload key already contains different content.', 409)
    }
    return uploadResponse(photoId, variant, key, contentType, data.byteLength, actualHash, true)
  }

  await bucket.put(key, data, {
    httpMetadata: { contentType, cacheControl: 'private, max-age=0, no-store' },
    customMetadata: { owner: viewerId, photoId, variant, sha256: actualHash },
  })
  return uploadResponse(photoId, variant, key, contentType, data.byteLength, actualHash, false)
}

async function downloadPhotoVariant(
  request: Request,
  database: D1Database,
  bucket: R2Bucket,
  viewerId: string,
  photoId: string,
): Promise<Response> {
  const variant = readVariant(request)
  const photo = await readablePhoto(database, viewerId, photoId)
  if (!photo || photo.deleted_at) throw new PhotoBinaryV1Error('Photo was not found.', 404)
  if (photo.storage_provider !== 'r2') throw new PhotoBinaryV1Error('This photo uses a different storage provider.', 409)
  const key = variant === 'thumbnail' ? photo.thumbnail_storage_key : photo.storage_key
  if (!key || !isOwnedObjectKey(key, photo.user_id, photoId, variant)) {
    throw new PhotoBinaryV1Error('Photo storage metadata is unavailable.', 404)
  }
  const object = await bucket.get(key)
  if (!object) throw new PhotoBinaryV1Error('Photo content was not found.', 404)
  const headers = new Headers()
  object.writeHttpMetadata(headers)
  headers.set('Cache-Control', 'private, max-age=0, no-store')
  headers.set('ETag', object.httpEtag)
  headers.set('X-Content-Type-Options', 'nosniff')
  return new Response(object.body, { status: 200, headers })
}

async function deletePhotoObjects(
  database: D1Database,
  bucket: R2Bucket,
  viewerId: string,
  photoId: string,
): Promise<Response> {
  const photo = await ownedPhoto(database, viewerId, photoId)
  if (photo && !photo.deleted_at) {
    throw new PhotoBinaryV1Error('Photo metadata must be tombstoned before binary cleanup.', 409)
  }
  const keys = photo
    ? [photo.storage_key, photo.thumbnail_storage_key].filter((key): key is string => Boolean(key))
    : defaultObjectKeys(viewerId, photoId)
  const ownedKeys = keys.filter((key) => key.startsWith(`${ownerPrefix(viewerId)}/photos/${photoId}/`))
  if (ownedKeys.length > 0) await bucket.delete(ownedKeys)
  return Response.json({ apiVersion: API_VERSION, photoId, deleted: true })
}

function readVariant(request: Request): PhotoVariant {
  const value = new URL(request.url).searchParams.get('variant') ?? 'display'
  if (value !== 'display' && value !== 'thumbnail') {
    throw new PhotoBinaryV1Error('Photo variant is invalid.', 400)
  }
  return value
}

function objectKey(viewerId: string, photoId: string, variant: PhotoVariant, contentType: string) {
  const extension = contentType === 'image/png' ? 'png' : contentType === 'image/heic' || contentType === 'image/heif' ? 'heic' : 'jpg'
  return `${ownerPrefix(viewerId)}/photos/${photoId}/${variant}.${extension}`
}

function defaultObjectKeys(viewerId: string, photoId: string) {
  return ['display.jpg', 'display.png', 'display.heic', 'thumbnail.jpg', 'thumbnail.png', 'thumbnail.heic']
    .map((name) => `${ownerPrefix(viewerId)}/photos/${photoId}/${name}`)
}

function ownerPrefix(viewerId: string) {
  return `users/${encodeURIComponent(viewerId)}`
}

function isOwnedObjectKey(key: string, viewerId: string, photoId: string, variant: PhotoVariant) {
  return key.startsWith(`${ownerPrefix(viewerId)}/photos/${photoId}/${variant}.`)
}

async function ownedPhoto(database: D1Database, viewerId: string, photoId: string) {
  return database.prepare(`SELECT id, user_id, storage_provider, storage_key, thumbnail_storage_key, deleted_at
    FROM photos WHERE id = ? AND user_id = ? LIMIT 1`)
    .bind(photoId, viewerId).first<OwnedPhotoRow>()
}

async function readablePhoto(database: D1Database, viewerId: string, photoId: string) {
  return database.prepare(`SELECT p.id, p.user_id, p.storage_provider, p.storage_key,
      p.thumbnail_storage_key, p.deleted_at
    FROM photos p
    WHERE p.id = ? AND p.deleted_at IS NULL AND (
      p.user_id = ? OR EXISTS (
        SELECT 1 FROM user_profiles up
        WHERE up.user_id = p.user_id AND up.avatar_photo_id = p.id
          AND up.deleted_at IS NULL AND (
            up.visibility = 'public' OR (
              up.visibility = 'friends' AND EXISTS (
                SELECT 1 FROM friendships f
                WHERE f.status = 'accepted' AND f.deleted_at IS NULL AND (
                  (f.requester_id = ? AND f.addressee_id = up.user_id) OR
                  (f.requester_id = up.user_id AND f.addressee_id = ?)
                )
              )
            )
          )
      )
      OR EXISTS (
        SELECT 1 FROM visits v
        JOIN user_profiles vp ON vp.user_id = v.user_id
        WHERE v.id = p.visit_id AND v.user_id = p.user_id
          AND v.deleted_at IS NULL AND vp.deleted_at IS NULL AND (
            (
              vp.visibility = 'public'
              AND p.visibility = 'public'
              AND v.visibility = 'public'
            ) OR (
              vp.visibility IN ('public', 'friends')
              AND p.visibility IN ('public', 'friends')
              AND v.visibility IN ('public', 'friends')
              AND EXISTS (
                SELECT 1 FROM friendships vf
                WHERE vf.status = 'accepted' AND vf.deleted_at IS NULL AND (
                  (vf.requester_id = ? AND vf.addressee_id = p.user_id) OR
                  (vf.requester_id = p.user_id AND vf.addressee_id = ?)
                )
              )
            )
          )
      )
    ) LIMIT 1`)
    .bind(photoId, viewerId, viewerId, viewerId, viewerId, viewerId).first<OwnedPhotoRow>()
}

function uploadResponse(
  photoId: string,
  variant: PhotoVariant,
  storageKey: string,
  contentType: string,
  byteSize: number,
  checksum: string,
  duplicate: boolean,
) {
  return Response.json({
    apiVersion: API_VERSION,
    photoId,
    variant,
    storageProvider: 'r2',
    storageKey,
    contentType,
    byteSize,
    checksum,
    duplicate,
  })
}

async function sha256(data: ArrayBuffer) {
  const digest = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}
