import type { RestaurantSummary, Visit } from '../types/domain'
import type { AnalysisShareType, AnalysisVisualRef } from '../types/analysisShare'
import { resolvePhotoSource } from './photoAssets'

function stableHash(value: string) {
  let hash = 2166136261
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

function stableIndex(seed: string, length: number) {
  return length ? stableHash(seed) % length : 0
}

function uniqueVisuals(items: AnalysisVisualRef[]) {
  const seen = new Set<string>()
  return items.filter((item) => {
    const key = `${item.photoId || ''}:${item.source || ''}:${item.restaurantId || ''}`
    if (!item.source || seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function rotate<T>(items: T[], seed: string) {
  if (items.length < 2) return items
  const pivot = stableIndex(seed, items.length)
  return [...items.slice(pivot), ...items.slice(0, pivot)]
}

export function restaurantVisual(restaurant: RestaurantSummary): AnalysisVisualRef {
  const source = restaurant.markerImageData || restaurant.merchantImageUrl || null
  return {
    source,
    photoId: restaurant.markerPhotoId || null,
    origin: source ? 'restaurant' : 'fallback',
    label: restaurant.name,
    restaurantId: restaurant.id,
  }
}

export function visitVisuals(visits: Visit[], restaurants: RestaurantSummary[]) {
  const restaurantNames = new Map(restaurants.map((item) => [item.id, item.name]))
  return visits.flatMap((visit) => {
    const sources = visit.photos || []
    const photoIds = visit.photoIds || []
    return sources.map((source, index): AnalysisVisualRef => ({
      source,
      photoId: photoIds[index] || null,
      origin: 'visit',
      label: restaurantNames.get(visit.restaurantId) || '到访实拍',
      restaurantId: visit.restaurantId,
    }))
  })
}

export function cuisineFallback(label: string, cuisine: string, seed: string): AnalysisVisualRef {
  const palettes = [
    ['#506C8C', '#EDF2F6', '#D09A63'],
    ['#344F69', '#E9EFEA', '#B9C9B8'],
    ['#765E77', '#F1ECF1', '#D8B38D'],
    ['#6D7761', '#EEF0E8', '#CE9B6B'],
  ]
  const [primary, background, accent] = palettes[stableIndex(seed, palettes.length)]
  const escape = (value: string) => value.replace(/[<>&'"]/g, '')
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800"><rect width="1200" height="800" fill="${background}"/><circle cx="930" cy="120" r="250" fill="${accent}" opacity=".24"/><circle cx="160" cy="690" r="330" fill="${primary}" opacity=".12"/><path d="M320 480c88-145 227-216 418-151 85 29 147 94 180 181H287c6-10 17-20 33-30Z" fill="${primary}" opacity=".92"/><path d="M458 322c43-61 102-96 176-101 80-6 152 20 218 78" fill="none" stroke="${accent}" stroke-width="24" stroke-linecap="round"/><text x="88" y="112" font-family="system-ui,sans-serif" font-size="34" letter-spacing="7" fill="${primary}">TASTE MAP</text><text x="88" y="628" font-family="system-ui,sans-serif" font-size="64" font-weight="700" fill="${primary}">${escape(label.slice(0, 12))}</text><text x="90" y="690" font-family="system-ui,sans-serif" font-size="34" fill="${primary}" opacity=".72">${escape(cuisine.slice(0, 12))}</text></svg>`
  return { source: `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`, photoId: null, origin: 'fallback', label }
}

export function collectAnalysisVisuals(
  restaurants: RestaurantSummary[],
  visits: Visit[],
  type: AnalysisShareType,
  periodSeed: string,
) {
  const seed = `${type}:${periodSeed}`
  const visitTier = uniqueVisuals(visitVisuals(visits, restaurants))
  const restaurantTier = uniqueVisuals(restaurants.map(restaurantVisual))
  const fallbackTier = restaurants.slice(0, 6).map((restaurant) => cuisineFallback(restaurant.name, restaurant.tags?.[0] || '餐厅', `${seed}:${restaurant.id}`))
  return [
    ...rotate(visitTier, `${seed}:visit`),
    ...rotate(restaurantTier, `${seed}:restaurant`),
    ...rotate(fallbackTier, `${seed}:fallback`),
  ]
}

export async function resolveVisualForPoster(visual: AnalysisVisualRef | undefined) {
  if (!visual?.source) return null
  const resolved = await resolvePhotoSource(visual.source, visual.photoId || undefined)
  if (!resolved) return null
  if (resolved.startsWith('data:')) return resolved
  try {
    const response = await fetch(resolved, { credentials: 'include' })
    if (!response.ok) return null
    return blobToDataUrl(await response.blob())
  } catch {
    return null
  }
}

export function blobToDataUrl(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result || ''))
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(blob)
  })
}
