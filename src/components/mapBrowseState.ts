import type { TasteMapMapFilters, TasteMapMapScope, TasteMapMapSort, TasteMapNativeMapViewport } from '../platform/TasteMapPlatform'

export type MapBrowseMode = 'map' | 'list'

export interface MapScopeQuery {
  filters: TasteMapMapFilters
  sort: TasteMapMapSort
  search: string
}

export interface MapBrowseState {
  mode: MapBrowseMode
  scope: TasteMapMapScope
  filters: TasteMapMapFilters
  sort: TasteMapMapSort
  city?: string
  search: string
  viewport: TasteMapNativeMapViewport | null
  selectedRestaurantID: string | null
  revision: number
  scopeQueries: Partial<Record<TasteMapMapScope, MapScopeQuery>>
  cameraFitRevision: number
}

export type MapBrowseAction =
  | { type: 'toggleMode' }
  | { type: 'scope'; value: TasteMapMapScope; appliedCameraFitRevision?: number }
  | { type: 'filters'; value: TasteMapMapFilters }
  | { type: 'sort'; value: TasteMapMapSort }
  | { type: 'search'; value: string }
  | { type: 'viewport'; value: TasteMapNativeMapViewport }
  | { type: 'selection'; value: string | null }
  | { type: 'retry' }

export const initialMapBrowseState: MapBrowseState = {
  mode: 'map', scope: 'visited', filters: {}, sort: 'recent', search: '',
  viewport: null, selectedRestaurantID: null, revision: 0,
  scopeQueries: {}, cameraFitRevision: 0,
}

export function mapScopeQuery(state: MapBrowseState, scope: TasteMapMapScope): MapScopeQuery {
  if (scope === state.scope) return { filters: state.filters, sort: state.sort, search: state.search }
  return state.scopeQueries[scope] ?? { filters: {}, sort: 'recent', search: '' }
}

export function mapBrowseReducer(state: MapBrowseState, action: MapBrowseAction): MapBrowseState {
  switch (action.type) {
  case 'toggleMode': return { ...state, mode: state.mode === 'map' ? 'list' : 'map' }
  case 'scope': {
    if (action.value === state.scope) return state
    const query = mapScopeQuery(state, action.value)
    return { ...state, ...query, scope: action.value, city: query.filters.city,
      cameraFitRevision: action.appliedCameraFitRevision ?? state.cameraFitRevision,
      selectedRestaurantID: null,
      scopeQueries: { ...state.scopeQueries, [state.scope]: mapScopeQuery(state, state.scope) } }
  }
  case 'filters': return { ...state, filters: action.value, city: action.value.city, cameraFitRevision: state.cameraFitRevision + 1 }
  case 'sort': return { ...state, sort: action.value }
  case 'search': return { ...state, search: action.value, cameraFitRevision: state.cameraFitRevision + 1 }
  case 'viewport': return { ...state, viewport: action.value }
  case 'selection': return { ...state, selectedRestaurantID: action.value }
  case 'retry': return { ...state, revision: state.revision + 1 }
  }
}
