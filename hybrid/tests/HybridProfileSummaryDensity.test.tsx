import { readFileSync } from 'node:fs'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import fixture from '../fixtures/profile-restaurant-rich.json'
import { ProfilePage } from '../../src/components/ProfilePage'
import type { RestaurantSummary, UserProfile, Visit } from '../../src/types/domain'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))

const source = (name: string) => readFileSync(new URL(name, import.meta.url), 'utf8')
const css = source('../../src/styles/global.css')

describe('compact owner Profile statistics template', () => {
  it('preserves the three complete values, drill-down controls and surrounding order', () => {
    for (const populated of [false, true]) {
      const html = renderToStaticMarkup(<ProfilePage
        user={fixture.profile.user as unknown as UserProfile}
        restaurants={populated ? fixture.restaurants as unknown as RestaurantSummary[] : []}
        visits={populated ? fixture.restaurants.flatMap((restaurant) => restaurant.visits) as unknown as Visit[] : []}
      />)
      const statistics = html.match(/class="profile-dashboard__counts profile-dashboard__counts--primary">([\s\S]*?)<\/div>/)?.[1] ?? ''
      expect([...statistics.matchAll(/<small>([^<]*)<\/small>/g)].map((match) => match[1])).toEqual(['去过', '想去', '总消费'])
      expect(statistics.match(/<button /g)).toHaveLength(3)
      expect(statistics).toContain('class="is-currency"')
      expect(statistics).toContain('data-tastemap-semantic-icon="visited"')
      expect(html).toContain('profile-dashboard__identity')
      expect(html.indexOf('profile-dashboard__identity')).toBeLessThan(html.indexOf('profile-dashboard__counts--primary'))
      expect(html.indexOf('profile-dashboard__counts--primary')).toBeLessThan(html.indexOf('profile-quick-actions'))
      expect(html).toContain('今天吃什么')
      expect(html).toContain('我的口味档案')
    }
  })

  it('uses one compact spacing scale without shrinking typography or interactive targets', () => {
    for (const [token, value] of Object.entries({
      'identity-gap': 8,
      'statistic-inset': 4,
      'statistic-min-height': 44,
      'next-gap': 10,
    })) expect(css).toContain(`--profile-summary-${token}: ${value}px;`)
    expect(css).toMatch(/\.profile-dashboard--owner \.profile-dashboard__header \{[^}]*padding-bottom: var\(--profile-summary-identity-gap\);/)
    expect(css).toMatch(/\.profile-dashboard__counts\.profile-dashboard__counts--primary > button \{[^}]*min-height: var\(--profile-summary-statistic-min-height\);/)
    expect(css).toMatch(/\.profile-dashboard--owner \.profile-dashboard__hero \{[^}]*padding-bottom: 0;/)
    expect(css).toMatch(/\.profile-dashboard--owner \.profile-dashboard__hero \+ \.profile-quick-actions \{[^}]*margin-top: var\(--profile-summary-next-gap\);/)
    const primaryRules = [...css.matchAll(/\.profile-dashboard__counts--primary \{([^}]*)\}/g)].map((match) => match[1])
    expect(primaryRules.filter((rule) => rule.includes('padding-block: var(--profile-summary-statistic-inset)'))).toHaveLength(2)
    expect(primaryRules.some((rule) => /(?:padding|margin-bottom):\s*[1-9]/.test(rule))).toBe(false)
    expect(css).toContain('.profile-dashboard__counts > button.is-currency strong { font-size: 17px; letter-spacing: -.025em; white-space: nowrap; }')
    expect(css).toContain('.profile-dashboard__counts > button.is-currency strong { font-size: 14px; }')
    expect(css).toContain('.profile-dashboard__counts--primary { grid-template-columns: minmax(0, .86fr) minmax(0, .86fr) minmax(0, 1.28fr); }')
  })

  it('keeps Native rollback and all owner previews on the same summary template', () => {
    const native = source('../../ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift')
    const tokens = source('../../ios/TasteMap/TasteMap/Components/TasteMapDesignTokens.swift')
    expect(native.match(/ProfileSummaryTemplate\(showsStatistics:/g)).toHaveLength(2)
    expect(native).toContain('statistics.padding(.top, TasteMapDesignTokens.ProfileSummary.identityGap)')
    expect(native).toContain('actions.padding(.top, TasteMapDesignTokens.ProfileSummary.nextGap)')
    const statistics = native.slice(native.indexOf('private struct ProfileStatisticsSection'), native.indexOf('private struct ProfileDashboardSection'))
    expect(statistics).toContain('.padding(.vertical, TasteMapDesignTokens.ProfileSummary.statisticInset)')
    expect(statistics).toContain('minHeight: TasteMapDesignTokens.ProfileSummary.statisticMinimumHeight')
    expect(statistics).not.toContain('minHeight: 42')
    expect(statistics).not.toContain('.padding(.vertical, 8)')
    expect(statistics).toContain('dynamicTypeSize.isAccessibilitySize')
    expect(tokens).toContain('static let statisticMinimumHeight = Control.minimumHitTarget')
    expect(tokens).toContain('static let statisticInset = Spacing.xSmall')
  })
})
