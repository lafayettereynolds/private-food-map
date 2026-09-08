/** Shared shell/size semantics for live, fallback and same-coordinate layers. */
export function isUnvisitedMapMarker(status: string, recommendationScope = false) {
  return recommendationScope || status === 'wantToGo'
}
