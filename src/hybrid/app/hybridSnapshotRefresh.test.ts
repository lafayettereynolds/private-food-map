import { describe, expect, it, vi } from 'vitest'
import type { TasteMapPlatform } from '../../platform/TasteMapPlatform'
import { refreshHybridSnapshots } from './hybridSnapshotRefresh'

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: Error) => void
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

function setup() {
  const profile = deferred<Awaited<ReturnType<TasteMapPlatform['profile']['getCurrent']>>>()
  const content = deferred<Awaited<ReturnType<TasteMapPlatform['content']['snapshot']>>>()
  const platform = { profile: { getCurrent: () => profile.promise }, content: { snapshot: () => content.promise } } as TasteMapPlatform
  const callbacks = { isCurrent: vi.fn(() => true), onProfile: vi.fn(), onContent: vi.fn() }
  return { profile, content, platform, callbacks }
}

describe('independent mounted Hybrid snapshot refresh', () => {
  it('publishes owner Visits and spend before pending Discovery content completes', async () => {
    const { profile, content, platform, callbacks } = setup()
    const refresh = refreshHybridSnapshots(platform, callbacks)
    const owner = { visits: [{ id: 'new-visit', myActualSpend: 50 }] } as never
    profile.resolve(owner)
    await vi.waitFor(() => expect(callbacks.onProfile).toHaveBeenCalledWith(owner))
    expect(callbacks.onContent).not.toHaveBeenCalled()
    content.resolve({ generatedAt: 'new-content' } as never)
    expect(await refresh).toEqual({ failed: false, contentFailed: false, message: null })
  })

  it('keeps the successful owner snapshot when independent content fails', async () => {
    const { profile, content, platform, callbacks } = setup()
    const refresh = refreshHybridSnapshots(platform, callbacks)
    profile.resolve({ visits: [{ id: 'saved' }] } as never)
    content.reject(new Error('offline'))
    expect(await refresh).toEqual({ failed: true, contentFailed: true, message: null })
    expect(callbacks.onProfile).toHaveBeenCalledOnce()
    expect(callbacks.onContent).not.toHaveBeenCalled()
  })

  it('still publishes content when owner data fails', async () => {
    const { profile, content, platform, callbacks } = setup()
    const refresh = refreshHybridSnapshots(platform, callbacks)
    profile.reject(new Error('local read failed'))
    content.resolve({ lists: [{ id: 'current-list' }] } as never)
    expect(await refresh).toEqual({ failed: true, contentFailed: false, message: null })
    expect(callbacks.onProfile).not.toHaveBeenCalled()
    expect(callbacks.onContent).toHaveBeenCalledOnce()
  })

  it('discards late data after a newer refresh, account change or unmount', async () => {
    const { profile, content, platform, callbacks } = setup()
    const refresh = refreshHybridSnapshots(platform, callbacks)
    callbacks.isCurrent.mockReturnValue(false)
    profile.resolve({ user: { id: 'previous-owner' } } as never)
    content.resolve({ lists: [{ id: 'previous-owner-list' }] } as never)
    await refresh
    expect(callbacks.onProfile).not.toHaveBeenCalled()
    expect(callbacks.onContent).not.toHaveBeenCalled()
  })

  it('bounds stalled content, preserves the published owner data and ignores late completion', async () => {
    vi.useFakeTimers()
    try {
      const { profile, content, platform, callbacks } = setup()
      const refresh = refreshHybridSnapshots(platform, callbacks, 100)
      profile.resolve({ visits: [{ id: 'saved' }] } as never)
      await vi.advanceTimersByTimeAsync(1)
      expect(callbacks.onProfile).toHaveBeenCalledOnce()
      await vi.advanceTimersByTimeAsync(100)
      expect(await refresh).toEqual({ failed: true, contentFailed: true, message: null })
      expect(vi.getTimerCount()).toBe(0)
      content.resolve({ generatedAt: 'too-late' } as never)
      await vi.advanceTimersByTimeAsync(1)
      expect(callbacks.onContent).not.toHaveBeenCalled()
    } finally { vi.useRealTimers() }
  })

  it('publishes a cached partial snapshot but does not treat its structured issue as refresh success', async () => {
    const { profile, content, platform, callbacks } = setup()
    const snapshot = { discovery: { refreshStatus: { trending: {
      state: 'cached', city: '杭州', windowDays: 7, sourceGeneratedAt: 'old', attemptedAt: 'now',
      issue: { code: 'DISCOVERY_AGGREGATE_CAPACITY', message: '完整统计容量不足。', recoverable: true },
    } } } } as never
    const refresh = refreshHybridSnapshots(platform, callbacks)
    profile.resolve({ visits: [{ id: 'saved' }] } as never)
    content.resolve(snapshot)
    expect(await refresh).toEqual({ failed: true, contentFailed: false, message: '趋势：完整统计容量不足。正在显示上次缓存。' })
    expect(callbacks.onContent).toHaveBeenCalledWith(snapshot)
    expect(callbacks.onProfile).toHaveBeenCalledOnce()
  })

  it('passes an explicit retry and leaves permission restrictions to the corresponding mode', async () => {
    const { profile, content, platform, callbacks } = setup()
    const snapshot = vi.spyOn(platform.content, 'snapshot')
    const refresh = refreshHybridSnapshots(platform, callbacks, 100, { forceRefresh: true })
    profile.resolve({ visits: [] } as never)
    content.resolve({ discovery: { refreshStatus: { similar_taste: {
      state: 'restricted', issue: { code: 'discovery_access_required', message: '需要权限', recoverable: false },
    } } } } as never)
    expect(await refresh).toEqual({ failed: false, contentFailed: false, message: null })
    expect(snapshot).toHaveBeenCalledWith({ forceRefresh: true })
  })
})
