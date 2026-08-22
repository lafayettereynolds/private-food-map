/** Scales want-to-go markers from 1.28x nearby to 0.78x at 30km and beyond. */
export function wantedMarkerScale(distanceKilometers: number) {
  if (!Number.isFinite(distanceKilometers) || distanceKilometers < 0) return 1
  const distanceProgress = Math.min(1, Math.log1p(distanceKilometers) / Math.log1p(30))
  return 1.28 - distanceProgress * 0.5
}
