import { describe, expect, it } from 'vitest'
import { loadTasteMapBrowserDebugFixture } from './TasteMapBrowserDebugFixture'

describe('Restaurant visual product fixture', () => {
  it('exercises owner, public UGC, activity photo and category semantics without fake attribution', async () => {
    const { content } = await loadTasteMapBrowserDebugFixture()
    expect(content.discovery.forYou.slice(0, 3).map((item) => item.restaurant.image.kind)).toEqual([
      'ownerPhoto', 'publicUGC', 'foodCategoryVisual',
    ])
    expect(content.discovery.forYou.every((item) => item.sourceUser == null && item.activityRating == null)).toBe(true)
    expect(content.discovery.similarTaste[0].restaurant.image.kind).toBe('activityPhoto')
    expect(content.discovery.similarTaste[0].sourceUser).not.toBeNull()
    expect(content.discovery.similarTaste.every((item) => item.activityRating != null)).toBe(true)
    expect(content.discovery.trending.slice(0, 2).map((item) => item.restaurant.image.kind)).toEqual([
      'publicUGC', 'foodCategoryVisual',
    ])
    expect(content.discovery.trending.every((item) => item.sourceUser == null && item.activityRating == null)).toBe(true)
    expect(content.community.latest[0].restaurant.image.kind).toBe('activityPhoto')
    const latestImage = content.community.latest[0].restaurant.image
    expect(latestImage.kind === 'activityPhoto' ? latestImage.exportAllowed : null).toBe(false)
  })

  it('keeps every visible comment count backed by the same visit comment collection', async () => {
    const { commentsByVisit, content } = await loadTasteMapBrowserDebugFixture()
    for (const item of content.discovery.forYou) {
      expect(item.interaction).not.toBeNull()
      expect(commentsByVisit[item.interaction!.visitID]).toHaveLength(item.commentCount)
      expect(commentsByVisit[item.interaction!.visitID].every((comment) => comment.visitID === item.interaction!.visitID)).toBe(true)
    }
  })
})
