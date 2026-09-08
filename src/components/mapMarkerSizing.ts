/** Far-distance sizing changes visual diameter only, never map anchors or grouping. */
export const MAP_MARKER_FAR_SCALE = {
  startLatitudeDelta: 2.4,
  fullLatitudeDelta: 80,
  minimumDiameter: 14,
  minimumUnvisitedIncrease: 1,
  minimumSelectionIncrease: 1,
} as const

export interface MapMarkerBaselineSizes {
  diameter: number
  selectedDiameter: number
  unvisitedIncrease: number
}

/** A metadata rerender must not turn a north/south pan into a marker zoom. */
export class MapMarkerViewportScale {
  private key = ''
  private latitudeDelta = 0

  resolve(zoom: number, width: number, height: number, latitudeDelta: number) {
    const key = `${zoom}:${width}:${height}`
    if (key !== this.key) {
      this.key = key
      this.latitudeDelta = latitudeDelta
    }
    return this.latitudeDelta
  }
}

export function mapMarkerZoomDimensions(latitudeDelta: number, baseline: MapMarkerBaselineSizes) {
  const tokens = MAP_MARKER_FAR_SCALE
  const delta = Number.isFinite(latitudeDelta) ? latitudeDelta : tokens.startLatitudeDelta
  const progress = Math.min(1, Math.max(0,
    Math.log(Math.max(tokens.startLatitudeDelta, delta) / tokens.startLatitudeDelta)
      / Math.log(tokens.fullLatitudeDelta / tokens.startLatitudeDelta),
  ))
  const interpolate = (near: number, far: number) => near + (far - near) * progress
  const diameter = interpolate(baseline.diameter, tokens.minimumDiameter)
  const selectionIncrease = interpolate(baseline.selectedDiameter - baseline.diameter, tokens.minimumSelectionIncrease)
  return {
    diameter,
    selectedDiameter: diameter + selectionIncrease,
    unvisitedIncrease: interpolate(baseline.unvisitedIncrease, tokens.minimumUnvisitedIncrease),
    glyphSize: interpolate(16, 6),
  }
}
