export type SyncEntityType = 'restaurant' | 'visit' | 'user' | 'restaurantList' | 'restaurantListItem'
export type SyncOperationStatus = 'pending' | 'syncing' | 'synced' | 'failed'
export type SyncOperationAction = 'upsert' | 'delete'

export interface SyncQueueItem {
  id: string
  operationId?: string
  entityType: SyncEntityType
  entityId: string
  action?: SyncOperationAction
  status?: SyncOperationStatus
  attemptCount?: number
  nextAttemptAt?: string | null
  lastError?: string | null
  createdAt?: string
  updatedAt: string
}

export type StoredSyncStatus = 'idle' | 'syncing' | 'synced' | 'error' | 'migrationRequired'

export interface SyncMetadata {
  key: 'cloud'
  status: StoredSyncStatus
  lastSyncAttemptAt: string | null
  lastSuccessfulSyncAt: string | null
  errorMessage: string | null
}

export function syncQueueId(entityType: SyncEntityType, entityId: string) {
  return `${entityType}:${entityId}`
}
