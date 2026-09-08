import { afterEach, describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { TasteMapProfileDashboardViewModel } from './TasteMapPlatform'
import type { RestaurantSummary, UserProfile } from '../types/domain'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { createPreferenceStore } from '../components/RecommendationNotInterested'
import { BrowserRecommendationPreferenceSync, emptyBrowserRecommendationPreferenceState, type BrowserRecommendationPreferenceState } from '../services/browserRecommendationPreferenceSync'

const profile = (owner: string): TasteMapProfileDashboardViewModel => ({
  user: { ...fixture.profile.user, id: owner } as UserProfile,
  restaurants: fixture.restaurants.map(restaurant => ({ ...restaurant, userId: owner })) as unknown as RestaurantSummary[],
  visits: [], followerCount: 0, followingCount: 0, restaurantImages: {},
})
function storage() {
  const values = new Map<string, string>()
  vi.stubGlobal('localStorage', { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => values.set(key, value) })
}
afterEach(() => vi.unstubAllGlobals())
function preferenceSync() {
  const rows = new Map<string, BrowserRecommendationPreferenceState>()
  return new BrowserRecommendationPreferenceSync({
    read: async owner => rows.get(owner),
    update: async (owner, change) => { const next = change(structuredClone(rows.get(owner) ?? emptyBrowserRecommendationPreferenceState(owner))); rows.set(owner, next); return next },
  }, undefined, undefined, () => false)
}
describe('Browser recommendation ownership', () => {
  it('publishes an owner change to the real shared store and detaches listeners', async () => {
    storage()
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile('a') }, preferenceSync())
    const listener = vi.fn(); const subscription = await adapter.events.subscribe(listener)
    const store = createPreferenceStore(adapter); const disconnect = store.connect()
    await store.refresh()
    expect(store.snapshot().ownerID).toBe('a')
    adapter.acceptProfileSnapshot(profile('b'))
    expect(store.snapshot().ready).toBe(false)
    await store.refresh()
    expect(store.snapshot()).toMatchObject({ ownerID: 'b', excludedIDs: [] })
    await expect(store.dismiss(fixture.restaurants[0].id, 'a')).rejects.toThrow('账户已切换')
    expect(listener).toHaveBeenCalledWith(expect.objectContaining({ name: 'auth.changed', payload: expect.objectContaining({ userID: 'b' }) }))
    await subscription.remove(); disconnect()
    adapter.acceptProfileSnapshot(profile('c'))
    expect(listener).toHaveBeenCalledTimes(1)
  })
  it('binds an in-flight write to its initial profile even without an acquisition snapshot', async () => {
    storage()
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile('a') }, preferenceSync())
    await adapter.recommendations.preference()
    const pending = adapter.recommendations.preference(fixture.restaurants[0].id)
    adapter.acceptProfileSnapshot(profile('b'))
    await expect(pending).rejects.toMatchObject({ code: 'account_changed' })
    expect(await adapter.recommendations.preference()).toMatchObject({ ownerID: 'b', excludedIDs: [] })
  })
})
