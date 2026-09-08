import { describe, expect, it } from 'vitest'
import { loadTasteMapBrowserDebugFixture } from './TasteMapBrowserDebugFixture'

describe('Restaurant visual product fixture', () => {
  it('provides distinct one/two/multi-photo albums bound to the current Visit only', async () => {
    const { content } = await loadTasteMapBrowserDebugFixture()
    expect(content.discovery.similarTaste.slice(0, 8).map((item) => item.activityImages?.length)).toEqual([1, 2, 4, 5, 6, 7, 0, 3])
    for (const count of [1, 2, 4, 5, 6, 7]) {
      expect(content.discovery.similarTaste.filter((item) => item.activityImages?.length === count)).toHaveLength(1)
      expect(content.community.latest.filter((item) => item.activityImages?.length === count)).toHaveLength(1)
    }
    for (const item of [...content.discovery.similarTaste, ...content.community.latest, ...content.community.following]) {
      const photos = item.activityImages ?? []
      expect(new Set(photos.map((photo) => 'resourceURL' in photo ? photo.resourceURL : null)).size).toBe(photos.length)
      expect(new Set(photos.map((photo) => 'photoID' in photo ? photo.photoID : null)).size).toBe(photos.length)
      for (const photo of photos) {
        expect(photo).toMatchObject({ kind: 'activityPhoto', visitID: item.interaction?.visitID,
          sourceOwnerID: item.interaction?.authorID, restaurantID: item.restaurant.id, exportAllowed: false })
      }
    }
    expect([...content.discovery.forYou, ...content.discovery.trending].every((item) => item.activityImages === undefined)).toBe(true)
    expect(content.community.latest.filter((item) => item.kind === 'want_to_go').every((item) => item.activityImages === undefined)).toBe(true)
  })

  it('exercises owner, public UGC, activity photo and category semantics without fake attribution', async () => {
    const { content } = await loadTasteMapBrowserDebugFixture()
    expect(content.discovery.forYou.slice(0, 3).map((item) => item.restaurant.image.kind)).toEqual([
      'ownerPhoto', 'publicUGC', 'foodCategoryVisual',
    ])
    expect(content.discovery.forYou.every((item) => item.sourceUser == null && item.activityRating == null)).toBe(true)
    expect(content.discovery.similarTaste[0].restaurant.image.kind).toBe('activityPhoto')
    expect(content.discovery.similarTaste[0].sourceUser).not.toBeNull()
    expect(content.discovery.similarTaste.every((item) => (item.activityRating ?? -1) >= 3.75)).toBe(true)
    expect(content.discovery.trending.slice(0, 2).map((item) => item.restaurant.image.kind)).toEqual([
      'publicUGC', 'foodCategoryVisual',
    ])
    expect(content.discovery.trending.every((item) => item.sourceUser == null && item.activityRating == null)).toBe(true)
    expect(content.community.latest[0].restaurant.image.kind).toBe('activityPhoto')
    expect(content.community.latest.filter((item) => item.kind === 'visit').every((item) =>
      (item.visitRating ?? -1) >= 3.75)).toBe(true)
    expect(content.community.latest.some((item) => item.kind === 'want_to_go' && item.visitRating == null)).toBe(true)
    expect(content.community.latest.find((item) => item.id === 'hybrid-activity-6')?.visitRating).toBe(4.5)
    const latestImage = content.community.latest[0].restaurant.image
    expect(latestImage.kind === 'activityPhoto' ? latestImage.exportAllowed : null).toBe(false)
  })

  it('keeps every visible comment count backed by the same visit comment collection', async () => {
    const { commentsByVisit, content } = await loadTasteMapBrowserDebugFixture()
    const interactiveItems = [
      ...content.discovery.similarTaste,
      ...content.community.latest,
    ].filter((item) => item.interaction != null)
    expect(interactiveItems.length).toBeGreaterThan(0)
    for (const item of interactiveItems) {
      expect(commentsByVisit[item.interaction!.visitID]).toHaveLength(item.commentCount)
      expect(commentsByVisit[item.interaction!.visitID].every((comment) => comment.visitID === item.interaction!.visitID)).toBe(true)
    }
  })
})
