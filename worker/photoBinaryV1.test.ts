import { beforeEach, describe, expect, it } from 'vitest'
import { handlePhotoBinaryV1 } from './photoBinaryV1'

const PHOTO_ID = '94c7e85e-9aa9-4e20-9ee4-e53f32dd5f2c'
const USER_A = 'tm_user_a'
const USER_B = 'tm_user_b'

describe('Photo Binary API V1', () => {
  let bucket: MemoryR2Bucket
  let database: PhotoDatabase

  beforeEach(() => {
    bucket = new MemoryR2Bucket()
    database = new PhotoDatabase()
  })

  it('uses an owner-scoped deterministic key and deduplicates a lost upload response', async () => {
    const data = new TextEncoder().encode('display-photo')
    const checksum = await sha256(data)
    const first = await upload(bucket, database, USER_A, data, checksum)
    const repeated = await upload(bucket, database, USER_A, data, checksum)

    await expect(first.json()).resolves.toMatchObject({
      photoId: PHOTO_ID,
      storageProvider: 'r2',
      storageKey: `users/${USER_A}/photos/${PHOTO_ID}/display.jpg`,
      duplicate: false,
    })
    await expect(repeated.json()).resolves.toMatchObject({ duplicate: true })
    expect(bucket.putCount).toBe(1)
    expect(bucket.objects.size).toBe(1)
  })

  it('rejects a retry that reuses a photo key with different bytes', async () => {
    const first = new TextEncoder().encode('first')
    await upload(bucket, database, USER_A, first, await sha256(first))
    const changed = new TextEncoder().encode('changed')
    expect((await upload(bucket, database, USER_A, changed, await sha256(changed))).status).toBe(409)
  })

  it('authorizes private download from D1 ownership and never exposes a public URL', async () => {
    const data = new TextEncoder().encode('private-photo')
    const response = await upload(bucket, database, USER_A, data, await sha256(data))
    const body = await response.json() as { storageKey: string }
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: body.storageKey, thumbnail_storage_key: null, deleted_at: null,
    }

    const downloaded = await handlePhotoBinaryV1(
      new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`),
      environment(database, bucket), USER_A, PHOTO_ID,
    )
    expect(await downloaded.text()).toBe('private-photo')
    expect(downloaded.headers.get('cache-control')).toContain('private')
    expect((await handlePhotoBinaryV1(
      new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`),
      environment(database, bucket), USER_B, PHOTO_ID,
    )).status).toBe(404)
  })

  it('allows only the current public avatar while keeping other private Photos closed', async () => {
    const data = new TextEncoder().encode('profile-avatar')
    const response = await upload(bucket, database, USER_A, data, await sha256(data))
    const body = await response.json() as { storageKey: string }
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: body.storageKey, thumbnail_storage_key: null, deleted_at: null,
    }
    database.publicAvatarReadable = true
    const publicAvatar = await handlePhotoBinaryV1(
      new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`),
      environment(database, bucket), USER_B, PHOTO_ID,
    )
    expect(publicAvatar.status).toBe(200)
    expect(await publicAvatar.text()).toBe('profile-avatar')

    database.publicAvatarReadable = false
    expect((await handlePhotoBinaryV1(
      new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`),
      environment(database, bucket), USER_B, PHOTO_ID,
    )).status).toBe(404)
  })

  it('requires a metadata tombstone before idempotent binary cleanup', async () => {
    const data = new TextEncoder().encode('delete-me')
    const response = await upload(bucket, database, USER_A, data, await sha256(data))
    const body = await response.json() as { storageKey: string }
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: body.storageKey, thumbnail_storage_key: null, deleted_at: null,
    }
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    expect((await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)).status).toBe(409)

    database.photo.deleted_at = '2026-08-27T16:00:00.000Z'
    const deleted = await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)
    expect(await deleted.json()).toMatchObject({ deleted: true })
    expect(bucket.objects.size).toBe(0)
    const repeated = await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)
    expect(repeated.status).toBe(200)
  })

  it('fails closed when the current environment has no photo storage binding', async () => {
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`)
    const response = await handlePhotoBinaryV1(
      request,
      { DB: database as unknown as D1Database },
      USER_A,
      PHOTO_ID,
    )
    expect(response.status).toBe(503)
    await expect(response.json()).resolves.toMatchObject({ error: expect.stringContaining('not configured') })
  })
})

async function upload(
  bucket: MemoryR2Bucket,
  database: PhotoDatabase,
  viewer: string,
  data: Uint8Array,
  checksum: string,
) {
  return handlePhotoBinaryV1(new Request(
    `https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`,
    {
      method: 'PUT',
      headers: {
        'Content-Type': 'image/jpeg',
        'X-Taste-Map-Content-SHA256': checksum,
      },
      body: data,
    },
  ), environment(database, bucket), viewer, PHOTO_ID)
}

function environment(database: PhotoDatabase, bucket: MemoryR2Bucket) {
  return {
    DB: database as unknown as D1Database,
    PHOTO_STORAGE: bucket as unknown as R2Bucket,
  }
}

async function sha256(data: Uint8Array) {
  const digest = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

interface PhotoRow {
  id: string
  user_id: string
  storage_provider: string
  storage_key: string | null
  thumbnail_storage_key: string | null
  deleted_at: string | null
}

class PhotoDatabase {
  photo: PhotoRow | null = null
  publicAvatarReadable = false
  prepare(sql: string) {
    const database = this
    return {
      bind(photoID: string, userID: string) {
        return {
          async first() {
            const publicAvatar = sql.includes('FROM user_profiles') && database.publicAvatarReadable
            return database.photo?.id === photoID &&
              (database.photo.user_id === userID || publicAvatar)
              ? database.photo
              : null
          },
        }
      },
    }
  }
}

class MemoryR2Bucket {
  objects = new Map<string, {
    data: Uint8Array
    contentType: string
    customMetadata: Record<string, string>
  }>()
  putCount = 0

  async head(key: string) {
    const object = this.objects.get(key)
    return object ? { customMetadata: object.customMetadata } : null
  }

  async put(key: string, data: ArrayBuffer, options: R2PutOptions) {
    this.putCount += 1
    this.objects.set(key, {
      data: new Uint8Array(data),
      contentType: options.httpMetadata && 'contentType' in options.httpMetadata
        ? options.httpMetadata.contentType ?? 'application/octet-stream'
        : 'application/octet-stream',
      customMetadata: options.customMetadata ?? {},
    })
  }

  async get(key: string) {
    const object = this.objects.get(key)
    if (!object) return null
    return {
      body: object.data,
      httpEtag: `"${key}"`,
      writeHttpMetadata(headers: Headers) {
        headers.set('Content-Type', object.contentType)
      },
    }
  }

  async delete(keys: string | string[]) {
    for (const key of Array.isArray(keys) ? keys : [keys]) this.objects.delete(key)
  }
}
