import { describe, expect, it, vi } from 'vitest'
import { ExternalLinkResolveError, parseKnownRestaurantUrl, resolveExternalRestaurantEvidence, validateExternalRestaurantUrl } from './externalRestaurantLinkResolver'

describe('external restaurant link resolver', () => {
  it('parses an Amap marker URL without fetching it', async () => {
    const fetcher = vi.fn<typeof fetch>()
    const result = await resolveExternalRestaurantEvidence({
      url: 'https://uri.amap.com/marker?position=120.1551,30.2741&name=%E6%A1%82%E8%AF%AD%E5%B1%B1%E6%88%BF&address=%E6%BB%A1%E8%A7%89%E9%99%87%E8%B7%AF',
      currentCity: '杭州市',
    }, fetcher)
    expect(result).toMatchObject({ sourceType: 'amap', name: '桂语山房', city: '杭州市', latitude: 30.2741, longitude: 120.1551 })
    expect(fetcher).not.toHaveBeenCalled()
  })

  it('parses an Apple Maps restaurant URL as medium confidence evidence', () => {
    const result = parseKnownRestaurantUrl(new URL('https://maps.apple.com/?q=Din%20Tai%20Fung&address=Broadway%2C%20New%20York&ll=40.758,-73.9855'))
    expect(result).toMatchObject({ sourceType: 'apple_maps', name: 'Din Tai Fung', latitude: 40.758, longitude: -73.9855, confidence: 'MEDIUM' })
  })

  it('extracts a restaurant from generic JSON-LD', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(`
      <html><script type="application/ld+json">{"@type":"Restaurant","name":"小满手工粉","address":{"streetAddress":"武林路 18 号","addressLocality":"杭州"},"geo":{"latitude":30.27,"longitude":120.16}}</script></html>
    `, { headers: { 'content-type': 'text/html; charset=utf-8' } }))
    const result = await resolveExternalRestaurantEvidence({ url: 'https://example.com/restaurants/xiaoman' }, fetcher)
    expect(result).toMatchObject({ name: '小满手工粉', address: '武林路 18 号 杭州', city: '杭州', confidence: 'MEDIUM' })
  })

  it('blocks localhost and private network URLs before fetching', async () => {
    expect(() => validateExternalRestaurantUrl('https://127.0.0.1/admin')).toThrow(ExternalLinkResolveError)
    expect(() => validateExternalRestaurantUrl('https://192.168.1.5/place')).toThrow(ExternalLinkResolveError)
    await expect(resolveExternalRestaurantEvidence({ url: 'http://example.com/place' })).rejects.toMatchObject({ status: 400 })
  })

  it('validates every redirect target', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(null, { status: 302, headers: { location: 'https://169.254.169.254/latest/meta-data' } }))
    await expect(resolveExternalRestaurantEvidence({ url: 'https://example.com/short' }, fetcher)).rejects.toMatchObject({ status: 400 })
  })

  it('keeps plain shared text as low-confidence search evidence', async () => {
    const result = await resolveExternalRestaurantEvidence({ text: '西湖边的桂语山房', currentCity: '杭州' })
    expect(result).toMatchObject({ sourceType: 'shared_text', name: '西湖边的桂语山房', city: '杭州', confidence: 'LOW' })
  })
})
