import { renderToStaticMarkup as renderMarkup } from 'react-dom/server'
import type { ReactNode } from 'react'
import { PremiumAccessContext } from './PremiumAccess'
const renderToStaticMarkup = (node: ReactNode) => renderMarkup(<PremiumAccessContext.Provider value={true}>{node}</PremiumAccessContext.Provider>)
import { describe, expect, it } from 'vitest'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { RestaurantSummary } from '../types/domain'
import { RestaurantSocialStatsPanel } from './RestaurantSocialStatsPanel'

const restaurantWithoutRating = fixture.restaurants[1] as unknown as RestaurantSummary

describe('RestaurantSocialStatsPanel', () => {
  it('locks similar taste without leaking its score or count for free accounts', () => {
    const markup = renderMarkup(<RestaurantSocialStatsPanel amapPoiId="test" restaurant={restaurantWithoutRating} remoteStatsEnabled={false} socialStats={{ overallUserRating: 8.8, overallUserCount: 36, friendAverageRating: 9.2, friendUserCount: 8, similarTasteAverageRating: 9.7, similarTasteUserCount: 127, repeatVisitRate: 42, repeatVisitorCount: 9, uniqueVisitorCount: 36 }} />)
    expect(markup).toContain('同味评分，会员专享')
    expect(markup).not.toContain('9.7')
    expect(markup).not.toContain('127 个有效样本')
    expect(markup).not.toContain('查看同味评分说明')
    expect(markup).toContain('<strong>9.2</strong>')
  })
  it('uses the shared graphic and 暂无数据 state when 我的评分 is empty', () => {
    const markup = renderToStaticMarkup(
      <RestaurantSocialStatsPanel
        amapPoiId={restaurantWithoutRating.amapPoiId}
        personalRatingOverride={{ score: null, count: 0, label: '我的评分' }}
        remoteStatsEnabled={false}
        restaurant={restaurantWithoutRating}
      />,
    )
    const personal = markup.match(/<button[^>]*class="score-reference-item is-personal is-empty"[\s\S]*?<\/button>/)?.[0] ?? ''

    expect(personal).toContain('class="score-reference-empty"')
    expect(personal).toContain('lucide-ghost')
    expect(personal).toContain('暂无数据')
    expect(personal).toContain('<b>我的评分</b>')
    expect(personal).not.toContain('未评分')
    expect(personal).not.toContain('<strong>—</strong>')
    expect(personal).toContain('aria-label="查看我的评分说明"')
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
    const personal = markup.match(/<button[^>]*class="score-reference-item is-personal"[\s\S]*?<\/button>/)?.[0] ?? ''

    expect(personal).toContain('<strong>8.0</strong>')
    expect(personal).not.toContain('score-reference-empty')
    expect(personal).not.toContain('暂无数据')
    expect(personal).not.toContain('基于你在这家餐厅')
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
    expect(markup).not.toContain('样本较少')
    expect(markup).not.toContain('基于 8 位好友')
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
    const prediction = markup.match(/<button[^>]*class="score-reference-item is-personal is-empty"[\s\S]*?<\/button>/)?.[0] ?? ''

    expect(prediction).toContain('暂无数据')
    expect(prediction).not.toContain('NaN')
    expect(prediction).not.toContain('记录更多评分后生成')
  })

  it('keeps score methodology hidden until a score control is selected', () => {
    const methodology = '基于 154 条历史评分与 61 家相近餐厅推算'
    const markup = renderToStaticMarkup(
      <RestaurantSocialStatsPanel
        amapPoiId={restaurantWithoutRating.amapPoiId}
        personalRatingOverride={{ score: 8.5, count: 154, label: '历史预测', description: methodology }}
        remoteStatsEnabled={false}
        restaurant={restaurantWithoutRating}
        socialStats={{
          overallUserRating: 8.4, overallUserCount: 26,
          friendAverageRating: 9.1, friendUserCount: 9,
          similarTasteAverageRating: 9, similarTasteUserCount: 11,
          repeatVisitRate: 0, repeatVisitorCount: 0, uniqueVisitorCount: 26,
        }}
      />,
    )

    expect(markup).not.toContain(methodology)
    expect(markup).not.toContain('rating-explanation-dialog')
    expect(markup.match(/aria-expanded="false"/g)).toHaveLength(4)
    expect(markup.match(/查看(?:历史预测|全部用户|好友评分|同味评分)说明/g)).toHaveLength(4)
  })
})
