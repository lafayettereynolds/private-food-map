import { describe, expect, it } from 'vitest'
import type { RestaurantSummary, Visit } from '../types/domain'
import { buildPublicProfileMap, filterPublicProfileVisits, hasPublicTasteSummary, selectPublicProfileActivity, selectRepresentativeRestaurants } from './publicProfile'

describe('public profile visibility', () => {
  const visits = [
    visit('public', 'restaurant-a', 'public'),
    visit('friends', 'restaurant-b', 'friends'),
    visit('private', 'restaurant-c', 'private'),
    { ...visit('deleted', 'restaurant-d', 'public'), deletedAt: '2026-08-25T00:00:00.000Z' },
    visit('public', 'restaurant-a', 'public'),
  ]

  it('lets the owner see every valid unique visit', () => {
    expect(filterPublicProfileVisits(visits, viewer('owner', true, 'private', false)).map((item) => item.id)).toEqual(['public', 'friends', 'private'])
  })

  it('shows only public visits to a stranger on a public map', () => {
    expect(filterPublicProfileVisits(visits, viewer('stranger', true, 'public', false)).map((item) => item.id)).toEqual(['public'])
  })

  it('adds friends-only visits for an accepted friend without exposing private visits', () => {
    expect(filterPublicProfileVisits(visits, viewer('friend', true, 'public', true)).map((item) => item.id)).toEqual(['public', 'friends'])
  })

  it('does not expose a friends-only or disabled map to a stranger', () => {
    expect(filterPublicProfileVisits(visits, viewer('stranger', true, 'friends', false))).toEqual([])
    expect(filterPublicProfileVisits(visits, viewer('stranger', false, 'public', true))).toEqual([])
  })
})

describe('public profile map', () => {
  it('aggregates repeated restaurants and chooses the city with the most visible restaurants', () => {
    const model = buildPublicProfileMap([
      restaurant('a-1', 'poi-a', '杭州市', 2, 8.4),
      restaurant('a-2', 'poi-a', '杭州市', 3, 9),
      restaurant('b', 'poi-b', '杭州市', 1, 7),
      restaurant('c', 'poi-c', '上海市', 1, 9.2),
    ])

    expect(model.totalRestaurantCount).toBe(3)
    expect(model.defaultCity).toBe('杭州市')
    expect(model.restaurants.map((item) => item.amapPoiId)).toEqual(['poi-a', 'poi-b'])
    expect(model.restaurants[0].visitCount).toBe(5)
    expect(model.cities).toEqual([{ city: '杭州市', restaurantCount: 2 }, { city: '上海市', restaurantCount: 1 }])
  })

  it('supports switching to another visible city without duplicating markers', () => {
    const model = buildPublicProfileMap([
      restaurant('a', 'poi-a', '杭州市', 1, 8),
      restaurant('b', 'poi-b', '上海市', 1, 9),
    ], '上海市')
    expect(model.selectedCity).toBe('上海市')
    expect(model.restaurants.map((item) => item.id)).toEqual(['b'])
  })
})

describe('public profile summaries', () => {
  it('only exposes a taste summary after enough rated public evidence', () => {
    expect(hasPublicTasteSummary([
      visit('1', 'a', 'public', 4), visit('2', 'a', 'public', 4),
      visit('3', 'b', 'public', 4), visit('4', 'b', 'public', 4),
      visit('5', 'c', 'public', 4),
    ])).toBe(true)
    expect(hasPublicTasteSummary([visit('1', 'a', 'public', 4), visit('2', 'b', 'public', 4), visit('3', 'c', 'public', 4)])).toBe(false)
  })

  it('selects representative restaurants without repeating the same cover', () => {
    const first = restaurant('a', 'poi-a', '杭州市', 8, 9.6, 'same-cover')
    const duplicateCover = restaurant('b', 'poi-b', '杭州市', 7, 9.4, 'same-cover')
    const differentCover = restaurant('c', 'poi-c', '杭州市', 4, 8.8, 'other-cover')
    expect(selectRepresentativeRestaurants([first, duplicateCover, differentCover], 2).map((item) => item.id)).toEqual(['a', 'c'])
  })

  it('keeps representative restaurants at Restaurant level while activity stays Visit level', () => {
    const first = restaurant('a', 'poi-a', '杭州市', 2, 8.8)
    first.visits[0].visitedAt = '2026-08-25T12:00:00.000Z'
    first.visits[1].visitedAt = '2026-08-20T12:00:00.000Z'
    const second = restaurant('b', 'poi-b', '杭州市', 1, 9.2)
    second.visits[0].visitedAt = '2026-08-23T12:00:00.000Z'

    expect(selectRepresentativeRestaurants([first, second], 4)).toHaveLength(2)
    expect(selectPublicProfileActivity([first, second]).map((item) => item.visit.id)).toEqual(['a-0', 'b-0', 'a-1'])
  })

  it('deduplicates synced visit ids in recent public activity', () => {
    const first = restaurant('a', 'poi-a', '杭州市', 1, 8.8)
    const duplicate = restaurant('b', 'poi-b', '杭州市', 1, 8.8)
    duplicate.visits[0].id = first.visits[0].id
    expect(selectPublicProfileActivity([first, duplicate])).toHaveLength(1)
  })
})

function viewer(viewerUserId: string, mapSharingEnabled: boolean, mapVisibility: 'private' | 'friends' | 'public', isAcceptedFriend: boolean) {
  return { viewerUserId, ownerUserId: 'owner', mapSharingEnabled, mapVisibility, isAcceptedFriend }
}

function restaurant(id: string, amapPoiId: string, city: string, visitCount: number, scoreOutOfTen: number, image = `${id}-cover`): RestaurantSummary {
  const visits = Array.from({ length: visitCount }, (_, index) => visit(`${id}-${index}`, id, 'public', 4, image))
  return {
    id, userId: 'owner', amapPoiId, name: id, address: '测试路 1 号', city, latitude: city === '杭州市' ? 30.25 : 31.23, longitude: city === '杭州市' ? 120.17 : 121.47,
    status: 'visited', preferenceLevel: 'like', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null, valueRating: null,
    tags: ['餐厅'], longTermNote: '', pricePerPerson: 100, markerType: 'image', markerImageData: image, markerPhotoId: null, merchantImageUrl: image,
    markerEmoji: '🍽️', createdAt: '2026-08-25T00:00:00.000Z', updatedAt: '2026-08-25T00:00:00.000Z', deletedAt: null,
    visitCount, averageRating: scoreOutOfTen / 2, scoreOutOfTen, latestVisitDate: visits[0]?.visitedAt ?? null, latestVisit: visits[0] ?? null, visits,
    averagePricePerPerson: 100, averageQueueMinutes: null,
  }
}

function visit(id: string, restaurantId: string, visibility: Visit['visibility'], rating: Visit['rating'] = 4, photo = ''): Visit {
  return {
    id, userId: 'owner', restaurantId, visitedAt: '2026-08-25T12:00:00.000Z', rating, visibility, diningMode: 'dine_in', totalPrice: null,
    myActualSpend: null, paymentMode: null, pricePerPerson: null, partySize: 1, queueDuration: null, diningOccasions: [], diningOccasion: null,
    diningOccasionText: '', valueRating: null, environmentRating: null, serviceRating: null, valueTags: [], environmentTags: [], serviceTags: [],
    noiseLevel: null, diningDuration: null, portionLevel: null, transportConvenience: null, specialNotes: '', recommendationSourceType: null,
    recommendationSourceUserId: null, recommendationSourceText: '', sharedMealId: null, companions: [], companionIds: [], dishes: [], note: '',
    photos: photo ? [photo] : [], photoIds: photo ? [null] : [], createdAt: '2026-08-25T12:00:00.000Z', updatedAt: '2026-08-25T12:00:00.000Z', deletedAt: null,
  }
}
