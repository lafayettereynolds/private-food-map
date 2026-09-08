import { renderToStaticMarkup } from 'react-dom/server'
import { describe, it, expect } from 'vitest'
import { FilterChoiceGroup } from './MyMapBrowsePage'
import { PremiumAccessContext } from './PremiumAccess'

describe('premium filter choices', () => {
  const options = Array.from({ length: 12 }, (_, i) => [`p${i}`, `饭搭子${i}`])
  it('keeps locks and direct buttons, never a dropdown or add-custom action', () => {
    const html = renderToStaticMarkup(<FilterChoiceGroup premiumOnly label="饭搭子" value="" options={options} onSelect={() => {}} />)
    expect(html).toContain('会员专享')
    expect(html).toContain('更多')
    expect(html).not.toContain('<select')
    expect(html).not.toContain('自定义')
    expect(html).not.toContain('饭搭子11')
  })
  it('keeps selected overflow choices visible for members', () => {
    const html = renderToStaticMarkup(<PremiumAccessContext.Provider value={true}><FilterChoiceGroup premiumOnly label="饭搭子" value="p11" options={options} onSelect={() => {}} /></PremiumAccessContext.Provider>)
    expect(html).toContain('饭搭子11')
    expect(html).toContain('aria-pressed="true"')
    expect(html).not.toContain('会员专享')
  })
})
