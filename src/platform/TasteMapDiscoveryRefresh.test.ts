import { describe, expect, it, vi } from 'vitest'
import { TasteMapNativeAdapter } from './TasteMapNativeAdapter'
import { loadTasteMapBrowserDebugFixture } from './TasteMapBrowserDebugFixture'
import { discoveryRefreshMessage } from '../hybrid/app/discoveryRefreshState'
import type { TasteMapBridgeRequestEnvelope, TasteMapHybridContentSnapshotDTO } from './TasteMapPlatform'

const issue = { code: 'DISCOVERY_AGGREGATE_CAPACITY', message: '完整统计容量不足。', recoverable: true, details: { status: 503 } }
const content: TasteMapHybridContentSnapshotDTO = {
  generatedAt: 'now', discovery: { forYou: [], similarTaste: [], trending: [], refreshStatus: {
    for_you: { state: 'cached', city: '杭州', windowDays: 7, sourceGeneratedAt: 'old', attemptedAt: 'now', issue },
  } }, community: { following: [], latest: [] }, lists: [],
}

describe('Discovery structured refresh bridge compatibility', () => {
  it('transports full authorized activity albums through the actual Native content adapter without altering provenance', async () => {
    const { content: multiPhotoContent } = await loadTasteMapBrowserDebugFixture()
    const invoke = vi.fn(async ({ request }: { request: TasteMapBridgeRequestEnvelope<unknown> }) => ({
      version: 1, requestId: request.requestId,
      result: request.method === 'runtime.info' ? { bridgeVersion: 1 } : JSON.parse(JSON.stringify(multiPhotoContent)),
    }))
    const adapter = new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: { invoke } } } } as never)
    const value = await adapter.content.snapshot()
    expect(value.discovery.similarTaste.map((item) => item.activityImages)).toEqual(multiPhotoContent.discovery.similarTaste.map((item) => item.activityImages))
    expect(value.community.latest.map((item) => item.activityImages)).toEqual(multiPhotoContent.community.latest.map((item) => item.activityImages))
    expect(value.community.following.map((item) => item.activityImages)).toEqual(multiPhotoContent.community.following.map((item) => item.activityImages))
    expect(value.discovery.forYou.every((item) => item.activityImages === undefined)).toBe(true)
    expect(value.discovery.trending.every((item) => item.activityImages === undefined)).toBe(true)
  })

  it('preserves per-mode issue, cache provenance, and explicit retry through the real Native adapter', async () => {
    const invoke = vi.fn(async ({ request }: { request: TasteMapBridgeRequestEnvelope<unknown> }) => ({
      version: 1, requestId: request.requestId,
      result: request.method === 'runtime.info' ? { bridgeVersion: 1 } : content,
    }))
    const adapter = new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: { invoke } } } } as never)
    const value = await adapter.content.snapshot({ forceRefresh: true })
    expect(invoke.mock.calls[invoke.mock.calls.length - 1]?.[0].request).toMatchObject({ method: 'content.snapshot', payload: { forceRefresh: true } })
    expect(value.discovery.refreshStatus?.for_you).toEqual(content.discovery.refreshStatus?.for_you)
    expect(discoveryRefreshMessage(value)).toBe('为你推荐：完整统计容量不足。正在显示上次缓存。')
  })

  it('does not invent freshness for legacy payloads or render permission denial as retryable network failure', () => {
    const legacy = { ...content, discovery: { forYou: [], similarTaste: [], trending: [] } }
    expect(discoveryRefreshMessage(legacy)).toBeNull()
    expect(discoveryRefreshMessage({ ...content, discovery: { ...content.discovery, refreshStatus: {
      similar_taste: { state: 'restricted', city: '杭州', windowDays: 7, sourceGeneratedAt: null, attemptedAt: 'now',
        issue: { code: 'discovery_access_required', message: '需要访问权限。', recoverable: false } },
    } } })).toBeNull()
  })
})
