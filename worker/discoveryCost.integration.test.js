import { describe, it, expect, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { discoveryCostFixture } from './testSupport/discoveryCostFixture.js'
import { discoveryRestaurantCandidates } from './discoveryCandidates'
import { handleDiscoveryV1 } from './discoveryV1'

describe('Discovery candidate-first cost and correctness', () => {
  it('keeps all mode output identical when unrelated city history grows, including whitespace cities', async () => {
    const clock=vi.spyOn(Date,'now').mockReturnValue(Date.parse('2026-09-09T00:00:00Z'))
    const small=discoveryCostFixture({optimizedIndexes:true,outside:0})
    const large=discoveryCostFixture({optimizedIndexes:true,outside:2000})
    try {
      for (const mode of ['for-you','similar-taste','trending']) {
        const request=new Request(`https://fixture.invalid/api/v1/discovery/${mode}?city=杭州&limit=20`)
        expect(await handleDiscoveryV1(request,large,'viewer')).toEqual(await handleDiscoveryV1(request,small,'viewer'))
      }
      const candidates=await discoveryRestaurantCandidates(large,'viewer','杭州')
      expect(candidates).toHaveLength(40)
      const plans=large.queries.flatMap(q=>q.plan.map(p=>p.detail)).join('\n')
      expect(plans).toContain('idx_restaurants_discovery_trimmed_city')
      expect(plans).toContain('idx_visits_discovery_candidate')
      expect(large.queries.some(q=>q.sql.includes('eligible AS MATERIALIZED'))).toBe(true)
    } finally {clock.mockRestore();small.sqlite.close();large.sqlite.close()}
  })
  it('returns the complete deduplicated candidate set above 5000 without a hard availability cap', async () => {
    const db=discoveryCostFixture({optimizedIndexes:true,outside:5001})
    try {
      const candidates=await discoveryRestaurantCandidates(db,'viewer','北京')
      const expected=db.sqlite.prepare("SELECT id FROM restaurants WHERE city='北京' OR user_id='viewer'").all().map(row=>row.id).sort()
      expect(candidates.length).toBeGreaterThan(5000)
      expect([...candidates].sort()).toEqual(expected)
      expect(new Set(candidates).size).toBe(candidates.length)
      expect(db.queries.at(-1).sql).not.toMatch(/\bLIMIT\b/i)
    } finally {db.sqlite.close()}
  })
  it('has no cross-request permission cache and rechecks profile privacy and membership', async () => {
    const db=discoveryCostFixture({optimizedIndexes:true,outside:0})
    const request=new Request('https://fixture.invalid/api/v1/discovery/trending?city=杭州&limit=50')
    try {
      const before=await handleDiscoveryV1(request,db,'viewer')
      expect(before.items.length).toBeGreaterThan(0)
      db.sqlite.exec("UPDATE user_profiles SET visibility='private' WHERE user_id='peer'")
      const after=await handleDiscoveryV1(request,db,'viewer')
      expect(after.items.length).toBeLessThan(before.items.length)
      await expect(handleDiscoveryV1(new Request('https://fixture.invalid/api/v1/discovery/similar-taste?city=杭州'),db,'viewer',{isPremium:false})).rejects.toThrow()
    } finally {db.sqlite.close()}
  })
  it('only primes canonical For You; other tabs retain explicit page loading', () => {
    const runtime=readFileSync('ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift','utf8')
    const refresh=runtime.split('private func refreshDiscoveryContentIfNeeded')[1].split('private func refreshDiscoveryMode')[0]
    expect(refresh).toContain('await refreshDiscoveryMode(.forYou')
    expect(refresh).not.toContain('refreshDiscoveryMode(.similarTaste')
    expect(refresh).not.toContain('refreshDiscoveryMode(.trending')
    const ui=readFileSync('src/hybrid/app/HybridDiscoveryPage.tsx','utf8')
    expect(ui).toContain('citySession.select(canonicalScope ? null : query)')
    expect(ui).toContain('platform.discovery.cityPage(query)')
  })
})
