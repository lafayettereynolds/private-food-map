import {
  TASTE_MAP_NATIVE_BRIDGE_VERSION,
  TasteMapPlatformError,
  type TasteMapPlatform,
  type TasteMapPOCDataset,
} from './TasteMapPlatform'

export class TasteMapBrowserAdapter implements TasteMapPlatform {
  readonly kind = 'browser' as const
  private datasetPromise: Promise<TasteMapPOCDataset> | null = null

  runtime = {
    info: async () => ({
      bridgeVersion: TASTE_MAP_NATIVE_BRIDGE_VERSION,
      platform: 'browser' as const,
      dataSource: 'browser-fixture' as const,
      localBundle: false,
      offlineCapable: false,
    }),
  }

  profile = {
    getCurrent: async () => {
      const dataset = await this.dataset()
      return {
        ...dataset.profile,
        restaurants: dataset.restaurants,
        visits: dataset.restaurants.flatMap((restaurant) => restaurant.visits),
      }
    },
  }

  restaurant = {
    get: async (id: string) => {
      const restaurant = (await this.dataset()).restaurants.find((item) => item.id === id)
      if (!restaurant) throw new TasteMapPlatformError(`Restaurant ${id} was not found.`, 'restaurant_not_found')
      return restaurant
    },
  }

  haptics = { selection: async () => undefined }

  auth = {
    sessionStatus: async () => ({ state: 'authenticated' as const, provider: 'local-poc' as const, userID: 'tm_capacitor_poc' }),
    signInWithApple: async () => ({ state: 'unavailable' as const, reason: 'Browser POC does not invoke Apple authentication.' }),
  }

  private dataset() {
    this.datasetPromise ??= fetch('/hybrid-poc/dataset.json', { cache: 'no-store' }).then(async (response) => {
      if (!response.ok) throw new TasteMapPlatformError('The deterministic Browser fixture could not be loaded.', 'fixture_unavailable')
      return response.json() as Promise<TasteMapPOCDataset>
    })
    return this.datasetPromise
  }
}
