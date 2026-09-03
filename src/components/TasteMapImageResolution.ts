import type { TasteMapImageDescriptor, TasteMapImageResolutionDTO } from '../platform/TasteMapPlatform'

export function resolvedImageDescriptor(
  resolution: TasteMapImageResolutionDTO,
  failedSourceCount: number,
): TasteMapImageDescriptor {
  return resolution.sources[failedSourceCount] ?? resolution.fallback
}
