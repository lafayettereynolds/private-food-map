import catalog from '../../public/food-library/catalog.json'
import { resolveFoodLibraryArtwork } from '../visuals/FoodLibraryArtwork'
import { resolveFoodCategoryVisualID } from '../visuals/FoodCategoryVisualContract'

const artworkCache = new Map<string, Promise<string | null>>()

export type PosterObjectArtwork = 'restaurant' | 'dish' | 'city' | 'salt' | 'leaf'
/** Objects already present in the original bundled general sheet. No replacement artwork. */
const objectCrops: Record<PosterObjectArtwork, [number, number, number, number]> = {
  restaurant: [842, 824, 276, 252], dish: [8, 824, 267, 244],
  city: [286, 1080, 274, 268], salt: [850, 1080, 258, 273], leaf: [570, 1082, 268, 270],
}
export function posterObjectArtwork(object: PosterObjectArtwork) {
  return croppedArtwork(`object:${object}`, 'general', objectCrops[object])
}

/** Unknown flavor/time labels must not silently become a random meal illustration. */
export function posterPreferenceArtwork(label: string) {
  if (/咸/.test(label)) return posterObjectArtwork('salt')
  if (/清淡/.test(label)) return posterObjectArtwork('leaf')
  if (/甜/.test(label)) return posterFoodArtwork('蛋糕')
  return Promise.resolve(null)
}

/** Reuse the supplied content library, cropped only at render time. These
 * locally bundled illustrations are never labelled as a user's actual photo.
 */
export function posterFoodArtwork(name: string, tags: readonly string[] = []) {
  const entry = resolveFoodLibraryArtwork({ name, tags, categoryVisualID: resolveFoodCategoryVisualID({ name, tags }) })
  const crop = (catalog.crops as Record<string, number[]>)[entry.id]
  const width = crop?.[2] ?? catalog.sheetWidth / catalog.columns
  return croppedArtwork(entry.id, entry.sheet, [crop?.[0] ?? entry.column * width, crop?.[1] ?? catalog.rowEdges[entry.row], width, crop?.[3] ?? catalog.rowEdges[entry.row + 1] - catalog.rowEdges[entry.row]])
}

function croppedArtwork(key: string, sheet: string, [left, top, width, height]: number[]) {
  const cached = artworkCache.get(key)
  if (cached) return cached
  const promise = (async () => {
    if (typeof Image === 'undefined' || typeof document === 'undefined') return null
    const image = new Image()
    image.src = `/food-library/${sheet}.png`
    await image.decode()
    const canvas = document.createElement('canvas')
    canvas.width = Math.round(width); canvas.height = Math.round(height)
    const context = canvas.getContext('2d')
    if (!context) return null
    context.drawImage(image, left, top, width, height, 0, 0, canvas.width, canvas.height)
    return canvas.toDataURL('image/png')
  })().catch(() => { artworkCache.delete(key); return null })
  artworkCache.set(key, promise)
  return promise
}
