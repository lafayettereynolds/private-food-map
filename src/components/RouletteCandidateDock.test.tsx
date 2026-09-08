import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import native from '../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridMapSurface.swift?raw'
import hybridShell from '../hybrid/app/HybridAppShell.tsx?raw'
import browserShell from '../App.tsx?raw'
import { RouletteCandidateDock } from './RouletteCandidateDock'

const handlers = {
  onExpandedChange: () => undefined,
  onRemove: () => undefined,
  onClear: () => undefined,
  onOpen: () => undefined,
}

describe('RouletteCandidateDock', () => {
  it('reserves separate space for Add in both shared map hosts', () => {
    expect(native).toContain('path.subtracting(')
    expect(native).not.toContain('mask.fillRule = .evenOdd')
  })
  it('shows the shared session dock on Map and Discovery in both hosts', () => {
    expect(hybridShell).toContain("route.surface === 'map' || route.surface === 'discovery'")
    expect(browserShell).toContain("activeView === 'map' || activeView === 'community'")
    const action = hybridShell.split('const openDiscoveryRoulette =')[1].split('const toggleDetailRoulette')[0]
    expect(action).not.toContain('navigate(')
  })
  it('stays absent until the current session has a candidate', () => {
    expect(renderToStaticMarkup(<RouletteCandidateDock candidates={[]} expanded={false} {...handlers} />)).toBe('')
  })

  it('shows the real count and keeps spin disabled for one candidate', () => {
    const markup = renderToStaticMarkup(<RouletteCandidateDock
      candidates={[{ id: 'restaurant-1', name: '春日泰味' }]}
      expanded
      {...handlers}
    />)
    expect(markup).toContain('data-product-contract="map-roulette-candidate-dock"')
    expect(markup).toContain('已选 1/10')
    expect(markup).toContain('当前候选')
    expect(markup).toContain('春日泰味')
    expect(markup).toContain('至少再选 1 家餐厅才能开始抽')
    expect(markup).toMatch(/<button[^>]*disabled=""[^>]*title="至少选择 2 家餐厅"/)
  })

  it('enables the same-pool spin action at two candidates', () => {
    const markup = renderToStaticMarkup(<RouletteCandidateDock
      candidates={[{ id: 'restaurant-1', name: '春日泰味' }, { id: 'restaurant-2', name: '青岚寿司' }]}
      expanded={false}
      {...handlers}
    />)
    expect(markup).toContain('已选 2/10')
    expect(markup).toContain('title="开始抽"')
    expect(markup).not.toContain('disabled=""')
  })
})
