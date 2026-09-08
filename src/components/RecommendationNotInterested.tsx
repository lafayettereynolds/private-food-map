import { useEffect, useRef, useState, useSyncExternalStore } from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'
import { recommendationIdentityKey } from '../services/recommendationExclusions'
import type { RecommendationPreferences } from '../services/recommendationIntent'
import { boundedSnapshotRead } from '../hybrid/app/hybridSnapshotRefresh'
import { ModalShell } from './ModalShell'
import './recommendationNotInterested.css'

type PreferenceState = RecommendationPreferences & { ready: boolean; error: string | null }
const initial: PreferenceState = { ready: false, ownerID: null, excludedIDs: [], error: null }
const unsupported: PreferenceState = { ...initial, ready: true }
const stores = new WeakMap<TasteMapPlatform, ReturnType<typeof createPreferenceStore>>()

export function createPreferenceStore(platform: TasteMapPlatform) {
  let state = platform.recommendations ? initial : unsupported
  let generation = 0
  let writing = false
  let reading: Promise<void> | null = null
  let connectionCount = 0
  let disconnect: (() => void) | null = null
  const listeners = new Set<() => void>()
  const publish = (next: PreferenceState) => { state = next; listeners.forEach(listener => listener()) }
  const refresh = (): Promise<void> => {
    if (reading) return reading
    const task = async () => {
      if (writing) return
      if (!platform.recommendations) { publish({ ...initial, ready: true }); return }
      const request = ++generation
      try {
        const result = await boundedSnapshotRead(platform.recommendations.preference())
        if (request === generation) publish({ ...result, ready: true, error: null })
      } catch {
        if (request === generation) publish({ ...state, error: '推荐偏好暂时无法读取，请重试。' })
      }
    }
    const result = task().finally(() => { if (reading === result) reading = null })
    reading = result
    return result
  }
  return {
    snapshot: () => state,
    subscribe: (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener) } },
    reset: () => { ++generation; reading = null; publish(initial) },
    connect: () => {
      connectionCount += 1
      if (connectionCount === 1) {
        let cancelled = false
        const subscription = platform.events.subscribe(event => {
          if (cancelled) return
          if (event.name === 'auth.changed') { ++generation; reading = null; publish(initial); void refresh() }
          else if (event.name === 'data.changed' || event.name === 'app.lifecycle') void refresh()
        })
        disconnect = () => { cancelled = true; void subscription.then(value => value.remove()).catch(() => undefined) }
      }
      if (!state.ready) void refresh()
      return () => { connectionCount -= 1; if (!connectionCount) { disconnect?.(); disconnect = null } }
    },
    refresh,
    async dismiss(id: string, expectedOwnerID?: string) {
      if (!platform.recommendations || writing || !state.ready) throw new Error('推荐偏好尚未就绪，请稍后重试。')
      if (expectedOwnerID !== undefined && expectedOwnerID !== state.ownerID) throw new Error('账户已切换，请在当前账户重试。')
      writing = true
      const request = ++generation
      try {
        const result = await platform.recommendations.preference(id)
        if (request !== generation) throw new Error('账户已切换，请在当前账户重试。')
        publish({ ...result, ready: true, error: null })
      } finally { writing = false; if (request !== generation) void refresh() }
    },
  }
}

export function useRecommendationPreferences(platform: TasteMapPlatform) {
  let store = stores.get(platform)
  if (!store) { store = createPreferenceStore(platform); stores.set(platform, store) }
  const current = store
  const state = useSyncExternalStore(current.subscribe, current.snapshot, () => platform.recommendations ? initial : unsupported)
  useEffect(() => current.connect(), [current])
  return { ...state, dismiss: current.dismiss, retry: current.refresh }
}

export function RecommendationNotInterested({ platform, restaurantID, restaurantName, overlay = false }: {
  platform: TasteMapPlatform; restaurantID: string; restaurantName?: string; overlay?: boolean
}) {
  const preferences = useRecommendationPreferences(platform)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmation, setConfirmation] = useState<{ ownerID: string; restaurantID: string } | null>(null)
  const saving = useRef(false)
  const trigger = useRef<HTMLButtonElement>(null)
  useEffect(() => { setConfirmation(null); setError(null) }, [preferences.ownerID, restaurantID])
  const close = () => {
    if (saving.current) return
    setConfirmation(null); setError(null)
    requestAnimationFrame(() => trigger.current?.focus())
  }
  const confirm = async () => {
    if (saving.current || !confirmation) return
    if (confirmation.ownerID !== preferences.ownerID || confirmation.restaurantID !== restaurantID || !preferences.ready) {
      setConfirmation(null); setError('账户或餐厅已变化，请重新操作。'); return
    }
    saving.current = true; setPending(true); setError(null)
    try { await preferences.dismiss(confirmation.restaurantID, confirmation.ownerID); setConfirmation(null) }
    catch (cause) { setError(cause instanceof Error ? cause.message : '未能保存，请重试。') }
    finally { saving.current = false; setPending(false) }
  }
  const excluded = preferences.excludedIDs.includes(recommendationIdentityKey(restaurantID))
  if (!platform.recommendations) return null
  return <><span className={`tm-not-interested${overlay ? ' is-image-overlay' : ''}`}>
    <button ref={trigger} type="button" aria-label={excluded ? '已标记不感兴趣' : '不感兴趣'} aria-haspopup="dialog" aria-expanded={Boolean(confirmation)} aria-busy={pending} disabled={pending || excluded}
      onClick={() => {
        setError(null)
        if (!preferences.ready || !preferences.ownerID) { setError('推荐偏好尚未就绪，请稍后重试。'); void preferences.retry(); return }
        setConfirmation({ ownerID: preferences.ownerID, restaurantID })
      }}><X aria-hidden="true" size={18} /></button>
    {error ? <span role="alert" className="tm-not-interested__error">{error}</span> : null}
  </span>{confirmation ? createPortal(<div onClick={event => event.stopPropagation()}><ModalShell title="不再推荐这家餐厅？" eyebrow={null} description={restaurantName} size="small" onClose={close} dismissDisabled={pending}>
    <p>确认后，这家餐厅将从“为你推荐”和地图“推荐”中移除。不会删除你的收藏、到访记录或评分。</p>
    <p>这次选择会用于调整推荐，不代表你不喜欢它的味道。</p>
    {error ? <p role="alert">{error}</p> : null}
    <div className="modal-actions"><button className="secondary-button" type="button" onClick={close} disabled={pending}>取消</button><button className="primary-button" type="button" onClick={() => void confirm()} disabled={pending}>{pending ? '正在保存…' : '确认不感兴趣'}</button></div>
  </ModalShell></div>, document.body) : null}</>
}
