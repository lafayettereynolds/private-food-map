import { db } from '../db/appDb'
import { syncQueueId } from '../types/sync'
import type { Photo } from '../types/domain'
import { getGoogleDriveState, subscribeGoogleDrive } from './googleDrive'
import { cachePhotoBlob, removeCachedPhoto } from './photoAssets'
import { drivePhotoReference } from './cloudSyncData'
import { CLOUD_SYNC_REQUEST_EVENT, requestCloudSync } from './syncEvents'
import { DATABASE_NAME } from '../config/appEnvironment'
import { CURRENT_USER_ID } from '../db/social'
import { activeWebPhotoStorageProvider, photoStorageProviderFor } from './photoStorage'

export interface PhotoSyncState {
  status: 'idle' | 'syncing' | 'synced' | 'error'
  pending: number
  completed: number
  failed: number
  total: number
  errorMessage: string | null
}

type PendingPhoto =
  | { kind: 'restaurant-marker'; restaurantId: string; visitId: null; source: string }
  | { kind: 'visit'; restaurantId: string; visitId: string; source: string; index: number }
  | { kind: 'dish'; restaurantId: string; visitId: string; source: string; dishId: string }

const listeners = new Set<() => void>()
let state: PhotoSyncState = { status: 'idle', pending: 0, completed: 0, failed: 0, total: 0, errorMessage: null }
let inFlight: Promise<PhotoSyncState> | null = null
let scheduled: number | null = null
const AUTO_SYNC_KEY = `taste-map-photo-auto-sync:${DATABASE_NAME}`

export function getPhotoSyncState() {
  return state
}

export function subscribePhotoSync(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export async function initializePhotoSync() {
  const initialPending = await refreshPendingPhotoCount()
  if (getGoogleDriveState().status === 'connected' && !initialPending) enablePhotoAutoSync()
  const onDriveChanged = () => { void refreshPendingPhotoCount() }
  const scheduleIfEnabled = () => {
    if (isPhotoAutoSyncEnabled()) schedulePhotoSync()
    else void refreshPendingPhotoCount()
  }
  const unsubscribeDrive = subscribeGoogleDrive(onDriveChanged)
  window.addEventListener('online', scheduleIfEnabled)
  window.addEventListener(CLOUD_SYNC_REQUEST_EVENT, scheduleIfEnabled)
  if (isPhotoAutoSyncEnabled()) schedulePhotoSync(200)
  return () => {
    unsubscribeDrive()
    window.removeEventListener('online', scheduleIfEnabled)
    window.removeEventListener(CLOUD_SYNC_REQUEST_EVENT, scheduleIfEnabled)
    if (scheduled !== null) window.clearTimeout(scheduled)
  }
}

export function schedulePhotoSync(delay = 700) {
  if (scheduled !== null) return
  scheduled = window.setTimeout(() => {
    scheduled = null
    if (getGoogleDriveState().status === 'connected' && navigator.onLine) {
      void syncPendingPhotos().catch(() => undefined)
    } else {
      void refreshPendingPhotoCount()
    }
  }, delay)
}

export async function refreshPendingPhotoCount() {
  const [pending, deletes] = await Promise.all([collectPendingPhotos(), collectPendingDeletes()])
  updateState({ pending: pending.length + deletes.length })
  return pending.length + deletes.length
}

export async function syncPendingPhotos() {
  if (inFlight) return inFlight
  inFlight = performPhotoSync().finally(() => { inFlight = null })
  return inFlight
}

export function enablePhotoAutoSync() {
  localStorage.setItem(AUTO_SYNC_KEY, 'true')
}

export async function markPhotoIdsForDeletion(photoIds: Array<string | null | undefined>) {
  const ids = [...new Set(photoIds.filter((id): id is string => Boolean(id)))]
  if (!ids.length) return
  const now = new Date().toISOString()
  await db.photos.where('id').anyOf(ids).modify({ localState: 'delete-pending', syncStatus: 'delete-pending', updatedAt: now, lastError: null })
  await refreshPendingPhotoCount()
  schedulePhotoSync(100)
}

export async function getGoogleDriveAccountWarning() {
  const account = getGoogleDriveState()
  if (account.status !== 'connected' || !account.accountId) return null
  const activePhotos = await db.photos.filter((photo) => !photo.deletedAt).toArray()
  const expected = activePhotos.find((photo) => photo.driveAccountId)?.driveAccountId
  return expected && expected !== account.accountId
    ? '你当前连接的是另一个 Google Drive 账号，原有云端照片可能无法访问。'
    : null
}

async function performPhotoSync() {
  const account = getGoogleDriveState()
  if (account.status !== 'connected' || !account.accountId) {
    const pending = await refreshPendingPhotoCount()
    const message = '请先连接 Google Drive，再同步图片。'
    updateState({ status: 'error', pending, total: pending, completed: 0, failed: 0, errorMessage: message })
    throw new Error(message)
  }
  const accountWarning = await getGoogleDriveAccountWarning()
  if (accountWarning) {
    updateState({ status: 'error', errorMessage: accountWarning })
    throw new Error(accountWarning)
  }
  enablePhotoAutoSync()

  const [pendingPhotos, pendingDeletes] = await Promise.all([collectPendingPhotos(), collectPendingDeletes()])
  const total = pendingPhotos.length + pendingDeletes.length
  updateState({ status: 'syncing', pending: total, total, completed: 0, failed: 0, errorMessage: null })
  let completed = 0
  let failed = 0
  let lastError: string | null = null

  for (const photo of pendingDeletes) {
    try {
      await deletePendingPhoto(photo)
      completed += 1
    } catch (error) {
      failed += 1
      lastError = errorMessage(error)
      await db.photos.update(photo.id, { lastError })
    }
    updateState({ completed, failed, pending: total - completed - failed })
  }

  for (const pending of pendingPhotos) {
    try {
      await uploadPendingPhoto(pending, account.accountId)
      completed += 1
    } catch (error) {
      failed += 1
      lastError = errorMessage(error)
    }
    updateState({ completed, failed, pending: total - completed - failed })
  }

  if (completed) requestCloudSync()
  const remaining = await refreshPendingPhotoCount()
  updateState({
    status: failed ? 'error' : 'synced',
    pending: remaining,
    total,
    completed,
    failed,
    errorMessage: lastError,
  })
  return state
}

async function collectPendingPhotos(): Promise<PendingPhoto[]> {
  const [restaurants, visits] = await Promise.all([
    db.restaurants.filter((restaurant) => !restaurant.deletedAt).toArray(),
    db.visits.filter((visit) => !visit.deletedAt).toArray(),
  ])
  const pending: PendingPhoto[] = []
  restaurants.forEach((restaurant) => {
    if (!restaurant.markerPhotoId && isLocalImage(restaurant.markerImageData)) {
      pending.push({ kind: 'restaurant-marker', restaurantId: restaurant.id, visitId: null, source: restaurant.markerImageData })
    }
  })
  visits.forEach((visit) => {
    visit.photos.forEach((source, index) => {
      if (!visit.photoIds[index] && isLocalImage(source)) {
        pending.push({ kind: 'visit', restaurantId: visit.restaurantId, visitId: visit.id, source, index })
      }
    })
    visit.dishes.forEach((dish) => {
      if (!dish.photoId && isLocalImage(dish.imageData)) {
        pending.push({ kind: 'dish', restaurantId: visit.restaurantId, visitId: visit.id, source: dish.imageData, dishId: dish.id })
      }
    })
  })
  return pending
}

async function collectPendingDeletes() {
  return db.photos.where('localState').equals('delete-pending').filter((photo) => !photo.deletedAt).toArray()
}

async function uploadPendingPhoto(pending: PendingPhoto, driveAccountId: string) {
  const blob = dataUrlToBlob(pending.source)
  if (blob.size > 5 * 1024 * 1024) throw new Error('压缩后的图片仍超过 5 MB，请换一张图片重试。')
  const photoId = createId()
  const dimensions = await readImageDimensions(blob)
  const provider = activeWebPhotoStorageProvider()
  let storageKey: string | null = null
  let thumbnailStorageKey: string | null = null
  let uploadedPhoto: Photo | null = null
  try {
    const [uploaded, thumbnail] = await Promise.all([
      provider.upload(photoId, blob, 'original'),
      createThumbnailBlob(blob).then((thumbnailBlob) => provider.upload(photoId, thumbnailBlob, 'thumbnail')),
    ])
    storageKey = uploaded.storageKey
    thumbnailStorageKey = thumbnail.storageKey
    const now = new Date().toISOString()
    const sourceVisit = pending.visitId ? await db.visits.get(pending.visitId) : null
    const photo: Photo = {
      id: photoId,
      userId: CURRENT_USER_ID,
      restaurantId: pending.restaurantId,
      visitId: pending.visitId,
      kind: pending.kind,
      storageProvider: provider.id,
      storageKey: uploaded.storageKey,
      thumbnailStorageKey: thumbnail.storageKey,
      thumbnailFileSize: thumbnail.fileSize,
      driveAccountId,
      driveFileId: uploaded.storageKey,
      fileName: uploaded.fileName,
      mimeType: blob.type,
      fileSize: uploaded.fileSize,
      width: dimensions.width,
      height: dimensions.height,
      visibility: sourceVisit?.visibility ?? 'private',
      syncStatus: 'synced',
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      localState: 'synced',
      lastError: null,
    }
    uploadedPhoto = photo
    await saveUploadedPhoto(pending, photo)
    await cachePhotoBlob(photoId, blob)
  } catch (error) {
    if (storageKey) {
      const removed = await provider.delete(storageKey).then(() => true).catch(() => false)
      if (thumbnailStorageKey) await provider.delete(thumbnailStorageKey).catch(() => undefined)
      if (!removed && uploadedPhoto) {
        await db.photos.put({
          ...uploadedPhoto,
          restaurantId: null,
          visitId: null,
          localState: 'delete-pending',
          syncStatus: 'delete-pending',
          lastError: 'Drive 文件已上传，但本地关联失败；正在等待自动清理。',
        }).catch(() => undefined)
      }
    }
    throw error
  }
}

async function saveUploadedPhoto(pending: PendingPhoto, photo: Photo) {
  const reference = drivePhotoReference(photo.id)
  await db.transaction('rw', db.photos, db.restaurants, db.visits, db.syncQueue, async () => {
    if (pending.kind === 'restaurant-marker') {
      const restaurant = await db.restaurants.get(pending.restaurantId)
      if (!restaurant || restaurant.markerPhotoId || restaurant.markerImageData !== pending.source) {
        throw new Error('餐厅图片已发生变化，本次上传已取消。')
      }
      await db.restaurants.update(restaurant.id, {
        markerPhotoId: photo.id,
        markerImageData: reference,
        updatedAt: photo.updatedAt,
      })
      await queueRestaurant(restaurant.id, photo.updatedAt)
    } else {
      const visit = await db.visits.get(pending.visitId)
      if (!visit) throw new Error('没有找到照片所属的到访记录。')
      if (pending.kind === 'visit') {
        if (visit.photoIds[pending.index] || visit.photos[pending.index] !== pending.source) {
          throw new Error('到访照片已发生变化，本次上传已取消。')
        }
        const photos = [...visit.photos]
        const photoIds = [...visit.photoIds]
        photos[pending.index] = reference
        photoIds[pending.index] = photo.id
        await db.visits.update(visit.id, { photos, photoIds, updatedAt: photo.updatedAt })
      } else {
        const dish = visit.dishes.find((item) => item.id === pending.dishId)
        if (!dish || dish.photoId || dish.imageData !== pending.source) {
          throw new Error('菜品图片已发生变化，本次上传已取消。')
        }
        const dishes = visit.dishes.map((item) => item.id === pending.dishId
          ? { ...item, photoId: photo.id, imageData: reference }
          : item)
        await db.visits.update(visit.id, { dishes, updatedAt: photo.updatedAt })
      }
      await queueVisit(visit.id, photo.updatedAt)
    }
    await db.photos.put(photo)
  })
}

async function deletePendingPhoto(photo: Photo) {
  const account = getGoogleDriveState()
  if (account.accountId !== photo.driveAccountId) {
    throw new Error('当前 Google Drive 账号与这张照片不一致，暂未删除原图。')
  }
  const provider = photoStorageProviderFor(photo)
  await provider.delete(photo.storageKey || photo.driveFileId)
  if (photo.thumbnailStorageKey) await provider.delete(photo.thumbnailStorageKey).catch(() => undefined)
  const now = new Date().toISOString()
  await db.photos.update(photo.id, { deletedAt: now, updatedAt: now, localState: 'synced', syncStatus: 'synced', lastError: null })
  await removeCachedPhoto(photo.id)
}

async function queueRestaurant(id: string, updatedAt: string) {
  await db.syncQueue.put({ id: syncQueueId('restaurant', id), entityType: 'restaurant', entityId: id, updatedAt })
}

async function queueVisit(id: string, updatedAt: string) {
  await db.syncQueue.put({ id: syncQueueId('visit', id), entityType: 'visit', entityId: id, updatedAt })
}

function dataUrlToBlob(source: string) {
  const match = /^data:([^;,]+);base64,(.+)$/s.exec(source)
  if (!match) throw new Error('本地图片格式无法识别。')
  const binary = atob(match[2])
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index)
  return new Blob([bytes], { type: match[1] })
}

async function readImageDimensions(blob: Blob) {
  const url = URL.createObjectURL(blob)
  try {
    const image = new Image()
    image.src = url
    await image.decode()
    return { width: image.naturalWidth || null, height: image.naturalHeight || null }
  } catch {
    return { width: null, height: null }
  } finally {
    URL.revokeObjectURL(url)
  }
}

async function createThumbnailBlob(blob: Blob) {
  const url = URL.createObjectURL(blob)
  try {
    const image = new Image()
    image.src = url
    await image.decode()
    const scale = Math.min(1, 480 / Math.max(image.naturalWidth, image.naturalHeight))
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale))
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale))
    const context = canvas.getContext('2d')
    if (!context) throw new Error('当前浏览器无法生成照片缩略图。')
    context.drawImage(image, 0, 0, canvas.width, canvas.height)
    return await new Promise<Blob>((resolve, reject) => canvas.toBlob(
      (thumbnail) => thumbnail ? resolve(thumbnail) : reject(new Error('照片缩略图生成失败。')),
      'image/webp',
      0.72,
    ))
  } finally {
    URL.revokeObjectURL(url)
  }
}

function isLocalImage(value: string | null | undefined): value is string {
  return Boolean(value?.startsWith('data:image/'))
}

function createId() {
  return 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : '图片同步失败，请稍后重试。'
}

function updateState(changes: Partial<PhotoSyncState>) {
  state = { ...state, ...changes }
  listeners.forEach((listener) => listener())
}

function isPhotoAutoSyncEnabled() {
  return localStorage.getItem(AUTO_SYNC_KEY) === 'true'
}
