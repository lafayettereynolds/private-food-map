import type { Photo, Restaurant, Visit, VisitDish } from './domain'

export type CloudRestaurant = Omit<Restaurant, 'markerImageData'>
export type CloudVisitDish = Omit<VisitDish, 'imageData'>
export type CloudVisit = Omit<Visit, 'dishes' | 'photos'> & { dishes: CloudVisitDish[] }
export type CloudPhoto = Omit<Photo, 'localState' | 'lastError'>

export interface CloudSnapshot {
  restaurants: CloudRestaurant[]
  visits: CloudVisit[]
  photos: CloudPhoto[]
  serverTime: string
}

export interface SyncCounts {
  restaurants: number
  visits: number
  photos: number
}

export type CloudSyncStatus =
  | 'disabled'
  | 'idle'
  | 'syncing'
  | 'synced'
  | 'error'
  | 'migrationRequired'

export interface CloudSyncState {
  status: CloudSyncStatus
  lastSuccessfulSyncAt: string | null
  errorMessage: string | null
  localCounts: SyncCounts | null
  cloudCounts: SyncCounts | null
}

export interface CloudSyncResult {
  localCounts: SyncCounts
  cloudCounts: SyncCounts
  migrationRequired: boolean
}
