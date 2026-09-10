// Local test harness only. Not imported by any application entry point.
import { createRoot } from 'react-dom/client'
import { useState } from 'react'
import { UGCSafetyMenu } from '../../src/components/UGCSafetyMenu'
import { CommunityCommentList } from '../../src/components/CommunityCommentList'
import type { TasteMapPlatform, TasteMapHybridEvent } from '../../src/platform/TasteMapPlatform'
import { TasteMapActivityCardFrame } from '../../src/components/TasteMapDiscoveryShared'
import { HybridRestaurantImage } from '../../src/components/TasteMapHybridShared'
import type { TasteMapImageDescriptor, TasteMapImageResolutionDTO } from '../../src/platform/TasteMapPlatform'
import '../../src/styles/global.css'

const listeners = new Set<(event: TasteMapHybridEvent) => void>()
const log: string[] = []
let fail = false
let releaseDelete: (() => void) | undefined
const platform = {
  events: { subscribe: async (listener: (event: TasteMapHybridEvent) => void) => { listeners.add(listener); return { remove: async () => { listeners.delete(listener) } } } },
  community: {
    safety: async ({ id }: { id: string }) => ({ ownerID: id === 'own' ? 'viewer' : 'other', canDelete: id === 'own', canReport: id !== 'own', canBlock: id !== 'own' }),
    report: async () => { log.push('report'); if (fail) throw new Error('测试：服务端拒绝'); return { status: 'pending' } },
    block: async () => { log.push('block'); return { blocked: true } },
    deleteComment: async () => { log.push('delete'); await new Promise<void>(resolve => { releaseDelete = resolve }); if (fail) throw new Error('测试：删除失败'); return { deleted: true } },
  },
} as unknown as TasteMapPlatform
const comments = ['own', 'other'].map(id => ({ id, visitID: 'visit', body: `${id} 评论正文`, author: { id: id === 'own' ? 'viewer' : 'other', name: id === 'own' ? '本人' : '另一位食客', city: null, avatarPhotoID: null, avatarPresetID: 'polar-bear', isFollowing: false }, createdAt: '2026-09-10' }))
const photoResolution: TasteMapImageResolutionDTO = {
  sources: ['missing', 'fallback'].map(id => ({ kind: 'publicUGC', photoID: id, visitID: `visit-${id}`, sourceOwnerID: 'other', restaurantID: 'restaurant', visibility: 'public', exportAllowed: false, attributionRequired: true, accessibilityLabel: '照片降级测试',
    resourceURL: id === 'missing' ? '/missing-ugc-image.png' : 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=' })),
  fallback: { kind: 'foodCategoryVisual', categoryVisualID: 'chinese', stableSeed: 'test', accessibilityLabel: '插画', exportAllowed: false },
}
function PhotoProbe() {
  const [selected, setSelected] = useState<TasteMapImageDescriptor | null>(null)
  return <section><HybridRestaurantImage appearance="content" name="照片降级" resolution={photoResolution} onResolved={setSelected} /><output data-testid="photo-target">{selected && 'visitID' in selected ? selected.visitID : ''}</output></section>
}
function Harness() {
  const [revision, reset] = useState(0)
  return <main style={{ maxWidth: 420, margin: 'auto' }}>
    <button onClick={() => { fail = !fail }}>Toggle failure</button><button onClick={() => releaseDelete?.()}>Finish delete</button>
    <button onClick={() => listeners.forEach(listener => listener({ version: 1, sequence: 1, name: 'auth.changed', payload: { state: 'signedOut', userID: null, displayName: null } }))}>Switch account</button>
    <button onClick={() => reset(revision + 1)}>Rerender</button><button onClick={() => { document.querySelector('#log')!.textContent = log.join(',') }}>Read log</button><output id="log" />
    <TasteMapActivityCardFrame variant="activity" header={<strong>另一位食客 · 公开到访</strong>} restaurant={<strong>本地安全测试餐厅</strong>}
      safetyAction={<UGCSafetyMenu platform={platform} target={{ type: 'visit', id: 'visit' }} />}
      body={<p>这是一条用于验证正式共享组件的安全本地测试记录。</p>}
      restaurantActions={<>记录 ｜ 想吃 ｜ 轮盘</>} socialActions={<>点赞 ｜ 评论 ｜ 分享</>} />
    <CommunityCommentList items={comments} platform={platform} loading={false} error={null} onRetry={() => {}} />
    <PhotoProbe />
  </main>
}
createRoot(document.getElementById('root')!).render(<Harness />)
