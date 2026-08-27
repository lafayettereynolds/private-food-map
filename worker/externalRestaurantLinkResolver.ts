export type ExternalRestaurantSourceType = 'apple_maps' | 'amap' | 'generic_url' | 'shared_text'
export type ExternalRestaurantConfidence = 'HIGH' | 'MEDIUM' | 'LOW' | 'NONE'

export interface ExternalRestaurantResolveInput {
  url?: string
  text?: string
  currentCity?: string
}

export interface ExternalPlaceEvidence {
  sourceType: ExternalRestaurantSourceType
  sourceUrl: string | null
  provider: 'apple' | 'amap' | 'generic' | 'text'
  externalId: string | null
  name: string
  address: string
  city: string
  latitude: number | null
  longitude: number | null
  confidence: ExternalRestaurantConfidence
}

const MAX_URL_LENGTH = 4_096
const MAX_REDIRECTS = 4
const MAX_RESPONSE_BYTES = 512_000
const REQUEST_TIMEOUT_MS = 5_000
const URL_PATTERN = /https:\/\/[^\s<>"'）)]+/i

export async function resolveExternalRestaurantEvidence(
  input: ExternalRestaurantResolveInput,
  fetcher: typeof fetch = fetch,
): Promise<ExternalPlaceEvidence> {
  const rawText = `${input.text ?? ''}`.trim()
  const rawUrl = `${input.url ?? ''}`.trim() || rawText.match(URL_PATTERN)?.[0] || ''
  if (!rawUrl) return evidenceFromPlainText(rawText, input.currentCity ?? '')

  const url = validateExternalRestaurantUrl(rawUrl)
  const sourceType = sourceTypeForUrl(url)
  const fromUrl = parseKnownRestaurantUrl(url, sourceType, input.currentCity ?? '')
  if (fromUrl.confidence === 'HIGH' || (fromUrl.name && fromUrl.address)) return fromUrl

  const fetched = await fetchExternalMetadata(url, fetcher)
  const merged = mergeEvidence(fromUrl, fetched, input.currentCity ?? '')
  if (merged.name) return merged

  const textWithoutUrl = rawText.replace(URL_PATTERN, '').trim()
  return textWithoutUrl ? evidenceFromPlainText(textWithoutUrl, input.currentCity ?? '') : merged
}

export function validateExternalRestaurantUrl(value: string) {
  if (value.length > MAX_URL_LENGTH) throw new ExternalLinkResolveError('餐厅链接过长，请检查后重试。', 400)
  let url: URL
  try {
    url = new URL(value)
  } catch {
    throw new ExternalLinkResolveError('这不是有效的餐厅链接。', 400)
  }
  if (url.protocol !== 'https:') throw new ExternalLinkResolveError('只支持 HTTPS 餐厅链接。', 400)
  if (isUnsafeHostname(url.hostname)) throw new ExternalLinkResolveError('这个链接指向不允许访问的网络地址。', 400)
  url.username = ''
  url.password = ''
  url.hash = ''
  return url
}

export function sourceTypeForUrl(url: URL): ExternalRestaurantSourceType {
  const hostname = url.hostname.toLowerCase()
  if (hostname === 'maps.apple.com' || hostname.endsWith('.maps.apple.com')) return 'apple_maps'
  if (hostname === 'amap.com' || hostname.endsWith('.amap.com') || hostname === 'gaode.com' || hostname.endsWith('.gaode.com')) return 'amap'
  return 'generic_url'
}

export function parseKnownRestaurantUrl(
  url: URL,
  sourceType = sourceTypeForUrl(url),
  currentCity = '',
): ExternalPlaceEvidence {
  const query = url.searchParams
  const name = cleanText(firstValue(query, ['name', 'q', 'query', 'title', 'placeName']))
  const address = cleanText(firstValue(query, ['address', 'addr', 'daddr']))
  const city = cleanText(firstValue(query, ['city', 'cityname'])) || currentCity.trim()
  const coordinateText = firstValue(query, ['ll', 'location', 'position', 'center'])
  const coordinates = parseCoordinates(coordinateText)
  const pathExternalId = sourceType === 'amap'
    ? url.pathname.match(/\b(B0[A-Z0-9]{6,})\b/i)?.[1] ?? null
    : null
  const externalId = cleanText(firstValue(query, ['id', 'poiid', 'poiId', 'place-id'])) || pathExternalId
  const provider = sourceType === 'amap' ? 'amap' : sourceType === 'apple_maps' ? 'apple' : 'generic'
  const richEvidence = Boolean(name && (address || coordinates || externalId))
  return {
    sourceType,
    sourceUrl: url.toString(),
    provider,
    externalId,
    name,
    address,
    city,
    latitude: coordinates?.latitude ?? null,
    longitude: coordinates?.longitude ?? null,
    confidence: provider === 'amap' && externalId && richEvidence ? 'HIGH' : richEvidence ? 'MEDIUM' : name ? 'LOW' : 'NONE',
  }
}

async function fetchExternalMetadata(url: URL, fetcher: typeof fetch) {
  let currentUrl = url
  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount += 1) {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS)
    let response: Response
    try {
      response = await fetcher(currentUrl.toString(), {
        method: 'GET',
        redirect: 'manual',
        signal: controller.signal,
        headers: {
          accept: 'text/html,application/xhtml+xml,application/json;q=0.8',
          'user-agent': 'TasteMap-LinkResolver/1.0',
        },
      })
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') throw new ExternalLinkResolveError('餐厅链接解析超时，请重试。', 504)
      throw new ExternalLinkResolveError('暂时无法读取这个餐厅链接。', 502)
    } finally {
      clearTimeout(timeout)
    }

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location')
      if (!location) throw new ExternalLinkResolveError('餐厅链接重定向不完整。', 422)
      if (redirectCount === MAX_REDIRECTS) throw new ExternalLinkResolveError('餐厅链接重定向次数过多。', 422)
      currentUrl = validateExternalRestaurantUrl(new URL(location, currentUrl).toString())
      continue
    }
    if (!response.ok) throw new ExternalLinkResolveError('餐厅链接暂时无法访问。', 422)
    const contentType = response.headers.get('content-type')?.toLowerCase() ?? ''
    if (!contentType.includes('text/html') && !contentType.includes('application/xhtml+xml') && !contentType.includes('application/json')) {
      throw new ExternalLinkResolveError('这个链接不是可识别的餐厅页面。', 415)
    }
    const declaredLength = Number(response.headers.get('content-length') ?? 0)
    if (declaredLength > MAX_RESPONSE_BYTES) throw new ExternalLinkResolveError('餐厅页面过大，无法安全解析。', 413)
    const body = await readLimitedText(response, MAX_RESPONSE_BYTES)
    return parseMetadataBody(body, contentType, currentUrl)
  }
  throw new ExternalLinkResolveError('餐厅链接无法解析。', 422)
}

async function readLimitedText(response: Response, limit: number) {
  if (!response.body) return ''
  const reader = response.body.getReader()
  const chunks: Uint8Array[] = []
  let size = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    size += value.byteLength
    if (size > limit) {
      await reader.cancel()
      throw new ExternalLinkResolveError('餐厅页面过大，无法安全解析。', 413)
    }
    chunks.push(value)
  }
  const combined = new Uint8Array(size)
  let offset = 0
  for (const chunk of chunks) {
    combined.set(chunk, offset)
    offset += chunk.byteLength
  }
  return new TextDecoder().decode(combined)
}

function parseMetadataBody(body: string, contentType: string, sourceUrl: URL) {
  if (contentType.includes('application/json')) {
    try {
      return metadataFromJson(JSON.parse(body), sourceUrl)
    } catch {
      return emptyFetchedMetadata(sourceUrl)
    }
  }
  const jsonLdMatches = [...body.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)]
  for (const match of jsonLdMatches.slice(0, 12)) {
    try {
      const parsed = JSON.parse(match[1])
      const metadata = metadataFromJson(parsed, sourceUrl)
      if (metadata.name) return metadata
    } catch {
      // Ignore malformed third-party JSON-LD and continue with safe meta tags.
    }
  }
  const title = extractMeta(body, 'property', 'og:title') || extractMeta(body, 'name', 'twitter:title') || extractTitle(body)
  const description = extractMeta(body, 'property', 'og:description') || extractMeta(body, 'name', 'description')
  return {
    sourceUrl: sourceUrl.toString(),
    name: cleanRestaurantPageTitle(title),
    address: cleanText(description),
    city: '',
    latitude: null,
    longitude: null,
    externalId: null,
  }
}

function metadataFromJson(value: unknown, sourceUrl: URL) {
  const candidates = Array.isArray(value) ? value : isRecord(value) && Array.isArray(value['@graph']) ? value['@graph'] : [value]
  const item = candidates.find((candidate) => isRecord(candidate) && isRestaurantLike(candidate))
    ?? candidates.find(isRecord)
  if (!item || !isRecord(item)) return emptyFetchedMetadata(sourceUrl)
  const addressValue = item.address
  const address = typeof addressValue === 'string'
    ? addressValue
    : isRecord(addressValue)
      ? [addressValue.streetAddress, addressValue.addressLocality, addressValue.addressRegion].filter((part) => typeof part === 'string').join(' ')
      : ''
  const geo = isRecord(item.geo) ? item.geo : null
  return {
    sourceUrl: sourceUrl.toString(),
    name: cleanText(item.name),
    address: cleanText(address),
    city: isRecord(addressValue) ? cleanText(addressValue.addressLocality) : '',
    latitude: numericValue(geo?.latitude),
    longitude: numericValue(geo?.longitude),
    externalId: cleanText(item.identifier),
  }
}

function mergeEvidence(
  base: ExternalPlaceEvidence,
  fetched: ReturnType<typeof emptyFetchedMetadata>,
  currentCity: string,
): ExternalPlaceEvidence {
  const name = base.name || fetched.name
  const address = base.address || fetched.address
  const city = base.city || fetched.city || currentCity.trim()
  const externalId = base.externalId || fetched.externalId
  const latitude = base.latitude ?? fetched.latitude
  const longitude = base.longitude ?? fetched.longitude
  const richEvidence = Boolean(name && (address || (latitude !== null && longitude !== null) || externalId))
  return {
    ...base,
    sourceUrl: fetched.sourceUrl || base.sourceUrl,
    externalId,
    name,
    address,
    city,
    latitude,
    longitude,
    confidence: base.provider === 'amap' && externalId && richEvidence ? 'HIGH' : richEvidence ? 'MEDIUM' : name ? 'LOW' : 'NONE',
  }
}

function evidenceFromPlainText(text: string, currentCity: string): ExternalPlaceEvidence {
  const cleaned = cleanText(text).slice(0, 240)
  return {
    sourceType: 'shared_text',
    sourceUrl: null,
    provider: 'text',
    externalId: null,
    name: cleaned,
    address: '',
    city: currentCity.trim(),
    latitude: null,
    longitude: null,
    confidence: cleaned ? 'LOW' : 'NONE',
  }
}

function emptyFetchedMetadata(sourceUrl: URL) {
  return { sourceUrl: sourceUrl.toString(), name: '', address: '', city: '', latitude: null as number | null, longitude: null as number | null, externalId: null as string | null }
}

function parseCoordinates(value: string) {
  const match = value.match(/^\s*(-?\d+(?:\.\d+)?)\s*[,，]\s*(-?\d+(?:\.\d+)?)\s*$/)
  if (!match) return null
  const first = Number(match[1])
  const second = Number(match[2])
  const latitudeFirst = Math.abs(first) <= 90 && Math.abs(second) <= 180
  return latitudeFirst ? { latitude: first, longitude: second } : { latitude: second, longitude: first }
}

function firstValue(query: URLSearchParams, keys: string[]) {
  for (const key of keys) {
    const value = query.get(key)
    if (value) return value
  }
  return ''
}

function isUnsafeHostname(hostname: string) {
  const normalized = hostname.toLowerCase().replace(/^\[|\]$/g, '')
  if (normalized === 'localhost' || normalized.endsWith('.localhost') || normalized.endsWith('.local') || normalized.endsWith('.internal')) return true
  if (normalized === 'metadata.google.internal' || normalized === 'metadata') return true
  if (normalized === '::1' || normalized === '::' || normalized.startsWith('fc') || normalized.startsWith('fd') || normalized.startsWith('fe8') || normalized.startsWith('fe9') || normalized.startsWith('fea') || normalized.startsWith('feb')) return true
  const ipv4 = normalized.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  if (!ipv4) return false
  const [, aText, bText, cText, dText] = ipv4
  const [a, b, c, d] = [aText, bText, cText, dText].map(Number)
  if ([a, b, c, d].some((part) => part < 0 || part > 255)) return true
  return a === 0 || a === 10 || a === 127 || a >= 224
    || (a === 169 && b === 254)
    || (a === 172 && b >= 16 && b <= 31)
    || (a === 192 && b === 168)
    || (a === 100 && b >= 64 && b <= 127)
}

function extractMeta(body: string, attribute: string, value: string) {
  const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const patterns = [
    new RegExp(`<meta[^>]+${attribute}=["']${escaped}["'][^>]+content=["']([^"']*)["'][^>]*>`, 'i'),
    new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+${attribute}=["']${escaped}["'][^>]*>`, 'i'),
  ]
  return decodeHtml(patterns.map((pattern) => body.match(pattern)?.[1] ?? '').find(Boolean) ?? '')
}

function extractTitle(body: string) {
  return decodeHtml(body.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? '')
}

function cleanRestaurantPageTitle(value: string) {
  return cleanText(value.split(/\s[-|｜]\s/)[0])
}

function decodeHtml(value: string) {
  return value.replace(/&amp;/gi, '&').replace(/&quot;/gi, '"').replace(/&#39;/gi, "'").replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/\s+/g, ' ').trim()
}

function cleanText(value: unknown) {
  return typeof value === 'string' ? decodeHtml(value).slice(0, 500) : ''
}

function numericValue(value: unknown) {
  const parsed = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : Number.NaN
  return Number.isFinite(parsed) ? parsed : null
}

function isRestaurantLike(value: Record<string, unknown>) {
  const type = value['@type']
  const values = Array.isArray(type) ? type : [type]
  return values.some((item) => typeof item === 'string' && /(restaurant|foodestablishment|cafeorcoffeeshop|bakery|barornightclub)/i.test(item))
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export class ExternalLinkResolveError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
    this.name = 'ExternalLinkResolveError'
  }
}
