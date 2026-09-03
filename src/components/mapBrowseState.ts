import type { TasteMapMapFilters, TasteMapMapScope, TasteMapMapSort, TasteMapNativeMapViewport } from '../platform/TasteMapPlatform'

export type MapBrowseMode = 'map' | 'list'

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
}

export type MapBrowseAction =
  | { type: 'toggleMode' }
  | { type: 'scope'; value: TasteMapMapScope }
  | { type: 'filters'; value: TasteMapMapFilters }
  | { type: 'sort'; value: TasteMapMapSort }
  | { type: 'search'; value: string }
  | { type: 'viewport'; value: TasteMapNativeMapViewport }
  | { type: 'selection'; value: string | null }
  | { type: 'retry' }

export const initialMapBrowseState: MapBrowseState = {
  mode: 'map', scope: 'visited', filters: {}, sort: 'recent', search: '',
  viewport: null, selectedRestaurantID: null, revision: 0,
}

export function mapBrowseReducer(state: MapBrowseState, action: MapBrowseAction): MapBrowseState {
  switch (action.type) {
  case 'toggleMode': return { ...state, mode: state.mode === 'map' ? 'list' : 'map' }
  case 'scope': return { ...state, scope: action.value }
  case 'filters': return { ...state, filters: action.value, city: action.value.city }
  case 'sort': return { ...state, sort: action.value }
  case 'search': return { ...state, search: action.value }
  case 'viewport': return { ...state, viewport: action.value }
  case 'selection': return { ...state, selectedRestaurantID: action.value }
  case 'retry': return { ...state, revision: state.revision + 1 }
  }
}
