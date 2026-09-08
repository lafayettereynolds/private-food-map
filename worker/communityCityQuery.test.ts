import { describe, expect, it } from 'vitest'
import { communityCityKey, decodeCommunityFeedCursor, encodeCommunityFeedCursor } from './communityCityQuery'

describe('community city query scope', () => {
  it.each([[' 杭州市 ', '杭州'], ['温州', '温州'], ['Kansas City', 'kansas city'], ['ＴＯＫＹＯ', 'tokyo'], ['', '']])('normalizes %s conservatively', (value, expected) => {
    expect(communityCityKey(value)).toBe(expected)
  })
  it('requires the same normalized owner, city and feed context', () => {
    const scope = { viewerId: 'viewer', scope: 'latest', city: '杭州' }
    const cursor = encodeCommunityFeedCursor('2026-09-06T00:00:00Z', 'visit-id', Date.parse('2026-09-06T01:00:00Z'), scope)
    expect(decodeCommunityFeedCursor(cursor, scope).id).toBe('visit-id')
    for (const different of [{ ...scope, city: '' }, { ...scope, city: '成都' }, { ...scope, viewerId: 'other' }, { ...scope, scope: 'following' }]) {
      expect(() => decodeCommunityFeedCursor(cursor, different)).toThrow()
    }
  })
  it('rejects malformed dates, oversized cursors and out-of-range timestamps', () => {
    const scope = { viewerId: 'viewer', scope: 'latest', city: '杭州' }
    expect(() => decodeCommunityFeedCursor('x'.repeat(4097), scope)).toThrow()
    expect(() => decodeCommunityFeedCursor(encodeCommunityFeedCursor('not-a-date', 'id', 1, scope), scope)).toThrow()
    expect(() => decodeCommunityFeedCursor(encodeCommunityFeedCursor('2026-09-06T00:00:00Z', 'id', 1e200, scope), scope)).toThrow()
  })
})
