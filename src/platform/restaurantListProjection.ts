import type { TasteMapHybridListDTO, TasteMapListPageDTO, TasteMapListRatingDTO } from './TasteMapPlatform'

export function listCoordinate(latitude: unknown, longitude: unknown) {
  return typeof latitude === 'number' && Number.isFinite(latitude) && Math.abs(latitude) <= 90
    && typeof longitude === 'number' && Number.isFinite(longitude) && Math.abs(longitude) <= 180
    ? { latitude, longitude } : null
}

export function listRating(valueOutOfTen: unknown, source: TasteMapListRatingDTO['source'], sampleCount: number): TasteMapListRatingDTO | null {
  return typeof valueOutOfTen === 'number' && Number.isFinite(valueOutOfTen)
    && valueOutOfTen > 0 && valueOutOfTen <= 10 && Number.isInteger(sampleCount) && sampleCount > 0
    ? { valueOutOfTen, source, sampleCount } : null
}

export function mergeListPage(previous: TasteMapHybridListDTO | null, page: TasteMapListPageDTO): TasteMapHybridListDTO {
  if (!previous) return page.list
  if (previous.id !== page.list.id || previous.updatedAt !== page.list.updatedAt) {
    throw new Error('食单已更新，请重新读取后继续。')
  }
  const items = new Map(previous.restaurants.map(item => [item.id.toLowerCase(), item]))
  for (const item of page.list.restaurants) items.set(item.id.toLowerCase(), item)
  return { ...page.list, restaurants: [...items.values()].sort((a, b) => a.position - b.position || a.id.localeCompare(b.id)) }
}

export function validatedListShareURL(value: unknown): string {
  if (typeof value !== 'string') throw new Error('分享服务没有返回真实链接。')
  const url = new URL(value)
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash
    || !/^\/share\/[A-Za-z0-9_-]{32}$/.test(url.pathname)) throw new Error('分享服务返回的链接无效。')
  return url.href
}
