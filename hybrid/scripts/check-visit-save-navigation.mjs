import assert from 'node:assert/strict'
import { writeFile } from 'node:fs/promises'

const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
const evidence = []
try {
  for (const { restoredEditor, replyDelayMS } of [false, true].flatMap(restoredEditor => [0, 40].map(replyDelayMS => ({ restoredEditor, replyDelayMS })))) {
    const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
    const errors = []
    page.on('pageerror', error => errors.push(error.message))
    await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
    await page.evaluate(async ({ restored, replyDelayMS }) => {
      const React = (await import('/node_modules/.vite/deps/react.js')).default
      const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
      const { HybridAppShell } = await import('/src/hybrid/app/HybridAppShell.tsx')
      const { TasteMapNativeAdapter } = await import('/src/platform/TasteMapNativeAdapter.ts')
      const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
      const fixture = await loadTasteMapBrowserDebugFixture()
      const restaurant = fixture.profile.restaurants.find(item => fixture.profile.visits.some(visit => visit.restaurantId === item.id))
      const visit = fixture.profile.visits.find(item => item.restaurantId === restaurant.id)
      const profile = { ...fixture.profile, restaurants: [restaurant], visits: [visit] }
      const routes = { profile: { surface: 'profile' }, detail: { surface: 'restaurant', identifier: restaurant.id }, editor: { surface: 'visitEdit', identifier: visit.id } }
      document.getElementById('root').remove()
      window.history.replaceState(null, '', '#/profile')
      if (restored) {
        window.history.pushState(null, '', `#/restaurant/${encodeURIComponent(restaurant.id)}`)
        window.history.pushState(null, '', `#/visitEdit/${encodeURIComponent(visit.id)}`)
      }
      const listeners = new Set()
      const probe = window.visitNavigationProbe = { history: restored ? Object.values(routes) : [routes.profile], calls: [], saves: [], sequence: 0 }
      const plugin = {
        addListener: async (_, listener) => { listeners.add(listener); return { remove: async () => listeners.delete(listener) } },
        invoke: async ({ request }) => {
          let result = {}
          if (request.method === 'runtime.info') result = { bridgeVersion: 1, supportedCapabilities: { location: false }, dataSource: 'isolated-visit-navigation-probe' }
          if (request.method.startsWith('navigation.')) {
            // Match the shipping coordinator's stable-route de-duplication and
            // single-stack open/back operations; never stub Back to a desired page.
            if (request.method === 'navigation.openHybrid') {
              const route = { surface: request.payload.surface, ...(request.payload.identifier ? { identifier: request.payload.identifier } : {}) }
              if (request.payload.replaceCurrent === true) {
                probe.history[probe.history.length - 1] = route
                if (probe.history.length > 1 && JSON.stringify(probe.history.at(-2)) === JSON.stringify(route)) probe.history.pop()
              } else if (JSON.stringify(probe.history.at(-1)) !== JSON.stringify(route)) probe.history.push(route)
            } else if (request.method === 'navigation.back' && probe.history.length > 1) probe.history.pop()
            result = { route: probe.history.at(-1), owner: 'hybrid', canGoBack: probe.history.length > 1, sourceRequestID: request.requestId }
            probe.calls.push({ method: request.method, payload: request.payload, stack: structuredClone(probe.history) })
            for (const listener of listeners) listener({ version: 1, sequence: ++probe.sequence, name: 'navigation.route', payload: result })
          }
          // A real bridge reply can arrive after WebKit's asynchronous history
          // traversal. Exercise that ordering deterministically, not a zero-time mock.
          if (request.method === 'navigation.back' && replyDelayMS) await new Promise(resolve => setTimeout(resolve, replyDelayMS))
          return { version: 1, requestId: request.requestId, result }
        },
      }
      const platform = new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: plugin } } })
      platform.auth.sessionStatus = async () => ({ state: 'authenticated', userID: profile.user.id })
      platform.profile.getCurrent = async () => structuredClone(profile)
      platform.content.snapshot = async () => structuredClone(fixture.content)
      platform.restaurant.get = async id => ({ restaurant: { ...structuredClone(restaurant), visits: structuredClone(profile.visits) }, image: fixture.profile.restaurantImages[id], editableVisitIDs: [visit.id], viewerState: 'visited', capabilities: { canRecordVisit: true } })
      platform.visit.save = async request => {
        probe.saves.push(request)
        profile.visits = [{ ...visit, ...request.draft, id: visit.id, restaurantId: restaurant.id }]
        return { restaurantID: restaurant.id }
      }
      createRoot(document.body.appendChild(document.createElement('div'))).render(React.createElement(HybridAppShell, { platform }))
    }, { restored: restoredEditor, replyDelayMS })
    if (!restoredEditor) {
      await page.locator('.profile-taste-footprints-preview__row').first().click()
      await page.locator('[data-product-contract="visit-edit-entry"]').first().click()
    }
    await page.getByRole('heading', { name: '编辑到访记录', exact: true }).waitFor()
    await page.getByRole('textbox', { name: '到访笔记', exact: true }).fill('保存后返回不能恢复旧编辑页')
    await page.getByRole('button', { name: '保存修改', exact: true }).click()
    await page.locator('.tm-hybrid-shell[data-route="restaurant"]').waitFor()
    const afterSave = await page.evaluate(() => ({ hash: location.hash, stack: window.visitNavigationProbe.history, saves: window.visitNavigationProbe.saves.length }))
    await page.getByRole('button', { name: '返回上一页', exact: true }).click()
    await page.waitForTimeout(150)
    const afterBack = await page.evaluate(() => ({ hash: location.hash, route: document.querySelector('.tm-hybrid-shell')?.dataset.route, stack: window.visitNavigationProbe.history, calls: window.visitNavigationProbe.calls }))
    evidence.push({ scenario: restoredEditor ? 'restored-editor-with-existing-detail-history' : 'warm-profile-detail-edit', replyDelayMS, afterSave, afterBack, errors })
    assert.equal(afterSave.saves, 1)
    await page.close()
  }
  for (const scenario of evidence) {
    assert.deepEqual(scenario.errors, [])
    assert.equal(scenario.afterBack.route, 'profile', `${scenario.scenario}: Detail Back must restore Profile, never the completed editor`)
    assert.equal(scenario.afterSave.stack.some(route => route.surface === 'visitEdit'), false, `${scenario.scenario}: saved editor remains in Native history`)
  }
  console.log('PASS actual HybridAppShell + NativeAdapter: warm and restored Detail → Edit → Save → Detail → Back restore Profile with no completed editor in Native history')
} finally {
  await writeFile(process.env.TASTEMAP_NAVIGATION_EVIDENCE ?? '/tmp/tastemap-visit-save-navigation.json', JSON.stringify(evidence, null, 2))
  await browser.close()
}
