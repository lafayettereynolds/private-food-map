import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')
describe('Premium purchase discoverability', () => {
  it('keeps the shared Browser/Capacitor purchase section before the long benefits table', () => {
    const source = read('../../src/components/TasteMapPremiumSettingsPages.tsx')
    expect(source.indexOf('<h3>开通 Premium</h3>')).toBeLessThan(source.indexOf('<section className="tm-hybrid-premium-benefits">'))
    expect(source).toContain('重新加载订阅方案')
    expect(source).toContain('product.displayPrice')
    expect(source).not.toContain('¥8')
    expect(source).not.toContain('¥80')
  })
  it('keeps the native rollback purchase section before its benefits and supports retry', () => {
    const source = read('../../ios/TasteMap/TasteMap/Features/Premium/PremiumViews.swift')
    const paywall = source.slice(source.indexOf('struct PremiumPaywallView'))
    expect(paywall.indexOf('                        productSection')).toBeLessThan(paywall.indexOf('                    benefits'))
    expect(paywall).toContain('重新加载订阅方案')
  })
})
