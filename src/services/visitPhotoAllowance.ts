import type { VisitDish } from '../types/domain'

interface VisitPhotoCollection {
  photos: readonly string[]
  photoIds?: readonly (string | null)[]
  dishes?: readonly Pick<VisitDish, 'imageData' | 'photoId'>[]
}

function photoKeys(value: VisitPhotoCollection): string[] {
  const keys: string[] = []
  const knownIDs = new Set<string>()
  const add = (source: string | null | undefined, id: string | null | undefined) => {
    if (!source && !id) return
    if (id && knownIDs.has(id)) return // One real Photo reused as a Dish association.
    if (id) knownIDs.add(id)
    keys.push(id ? `id:${id}` : `source:${source}`)
  }
  // Synced photos may have only an opaque ID until their readable URL arrives.
  for (let index = 0; index < Math.max(value.photos.length, value.photoIds?.length ?? 0); index++) {
    add(value.photos[index], value.photoIds?.[index])
  }
  value.dishes?.forEach(dish => add(dish.imageData, dish.photoId))
  return keys
}

export function visitPhotoCount(value: VisitPhotoCollection): number { return photoKeys(value).length }

/** Free accounts may retain/remove historical dish photos, never add/replace them. */
export function assertDishPhotoAccess(next: VisitPhotoCollection, allowed: boolean, previous?: VisitPhotoCollection): void {
  if (allowed) return
  const old = new Set(photoKeys({ photos: [], dishes: previous?.dishes }))
  if (photoKeys({ photos: [], dishes: next.dishes }).some(key => !old.has(key))) {
    throw new Error('菜品照片仅限 Premium；已有照片会继续保留。')
  }
}

/** A retained/reordered/subset legacy collection is valid; new material is quota-bound. */
export function assertVisitPhotoAllowance(next: VisitPhotoCollection, limit: number, previous?: VisitPhotoCollection): void {
  const nextKeys = photoKeys(next)
  if (nextKeys.length <= limit) return
  const remaining = new Map<string, number>()
  for (const key of previous ? photoKeys(previous) : []) remaining.set(key, (remaining.get(key) ?? 0) + 1)
  for (const key of nextKeys) {
    const count = remaining.get(key) ?? 0
    if (!count) throw new Error(`每次到访最多可添加 ${limit} 张照片；已有照片会继续保留。`)
    remaining.set(key, count - 1)
  }
}
