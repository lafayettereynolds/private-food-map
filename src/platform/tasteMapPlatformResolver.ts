import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { hasNativeTasteMapRuntime, TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import type { TasteMapPlatform } from './TasteMapPlatform'

export function resolveTasteMapPlatform(): TasteMapPlatform {
  const requested = new URLSearchParams(window.location.search).get('adapter')
  if (import.meta.env.DEV && requested === 'browser') return new TasteMapBrowserAdapter()
  return hasNativeTasteMapRuntime() ? new TasteMapNativeAdapter() : new TasteMapBrowserAdapter()
}

export function shouldRenderHybridShell() {
  const internalBrowserEntry = import.meta.env.DEV
    && import.meta.env.VITE_HYBRID_INTERNAL === 'true'
    && new URLSearchParams(window.location.search).get('hybrid') === '1'
  return import.meta.env.VITE_HYBRID_SHELL === 'true'
    || internalBrowserEntry
    || hasNativeTasteMapRuntime()
}
