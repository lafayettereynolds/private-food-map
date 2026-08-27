import type { RestaurantSummary, UserProfile, Visit, Visibility } from '../types/domain'

export type PublicProfileViewer = {
  viewerUserId: string
  ownerUserId: string
  isAcceptedFriend: boolean
  mapSharingEnabled: boolean
  mapVisibility: Visibility
}

export type PublicProfileCity = {
  city: string
  restaurantCount: number
}

export type PublicProfileMapModel = {
  cities: PublicProfileCity[]
  defaultCity: string | null
  selectedCity: string | null
  restaurants: RestaurantSummary[]
  totalRestaurantCount: number
}

export type PublicProfileActivity = {
  restaurant: RestaurantSummary
  visit: Visit
}

/**
 * The same policy is used by tests and local-only profile data. Cloud responses
 * are filtered again in the Worker before they reach the browser.
 */
export function filterPublicProfileVisits(visits: Visit[], viewer: PublicProfileViewer) {
  const validVisits = uniqueVisits(visits.filter((visit) => !visit.deletedAt))
  if (viewer.viewerUserId === viewer.ownerUserId) return validVisits
  if (!viewer.mapSharingEnabled || viewer.mapVisibility === 'private') return []
  if (viewer.mapVisibility === 'friends' && !viewer.isAcceptedFriend) return []
  return validVisits.filter((visit) => visit.visibility === 'public' || (viewer.isAcceptedFriend && visit.visibility === 'friends'))
}

export function buildPublicProfileMap(restaurants: RestaurantSummary[], requestedCity?: string | null): PublicProfileMapModel {
  const deduplicated = deduplicatePublicRestaurants(restaurants)
    .filter((restaurant) => Number.isFinite(restaurant.latitude) && Number.isFinite(restaurant.longitude))
  const cityCounts = new Map<string, number>()
  deduplicated.forEach((restaurant) => {
    const city = normalizedCity(restaurant.city)
    cityCounts.set(city, (cityCounts.get(city) ?? 0) + 1)
  })
  const cities = [...cityCounts]
    .map(([city, restaurantCount]) => ({ city, restaurantCount }))
    .sort((a, b) => b.restaurantCount - a.restaurantCount || a.city.localeCompare(b.city, 'zh-CN'))
  const defaultCity = cities[0]?.city ?? null
  const selectedCity = requestedCity && cityCounts.has(requestedCity) ? requestedCity : defaultCity
  return {
    cities,
    defaultCity,
    selectedCity,
    restaurants: selectedCity ? deduplicated.filter((restaurant) => normalizedCity(restaurant.city) === selectedCity) : [],
    totalRestaurantCount: deduplicated.length,
  }
}

export function deduplicatePublicRestaurants(restaurants: RestaurantSummary[]) {
  const grouped = new Map<string, RestaurantSummary[]>()
  restaurants.forEach((restaurant) => {
    const key = publicRestaurantIdentity(restaurant)
    grouped.set(key, [...(grouped.get(key) ?? []), restaurant])
  })
  return [...grouped.values()].map(mergePublicRestaurants).sort(comparePublicRestaurants)
}

export function selectRepresentativeRestaurants(restaurants: RestaurantSummary[], maximum = 4) {
  const ranked = deduplicatePublicRestaurants(restaurants)
    .map((restaurant) => ({ restaurant, rank: representativeRank(restaurant) }))
    .sort((a, b) => b.rank - a.rank || comparePublicRestaurants(a.restaurant, b.restaurant))
  const selected: RestaurantSummary[] = []
  const usedCovers = new Set<string>()
  for (const { restaurant } of ranked) {
    const cover = publicRestaurantCoverIdentity(restaurant)
    if (cover && usedCovers.has(cover)) continue
    selected.push(restaurant)
    if (cover) usedCovers.add(cover)
    if (selected.length >= maximum) break
  }
  return selected
}

export function selectPublicProfileActivity(restaurants: RestaurantSummary[], maximum = 8): PublicProfileActivity[] {
  const seen = new Set<string>()
  return restaurants
    .flatMap((restaurant) => restaurant.visits.map((visit) => ({ restaurant, visit })))
    .filter(({ visit }) => {
      if (visit.deletedAt || seen.has(visit.id)) return false
      seen.add(visit.id)
      return true
    })
    .sort((a, b) => b.visit.visitedAt.localeCompare(a.visit.visitedAt))
    .slice(0, maximum)
}

export function hasPublicTasteSummary(visits: Visit[]) {
  const rated = uniqueVisits(visits.filter((visit) => !visit.deletedAt && visit.rating !== null))
  return rated.length >= 5 && new Set(rated.map((visit) => visit.restaurantId)).size >= 3
}

export function publicRestaurantIdentity(restaurant: RestaurantSummary) {
  if (restaurant.amapPoiId && !restaurant.amapPoiId.startsWith('profile-')) return `poi:${restaurant.amapPoiId}`
  if (Number.isFinite(restaurant.latitude) && Number.isFinite(restaurant.longitude)) {
    return `geo:${restaurant.latitude.toFixed(5)}:${restaurant.longitude.toFixed(5)}`
  }
  return `name:${normalizedCity(restaurant.city)}:${restaurant.name.trim().toLocaleLowerCase()}`
}

function mergePublicRestaurants(restaurants: RestaurantSummary[]) {
  const best = [...restaurants].sort(comparePublicRestaurants)[0]
  const visits = uniqueVisits(restaurants.flatMap((restaurant) => restaurant.visits)).sort((a, b) => b.visitedAt.localeCompare(a.visitedAt))
  const ratings = visits.flatMap((visit) => visit.rating === null ? [] : [visit.rating])
  const prices = visits.flatMap((visit) => visit.pricePerPerson === null ? [] : [visit.pricePerPerson]).sort((a, b) => a - b)
  return {
    ...best,
    status: 'visited' as const,
    visits,
    visitCount: visits.length,
    latestVisit: visits[0] ?? null,
    latestVisitDate: visits[0]?.visitedAt ?? null,
    averageRating: ratings.length ? ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length : null,
    scoreOutOfTen: ratings.length ? ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length * 2 : null,
    averagePricePerPerson: prices.length ? prices[Math.floor(prices.length / 2)] : best.averagePricePerPerson,
  }
}

function uniqueVisits(visits: Visit[]) {
  const seen = new Set<string>()
  return visits.filter((visit) => {
    if (seen.has(visit.id)) return false
    seen.add(visit.id)
    return true
  })
}

function representativeRank(restaurant: RestaurantSummary) {
  const rating = restaurant.scoreOutOfTen ?? 0
  const repeat = Math.max(0, restaurant.visitCount - 1)
  const recency = restaurant.latestVisitDate ? Math.max(0, 365 - Math.floor((Date.now() - new Date(restaurant.latestVisitDate).getTime()) / 86_400_000)) / 365 : 0
  return rating * 4 + Math.min(restaurant.visitCount, 12) * 1.7 + Math.min(repeat, 6) * 2.4 + recency * 3
}

function comparePublicRestaurants(a: RestaurantSummary, b: RestaurantSummary) {
  return (b.scoreOutOfTen ?? -1) - (a.scoreOutOfTen ?? -1)
    || b.visitCount - a.visitCount
    || (b.latestVisitDate ?? '').localeCompare(a.latestVisitDate ?? '')
    || a.name.localeCompare(b.name, 'zh-CN')
}

function publicRestaurantCoverIdentity(restaurant: RestaurantSummary) {
  for (const visit of restaurant.visits) {
    if (visit.photoIds[0]) return `photo:${visit.photoIds[0]}`
    if (visit.photos[0]) return `source:${visit.photos[0]}`
  }
  return restaurant.markerPhotoId
    ? `photo:${restaurant.markerPhotoId}`
    : restaurant.markerImageData || restaurant.merchantImageUrl
      ? `source:${restaurant.markerImageData || restaurant.merchantImageUrl}`
      : ''
}

function normalizedCity(city: string) {
  return city.trim() || '其他城市'
}

export function profileMapVisibility(user: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) {
  return { mapSharingEnabled: user.mapSharingEnabled, mapVisibility: user.mapVisibility }
}
