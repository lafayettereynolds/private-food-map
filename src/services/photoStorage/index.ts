import type { Photo } from '../../types/domain'
import { cloudKitPhotoStorageProvider } from './cloudKitProvider'
import { googleDrivePhotoStorageProvider } from './googleDriveProvider'
import type { PhotoStorageProvider } from './types'

const providers = new Map<string, PhotoStorageProvider>([
  [googleDrivePhotoStorageProvider.id, googleDrivePhotoStorageProvider],
  [cloudKitPhotoStorageProvider.id, cloudKitPhotoStorageProvider],
])

export function photoStorageProviderFor(photo: Pick<Photo, 'storageProvider'>) {
  const provider = providers.get(photo.storageProvider)
  if (!provider) throw new Error(`暂不支持 ${photo.storageProvider} 图片存储。`)
  return provider
}

export function activeWebPhotoStorageProvider() {
  return googleDrivePhotoStorageProvider
}

export type { PhotoStorageProvider, PhotoStorageProviderId, StoredPhotoObject } from './types'
