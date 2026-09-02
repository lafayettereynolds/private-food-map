import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import { hasNativeTasteMapRuntime, TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import type { TasteMapPlatform } from './TasteMapPlatform'

export function resolveTasteMapPlatform(): TasteMapPlatform {
  const requested = new URLSearchParams(window.location.search).get('adapter')
  if (requested === 'browser') return new TasteMapBrowserAdapter()
  return hasNativeTasteMapRuntime() ? new TasteMapNativeAdapter() : new TasteMapBrowserAdapter()
}

export function shouldRenderHybridPOC() {
  return new URLSearchParams(window.location.search).get('hybridPOC') === '1'
    || hasNativeTasteMapRuntime()
}
