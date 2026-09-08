import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import { MapView, restaurantMarkerReconciliationPlan, restaurantMarkerSignature } from './MapView'
import { compareMarkerLayerPriority, markerCoincidentGroups, markerCoincidentStackMembers, markerIsCoincidentGroup, markerLayerPriorities, markerRegionalGroupingDistance, markerRegionalGroups, markerUsesRegionalGrouping } from './mapMarkerPriority'
import { MapRestaurantGroupSheet, resolveMapGroupRestaurants } from './MyMapBrowsePage'
import * as markerShape from './mapMarkerShape'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))
vi.mock('../services/mapService', () => ({ mapService: { isConfigured: false } }))

const marker = (
  id: string,
  scoreOutOfTen: number | null,
  visitCount: number,
  recommendationScore?: number,
) => ({ id, scoreOutOfTen, visitCount, recommendationScore })

describe('hybrid Restaurant marker ordering', () => {
  it('keeps selected above rating, rating above visit count, and ID as a deterministic tie break', () => {
    const low = marker('restaurant-low', 7.8, 9_999)
    const high = marker('restaurant-high', 7.9, 0)
    expect(compareMarkerLayerPriority(high, low)).toBeGreaterThan(0)
    const selectedLayers = markerLayerPriorities([high, low], low.id)
    expect(selectedLayers.get(low.id)).toBeGreaterThan(selectedLayers.get(high.id)!)

    const fewerVisits = marker('restaurant-z', 8.8, 4)
    const moreVisits = marker('restaurant-a', 8.8, 5)
    expect(compareMarkerLayerPriority(moreVisits, fewerVisits)).toBeGreaterThan(0)

    expect(compareMarkerLayerPriority(marker('restaurant-a', 8.8, 5), marker('restaurant-b', 8.8, 5))).toBeLessThan(0)
    expect(compareMarkerLayerPriority(marker('restaurant-a', 8.8, 5), marker('RESTAURANT-A', 8.8, 5))).toBe(0)
  })

  it('places a rated Restaurant above nil rating without moving the user marker into this comparator', () => {
    expect(compareMarkerLayerPriority(marker('rated', 0, 0), marker('nil', null, 9_999))).toBeGreaterThan(0)
  })

  it('puts exact finite scores before recommendation rank, then rank before visits', () => {
    const first = { ...marker('recommendation-first', 8.7999, 99_999, 99), recommendationRank: 1 }
    const later = { ...marker('recommendation-later', 8.8, 0, 88), recommendationRank: 999 }
    expect(compareMarkerLayerPriority(later, first)).toBeGreaterThan(0)
    expect(compareMarkerLayerPriority({ ...first, scoreOutOfTen: 8.8 }, later)).toBeGreaterThan(0)
    expect(compareMarkerLayerPriority(marker('finite', 0, 0), { ...first, scoreOutOfTen: Number.NaN })).toBeGreaterThan(0)
    expect(markerLayerPriorities([later, first]).get(later.id)).toBeGreaterThan(markerLayerPriorities([later, first]).get(first.id)!)
  })

  it('keeps cities independent and only consolidates wide regions into real Restaurant representatives', () => {
    const high = marker('high', 9.6, 1)
    const medium = marker('medium', 8.4, 4)
    const low = marker('low', 7.2, 8)
    const far = marker('far', 10, 10)
    const restaurants = [low, medium, high, far]
    const points = new Map([
      ['high', { x: 100, y: 100 }],
      ['medium', { x: 108, y: 100 }],
      ['low', { x: 145, y: 100 }],
      ['far', { x: 400, y: 400 }],
    ])
    const groupsAt = (span: number) => markerRegionalGroups(restaurants, points, markerRegionalGroupingDistance(span, 32))
      .map((group) => group.map((restaurant) => restaurant.id))
    expect(groupsAt(0.8)).toEqual([['far'], ['high'], ['medium'], ['low']])
    expect(groupsAt(1.2)).toEqual([['far'], ['high', 'medium'], ['low']])
    expect(groupsAt(2.4)).toEqual([['far'], ['high', 'medium', 'low']])
    expect(groupsAt(0.08)).toEqual([['far'], ['high'], ['medium'], ['low']])
    expect(points.get('high')).toEqual({ x: 100, y: 100 })
    expect(points.get('medium')).toEqual({ x: 108, y: 100 })
    expect(markerRegionalGroupingDistance(0.800001, 32)).toBeLessThan(0.01)
    expect(markerRegionalGroupingDistance(8, 32)).toBe(markerRegionalGroupingDistance(2.4, 32))
    expect(markerUsesRegionalGrouping(0.79999)).toBe(false)
    expect(markerUsesRegionalGrouping(0.8)).toBe(true)
    expect(markerUsesRegionalGrouping(Number.NaN)).toBe(false)
  })

  it('retains the higher-scored representative through panning and input reorder regardless of recommendation rank', () => {
    const first = { ...marker('recommendation-first', null, 0), recommendationRank: 1 }
    const second = { ...marker('recommendation-second', 10, 999), recommendationRank: 2 }
    const points = new Map([
      [first.id, { x: 100, y: 100 }],
      [second.id, { x: 110, y: 100 }],
    ])
    const original = markerRegionalGroups([second, first], points, 20)
    const translated = new Map([...points].map(([id, point]) => [id, { x: point.x + 500, y: point.y - 370 }]))
    expect(original).toEqual([[second, first]])
    expect(markerRegionalGroups([first, second], translated, 20)).toEqual(original)
  })

  it('keeps coincident Restaurant centers on their real shared location, including when selected', () => {
    const base = fixture.restaurants[0] as unknown as RestaurantSummary
    const restaurants = Array.from({ length: 90 }, (_, index) => ({
      ...base, id: `dense-${String(index).padStart(2, '0')}`,
      latitude: 30.27, longitude: 120.15,
      scoreOutOfTen: 10 - (index % 50) / 10, visitCount: 90 - index,
    }))
    const positions = (selectedRestaurant?: RestaurantSummary) => {
      const html = renderToStaticMarkup(createElement(MapView, {
        restaurants, selectedRestaurant, onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(),
        currentCoordinates: null,
      }))
      return [...html.matchAll(/class="private-image-marker-anchor tm-offline-map__anchor"[^>]*style="[^"]*left:([^;"]+);top:([^;"]+)/g)]
        .map((match) => [match[1], match[2]])
    }
    const initialPositions = positions()
    expect(initialPositions).toHaveLength(90)
    expect(new Set(initialPositions.map((point) => point.join(','))).size).toBe(1)
    expect(positions(restaurants[89])).toEqual(initialPositions)
  })

  it('makes exact-coordinate members accessible as a stack without inventing building identity', () => {
    const base = fixture.restaurants[0] as unknown as RestaurantSummary
    const first = { ...base, id: 'first', scoreOutOfTen: 9.5, latitude: 30.27, longitude: 120.15 }
    const second = { ...first, id: 'second', scoreOutOfTen: 8.0 }
    const nearby = { ...first, id: 'nearby', latitude: 30.270001 }
    expect(markerCoincidentGroups([second, nearby, first]).find((group) => group.includes(first))).toEqual([first, second])
    expect(markerIsCoincidentGroup([first, second])).toBe(true)
    expect(markerIsCoincidentGroup([first, nearby])).toBe(false)
    const html = renderToStaticMarkup(createElement(MapView, {
      restaurants: [first, second], onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
    }))
    expect(html.match(/此处有多家餐厅，轻点查看列表/g)).toHaveLength(2)
    expect(html).not.toContain('group-count')
    expect(html).not.toContain('is-city-group')
  })

  it('shows at most three real exact-coordinate images with the highest score at the fixed front', () => {
    const base = fixture.restaurants[0] as unknown as RestaurantSummary
    const members = fixture.restaurants.slice(0, 4).map((restaurant, index) => ({
      ...restaurant, id: `stack-${index}`, scoreOutOfTen: 9.8 - index,
      latitude: base.latitude, longitude: base.longitude, markerImageData: restaurant.merchantImageUrl,
    })) as unknown as RestaurantSummary[]
    const stack = markerCoincidentStackMembers([...members].reverse())
    expect(stack).toHaveLength(3)
    expect(stack[0]).toBe(members[0])
    expect(stack[1]).toBe(members[1])
    expect(stack[2]).toBe(members[2])
    expect(markerCoincidentStackMembers([members[0], { ...members[1], latitude: base.latitude + 0.001 }])).toEqual([])
    const html = renderToStaticMarkup(createElement(MapView, {
      restaurants: members, onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
    }))
    const backIDs = [...html.matchAll(/class="private-image-marker__stack-back(?: is-unvisited)?"[^>]*><span class="private-image-marker__visual" data-restaurant-id="([^"]+)"/g)].map((match) => match[1])
    expect(backIDs).toEqual(['stack-1', 'stack-2'])
    expect(html.match(/class="private-image-marker-anchor tm-offline-map__anchor" hidden=""/g)).toHaveLength(3)
    for (const member of stack) {
      expect(html).toContain(`data-restaurant-id="${member.id}"`)
      if (member.markerImageData) expect(html).toContain(`src="${member.markerImageData.replace(/&/g, '&amp;')}"`)
    }
    expect(html).not.toContain('group-count')
  })

  it('gives both pending scopes the larger shared shell on real front and back member visuals', () => {
    const base = fixture.restaurants[0] as unknown as RestaurantSummary
    for (const recommendationScope of [false, true]) {
      const members = [0, 1, 2].map((index) => ({
        ...base, id: `pending-${index}`, scoreOutOfTen: 9 - index,
        status: recommendationScope ? 'visited' : 'wantToGo',
      })) as RestaurantSummary[]
      const html = renderToStaticMarkup(createElement(MapView, {
        restaurants: members, selectedRestaurant: members[0], unvisitedMarkerStyle: recommendationScope,
        onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
      }))
      expect(html.match(/class="private-image-marker__stack-back is-unvisited"/g)).toHaveLength(2)
      expect(html).toContain('tm-offline-map__marker is-selected is-unvisited')
      expect(html).not.toContain('--marker-scale')
      expect(html).not.toContain('group-count')
    }
  })

  it('retains every distinct city coordinate without forming a proximity template or changing its position', () => {
    const base = fixture.restaurants[0] as unknown as RestaurantSummary
    const items = [0, 1, 2, 3].map((index) => ({
      ...base, id: `independent-${index}`, latitude: 30.27 + index * 0.000001,
      longitude: 120.15, scoreOutOfTen: 9.8 - index,
    }))
    const coordinates = items.map(({ latitude, longitude }) => [latitude, longitude])
    const groups = markerCoincidentGroups(items)
    expect(groups).toEqual(items.map((item) => [item]))
    expect(markerCoincidentGroups([...items].reverse())).toEqual(groups)
    expect(markerCoincidentStackMembers(items)).toEqual([])
    const html = renderToStaticMarkup(createElement(MapView, {
      restaurants: items, onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
    }))
    expect(html.match(/class="private-image-marker-anchor tm-offline-map__anchor"/g)).toHaveLength(4)
    expect(html).not.toContain('private-image-marker__stack-back')
    expect(html).not.toContain('此处有多家餐厅')
    expect(items.map(({ latitude, longitude }) => [latitude, longitude])).toEqual(coordinates)
    expect(markerUsesRegionalGrouping(0.08)).toBe(false)
  })

  it('opens only current real members and renders every member as an actionable row', () => {
    const items = fixture.restaurants.slice(0, 3) as unknown as RestaurantSummary[]
    const selected = resolveMapGroupRestaurants(items, [items[1].id.toUpperCase(), 'not-owned-or-not-visible', items[0].id, items[1].id])
    expect(selected).toEqual([items[1], items[0]].sort((left, right) => compareMarkerLayerPriority(right, left)))
    const html = renderToStaticMarkup(createElement(MapRestaurantGroupSheet, {
      items: selected, images: {}, scope: 'visited', onClose: vi.fn(), onOpen: vi.fn(),
    }))
    expect(html).toContain('role="dialog"')
    expect(html).toContain('此处的餐厅 · 2 家')
    expect(html.match(/aria-label="查看餐厅 /g)).toHaveLength(2)
    expect(html).toContain(items[0].name)
    expect(html).toContain(items[1].name)
    expect(html).not.toContain('not-owned-or-not-visible')
    expect(html).not.toContain('MY TASTE MAP')
  })

  it('diffs stable Restaurant IDs and reuses unchanged marker/image identities', () => {
    const first = fixture.restaurants[0] as unknown as RestaurantSummary
    const second = fixture.restaurants[1] as unknown as RestaurantSummary
    const removed = fixture.restaurants[2] as unknown as RestaurantSummary
    const changed = { ...second, visitCount: second.visitCount + 1 }
    const records = new Map([
      [first.id, { signature: restaurantMarkerSignature(first, null) }],
      [second.id, { signature: restaurantMarkerSignature(second, null) }],
      [removed.id, { signature: restaurantMarkerSignature(removed, null) }],
    ])
    const plan = restaurantMarkerReconciliationPlan(new Set(records.keys()), records, [first, changed], null)
    expect(plan.reused.map((value) => value.id)).toEqual([first.id])
    expect(plan.changed.map((value) => value.id)).toEqual([second.id])
    expect(plan.removed).toEqual([removed.id])
    expect(plan.added).toEqual([])
  })

  it('refreshes front and back category visuals when the member emoji or category changes', () => {
    const restaurant = fixture.restaurants[0] as unknown as RestaurantSummary
    const original = restaurantMarkerSignature(restaurant, null)
    expect(restaurantMarkerSignature({ ...restaurant, markerEmoji: '🍜' }, null)).not.toBe(original)
    expect(restaurantMarkerSignature({ ...restaurant, tags: ['新的真实分类'] }, null)).not.toBe(original)
  })

  it('rebuilds the same Restaurant when Recommendation switches it to the unvisited Web marker shell', () => {
    const restaurant = fixture.restaurants[0] as unknown as RestaurantSummary
    const personalSignature = restaurantMarkerSignature(restaurant, null)
    const recommendedSignature = restaurantMarkerSignature(restaurant, null, true)
    expect(recommendedSignature).not.toBe(personalSignature)

    const plan = restaurantMarkerReconciliationPlan(
      new Set([restaurant.id]),
      new Map([[restaurant.id, { signature: personalSignature }]]),
      [restaurant],
      null,
      true,
    )
    expect(plan.changed.map((value) => value.id)).toEqual([restaurant.id])
    expect(plan.reused).toEqual([])
  })

  it('keeps the paused chest absent from every formal main and back member', () => {
    const base = fixture.restaurants[0] as unknown as RestaurantSummary
    const items: RestaurantSummary[] = [
      { ...base, id: 'front-visited', status: 'visited', scoreOutOfTen: 9.8, latitude: 30.27, longitude: 120.15 },
      { ...base, id: 'back-wanted', status: 'wantToGo', scoreOutOfTen: null, latitude: 30.27, longitude: 120.15 },
    ]
    const html = renderToStaticMarkup(createElement(MapView, {
      restaurants: items, onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
    }))
    expect(html.match(/data-marker-shape="circle"/g)).toHaveLength(3)
    // The static renderer retains the lower member's hidden main node, plus
    // its visible decorative back member, just as before this shape override.
    expect(html).not.toContain('data-marker-shape="treasureChest"')
    expect(html).not.toContain('private-image-marker__chest-shell')
    expect(html.match(/class="private-image-marker-anchor tm-offline-map__anchor" hidden=""/g)).toHaveLength(1)
    expect(html).toContain('class="private-image-marker__stack-back is-unvisited" data-marker-shape="circle"')
    expect(html).not.toContain('group-count')

    const recommended = renderToStaticMarkup(createElement(MapView, {
      restaurants: items, unvisitedMarkerStyle: true,
      onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
    }))
    expect(recommended.match(/data-marker-shape="circle"/g)).toHaveLength(3)
    expect(recommended).not.toContain('data-marker-shape="treasureChest"')
    expect(recommended).not.toContain('private-image-marker__chest-shell')
  })

  it('retains the candidate renderer behind an isolated test-only shape override', () => {
    const original = markerShape.mapMarkerShape
    const override = vi.spyOn(markerShape, 'mapMarkerShape').mockImplementation((status, scope) => original(status, scope, true))
    try {
      const base = fixture.restaurants[0] as unknown as RestaurantSummary
      const html = renderToStaticMarkup(createElement(MapView, {
        restaurants: [base, { ...base, id: 'candidate-back', status: 'wantToGo', scoreOutOfTen: null }],
        unvisitedMarkerStyle: true,
        onSelect: vi.fn(), onSelectGroup: vi.fn(), onClearSelection: vi.fn(), currentCoordinates: null,
      }))
      expect(html.match(/data-marker-shape="treasureChest"/g)).toHaveLength(3)
      expect(html.match(/class="private-image-marker__chest-shell"/g)).toHaveLength(3)
    } finally {
      override.mockRestore()
    }
  })
})
