import { db } from '../db/appDb'
import { getGoogleDriveState } from './googleDrive'
import { photoStorageProviderFor } from './photoStorage'
import { photoIdFromReference } from './cloudSyncData'

const MAX_CACHE_BYTES = 300 * 1024 * 1024
const objectUrls = new Map<string, string>()

export async function resolvePhotoSource(source: string | null | undefined, explicitPhotoId?: string | null) {
  // Native descriptors are already scoped by the platform adapter. Only the
  // Native scheme handler can authorize/read them; Browser cache IDs are a
  // different namespace and must not replace an otherwise valid resource.
  if (source?.startsWith('tastemap-resource://')) return source
  const photoId = explicitPhotoId ?? photoIdFromReference(source)
  if (!photoId) return source || null

  const photo = await db.photos.get(photoId)
  if (!photo || photo.deletedAt || photo.localState === 'delete-pending' || photo.syncStatus === 'delete-pending') return null

  const existingUrl = objectUrls.get(photoId)
  if (existingUrl) {
    void touchCache(photoId)
    return existingUrl
  }

  const cached = await db.photoCache.get(photoId)
  if (cached) {
    const current = await db.photos.get(photoId)
    if (!current || current.deletedAt || current.localState === 'delete-pending' || current.syncStatus === 'delete-pending') return null
    const url = rememberObjectUrl(photoId, cached.blob)
    void touchCache(photoId)
    return url
  }

  const account = getGoogleDriveState()
  if (account.status !== 'connected') throw new Error('Google Drive 未连接，请在设置中重新连接。')
  if (photo.driveAccountId && account.accountId !== photo.driveAccountId) {
    throw new Error('当前连接的是另一个 Google Drive 账号，无法读取原有照片。')
  }

  const provider = photoStorageProviderFor(photo)
  if (!provider.isAvailable()) throw new Error('当前图片存储服务不可用，请稍后重试。')
  const blob = await provider.download(photo.thumbnailStorageKey || photo.storageKey || photo.driveFileId)
  const current = await db.photos.get(photoId)
  if (!current || current.deletedAt || current.localState === 'delete-pending' || current.syncStatus === 'delete-pending') return null
  await cachePhotoBlob(photoId, blob)
  const afterCache = await db.photos.get(photoId)
  if (!afterCache || afterCache.deletedAt || afterCache.localState === 'delete-pending' || afterCache.syncStatus === 'delete-pending') {
    await removeCachedPhoto(photoId)
    return null
  }
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
