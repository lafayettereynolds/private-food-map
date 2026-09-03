import type {
  TasteMapImageDescriptor,
  TasteMapMapBrowseOptions,
  TasteMapMapFilters,
  TasteMapMapScope,
  TasteMapMapSort,
} from '../platform/TasteMapPlatform'
import type { Coordinates, RestaurantSummary } from '../types/domain'
import type { MapBrowseMode } from './mapBrowseState'
import type { TasteMapMapViewport } from './MapView'

export interface MapBrowsePresentationSnapshot {
  scope: TasteMapMapScope
  items: RestaurantSummary[]
  images: Record<string, TasteMapImageDescriptor>
  options: TasteMapMapBrowseOptions
  capturedAt: number
}

export interface MapBrowseSnapshotKeyInput {
  ownerUserID: string
  dataVersion: string
  mode: MapBrowseMode
  scope: TasteMapMapScope
  filters: TasteMapMapFilters
  sort: TasteMapMapSort
  search: string
  viewport: TasteMapMapViewport | null
  currentLocation: Coordinates | null
}

/**
 * A bounded presentation cache. Native/SwiftData remains authoritative; this
 * only prevents an unchanged scope from rebuilding its projection on every tap.
 */
export class MapBrowseSnapshotCache {
  private readonly values = new Map<string, MapBrowsePresentationSnapshot>()

  constructor(private readonly maximumEntries = 18) {}

  get(key: string) {
    const value = this.values.get(key)
    if (!value) return undefined
    this.values.delete(key)
    this.values.set(key, value)
    return value
  }

  set(key: string, value: MapBrowsePresentationSnapshot) {
    this.values.delete(key)
    this.values.set(key, value)
    while (this.values.size > this.maximumEntries) {
      const oldest = this.values.keys().next().value
      if (oldest === undefined) break
      this.values.delete(oldest)
    }
  }

  clear() { this.values.clear() }
  get size() { return this.values.size }
}

/** Latest-selection gate for non-cancellable Native bridge calls. */
export class LatestMapRequestGate {
  private currentRequestID = ''

  activate(requestID: string) { this.currentRequestID = requestID }
  invalidate(reason = 'selection') { this.currentRequestID = `${reason}-${performance.now()}` }
  accepts(requestID: string, responseRequestID = requestID) {
    return this.currentRequestID === requestID && responseRequestID === requestID
  }
}

export function mapBrowseDataVersion(restaurants: RestaurantSummary[]) {
  const newest = restaurants.reduce((value, restaurant) => restaurant.updatedAt > value ? restaurant.updatedAt : value, '')
  const visitCount = restaurants.reduce((value, restaurant) => value + restaurant.visits.length, 0)
  return `${restaurants.length}:${visitCount}:${newest}`
}

export function mapBrowseSnapshotKey(input: MapBrowseSnapshotKeyInput) {
  const bounds = input.mode === 'map' && input.viewport ? {
    north: rounded(input.viewport.bounds.north),
    east: rounded(input.viewport.bounds.east),
    south: rounded(input.viewport.bounds.south),
    west: rounded(input.viewport.bounds.west),
  } : null
  const location = input.currentLocation ? {
    latitude: rounded(input.currentLocation.latitude),
    longitude: rounded(input.currentLocation.longitude),
  } : null
  return JSON.stringify({
    owner: input.ownerUserID,
    version: input.dataVersion,
    mode: input.mode,
    scope: input.scope,
    filters: orderedFilters(input.filters),
    sort: input.sort,
    search: input.search.trim(),
    bounds,
    location,
  })
}

/** Scope is intentionally absent: changing it must never request a camera fit. */
export function mapBrowseCameraFitKey(filters: TasteMapMapFilters, search: string) {
  return JSON.stringify({ filters: orderedFilters(filters), search: search.trim() })
}

function orderedFilters(filters: TasteMapMapFilters) {
  return {
    city: filters.city ?? null,
    minimumScoreOutOfTen: filters.minimumScoreOutOfTen ?? null,
    maximumSpend: filters.maximumSpend ?? null,
    minimumVisitCount: filters.minimumVisitCount ?? null,
    companion: filters.companion ?? null,
    cuisine: filters.cuisine ?? null,
    recommendationSource: filters.recommendationSource ?? null,
  }
}

function rounded(value: number) { return Math.round(value * 100_000) / 100_000 }
