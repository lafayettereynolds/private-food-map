import { IS_DEVELOPMENT, SOCIAL_API_ENABLED } from '../config/appEnvironment'
import type { CloudVisit } from '../types/cloudSync'
import type { CompanionLinkRequest, CommunityVisit, DiningCompanion, Follow, Friendship, HistoricalMealFact, RestaurantListCollection, RestaurantListItem, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { drivePhotoReference } from './cloudSyncData'

export type PublicUser = Pick<UserProfile, 'id' | 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId' | 'membershipTier'>

export function publicUserToProfile(user: PublicUser): UserProfile {
  return {
    ...user,
    email: null,
    avatarImageData: user.avatarImageData ?? (user.avatarPhotoId ? drivePhotoReference(user.avatarPhotoId) : null),
    avatarPresetId: user.avatarPresetId ?? 'polar-bear',
    membershipTier: user.membershipTier ?? 'free',
    mapSharingEnabled: false,
    mapVisibility: 'private',
    authProvider: 'cloudflare-access',
    authSubject: null,
    createdAt: '',
    updatedAt: '',
    deletedAt: null,
  }
}

interface CommunityResponse {
  mode: DiscoveryMode
  city: string
  items: Array<{
    visit: CloudVisit
    restaurant: Pick<RestaurantSummary, 'id' | 'amapPoiId' | 'name' | 'address' | 'city' | 'latitude' | 'longitude' | 'merchantImageUrl'>
    user: PublicUser
    similarity?: number | null
    recommendationReason?: string | null
    recommendationType?: CommunityVisit['recommendationType']
    recommendationRank?: number | null
    recommendationConfidence?: CommunityVisit['recommendationConfidence']
    reasonCodes?: CommunityVisit['reasonCodes']
    surface?: CommunityVisit['surface']
  }>
}

export type DiscoveryMode = 'following' | 'for_you' | 'similar' | 'latest' | 'trending'

export async function fetchCommunityFeed(mode: DiscoveryMode = 'for_you', city = '', trendWindow: 7 | 30 = 7): Promise<CommunityVisit[]> {
  if (!SOCIAL_API_ENABLED) return []
  const response = await apiFetch<CommunityResponse>(`/api/community?mode=${mode}&city=${encodeURIComponent(city)}&window=${trendWindow}`)
  return response.items.map((item) => ({
    visit: cloudVisitToLocal(item.visit),
    restaurant: item.restaurant,
    user: {
      id: item.user.id,
      nickname: item.user.nickname,
      email: null,
      bio: item.user.bio,
      city: item.user.city,
      avatarImageData: item.user.avatarImageData ?? (item.user.avatarPhotoId ? drivePhotoReference(item.user.avatarPhotoId) : null),
      avatarPhotoId: item.user.avatarPhotoId,
      avatarPresetId: item.user.avatarPresetId ?? 'polar-bear',
      membershipTier: item.user.membershipTier ?? 'free',
      mapSharingEnabled: false,
      mapVisibility: 'private',
      authProvider: 'cloudflare-access',
      authSubject: null,
      createdAt: '',
      updatedAt: '',
      deletedAt: null,
    },
    similarity: item.similarity ?? null,
    recommendationReason: item.recommendationReason ?? null,
    recommendationType: item.recommendationType ?? null,
    recommendationRank: item.recommendationRank ?? null,
    recommendationConfidence: item.recommendationConfidence ?? null,
    reasonCodes: item.reasonCodes ?? [],
    surface: item.surface ?? null,
  }))
}

export async function searchCloudUsers(query: string): Promise<PublicUser[]> {
  if (!SOCIAL_API_ENABLED) return []
  const result = await apiFetch<{ users: PublicUser[] }>(`/api/users/search?q=${encodeURIComponent(query.trim())}`)
  return result.users
}

export async function fetchFollows(): Promise<Follow[]> {
  if (!SOCIAL_API_ENABLED) return []
  const result = await apiFetch<{ follows: Follow[] }>('/api/follows')
  return result.follows
}

export async function setFollow(userId: string, followed: boolean): Promise<void> {
  if (!SOCIAL_API_ENABLED) return
  await apiFetch('/api/follows', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: followed ? 'add' : 'remove', userId }),
  })
}

export async function fetchPublicRestaurantList(listId: string) {
  if (!SOCIAL_API_ENABLED) return null
  return apiFetch<{
    list: Omit<RestaurantListCollection, 'customCoverImageData'>
    items: RestaurantListItem[]
    restaurants: Array<Pick<RestaurantSummary, 'id' | 'amapPoiId' | 'name' | 'address' | 'city' | 'latitude' | 'longitude' | 'tags' | 'merchantImageUrl' | 'markerEmoji'>>
  }>(`/api/restaurant-lists/${encodeURIComponent(listId)}`)
}

export async function fetchUserProfile(userId: string) {
  if (!SOCIAL_API_ENABLED) return null
  const result = await apiFetch<{
    user: PublicUser
    items: Array<{ visit: CloudVisit; restaurant: Pick<RestaurantSummary, 'id' | 'amapPoiId' | 'name' | 'address' | 'city' | 'latitude' | 'longitude' | 'tags' | 'pricePerPerson' | 'phone' | 'openingHours' | 'merchantImageUrl' | 'markerEmoji'> }>
    followerCount: number
    followingCount: number
  }>(`/api/profiles/${encodeURIComponent(userId)}`)
  const user = publicUserToProfile(result.user)
  const grouped = new Map<string, RestaurantSummary>()
  result.items.forEach((item) => {
    const visit = cloudVisitToLocal(item.visit)
    const current = grouped.get(item.restaurant.id)
    if (current) {
      current.visits.push(visit)
      current.visitCount += 1
      if (!current.latestVisitDate || visit.visitedAt > current.latestVisitDate) {
        current.latestVisitDate = visit.visitedAt
        current.latestVisit = visit
      }
      return
    }
    grouped.set(item.restaurant.id, {
      ...item.restaurant,
      userId,
      amapPoiId: item.restaurant.amapPoiId || `profile-${item.restaurant.id}`,
      status: 'visited',
      preferenceLevel: 'normal',
      overallRating: null,
      foodRating: null,
      environmentRating: null,
      serviceRating: null,
      valueRating: null,
      tags: item.restaurant.tags ?? [],
      longTermNote: '',
      pricePerPerson: item.restaurant.pricePerPerson ?? visit.pricePerPerson,
      markerType: item.restaurant.merchantImageUrl ? 'image' : 'emoji',
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: item.restaurant.merchantImageUrl ?? null,
      markerEmoji: item.restaurant.markerEmoji || '🍽️',
      createdAt: visit.createdAt,
      updatedAt: visit.updatedAt,
      deletedAt: null,
      visitCount: 1,
      averageRating: visit.rating,
      scoreOutOfTen: visit.rating ? visit.rating * 2 : null,
      latestVisitDate: visit.visitedAt,
      latestVisit: visit,
      visits: [visit],
      averagePricePerPerson: visit.pricePerPerson,
      averageQueueMinutes: null,
    })
  })
  grouped.forEach((restaurant) => {
    restaurant.visits.sort((a, b) => b.visitedAt.localeCompare(a.visitedAt))
    const ratings = restaurant.visits.flatMap((visit) => visit.rating === null ? [] : [visit.rating])
    restaurant.averageRating = ratings.length ? ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length : null
    restaurant.scoreOutOfTen = restaurant.averageRating === null ? null : restaurant.averageRating * 2
    const prices = restaurant.visits.flatMap((visit) => visit.pricePerPerson === null ? [] : [visit.pricePerPerson]).sort((a, b) => a - b)
    restaurant.averagePricePerPerson = prices.length ? prices[Math.floor(prices.length / 2)] : null
  })
  return { user, restaurants: [...grouped.values()], followerCount: result.followerCount ?? 0, followingCount: result.followingCount ?? 0 }
}

export async function sendFriendRequest(userId: string): Promise<Friendship> {
  return apiFetch<Friendship>('/api/friendships', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'request', userId }),
  })
}

export async function respondToFriendship(friendshipId: string, status: 'accepted' | 'rejected' | 'removed') {
  return apiFetch('/api/friendships', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(status === 'removed' ? { action: 'remove', friendshipId } : { action: 'respond', friendshipId, status }),
  })
}

export async function fetchCompanionLinks() {
  if (!SOCIAL_API_ENABLED) return { companions: [] as DiningCompanion[], requests: [] as CompanionLinkRequest[], users: [] as PublicUser[] }
  return apiFetch<{ companions: DiningCompanion[]; requests: CompanionLinkRequest[]; users: PublicUser[] }>('/api/companion-links')
}

export async function requestCompanionLink(companion: Pick<DiningCompanion, 'id' | 'displayName'>, targetUserId: string) {
  return apiFetch<CompanionLinkRequest>('/api/companion-links', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'request', companionId: companion.id, displayName: companion.displayName, targetUserId }),
  })
}

export async function respondToCompanionLink(requestId: string, status: 'accepted' | 'rejected') {
  return apiFetch<CompanionLinkRequest>('/api/companion-links', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'respond', requestId, status }),
  })
}

export async function unlinkCompanion(companionId: string) {
  return apiFetch<DiningCompanion>('/api/companion-links', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'unlink', companionId }),
  })
}

export async function fetchCompanionHistory(requestId: string) {
  return apiFetch<{ request: CompanionLinkRequest; facts: HistoricalMealFact[] }>(`/api/companion-links/${encodeURIComponent(requestId)}/history`)
}

export async function importCompanionHistory(requestId: string, sourceVisitIds: string[]) {
  return apiFetch<{ imported: number }>('/api/companion-links', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'import', requestId, sourceVisitIds }),
  })
}

function cloudVisitToLocal(visit: CloudVisit): Visit {
  const syncedPhotos = visit.photoIds.map((photoId) => photoId ? drivePhotoReference(photoId) : '')
  const isDiscoveryTestVisit = visit.isTestData || visit.id.startsWith('test-discovery-')
  const demoPhotos = IS_DEVELOPMENT && isDiscoveryTestVisit && !syncedPhotos.some(Boolean)
    ? testVisitPhotos(visit.id)
    : syncedPhotos
  return {
    ...visit,
    userId: visit.userId ?? 'owner',
    visibility: visit.visibility ?? 'private',
    diningMode: visit.diningMode ?? 'dine_in',
    myActualSpend: visit.myActualSpend ?? null,
    paymentMode: visit.paymentMode ?? null,
    diningOccasions: visit.diningOccasions?.length ? visit.diningOccasions : visit.diningOccasion ? [visit.diningOccasion] : [],
    diningOccasion: visit.diningOccasion ?? visit.diningOccasions?.[0] ?? null,
    diningOccasionText: visit.diningOccasionText ?? '',
    valueRating: visit.valueRating ?? null,
    environmentRating: visit.environmentRating ?? null,
    serviceRating: visit.serviceRating ?? null,
    valueTags: visit.valueTags ?? [],
    environmentTags: visit.environmentTags ?? [],
    serviceTags: visit.serviceTags ?? [],
    noiseLevel: visit.noiseLevel ?? null,
    diningDuration: visit.diningDuration ?? null,
    portionLevel: visit.portionLevel ?? null,
    transportConvenience: visit.transportConvenience ?? null,
    specialNotes: visit.specialNotes ?? '',
    recommendationSourceType: visit.recommendationSourceType ?? null,
    recommendationSourceUserId: visit.recommendationSourceUserId ?? null,
    recommendationSourceText: visit.recommendationSourceText ?? '',
    sharedMealId: visit.sharedMealId ?? null,
    dishes: visit.dishes.map((dish) => ({ ...dish, imageData: dish.photoId ? drivePhotoReference(dish.photoId) : null })),
    photos: demoPhotos,
    photoIds: demoPhotos === syncedPhotos ? visit.photoIds : demoPhotos.map(() => null),
  }
}

const TEST_VISIT_PHOTOS = [
  'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1200&q=82',
  'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=1200&q=82',
  'https://images.unsplash.com/photo-1559314809-0d155014e29e?auto=format&fit=crop&w=1200&q=82',
  'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=1200&q=82',
  'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=1200&q=82',
  'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?auto=format&fit=crop&w=1200&q=82',
]

function testVisitPhotos(visitId: string) {
  const seed = [...visitId].reduce((total, character) => ((total * 31) + character.charCodeAt(0)) >>> 0, 17)
  const count = 2 + (seed % 2)
  return Array.from({ length: count }, (_, index) => TEST_VISIT_PHOTOS[(seed + index * 2) % TEST_VISIT_PHOTOS.length])
}

async function apiFetch<Result = unknown>(input: string, init: RequestInit = {}): Promise<Result> {
  const response = await fetch(input, { ...init, credentials: 'same-origin', headers: { Accept: 'application/json', ...init.headers } })
  const payload: unknown = await response.json().catch(() => null)
  if (!response.ok) {
    const message = payload && typeof payload === 'object' && typeof (payload as Record<string, unknown>).error === 'string'
      ? String((payload as Record<string, unknown>).error)
      : `请求失败（${response.status}）`
    throw new Error(message)
  }
  return payload as Result
}
