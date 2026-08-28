import { describe, expect, it } from 'vitest'
import {
  decodeDiningCompanionSyncContract,
  decodeRecommendationSourceSyncContract,
  normalizedPrivateDirectoryName,
} from './companionSourceContract'

const at = '2026-08-28T08:00:00.000Z'

describe('P2-F private directory JSON contracts', () => {
  it('normalizes Unicode compatibility forms and whitespace conservatively', () => {
    expect(normalizedPrivateDirectoryName('  大学\u3000室友  Ａlex  ')).toBe('大学 室友 Alex')
    expect(normalizedPrivateDirectoryName('Alex')).not.toBe(normalizedPrivateDirectoryName('alex'))
  })

  it('round-trips a companion without requiring a linked Taste Map user', () => {
    expect(decodeDiningCompanionSyncContract({
      schemaVersion: 1, id: 'companion-1', userId: 'claimed-owner', displayName: ' 小王 ',
      linkedTasteMapUserId: null, createdAt: at, updatedAt: at, deletedAt: null,
    })).toEqual({
      schemaVersion: 1, id: 'companion-1', userId: 'claimed-owner', displayName: '小王',
      linkedTasteMapUserId: null, createdAt: at, updatedAt: at, deletedAt: null,
    })
  })

  it('round-trips every supported recommendation source type', () => {
    for (const sourceType of ['friend', 'xiaohongshu', 'douyin', 'dianping', 'blogger', 'self', 'other']) {
      expect(decodeRecommendationSourceSyncContract({
        schemaVersion: 1, id: `source-${sourceType}`, userId: 'claimed-owner',
        displayName: `来源 ${sourceType}`, sourceType, linkedTasteMapUserId: null,
        createdAt: at, updatedAt: at, deletedAt: null,
      }).sourceType).toBe(sourceType)
    }
  })

  it('rejects blank names, unknown types, and malformed dates', () => {
    expect(() => decodeDiningCompanionSyncContract({
      schemaVersion: 1, id: 'companion', userId: 'owner', displayName: '   ',
      linkedTasteMapUserId: null, createdAt: at, updatedAt: at, deletedAt: null,
    })).toThrow(/invalid/)
    expect(() => decodeRecommendationSourceSyncContract({
      schemaVersion: 1, id: 'source', userId: 'owner', displayName: '来源',
      sourceType: 'email', linkedTasteMapUserId: null,
      createdAt: 'not-a-date', updatedAt: at, deletedAt: null,
    })).toThrow(/invalid/)
  })
})
