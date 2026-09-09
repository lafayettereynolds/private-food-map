import { afterEach, expect, it, vi } from 'vitest'
import appleNodeFetch, { Headers } from './appleNodeFetch'

afterEach(() => vi.unstubAllGlobals())
it('preserves binary OCSP bytes and node-fetch buffer contract', async () => {
  const bytes = new Uint8Array([0, 128, 255, 48])
  const fetch = vi.fn<typeof globalThis.fetch>(async () => new Response(bytes))
  vi.stubGlobal('fetch', fetch)
  const headers = new Headers({ 'Content-Type': 'application/ocsp-request' })
  const response = await appleNodeFetch('https://ocsp.apple.com', { method: 'POST', headers, body: bytes, timeout: 30_000 })
  expect([...await response.buffer()]).toEqual([...bytes])
  expect(fetch.mock.calls[0][1]).toMatchObject({ method: 'POST', headers, body: bytes, signal: expect.any(AbortSignal) })
  expect(fetch.mock.calls[0][1]).not.toHaveProperty('timeout')
})
it('does not turn HTTP rejection into success or retry without checks', async () => {
  const fetch = vi.fn(async () => new Response(null, { status: 503 }))
  vi.stubGlobal('fetch', fetch)
  expect((await appleNodeFetch('https://ocsp.apple.com')).ok).toBe(false)
  expect(fetch).toHaveBeenCalledTimes(1)
})
it('propagates network failures', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('network unavailable') }))
  await expect(appleNodeFetch('https://ocsp.apple.com')).rejects.toThrow('network unavailable')
})
