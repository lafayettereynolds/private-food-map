import { beforeEach, describe, expect, it, vi } from 'vitest'

const stores = vi.hoisted(() => ({ cache: vi.fn(), photo: vi.fn() }))
vi.mock('../db/appDb', () => ({ db: { photoCache: { get: stores.cache }, photos: { get: stores.photo } } }))
vi.mock('./googleDrive', () => ({ getGoogleDriveState: vi.fn() }))
vi.mock('./photoStorage', () => ({ photoStorageProviderFor: vi.fn() }))
vi.mock('./cloudSyncData', () => ({ photoIdFromReference: () => null }))
import { resolvePhotoSource } from './photoAssets'

describe('Native and Browser photo namespaces', () => {
  beforeEach(() => { vi.clearAllMocks(); stores.cache.mockResolvedValue(undefined); stores.photo.mockResolvedValue(undefined) })
  it.each(['photo', 'public-photo', 'photo-draft'])('keeps the authorized %s resource even with an explicit ID', async host => {
    const source = `tastemap-resource://${host}/opaque-avatar-id/display`
    expect(await resolvePhotoSource(source, 'opaque-avatar-id')).toBe(source)
    expect(stores.cache).not.toHaveBeenCalled()
    expect(stores.photo).not.toHaveBeenCalled()
  })
  it('keeps ordinary Browser ID lookup and does not invent Native access', async () => {
    expect(await resolvePhotoSource(null, 'browser-photo')).toBeNull()
    expect(stores.cache).toHaveBeenCalledWith('browser-photo')
    expect(stores.photo).toHaveBeenCalledWith('browser-photo')
  })
  it('preserves a Browser inline image without a photo ID', async () => {
    expect(await resolvePhotoSource('data:image/png;base64,fixture')).toBe('data:image/png;base64,fixture')
    expect(stores.photo).not.toHaveBeenCalled()
  })
})
