import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import { listCoordinate, listRating, mergeListPage, validatedListShareURL } from './restaurantListProjection'
import type { TasteMapHybridListDTO, TasteMapProfileDashboardViewModel } from './TasteMapPlatform'

const mocks = vi.hoisted(() => ({ get: vi.fn(), items: vi.fn(), api: vi.fn() }))
vi.mock('../db/appDb', () => ({ db: {
  restaurantLists: { get: mocks.get },
  restaurantListItems: { where: () => ({ equals: () => ({ filter: () => ({ toArray: mocks.items }) }) }) },
} }))
vi.mock('../services/restaurantListApi', () => ({ requestRestaurantListAPI: mocks.api }))

function profile(owner = 'owner'): TasteMapProfileDashboardViewModel {
  return { user: { id: owner, nickname: '我' }, restaurants: [], visits: [], restaurantImages: {}, followingCount: 0, followerCount: 0 } as unknown as TasteMapProfileDashboardViewModel
}
function page(nextCursor: string | null = null, ids = ['public-r']) {
  return {
    apiVersion: 1, list: { id: 'public-list', title: '公开食单', description: '说明', visibility: 'public', isRanked: true,
      restaurantCount: 2, updatedAt: 'revision-1', owner: { userId: 'tm_other', displayName: '公开作者' } },
    items: ids.map((id, index) => ({ id: `item-${id}`, position: index, note: '', restaurant: {
      restaurantId: id, globalKey: `apple_maps:${id}`, name: id, address: '公开地点', city: '杭州', latitude: 30.25, longitude: 120.15,
      // An unexpected author-private field must never enter the DTO.
      rating: 10,
    } })), nextCursor, generatedAt: 'now',
  }
}
function ownList(visibility = 'public') {
  return { id: 'own-list', userId: 'owner', title: '食单', description: '', visibility, isRanked: false, updatedAt: 'revision-1', deletedAt: null }
}

beforeEach(() => { vi.clearAllMocks(); mocks.get.mockResolvedValue(undefined); mocks.items.mockResolvedValue([]) })
afterEach(() => vi.restoreAllMocks())

describe('List truth and privacy projection', () => {
  it('retains original coordinates, with absent/invalid values staying null', () => {
    expect(listCoordinate(30.12345678, 120.87654321)).toEqual({ latitude: 30.12345678, longitude: 120.87654321 })
    for (const value of [undefined, null, NaN, Infinity, 91]) expect(listCoordinate(value, 120)).toBeNull()
    expect(listCoordinate(0, 0)).toEqual({ latitude: 0, longitude: 0 })
  })
  it('allows only genuine positive ten-point scores and positive samples, preserving explicit origin', () => {
    expect(listRating(8.7, 'public', 12)).toEqual({ valueOutOfTen: 8.7, source: 'public', sampleCount: 12 })
    expect(listRating(9, 'viewer', 2)?.source).toBe('viewer')
    for (const value of [null, NaN, 0, 11]) expect(listRating(value, 'public', 1)).toBeNull()
    expect(listRating(9, 'public', 0)).toBeNull()
  })
  it('projects the current viewer rating, never an unexpected public-author private rating', async () => {
    mocks.get.mockResolvedValue(ownList())
    mocks.items.mockResolvedValue([{ listId: 'own-list', restaurantId: 'owned', position: 0, note: '' }])
    const source = profile()
    source.restaurants = [{ id: 'owned', userId: 'owner', name: '自有餐厅', latitude: 30.123456, longitude: 120.654321,
      scoreOutOfTen: 9, visits: [{ rating: 4.5, photos: [], photoIds: [], dishes: [], visitedAt: '2026-08-01T12:00:00Z', deletedAt: null }], tags: [] }] as unknown as typeof source.restaurants
    const adapter = new TasteMapBrowserAdapter({ profile: async () => source })
    const own = await adapter.lists.get({ id: 'own-list' })
    expect(own.list.restaurants[0].rating).toEqual({ valueOutOfTen: 9, source: 'viewer', sampleCount: 1 })
    expect(own.list.restaurants[0].coordinate).toEqual({ latitude: 30.123456, longitude: 120.654321 })
    mocks.get.mockResolvedValue(undefined); mocks.api.mockResolvedValue(page())
    expect((await adapter.lists.get({ id: 'public-list' })).list.restaurants[0].rating).toBeNull()
  })
  it('retains public membership and supplies complete pagination without silently truncating', async () => {
    mocks.api.mockResolvedValueOnce(page('server-page-2', ['a'])).mockResolvedValueOnce(page(null, ['b']))
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    const first = await adapter.lists.get({ id: 'public-list' })
    expect(first.nextCursor).toBeTruthy(); expect(first.nextCursor).not.toBe('server-page-2')
    const second = await adapter.lists.get({ id: 'public-list', cursor: first.nextCursor })
    expect(mergeListPage(first.list, second).restaurants.map(item => item.id)).toEqual(['a', 'b'])
    expect(second.nextCursor).toBeNull()
    expect(mocks.api.mock.calls[1][0]).toContain('cursor=server-page-2')
  })
  it('rejects an old cursor after refresh and a forged cursor without contacting the API', async () => {
    mocks.api.mockResolvedValue(page('next'))
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    const first = await adapter.lists.get({ id: 'public-list' })
    await adapter.lists.get({ id: 'public-list' })
    await expect(adapter.lists.get({ id: 'public-list', cursor: first.nextCursor })).rejects.toMatchObject({ code: 'list_cursor_expired' })
    await expect(adapter.lists.get({ id: 'public-list', cursor: 'forged' })).rejects.toMatchObject({ code: 'list_cursor_expired' })
    expect(mocks.api).toHaveBeenCalledTimes(2)
  })
  it('drops late responses after an owner transition, including A→B→A', async () => {
    let resolve!: (value: unknown) => void
    mocks.api.mockImplementation(() => new Promise(value => { resolve = value }))
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    adapter.acceptProfileSnapshot(profile())
    const pending = adapter.lists.get({ id: 'public-list' })
    await vi.waitFor(() => expect(mocks.api).toHaveBeenCalledTimes(1))
    adapter.acceptProfileSnapshot(profile('tm_b')); adapter.acceptProfileSnapshot(profile())
    resolve(page())
    await expect(pending).rejects.toMatchObject({ code: 'list_request_superseded' })
  })
  it('rejects page-version mismatch instead of combining different List revisions', () => {
    const list = { id: 'a', updatedAt: 'v1', restaurants: [] } as unknown as TasteMapHybridListDTO
    expect(() => mergeListPage(list, { list: { ...list, updatedAt: 'v2' }, nextCursor: null, generatedAt: '' })).toThrow('食单已更新')
  })
  it('does not resurrect a local tombstone from an older server copy', async () => {
    mocks.get.mockResolvedValue({ ...ownList(), deletedAt: 'deleted-now' })
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    await expect(adapter.lists.get({ id: 'own-list' })).rejects.toMatchObject({ code: 'list_unavailable' })
    expect(mocks.api).not.toHaveBeenCalled()
  })
  it('uses additive typed native methods with no client-selected owner in either payload', async () => {
    const invoke = vi.fn(async ({ request }: { request: { method: string; requestId: string; payload: unknown } }) => ({ version: 1, requestId: request.requestId,
      result: request.method === 'runtime.info' ? { bridgeVersion: 1 } : request.method === 'lists.get'
        ? { list: {}, nextCursor: null, generatedAt: '' } : { url: `https://example.com/share/${'a'.repeat(32)}` } }))
    const target = { Capacitor: { Plugins: { TasteMapNative: { invoke } } } } as unknown as ConstructorParameters<typeof TasteMapNativeAdapter>[0]
    const adapter = new TasteMapNativeAdapter(target)
    await adapter.lists.get({ id: 'public-list', cursor: 'opaque' })
    await adapter.lists.createShareLink('own-list')
    expect(invoke.mock.calls.map(([value]) => [value.request.method, value.request.payload])).toEqual([
      ['runtime.info', {}], ['lists.get', { id: 'public-list', cursor: 'opaque' }], ['lists.createShareLink', { id: 'own-list' }],
    ])
  })
})

describe('Permission-safe List links', () => {
  it('does not call share API for private/friends or another owner List', async () => {
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    for (const visibility of ['private', 'friends']) {
      mocks.get.mockResolvedValue(ownList(visibility))
      await expect(adapter.lists.createShareLink('own-list')).rejects.toMatchObject({ code: 'list_share_not_public' })
    }
    mocks.get.mockResolvedValue({ ...ownList(), userId: 'tm_other' })
    await expect(adapter.lists.createShareLink('own-list')).rejects.toMatchObject({ code: 'list_share_not_owned' })
    expect(mocks.api).not.toHaveBeenCalled()
  })
  it('uses an authenticated entity request and the real opaque URL, never a title-only substitute', async () => {
    mocks.get.mockResolvedValue(ownList())
    const url = `https://example.com/share/${'a'.repeat(32)}`
    mocks.api.mockResolvedValue({ apiVersion: 1, entityType: 'list', url })
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    expect(await adapter.lists.createShareLink('own-list')).toEqual({ url })
    expect(mocks.api).toHaveBeenCalledWith('/api/v1/public-shares', { entityType: 'list', entityId: 'own-list' })
  })
  it('fails closed on a local visibility downgrade while sharing awaits', async () => {
    mocks.get.mockResolvedValueOnce(ownList()).mockResolvedValueOnce(ownList('private'))
    mocks.api.mockResolvedValue({ apiVersion: 1, entityType: 'list', url: `https://example.com/share/${'a'.repeat(32)}` })
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile() })
    await expect(adapter.lists.createShareLink('own-list')).rejects.toMatchObject({ code: 'list_share_superseded' })
  })
  it('rejects non-HTTPS, credentials, query/hash and synthetic ID links', () => {
    for (const url of ['http://example.com/share/' + 'a'.repeat(32), 'https://secret@example.com/share/' + 'a'.repeat(32),
      'https://example.com/#list=own-list', 'https://example.com/share/own-list', 'https://example.com/share/' + 'a'.repeat(32) + '?owner=a']) {
      expect(() => validatedListShareURL(url)).toThrow()
    }
  })
})
