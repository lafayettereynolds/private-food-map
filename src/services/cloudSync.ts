import { CLOUD_SYNC_ENABLED } from '../config/appEnvironment'
import { db } from '../db/appDb'
import type {
  CloudSnapshot,
  CloudSyncResult,
  CloudSyncState,
} from '../types/cloudSync'
import type { Photo, Restaurant, Visit } from '../types/domain'
import type { StoredSyncStatus, SyncQueueItem } from '../types/sync'
import { activeCounts, mergeCloudData, toCloudPhoto, toCloudRestaurant, toCloudVisit } from './cloudSyncData'
import { CLOUD_SYNC_REQUEST_EVENT } from './syncEvents'

const API_PATH = '/api/sync'
const listeners = new Set<() => void>()
let inFlightSync: Promise<CloudSyncResult> | null = null
let scheduledSync: number | null = null

let state: CloudSyncState = {
  status: CLOUD_SYNC_ENABLED ? 'idle' : 'disabled',
  lastSuccessfulSyncAt: null,
  errorMessage: null,
  localCounts: null,
  cloudCounts: null,
}

export function getCloudSyncState() {
  return state
}

export function subscribeCloudSync(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export async function initializeCloudSync() {
  if (!CLOUD_SYNC_ENABLED) return () => undefined
  const storedMetadata = await db.syncMetadata.get('cloud')
  if (storedMetadata) {
    updateState({
      lastSuccessfulSyncAt: storedMetadata.lastSuccessfulSyncAt,
      errorMessage: storedMetadata.errorMessage,
    })
  }

  const onSyncRequested = () => scheduleCloudSync()
  const onOnline = () => scheduleCloudSync(100)
  window.addEventListener(CLOUD_SYNC_REQUEST_EVENT, onSyncRequested)
  window.addEventListener('online', onOnline)
  void syncNow().catch(() => undefined)

  return () => {
    window.removeEventListener(CLOUD_SYNC_REQUEST_EVENT, onSyncRequested)
    window.removeEventListener('online', onOnline)
    if (scheduledSync !== null) window.clearTimeout(scheduledSync)
  }
}

export function scheduleCloudSync(delay = 900) {
  if (!CLOUD_SYNC_ENABLED || scheduledSync !== null) return
  scheduledSync = window.setTimeout(() => {
    scheduledSync = null
    void syncNow().catch(() => undefined)
  }, delay)
}

export function dismissInitialMigration() {
  if (state.status !== 'migrationRequired') return
  updateState({ status: 'idle', errorMessage: null })
}

export function syncNow(options: { allowInitialUpload?: boolean } = {}) {
  if (!CLOUD_SYNC_ENABLED) {
    return Promise.resolve({
      localCounts: { restaurants: 0, visits: 0, photos: 0 },
      cloudCounts: { restaurants: 0, visits: 0, photos: 0 },
      migrationRequired: false,
    })
  }
  if (inFlightSync) return inFlightSync
  inFlightSync = performSync(options).finally(() => {
    inFlightSync = null
  })
  return inFlightSync
}

async function performSync({ allowInitialUpload = false }: { allowInitialUpload?: boolean }) {
  const attemptAt = new Date().toISOString()
  updateState({ status: 'syncing', errorMessage: null })
  await storeMetadata('syncing', attemptAt, null)

  try {
    const [localRestaurants, localVisits, localPhotos, queuedAtStart, cloudBefore] = await Promise.all([
      db.restaurants.toArray(),
      db.visits.toArray(),
      db.photos.toArray(),
      db.syncQueue.toArray(),
      fetchCloudSnapshot(),
    ])
    const localCounts = activeCounts(localRestaurants, localVisits, localPhotos)
    const cloudCountsBefore = activeCounts(cloudBefore.restaurants, cloudBefore.visits, cloudBefore.photos)
    const cloudIsCompletelyEmpty = cloudBefore.restaurants.length === 0 && cloudBefore.visits.length === 0
    const localHasData = localCounts.restaurants > 0 || localCounts.visits > 0

    if (cloudIsCompletelyEmpty && localHasData && !allowInitialUpload) {
      updateState({
        status: 'migrationRequired',
        localCounts,
        cloudCounts: cloudCountsBefore,
        errorMessage: null,
      })
      await storeMetadata('migrationRequired', attemptAt, null)
      return { localCounts, cloudCounts: cloudCountsBefore, migrationRequired: true }
    }

    const cloudAfter = await pushLocalSnapshot(localRestaurants, localVisits, localPhotos)
    const merged = mergeCloudData(localRestaurants, localVisits, localPhotos, cloudAfter)
    await db.transaction(
      'rw',
      db.restaurants,
      db.visits,
      db.photos,
      db.syncQueue,
      db.syncMetadata,
      async () => {
        for (const restaurant of merged.restaurants) {
          const current = await db.restaurants.get(restaurant.id)
          if (!current || current.updatedAt <= restaurant.updatedAt) await db.restaurants.put(restaurant)
        }
        for (const visit of merged.visits) {
          const current = await db.visits.get(visit.id)
          if (!current || current.updatedAt <= visit.updatedAt) await db.visits.put(visit)
        }
        for (const photo of merged.photos) {
          const current = await db.photos.get(photo.id)
          if (!current || current.updatedAt <= photo.updatedAt) await db.photos.put(photo)
        }
        await clearCompletedQueueItems(queuedAtStart)
        await db.syncMetadata.put({
          key: 'cloud',
          status: 'synced',
          lastSyncAttemptAt: attemptAt,
          lastSuccessfulSyncAt: cloudAfter.serverTime,
          errorMessage: null,
        })
      },
    )

    const cloudCounts = activeCounts(cloudAfter.restaurants, cloudAfter.visits, cloudAfter.photos)
    updateState({
      status: 'synced',
      lastSuccessfulSyncAt: cloudAfter.serverTime,
      errorMessage: null,
      localCounts: activeCounts(merged.restaurants, merged.visits, merged.photos),
      cloudCounts,
    })
    return { localCounts: activeCounts(merged.restaurants, merged.visits, merged.photos), cloudCounts, migrationRequired: false }
  } catch (error) {
    const message = error instanceof Error ? error.message : '云端同步失败，请稍后重试。'
    updateState({ status: 'error', errorMessage: message })
    await storeMetadata('error', attemptAt, message)
    throw error
  }
}

async function fetchCloudSnapshot(): Promise<CloudSnapshot> {
  const response = await fetch(API_PATH, { headers: { Accept: 'application/json' }, cache: 'no-store' })
  return readSyncResponse(response)
}

async function pushLocalSnapshot(
  restaurants: Restaurant[],
  visits: Visit[],
  photos: Photo[],
) {
  const response = await fetch(API_PATH, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      restaurants: restaurants.map(toCloudRestaurant),
      visits: visits.map(toCloudVisit),
      photos: photos.map(toCloudPhoto),
    }),
  })
  return readSyncResponse(response)
}

async function readSyncResponse(response: Response): Promise<CloudSnapshot> {
  const payload = await response.json().catch(() => null)
  if (!response.ok) {
    const message = isRecord(payload) && typeof payload.error === 'string'
      ? payload.error
      : `云端同步请求失败（${response.status}）`
    throw new Error(message)
  }
  if (!isCloudSnapshot(payload)) throw new Error('云端返回的数据格式无法识别。')
  return payload
}

async function clearCompletedQueueItems(items: SyncQueueItem[]) {
  for (const item of items) {
    const current = await db.syncQueue.get(item.id)
    if (current?.updatedAt === item.updatedAt) await db.syncQueue.delete(item.id)
  }
}

async function storeMetadata(status: StoredSyncStatus, attemptAt: string, errorMessage: string | null) {
  try {
    const existing = await db.syncMetadata.get('cloud')
    await db.syncMetadata.put({
      key: 'cloud',
      status,
      lastSyncAttemptAt: attemptAt,
      lastSuccessfulSyncAt: existing?.lastSuccessfulSyncAt ?? null,
      errorMessage,
    })
  } catch {
    // 同步元数据失败不能影响餐厅数据，也不能覆盖真正的同步错误。
  }
}

function updateState(changes: Partial<CloudSyncState>) {
  state = { ...state, ...changes }
  listeners.forEach((listener) => listener())
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object'
}

function isCloudSnapshot(value: unknown): value is CloudSnapshot {
  if (!isRecord(value)) return false
  return Array.isArray(value.restaurants) && Array.isArray(value.visits) && Array.isArray(value.photos) && typeof value.serverTime === 'string'
}
