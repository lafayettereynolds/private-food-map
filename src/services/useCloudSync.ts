import { useSyncExternalStore } from 'react'
import { getCloudSyncState, subscribeCloudSync } from './cloudSync'

export function useCloudSync() {
  return useSyncExternalStore(subscribeCloudSync, getCloudSyncState, getCloudSyncState)
}
