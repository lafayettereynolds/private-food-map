import { describe, expect, it } from 'vitest'
import { readingRouteKey } from './AnalysisReadingUI'

describe('Reading navigation repeat-tap identity', () => {
  it('recognizes the same destination independent of object property order', () => {
    expect(readingRouteKey({ page: 'D03' })).toBe(readingRouteKey({ page: 'D03', entity: undefined }))
    expect(readingRouteKey({ page: 'D02', entity: 'v1' })).toBe(readingRouteKey({ entity: 'v1', page: 'D02' }))
  })
  it('preserves genuinely different Visit, lens, record-set and date destinations', () => {
    const routes = [{ page: 'D03' }, { page: 'D02', entity: 'v1' }, { page: 'D02', entity: 'v2' },
      { page: 'S03', lens: 'all' }, { page: 'S03', lens: 'low' }, { page: 'X01', ids: ['v1'] },
      { page: 'X01', ids: ['v1', 'v2'] }, { page: 'D04', date: '2026-09-08' }, { page: 'D04', date: '2026-09-09' }]
    expect(new Set(routes.map(readingRouteKey)).size).toBe(routes.length)
  })
})
