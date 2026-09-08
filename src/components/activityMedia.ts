/** Preserve the current Visit's actual photo order, including ID-only photos. */
export function visitActivityMedia(photos: readonly (string | null)[], photoIds: readonly (string | null)[]) {
  const result: { source: string; photoId: string | null }[] = []
  const seen = new Set<string>()
  for (let index = 0; index < Math.max(photos.length, photoIds.length); index += 1) {
    const source = photos[index]?.trim() || ''
    const photoId = photoIds[index]?.trim() || null
    const key = photoId || source
    if (!key || seen.has(key)) continue
    seen.add(key)
    result.push({ source, photoId })
  }
  return result
}
