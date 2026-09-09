import { readFileSync } from 'node:fs'
import { expect, it } from 'vitest'

it('clears account presentation through auth.changed without clearing durable data', () => {
  const shell = readFileSync(new URL('../../src/hybrid/app/HybridAppShell.tsx', import.meta.url), 'utf8')
  const reset = shell.split("if (event.name === 'auth.changed') {")[1]?.split("if (event.name === 'data.changed')")[0]
  expect(reset).toBeDefined()
  for (const statement of [
    "setBootstrap({ state: 'loading' })", 'setRestaurant(null)', 'restaurantDetailCache.current.clear()',
    'setAvatarEditorOpen(false)', 'setPremiumLayerOpen(false)', 'setRouletteRestaurantIDs([])',
    'setRouletteExternalRestaurants([])', 'setRouletteTemporaryItems([])',
    'setRouletteSession({ rotation: 0, winnerId: null })', 'setShowRouletteCandidates(false)',
    'pendingHybridNavigation.current = null', '++navigationRevision.current',
    '++snapshotRefreshSequence.current', 'visitParentRoute.current = null',
  ]) expect(reset).toContain(statement)
  expect(reset).not.toMatch(/platform\.(sync|account|visit|restaurant)\./)
  const native = readFileSync(new URL('../../ios/TasteMap/TasteMap/ContentView.swift', import.meta.url), 'utf8')
  expect(native).toContain('.id(TasteMapRootPresentationIdentity.value(')
  expect(native).toContain('mode == .nativePrimary ? ownerID : "persistent-hybrid-root"')
})
