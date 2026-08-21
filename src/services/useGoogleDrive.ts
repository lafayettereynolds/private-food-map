import { useSyncExternalStore } from 'react'
import { getGoogleDriveState, subscribeGoogleDrive } from './googleDrive'

export function useGoogleDrive() {
  return useSyncExternalStore(subscribeGoogleDrive, getGoogleDriveState, getGoogleDriveState)
}
