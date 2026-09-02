import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'

export const TASTE_MAP_NATIVE_BRIDGE_VERSION = 1 as const

export interface TasteMapRuntimeInfo {
  bridgeVersion: typeof TASTE_MAP_NATIVE_BRIDGE_VERSION
  platform: 'browser' | 'ios'
  dataSource: 'browser-fixture' | 'native-swiftdata-in-memory'
  localBundle: boolean
  offlineCapable: boolean
}

export interface TasteMapProfileSnapshot {
  user: UserProfile
  restaurants: RestaurantSummary[]
  visits: Visit[]
  followerCount: number
  followingCount: number
}

export interface TasteMapAuthSessionStatus {
  state: 'authenticated' | 'signedOut'
  provider: 'apple' | 'local-poc'
  userID: string | null
}

export interface TasteMapAuthResult {
  state: 'cancelled' | 'unavailable'
  reason: string
}

export interface TasteMapPlatform {
  readonly kind: 'browser' | 'native'
  runtime: { info(): Promise<TasteMapRuntimeInfo> }
  profile: { getCurrent(): Promise<TasteMapProfileSnapshot> }
  restaurant: { get(id: string): Promise<RestaurantSummary> }
  haptics: { selection(): Promise<void> }
  auth: {
    sessionStatus(): Promise<TasteMapAuthSessionStatus>
    signInWithApple(): Promise<TasteMapAuthResult>
  }
}

export interface TasteMapPOCDataset {
  profile: {
    user: UserProfile
    followerCount: number
    followingCount: number
  }
  restaurants: RestaurantSummary[]
}

export class TasteMapPlatformError extends Error {
  constructor(message: string, readonly code: string) {
    super(message)
    this.name = 'TasteMapPlatformError'
  }
}
