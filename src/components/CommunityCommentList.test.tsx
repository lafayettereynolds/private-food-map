import { renderToStaticMarkup } from 'react-dom/server'
import nativeComments from '../../ios/TasteMap/TasteMap/Features/Community/CommunityInteractionViews.swift?raw'
import nativeProjection from '../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridBridgeService.swift?raw'
import discoverySource from '../hybrid/app/HybridDiscoveryPage.tsx?raw'
import { describe, expect, it } from 'vitest'
import { CommunityCommentList } from './CommunityCommentList'
import { loadTasteMapBrowserDebugFixture } from '../platform/TasteMapBrowserDebugFixture'

describe('remote comments distinguish content, empty, loading and failure', () => {
  const render = (loading: boolean, error: string | null) => renderToStaticMarkup(
    <CommunityCommentList items={[]} loading={loading} error={error} onRetry={() => {}} />,
  )
  it('keeps a retryable failure visible instead of claiming there are no comments', () => {
    const html = render(false, '评论暂时无法加载，请重试。')
    expect(html).toContain('role="alert"')
    expect(html).toContain('重试加载评论')
    expect(html).not.toContain('还没有评论')
  })
  it('does not flash an empty state while reading', () => {
    expect(render(true, null)).toContain('正在加载评论')
    expect(render(true, null)).not.toContain('还没有评论')
    expect(render(false, null)).toContain('还没有评论')
  })
  it('keeps Native rollback failures distinct and both fixture producers compatible with the Native validator', () => {
    const native = nativeComments
    expect(native.indexOf('comments.isEmpty, let loadError')).toBeLessThan(native.indexOf('} else if comments.isEmpty {'))
    expect(native).toContain('community-comments-retry')
    expect(native).toContain('catch { loadError =')
    const projection = nativeProjection
    expect(projection).toContain('visitID: "demo-visit-similar-')
    expect(projection).not.toContain('demo-similar-visit-')
  })
  it('preserves the card return position', () => {
    const discovery = discoverySource
    expect(discovery).toContain('commentReturnScroll.current = { top: window.scrollY, left: window.scrollX }')
    expect(discovery).toContain('window.scrollTo({ ...commentReturnScroll.current')
  })
  it('renders the actual comment collection of a Same Taste Visit', async () => {
    const fixture = await loadTasteMapBrowserDebugFixture()
    const item = fixture.content.discovery.similarTaste[0]
    const target = item.interaction!
    const comments = fixture.commentsByVisit[target.visitID]
    expect(target.visitID).toMatch(/^demo-visit-similar-/)
    expect(comments).toHaveLength(item.commentCount)
    expect(comments.every((comment) => comment.visitID === target.visitID)).toBe(true)
    const html = renderToStaticMarkup(<CommunityCommentList items={comments} loading={false} error={null} onRetry={() => {}} />)
    for (const comment of comments) expect(html).toContain(comment.body)
    expect(html).not.toContain('还没有评论')
  })
})
