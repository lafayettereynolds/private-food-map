export type RestaurantStatus = 'visited' | 'wantToGo'
export type PreferenceLevel = 'favorite' | 'like' | 'normal' | 'avoid'
export type ScoreBand = 1 | 2 | 3 | 4 | 5
export type MarkerType = 'image' | 'emoji'
export type WholeStarRating = 1 | 2 | 3 | 4 | 5
export type StarRating = 0.5 | 1 | 1.5 | 2 | 2.5 | 3 | 3.5 | 4 | 4.5 | 5
export type PhotoKind = 'restaurant-marker' | 'visit' | 'dish' | 'avatar'
export type Visibility = 'private' | 'friends' | 'public'
export type DiningMode = 'dine_in' | 'takeout'
export type PaymentMode = 'aa' | 'my_treat' | 'treated' | 'separate' | 'other'
export type DiningOccasion = 'solo' | 'date' | 'friends' | 'family' | 'business' | 'celebration' | 'other'
export type NoiseLevel = 'quiet' | 'normal' | 'loud' | 'very_loud'
export type DiningDuration = 'under15' | 'under30' | 'under45' | 'under60' | 'under90' | 'under120' | 'over120'
export type PortionLevel = 'small' | 'normal' | 'generous'
export type TransportConvenience = 'very_convenient' | 'convenient' | 'normal' | 'inconvenient'
export type RecommendationSourceType = 'friend' | 'xiaohongshu' | 'douyin' | 'dianping' | 'blogger' | 'self' | 'other'
export type FriendshipStatus = 'pending' | 'accepted' | 'rejected' | 'removed'
export type CompanionLinkRequestStatus = 'pending' | 'accepted' | 'rejected' | 'cancelled'
export type AvatarPresetId = 'polar-bear' | 'penguin' | 'cat' | 'dog' | 'parrot' | 'dinosaur' | 'shiba' | 'panda' | 'otter' | 'hedgehog' | 'rabbit' | 'koala' | 'fox' | 'raccoon' | 'deer' | 'whale'
export type MembershipTier = 'free' | 'member'
export type QueueDuration =
  | 'none'
  | 'under15'
  | 'under30'
  | 'under60'
  | 'under90'
  | 'under120'
  | 'over120'

import type { RestaurantPlaceIdentity } from './restaurantIdentity'

export interface Restaurant {
  id: string
  userId: string
  amapPoiId: string
  placeIdentities?: RestaurantPlaceIdentity[]
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
  phone?: string | null
  websiteUrl?: string | null
  openingHours?: string | null
  markerType: MarkerType
  markerImageData: string | null
  markerPhotoId: string | null
  merchantImageUrl: string | null
  markerEmoji: string
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  isTestData?: boolean
}

export interface Visit {
  id: string
  userId: string
  restaurantId: string
  visitedAt: string
  rating: StarRating | null
  visibility: Visibility
  diningMode: DiningMode
  totalPrice: number | null
  myActualSpend: number | null
  paymentMode: PaymentMode | null
  pricePerPerson: number | null
  partySize: number | null
  queueDuration: QueueDuration | null
  diningOccasions: DiningOccasion[]
  diningOccasion: DiningOccasion | null
  diningOccasionText: string
  valueRating: StarRating | null
  environmentRating: StarRating | null
  serviceRating: StarRating | null
  valueTags: string[]
  environmentTags: string[]
  serviceTags: string[]
  noiseLevel: NoiseLevel | null
  diningDuration: DiningDuration | null
  portionLevel: PortionLevel | null
  transportConvenience: TransportConvenience | null
  specialNotes: string
  recommendationSourceType: RecommendationSourceType | null
  recommendationSourceUserId: string | null
  recommendationSourceText: string
  sharedMealId: string | null
  companions: string[]
  companionIds: string[]
  dishes: VisitDish[]
  note: string
  photos: string[]
  photoIds: Array<string | null>
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  isTestData?: boolean
}

export interface DiningCompanion {
  id: string
  ownerUserId: string
  displayName: string
  linkedUserId: string | null
  privateAvatarData?: string | null
  relationshipLabel?: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface CompanionLinkRequest {
  id: string
  companionId: string
  companionDisplayName: string
  requesterUserId: string
  targetUserId: string
  status: CompanionLinkRequestStatus
  visitCount: number
  restaurantCount: number
  createdAt: string
  updatedAt: string
}

export interface HistoricalMealFact {
  sourceVisitId: string
  restaurant: Pick<Restaurant, 'amapPoiId' | 'name' | 'address' | 'city' | 'latitude' | 'longitude' | 'merchantImageUrl'>
  visitedAt: string
  sharedMealId: string | null
}

export interface VisitDish {
  id: string
  name: string
  taste: string
  rating: StarRating | null
  price: number | null
  imageData: string | null
  photoId: string | null
}

export interface Photo {
  id: string
  userId: string
  restaurantId: string | null
  visitId: string | null
  kind: PhotoKind
  storageProvider: 'google-drive' | 'cloudkit' | 'r2' | 'oss' | 'cos'
  storageKey: string
  thumbnailStorageKey: string | null
  thumbnailFileSize: number | null
  driveAccountId: string
  driveFileId: string
  fileName: string | null
  mimeType: string
  fileSize: number
  width: number | null
  height: number | null
  visibility: Visibility
  syncStatus: 'pending' | 'uploading' | 'synced' | 'failed' | 'delete-pending'
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  localState: 'synced' | 'delete-pending'
  lastError: string | null
}

export interface UserProfile {
  id: string
  nickname: string
  email: string | null
  bio: string
  city: string
  avatarImageData: string | null
  avatarPhotoId: string | null
  avatarPresetId: AvatarPresetId
  membershipTier: MembershipTier
  mapSharingEnabled: boolean
  mapVisibility: Visibility
  authProvider: 'apple' | 'cloudflare-access' | 'local'
  authSubject: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  isTestUser?: boolean
}

export interface Follow {
  id: string
  followerId: string
  followedUserId: string
  createdAt: string
  isTestData?: boolean
}

export interface Friendship {
  id: string
  requesterId: string
  addresseeId: string
  status: FriendshipStatus
  createdAt: string
  updatedAt: string
  isTestData?: boolean
}

export interface SharedMeal {
  id: string
  restaurantId: string
  createdByUserId: string
  occurredAt: string
  createdAt: string
  updatedAt: string
  deletedAt: string | null
  isTestData?: boolean
}

export interface SharedMealParticipant {
  id: string
  sharedMealId: string
  userId: string
  visitId: string | null
  status: 'pending' | 'accepted' | 'declined'
  createdAt: string
  updatedAt: string
  isTestData?: boolean
}

export type RestaurantListCoverMode = 'automatic' | 'custom'

export interface RestaurantListCollection {
  id: string
  userId: string
  title: string
  description: string
  visibility: Visibility
  isRanked: boolean
  coverMode: RestaurantListCoverMode
  customCoverImageData: string | null
  customCoverPhotoId: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface RestaurantListItem {
  id: string
  listId: string
  restaurantId: string
  position: number
  note: string
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface PhotoCacheEntry {
  photoId: string
  blob: Blob
  fileSize: number
  cachedAt: string
  lastAccessedAt: string
}

export interface RestaurantSummary extends Restaurant {
  visitCount: number
  averageRating: number | null
  scoreOutOfTen: number | null
  latestVisitDate: string | null
  latestVisit: Visit | null
  visits: Visit[]
  averagePricePerPerson: number | null
  priceConfidence?: 'unknown' | 'low' | 'medium' | 'high'
  priceSource?: 'unknown' | 'manual' | 'visit_median'
  priceSampleCount?: number
  averageQueueMinutes: number | null
  recommendationRank?: number
  recommendationScore?: number
  recommendationReason?: string
  isRecommendation?: boolean
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

export function calculatePricePerPerson(totalPrice: number | null, partySize: number | null) {
  if (totalPrice === null || !Number.isFinite(totalPrice) || partySize === null || partySize < 1) return null
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
  /** Provider-supplied POI hierarchy/tags. Never inferred from the name. */
  categoryHints: string[]
  merchantImageUrl: string | null
  phone?: string | null
  websiteUrl?: string | null
  openingHours?: string | null
}

export interface Coordinates {
  longitude: number
  latitude: number
}

export interface CommunityVisit {
  personalTastePercent?: number | null
  calibratedLikeProbability?: import('../contracts/recommendationSignal').CalibratedLikeProbability | null
  visit: Visit
  restaurant: Pick<Restaurant, 'id' | 'amapPoiId' | 'name' | 'address' | 'city' | 'latitude' | 'longitude' | 'merchantImageUrl' | 'phone' | 'openingHours' | 'pricePerPerson' | 'tags' | 'markerEmoji'>
  user: Pick<UserProfile, 'id' | 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId' | 'membershipTier'>
  similarity?: number | null
  recommendationReason?: string | null
  recommendationReasons?: string[]
  recommendationType?: 'for_you' | 'similar_taste' | 'trending' | null
  recommendationRank?: number | null
  recommendationConfidence?: 'low' | 'medium' | 'high' | null
  recommendationFitLevel?: import('./recommendation').RecommendationFitLevel | null
  primaryReasons?: import('./recommendation').RecommendationReason[]
  secondaryReasons?: import('./recommendation').RecommendationReason[]
  publicRating?: import('./recommendation').PublicRatingReference | null
  isExploration?: boolean
  reasonCodes?: import('./recommendation').RecommendationReasonCode[]
  surface?: 'map' | 'discover' | null
}

export const DINING_MODE_OPTIONS: { value: DiningMode; label: string }[] = [
  { value: 'dine_in', label: '到店' },
  { value: 'takeout', label: '外卖' },
]

export const VISIBILITY_OPTIONS: { value: Visibility; label: string; description: string }[] = [
  { value: 'private', label: '仅自己', description: '只有你能看到' },
  { value: 'friends', label: '互相关注', description: '互相关注的用户可见' },
  { value: 'public', label: '公开', description: '会出现在发现' },
]

export const PAYMENT_MODE_OPTIONS: { value: PaymentMode; label: string }[] = [
  { value: 'aa', label: 'AA' },
  { value: 'my_treat', label: '我请客' },
  { value: 'treated', label: '别人请客' },
  { value: 'separate', label: '各付各的' },
  { value: 'other', label: '其他' },
]

export const DINING_OCCASION_OPTIONS: { value: DiningOccasion; label: string }[] = [
  { value: 'solo', label: '一个人' },
  { value: 'date', label: '约会' },
  { value: 'friends', label: '朋友聚餐' },
  { value: 'family', label: '家庭聚餐' },
  { value: 'business', label: '商务' },
  { value: 'celebration', label: '庆祝' },
  { value: 'other', label: '其他' },
]

export const RECOMMENDATION_SOURCE_OPTIONS: { value: RecommendationSourceType; label: string }[] = [
  { value: 'friend', label: '好友推荐' },
  { value: 'xiaohongshu', label: '小红书' },
  { value: 'douyin', label: '抖音' },
  { value: 'dianping', label: '大众点评' },
  { value: 'blogger', label: '美食博主' },
  { value: 'self', label: '自己发现' },
  { value: 'other', label: '其他' },
]

export function diningModeLabel(value: DiningMode | null | undefined) {
  return DINING_MODE_OPTIONS.find((option) => option.value === (value ?? 'dine_in'))?.label ?? '到店'
}

export function visibilityLabel(value: Visibility | null | undefined) {
  return VISIBILITY_OPTIONS.find((option) => option.value === (value ?? 'private'))?.label ?? '仅自己'
}

export const RATING_META: Record<
  WholeStarRating,
  { label: string; shortLabel: string; color: string }
> = {
  5: { label: '挚爱', shortLabel: '5 星', color: '#2f9b66' },
  4: { label: '喜欢', shortLabel: '4 星', color: '#69a9ea' },
  3: { label: '不错', shortLabel: '3 星', color: '#e0ad39' },
  2: { label: '一般', shortLabel: '2 星', color: '#ed8b4b' },
  1: { label: '不喜欢', shortLabel: '1 星', color: '#df5f5f' },
}

export const UNRATED_COLOR = '#9ea3a0'

export function nearestStar(rating: number | null | undefined): WholeStarRating | null {
  if (!rating) return null
  return Math.min(5, Math.max(1, Math.round(rating))) as WholeStarRating
}

export function isStarRating(value: unknown): value is StarRating {
  const numericValue = Number(value)
  return Number.isFinite(numericValue)
    && numericValue >= 0.5
    && numericValue <= 5
    && Number.isInteger(numericValue * 2)
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
  return rating == null ? null : Math.round(rating * 20) / 10
}

export const SCORE_BAND_ORDER: ScoreBand[] = [5, 4, 3, 2, 1]

export const SCORE_BAND_META: Record<
  ScoreBand,
  { label: string; color: string; shortLabel: string }
> = {
  5: { label: '9.0–10.0 分', shortLabel: '挚爱', color: '#27845a' },
  4: { label: '7.0–8.9 分', shortLabel: '喜欢', color: '#3c75bd' },
  3: { label: '5.0–6.9 分', shortLabel: '不错', color: '#7b62b5' },
  2: { label: '3.0–4.9 分', shortLabel: '一般', color: '#c87818' },
  1: { label: '1.0–2.9 分', shortLabel: '不爱', color: '#a42b36' },
}

export function scoreBandFromScore(score: number | null | undefined): ScoreBand | null {
  if (score === null || score === undefined || !Number.isFinite(score)) return null
  if (score >= 9) return 5
  if (score >= 7) return 4
  if (score >= 5) return 3
  if (score >= 3) return 2
  return 1
}

export function scoreColor(score: number | null | undefined) {
  const band = scoreBandFromScore(score)
  if (!band || score === null || score === undefined) return UNRATED_COLOR
  const ranges: Record<ScoreBand, { minimum: number; maximum: number; light: string; deep: string; reverse?: boolean }> = {
    5: { minimum: 9, maximum: 10, light: '#46a47b', deep: '#176f49' },
    4: { minimum: 7, maximum: 8.9, light: '#6594d3', deep: '#2b5ca9' },
    3: { minimum: 5, maximum: 6.9, light: '#9178bd', deep: '#644b9f' },
    2: { minimum: 3, maximum: 4.9, light: '#dfa04d', deep: '#b9650e' },
    1: { minimum: 1, maximum: 2.9, light: '#cb4650', deep: '#851522', reverse: true },
  }
  const range = ranges[band]
  const progress = Math.max(0, Math.min(1, (score - range.minimum) / (range.maximum - range.minimum)))
  return mixHex(range.light, range.deep, range.reverse ? 1 - progress : progress)
}

function mixHex(from: string, to: string, amount: number) {
  const parse = (value: string) => [1, 3, 5].map((index) => Number.parseInt(value.slice(index, index + 2), 16))
  const start = parse(from)
  const end = parse(to)
  return `#${start.map((channel, index) => Math.round(channel + (end[index] - channel) * amount).toString(16).padStart(2, '0')).join('')}`
}

export const STATUS_META: Record<RestaurantStatus, { label: string }> = {
  visited: { label: '去过' },
  wantToGo: { label: '想去' },
}
