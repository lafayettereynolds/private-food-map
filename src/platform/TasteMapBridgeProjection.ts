import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { CURRENT_USER_ID } from '../db/social'
import { restaurantCity } from '../services/restaurantCity'
import type {
  TasteMapProfileDashboardDTO,
  TasteMapProfileDashboardViewModel,
  TasteMapRestaurantDTO,
  TasteMapRestaurantDetailDTO,
  TasteMapRestaurantDetailViewModel,
  TasteMapUserDTO,
  TasteMapVisitDTO,
} from './TasteMapPlatform'

export function projectBridgeProfile(dto: TasteMapProfileDashboardDTO): TasteMapProfileDashboardViewModel {
  const restaurants = dto.restaurants.map(projectRestaurant)
  return {
    user: projectUser(dto.user),
    restaurants,
    visits: restaurants.flatMap((restaurant) => restaurant.visits),
    followerCount: dto.followerCount,
    followingCount: dto.followingCount,
    restaurantImages: Object.fromEntries(dto.restaurants.map((restaurant) => [restaurant.id, restaurant.image])),
    analyticsIdentity: dto.analyticsIdentity?.ownerUserID === dto.user.id
      ? { ...dto.analyticsIdentity, recordOwnerID: CURRENT_USER_ID } : null,
  }
}

export function projectBridgeRestaurant(dto: TasteMapRestaurantDetailDTO): TasteMapRestaurantDetailViewModel {
  const restaurant = projectRestaurant(dto.restaurant)
  restaurant.status = dto.viewerState === 'visited' ? 'visited' : 'wantToGo'
  restaurant.isRecommendation = dto.viewerState === 'none'
  return {
    restaurant,
    image: dto.restaurant.image,
    contentImage: dto.restaurant.contentImage,
    contentImageResolution: dto.restaurant.contentImageResolution,
    socialStats: dto.socialStats ?? null,
    viewerState: dto.viewerState,
    editableVisitIDs: dto.editableVisitIDs,
    capabilities: dto.capabilities,
  }
}

function projectUser(user: TasteMapUserDTO): UserProfile {
  return {
    id: user.id,
    nickname: user.nickname,
    email: null,
    bio: user.bio,
    city: user.city,
    // This projection belongs to the Native adapter. Keep the opaque ID, but
    // resolve its bytes through the authenticated Native resource handler,
    // never through the Browser's unrelated Dexie / Drive photo store.
    avatarImageData: user.avatarPhotoId
      ? `tastemap-resource://photo/${encodeURIComponent(user.avatarPhotoId)}/display` : null,
    avatarPhotoId: user.avatarPhotoId,
    avatarPresetId: user.avatarPresetId,
    membershipTier: user.membershipTier,
    mapSharingEnabled: user.mapSharingEnabled,
    mapVisibility: user.mapVisibility,
    authProvider: 'apple',
    authSubject: null,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
    deletedAt: null,
  }
}

function projectRestaurant(restaurant: TasteMapRestaurantDTO): RestaurantSummary {
  // Native children have already been owner-scoped and joined to this parent.
  // Use its public identity; a local UUID (or differently cased UUID) is not it.
  const visits = restaurant.visits.map((visit) => projectVisit({ ...visit, restaurantId: restaurant.id }))
  const imageURL = restaurant.image.kind === 'foodDiningFallback' || restaurant.image.kind === 'foodCategoryVisual' ? null : restaurant.image.resourceURL
  return {
    id: restaurant.id,
    // The shared React presentation model uses this stable viewer sentinel to
    // distinguish the current owner's records from public/community records.
    // The real Taste Map user ID remains on the profile DTO and never changes.
    userId: CURRENT_USER_ID,
    amapPoiId: '',
    placeIdentities: [],
    name: restaurant.name,
    address: restaurant.address,
    city: restaurantCity(restaurant.city, restaurant.address),
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    status: restaurant.status,
    preferenceLevel: 'normal',
    overallRating: restaurant.averageRating,
    foodRating: null,
    environmentRating: null,
    serviceRating: null,
    valueRating: null,
    tags: restaurant.tags,
    longTermNote: '',
    pricePerPerson: restaurant.referencePrice,
    phone: restaurant.phone,
    websiteUrl: restaurant.websiteUrl ?? null,
    openingHours: restaurant.openingHours,
    markerType: restaurant.markerType ?? (imageURL ? 'image' : 'emoji'),
    markerImageData: imageURL,
    markerPhotoId: restaurant.image.kind === 'nativeResource' || restaurant.image.kind === 'publicOrCached' ? restaurant.image.photoID : null,
    merchantImageUrl: restaurant.image.kind === 'providerMerchant' ? restaurant.image.resourceURL : null,
    markerEmoji: restaurant.markerEmoji ?? '',
    createdAt: restaurant.createdAt,
    updatedAt: restaurant.updatedAt,
    deletedAt: null,
    visitCount: restaurant.visitCount,
    averageRating: restaurant.averageRating,
    scoreOutOfTen: restaurant.scoreOutOfTen,
    latestVisitDate: restaurant.latestVisitDate,
    latestVisit: visits[0] ?? null,
    visits,
    averagePricePerPerson: restaurant.referencePrice,
    averageQueueMinutes: null,
  }
}

function projectVisit(visit: TasteMapVisitDTO): Visit {
  return {
    id: visit.id,
    userId: CURRENT_USER_ID,
    restaurantId: visit.restaurantId,
    visitedAt: visit.visitedAt,
    rating: visit.rating,
    visibility: visit.visibility,
    diningMode: visit.diningMode,
    totalPrice: visit.totalPrice,
    myActualSpend: visit.myActualSpend,
    paymentMode: visit.paymentMode ?? null,
    pricePerPerson: visit.pricePerPerson,
    partySize: visit.partySize,
    queueDuration: visit.queueDuration,
    diningOccasions: visit.diningOccasions,
    diningOccasion: null,
    diningOccasionText: visit.diningOccasionText,
    valueRating: visit.valueRating,
    environmentRating: visit.environmentRating,
    serviceRating: visit.serviceRating,
    valueTags: visit.valueTags,
    environmentTags: visit.environmentTags,
    serviceTags: visit.serviceTags,
    noiseLevel: visit.noiseLevel ?? null,
    diningDuration: visit.diningDuration ?? null,
    portionLevel: visit.portionLevel ?? null,
    transportConvenience: visit.transportConvenience ?? null,
    specialNotes: visit.specialNotes ?? '',
    recommendationSourceType: visit.recommendationSourceType ?? null,
    recommendationSourceUserId: visit.recommendationSourceUserId ?? null,
    recommendationSourceText: visit.recommendationSourceText,
    sharedMealId: visit.sharedMealId ?? null,
    companions: visit.companions,
    companionIds: visit.companionIds,
    dishes: (visit.dishes ?? []).map((dish) => ({
      id: dish.id,
      name: dish.name,
      taste: dish.taste,
      rating: dish.rating as Visit['rating'],
      price: dish.price,
      imageData: null,
      photoId: dish.photoID,
    })),
    note: visit.note,
    photos: (visit.photos ?? []).map((photo) => photo.kind === 'foodDiningFallback' || photo.kind === 'foodCategoryVisual' ? '' : photo.resourceURL),
    photoIds: (visit.photos ?? []).map((photo) => 'photoID' in photo ? photo.photoID : null),
    createdAt: visit.createdAt,
    updatedAt: visit.updatedAt,
    deletedAt: null,
  }
}
