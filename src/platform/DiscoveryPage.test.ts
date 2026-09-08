import { describe, expect, it, vi } from 'vitest'
import { TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import { TasteMapBrowserAdapter } from './TasteMapBrowserAdapter'
import type { TasteMapBridgeRequestEnvelope, TasteMapDiscoveryPageDTO, TasteMapDiscoveryPageRequest } from './TasteMapPlatform'

const request: TasteMapDiscoveryPageRequest = { mode: 'trending', city: '杭州', windowDays: 30 }
const result: TasteMapDiscoveryPageDTO = {
  version: 1, mode: 'trending', requestedCity: '杭州', resolvedCity: '杭州市', windowDays: 30,
  snapshotID: 'server-scoped-native-session', generatedAt: '2026-09-06T00:00:00Z', items: [],
  nextCursor: 'opaque-real-cursor', pagination: 'more', engagementState: 'unknown', interactionsAvailable: false,
  refreshStatus: { state: 'fresh', city: '杭州市', windowDays: 30,
    sourceGeneratedAt: '2026-09-06T00:00:00Z', attemptedAt: '2026-09-06T00:00:01Z', issue: null },
}

function native(capability?: boolean, response: unknown = result, error?: object) {
  const invoke = vi.fn(async ({ request }: { request: TasteMapBridgeRequestEnvelope<unknown> }) => ({
    version: 1, requestId: request.requestId,
    ...(request.method === 'runtime.info'
      ? { result: { bridgeVersion: 1, supportedCapabilities: capability === undefined ? {} : { discoveryPage: capability } } }
      : error ? { error } : { result: response }),
  }))
  const target = { Capacitor: { Plugins: { TasteMapNative: { invoke } } } }
  return { invoke, adapter: new TasteMapNativeAdapter(target as unknown as ConstructorParameters<typeof TasteMapNativeAdapter>[0]) }
}

describe('additive discovery.page v1 adapter boundary', () => {
  it('sends selected city, mode, 30-day window and exact server cursor/snapshot without filtering content.snapshot', async () => {
    const { adapter, invoke } = native(true)
    expect(await adapter.discovery.page(request)).toEqual(result)
    const continuation = { ...request, cursor: result.nextCursor!, snapshotID: result.snapshotID! }
    await adapter.discovery.page(continuation)
    expect(invoke.mock.calls.map(([{ request }]) => request.method)).toEqual(['runtime.info', 'discovery.page', 'discovery.page'])
    expect(invoke.mock.calls[1][0].request.payload).toEqual(request)
    expect(invoke.mock.calls[2][0].request.payload).toEqual(continuation)
    expect(invoke.mock.calls[2][0].request.version).toBe(1)
    expect(invoke.mock.calls[2][0].request.payload).not.toHaveProperty('ownerUserID')
  })

  it.each([undefined, false])('does not invoke unsupported older v1 hosts (%s)', async (supported) => {
    const { adapter, invoke } = native(supported)
    await expect(adapter.discovery.page(request)).rejects.toMatchObject({ code: 'capability_unavailable', recoverable: false })
    expect(invoke).toHaveBeenCalledTimes(1)
  })

  it('passes scoped cached capacity failure without converting it to a successful empty city', async () => {
    const cached = { ...result, refreshStatus: { ...result.refreshStatus, state: 'cached',
      issue: { code: 'DISCOVERY_AGGREGATE_CAPACITY', message: 'No partial ranking.', recoverable: true, details: { status: 503 } } } }
    const { adapter } = native(true, cached)
    const value = await adapter.discovery.page({ ...request, forceRefresh: true })
    expect(value.refreshStatus.state).toBe('cached')
    expect(value.refreshStatus.issue?.code).toBe('DISCOVERY_AGGREGATE_CAPACITY')
    expect(value.nextCursor).toBe(result.nextCursor)
    expect(value.pagination).toBe('more')
    expect(value.engagementState).toBe('unknown')
    expect(value.interactionsAvailable).toBe(false)
  })

  it('preserves rejected cursor scope errors from the host', async () => {
    const { adapter } = native(true, null, { code: 'discovery_cursor_scope_mismatch', message: 'Reload this query.', recoverable: false })
    await expect(adapter.discovery.page({ ...request, cursor: 'foreign', snapshotID: 'foreign' }))
      .rejects.toMatchObject({ code: 'discovery_cursor_scope_mismatch' })
  })

  it('fails closed in Browser rather than creating real-looking cards with local fake social success', async () => {
    const profile = vi.fn(async () => { throw new Error('Discovery must not infer server identity from local profile') })
    const adapter = new TasteMapBrowserAdapter({ profile })
    expect((await adapter.runtime.info()).supportedCapabilities.discoveryPage).toBe(false)
    await expect(adapter.discovery.page(request)).rejects.toMatchObject({ code: 'capability_unavailable' })
    await expect(adapter.discovery.cityPage({ mode: 'following', city: '成都', windowDays: 7 })).rejects.toMatchObject({ code: 'capability_unavailable' })
    expect(profile).not.toHaveBeenCalled()
  })
})
