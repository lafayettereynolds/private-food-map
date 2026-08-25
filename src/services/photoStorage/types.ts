export type PhotoStorageProviderId = 'google-drive' | 'cloudkit' | 'r2' | 'oss' | 'cos'

export interface StoredPhotoObject {
  storageKey: string
  fileName: string | null
  fileSize: number
}

export interface PhotoStorageProvider {
  readonly id: PhotoStorageProviderId
  isAvailable(): boolean
  upload(photoId: string, blob: Blob, variant?: 'original' | 'thumbnail'): Promise<StoredPhotoObject>
  download(storageKey: string): Promise<Blob>
  delete(storageKey: string): Promise<void>
}
