import type {
  TasteMapImageDescriptor,
  TasteMapMapBrowseOptions,
  TasteMapMapFilters,
  TasteMapMapScope,
  TasteMapMapScopeCounts,
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
  scopeCounts: TasteMapMapScopeCounts
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

/**
 * Coalesces duplicate viewport-state notifications emitted while a gesture
 * settles. Viewport state is retained for camera restoration, but it no longer
 * keys or re-requests Restaurant data during a pan.
 */
export class LatestMapViewportCommitScheduler {
  private timeout: ReturnType<typeof setTimeout> | undefined

  constructor(private readonly delayMilliseconds = 160) {}

  schedule(viewport: TasteMapMapViewport, commit: (value: TasteMapMapViewport) => void) {
    this.cancel()
    this.timeout = globalThis.setTimeout(() => {
      this.timeout = undefined
      commit(viewport)
    }, this.delayMilliseconds)
  }

  cancel() {
    if (this.timeout === undefined) return
    globalThis.clearTimeout(this.timeout)
    this.timeout = undefined
  }
}

export function mapBrowseDataVersion(restaurants: RestaurantSummary[]) {
  const newest = restaurants.reduce((value, restaurant) => restaurant.updatedAt > value ? restaurant.updatedAt : value, '')
  const visitCount = restaurants.reduce((value, restaurant) => value + restaurant.visits.length, 0)
  // Imported/accepted snapshots can change city, status or identities without
  // moving the maximum updatedAt. Keep this independent of viewport geometry.
  const membership = restaurants.map((restaurant) => [
    restaurant.id, restaurant.status, restaurant.city, restaurant.deletedAt ?? null,
    // Each record's revision matters: a future-dated/late-synced peer can keep
    // the global maximum unchanged after this restaurant's avatar is saved.
    restaurant.updatedAt, restaurant.markerType, restaurant.markerEmoji, restaurant.markerPhotoId ?? null,
  ])
    .sort((left, right) => left[0]!.localeCompare(right[0]!))
  return `${restaurants.length}:${visitCount}:${newest}:${JSON.stringify(membership)}`
}

export function mapBrowseSnapshotKey(input: MapBrowseSnapshotKeyInput) {
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
    location,
  })
}

function orderedFilters(filters: TasteMapMapFilters) {
  return {
    city: filters.city ?? null,
    minimumScoreOutOfTen: filters.minimumScoreOutOfTen ?? null,
    scoreBands: filters.scoreBands ? [...filters.scoreBands].sort() : [],
    diningMode: filters.diningMode ?? null,
    queueDuration: filters.queueDuration ?? null,
    diningOccasions: filters.diningOccasions ? [...filters.diningOccasions].sort() : [],
    visitPeriod: filters.visitPeriod ?? null,
    distanceKilometers: filters.distanceKilometers ?? null,
    priceRange: filters.priceRange ?? null,
    recommendationSourceType: filters.recommendationSourceType ?? null,
    maximumSpend: filters.maximumSpend ?? null,
    minimumVisitCount: filters.minimumVisitCount ?? null,
    companion: filters.companion ?? null,
    cuisine: filters.cuisine ?? null,
    recommendationSource: filters.recommendationSource ?? null,
  }
}

function rounded(value: number) { return Math.round(value * 100_000) / 100_000 }
