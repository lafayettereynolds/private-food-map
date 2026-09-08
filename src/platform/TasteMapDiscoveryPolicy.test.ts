import { describe, expect, it } from 'vitest'
import type {
  TasteMapHybridActivityItemDTO,
  TasteMapHybridDiscoveryItemDTO,
} from './TasteMapPlatform'
import {
  isDiscoveryFeedActivityEligible,
  isDiscoveryPlacementEligible,
} from './TasteMapDiscoveryPolicy'

describe('Discovery evidence eligibility', () => {
  it('requires 7.5/10 for Following/Latest while preserving non-Visit social intent', () => {
    const rated = activity({ kind: 'visit', visitID: 'visit-1', visitRating: 4.5 })
    const boundary = activity({ kind: 'visit', visitID: 'visit-boundary', visitRating: 3.75 })
    const belowBoundary = activity({ kind: 'visit', visitID: 'visit-low', visitRating: 3.5 })
    const unrated = activity({ kind: 'visit', visitID: 'visit-2', visitRating: null })
    const wantToGo = activity({ kind: 'want_to_go', visitID: null, visitRating: null })

    expect(isDiscoveryFeedActivityEligible(rated)).toBe(true)
    expect(isDiscoveryFeedActivityEligible(boundary)).toBe(true)
    expect(isDiscoveryFeedActivityEligible(belowBoundary)).toBe(false)
    expect(isDiscoveryFeedActivityEligible(unrated)).toBe(false)
    expect(isDiscoveryFeedActivityEligible(wantToGo)).toBe(true)
  })

  it('requires rated concrete evidence except for count-based Trends and system recommendations', () => {
    const systemForYou = placement({ mode: 'for_you' })
    const unratedForYouActivity = placement({
      mode: 'for_you', activityRating: null, activityVisitedAt: '2026-09-04T10:00:00Z',
    })
    const unratedSimilar = placement({ mode: 'similar_taste', activityRating: null })
    const lowSimilar = placement({ mode: 'similar_taste', activityRating: 3.5 })
    const boundarySimilar = placement({ mode: 'similar_taste', activityRating: 3.75 })
    const unratedTrend = placement({ mode: 'trending', activityRating: null })

    expect(isDiscoveryPlacementEligible(systemForYou)).toBe(true)
    expect(isDiscoveryPlacementEligible(unratedForYouActivity)).toBe(false)
    expect(isDiscoveryPlacementEligible(unratedSimilar)).toBe(false)
    expect(isDiscoveryPlacementEligible(lowSimilar)).toBe(false)
    expect(isDiscoveryPlacementEligible(boundarySimilar)).toBe(true)
    expect(isDiscoveryPlacementEligible(unratedTrend)).toBe(true)
  })
})

function activity(overrides: Partial<TasteMapHybridActivityItemDTO>): TasteMapHybridActivityItemDTO {
  return {
    id: 'activity', kind: 'visit', eventAt: '2026-09-04T10:00:00Z',
    user: { id: 'user', name: '用户', city: '杭州', avatarPhotoID: null, avatarPresetID: 'otter', isFollowing: true },
    restaurant: restaurant(), visitID: 'visit', interaction: null, visitRating: 4.5,
    note: null, viewerState: 'none', likedByViewer: false, likeCount: 0, commentCount: 0,
    ...overrides,
  }
}

function placement(overrides: Partial<TasteMapHybridDiscoveryItemDTO>): TasteMapHybridDiscoveryItemDTO {
  return {
    id: 'placement', mode: 'for_you', restaurant: restaurant(), viewerState: 'none', sourceUser: null,
    activityRating: null, activityVisitedAt: null, interaction: null, likedByViewer: false,
    likeCount: 0, commentCount: 0, communityRating: { valueOutOfFive: 4.5, sampleCount: 12 },
    reasons: [], reason: '', similarityPercent: null, sharedRestaurantCount: null,
    trendWindowDays: null, uniqueVisitorCount: null, wantToGoCount: null, rank: 1,
    ...overrides,
  }
}

function restaurant(): TasteMapHybridActivityItemDTO['restaurant'] {
  return {
    id: 'restaurant', name: '餐厅', address: '地址', city: '杭州', latitude: 30.2, longitude: 120.1,
    tags: [], referencePrice: null, image: {
      kind: 'foodCategoryVisual', categoryVisualID: 'chinese', stableSeed: 'restaurant',
      exportAllowed: false, accessibilityLabel: '餐厅',
    },
  }
}
