import type { TasteMapMapScope } from '../platform/TasteMapPlatform'

export interface MapScopePerformanceRecord {
  id: string
  adapter: 'browser' | 'native'
  from: TasteMapMapScope
  to: TasteMapMapScope
  itemCount: number | null
  cacheHit: boolean
  tapAt: number
  selectedVisualAt: number | null
  dataReadyAt: number | null
  contentCommittedAt: number | null
  imagesStableAt: number | null
  bridgeDurationMs: number | null
  staleResponsesRejected: number
}

declare global {
  interface Window {
    __TASTEMAP_MAP_SCOPE_PERFORMANCE__?: MapScopePerformanceRecord[]
    __TASTEMAP_MAP_INSTANCE_CREATIONS__?: number
    __TASTEMAP_MAP_MARKER_RECONCILIATIONS__?: Array<{
      added: number; removed: number; changed: number; reused: number; active: number
    }>
  }
}

const records = new Map<string, MapScopePerformanceRecord>()
// Vite's production bundler sets DEV=false even for our signed Debug shell.
// MODE is therefore the compile-time boundary that keeps this instrumentation
// available in hybrid-debug while Rollup removes it from the hybrid Release.
const diagnosticEnabled = import.meta.env.DEV || import.meta.env.MODE === 'hybrid-debug'

export function beginMapScopeMeasurement(adapter: 'browser' | 'native', from: TasteMapMapScope, to: TasteMapMapScope) {
  if (!diagnosticEnabled) return null
  const id = `${to}-${performance.now().toFixed(3)}`
  const record: MapScopePerformanceRecord = {
    id, adapter, from, to, itemCount: null, cacheHit: false,
    tapAt: performance.now(), selectedVisualAt: null, dataReadyAt: null,
    contentCommittedAt: null, imagesStableAt: null, bridgeDurationMs: null,
    staleResponsesRejected: 0,
  }
  records.set(id, record)
  publish(record)
  return id
}

export function markMapScopeSelected(id: string | null) { update(id, (value) => { value.selectedVisualAt ??= performance.now() }) }

export function markMapScopeDataReady(
  id: string | null,
  details: { itemCount: number; cacheHit: boolean; bridgeDurationMs: number },
) {
  update(id, (value) => {
    value.itemCount = details.itemCount
    value.cacheHit = details.cacheHit
    value.bridgeDurationMs = details.bridgeDurationMs
    value.dataReadyAt ??= performance.now()
  })
}

export function markMapScopeContentCommitted(id: string | null, root: HTMLElement | null) {
  if (!id || !diagnosticEnabled) return
  requestAnimationFrame(() => {
    update(id, (value) => { value.contentCommittedAt ??= performance.now() })
    waitForImages(id, root, 0)
  })
}

export function markMapScopeStaleResponse(id: string | null) {
  update(id, (value) => { value.staleResponsesRejected += 1 })
}

export function recordMapInstanceCreation() {
  if (!diagnosticEnabled) return
  window.__TASTEMAP_MAP_INSTANCE_CREATIONS__ = (window.__TASTEMAP_MAP_INSTANCE_CREATIONS__ ?? 0) + 1
  publishDiagnosticsDOM()
}

export function recordMarkerReconciliation(value: { added: number; removed: number; changed: number; reused: number; active: number }) {
  if (!diagnosticEnabled) return
  const target = window.__TASTEMAP_MAP_MARKER_RECONCILIATIONS__ ??= []
  target.push(value)
  if (target.length > 80) target.splice(0, target.length - 80)
  publishDiagnosticsDOM()
}

function waitForImages(id: string, root: HTMLElement | null, attempt: number) {
  const images = root ? Array.from(root.querySelectorAll<HTMLImageElement>('img[data-restaurant-image]')) : []
  if (images.every((image) => image.complete) || attempt >= 120) {
    update(id, (value) => { value.imagesStableAt ??= performance.now() })
    return
  }
  requestAnimationFrame(() => waitForImages(id, root, attempt + 1))
}

function update(id: string | null, mutation: (value: MapScopePerformanceRecord) => void) {
  if (!id || !diagnosticEnabled) return
  const value = records.get(id)
  if (!value) return
  mutation(value)
  publish(value)
}

function publish(record: MapScopePerformanceRecord) {
  const target = window.__TASTEMAP_MAP_SCOPE_PERFORMANCE__ ??= []
  const index = target.findIndex((value) => value.id === record.id)
  if (index >= 0) target[index] = { ...record }
  else target.push({ ...record })
  if (target.length > 120) target.splice(0, target.length - 120)
  publishDiagnosticsDOM()
  if (record.imagesStableAt !== null) console.info('[TasteMapMapScopePerformance]', JSON.stringify(record))
}

function publishDiagnosticsDOM() {
  if (!diagnosticEnabled || typeof document === 'undefined') return
  let output = document.getElementById('tm-map-scope-performance') as HTMLOutputElement | null
  if (!output) {
    output = document.createElement('output')
    output.id = 'tm-map-scope-performance'
    output.hidden = true
    output.setAttribute('aria-hidden', 'true')
    document.body.append(output)
  }
  output.textContent = JSON.stringify({
    records: window.__TASTEMAP_MAP_SCOPE_PERFORMANCE__ ?? [],
    mapInstanceCreations: window.__TASTEMAP_MAP_INSTANCE_CREATIONS__ ?? 0,
    markerReconciliations: window.__TASTEMAP_MAP_MARKER_RECONCILIATIONS__ ?? [],
  })
}
