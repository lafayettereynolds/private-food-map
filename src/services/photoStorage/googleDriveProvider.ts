import { deleteGoogleDrivePhoto, downloadGoogleDrivePhoto, getGoogleDriveState, uploadGoogleDrivePhoto } from '../googleDrive'
import type { PhotoStorageProvider } from './types'

export const googleDrivePhotoStorageProvider: PhotoStorageProvider = {
  id: 'google-drive',
  isAvailable: () => getGoogleDriveState().status === 'connected',
  async upload(photoId, blob, variant = 'original') {
    const uploadId = variant === 'thumbnail' ? `${photoId}-thumbnail` : photoId
    const uploaded = await uploadGoogleDrivePhoto(uploadId, blob)
    return { storageKey: uploaded.driveFileId, fileName: uploaded.fileName, fileSize: uploaded.fileSize }
  },
  download: downloadGoogleDrivePhoto,
  delete: deleteGoogleDrivePhoto,
}
