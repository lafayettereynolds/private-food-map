import { beforeEach, describe, expect, it, vi } from 'vitest'

const harness = vi.hoisted(() => {
  type Row = Record<string, unknown> & { id: string }
  const stores: Record<string, Map<string, Row>> = {}
  let failQueue = false
  const table = (name: string) => {
    stores[name] = new Map()
    const put = async (row: Row) => {
      if (name === 'syncQueue' && failQueue) throw new Error('queue failed')
      stores[name].set(row.id, structuredClone(row))
    }
    const query = (key: string, values: unknown[]) => ({
      toArray: async () => [...stores[name].values()].filter((row) => values.includes(row[key])).map((row) => structuredClone(row)),
      modify: async (patch: object) => {
        for (const row of stores[name].values()) if (values.includes(row[key])) await put({ ...row, ...patch })
      },
    })
    return {
      get: async (id: string) => structuredClone(stores[name].get(id)), put,
      update: async (id: string, patch: object) => { const row = stores[name].get(id); if (row) await put({ ...row, ...patch }) },
      bulkPut: async (rows: Row[]) => { for (const row of rows) await put(row) },
      where: (key: string) => ({ equals: (value: unknown) => query(key, [value]), anyOf: (values: unknown[]) => query(key, values) }),
    }
  }
  const db = {
    restaurants: table('restaurants'), visits: table('visits'), photos: table('photos'), syncQueue: table('syncQueue'),
    transaction: async (...args: unknown[]) => {
      const snapshot = structuredClone(stores)
      try { await (args[args.length - 1] as () => Promise<void>)() }
      catch (error) { for (const key of Object.keys(stores)) stores[key] = snapshot[key]; throw error }
    },
  }
  return { db, stores, sync: vi.fn(), setQueueFailure: (value: boolean) => { failQueue = value } }
})
vi.mock('./appDb', () => ({ db: harness.db }))
vi.mock('./social', () => ({ CURRENT_USER_ID: 'owner', createSharedMealInvitations: vi.fn() }))
vi.mock('../services/syncEvents', () => ({ requestCloudSync: harness.sync }))
import { deleteRestaurant, deleteVisit } from './restaurants'

const visit = (id: string, extra: object = {}) => ({ id, restaurantId: 'r', userId: 'owner', deletedAt: null, rating: 4, photoIds: [], dishes: [], ...extra })
beforeEach(() => {
  for (const store of Object.values(harness.stores)) store.clear()
  harness.setQueueFailure(false); harness.sync.mockClear()
  harness.stores.restaurants.set('r', { id: 'r', userId: 'owner', deletedAt: null })
  harness.stores.visits.set('v', visit('v', { photoIds: ['p'] }))
  harness.stores.photos.set('p', { id: 'p', restaurantId: 'r', userId: 'owner', localState: 'ready' })
})

describe('owner visit deletion transaction', () => {
  it('tombstones the restaurant, all owner visits and photos when the final active visit is deleted', async () => {
    harness.stores.visits.set('old', visit('old', { deletedAt: 'yesterday' }))
    const result = await deleteVisit('v')
    expect(result.deletedRestaurantID).toBe('r')
    expect(harness.stores.restaurants.get('r')?.deletedAt).toBe(result.updatedAt)
    expect(harness.stores.visits.get('old')?.deletedAt).toBe(result.updatedAt)
    expect(harness.stores.photos.get('p')?.localState).toBe('delete-pending')
    expect([...harness.stores.syncQueue.values()].map((row) => row.entityId).sort()).toEqual(['old', 'r', 'v'])
    expect(harness.sync).toHaveBeenCalledOnce()
  })
  it('keeps a restaurant with another active owner visit and recalculates its rating', async () => {
    harness.stores.visits.set('remaining', visit('remaining', { rating: 5 }))
    expect((await deleteVisit('v')).deletedRestaurantID).toBeUndefined()
    expect(harness.stores.restaurants.get('r')).toMatchObject({ deletedAt: null, preferenceLevel: 'favorite' })
    expect(harness.stores.visits.get('remaining')?.deletedAt).toBeNull()
  })
  it('does not count or cascade other-user rows, or sweep unrelated old zero-visit restaurants', async () => {
    harness.stores.visits.set('other', visit('other', { userId: 'other' }))
    harness.stores.photos.set('other-photo', { id: 'other-photo', restaurantId: 'r', userId: 'other', localState: 'ready' })
    harness.stores.restaurants.set('legacy-zero', { id: 'legacy-zero', userId: 'owner', deletedAt: null })
    expect((await deleteVisit('v')).deletedRestaurantID).toBe('r')
    expect(harness.stores.visits.get('other')?.deletedAt).toBeNull()
    expect(harness.stores.photos.get('other-photo')?.localState).toBe('ready')
    expect(harness.stores.restaurants.get('legacy-zero')?.deletedAt).toBeNull()
  })
  it('rolls back every local change and never starts sync when queuing fails', async () => {
    harness.setQueueFailure(true)
    await expect(deleteVisit('v')).rejects.toThrow('queue failed')
    expect(harness.stores.restaurants.get('r')?.deletedAt).toBeNull()
    expect(harness.stores.visits.get('v')?.deletedAt).toBeNull()
    expect(harness.stores.photos.get('p')?.localState).toBe('ready')
    expect(harness.sync).not.toHaveBeenCalled()
  })
  it('rejects deletion of another owner restaurant or visit before mutation', async () => {
    harness.stores.visits.set('v', visit('v', { userId: 'other' }))
    await expect(deleteVisit('v')).rejects.toThrow('只能删除自己的到访')
    harness.stores.restaurants.set('r', { id: 'r', userId: 'other', deletedAt: null })
    await expect(deleteRestaurant('r')).rejects.toThrow('只能删除自己的餐厅')
    expect(harness.sync).not.toHaveBeenCalled()
  })
})
