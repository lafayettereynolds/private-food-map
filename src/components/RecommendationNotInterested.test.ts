import { describe, expect, it, vi } from 'vitest'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'
import { createPreferenceStore, RecommendationNotInterested } from './RecommendationNotInterested'
import { excludeRecommendationIDs, expandRecommendationAliases, saveBrowserRecommendationExclusion } from '../services/recommendationExclusions'

const response = (excludedIDs: string[] = [], ownerID = 'owner') => ({ ownerID, excludedIDs })
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r }); return { promise, resolve } }
function host(preference: (id?: string) => Promise<ReturnType<typeof response>>) {
  const remove = vi.fn(); let callback: (event: { name: string }) => void = () => undefined
  const subscribe = vi.fn(async (listener) => { callback = listener; return { remove } })
  const platform = { recommendations: { preference }, events: { subscribe } } as unknown as TasteMapPlatform
  return { platform, subscribe, remove, emit: (name: string) => callback({ name }) }
}
describe('Not Interested persisted recommendation projection', () => {
  it('uses one bare X without visible wording for feed and image-overlay controls', () => {
    for (const overlay of [false, true]) {
      const html = renderToStaticMarkup(createElement(RecommendationNotInterested, {
        platform: host(async () => response()).platform, restaurantID: 'restaurant', overlay,
      }))
      expect(html).toContain('aria-label="不感兴趣"')
      expect(html).toContain('lucide-x')
      expect(html.match(/<svg\b/g)).toHaveLength(1)
      expect(html).not.toContain('circle-minus')
      const button = html.match(/<button\b[^>]*>(.*?)<\/button>/s)?.[1] ?? ''
      expect(button).not.toContain('<span')
      expect(button).not.toContain('不感兴趣')
    }
  })
  it('coalesces reads across all simultaneously mounted cards', async () => {
    const read = deferred<ReturnType<typeof response>>(); const preference = vi.fn(() => read.promise)
    const h = host(preference); const store = createPreferenceStore(h.platform)
    const a = store.connect(); const b = store.connect()
    expect(h.subscribe).toHaveBeenCalledTimes(1); expect(preference).toHaveBeenCalledTimes(1)
    expect(store.snapshot().ready).toBe(false)
    read.resolve(response(['a'])); await store.refresh()
    expect(store.snapshot().excludedIDs).toEqual(['a'])
    a(); expect(h.remove).not.toHaveBeenCalled(); b(); await Promise.resolve(); expect(h.remove).toHaveBeenCalledTimes(1)
  })
  it('does not let an old read overwrite a successful dismissal', async () => {
    const late = deferred<ReturnType<typeof response>>()
    const preference = vi.fn().mockResolvedValueOnce(response()).mockReturnValueOnce(late.promise).mockResolvedValueOnce(response(['a']))
    const store = createPreferenceStore(host(preference).platform)
    await store.refresh(); const read = store.refresh(); await store.dismiss('a')
    late.resolve(response()); await read
    expect(store.snapshot().excludedIDs).toEqual(['a'])
  })
  it('clears exclusions immediately on owner change and ignores the old reply', async () => {
    const old = deferred<ReturnType<typeof response>>()
    const preference = vi.fn().mockReturnValueOnce(old.promise).mockResolvedValueOnce(response(['b'], 'next'))
    const h = host(preference); const store = createPreferenceStore(h.platform); const disconnect = store.connect()
    h.emit('auth.changed'); await store.refresh(); old.resolve(response(['a'])); await Promise.resolve()
    expect(store.snapshot().ownerID).toBe('next'); expect(store.snapshot().excludedIDs).toEqual(['b']); disconnect()
  })
  it('read failure fails closed and has a working retry', async () => {
    const preference = vi.fn().mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce(response(['a']))
    const store = createPreferenceStore(host(preference).platform)
    await store.refresh(); expect(store.snapshot().ready).toBe(false); expect(store.snapshot().error).toBeTruthy()
    await store.refresh(); expect(store.snapshot().ready).toBe(true); expect(store.snapshot().excludedIDs).toEqual(['a'])
  })
  it('rejects a stale confirmation owner before any preference write', async () => {
    const preference = vi.fn().mockResolvedValueOnce(response([], 'owner')).mockResolvedValueOnce(response([], 'next'))
    const h = host(preference); const store = createPreferenceStore(h.platform); const disconnect = store.connect()
    await store.refresh()
    h.emit('auth.changed'); await store.refresh()
    await expect(store.dismiss('restaurant', 'owner')).rejects.toThrow('账户已切换')
    expect(preference.mock.calls.every(args => args.length === 0)).toBe(true)
    expect(store.snapshot()).toMatchObject({ ownerID: 'next', excludedIDs: [] })
    disconnect()
  })
  it('failed writes do not pretend the restaurant was excluded and can retry', async () => {
    const preference = vi.fn().mockResolvedValueOnce(response()).mockRejectedValueOnce(new Error('disk')).mockResolvedValueOnce(response(['a']))
    const store = createPreferenceStore(host(preference).platform); await store.refresh()
    await expect(store.dismiss('a')).rejects.toThrow('disk'); expect(store.snapshot().excludedIDs).toEqual([])
    await store.dismiss('a'); expect(store.snapshot().excludedIDs).toEqual(['a'])
  })
  it('persists owner-isolated IDs without writing or deleting restaurant history', () => {
    const values = new Map<string, string>()
    const storage = { getItem: (k: string) => values.get(k) ?? null, setItem: (k: string, v: string) => { values.set(k, v) } }
    expect(saveBrowserRecommendationExclusion(storage, 'owner', [' A ', 'a'])).toEqual(['a'])
    expect(saveBrowserRecommendationExclusion(storage, 'owner')).toEqual(['a'])
    expect(saveBrowserRecommendationExclusion(storage, 'next')).toEqual([])
    expect(() => saveBrowserRecommendationExclusion(storage, '')).toThrow()
  })
  it('rejects corrupted storage and write failure rather than reporting success', () => {
    expect(() => saveBrowserRecommendationExclusion({ getItem: () => '{}', setItem: vi.fn() }, 'owner')).toThrow()
    expect(() => saveBrowserRecommendationExclusion({ getItem: () => null, setItem: () => { throw new Error('quota') } }, 'owner', ['a'])).toThrow('quota')
  })
  it('expands transitive stable aliases but preserves other branches', () => {
    const ids = expandRecommendationAliases(['LOCAL'], [['local', 'osm:1'], ['global', 'osm:1'], ['other', 'osm:2']])
    const items = ['local', 'GLOBAL', 'other'].map(id => ({ restaurant: { id } }))
    expect(excludeRecommendationIDs(items, ids).map(item => item.restaurant.id)).toEqual(['other'])
    expect(items).toHaveLength(3)
  })
})
