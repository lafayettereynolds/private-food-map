import { afterEach, describe, expect, it } from 'vitest'
import { BrowserRecommendationPreferenceSync, emptyBrowserRecommendationPreferenceState, projectBrowserRecommendationPreferences,
  type BrowserRecommendationPreferenceState, type BrowserRecommendationPreferenceStore, type RecommendationPreferenceTransport } from './browserRecommendationPreferenceSync'
import type { RecommendationPreferenceEventV1 } from '../contracts/recommendationPreferencesV1'

const controllers: BrowserRecommendationPreferenceSync[] = []
afterEach(() => controllers.splice(0).forEach(controller => controller.setOwner(null)))
const storage = () => {
  const records = new Map<string, string>()
  return { records, getItem: (key: string) => records.get(key) ?? null }
}
class MemoryStore implements BrowserRecommendationPreferenceStore {
  rows = new Map<string, BrowserRecommendationPreferenceState>()
  async read(owner: string) { const row = this.rows.get(owner); return row ? structuredClone(row) : undefined }
  async update(owner: string, change: (state: BrowserRecommendationPreferenceState) => BrowserRecommendationPreferenceState) {
    const next = change(structuredClone(this.rows.get(owner) ?? emptyBrowserRecommendationPreferenceState(owner)))
    this.rows.set(owner, structuredClone(next)); return structuredClone(next)
  }
}
function server() {
  const events = new Map<string, Map<string, RecommendationPreferenceEventV1 & { revision: number; receivedAt: string }>>()
  let revision = 0
  const state = { owner: 'a', pushes: 0, offline: false, loseAck: false, before: null as null | ((path: string) => Promise<void>) }
  const transport: RecommendationPreferenceTransport = async <T>(path: string, body?: unknown, options?: { headers?: Record<string, string> }) => {
    if (state.offline) throw new Error('offline')
    if (state.before) await state.before(path)
    const owner = state.owner
    if (!events.has(owner)) events.set(owner, new Map())
    const current = events.get(owner)!
    if (body) {
      if (options?.headers?.['X-Taste-Map-Preference-Owner'] !== owner) throw new Error('account_changed')
      state.pushes++
      const receipts = (body as { events: RecommendationPreferenceEventV1[] }).events.map(event => {
        if (!current.has(event.eventID)) current.set(event.eventID, { ...event, revision: ++revision, receivedAt: new Date().toISOString() })
        return { eventID: event.eventID, revision: current.get(event.eventID)!.revision }
      })
      if (state.loseAck) { state.loseAck = false; throw new Error('lost acknowledgement') }
      return { apiVersion: 1, ownerID: owner, receipts } as T
    }
    const query = new URL(path, 'https://test').searchParams
    const after = query.get('cursor') ? Number(atob(query.get('cursor')!.slice(4))) : 0
    const found = [...current.values()].filter(event => event.revision > after).slice(0, 100)
    const cursor = `rp1.${btoa(String(found[found.length - 1]?.revision ?? after)).replace(/=+$/, '')}`
    return { apiVersion: 1, ownerID: owner, events: found, cursor, hasMore: false } as T
  }
  return { state, transport, events }
}
function controller(store: MemoryStore, transport: RecommendationPreferenceTransport, owner = 'a') {
  let enabled = false
  const sync = new BrowserRecommendationPreferenceSync(store, transport, () => {}, () => enabled)
  controllers.push(sync); sync.setOwner(owner)
  return { sync, enable: () => { enabled = true } }
}
const adding = (id = 'amap:a') => ({ aliases: [id], metadata: { name: '肯德基(门店)', tags: [] } })

describe('Browser durable recommendation outbox', () => {
  it('keeps a confirmed exclusion offline and resumes the same immutable event after recreation', async () => {
    const store = new MemoryStore(); const remote = server(); const legacy = storage()
    const first = controller(store, remote.transport)
    expect(await first.sync.preference('a', legacy, [], adding())).toMatchObject({ excludedIDs: ['amap:a'], intentFeedback: { brandIDs: ['kfc'], contextCounts: { everyday_fast_food: 1 } } })
    const eventID = store.rows.get('a')!.entries[0].event.eventID
    first.enable(); remote.state.offline = true
    await expect(first.sync.syncNow()).rejects.toThrow('offline')
    expect(store.rows.get('a')).toMatchObject({ entries: [{ pending: true }], attempts: 1, lastError: 'offline' })
    first.sync.setOwner(null)
    remote.state.offline = false
    const second = controller(store, remote.transport); second.enable()
    await second.sync.syncNow()
    expect(store.rows.get('a')!.entries[0]).toMatchObject({ event: { eventID }, pending: false })
    expect(remote.events.get('a')!.size).toBe(1)
  })

  it('unions two offline devices and counts repeated same-restaurant feedback once after a lost acknowledgement', async () => {
    const remote = server(); const storeA = new MemoryStore(); const storeB = new MemoryStore()
    const a = controller(storeA, remote.transport); const b = controller(storeB, remote.transport)
    await a.sync.preference('a', storage(), [], adding('amap:same'))
    await b.sync.preference('a', storage(), [], adding('amap:same'))
    await b.sync.preference('a', storage(), [], adding('amap:other'))
    a.enable(); b.enable(); remote.state.loseAck = true
    await expect(a.sync.syncNow()).rejects.toThrow('lost acknowledgement')
    expect(storeA.rows.get('a')!.entries[0].pending).toBe(true)
    await a.sync.syncNow(); await b.sync.syncNow(); await a.sync.syncNow()
    for (const store of [storeA, storeB]) {
      const snapshot = projectBrowserRecommendationPreferences(store.rows.get('a')!, [])
      expect(snapshot.excludedIDs).toEqual(['amap:other', 'amap:same'])
      expect(snapshot.intentFeedback?.contextCounts).toEqual({ everyday_fast_food: 2 })
    }
    expect(remote.events.get('a')!.size).toBe(3)
  })

  it('migrates legacy facts without deleting keys or inventing intent, dates or extra votes on repeated reads', async () => {
    const remote = server(); const store = new MemoryStore(); const local = storage()
    local.records.set('tastemap:recommendation-exclusions:v1:a', '["amap:old"]')
    local.records.set('tastemap:recommendation-exclusions:v2:a', JSON.stringify({ excludedIDs: ['amap:voted'], entries: [{ aliases: ['amap:voted'], brandID: null, context: 'snack_takeaway' }] }))
    const original = [...local.records]
    const a = controller(store, remote.transport)
    const snapshot = await a.sync.preference('a', local, [])
    await a.sync.preference('a', local, [])
    expect(store.rows.get('a')!.entries).toHaveLength(3)
    expect(store.rows.get('a')!.entries.every(item => item.event.occurredAt === null)).toBe(true)
    expect(snapshot.intentFeedback?.contextCounts).toEqual({ snack_takeaway: 1 })
    expect([...local.records]).toEqual(original)
    a.enable(); await a.sync.syncNow()
    await a.sync.preference('a', local, [])
    expect(store.rows.get('a')!.entries.every(item => !item.pending)).toBe(true)
  })

  it('does not upload local owner data under a different authenticated account', async () => {
    const remote = server(); const store = new MemoryStore(); const a = controller(store, remote.transport)
    await a.sync.preference('a', storage(), [], adding()); remote.state.owner = 'b'; a.enable()
    await expect(a.sync.syncNow()).rejects.toThrow('账号')
    expect(remote.state.pushes).toBe(0)
    expect(store.rows.get('a')!.entries[0].pending).toBe(true)
    expect(store.rows.has('b')).toBe(false)
  })

  it('switching accounts during a pull leaves the original owner outbox untouched', async () => {
    const remote = server(); const store = new MemoryStore(); const a = controller(store, remote.transport)
    await a.sync.preference('a', storage(), [], adding())
    let release!: () => void
    remote.state.before = () => new Promise(resolve => { release = resolve })
    a.enable(); const pending = a.sync.syncNow()
    await new Promise(resolve => setTimeout(resolve, 0))
    a.sync.setOwner('b'); remote.state.owner = 'b'; release()
    await expect(pending).rejects.toThrow('账户已切换')
    expect(remote.state.pushes).toBe(0)
    expect(store.rows.get('a')!.entries[0].pending).toBe(true)
    expect(store.rows.get('a')!.cursor).toBeNull()
  })

  it('a cookie change between pull and push is rejected by the expected-owner precondition', async () => {
    const remote = server(); const store = new MemoryStore(); const a = controller(store, remote.transport)
    await a.sync.preference('a', storage(), [], adding())
    remote.state.before = async path => { if (path.endsWith('/push')) remote.state.owner = 'b' }
    a.enable(); await expect(a.sync.syncNow()).rejects.toThrow('account_changed')
    expect(store.rows.get('a')!.entries[0].pending).toBe(true)
    expect(remote.events.get('b')?.size ?? 0).toBe(0)
  })

  it('invalid pull and incomplete receipts cannot erase local events or acknowledge unsent work', async () => {
    for (const broken of ['pull', 'ack']) {
      const remote = server(); const store = new MemoryStore()
      const transport: RecommendationPreferenceTransport = async <T>(path: string, body?: unknown, options?: { signal?: AbortSignal; headers?: Record<string, string> }) => {
        if (broken === 'pull') return { apiVersion: 1, ownerID: 'a', cursor: 'rp1.YQ', events: null, hasMore: false } as T
        if (body) return { apiVersion: 1, ownerID: 'a', receipts: [] } as T
        return remote.transport<T>(path, body, options)
      }
      const a = controller(store, transport); await a.sync.preference('a', storage(), [], adding()); a.enable()
      await expect(a.sync.syncNow()).rejects.toThrow()
      expect(store.rows.get('a')!.entries).toHaveLength(1)
      expect(store.rows.get('a')!.entries[0].pending).toBe(true)
      if (broken === 'pull') expect(store.rows.get('a')!.cursor).toBeNull()
    }
  })

  it('keeps hard exclusions and suppresses conflicting intent independently of event arrival order', () => {
    const state = emptyBrowserRecommendationPreferenceState('a')
    state.entries = ['everyday_fast_food', 'snack_takeaway'].map((context, index) => ({ pending: false, event: {
      eventID: `e-${index}`, aliases: index ? ['alias-b'] : ['alias-a'], source: 'explicit_dismissal', occurredAt: '2026-09-07T00:00:00.000Z',
      intent: { classifierVersion: 1, brandID: null, context: context as 'everyday_fast_food' | 'snack_takeaway' },
    } }))
    const groups = [['alias-a', 'alias-b']]
    const first = projectBrowserRecommendationPreferences(state, groups)
    state.entries.reverse()
    expect(projectBrowserRecommendationPreferences(state, groups)).toEqual(first)
    expect(first).toMatchObject({ excludedIDs: ['alias-a', 'alias-b'], intentFeedback: { brandIDs: [], contextCounts: {} } })
  })
})
