import { readFileSync } from 'node:fs'
import { describe, expect, it, vi } from 'vitest'
import worker from './index'

describe('public health endpoint', () => {
  it.each([
    {},
    { Origin: 'https://unrelated.example', Authorization: 'Bearer invalid' },
    { Accept: 'text/html', 'Sec-Fetch-Mode': 'navigate' },
  ])('returns exact JSON without accessing auth, database, or assets: %j', async (headers) => {
    const env = new Proxy({}, { get: () => { throw new Error('Health must not access bindings') } })
    const response = await worker.fetch(new Request('https://origin-api.tastemap.cn/health', { headers }), env)
    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toBe('application/json')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(await response.text()).toBe('{"status":"ok"}')
  })

  it('preserves unrelated SPA fallback', async () => {
    const fetch = vi.fn().mockResolvedValue(new Response('existing SPA'))
    const response = await worker.fetch(new Request('https://origin-api.tastemap.cn/other-page'), { ASSETS: { fetch } })
    expect(fetch).toHaveBeenCalledOnce()
    expect(await response.text()).toBe('existing SPA')
  })

  it('routes health to the Worker before Cloudflare SPA fallback', () => {
    const config = JSON.parse(readFileSync('wrangler.jsonc', 'utf8'))
    expect(config.assets.run_worker_first).toContain('/health')
    expect(config.assets.run_worker_first).toContain('/api/*')
    expect(config.d1_databases[0].database_name).toBe('food-map-db')
    expect(config.r2_buckets[0].bucket_name).toBe('taste-map-photos')
  })
})
