export const CLOUD_SYNC_REQUEST_EVENT = 'taste-map:cloud-sync-requested'

export function requestCloudSync() {
  if (typeof window === 'undefined') return
  window.dispatchEvent(new Event(CLOUD_SYNC_REQUEST_EVENT))
}
