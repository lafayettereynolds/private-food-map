import { Building2 } from 'lucide-react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { TasteMapFilterBar, TasteMapFilterSelect } from './TasteMapDiscoveryShared'

describe('shared intrinsic compact filter select', () => {
  it('provides an explicit single-dimension dialog trigger without changing native consumers', () => {
    const markup = renderToStaticMarkup(<TasteMapFilterSelect presentation="dialog" icon={<Building2 />} label="评价人数" value="" options={[{value:'',label:'评价人数'},{value:'3',label:'至少 3 人评价'}]} onChange={() => {}} />)
    expect(markup).toContain('aria-haspopup="dialog"')
    expect(markup).toContain('aria-label="评价人数"')
    expect(markup).not.toContain('<select')
    expect(markup).not.toContain('至少 3 人评价')
  })
  const options = [{ value: 'all', label: '城市' }, { value: '杭州', label: '杭州' }, { value: 'long', label: '很长的城市名称不应撑大未选中的城市胶囊' }]
  it.each(options)('uses only the current label in the visible layout: $label', ({ value, label }) => {
    const markup = renderToStaticMarkup(<TasteMapFilterBar><TasteMapFilterSelect icon={<Building2 aria-hidden="true" />} label="城市" value={value} options={options} active={value !== 'all'} onChange={() => {}} /></TasteMapFilterBar>)
    expect(markup).toContain(`<span aria-hidden="true" class="tm-filter-select__value">${label}</span>`)
    expect(markup).toContain(`<option value="${value}" selected="">${label}</option>`)
    expect(markup.match(/<select /g)).toHaveLength(1)
    expect(markup.match(/<option /g)).toHaveLength(3)
    expect(markup).toContain('<select aria-label="城市"')
    expect(markup).toContain('tm-filter-select__disclosure')
    expect(markup).not.toContain('style=')
    expect(markup).not.toContain('disabled=')
  })
})
