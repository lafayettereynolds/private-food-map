/**
 * Formal Hybrid image resolution is presentation-only. TasteMapNative.v1
 * selects the canonical image tier and returns a safe resource URL; Browser
 * storage credentials and providers must never enter the signed Hybrid UI.
 */
export async function resolvePhotoSource(
  source: string | null | undefined,
  _explicitPhotoId?: string | null,
) {
  return source ?? null
}

export async function cachePhotoBlob(_photoId: string, _blob: Blob) {}
export async function removeCachedPhoto(_photoId: string) {}
export async function clearLocalPhotoCache() {}
export async function getLocalPhotoCacheBytes() { return 0 }
