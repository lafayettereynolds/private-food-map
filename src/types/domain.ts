export type RestaurantStatus = 'visited' | 'wantToGo'
export type PreferenceLevel = 'favorite' | 'like' | 'normal' | 'avoid'
export type MarkerType = 'image' | 'emoji'
export type StarRating = 1 | 2 | 3 | 4 | 5
export type QueueDuration =
  | 'none'
  | 'under15'
  | 'under30'
  | 'under60'
  | 'under90'
  | 'under120'
  | 'over120'

export interface Restaurant {
  id: string
  amapPoiId: string
  name: string
  address: string
  city: string
  latitude: number
  longitude: number
  status: RestaurantStatus
  preferenceLevel: PreferenceLevel
  overallRating: number | null
  foodRating: number | null
  environmentRating: number | null
  serviceRating: number | null
  valueRating: number | null
  tags: string[]
  longTermNote: string
  pricePerPerson: number | null
  markerType: MarkerType
  markerImageData: string | null
  merchantImageUrl: string | null
  markerEmoji: string
  createdAt: string
  updatedAt: string
}

export interface Visit {
  id: string
  restaurantId: string
  visitedAt: string
  rating: StarRating | null
  totalPrice: number | null
  pricePerPerson: number | null
  partySize: number
  queueDuration: QueueDuration | null
  companions: string[]
  dishes: VisitDish[]
  note: string
  photos: string[]
  createdAt: string
  updatedAt: string
}

export interface VisitDish {
  id: string
  name: string
  taste: string
  price: number | null
  imageData: string | null
}

export interface RestaurantSummary extends Restaurant {
  visitCount: number
  averageRating: number | null
  scoreOutOfTen: number | null
  latestVisitDate: string | null
  latestVisit: Visit | null
  visits: Visit[]
  averagePricePerPerson: number | null
  averageQueueMinutes: number | null
  recommendationScore?: number
  recommendationReason?: string
}

export const QUEUE_DURATION_OPTIONS: { value: QueueDuration; label: string }[] = [
  { value: 'none', label: '无需排队' },
  { value: 'under15', label: '15 分钟以内' },
  { value: 'under30', label: '30 分钟以内' },
  { value: 'under60', label: '1 小时以内' },
  { value: 'under90', label: '1.5 小时以内' },
  { value: 'under120', label: '2 小时以内' },
  { value: 'over120', label: '超过 2 小时' },
]

export function queueDurationLabel(value: QueueDuration | null | undefined) {
  return QUEUE_DURATION_OPTIONS.find((option) => option.value === value)?.label ?? '未记录排队'
}

const QUEUE_DURATION_APPROXIMATE_MINUTES: Record<QueueDuration, number> = {
  none: 0,
  under15: 8,
  under30: 23,
  under60: 45,
  under90: 75,
  under120: 105,
  over120: 135,
}

export function queueDurationApproximateMinutes(value: QueueDuration | null | undefined) {
  return value ? QUEUE_DURATION_APPROXIMATE_MINUTES[value] : null
}

export function formatAverageQueueDuration(minutes: number | null | undefined) {
  if (minutes === null || minutes === undefined) return '—'
  if (minutes < 1) return '无需排队'
  const roundedMinutes = Math.round(minutes)
  if (roundedMinutes < 60) return `约 ${roundedMinutes} 分钟`
  const hours = Math.floor(roundedMinutes / 60)
  const remainingMinutes = roundedMinutes % 60
  return `约 ${hours} 小时${remainingMinutes ? ` ${remainingMinutes} 分` : ''}`
}

export function calculatePricePerPerson(totalPrice: number | null, partySize: number) {
  if (totalPrice === null || !Number.isFinite(totalPrice) || partySize < 1) return null
  return Math.round(totalPrice / partySize)
}

export interface PoiSearchResult {
  amapPoiId: string
  name: string
  address: string
  city: string
  district: string
  latitude: number
  longitude: number
  merchantImageUrl: string | null
}

export const RATING_META: Record<
  StarRating,
  { label: string; shortLabel: string; color: string }
> = {
  5: { label: '挚爱', shortLabel: '5 星', color: '#2f9b66' },
  4: { label: '喜欢', shortLabel: '4 星', color: '#69a9ea' },
  3: { label: '不错', shortLabel: '3 星', color: '#e0ad39' },
  2: { label: '一般', shortLabel: '2 星', color: '#ed8b4b' },
  1: { label: '不喜欢', shortLabel: '1 星', color: '#df5f5f' },
}

export const UNRATED_COLOR = '#9ea3a0'

export function nearestStar(rating: number | null | undefined): StarRating | null {
  if (!rating) return null
  return Math.min(5, Math.max(1, Math.round(rating))) as StarRating
}

export function ratingColor(rating: number | null | undefined) {
  const star = nearestStar(rating)
  return star ? RATING_META[star].color : UNRATED_COLOR
}

export function ratingLabel(rating: number | null | undefined) {
  const star = nearestStar(rating)
  return star ? RATING_META[star].label : '未评分'
}

export function starToTenScore(rating: number | null | undefined) {
  return rating ? Math.round(rating * 20) / 10 : null
}

export const PREFERENCE_META: Record<
  PreferenceLevel,
  { label: string; color: string; shortLabel: string }
> = {
  favorite: { label: '最喜欢', shortLabel: '最爱', color: '#3f8f67' },
  like: { label: '喜欢', shortLabel: '喜欢', color: '#4f83c8' },
  normal: { label: '一般', shortLabel: '一般', color: '#f0b94b' },
  avoid: { label: '不会再去', shortLabel: '不再去', color: '#c96568' },
}

export const STATUS_META: Record<RestaurantStatus, { label: string }> = {
  visited: { label: '去过' },
  wantToGo: { label: '想去' },
}
