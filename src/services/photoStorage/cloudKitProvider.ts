import type { PhotoStorageProvider, StoredPhotoObject } from './types'

interface CloudKitPhotoBridge {
  upload(photoId: string, blob: Blob, variant: 'original' | 'thumbnail'): Promise<StoredPhotoObject>
  download(storageKey: string): Promise<Blob>
  delete(storageKey: string): Promise<void>
}

declare global {
  interface Window { tasteMapNative?: { cloudKitPhotos?: CloudKitPhotoBridge } }
}

/** Native iOS can inject this bridge without changing Visit, Restaurant, or Feed code. */
export const cloudKitPhotoStorageProvider: PhotoStorageProvider = {
  id: 'cloudkit',
  isAvailable: () => Boolean(window.tasteMapNative?.cloudKitPhotos),
  upload(photoId, blob, variant = 'original') {
    const bridge = requireBridge()
    return bridge.upload(photoId, blob, variant)
  },
  download(storageKey) { return requireBridge().download(storageKey) },
  delete(storageKey) { return requireBridge().delete(storageKey) },
}

function requireBridge() {
  const bridge = window.tasteMapNative?.cloudKitPhotos
  if (!bridge) throw new Error('CloudKit 图片服务暂不可用，照片会保留在本地等待同步。')
  return bridge
}
