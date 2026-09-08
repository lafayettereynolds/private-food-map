import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

describe('Shared Not Interested icon contract', () => {
  it('exposes dismissal only on For You cards, never Restaurant details', () => {
    const detail = readFileSync('src/components/RestaurantPreviewCard.tsx', 'utf8')
    const nativeDetail = readFileSync('ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailView.swift', 'utf8')
    const discovery = readFileSync('ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift', 'utf8')
    expect(detail).not.toContain('RecommendationNotInterested')
    expect(nativeDetail).not.toContain('RestaurantNotInterestedButton')
    expect(discovery.match(/RestaurantNotInterestedButton\(/g)).toHaveLength(1)
    expect(discovery).toContain('if card.mode == .forYou {\n                RestaurantNotInterestedButton')
    expect(readFileSync('src/hybrid/app/HybridDiscoveryPage.tsx', 'utf8')).toContain("item.mode === 'for_you' ? <RecommendationNotInterested")
  })
  it('retains 44-point targets and Native icon-only parity without a fourth action circle', () => {
    const css = readFileSync('src/components/recommendationNotInterested.css', 'utf8')
    expect(css).toContain('min-width: var(--control-min-hit-target, 44px)')
    expect(css).toContain('min-height: var(--control-min-hit-target, 44px)')
    const native = readFileSync('ios/TasteMap/TasteMap/Services/RestaurantRecommendationPreferences.swift', 'utf8')
    expect(native).toContain('Image(systemName: "xmark")')
    expect(native).toContain('minWidth: TasteMapDesignTokens.Control.minimumHitTarget')
    expect(native).not.toContain('minus.circle')
    expect(native).not.toMatch(/\bLabel\(saved \?/)
  })
})
