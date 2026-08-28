import { describe, expect, it } from 'vitest'
import {
  decodeOwnProfileSyncContract,
  ProfileContractError,
  type OwnProfileSyncContractV1,
} from './profileContract'

const valid: OwnProfileSyncContractV1 = {
  schemaVersion: 1,
  userId: 'tm_profile_contract',
  displayName: 'Lafayette 🍜',
  bio: '认真记录每一顿。',
  city: '杭州',
  avatarPhotoId: null,
  avatarPresetId: 'otter',
  visibility: 'public',
  createdAt: '2026-08-28T08:00:00.000Z',
  updatedAt: '2026-08-28T08:00:00.000Z',
  deletedAt: null,
}

describe('Profile V1 contract', () => {
  it('round-trips explicit required and nullable fields without guessing', () => {
    expect(decodeOwnProfileSyncContract(JSON.parse(JSON.stringify(valid)))).toEqual(valid)
    expect(decodeOwnProfileSyncContract({ ...valid, avatarPhotoId: 'avatar-photo-id' }).avatarPhotoId)
      .toBe('avatar-photo-id')
  })

  it('trims editable text and allows Unicode/emoji display names', () => {
    expect(decodeOwnProfileSyncContract({
      ...valid, displayName: '  小林 🍣  ', bio: '  一起吃饭  ', city: '  上海  ',
    })).toMatchObject({ displayName: '小林 🍣', bio: '一起吃饭', city: '上海' })
  })

  it.each([
    { displayName: '   ' },
    { displayName: '好'.repeat(201) },
    { bio: '介'.repeat(161) },
    { city: '城'.repeat(31) },
    { avatarPresetId: 'invented-avatar' },
    { visibility: 'everyone' },
    { avatarPhotoId: '' },
    { deletedAt: '2026-08-28T08:00:00.000Z' },
  ])('rejects invalid Profile mutations: %o', (changes) => {
    expect(() => decodeOwnProfileSyncContract({ ...valid, ...changes }))
      .toThrow(ProfileContractError)
  })

  it('keeps a legacy display name lossless and rejects ambiguous object shapes', () => {
    expect(decodeOwnProfileSyncContract({ ...valid, displayName: '旧版昵称'.repeat(16) }).displayName)
      .toBe('旧版昵称'.repeat(16))
    expect(() => decodeOwnProfileSyncContract({ ...valid, email: 'never-public@example.com' }))
      .toThrow(ProfileContractError)
    const missingNullable = { ...valid } as Record<string, unknown>
    delete missingNullable.avatarPhotoId
    expect(() => decodeOwnProfileSyncContract(missingNullable)).toThrow(ProfileContractError)
  })
})
