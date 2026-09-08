import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { TasteMapCitySearch, discoveryCityQuery } from './TasteMapCitySearch'

describe('shared discovery city search', () => {
  it.each([[' 杭州市 ', '杭州市'], ['成都', '成都'], ['温州', '温州'], [' New  York ', 'New York'], ['', '']])('normalizes query %s without inventing local-list membership', (input, expected) => {
    expect(discoveryCityQuery(input)).toBe(expected)
  })
  it('matches optional 市 aliases while retaining the existing server spelling', () => {
    expect(discoveryCityQuery('杭州', ['杭州市'])).toBe('杭州市')
    expect(discoveryCityQuery('杭州市', ['杭州'])).toBe('杭州')
    expect(discoveryCityQuery('成都', ['杭州市'])).toBe('成都')
  })
  it('offers a search dialog rather than a select restricted to loaded cities', () => {
    const html = renderToStaticMarkup(<TasteMapCitySearch city="" suggestions={['杭州']} onChange={() => {}} />)
    expect(html).toContain('搜索城市')
    expect(html).toContain('aria-haspopup="dialog"')
    expect(html).not.toContain('<select')
  })
  it('retains a city absent from the loaded suggestions', () => {
    const html = renderToStaticMarkup(<TasteMapCitySearch city="成都" suggestions={['杭州']} onChange={() => {}} />)
    expect(html).toContain('当前成都')
    expect(html).toContain('is-active')
  })
})
