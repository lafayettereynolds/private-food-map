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

export type LegacyWebBackupV4IssueSeverity = 'info' | 'warning' | 'requiresReview' | 'blocking'

/**
 * Architecture boundary for the native strict decoder. Source IDs remain
 * non-authoritative references and the normalized graph is intentionally not
 * typed as Backup v1 entities. F1-C1 does not provide a TypeScript converter.
 */
export interface LegacyWebBackupV4StagingBoundary {
  sourceLineage: 'legacy-web-v4'
  sourceVersion: 4
  sourceIdsAreNonAuthoritative: true
  sourceFingerprint: string
  normalizedEntityCounts: Readonly<Record<
    | 'restaurants' | 'visits' | 'dishes' | 'visitDishes' | 'photos'
    | 'companions' | 'recommendationSources' | 'profiles'
    | 'restaurantLists' | 'restaurantListItems' | 'tombstones',
    number
  >>
  issueCounts: Readonly<Record<LegacyWebBackupV4IssueSeverity, number>>
}
