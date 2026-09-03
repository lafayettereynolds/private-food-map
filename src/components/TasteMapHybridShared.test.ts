import { describe, expect, it } from 'vitest'
import type { TasteMapImageResolutionDTO } from '../platform/TasteMapPlatform'
import { resolvedImageDescriptor } from './TasteMapImageResolution'

describe('Hybrid canonical Restaurant image plan', () => {
  const resolution: TasteMapImageResolutionDTO = {
    sources: [
      {
        kind: 'nativeResource',
        resourceURL: 'tastemap-resource://photo/owner-photo/display',
        photoID: 'owner-photo',
        accessibilityLabel: '用户实拍',
      },
      {
        kind: 'publicOrCached',
        resourceURL: 'tastemap-resource://public-photo/public-photo/display',
        photoID: 'public-photo',
        accessibilityLabel: '公开餐厅图片',
      },
      {
        kind: 'providerMerchant',
        resourceURL: 'https://images.example.test/provider.jpg',
        accessibilityLabel: '商户餐厅图片',
      },
    ],
    fallback: {
      kind: 'foodDiningFallback',
      stableSeed: 'restaurant-1',
      accessibilityLabel: '暂无真实餐厅图片',
    },
  }

  it('advances through the Native-owned failure chain before fallback', () => {
    expect(resolvedImageDescriptor(resolution, 0).kind).toBe('nativeResource')
    expect(resolvedImageDescriptor(resolution, 1).kind).toBe('publicOrCached')
    expect(resolvedImageDescriptor(resolution, 2).kind).toBe('providerMerchant')
    expect(resolvedImageDescriptor(resolution, 3)).toEqual(resolution.fallback)
  })

  it('does not mutate or reorder the plan shared by Search and Nearby', () => {
    const searchKinds = [0, 1, 2, 3].map((index) => resolvedImageDescriptor(resolution, index).kind)
    const nearbyKinds = [0, 1, 2, 3].map((index) => resolvedImageDescriptor(resolution, index).kind)
    expect(nearbyKinds).toEqual(searchKinds)
    expect(resolution.sources.map((source) => source.kind)).toEqual([
      'nativeResource', 'publicOrCached', 'providerMerchant',
    ])
  })
})
