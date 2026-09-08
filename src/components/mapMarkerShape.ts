import { isUnvisitedMapMarker } from '../utils/mapMarkers'

/** Lafayette paused this candidate. Formal renderers must keep circle/dashed. */
export const TREASURE_CHEST_CANDIDATE_ENABLED = false

/** User-supplied 62px lossless cutout. Artwork is never recreated in code. */
export const MAP_MARKER_CHEST = {
  source: '/map-markers/treasure-chest.png',
  size: 62,
  photoWindow: { x: 8, y: 32, width: 46, height: 24 },
  clasp: { x: 25, y: 29, width: 12, height: 14 },
} as const

// An independent display mask reveals the real Restaurant photo but preserves
// the original PNG's clasp. This never edits pixels in the approved source file.
const window = MAP_MARKER_CHEST.photoWindow
const clasp = MAP_MARKER_CHEST.clasp
export const MAP_MARKER_CHEST_MASK = `url("data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 62 62"><mask id="window" maskUnits="userSpaceOnUse" x="0" y="0" width="62" height="62"><rect width="62" height="62" fill="white"/><rect x="${window.x}" y="${window.y}" width="${window.width}" height="${window.height}" fill="black"/><rect x="${clasp.x}" y="${clasp.y}" width="${clasp.width}" height="${clasp.height}" fill="white"/></mask><rect width="62" height="62" fill="white" mask="url(#window)"/></svg>`)}")`

export function mapMarkerShape(status: string, recommendationScope = false, candidateEnabled: boolean = TREASURE_CHEST_CANDIDATE_ENABLED) {
  return candidateEnabled && isUnvisitedMapMarker(status, recommendationScope) ? 'treasureChest' : 'circle'
}

/** A sibling of the image: a late image.replaceChildren cannot erase it. */
export function createTreasureChestDecoration() {
  const image = document.createElement('img')
  image.src = MAP_MARKER_CHEST.source
  image.alt = ''
  image.draggable = false
  image.className = 'private-image-marker__chest-shell'
  image.setAttribute('aria-hidden', 'true')
  return image
}
