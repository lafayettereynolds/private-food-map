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

  it('renders adapter-owned community, friend and similar-taste scores together', () => {
    const markup = renderToStaticMarkup(
      <RestaurantSocialStatsPanel
        amapPoiId={restaurantWithoutRating.amapPoiId}
        personalRatingOverride={{ score: 9, count: 2, label: '我的评分' }}
        remoteStatsEnabled={false}
        restaurant={restaurantWithoutRating}
        socialStats={{
          overallUserRating: 8.8, overallUserCount: 36,
          friendAverageRating: 9.2, friendUserCount: 8,
          similarTasteAverageRating: 9.0, similarTasteUserCount: 12,
          repeatVisitRate: 42, repeatVisitorCount: 9, uniqueVisitorCount: 36,
        }}
      />,
    )

    for (const [label, score, count] of [
      ['全部用户', '8.8', '36'], ['好友评分', '9.2', '8'], ['同味评分', '9.0', '12'],
    ]) {
      expect(markup).toContain(`<strong>${score}</strong>`)
      expect(markup).toContain(`<b>${label}</b>`)
      expect(markup).toContain(`aria-label="${count} 个有效样本"`)
    }
    expect(markup).not.toContain('暂无数据')
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
