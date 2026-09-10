import { useSyncExternalStore } from 'react'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'

type Snapshot = { blocked: ReadonlySet<string>; deleted: ReadonlySet<string> }
const stores = new WeakMap<TasteMapPlatform, ReturnType<typeof createStore>>()
function createStore(platform: TasteMapPlatform) {
  let snapshot: Snapshot = { blocked: new Set(), deleted: new Set() }
  const listeners = new Set<() => void>()
  const notify = () => listeners.forEach(listener => listener())
  let subscription: Promise<import('../platform/TasteMapPlatform').TasteMapEventSubscription> | null = null
  return {
    subscribe: (listener: () => void) => {
      listeners.add(listener)
      subscription ??= platform.events.subscribe(event => {
        if (event.name === 'auth.changed') { snapshot = { blocked: new Set(), deleted: new Set() }; notify() }
      })
      return () => {
        listeners.delete(listener)
        if (!listeners.size) {
          void subscription?.then(value => value.remove()).catch(() => undefined)
          subscription = null
          snapshot = { blocked: new Set(), deleted: new Set() }
        }
      }
    },
    snapshot: () => snapshot,
    update: (kind: 'blocked' | 'deleted', id: string, hidden: boolean) => {
      const values = new Set(snapshot[kind])
      if (hidden) values.add(id); else values.delete(id)
      snapshot = { ...snapshot, [kind]: values }; notify()
    },
  }
}
export function ugcSafetyState(platform: TasteMapPlatform) {
  let store = stores.get(platform)
  if (!store) { store = createStore(platform); stores.set(platform, store) }
  return store
}
export function useUGCSafetyState(platform: TasteMapPlatform) {
  const store = ugcSafetyState(platform)
  return useSyncExternalStore(store.subscribe, store.snapshot, store.snapshot)
}
