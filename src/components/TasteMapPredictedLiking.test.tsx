import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { TasteMapPredictedLiking } from './TasteMapPredictedLiking'
describe('predicted liking presentation', () => {
  it('uses predicted rating units, never a probability or actual rating label', () => {
    const html = renderToStaticMarkup(<TasteMapPredictedLiking value={{ scoreOutOfTen: 8.2, ratedRestaurantCount: 5,
      ratedVisitCount: 8, matchedRestaurantCount: 3, method: 'owner_history_weighted_rating_v1' }} />)
    expect(html).toContain('预计喜欢度 8.2 / 10')
    expect(html).not.toContain('82%')
    expect(html).not.toContain('我的评分')
    expect(html).not.toContain('大家评分')
    expect(html).toContain('aria-haspopup="dialog"')
  })
  it('does not substitute match or public scores for absent prediction', () => {
    expect(renderToStaticMarkup(<TasteMapPredictedLiking />)).toContain('预计喜欢度 积累中')
  })
})
