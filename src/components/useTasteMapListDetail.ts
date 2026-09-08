import { useCallback, useEffect, useRef, useState } from 'react'
import type { TasteMapHybridListDTO, TasteMapPlatform } from '../platform/TasteMapPlatform'
import { mergeListPage } from '../platform/restaurantListProjection'

export function useTasteMapListDetail(id: string, seed: TasteMapHybridListDTO | undefined, platform: TasteMapPlatform) {
  const [list, setList] = useState<TasteMapHybridListDTO | null>(seed ?? null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const generation = useRef(0)
  const latest = useRef({ list, loading, nextCursor })
  latest.current = { list, loading, nextCursor }

  const read = useCallback(async (append: boolean) => {
    if (!platform.lists) {
      setError('当前版本尚未连接食单详情读取。')
      return
    }
    const previous = latest.current
    if (append && (previous.loading || !previous.nextCursor)) return
    const sequence = ++generation.current
    latest.current = { ...previous, loading: true }
    setLoading(true)
    setError('')
    if (!append) setNextCursor(null)
    try {
      const page = await boundedListRead(platform.lists.get({ id, cursor: append ? previous.nextCursor : null }))
      if (generation.current !== sequence) return
      setList(mergeListPage(append ? previous.list : null, page))
      setNextCursor(page.nextCursor)
    } catch (reason) {
      if (generation.current !== sequence) return
      const code = reason && typeof reason === 'object' && 'code' in reason ? reason.code : null
      if (['list_unavailable', 'auth_required', 'list_request_superseded'].includes(String(code))) {
        setList(null)
        setNextCursor(null)
      }
      setError(reason instanceof Error ? reason.message : '食单读取失败，请重试。')
    } finally {
      if (generation.current === sequence) setLoading(false)
    }
  }, [id, platform])

  useEffect(() => {
    setList(seed ?? null)
    void read(false)
    return () => { ++generation.current }
  // Ordinary parent snapshot identity changes do not discard loaded pages.
  // A real List revision refreshes membership and invalidates the old cursor.
  }, [id, seed?.updatedAt, read])

  useEffect(() => {
    let disposed = false
    let remove: (() => Promise<void>) | undefined
    void platform.events.subscribe(event => {
      if (disposed) return
      if (event.name === 'auth.changed') {
        ++generation.current
        setList(null); setNextCursor(null); setLoading(false)
        setError('账户已变化，请重新打开食单。')
      } else if (event.name === 'data.changed') void read(false)
    }).then(subscription => {
      if (disposed) void subscription.remove()
      else remove = () => subscription.remove()
    }).catch(() => undefined)
    return () => { disposed = true; void remove?.() }
  }, [platform, read])

  return { list, loading, error, nextCursor, reload: () => read(false), loadMore: () => read(true) }
}

function boundedListRead<T>(promise: Promise<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('食单读取超时，请重试。')), 15_000)
    promise.then(resolve, reject).finally(() => clearTimeout(timeout))
  })
}
