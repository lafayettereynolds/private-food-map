import { useSyncExternalStore } from 'react'
import { getPhotoSyncState, subscribePhotoSync } from './photoSync'

export function usePhotoSync() {
  return useSyncExternalStore(subscribePhotoSync, getPhotoSyncState, getPhotoSyncState)
}
