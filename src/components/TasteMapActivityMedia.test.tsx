import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { TasteMapActivityMedia } from './TasteMapActivityMedia'
import { TasteMapActivityCardFrame } from './TasteMapDiscoveryShared'
import { visitActivityMedia } from './activityMedia'
import discoverySource from '../hybrid/app/HybridDiscoveryPage.tsx?raw'
import communitySource from './CommunityPage.tsx?raw'

describe('one compact activity photo layout for Similar Taste and Latest', () => {
  it.each([1, 2, 3, 4, 5, 6, 7, 9])('retains all %s actual photos without repeating placeholders', count => {
    const html = renderToStaticMarkup(<TasteMapActivityMedia name="测试餐厅" onOpen={() => {}}
      images={Array.from({ length: count }, (_, index) => <img key={index} src={`/real-${index}.jpg`} alt={`照片 ${index + 1}`} />)} />)
    expect(html.match(/class="tm-activity-media__tile"/g)).toHaveLength(count)
    expect(html).toContain(`data-columns="${count < 3 ? count : count === 4 ? 2 : 3}"`)
    expect(html).toContain(`data-photo-count="${count}"`)
    for (let index = 0; index < count; index++) expect(html).toContain(`/real-${index}.jpg`)
    expect(html).not.toContain('展开全部')
  })

  it('keeps larger histories accessible without making the initial card unbounded', () => {
    const html = renderToStaticMarkup(<TasteMapActivityMedia name="测试餐厅" onOpen={() => {}}
      images={Array.from({ length: 20 }, (_, i) => <img key={i} src={`/real-${i}.jpg`} alt="照片" />)} />)
    expect(html.match(/class="tm-activity-media__tile"/g)).toHaveLength(9)
    expect(html).toContain('展开全部 20 张照片')
    expect(html).toContain('aria-expanded="false"')
  })

  it('marks only multiple-photo containers for expansion and never makes same taste a recommendation banner', () => {
    const html = renderToStaticMarkup(<TasteMapActivityCardFrame variant="activity" mediaCount={2}
      media={<div>照片</div>} restaurant={<span>店名</span>} restaurantActions={<button>记录</button>} />)
    expect(html).toContain('tm-activity-card is-activity')
    expect(html).toContain('tm-activity-card__media has-multiple')
    expect(discoverySource).toContain("variant={item.mode === 'similar_taste' ? 'activity' : 'recommendation'}")
    expect(discoverySource.match(/<TasteMapActivityMedia /g)).toHaveLength(2)
  })

  it('does not lose ID-only Visit photos or invent a second image', () => {
    expect(visitActivityMedia([], ['a', 'b'])).toEqual([{ source: '', photoId: 'a' }, { source: '', photoId: 'b' }])
    expect(visitActivityMedia(['one', 'one'], ['a', 'a'])).toHaveLength(1)
    expect(visitActivityMedia([null, 'two'], ['a', null])).toEqual([{ source: '', photoId: 'a' }, { source: 'two', photoId: null }])
    expect(visitActivityMedia([], [])).toEqual([])
    const ids = Array.from({ length: 7 }, (_, index) => `id-${index}`)
    expect(visitActivityMedia([], ids).map(photo => photo.photoId)).toEqual(ids)
    expect(communitySource).toContain('additionalUserPhotos={visitActivityMedia(selectedItem.visit.photos, selectedItem.visit.photoIds)}')
  })
})
