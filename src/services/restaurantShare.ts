import type { RestaurantSummary } from '../types/domain'
import type { PublicRatingReference } from '../types/recommendation'

export type DiscoverShareMethod = 'system' | 'copy_link' | 'card'
export type DiscoverShareEventName =
  | 'discover_restaurant_share_open'
  | 'discover_restaurant_share_system'
  | 'discover_restaurant_share_copy_link'
  | 'discover_restaurant_share_card'
  | 'discover_restaurant_share_success'
  | 'discover_restaurant_share_failed'

export interface RestaurantShareModel {
  publicRestaurantId: string
  name: string
  coverImageUrl: string | null
  cuisines: string[]
  pricePerPerson: number | null
  city: string
  address: string
  publicRating: { value: number; sampleCount: number; confidence: 'low' | 'normal' } | null
  url: string
  title: string
  text: string
}

export interface DiscoverShareAnalytics {
  eventName: DiscoverShareEventName
  restaurantId: string
  discoverTab: string
  recommendationTier: string
  shareMethod?: DiscoverShareMethod
  occurredAt: string
}

const SHARE_ANALYTICS_KEY = 'taste-map-discover-share-events-v1'
const PUBLIC_CUISINES = new Set([
  '中餐', '日料', '日本料理', '韩餐', '韩国料理', '西餐', '法餐', '意大利菜', '泰国菜', '东南亚菜',
  '杭帮菜', '江浙菜', '川菜', '粤菜', '湘菜', '火锅', '烧烤', '咖啡', '甜品', '小吃', '面馆', '快餐',
])

export async function buildRestaurantShareModel(
  restaurant: RestaurantSummary,
  publicRating: PublicRatingReference | null | undefined,
  origin = window.location.origin,
): Promise<RestaurantShareModel> {
  const publicRestaurantId = await publicRestaurantIdFor({
    amapPoiId: restaurant.amapPoiId,
    name: restaurant.name,
    city: restaurant.city,
    address: restaurant.address,
  })
  const url = new URL(`/restaurant/${publicRestaurantId}`, origin)
  url.searchParams.set('ref', 'discover_share')
  const cuisines = restaurant.tags.filter((tag) => PUBLIC_CUISINES.has(tag)).slice(0, 3)
  const pricePerPerson = restaurant.averagePricePerPerson ?? restaurant.pricePerPerson ?? null
  const eligibleRating = presentablePublicRating(publicRating)
  const descriptors = [cuisines.join(' · '), pricePerPerson ? `参考人均 ¥${Math.round(pricePerPerson)}` : '', restaurant.city].filter(Boolean)

  return {
    publicRestaurantId,
    name: restaurant.name,
    coverImageUrl: restaurant.merchantImageUrl || null,
    cuisines,
    pricePerPerson,
    city: restaurant.city,
    address: restaurant.address,
    publicRating: eligibleRating,
    url: url.toString(),
    title: `${restaurant.name}｜Taste Map`,
    text: descriptors.length ? `${restaurant.name} · ${descriptors.join(' · ')}` : `在 Taste Map 查看 ${restaurant.name}`,
  }
}

export async function publicRestaurantIdFor(restaurant: Pick<RestaurantSummary, 'amapPoiId' | 'name' | 'city' | 'address'>) {
  const identity = restaurant.amapPoiId
    ? `amap:${restaurant.amapPoiId}`
    : `restaurant:${normalizeIdentityPart(restaurant.name)}|${normalizeIdentityPart(restaurant.city)}|${normalizeIdentityPart(restaurant.address)}`
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`taste-map-public:${identity}`))
  return [...new Uint8Array(digest)].slice(0, 12).map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

export function presentablePublicRating(publicRating: PublicRatingReference | null | undefined) {
  if (!publicRating?.value || publicRating.sampleCount < 5) return null
  return {
    value: publicRating.value,
    sampleCount: publicRating.sampleCount,
    confidence: publicRating.sampleCount < 10 ? 'low' as const : 'normal' as const,
  }
}

export function isShareCancellation(error: unknown) {
  return error instanceof DOMException && (error.name === 'AbortError' || error.name === 'NotAllowedError')
}

export async function copyRestaurantShareLink(model: RestaurantShareModel) {
  const text = `${model.text}\n${model.url}`
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text)
    return
  }
  const field = document.createElement('textarea')
  field.value = text
  field.setAttribute('readonly', '')
  field.style.position = 'fixed'
  field.style.opacity = '0'
  document.body.appendChild(field)
  field.select()
  const copied = document.execCommand('copy')
  field.remove()
  if (!copied) throw new Error('clipboard-unavailable')
}

export function trackDiscoverShareEvent(event: Omit<DiscoverShareAnalytics, 'occurredAt'>) {
  const payload: DiscoverShareAnalytics = { ...event, occurredAt: new Date().toISOString() }
  window.dispatchEvent(new CustomEvent('taste-map:discover-share', { detail: payload }))
  try {
    const current = JSON.parse(localStorage.getItem(SHARE_ANALYTICS_KEY) ?? '[]') as DiscoverShareAnalytics[]
    localStorage.setItem(SHARE_ANALYTICS_KEY, JSON.stringify([...current.slice(-99), payload]))
  } catch {
    // Analytics must never block sharing.
  }
}

function normalizeIdentityPart(value: string) {
  return value.trim().toLocaleLowerCase().replace(/\s+/g, '')
}
