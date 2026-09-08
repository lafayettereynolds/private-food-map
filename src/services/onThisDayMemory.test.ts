import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary, Visit } from '../types/domain'
import { exactMemoryReview, nearbyMemoryVisits } from './onThisDayMemory'
const restaurant = { ...fixture.restaurants[0], id: 'r', deletedAt: null } as unknown as RestaurantSummary
const visit = (id: string, date: string, deleted = false) => ({ ...fixture.restaurants[0].visits[0], id, restaurantId: 'r', visitedAt: date, rating: null, photos: [], photoIds: [], dishes: [], companions: [], note: '', deletedAt: deleted ? '2026-01-01' : null }) as Visit
describe('V2 exact and nearby memories', () => {
  it('keeps each prior-year same-day Visit, excludes current year, deleted and orphaned records', () => {
    const values = [visit('a', '2025-09-07T12:00:00'), visit('b', '2025-09-07T19:00:00'), visit('old', '2024-09-07'), visit('current', '2026-09-07'), visit('deleted', '2025-09-07', true), { ...visit('orphan', '2025-09-07'), restaurantId: 'missing' }]
    const review = exactMemoryReview([restaurant], values, new Date('2026-09-07T12:00:00'))
    expect(review.memories.map(item => item.visitId)).toEqual(['b', 'a', 'old'])
    expect(review.memories.every(item => item.scoreOutOfTen === null)).toBe(true)
  })
  it('does not relabel nearby dates as exact-day memories', () => {
    const values = [visit('exact', '2025-09-07T12:00:00'), visit('near', '2025-09-06T12:00:00'), visit('far', '2025-09-01T12:00:00')]
    const date = new Date('2026-09-07T12:00:00')
    expect(nearbyMemoryVisits([restaurant], values, date).map(item => item.id)).toEqual(['near'])
    expect(exactMemoryReview([restaurant], values, date).memories.map(item => item.visitId)).toEqual(['exact'])
  })
  it('matches leap days strictly and preserves the original Visit', () => {
    const values = [visit('leap', '2024-02-29T12:00:00')]; const before = JSON.stringify(values)
    expect(exactMemoryReview([restaurant], values, new Date('2028-02-29T12:00:00')).memories).toHaveLength(1)
    expect(exactMemoryReview([restaurant], values, new Date('2026-02-28T12:00:00')).memories).toHaveLength(0)
    expect(JSON.stringify(values)).toBe(before)
  })
})
