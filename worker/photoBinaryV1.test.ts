import { beforeEach, describe, expect, it } from 'vitest'
import { handlePhotoBinaryV1, resumePhotoBinaryDeletions } from './photoBinaryV1'

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

  it('authorizes a friends-only Visit Photo only while an accepted friendship exists', async () => {
    const data = new TextEncoder().encode('friends-visit-photo')
    const response = await upload(bucket, database, USER_A, data, await sha256(data))
    const body = await response.json() as { storageKey: string }
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: body.storageKey, thumbnail_storage_key: null, deleted_at: null,
    }
    database.friendVisitReadable = true
    expect((await handlePhotoBinaryV1(
      new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`),
      environment(database, bucket), USER_B, PHOTO_ID,
    )).status).toBe(200)
    database.friendVisitReadable = false
    expect((await handlePhotoBinaryV1(
      new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content?variant=display`),
      environment(database, bucket), USER_B, PHOTO_ID,
    )).status).toBe(404)
  })

  it('does not authorize a guessed Visit Photo ID when profile visibility denies the viewer', async () => {
    const data = new TextEncoder().encode('profile-private-visit-photo')
    const response = await upload(bucket, database, USER_A, data, await sha256(data))
    const body = await response.json() as { storageKey: string }
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: body.storageKey, thumbnail_storage_key: null, deleted_at: null,
    }
    database.friendVisitReadable = false
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

  it('fences a never-synced photo so a delayed upload cannot create its first object', async () => {
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    expect((await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)).status).toBe(200)
    const data = new TextEncoder().encode('delayed-first-upload')
    expect((await upload(bucket, database, USER_A, data, await sha256(data))).status).toBe(409)
    expect(bucket.putCount).toBe(0)
    expect(bucket.objects.size).toBe(0)
    // The fence belongs to this owner, not any guessed global UUID namespace.
    expect((await upload(bucket, database, USER_B, data, await sha256(data))).status).toBe(200)
  })

  it('periodic reconciliation removes late R2 writes without forgetting deletion authority', async () => {
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)
    const key = `users/${USER_A}/photos/${PHOTO_ID}/thumbnail.jpg`
    // Models a crashed request whose R2 PUT completes after DELETE's absence check.
    bucket.objects.set(key, { data: new Uint8Array([1]), contentType: 'image/jpeg', customMetadata: {} })
    bucket.failDeleteKey = key
    await resumePhotoBinaryDeletions(environment(database, bucket))
    expect(bucket.objects.has(key)).toBe(true)
    expect(database.fences.size).toBe(1)
    bucket.failDeleteKey = null
    await resumePhotoBinaryDeletions(environment(database, bucket))
    expect(bucket.objects.has(key)).toBe(false)
    expect(database.fences.size).toBe(1)
  })

  it('never claims R2 cleanup deleted content owned by another storage provider', async () => {
    database.photo = { id: PHOTO_ID, user_id: USER_A, storage_provider: 'google-drive',
      storage_key: 'drive-original', thumbnail_storage_key: 'drive-thumbnail', deleted_at: '2026-09-09' }
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    expect((await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)).status).toBe(409)
    expect(bucket.deleteCalls).toEqual([])
    expect(database.fences.size).toBe(0)
  })

  it('rejects a guessed other-owner ID without touching either owner objects', async () => {
    const bytes = new TextEncoder().encode('owner-only')
    const response = await upload(bucket, database, USER_A, bytes, await sha256(bytes))
    const { storageKey } = await response.json() as { storageKey: string }
    database.photo = { id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2', storage_key: storageKey,
      thumbnail_storage_key: null, deleted_at: '2026-09-09T00:00:00Z' }
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    expect((await handlePhotoBinaryV1(request, environment(database, bucket), USER_B, PHOTO_ID)).status).toBe(404)
    expect(bucket.objects.has(storageKey)).toBe(true)
    expect(bucket.deleteCalls).toEqual([])
  })

  it('D1 failure never begins destructive cleanup', async () => {
    const database = { prepare() { throw new Error('D1 unavailable') } } as unknown as PhotoDatabase
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    await expect(handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)).rejects.toThrow('D1 unavailable')
    expect(bucket.deleteCalls).toEqual([])
  })

  it('rejects stale uploads after a metadata tombstone without writing R2', async () => {
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: null, thumbnail_storage_key: null, deleted_at: '2026-09-09T00:00:00Z',
    }
    const data = new TextEncoder().encode('stale-device-photo')
    expect((await upload(bucket, database, USER_A, data, await sha256(data))).status).toBe(409)
    expect(bucket.putCount).toBe(0)
  })

  it('cleans a late PUT when deletion wins while the object write is in flight', async () => {
    bucket.afterPut = () => {
      database.photo = {
        id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
        storage_key: null, thumbnail_storage_key: null, deleted_at: '2026-09-09T00:00:00Z',
      }
    }
    const data = new TextEncoder().encode('in-flight-photo')
    expect((await upload(bucket, database, USER_A, data, await sha256(data))).status).toBe(409)
    expect(bucket.objects.size).toBe(0)
  })

  it('retries only surviving objects after partial binary cleanup', async () => {
    const data = new TextEncoder().encode('partial-delete')
    await upload(bucket, database, USER_A, data, await sha256(data))
    const original = `users/${USER_A}/photos/${PHOTO_ID}/display.jpg`
    const thumbnail = `users/${USER_A}/photos/${PHOTO_ID}/thumbnail.jpg`
    bucket.objects.set(thumbnail, bucket.objects.get(original)!)
    database.photo = {
      id: PHOTO_ID, user_id: USER_A, storage_provider: 'r2',
      storage_key: original, thumbnail_storage_key: thumbnail, deleted_at: '2026-09-09T00:00:00Z',
    }
    bucket.failDeleteKey = thumbnail
    const request = new Request(`https://dev.test/api/v1/photos/${PHOTO_ID}/content`, { method: 'DELETE' })
    await expect(handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)).rejects.toThrow('R2 unavailable')
    expect(bucket.objects.has(original)).toBe(false)
    expect(bucket.objects.has(thumbnail)).toBe(true)
    bucket.failDeleteKey = null
    expect((await handlePhotoBinaryV1(request, environment(database, bucket), USER_A, PHOTO_ID)).status).toBe(200)
    expect(bucket.objects.size).toBe(0)
    expect(bucket.deleteCalls.filter(key => key === original)).toHaveLength(1)
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
  fences = new Set<string>()
  publicAvatarReadable = false
  friendVisitReadable = false
  prepare(sql: string) {
    const database = this
    return {
      async all() {
        return { results: [...database.fences].map(value => {
          const [user_id, photo_id] = value.split(':')
          return { user_id, photo_id }
        }) }
      },
      bind(photoID: string, userID: string) {
        return {
          async first() {
            if (sql.includes('FROM photo_deletion_fences')) return database.fences.has(`${photoID}:${userID}`) ? { photo_id: userID } : null
            const publicAvatar = sql.includes('FROM user_profiles') && database.publicAvatarReadable
            const friendVisit = sql.includes('FROM visits') && database.friendVisitReadable
            return database.photo?.id === photoID &&
              (sql.includes('FROM photos WHERE id = ? LIMIT 1') || database.photo.user_id === userID || publicAvatar || friendVisit)
              ? database.photo
              : null
          },
          async run() {
            if (sql.includes('INSERT INTO photo_deletion_fences')) database.fences.add(`${photoID}:${userID}`)
            return { success: true }
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
  afterPut?: () => void
  failDeleteKey: string | null = null
  deleteCalls: string[] = []

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
    this.afterPut?.()
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
    for (const key of Array.isArray(keys) ? keys : [keys]) {
      this.deleteCalls.push(key)
      if (key === this.failDeleteKey) throw new Error('R2 unavailable')
      this.objects.delete(key)
    }
  }
}
