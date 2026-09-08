import type {
  TasteMapHybridDiscoveryItemDTO,
  TasteMapImageDescriptor,
  TasteMapMapBrowseOptions,
  TasteMapMapBrowseRequest,
} from '../platform/TasteMapPlatform'
import type { RestaurantSummary } from '../types/domain'
import { isDiscoveryPlacementEligible } from '../platform/TasteMapDiscoveryPolicy'
import { restaurantCityComparisonKey, restaurantCityFilterOptions } from '../services/restaurantCity'

export interface MapRecommendationProjection {
  restaurant: RestaurantSummary
  image: TasteMapImageDescriptor
  rank: number
}

/** One ordered For You result set is shared by Discovery and Map. */
export function canonicalForYouRecommendations(items: readonly TasteMapHybridDiscoveryItemDTO[]) {
  const ordered = items.filter(isDiscoveryPlacementEligible)
    .sort((left, right) => left.rank - right.rank || left.id.localeCompare(right.id))
  const seen = new Set<string>()
  return ordered.filter((item) => {
    const key = item.restaurant.id.toLocaleLowerCase()
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

export function forYouRecommendationDataVersion(
  generatedAt: string,
  items: readonly TasteMapHybridDiscoveryItemDTO[],
) {
  return `${generatedAt}:${JSON.stringify(items.map((item) => [item.rank, item.restaurant.id, item.restaurant.image.kind, item.restaurant.city]))}`
}

export function projectForYouRecommendationsToMap(
  items: readonly TasteMapHybridDiscoveryItemDTO[],
  ownerUserID: string,
  generatedAt: string,
): MapRecommendationProjection[] {
  return canonicalForYouRecommendations(items).map((item) => {
    const publicRating = item.communityRating.valueOutOfFive
    const imageURL = 'resourceURL' in item.restaurant.image ? item.restaurant.image.resourceURL : null
    const photoID = 'photoID' in item.restaurant.image ? item.restaurant.image.photoID : null
    return {
      rank: item.rank,
      image: item.restaurant.image,
      restaurant: {
        id: item.restaurant.id,
        userId: ownerUserID,
        amapPoiId: '',
        placeIdentities: [],
        name: item.restaurant.name,
        address: item.restaurant.address,
        city: item.restaurant.city,
        latitude: item.restaurant.latitude,
        longitude: item.restaurant.longitude,
        status: item.viewerState === 'visited' ? 'visited' : 'wantToGo',
        preferenceLevel: 'normal',
        overallRating: publicRating,
        foodRating: null,
        environmentRating: null,
        serviceRating: null,
        valueRating: null,
        tags: item.restaurant.tags,
        longTermNote: '',
        pricePerPerson: item.restaurant.referencePrice,
        phone: null,
        openingHours: null,
        markerType: imageURL ? 'image' : 'emoji',
        markerImageData: imageURL,
        markerPhotoId: photoID,
        merchantImageUrl: null,
        markerEmoji: '',
        createdAt: generatedAt,
        updatedAt: generatedAt,
        deletedAt: null,
        visitCount: 0,
        averageRating: publicRating,
        // The recommendation snapshot stores a five-point aggregate, while
        // every current product surface presents Restaurant scores out of ten.
        scoreOutOfTen: publicRating == null ? null : publicRating * 2,
        latestVisitDate: null,
        latestVisit: null,
        visits: [],
        averagePricePerPerson: item.restaurant.referencePrice,
        averageQueueMinutes: null,
        recommendationRank: item.rank,
        recommendationScore: Math.max(0, 100 - item.rank),
        recommendationReason: item.reasons[0]?.text ?? item.reason,
        isRecommendation: true,
      },
    }
  })
}

export function filterForYouMapRecommendations(
  values: readonly MapRecommendationProjection[],
  request: TasteMapMapBrowseRequest,
) {
  const query = request.search.trim().toLocaleLowerCase()
  const filtered = values.filter(({ restaurant }) => {
    if (request.bounds && !coordinateIsInBounds(restaurant, request.bounds)) return false
    if (request.filters.city && restaurantCityComparisonKey(restaurant.city) !== restaurantCityComparisonKey(request.filters.city)) return false
    if (request.filters.minimumScoreOutOfTen != null
      && (restaurant.scoreOutOfTen ?? -1) < request.filters.minimumScoreOutOfTen) return false
    if (request.filters.scoreBands?.length) {
      const band = scoreBand(restaurant.scoreOutOfTen)
      if (band == null || !request.filters.scoreBands.includes(band)) return false
    }
    const price = restaurant.averagePricePerPerson ?? restaurant.pricePerPerson
    if (request.filters.maximumSpend != null && (price ?? Number.POSITIVE_INFINITY) > request.filters.maximumSpend) return false
    if (request.filters.priceRange && !priceMatches(price, request.filters.priceRange)) return false
    if (request.filters.cuisine && !restaurant.tags.includes(request.filters.cuisine)) return false
    if (request.filters.distanceKilometers != null) {
      if (!request.currentLocation
        || distanceMeters(request.currentLocation, restaurant) > request.filters.distanceKilometers * 1_000) return false
    }
    return !query || [restaurant.name, restaurant.city, restaurant.address, ...restaurant.tags]
      .join('\n').toLocaleLowerCase().includes(query)
  })
  if (request.sort === 'rating') {
    return [...filtered].sort((left, right) => (right.restaurant.scoreOutOfTen ?? -1) - (left.restaurant.scoreOutOfTen ?? -1) || left.rank - right.rank)
  }
  if (request.sort === 'distance' && request.currentLocation) {
    return [...filtered].sort((left, right) => distanceMeters(request.currentLocation!, left.restaurant) - distanceMeters(request.currentLocation!, right.restaurant) || left.rank - right.rank)
  }
  // “综合/最近” preserves Discovery rank; Map must not invent a second rank.
  return filtered
}

export function recommendationMapOptions(
  options: TasteMapMapBrowseOptions,
  items: readonly TasteMapHybridDiscoveryItemDTO[],
): TasteMapMapBrowseOptions {
  return {
    ...options,
    cities: restaurantCityFilterOptions(canonicalForYouRecommendations(items).map((item) => item.restaurant.city)),
    cuisines: stableValues([...options.cuisines, ...items.flatMap((item) => item.restaurant.tags)]),
  }
}

function coordinateIsInBounds(
  value: { latitude: number; longitude: number },
  bounds: NonNullable<TasteMapMapBrowseRequest['bounds']>,
) {
  const longitudeMatches = bounds.west <= bounds.east
    ? value.longitude >= bounds.west && value.longitude <= bounds.east
    : value.longitude >= bounds.west || value.longitude <= bounds.east
  return value.latitude >= bounds.south && value.latitude <= bounds.north && longitudeMatches
}

function scoreBand(score: number | null): 1 | 2 | 3 | 4 | 5 | null {
  if (score == null || !Number.isFinite(score)) return null
  if (score >= 9) return 5
  if (score >= 7) return 4
  if (score >= 5) return 3
  if (score >= 3) return 2
  return 1
}

function priceMatches(
  value: number | null,
  range: NonNullable<TasteMapMapBrowseRequest['filters']['priceRange']>,
) {
  if (value == null || !Number.isFinite(value)) return false
  if (range === 'under100') return value < 100
  if (range === '100to200') return value >= 100 && value <= 200
  return value > 200
}

function distanceMeters(
  left: { latitude: number; longitude: number },
  right: { latitude: number; longitude: number },
) {
  const radians = (value: number) => value * Math.PI / 180
  const latitudeDelta = radians(right.latitude - left.latitude)
  const longitudeDelta = radians(right.longitude - left.longitude)
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(radians(left.latitude)) * Math.cos(radians(right.latitude)) * Math.sin(longitudeDelta / 2) ** 2
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)))
}

function stableValues(values: readonly string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))]
    .sort((left, right) => left.localeCompare(right, 'zh-CN'))
}
