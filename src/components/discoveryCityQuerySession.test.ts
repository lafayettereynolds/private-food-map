import { describe, expect, it, vi } from 'vitest'
import { createDiscoveryCityQuerySession, discoveryCityQueryKey } from './discoveryCityQuerySession'

const query = { mode: 'latest', city: '成都', windowDays: 7 as const }
const page = (city = '成都', extra = {}) => ({ mode: 'latest', requestedCity: city, windowDays: 7 as const,
  snapshotID: `snapshot-${city}`, nextCursor: 'next', pagination: 'more' as 'more' | 'complete' | 'unknown', rows: [city], ...extra })
const deferred = <T,>() => { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done }); return { resolve, promise } }
const tick = async () => { await Promise.resolve(); await Promise.resolve() }

describe('server query identity', () => {
  it('binds filtering, sorting and session preferences rather than only city', () => {
    const base = discoveryCityQueryKey(query)
    for (const extra of [{ filters: { minimumPublicScoreOutOfTen: 9 } }, { sort: 'distance' }, { preferences: { exploration: 'familiar' } }]) {
      expect(discoveryCityQueryKey({ ...query, ...extra })).not.toBe(base)
    }
    expect(discoveryCityQueryKey({ ...query, cursor: 'another-page', snapshotID: 'snapshot' })).toBe(base)
  })
})

describe('session-only Discovery city query', () => {
  it.each(['following', 'for_you', 'similar_taste', 'latest', 'trending'])('queries arbitrary cities for %s rather than filtering a loaded snapshot', async (mode) => {
    const load = vi.fn(async () => page('成都', { mode }))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    await session.select({ ...query, mode })
    expect(load).toHaveBeenCalledWith({ ...query, mode, forceRefresh: false })
    expect(session.snapshot().page?.rows).toEqual(['成都'])
  })
  it('uses only the accepted paired cursor and snapshot; results are already accumulated by the producer', async () => {
    const load = vi.fn<(request: typeof query) => Promise<ReturnType<typeof page>>>().mockResolvedValueOnce(page()).mockResolvedValueOnce(page('成都', { rows: ['成都', '更多'], nextCursor: null, pagination: 'complete' }))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    await session.select(query); await session.more()
    expect(load.mock.calls[1][0]).toEqual({ ...query, cursor: 'next', snapshotID: 'snapshot-成都' })
    expect(session.snapshot().page?.rows).toEqual(['成都', '更多'])
    await session.more(); expect(load).toHaveBeenCalledTimes(2)
  })
  it('clears the old city immediately and ignores its late reply', async () => {
    const slow = deferred<ReturnType<typeof page>>()
    const load = vi.fn<(request: typeof query) => Promise<ReturnType<typeof page>>>().mockReturnValueOnce(slow.promise).mockResolvedValueOnce(page('上海'))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    const old = session.select(query); await tick()
    const latest = session.select({ ...query, city: '上海' })
    expect(session.snapshot().page).toBeNull()
    await latest; slow.resolve(page()); await old
    expect(session.snapshot().page?.requestedCity).toBe('上海')
  })
  it('invalidates a pending append on refresh and retains no old page on a failed replacement query', async () => {
    const slow = deferred<ReturnType<typeof page>>()
    const load = vi.fn<(request: typeof query) => Promise<ReturnType<typeof page>>>().mockResolvedValueOnce(page()).mockReturnValueOnce(slow.promise).mockRejectedValueOnce(new Error('offline'))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    await session.select(query); const append = session.more(); await tick(); await session.retry()
    slow.resolve(page('成都', { rows: ['must-not-return'] })); await append
    expect(session.snapshot().page).toBeNull()
    expect(session.snapshot().error).toBe('offline')
    expect(load.mock.calls[2][0]).toEqual({ ...query, forceRefresh: true })
  })
  it('preserves only the same owner/query page after append failure', async () => {
    const load = vi.fn<(request: typeof query) => Promise<ReturnType<typeof page>>>().mockResolvedValueOnce(page()).mockRejectedValueOnce(new Error('retry'))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    await session.select(query); await session.more()
    expect(session.snapshot().page?.rows).toEqual(['成都'])
    expect(session.snapshot().error).toBe('retry')
  })
  it('rejects changed owners after async fetch and clears accepted data on invalidation', async () => {
    let owner = 'owner-a'
    const slow = deferred<ReturnType<typeof page>>()
    const session = createDiscoveryCityQuerySession({ load: () => slow.promise, owner: async () => owner, publish: () => {} })
    const loading = session.select(query); await tick(); owner = 'owner-b'; slow.resolve(page()); await loading
    expect(session.snapshot().page).toBeNull()
    expect(session.snapshot().error).toContain('账户已变化')
    session.invalidate(); expect(session.snapshot().key).toBeNull()
  })
  it('rejects cross-city/mode responses and never calls the server while signed out', async () => {
    const load = vi.fn(async () => page('杭州'))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    await session.select(query); expect(session.snapshot().page).toBeNull(); expect(session.snapshot().error).toContain('不一致')
    const denied = createDiscoveryCityQuerySession({ load, owner: async () => null, publish: () => {} })
    await denied.select(query); expect(load).toHaveBeenCalledTimes(1)
  })
  it('reset cancels pending requests without inventing an all-city response', async () => {
    const slow = deferred<ReturnType<typeof page>>()
    const session = createDiscoveryCityQuerySession({ load: () => slow.promise, owner: async () => 'owner', publish: () => {} })
    const loading = session.select(query); await tick(); await session.select(null); slow.resolve(page()); await loading
    expect(session.snapshot()).toEqual({ key: null, page: null, loading: false, appending: false, error: null })
  })
  it.each([{ mode: 'following' }, { windowDays: 30 }])('rejects a response for a different scope %j', async (scope) => {
    const session = createDiscoveryCityQuerySession({ load: async () => page('成都', scope), owner: async () => 'owner', publish: () => {} })
    await session.select(query)
    expect(session.snapshot().page).toBeNull()
    expect(session.snapshot().error).toContain('不一致')
  })
  it('accepts optional 市 aliases without trimming actual city-name characters', async () => {
    const session = createDiscoveryCityQuerySession({ load: async () => page('温州市'), owner: async () => 'owner', publish: () => {} })
    await session.select({ ...query, city: '温州' })
    expect(session.snapshot().page?.requestedCity).toBe('温州市')
    await session.select({ ...query, city: '温' })
    expect(session.snapshot().page).toBeNull()
  })
  it('rejects cross-snapshot append rather than mixing two result sets', async () => {
    const load = vi.fn<(request: typeof query) => Promise<ReturnType<typeof page>>>().mockResolvedValueOnce(page()).mockResolvedValueOnce(page('成都', { snapshotID: 'new-snapshot', rows: ['foreign'] }))
    const session = createDiscoveryCityQuerySession({ load, owner: async () => 'owner', publish: () => {} })
    await session.select(query); await session.more()
    expect(session.snapshot().page?.rows).toEqual(['成都'])
    expect(session.snapshot().error).toContain('已更新')
  })
  it('clears the previous owner before attempting their cursor under a new account', async () => {
    let owner = 'owner-a'
    const load = vi.fn(async () => page())
    const session = createDiscoveryCityQuerySession({ load, owner: async () => owner, publish: () => {} })
    await session.select(query); owner = 'owner-b'; await session.more()
    expect(load).toHaveBeenCalledTimes(1)
    expect(session.snapshot().page).toBeNull()
    expect(session.snapshot().error).toContain('账户已变化')
  })
})
