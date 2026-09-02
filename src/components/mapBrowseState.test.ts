import { describe, expect, it } from 'vitest'
import { initialMapBrowseState, mapBrowseReducer } from './mapBrowseState'

describe('canonical MapBrowseState', () => {
  it('preserves scope, filters, sort, search, viewport and selection across Map/List switches', () => {
    const configured = {
      ...initialMapBrowseState,
      scope: 'wantToGo' as const,
      filters: { city: '杭州', minimumVisitCount: 3 },
      sort: 'rating' as const,
      search: '面馆',
      viewport: {
        zoom: 14,
        center: { latitude: 30.27, longitude: 120.15 },
        bounds: { north: 30.3, east: 120.2, south: 30.2, west: 120.1 },
      },
      selectedRestaurantID: 'restaurant-1',
    }
    const list = mapBrowseReducer(configured, { type: 'toggleMode' })
    expect(list).toMatchObject({ mode: 'list', scope: 'wantToGo', filters: configured.filters, sort: 'rating', search: '面馆', selectedRestaurantID: 'restaurant-1' })
    expect(list.viewport).toEqual(configured.viewport)
    expect(mapBrowseReducer(list, { type: 'toggleMode' })).toMatchObject({ mode: 'map', scope: 'wantToGo', filters: configured.filters })
  })
})
