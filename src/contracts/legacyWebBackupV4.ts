import type { BackupEntitiesV1, BackupTombstoneV1 } from './backupV1'

/**
 * Exact lineage marker for the current Dexie dump. It is not schemaVersion 4
 * of `com.tastemap.backup`; it predates and is unrelated to Backup v1.
 * Entity payloads stay unknown until a future strict legacy decoder validates
 * and normalizes them.
 */
export interface LegacyWebBackupV4 {
  app: 'Taste Map'
  version: 4
  environment: string
  databaseName: string
  exportedAt: string
  restaurants: unknown[]
  visits: unknown[]
  photos: unknown[]
  users: unknown[]
  friendships: unknown[]
  sharedMeals: unknown[]
  sharedMealParticipants: unknown[]
  restaurantLists: unknown[]
  restaurantListItems: unknown[]
}

/** Boundary only; F1-B1 deliberately provides no legacy converter. */
export interface LegacyWebBackupV4StagingBoundary {
  sourceLineage: 'legacy-web-v4'
  sourceVersion: 4
  normalizedEntities: BackupEntitiesV1
  tombstones: BackupTombstoneV1[]
  unsupportedFields: string[]
}
