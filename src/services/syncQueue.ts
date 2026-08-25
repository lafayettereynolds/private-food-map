import { db } from '../db/appDb'
import { syncQueueId, type SyncEntityType, type SyncOperationAction, type SyncQueueItem } from '../types/sync'

export async function enqueueSyncOperation(
  entityType: SyncEntityType,
  entityId: string,
  updatedAt: string,
  action: SyncOperationAction = 'upsert',
) {
  const id = syncQueueId(entityType, entityId)
  const current = await db.syncQueue.get(id)
  const item: SyncQueueItem = {
    id,
    operationId: current?.operationId ?? id,
    entityType,
    entityId,
    action,
    status: 'pending',
    attemptCount: current?.attemptCount ?? 0,
    nextAttemptAt: null,
    lastError: null,
    createdAt: current?.createdAt ?? updatedAt,
    updatedAt,
  }
  await db.syncQueue.put(item)
  return item
}

export function normalizedSyncOperation(item: SyncQueueItem): Required<Omit<SyncQueueItem, 'nextAttemptAt' | 'lastError'>> & Pick<SyncQueueItem, 'nextAttemptAt' | 'lastError'> {
  return {
    ...item,
    operationId: item.operationId ?? item.id,
    action: item.action ?? 'upsert',
    status: item.status ?? 'pending',
    attemptCount: item.attemptCount ?? 0,
    nextAttemptAt: item.nextAttemptAt ?? null,
    lastError: item.lastError ?? null,
    createdAt: item.createdAt ?? item.updatedAt,
  }
}

export function retryDelayMilliseconds(attemptCount: number) {
  return Math.min(5 * 60_000, 1_000 * 2 ** Math.min(8, Math.max(0, attemptCount)))
}
