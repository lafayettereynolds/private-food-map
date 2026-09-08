import { describe, expect, it } from 'vitest'
import { TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import type { TasteMapBridgeRequestEnvelope, TasteMapHybridEvent } from './TasteMapPlatform'

function fixture() {
  const requests: TasteMapBridgeRequestEnvelope<unknown>[] = []
  const listeners = new Set<(event: TasteMapHybridEvent) => void>()
  const adapter = new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: {
    addListener: async (_: string, listener: (event: TasteMapHybridEvent) => void) => {
      listeners.add(listener)
      return { remove: async () => { listeners.delete(listener) } }
    },
    invoke: async ({ request }: { request: TasteMapBridgeRequestEnvelope<unknown> }) => {
      requests.push(request)
      return { version: 1, requestId: request.requestId, result: request.method === 'runtime.info'
        ? { bridgeVersion: 1 }
        : { route: request.payload, owner: 'hybrid', canGoBack: true, sourceRequestID: request.requestId } }
    },
  } } } } as never)
  const emit = (sourceRequestID?: string, name: 'navigation.route' | 'deepLink.received' = 'navigation.route') => {
    const event: TasteMapHybridEvent = { version: 1, sequence: 1, name, payload: { route: { surface: 'discovery' }, owner: 'hybrid', canGoBack: true, sourceRequestID } }
    listeners.forEach(listener => listener(event))
  }
  return { adapter, requests, emit }
}

describe('Native navigation acknowledgement correlation', () => {
  it('sends replacement only for an explicit completed-route command without leaking local acknowledgement policy', async () => {
    const { adapter, requests } = fixture()
    await adapter.navigation.openHybrid({ surface: 'restaurant', identifier: 'restaurant-1' }, { localTransition: true, replaceCurrent: true })
    await adapter.navigation.openHybrid({ surface: 'map' }, { localTransition: true })
    const commands = requests.filter(request => request.method === 'navigation.openHybrid')
    expect(commands.map(request => request.payload)).toEqual([
      { surface: 'restaurant', identifier: 'restaurant-1', replaceCurrent: true },
      { surface: 'map' },
    ])
  })

  it('consumes its own completed and reversed acknowledgements for every subscriber without a timeout', async () => {
    const { adapter, requests, emit } = fixture()
    const first: TasteMapHybridEvent[] = [], second: TasteMapHybridEvent[] = []
    await adapter.events.subscribe(event => first.push(event))
    await adapter.events.subscribe(event => second.push(event))
    await adapter.navigation.openHybrid({ surface: 'discovery' }, { localTransition: true })
    await adapter.navigation.openHybrid({ surface: 'map' }, { localTransition: true })
    await adapter.navigation.back({ localTransition: true })
    const commands = requests.filter(request => request.method.startsWith('navigation.'))
    expect(new Set(commands.map(request => request.requestId)).size).toBe(3)
    for (const request of commands.reverse()) emit(request.requestId)
    expect(first).toEqual([])
    expect(second).toEqual([])
  })

  it('preserves genuine Native-origin, legacy uncorrelated, foreign-client and deep-link events', async () => {
    const { adapter, requests, emit } = fixture()
    const delivered: TasteMapHybridEvent[] = []
    await adapter.events.subscribe(event => delivered.push(event))
    await adapter.navigation.openHybrid({ surface: 'map' })
    emit()
    emit('another-client-request')
    emit(requests[requests.length - 1].requestId) // An ordinary component handoff still owns its route event.
    emit(requests[requests.length - 1].requestId, 'deepLink.received')
    expect(delivered).toHaveLength(4)
    expect(delivered.map(event => event.name)).toEqual(['navigation.route', 'navigation.route', 'navigation.route', 'deepLink.received'])
  })

  it('keeps rapid open/add/back request order while runtime verification is shared', async () => {
    const { adapter, requests } = fixture()
    await Promise.all([
      adapter.navigation.openHybrid({ surface: 'map' }),
      adapter.navigation.openHybrid({ surface: 'add' }),
      adapter.navigation.back(),
      adapter.navigation.openHybrid({ surface: 'discovery' }),
      adapter.navigation.openHybrid({ surface: 'map' }),
    ])
    const commands = requests.filter(request => request.method.startsWith('navigation.'))
    expect(commands.map(request => request.method === 'navigation.back' ? 'back' : (request.payload as { surface: string }).surface))
      .toEqual(['map', 'add', 'back', 'discovery', 'map'])
    expect(commands.every(request => request.requestId.length >= 8 && request.requestId.length <= 128)).toBe(true)
  })
})
