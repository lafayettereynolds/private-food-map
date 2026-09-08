import { describe, expect, it } from 'vitest'
import shell from '../hybrid/app/HybridAppShell.tsx?raw'
import map from './MyMapBrowsePage.tsx?raw'
import layer from './PremiumReturnLayer.tsx?raw'
describe('membership return-context contract', () => {
  it('opens a child layer before any route or native-history mutation', () => {
    const navigate = shell.slice(shell.indexOf('const navigate = useCallback'), shell.indexOf('const refreshReadyData'))
    expect(navigate).toMatch(/nextRoute.surface === 'premium'[\s\S]*setPremiumLayerOpen\(true\)[\s\S]*return/)
    expect(navigate.indexOf('setPremiumLayerOpen(true)')).toBeLessThan(navigate.indexOf('commitLocalRoute'))
    expect(shell).toContain('<PremiumReturnLayer')
  })
  it('does not dismiss the originating filter when a paywall opens', () => {
    expect(map).not.toContain('addEventListener(PREMIUM_PAYWALL_OPEN_EVENT, onClose)')
  })
  it('uses a modal top layer and contains Escape without closing the parent', () => {
    expect(layer).toContain('showModal()')
    expect(layer).toContain('stopImmediatePropagation()')
    expect(layer).not.toContain('navigation.back')
  })
})
