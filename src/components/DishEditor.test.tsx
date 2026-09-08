import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { DishEditor } from './DishEditor'

describe('free dish entry', () => {
  it('always exposes an enabled, explicit add-dish action without requiring photos', () => {
    const html = renderToStaticMarkup(<DishEditor value={[]} onChange={() => {}} canUploadPhotos={false} />)
    const action = html.match(/<button aria-label="添加菜品"[\s\S]*?<\/button>/)?.[0]
    expect(action).toContain('添加菜品')
    expect(action).not.toContain('disabled')
    expect(html).not.toContain('type="file"')
  })
})
