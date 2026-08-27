import { describe, expect, it } from 'vitest'
import { buildCompanionInsights, companionAvatarCharacter, companionAvatarThemeIndex, companionInsightConfidence, companionKind, resolveCompanionAvatar, selectCompanionInsights, type CompanionInsights } from './companionInsights'
import type { DiningCompanion, RestaurantSummary, UserProfile, Visit } from '../types/domain'

const companion: DiningCompanion = { id: 'c1', ownerUserId: 'owner', displayName: '小王', linkedUserId: null, createdAt: '', updatedAt: '', deletedAt: null }
const restaurant = { id: 'r1', name: '餐厅 A', city: '杭州', tags: ['日料'] } as RestaurantSummary
function visit(id: string, rating: Visit['rating'], spend: number | null, restaurantId = 'r1'): Visit { return { id, userId: 'owner', restaurantId, visitedAt: `2026-08-${id.padStart(2, '0')}T12:00:00.000Z`, rating, visibility: 'private', diningMode: 'dine_in', totalPrice: 999, myActualSpend: spend, paymentMode: null, pricePerPerson: null, partySize: 2, queueDuration: null, diningOccasions: ['friends'], diningOccasion: null, diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [], noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null, recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: ['小王'], companionIds: ['c1'], dishes: [], note: '', photos: [], photoIds: [], createdAt: '', updatedAt: '', deletedAt: null } }

function compactInsight(id: string, displayName: string, sharedVisitCount: number, latestVisitedAt: string | null): CompanionInsights {
  return {
    companion: { ...companion, id, displayName }, confidence: companionInsightConfidence(sharedVisitCount), sharedVisitCount, latestVisitedAt,
    restaurantCount: sharedVisitCount, repeatRestaurantCount: 0, repeatRate: null, firstVisitedAt: latestVisitedAt, spanDays: 0,
    spend: { total: null, average: null, maximum: null, sampleCount: 0 }, rating: { average: null, ratedVisitCount: 0, highScoreCount: 0 },
    topCuisines: [], topRestaurants: [], diningModes: [], occasions: [], cities: [], memories: [], linkedUserStatus: 'UNLINKED',
  }
}

describe('companion insights', () => {
  it('uses configurable confidence thresholds', () => {
    expect(companionInsightConfidence(2)).toBe('INSUFFICIENT')
    expect(companionInsightConfidence(3)).toBe('EMERGING')
    expect(companionInsightConfidence(6)).toBe('LIGHT')
    expect(companionInsightConfidence(11)).toBe('STABLE')
  })

  it('uses only myActualSpend and keeps repeated restaurants distinct from visit count', () => {
    const result = buildCompanionInsights(companion, [restaurant], [visit('1', 4, 60), visit('2', 5, 80)])
    expect(result.sharedVisitCount).toBe(2)
    expect(result.restaurantCount).toBe(1)
    expect(result.repeatRestaurantCount).toBe(1)
    expect(result.spend.total).toBe(140)
    expect(result.spend.average).toBe(70)
    expect(result.rating.average).toBe(9)
  })

  it('creates stable, readable character avatars without emoji', () => {
    expect(companionAvatarCharacter('妈妈')).toBe('妈')
    expect(companionAvatarCharacter('小王')).toBe('王')
    expect(companionAvatarCharacter('老张')).toBe('张')
    expect(companionAvatarCharacter('Alice')).toBe('A')
    expect(companionAvatarThemeIndex('stable-id')).toBe(companionAvatarThemeIndex('stable-id'))
  })

  it('distinguishes a category-like companion from a person', () => {
    expect(companionKind({ displayName: '朋友' })).toBe('CATEGORY_LIKE')
    expect(companionKind({ displayName: '大学朋友' })).toBe('PERSON')
  })

  it('prioritizes a linked user avatar, then a private avatar', () => {
    const linkedUser = { avatarImageData: 'data:image/png;base64,linked', avatarPhotoId: null } as Pick<UserProfile, 'avatarImageData' | 'avatarPhotoId'>
    const privateCompanion = { ...companion, privateAvatarData: 'data:image/png;base64,private' }
    expect(resolveCompanionAvatar(privateCompanion, linkedUser)).toMatchObject({ kind: 'IMAGE', imageData: linkedUser.avatarImageData })
    expect(resolveCompanionAvatar(privateCompanion, null)).toMatchObject({ kind: 'IMAGE', imageData: 'data:image/png;base64,private' })
    expect(resolveCompanionAvatar(companion, null)).toMatchObject({ kind: 'CHARACTER', character: '王' })
  })

  it('uses a dedicated category avatar for aggregate labels', () => {
    expect(resolveCompanionAvatar({ ...companion, displayName: '同事' }, null).kind).toBe('CATEGORY')
  })

  it('sorts recent companions by latest shared visit and keeps missing dates last', () => {
    const values = [compactInsight('none', '无日期', 9, null), compactInsight('old', '较早', 4, '2026-07-01T12:00:00.000Z'), compactInsight('new', '最近', 2, '2026-08-20T12:00:00.000Z')]
    expect(selectCompanionInsights(values, 'RECENT').map((item) => item.companion.id)).toEqual(['new', 'old', 'none'])
  })

  it('sorts frequent companions by shared count and then recency', () => {
    const values = [compactInsight('low', '少', 2, '2026-08-25T12:00:00.000Z'), compactInsight('older', '多且早', 8, '2026-07-01T12:00:00.000Z'), compactInsight('newer', '多且新', 8, '2026-08-01T12:00:00.000Z')]
    expect(selectCompanionInsights(values, 'FREQUENT').map((item) => item.companion.id)).toEqual(['newer', 'older', 'low'])
  })

  it('defines historical companions by minimum shared visits and inactivity', () => {
    const now = new Date('2026-08-26T12:00:00.000Z')
    const values = [compactInsight('history', '老饭友', 5, '2026-01-01T12:00:00.000Z'), compactInsight('too-few', '记录少', 2, '2026-01-01T12:00:00.000Z'), compactInsight('active', '仍活跃', 7, '2026-08-20T12:00:00.000Z')]
    expect(selectCompanionInsights(values, 'HISTORICAL', '', now).map((item) => item.companion.id)).toEqual(['history'])
  })

  it('combines search with the selected mode', () => {
    const now = new Date('2026-08-26T12:00:00.000Z')
    const values = [compactInsight('wang', '老王', 5, '2026-01-01T12:00:00.000Z'), compactInsight('li', '老李', 6, '2026-01-01T12:00:00.000Z')]
    expect(selectCompanionInsights(values, 'HISTORICAL', '王', now).map((item) => item.companion.id)).toEqual(['wang'])
  })
})
