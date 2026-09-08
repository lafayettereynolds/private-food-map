import { describe, expect, it, vi } from 'vitest'
import { withProductionCORS } from './productionBoundary'
import worker from './index'

describe('production authentication and origin boundary', () => {
  it('allows the formal Browser preflight without a wildcard', async () => {
    const next = vi.fn()
    const response = await withProductionCORS(new Request('https://api.tastemap.cn/api/v1/sync/pull', {
      method: 'OPTIONS', headers: { Origin: 'https://tastemap.cn', 'Access-Control-Request-Headers': 'authorization,content-type' },
    }), next)
    expect(response.status).toBe(204)
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://tastemap.cn')
    expect(next).not.toHaveBeenCalled()
  })
  it('does not grant cross-origin privileges to another site', async () => {
    const response = await withProductionCORS(new Request('https://api.tastemap.cn/api/v1/sync/pull', {
      headers: { Origin: 'https://attacker.example' },
    }), async () => new Response('denied', { status: 403 }))
    expect(response.headers.has('Access-Control-Allow-Origin')).toBe(false)
  })
  it.each(['/api/sync', '/api/v1/sync/pull', '/internal/premium'])(
    'rejects forged Access headers without a Taste Map session: %s', async path => {
      const database = new Proxy({}, { get: () => { throw Error('Unauthenticated request touched DB') } })
      const response = await worker.fetch(new Request(`https://api.tastemap.cn${path}`, {
        headers: { 'Cf-Access-Authenticated-User-Email': 'admin@example.test', 'Cf-Access-Jwt-Assertion': 'forged' },
      }), { APP_ENVIRONMENT: 'production', DB: database } as never)
      expect(response.status).toBe(401)
    },
  )
})
