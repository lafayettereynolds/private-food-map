import { db } from '../db/appDb'
import { downloadGoogleDrivePhoto, getGoogleDriveState } from './googleDrive'
import { photoIdFromReference } from './cloudSyncData'

const MAX_CACHE_BYTES = 300 * 1024 * 1024
const objectUrls = new Map<string, string>()

export async function resolvePhotoSource(source: string | null | undefined, explicitPhotoId?: string | null) {
  const photoId = explicitPhotoId ?? photoIdFromReference(source)
  if (!photoId) return source || null

  const existingUrl = objectUrls.get(photoId)
  if (existingUrl) {
    void touchCache(photoId)
    return existingUrl
  }

  const cached = await db.photoCache.get(photoId)
  if (cached) {
    const url = rememberObjectUrl(photoId, cached.blob)
    void touchCache(photoId)
    return url
  }

  const photo = await db.photos.get(photoId)
  if (!photo || photo.deletedAt) return null
  const account = getGoogleDriveState()
  if (account.status !== 'connected') throw new Error('Google Drive 未连接，请在设置中重新连接。')
  if (photo.driveAccountId && account.accountId !== photo.driveAccountId) {
    throw new Error('当前连接的是另一个 Google Drive 账号，无法读取原有照片。')
  }

  const blob = await downloadGoogleDrivePhoto(photo.driveFileId)
  await cachePhotoBlob(photoId, blob)
  return rememberObjectUrl(photoId, blob)
}

export async function cachePhotoBlob(photoId: string, blob: Blob) {
  const now = new Date().toISOString()
  await db.photoCache.put({
    photoId,
    blob,
    fileSize: blob.size,
    cachedAt: now,
    lastAccessedAt: now,
  })
  await evictOldCacheEntries()
}

export async function removeCachedPhoto(photoId: string) {
  await db.photoCache.delete(photoId)
  const url = objectUrls.get(photoId)
  if (url) URL.revokeObjectURL(url)
  objectUrls.delete(photoId)
}

export async function clearLocalPhotoCache() {
  await db.photoCache.clear()
  objectUrls.forEach((url) => URL.revokeObjectURL(url))
  objectUrls.clear()
}

export async function getLocalPhotoCacheBytes() {
  const entries = await db.photoCache.toArray()
  return entries.reduce((total, entry) => total + entry.fileSize, 0)
}

async function touchCache(photoId: string) {
  try {
    await db.photoCache.update(photoId, { lastAccessedAt: new Date().toISOString() })
  } catch {
    // 缓存时间更新失败不影响图片显示。
  }
}

async function evictOldCacheEntries() {
  const entries = await db.photoCache.orderBy('lastAccessedAt').toArray()
  let total = entries.reduce((sum, entry) => sum + entry.fileSize, 0)
  for (const entry of entries) {
    if (total <= MAX_CACHE_BYTES) break
    await removeCachedPhoto(entry.photoId)
    total -= entry.fileSize
  }
}

function rememberObjectUrl(photoId: string, blob: Blob) {
  const url = URL.createObjectURL(blob)
  objectUrls.set(photoId, url)
  return url
}
