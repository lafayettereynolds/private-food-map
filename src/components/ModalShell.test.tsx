import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { ModalShell } from './ModalShell'

describe('ModalShell dismissal ownership', () => {
  it('replaces close with exactly one shared back icon for an editor', () => {
    const html = renderToStaticMarkup(<ModalShell dismissAction="back" onClose={() => {}} title="编辑资料"><p>资料</p></ModalShell>)
    expect(html.match(/<button\b/g)).toHaveLength(1)
    expect(html.match(/aria-label="返回上一页"/g)).toHaveLength(1)
    expect(html).not.toContain('aria-label="关闭"')
    expect(html).not.toContain('取消')
  })
  it('keeps save-in-progress exit disabled', () => {
    const html = renderToStaticMarkup(<ModalShell dismissAction="back" dismissDisabled onClose={() => {}} title="编辑资料"><p>保存中</p></ModalShell>)
    expect(html).toMatch(/<button[^>]*aria-label="返回上一页"[^>]*disabled=""/)
  })
  it('preserves the existing close-only contract for unrelated modal sheets', () => {
    const html = renderToStaticMarkup(<ModalShell onClose={() => {}} title="提示"><p>内容</p></ModalShell>)
    expect(html.match(/aria-label="关闭"/g)).toHaveLength(1)
    expect(html).not.toContain('返回上一页')
    expect(html).toContain('私人餐厅库')
  })
  it('allows public recommendation explanations to name their own context', () => {
    const html = renderToStaticMarkup(<ModalShell eyebrow="推荐依据" onClose={() => {}} title="推荐理由"><p>原始理由</p></ModalShell>)
    expect(html).toContain('class="eyebrow">推荐依据</span>')
    expect(html).not.toContain('私人餐厅库')
  })
  it('can hide a context label without changing the modal title or close action', () => {
    const html = renderToStaticMarkup(<ModalShell eyebrow={null} onClose={() => {}} title="说明"><p>内容</p></ModalShell>)
    expect(html).not.toContain('eyebrow')
    expect(html).toContain('id="modal-title">说明</h2>')
    expect(html).toContain('aria-label="关闭"')
  })
})
