import { describe, expect, it } from 'vitest'
import type { TasteMapImageResolutionDTO } from '../platform/TasteMapPlatform'
import { resolvedImageDescriptor } from './TasteMapImageResolution'

describe('Hybrid canonical Restaurant image plan', () => {
  const resolution: TasteMapImageResolutionDTO = {
    sources: [
      {
        kind: 'ownerPhoto',
        resourceURL: 'tastemap-resource://photo/owner-photo/display',
        photoID: 'owner-photo',
        restaurantID: 'restaurant-1',
        visitID: 'visit-owner',
        sourceOwnerID: 'tm_viewer',
        visibility: 'private',
        exportAllowed: true,
        attributionRequired: false,
        accessibilityLabel: '用户实拍',
      },
      {
        kind: 'publicUGC',
        resourceURL: 'tastemap-resource://public-photo/public-photo/display',
        photoID: 'public-photo',
        restaurantID: 'restaurant-1',
        visitID: 'visit-public',
        sourceOwnerID: 'tm_author',
        visibility: 'public',
        exportAllowed: false,
        attributionRequired: false,
        accessibilityLabel: '公开餐厅图片',
      },
    ],
    fallback: {
      kind: 'foodCategoryVisual',
      categoryVisualID: 'hotpotBBQ',
      stableSeed: 'restaurant-1',
      exportAllowed: false,
      accessibilityLabel: '火锅分类图示',
    },
  }

  it('advances through the Native-owned failure chain before fallback', () => {
    expect(resolvedImageDescriptor(resolution, 0).kind).toBe('ownerPhoto')
    expect(resolvedImageDescriptor(resolution, 1).kind).toBe('publicUGC')
    expect(resolvedImageDescriptor(resolution, 2)).toEqual(resolution.fallback)
  })

  it('does not mutate or reorder the plan shared by Search and Nearby', () => {
    const searchKinds = [0, 1, 2].map((index) => resolvedImageDescriptor(resolution, index).kind)
    const nearbyKinds = [0, 1, 2].map((index) => resolvedImageDescriptor(resolution, index).kind)
    expect(nearbyKinds).toEqual(searchKinds)
    expect(resolution.sources.map((source) => source.kind)).toEqual(['ownerPhoto', 'publicUGC'])
    expect(resolution.fallback.kind).toBe('foodCategoryVisual')
  })
})
