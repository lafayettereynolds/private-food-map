import { beforeEach, describe, expect, it, vi } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { DiningCompanion } from '../types/domain'
import type { TasteMapAnalyticsIdentityDTO, TasteMapProfileDashboardDTO } from './TasteMapPlatform'
import { projectBridgeProfile } from './TasteMapBridgeProjection'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'

const state = vi.hoisted(() => ({ companions: [] as DiningCompanion[] }))
vi.mock('../db/social', () => ({ CURRENT_USER_ID: 'owner', ensureCurrentUser: async () => ({ id: 'owner', nickname: '本人', membershipTier: 'free' }) }))
vi.mock('../db/appDb', () => ({ db: {
  restaurants: { filter: () => ({ toArray: async () => [] }) }, visits: { filter: () => ({ toArray: async () => [] }) }, follows: { toArray: async () => [] },
  diningCompanions: { where: (field: string) => ({ equals: (owner: string) => ({ toArray: async () => state.companions.filter(item => field === 'ownerUserId' && item.ownerUserId === owner) }) }) },
} }))

const identity: TasteMapAnalyticsIdentityDTO = { ownerUserID: 'tm_owner', recordOwnerID: 'tm_owner', companions: [], sources: [], visitSourceLinks: [] }
describe('owner-proven analytics directory projection', () => {
  beforeEach(() => { state.companions = [] })
  it('only accepts the matching native owner bundle and explicitly maps its record sentinel', () => {
    const raw = { ...fixture.profile, user: { ...fixture.profile.user, id: 'tm_owner' }, restaurants: [], analyticsIdentity: identity } as unknown as TasteMapProfileDashboardDTO
    expect(projectBridgeProfile(raw).analyticsIdentity).toEqual({ ...identity, recordOwnerID: 'owner' })
    expect(projectBridgeProfile({ ...raw, analyticsIdentity: { ...identity, ownerUserID: 'tm_other' } }).analyticsIdentity).toBeNull()
    expect(projectBridgeProfile({ ...raw, analyticsIdentity: undefined }).analyticsIdentity).toBeNull()
  })
  it('Browser reads its real private companion directory without inventing a source directory or exposing linked IDs', async () => {
    state.companions = [
      { id: 'a', ownerUserId: 'owner', displayName: '同名', linkedUserId: 'private-linked-user', createdAt: '', updatedAt: '2026-09-01', deletedAt: null },
      { id: 'b', ownerUserId: 'owner', displayName: '同名', linkedUserId: null, createdAt: '', updatedAt: '2026-09-02', deletedAt: null },
      { id: 'foreign', ownerUserId: 'another-owner', displayName: '外部姓名', linkedUserId: null, createdAt: '', updatedAt: '', deletedAt: null },
    ]
    const adapter = new TasteMapBrowserAdapter()
    const result = (await adapter.profile.getCurrent()).analyticsIdentity!
    expect(result.ownerUserID).toBe('owner')
    expect(result.recordOwnerID).toBe('owner')
    expect(result.companions?.map(item => item.id)).toEqual(['a', 'b'])
    expect(result.sources).toBeNull()
    expect(result.visitSourceLinks).toBeNull()
    expect(JSON.stringify(result)).not.toContain('private-linked-user')
    expect(JSON.stringify(result)).not.toContain('外部姓名')
    state.companions[0].displayName = '已改名'
    state.companions[1].deletedAt = '2026-09-03'
    const updated = (await adapter.profile.getCurrent()).analyticsIdentity!
    expect(updated.companions?.[0].displayName).toBe('已改名')
    expect(updated.companions?.[1].deletedAt).toBe('2026-09-03')
  })
})
