import { CLOUD_SYNC_ENABLED } from '../config/appEnvironment'
import type { CloudVisit } from '../types/cloudSync'
import type { CommunityVisit, RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { drivePhotoReference } from './cloudSyncData'

export type PublicUser = Pick<UserProfile, 'id' | 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId' | 'membershipTier'>

interface CommunityResponse {
  items: Array<{
    visit: CloudVisit
    restaurant: Pick<RestaurantSummary, 'id' | 'name' | 'address' | 'city' | 'latitude' | 'longitude'>
    user: PublicUser
  }>
}

export async function fetchCommunityFeed(): Promise<CommunityVisit[]> {
  if (!CLOUD_SYNC_ENABLED) return []
  const response = await apiFetch<CommunityResponse>('/api/community')
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
  }))
}

export async function searchCloudUsers(query: string): Promise<PublicUser[]> {
  if (!CLOUD_SYNC_ENABLED || !query.trim()) return []
  const result = await apiFetch<{ users: PublicUser[] }>(`/api/users/search?q=${encodeURIComponent(query.trim())}`)
  return result.users
}

export async function fetchUserProfile(userId: string) {
  if (!CLOUD_SYNC_ENABLED) return null
  const result = await apiFetch<{
    user: PublicUser
    items: Array<{ visit: CloudVisit; restaurant: Pick<RestaurantSummary, 'id' | 'name' | 'address' | 'city' | 'latitude' | 'longitude'> }>
  }>(`/api/profiles/${encodeURIComponent(userId)}`)
  const user: UserProfile = {
    ...result.user,
    email: null,
    avatarImageData: result.user.avatarImageData ?? (result.user.avatarPhotoId ? drivePhotoReference(result.user.avatarPhotoId) : null),
    avatarPresetId: result.user.avatarPresetId ?? 'polar-bear',
    membershipTier: result.user.membershipTier ?? 'free',
    mapSharingEnabled: false,
    mapVisibility: 'private',
    authProvider: 'cloudflare-access',
    authSubject: null,
    createdAt: '',
    updatedAt: '',
    deletedAt: null,
  }
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
      amapPoiId: `profile-${item.restaurant.id}`,
      status: 'visited',
      preferenceLevel: 'normal',
      overallRating: null,
      foodRating: null,
      environmentRating: null,
      serviceRating: null,
      valueRating: null,
      tags: [],
      longTermNote: '',
      pricePerPerson: visit.pricePerPerson,
      markerType: 'emoji',
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: null,
      markerEmoji: '🍽️',
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
  grouped.forEach((restaurant) => restaurant.visits.sort((a, b) => b.visitedAt.localeCompare(a.visitedAt)))
  return { user, restaurants: [...grouped.values()] }
}

export async function sendFriendRequest(userId: string) {
  return apiFetch('/api/friendships', {
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

function cloudVisitToLocal(visit: CloudVisit): Visit {
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
    photos: visit.photoIds.map((photoId) => photoId ? drivePhotoReference(photoId) : ''),
  }
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
