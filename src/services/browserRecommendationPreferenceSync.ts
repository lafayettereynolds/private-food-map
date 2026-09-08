import {
  normalizeRecommendationPreferenceEventV1,
  type RecommendationPreferenceEventV1,
  type RecommendationPreferencesPullResponseV1,
  type RecommendationPreferencesPushResponseV1,
} from '../contracts/recommendationPreferencesV1'
import { expandRecommendationAliases } from './recommendationExclusions'
import { recommendationIntent, summarizeRecommendationIntent, type RecommendationIntentEntry, type RecommendationIntentMetadata, type RecommendationPreferences } from './recommendationIntent'
import { requestRestaurantListAPI } from './restaurantListApi'

export interface BrowserRecommendationPreferenceState {
  ownerID: string
  entries: Array<{ event: RecommendationPreferenceEventV1; pending: boolean; revision?: number }>
  cursor: string | null
  attempts: number
  nextRetryAt: number
  lastError: string | null
}
export interface BrowserRecommendationPreferenceStore {
  read(ownerID: string): Promise<BrowserRecommendationPreferenceState | undefined>
  /** Must serialize and atomically commit this owner record (including outbox). */
  update(ownerID: string, change: (state: BrowserRecommendationPreferenceState) => BrowserRecommendationPreferenceState): Promise<BrowserRecommendationPreferenceState>
}
export type RecommendationPreferenceTransport = <T>(path: string, body?: unknown, options?: { signal?: AbortSignal; headers?: Record<string, string> }) => Promise<T>
export const emptyBrowserRecommendationPreferenceState = (ownerID: string): BrowserRecommendationPreferenceState => ({ ownerID, entries: [], cursor: null, attempts: 0, nextRetryAt: 0, lastError: null })
const ROOT = '/api/v1/recommendation-preferences/'
const accountChanged = () => new Error('账户已切换，请在当前账户重试。')

/** Transactional local events/outbox. Network is deliberately separate from
 * the local click, and cannot make a successful local exclusion disappear. */
export class BrowserRecommendationPreferenceSync {
  private owner: string | null = null
  private generation = 0
  private running: { owner: string; task: Promise<void>; controller: AbortController } | null = null
  private lastStartedAt = 0
  private retryTimer: ReturnType<typeof setTimeout> | null = null
  constructor(
    private readonly store: BrowserRecommendationPreferenceStore,
    private readonly transport: RecommendationPreferenceTransport = requestRestaurantListAPI,
    private readonly changed: (ownerID: string) => void = () => {},
    private readonly networkEnabled: () => boolean = () => true,
  ) {}

  setOwner(ownerID: string | null) {
    if (this.owner === ownerID) return
    this.owner = ownerID; ++this.generation; this.lastStartedAt = 0
    this.running?.controller.abort(); this.running = null
    if (this.retryTimer) clearTimeout(this.retryTimer)
    this.retryTimer = null
  }

  async preference(ownerID: string, storage: Pick<Storage, 'getItem'>, groups: readonly (readonly string[])[],
    adding?: { aliases: string[]; metadata: RecommendationIntentMetadata }, isCurrent: () => boolean = () => true): Promise<RecommendationPreferences> {
    const generation = this.generation
    const check = () => { if (this.owner !== ownerID || this.generation !== generation || !isCurrent()) throw accountChanged() }
    check()
    const imported = await legacyEvents(storage, ownerID)
    check()
    const state = await this.store.update(ownerID, state => {
      check()
      mergeEvents(state, imported.map(event => ({ event, pending: true })))
      const snapshot = projectBrowserRecommendationPreferences(state, groups)
      if (adding && !expandRecommendationAliases(adding.aliases, groups).some(id => snapshot.excludedIDs.includes(id))) {
        const classification = recommendationIntent(adding.metadata)
        state.entries.push({ pending: true, event: normalizeRecommendationPreferenceEventV1({
          eventID: crypto.randomUUID(), aliases: adding.aliases, source: 'explicit_dismissal',
          occurredAt: new Date().toISOString(), intent: { classifierVersion: 1, ...classification },
        }) })
      }
      return state
    })
    check()
    // Do not await networking in the user's confirmation path.
    this.requestSync(Boolean(adding))
    return projectBrowserRecommendationPreferences(state, groups)
  }

  requestSync(force = false) {
    if (!this.owner || !this.networkEnabled() || (typeof navigator !== 'undefined' && !navigator.onLine)) return
    if (!force && Date.now() - this.lastStartedAt < 30_000) return
    void this.syncNow().catch(() => {}) // durable lastError/nextRetryAt remain inspectable
  }

  /** Safe to call on online, visible, account changes and manual refresh. Every
   * request is time bounded. At most 20 pages/batches per turn; continue later. */
  syncNow(): Promise<void> {
    const ownerID = this.owner
    if (!ownerID || !this.networkEnabled()) return Promise.resolve()
    if (this.running?.owner === ownerID) return this.running.task
    const controller = new AbortController()
    const generation = this.generation
    this.lastStartedAt = Date.now()
    const check = () => { if (this.owner !== ownerID || this.generation !== generation || controller.signal.aborted) throw accountChanged() }
    const request = async <T>(path: string, body?: unknown): Promise<T> => {
      check()
      const timeout = setTimeout(() => controller.abort(), 15_000)
      try { const result = await this.transport<T>(path, body, { signal: controller.signal, headers: { 'X-Taste-Map-Preference-Owner': ownerID } }); check(); return result }
      finally { clearTimeout(timeout) }
    }
    const run = async () => {
      try {
        let remaining = false
        // Pull before any upload proves that this cookie/Access identity is the
        // same owner as local data. Local 'owner' is never silently reassigned.
        for (let pageIndex = 0; pageIndex < 20; pageIndex++) {
          const state = await this.store.read(ownerID) ?? emptyBrowserRecommendationPreferenceState(ownerID)
          check()
          const value = await request<unknown>(`${ROOT}pull?apiVersion=1${state.cursor ? `&cursor=${encodeURIComponent(state.cursor)}` : ''}&limit=100`)
          const page = validatePull(value, ownerID)
          if (page.hasMore && (!page.events.length || page.cursor === state.cursor)) throw new Error('推荐偏好同步分页没有前进。')
          await this.store.update(ownerID, current => {
            check()
            // Another browser tab may have advanced the checkpoint. Never
            // replace it with an older response; events themselves still union.
            mergeEvents(current, page.events.map(event => ({ event: normalizeRecommendationPreferenceEventV1(eventPayload(event)), pending: false, revision: event.revision })))
            if (current.cursor === state.cursor) current.cursor = page.cursor
            return current
          })
          remaining = page.hasMore
          if (!remaining) break
        }
        for (let batchIndex = 0; batchIndex < 20; batchIndex++) {
          check()
          const state = await this.store.read(ownerID) ?? emptyBrowserRecommendationPreferenceState(ownerID)
          const pending = state.entries.filter(item => item.pending).slice(0, 100)
          if (!pending.length) break
          const value = await request<unknown>(`${ROOT}push`, { apiVersion: 1, events: pending.map(item => item.event) })
          const response = validatePush(value, ownerID, pending.map(item => item.event.eventID))
          await this.store.update(ownerID, current => {
            check()
            for (const receipt of response.receipts) {
              const item = current.entries.find(item => item.event.eventID === receipt.eventID)
              if (item) { item.pending = false; item.revision = receipt.revision }
            }
            return current
          })
          if (batchIndex === 19) remaining = true
        }
        check()
        await this.store.update(ownerID, state => { check(); remaining ||= state.entries.some(item => item.pending); return { ...state, attempts: 0, nextRetryAt: remaining ? Date.now() + 1000 : 0, lastError: null } })
        this.changed(ownerID)
        if (remaining) this.scheduleRetry(1000)
      } catch (cause) {
        if (this.owner === ownerID && this.generation === generation) {
          const state = await this.store.update(ownerID, state => {
            const attempts = Math.min(state.attempts + 1, 10)
            return { ...state, attempts, nextRetryAt: Date.now() + Math.min(300_000, 1000 * 2 ** attempts), lastError: cause instanceof Error ? cause.message : '推荐偏好同步失败。' }
          })
          this.scheduleRetry(Math.max(1000, state.nextRetryAt - Date.now()))
        }
        throw cause
      }
    }
    const task = run().finally(() => { if (this.running?.controller === controller) this.running = null })
    this.running = { owner: ownerID, task, controller }
    return task
  }

  connectLifecycle() {
    if (typeof window === 'undefined') return () => {}
    const retry = () => this.requestSync(true)
    const visible = () => { if (document.visibilityState === 'visible') retry() }
    window.addEventListener('online', retry); window.addEventListener('focus', retry)
    document.addEventListener('visibilitychange', visible)
    return () => { window.removeEventListener('online', retry); window.removeEventListener('focus', retry); document.removeEventListener('visibilitychange', visible); this.setOwner(null) }
  }
  private scheduleRetry(delay: number) {
    if (this.retryTimer) clearTimeout(this.retryTimer)
    this.retryTimer = setTimeout(() => { this.retryTimer = null; this.requestSync(true) }, delay)
  }
}

function mergeEvents(state: BrowserRecommendationPreferenceState, incoming: BrowserRecommendationPreferenceState['entries']) {
  for (const item of incoming) {
    const existing = state.entries.find(value => value.event.eventID === item.event.eventID)
    if (existing) {
      if (JSON.stringify(existing.event) !== JSON.stringify(item.event)) throw new Error('推荐偏好事件内容冲突，原记录已保留。')
      if (!item.pending) { existing.pending = false; existing.revision = item.revision }
    } else state.entries.push(item)
  }
}

/** Same-restaurant events across devices count once. Conflicting classifier
 * results suppress that inferred dimension instead of depending on arrival order. */
export function projectBrowserRecommendationPreferences(state: BrowserRecommendationPreferenceState, groups: readonly (readonly string[])[]): RecommendationPreferences {
  const events = state.entries.map(item => item.event)
  const allGroups = [...groups, ...events.map(event => event.aliases)]
  const excludedIDs = expandRecommendationAliases(events.flatMap(event => event.aliases), allGroups)
  const seen = new Set<string>(); const votes: RecommendationIntentEntry[] = []
  for (const event of events) {
    if (event.aliases.some(alias => seen.has(alias))) continue
    const aliases = expandRecommendationAliases(event.aliases, allGroups)
    aliases.forEach(alias => seen.add(alias))
    const classifications = events.filter(item => item.source !== 'legacy_exclusion' && item.aliases.some(alias => aliases.includes(alias))).map(item => item.intent).filter(item => item !== null)
    const brands = new Set(classifications.map(item => item.brandID).filter(item => item !== null))
    const contexts = new Set(classifications.map(item => item.context).filter(item => item !== null))
    votes.push({ aliases, brandID: brands.size === 1 ? [...brands][0] : null, context: contexts.size === 1 ? [...contexts][0] : null })
  }
  return { ownerID: state.ownerID, excludedIDs, intentFeedback: summarizeRecommendationIntent(votes) }
}

async function legacyEvents(storage: Pick<Storage, 'getItem'>, ownerID: string): Promise<RecommendationPreferenceEventV1[]> {
  const suffix = encodeURIComponent(ownerID)
  const legacy: unknown = JSON.parse(storage.getItem(`tastemap:recommendation-exclusions:v1:${suffix}`) ?? '[]')
  const current: unknown = JSON.parse(storage.getItem(`tastemap:recommendation-exclusions:v2:${suffix}`) ?? '{"excludedIDs":[],"entries":[]}')
  const strings = (value: unknown): value is string[] => Array.isArray(value) && value.every(id => typeof id === 'string')
  if (!strings(legacy) || !isRecord(current) || !strings(current.excludedIDs) || !Array.isArray(current.entries)) throw new Error('旧推荐偏好无法读取，原记录已保留。')
  const values: RecommendationPreferenceEventV1[] = [
    ...[...new Set([...legacy, ...current.excludedIDs])].map(alias => normalizeRecommendationPreferenceEventV1({ eventID: 'legacy', aliases: [alias], source: 'legacy_exclusion', occurredAt: null, intent: null })),
    ...current.entries.map(value => {
      if (!isRecord(value)) throw new Error('旧推荐意图无法读取。')
      return normalizeRecommendationPreferenceEventV1({ eventID: 'legacy', aliases: value.aliases, source: 'legacy_intent', occurredAt: null, intent: { classifierVersion: 1, brandID: value.brandID, context: value.context } })
    }),
  ]
  return Promise.all(values.map(async event => {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(event)))
    return { ...event, eventID: `legacy:${[...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('')}` }
  }))
}
function isRecord(value: unknown): value is Record<string, unknown> { return !!value && typeof value === 'object' && !Array.isArray(value) }
function eventPayload(value: RecommendationPreferenceEventV1): RecommendationPreferenceEventV1 {
  return { eventID: value.eventID, aliases: value.aliases, source: value.source, occurredAt: value.occurredAt, intent: value.intent }
}
function validatePull(value: unknown, ownerID: string): RecommendationPreferencesPullResponseV1 {
  if (!isRecord(value) || value.apiVersion !== 1 || value.ownerID !== ownerID || !Array.isArray(value.events) || value.events.length > 100
    || typeof value.cursor !== 'string' || !/^rp1\.[A-Za-z0-9_-]{1,256}$/.test(value.cursor) || typeof value.hasMore !== 'boolean') throw new Error('推荐偏好账号或同步响应不匹配，未上传本地记录。')
  let previous = 0
  const ids = new Set<string>()
  for (const event of value.events) {
    if (!isRecord(event) || !Number.isSafeInteger(event.revision) || Number(event.revision) <= previous || typeof event.receivedAt !== 'string' || !Number.isFinite(Date.parse(event.receivedAt))) throw new Error('推荐偏好同步记录无效。')
    const normalized = normalizeRecommendationPreferenceEventV1(eventPayload(event as unknown as RecommendationPreferenceEventV1))
    if (ids.has(normalized.eventID)) throw new Error('推荐偏好同步记录重复。')
    ids.add(normalized.eventID); previous = Number(event.revision)
  }
  return value as unknown as RecommendationPreferencesPullResponseV1
}
function validatePush(value: unknown, ownerID: string, expected: string[]): RecommendationPreferencesPushResponseV1 {
  if (!isRecord(value) || value.apiVersion !== 1 || value.ownerID !== ownerID || !Array.isArray(value.receipts) || value.receipts.length !== expected.length) throw new Error('推荐偏好同步未得到完整确认。')
  const remaining = new Set(expected)
  for (const receipt of value.receipts) {
    if (!isRecord(receipt) || typeof receipt.eventID !== 'string' || !remaining.delete(receipt.eventID) || !Number.isSafeInteger(receipt.revision) || Number(receipt.revision) < 1) throw new Error('推荐偏好同步确认无效。')
  }
  return value as unknown as RecommendationPreferencesPushResponseV1
}
