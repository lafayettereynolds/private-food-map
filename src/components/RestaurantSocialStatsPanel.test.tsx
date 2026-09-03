import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import { RestaurantSocialStatsPanel } from './RestaurantSocialStatsPanel'

const restaurantWithoutRating = fixture.restaurants[1] as unknown as RestaurantSummary

describe('RestaurantSocialStatsPanel', () => {
  it('uses the shared graphic and 暂无数据 state when 我的评分 is empty', () => {
    const markup = renderToStaticMarkup(
      <RestaurantSocialStatsPanel
        amapPoiId={restaurantWithoutRating.amapPoiId}
        personalRatingOverride={{ score: null, count: 0, label: '我的评分' }}
        remoteStatsEnabled={false}
        restaurant={restaurantWithoutRating}
      />,
    )
    const personal = markup.match(/<article class="score-reference-item is-personal is-empty">[\s\S]*?<\/article>/)?.[0] ?? ''

    expect(personal).toContain('class="score-reference-empty"')
    expect(personal).toContain('lucide-ghost')
    expect(personal).toContain('暂无数据')
    expect(personal).toContain('<b>我的评分</b>')
    expect(personal).not.toContain('未评分')
    expect(personal).not.toContain('<strong>—</strong>')
  })

  it('keeps a real personal score instead of applying the empty state', () => {
    const markup = renderToStaticMarkup(
      <RestaurantSocialStatsPanel
        amapPoiId={restaurantWithoutRating.amapPoiId}
        personalRatingOverride={{ score: 8, count: 1, label: '我的评分' }}
        remoteStatsEnabled={false}
        restaurant={restaurantWithoutRating}
      />,
    )
    const personal = markup.match(/<article class="score-reference-item is-personal">[\s\S]*?<\/article>/)?.[0] ?? ''

    expect(personal).toContain('<strong>8.0</strong>')
    expect(personal).not.toContain('score-reference-empty')
    expect(personal).not.toContain('暂无数据')
  })

  it('normalizes an invalid prediction into the same visual no-data state', () => {
    const markup = renderToStaticMarkup(
      <RestaurantSocialStatsPanel
        amapPoiId={restaurantWithoutRating.amapPoiId}
        personalRatingOverride={{ score: Number.NaN, count: 0, label: '历史预测', description: '记录更多评分后生成' }}
        remoteStatsEnabled={false}
        restaurant={restaurantWithoutRating}
      />,
    )
    const prediction = markup.match(/<article class="score-reference-item is-personal is-empty">[\s\S]*?<\/article>/)?.[0] ?? ''

    expect(prediction).toContain('暂无数据')
    expect(prediction).not.toContain('NaN')
    expect(prediction).not.toContain('记录更多评分后生成')
  })
})
