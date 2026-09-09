import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Photo } from '../types/domain'

const state = vi.hoisted(() => ({ photo: null as Photo | null, objects: new Set<string>(), calls: [] as string[], fail: '' }))
vi.mock('../db/appDb', () => ({ db: { photos: {
  get: async () => state.photo,
  update: async (_id: string, patch: Partial<Photo>) => { Object.assign(state.photo!, patch) },
} } }))
vi.mock('../db/social', () => ({ CURRENT_USER_ID: 'owner' }))
vi.mock('./googleDrive', () => ({ getGoogleDriveState: () => ({ accountId: 'drive-owner' }), subscribeGoogleDrive: vi.fn() }))
vi.mock('./photoAssets', () => ({ cachePhotoBlob: vi.fn(), removeCachedPhoto: vi.fn() }))
vi.mock('./photoStorage', () => ({ activeWebPhotoStorageProvider: vi.fn(), photoStorageProviderFor: () => ({
  delete: async (key: string) => {
    state.calls.push(key)
    if (state.fail === key) throw new Error('network timeout')
    state.objects.delete(key)
  },
}) }))
vi.mock('./syncEvents', () => ({ CLOUD_SYNC_REQUEST_EVENT: 'test', requestCloudSync: vi.fn() }))
import { deletePendingPhoto } from './photoSync'
import { removeCachedPhoto } from './photoAssets'

describe('durable original and thumbnail deletion', () => {
  beforeEach(() => {
    vi.clearAllMocks(); state.calls = []; state.fail = ''; state.objects = new Set(['original', 'thumbnail'])
    state.photo = { id: 'photo', userId: 'owner', driveAccountId: 'drive-owner', storageKey: 'original',
      driveFileId: 'original', thumbnailStorageKey: 'thumbnail', localState: 'delete-pending',
      syncStatus: 'delete-pending', deletedAt: '2026-09-09T00:00:00Z' } as Photo
  })
  it.each(['original', 'thumbnail'])('retains retry state on %s failure and completes after retry', async key => {
    const originalSnapshot = structuredClone(state.photo!)
    state.fail = key
    await expect(deletePendingPhoto(originalSnapshot)).rejects.toThrow('network timeout')
    expect(state.photo?.localState).toBe('delete-pending')
    expect(removeCachedPhoto).not.toHaveBeenCalled()
    const completed = [...state.photo?.deletedStorageKeys ?? []]
    state.fail = ''
    // New caller after restart must read persisted progress, not stale input.
    await deletePendingPhoto(originalSnapshot)
    expect(state.objects.size).toBe(0)
    expect(state.photo?.localState).toBe('synced')
    for (const key of completed) expect(state.calls.filter(call => call === key)).toHaveLength(1)
    expect(removeCachedPhoto).toHaveBeenCalledWith('photo')
  })
  it('continues original cleanup when thumbnail already completed before restart', async () => {
    state.photo!.deletedStorageKeys = ['thumbnail']; state.objects.delete('thumbnail')
    state.fail = 'original'
    await expect(deletePendingPhoto(state.photo!)).rejects.toThrow()
    expect(state.photo?.localState).toBe('delete-pending')
    state.fail = ''
    await deletePendingPhoto(state.photo!)
    expect(state.calls).toEqual(['original', 'original'])
    expect(state.objects.size).toBe(0)
  })
  it('duplicate completed delete performs no further provider operations', async () => {
    await deletePendingPhoto(state.photo!)
    await deletePendingPhoto(state.photo!)
    expect(state.calls).toEqual(['original', 'thumbnail'])
    expect(state.photo?.deletedAt).toBeTruthy()
  })
  it('rejects another owner before provider access', async () => {
    state.photo!.userId = 'other'
    await expect(deletePendingPhoto(state.photo!)).rejects.toThrow('只能删除自己上传的照片')
    expect(state.calls).toEqual([])
    expect(state.objects.size).toBe(2)
  })
})
