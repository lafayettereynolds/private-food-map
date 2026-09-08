import { describe, expect, it } from 'vitest'
import { apiURL, resolveAPIBaseURL } from './apiEnvironment'

describe('API environment configuration', () => {
  it('boots production without local configuration', () => {
    expect(resolveAPIBaseURL('production', {})).toBe('https://api.tastemap.cn')
    expect(apiURL('/api/sync', null)).toBe('/api/sync')
  })

  it('selects Development and Production independently', () => {
    const values = {
      VITE_API_DEV_BASE_URL: 'http://127.0.0.1:8788/',
      VITE_API_PROD_BASE_URL: 'https://api.example.test',
    }
    expect(resolveAPIBaseURL('development', values)).toBe('http://127.0.0.1:8788')
    expect(resolveAPIBaseURL('production', values)).toBe('https://api.tastemap.cn')
    expect(apiURL('/api/sync', 'https://api.example.test')).toBe('https://api.example.test/api/sync')
  })

  it('rejects embedded credentials and malformed paths', () => {
    expect(() => resolveAPIBaseURL('development', { VITE_API_DEV_BASE_URL: 'https://user:secret@example.test' })).toThrow()
    expect(() => apiURL('api/sync', null)).toThrow()
  })
})
