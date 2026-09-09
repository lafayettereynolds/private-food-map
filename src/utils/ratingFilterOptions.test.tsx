import communitySource from '../components/CommunityPage.tsx?raw'
import discoverySource from '../hybrid/app/HybridDiscoveryPage.tsx?raw'
import mapSource from '../components/MyMapBrowsePage.tsx?raw'
import nativeSource from '../../ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift?raw'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { MapFilterBar } from '../components/MyMapBrowsePage'
import { DISCOVERY_RATING_FILTER_THRESHOLDS, minimumRatingFilterLabel, RATING_FILTER_THRESHOLDS } from './ratingFilterOptions'

describe('complete minimum-rating filters', () => {
  it('offers every supported integer score and retains the Discovery 7.5 shortcut', () => {
    expect(RATING_FILTER_THRESHOLDS).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    expect(DISCOVERY_RATING_FILTER_THRESHOLDS).toEqual([1, 2, 3, 4, 5, 6, 7, 7.5, 8, 9, 10])
    expect(minimumRatingFilterLabel(1)).toBe('1 分以上')
    expect(minimumRatingFilterLabel(7.5)).toBe('7.5 分以上')
    expect(minimumRatingFilterLabel(10)).toBe('10 分')
  })

  it('renders the real Map/List select with all ten scores, clear and current selection', () => {
    for (const minimumScoreOutOfTen of [undefined, ...RATING_FILTER_THRESHOLDS]) {
      const markup = renderToStaticMarkup(<MapFilterBar
        activeCount={minimumScoreOutOfTen == null ? 0 : 1}
        filters={{ minimumScoreOutOfTen }} onChange={() => {}} onOpenAll={() => {}}
        options={{ cities: [], companions: [], cuisines: [], recommendationSources: [] }}
        search="" setSearch={() => {}} sort="recent" setSort={() => {}}
      />)
      const select = markup.match(/<select aria-label="评分"[^>]*>(.*?)<\/select>/)?.[1] ?? ''
      expect([...select.matchAll(/<option value="([^"]*)"/g)].map((match) => match[1]))
        .toEqual(['', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'])
      expect(select).toContain('不限评分')
      expect(select).toContain(`value="${minimumScoreOutOfTen ?? ''}" selected=""`)
    }
  })

  it('keeps every threshold consumer on the shared policy rather than four high-score literals', () => {
    for (const text of [communitySource, discoverySource]) {
      expect(text).toContain('DISCOVERY_RATING_FILTER_THRESHOLDS.map')
      expect(text).toContain('minimumRatingFilterLabel')
    }
    expect(mapSource).not.toContain("options={['6', '7', '8', '9']}")
    expect(nativeSource).toContain('TasteMapRatingFilterOptions.discoveryThresholdsOutOfTen')
    expect(nativeSource).toContain('Double?.some(score)')
    expect(nativeSource).toContain('$filters.minimumPredictedLikingOutOfTen')
    expect(nativeSource).toContain('$filters.minimumTasteMatchPercent')
    expect(nativeSource).not.toContain('Double?.some(score / 2)')
    expect(nativeSource).not.toContain('Text("社区评分")')
  })
})
