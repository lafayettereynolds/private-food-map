import type { PoiSearchResult } from '../types/domain'

export type ExternalLinkConfidence = 'HIGH' | 'MEDIUM' | 'LOW' | 'NONE'

export interface ExternalLinkResolveResult {
  sourceType: 'apple_maps' | 'amap' | 'generic_url' | 'shared_text'
  sourceHost: string | null
  confidence: ExternalLinkConfidence
  matchType: 'single' | 'multiple' | 'search_fallback'
  candidates: Array<PoiSearchResult & { restaurantId: string | null }>
  searchFallback: {
    keyword: string
    city: string
    addressHint: string
    latitude: number | null
    longitude: number | null
  } | null
  sourceSuggestion: string
  message: string
}

export async function resolveExternalRestaurantLink(value: string, currentCity: string) {
  const controller = new AbortController()
  const timeout = window.setTimeout(() => controller.abort(), 10_000)
  try {
    const response = await fetch('/api/external-place/resolve', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      credentials: 'same-origin',
      signal: controller.signal,
      body: JSON.stringify({ text: value, currentCity }),
    })
    const payload = await response.json().catch(() => null) as (ExternalLinkResolveResult & { error?: string }) | null
    if (!response.ok || !payload) throw new Error(payload?.error || '餐厅链接暂时无法解析。')
    return payload
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw new Error('链接解析超时，请重试。')
    throw error
  } finally {
    window.clearTimeout(timeout)
  }
}
