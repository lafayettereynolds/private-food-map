import { restaurantCityComparisonKey } from '../services/restaurantCity'

interface CityQuery { mode: string; city: string; windowDays: 7 | 30; cursor?: string; snapshotID?: string; forceRefresh?: boolean; filters?: unknown; sort?: string; preferences?: unknown }
interface CityPage {
  mode: string; requestedCity: string; windowDays: 7 | 30
  snapshotID: string | null; nextCursor: string | null
  pagination: 'more' | 'complete' | 'unknown'
}
export interface CityQueryState<P> {
  key: string | null
  page: P | null
  loading: boolean
  appending: boolean
  error: string | null
}
export function discoveryCityQueryKey(query: CityQuery): string {
  return JSON.stringify([query.mode, restaurantCityComparisonKey(query.city), query.windowDays, query.filters ?? null, query.sort ?? 'recommended', query.preferences ?? null])
}

/** Session-only latest-intent guard. It never replaces content.snapshot or Map's
 * canonical recommendation projection, and an owner change clears accepted data. */
export function createDiscoveryCityQuerySession<Q extends CityQuery, P extends CityPage>({ load, owner, publish }: {
  load: (query: Q) => Promise<P>
  owner: () => Promise<string | null>
  publish: (state: CityQueryState<P>) => void
}) {
  let revision = 0
  let query: Q | null = null
  let failureAt = 0
  let failureKey: string | null = null
  let acceptedOwner: string | null = null
  let state: CityQueryState<P> = { key: null, page: null, loading: false, appending: false, error: null }
  const update = (next: CityQueryState<P>) => { state = next; publish(next) }
  async function request(append: boolean, forceRefresh = false) {
    if (!query || (append && (state.loading || state.appending || state.page?.pagination !== 'more' || !state.page.nextCursor || !state.page.snapshotID))) return
    const current = query
    const key = discoveryCityQueryKey(current)
    if (!append && !forceRefresh && failureKey === key && Date.now() - failureAt < 60_000) return
    const token = ++revision
    const priorPage = append ? state.page : null
    update({ key, page: priorPage, loading: !append, appending: append, error: null })
    try {
      const identity = await owner()
      if (token !== revision) return
      if (!identity || (append && identity !== acceptedOwner)) throw new Error('账户已变化，请重新搜索城市。')
      const payload = append ? { ...current, cursor: priorPage!.nextCursor!, snapshotID: priorPage!.snapshotID! } : { ...current, forceRefresh }
      const result = await load(payload)
      if (token !== revision) return
      const currentOwner = await owner()
      if (token !== revision) return
      if (currentOwner !== identity) {
        acceptedOwner = null
        update({ key, page: null, loading: false, appending: false, error: '账户已变化，请重新搜索城市。' })
        return
      }
      if (result.mode !== current.mode || result.windowDays !== current.windowDays
        || restaurantCityComparisonKey(result.requestedCity) !== restaurantCityComparisonKey(current.city)) {
        throw new Error('城市查询结果与当前选择不一致，请重试。')
      }
      if (append && result.snapshotID !== priorPage!.snapshotID) throw new Error('这份城市结果已更新，请重新搜索。')
      failureKey = null
      acceptedOwner = identity
      update({ key, page: result, loading: false, appending: false, error: null })
    } catch (error) {
      if (token !== revision) return
      const currentOwner = await owner().catch(() => null)
      if (token !== revision) return
      failureAt = Date.now(); failureKey = key
      update({ key, page: currentOwner && currentOwner === acceptedOwner ? priorPage : null,
        loading: false, appending: false, error: error instanceof Error ? error.message : '城市内容暂时无法加载，请重试。' })
    }
  }
  return {
    snapshot: () => state,
    select(next: Q | null) {
      ++revision
      query = next
      failureKey = null
      acceptedOwner = null
      update({ key: next ? discoveryCityQueryKey(next) : null, page: null, loading: false, appending: false, error: null })
      return next ? request(false) : Promise.resolve()
    },
    retry: () => request(false, true),
    refreshAutomatically: () => request(false),
    more: () => request(true),
    invalidate() {
      ++revision; acceptedOwner = null; query = null; failureKey = null
      update({ key: null, page: null, loading: false, appending: false, error: null })
    },
  }
}
