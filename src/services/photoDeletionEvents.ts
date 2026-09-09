// Photo IDs are immutable resource identities. This is a presentation barrier,
// never delete authority or a replacement for the persisted tombstone.
const deleted = new Set<string>()
export const PHOTO_DELETED_EVENT = 'taste-map:photo-deleted'
export function photoWasDeleted(id?: string | null) { return Boolean(id && deleted.has(id.toLowerCase())) }
export function notifyPhotoDeleted(id: string) {
  deleted.add(id.toLowerCase())
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(PHOTO_DELETED_EVENT, { detail: id }))
}
