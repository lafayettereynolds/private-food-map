import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  TasteMapPlatformError,
  type TasteMapAuthResult,
  type TasteMapAuthSessionStatus,
  type TasteMapPlatform,
  type TasteMapProfileSnapshot,
  type TasteMapRuntimeInfo,
} from './TasteMapPlatform'
import type { RestaurantSummary } from '../types/domain'

interface TasteMapNativeV1Plugin {
  runtimeInfo(): Promise<TasteMapRuntimeInfo>
  profileGetCurrent(): Promise<TasteMapProfileSnapshot>
  restaurantGet(options: { id: string }): Promise<RestaurantSummary>
  hapticsSelection(): Promise<Record<string, never>>
  authSessionStatus(): Promise<TasteMapAuthSessionStatus>
  authSignInWithApple(): Promise<TasteMapAuthResult>
}

interface CapacitorWindow extends Window {
  Capacitor?: {
    Plugins?: { TasteMapNative?: TasteMapNativeV1Plugin }
    getPlatform?: () => string
    isNativePlatform?: () => boolean
  }
}

export class TasteMapNativeAdapter implements TasteMapPlatform {
  readonly kind = 'native' as const
  private readonly plugin: TasteMapNativeV1Plugin

  constructor(target: CapacitorWindow = window as CapacitorWindow) {
    const plugin = target.Capacitor?.Plugins?.TasteMapNative
    if (!plugin) throw new TasteMapPlatformError('TasteMapNative.v1 is not registered.', 'native_bridge_unavailable')
    this.plugin = plugin
  }

  runtime = {
    info: async () => {
      const info = await this.plugin.runtimeInfo()
      if (info.bridgeVersion !== TASTE_MAP_NATIVE_BRIDGE_VERSION) {
        throw new TasteMapPlatformError(`Unsupported bridge version ${info.bridgeVersion}.`, 'bridge_version_mismatch')
      }
      return info
    },
  }

  profile = { getCurrent: () => this.plugin.profileGetCurrent() }
  restaurant = { get: (id: string) => this.plugin.restaurantGet({ id }) }
  haptics = { selection: async () => { await this.plugin.hapticsSelection() } }
  auth = {
    sessionStatus: () => this.plugin.authSessionStatus(),
    signInWithApple: () => this.plugin.authSignInWithApple(),
  }
}

export function hasNativeTasteMapRuntime(target: CapacitorWindow = window as CapacitorWindow) {
  return target.Capacitor?.isNativePlatform?.() === true
    && target.Capacitor?.getPlatform?.() === 'ios'
    && Boolean(target.Capacitor?.Plugins?.TasteMapNative)
}
