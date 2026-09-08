import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { VisitPhotoPicker } from './VisitPhotoPicker'

describe('Visit photo picker entitlement', () => {
  it('defaults to two and retains every historical image without an upload slot', () => {
    const html = renderToStaticMarkup(<VisitPhotoPicker value={['a', 'b', 'c']} photoIds={[]} onChange={() => {}} upgradeAvailable />)
    expect(html).toContain('3 / 2 张')
    expect((html.match(/<figure/g) ?? []).length).toBe(3)
    expect(html).not.toContain('type="file"')
    expect(html).toContain('Premium 每次到访可上传 20 张照片')
  })
  it('accounts for dish photos and retains the twenty-photo member allowance', () => {
    const free = renderToStaticMarkup(<VisitPhotoPicker value={['a']} photoIds={[]} totalPhotoCount={2} onChange={() => {}} />)
    expect(free).toContain('2 / 2 张')
    expect(free).not.toContain('type="file"')
    const member = renderToStaticMarkup(<VisitPhotoPicker value={['a', 'b', 'c']} photoIds={[]} maxPhotos={20} onChange={() => {}} />)
    expect(member).toContain('3 / 20 张')
    expect(member).toContain('type="file"')
  })
})
