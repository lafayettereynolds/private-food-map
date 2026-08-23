export type SyncEntityType = 'restaurant' | 'visit' | 'user'

export interface SyncQueueItem {
  id: string
  entityType: SyncEntityType
  entityId: string
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
