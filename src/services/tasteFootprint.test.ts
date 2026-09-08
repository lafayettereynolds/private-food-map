import { describe, expect, it } from 'vitest'
import type { RestaurantSummary, Visit } from '../types/domain'
import { buildTasteFootprintEvents } from './tasteFootprint'

function restaurant(id: string, overrides: Partial<RestaurantSummary> = {}): RestaurantSummary {
  return {
    id,
    name: `餐厅 ${id}`,
    address: '湖滨路 1 号',
    city: '杭州',
    status: 'visited',
    createdAt: '2026-09-01T08:00:00Z',
    deletedAt: null,
    visits: [],
    ...overrides,
  } as RestaurantSummary
}

function visit(id: string, restaurantId: string, visitedAt: string, overrides: Partial<Visit> = {}): Visit {
  return {
    id,
    restaurantId,
    visitedAt,
    rating: null,
    deletedAt: null,
    ...overrides,
  } as Visit
}

describe('buildTasteFootprintEvents', () => {
  it('combines every visit and current want-to-go save in reverse chronological order', () => {
    const visited = restaurant('visited')
    const wanted = restaurant('wanted', { status: 'wantToGo', createdAt: '2026-09-04T08:00:00Z' })
    const events = buildTasteFootprintEvents([visited, wanted], [
      visit('old', visited.id, '2026-09-02T08:00:00Z'),
      visit('new', visited.id, '2026-09-05T08:00:00Z', { rating: 4.5 }),
    ])

    expect(events.map(({ id }) => id)).toEqual(['visit:new', 'wantToGo:wanted', 'visit:old'])
    expect(events.map(({ kind }) => kind)).toEqual(['visit', 'wantToGo', 'visit'])
  })

  it('keeps unrated visits and deduplicates the same visit from embedded summaries', () => {
    const record = visit('unrated', 'place', '2026-09-03T08:00:00Z')
    const place = restaurant('place', { visits: [record, record] })
    const events = buildTasteFootprintEvents([place])

    expect(events).toHaveLength(1)
    expect(events[0]).toMatchObject({ id: 'visit:unrated', kind: 'visit', visit: { rating: null } })
  })

  it('merges separately supplied visits with visits embedded in restaurant summaries', () => {
    const embedded = visit('embedded', 'place', '2026-09-03T08:00:00Z')
    const supplied = visit('supplied', 'place', '2026-09-04T08:00:00Z')
    const events = buildTasteFootprintEvents([restaurant('place', { visits: [embedded] })], [supplied])

    expect(events.map(({ id }) => id)).toEqual(['visit:supplied', 'visit:embedded'])
  })

  it('does not invent events for deleted data, visited restaurant creation, or orphan visits', () => {
    const events = buildTasteFootprintEvents([
      restaurant('visited'),
      restaurant('deleted-want', { status: 'wantToGo', deletedAt: '2026-09-05T00:00:00Z' }),
    ], [
      visit('deleted', 'visited', '2026-09-05T08:00:00Z', { deletedAt: '2026-09-05T09:00:00Z' }),
      visit('orphan', 'missing', '2026-09-05T08:00:00Z'),
    ])

    expect(events).toEqual([])
  })

  it('uses the newly refreshed Visit and removes deleted duplicates from stale embedded summaries', () => {
    const before = visit('edited', 'place', '2026-09-02T08:00:00Z', { note: '旧笔记', rating: 4 })
    const removed = visit('removed', 'place', '2026-09-03T08:00:00Z')
    const place = restaurant('place', { visits: [before, removed] })
    const after = { ...before, visitedAt: '2026-09-05T08:00:00Z', note: '已保存的新笔记', rating: null }
    const events = buildTasteFootprintEvents([place], [after, { ...removed, deletedAt: '2026-09-05T09:00:00Z' }])

    expect(events).toHaveLength(1)
    expect(events[0]).toMatchObject({ id: 'visit:edited', eventAt: after.visitedAt, visit: { note: '已保存的新笔记', rating: null } })
  })
})
