import { describe, expect, it } from 'vitest'
import { initialMapBrowseState, mapBrowseReducer, mapScopeQuery } from './mapBrowseState'

describe('canonical MapBrowseState', () => {
  it('isolates and restores each scope query without fitting or moving the map', () => {
    let state = mapBrowseReducer(initialMapBrowseState, { type: 'filters', value: { city: '杭州', minimumScoreOutOfTen: 6, scoreBands: [3, 4] } })
    state = mapBrowseReducer(state, { type: 'search', value: '面馆' })
    state = mapBrowseReducer(state, { type: 'sort', value: 'rating' })
    const visited = mapScopeQuery(state, 'visited')
    const fitRevision = state.cameraFitRevision
    for (const scope of ['wantToGo', 'recommended'] as const) {
      state = mapBrowseReducer(state, { type: 'scope', value: scope })
      expect(state).toMatchObject({ scope, filters: {}, search: '', sort: 'recent', cameraFitRevision: fitRevision })
    }
    state = mapBrowseReducer(state, { type: 'filters', value: { city: '上海', minimumScoreOutOfTen: 9 } })
    const recommendation = mapScopeQuery(state, 'recommended')
    state = mapBrowseReducer(state, { type: 'scope', value: 'visited' })
    expect(mapScopeQuery(state, 'visited')).toEqual(visited)
    expect(mapScopeQuery(state, 'recommended')).toEqual(recommendation)
    state = mapBrowseReducer(state, { type: 'filters', value: {} })
    state = mapBrowseReducer(state, { type: 'scope', value: 'recommended' })
    expect(state.filters).toEqual(recommendation.filters)
    expect(state.viewport).toEqual(initialMapBrowseState.viewport)
    expect(mapBrowseReducer(state, { type: 'toggleMode' }).filters).toEqual(recommendation.filters)
  })
  it('cancels an unapplied previous-scope camera request during a rapid switch', () => {
    const pending = mapBrowseReducer(initialMapBrowseState, { type: 'filters', value: { city: '杭州' } })
    expect(pending.cameraFitRevision).toBe(1)
    const switched = mapBrowseReducer(pending, { type: 'scope', value: 'recommended', appliedCameraFitRevision: 0 })
    expect(switched.cameraFitRevision).toBe(0)
    expect(switched.filters).toEqual({})
    expect(mapScopeQuery(switched, 'visited').filters).toEqual({ city: '杭州' })
  })
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
