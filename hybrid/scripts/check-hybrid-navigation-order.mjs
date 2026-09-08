import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridAppShell } = await import('/src/hybrid/app/HybridAppShell.tsx')
    const { TasteMapNativeAdapter } = await import('/src/platform/TasteMapNativeAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('root').remove()
    window.history.replaceState(null, '', '#/profile')
    const host = document.body.appendChild(document.createElement('div'))
    host.id = 'navigation-order-probe'
    const listeners = new Set()
    const probe = window.navigationProbe = { pendingEvents: [], pendingBacks: [], deferBack: false, sequence: 0, history: [{ surface: 'profile' }] }
    probe.emit = event => listeners.forEach(listener => listener({ version: 1, sequence: ++probe.sequence, name: 'navigation.route', ...event }))
    const plugin = {
      addListener: async (_, listener) => { listeners.add(listener); return { remove: async () => listeners.delete(listener) } },
      invoke: async ({ request }) => {
        let result = {}
        if (request.method === 'runtime.info') result = { bridgeVersion: 1, supportedCapabilities: { location: false }, dataSource: 'isolated-navigation-probe' }
        if (request.method === 'navigation.openHybrid' || request.method === 'navigation.back') {
          if (request.method === 'navigation.openHybrid') probe.history.push(request.payload)
          else if (probe.history.length > 1) probe.history.pop()
          result = { route: probe.history.at(-1), owner: 'hybrid', canGoBack: probe.history.length > 1, sourceRequestID: request.requestId }
          probe.pendingEvents.push({ payload: result })
          if (request.method === 'navigation.back' && probe.deferBack) {
            return new Promise(resolve => probe.pendingBacks.push(() => resolve({ version: 1, requestId: request.requestId, result })))
          }
        }
        return { version: 1, requestId: request.requestId, result }
      },
    }
    const platform = new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: plugin } } })
    platform.auth.sessionStatus = async () => ({ state: 'authenticated' })
    platform.profile.getCurrent = async () => structuredClone(fixture.profile)
    platform.content.snapshot = async () => structuredClone(fixture.content)
    platform.acquisition.nearby = async () => ({ candidates: [], state: 'empty', detectedCity: null })
    platform.acquisition.shared = async () => ({ candidates: [], state: 'empty', detectedCity: null })
    platform.map.viewport = async request => ({ requestID: request.requestID, items: [], total: 0, options: { cities: [], companions: [], cuisines: [], recommendationSources: [] }, scopeCounts: { visited: 0, wantToGo: 0, recommended: 0 } })
    platform.map.updateNativeSurface = async request => ({ requestID: request.requestID, surface: 'mapkit', persistent: true })
    platform.restaurant.get = async id => ({ restaurant: fixture.profile.restaurants.find(item => item.id === id), image: fixture.profile.restaurantImages[id], editableVisitIDs: [], viewerState: 'visited', capabilities: {} })
    createRoot(host).render(React.createElement(HybridAppShell, { platform }))
  })
  const host = page.locator('#navigation-order-probe')
  const settle = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  const route = () => host.locator('.tm-hybrid-shell').getAttribute('data-route')
  await host.getByRole('button', { name: '地图', exact: true }).click()
  await host.getByRole('button', { name: '添加餐厅', exact: true }).waitFor()
  await host.getByRole('button', { name: '发现', exact: true }).click()
  await host.locator('.tm-hybrid-shell[data-route="discovery"]').waitFor()
  await host.getByRole('button', { name: '地图', exact: true }).click()
  await host.getByRole('button', { name: '添加餐厅', exact: true }).waitFor()
  await page.waitForFunction(() => window.navigationProbe.pendingEvents.filter(event => event.payload.route.surface === 'map').length >= 2)
  // Release the accepted latest Map acknowledgement before the obsolete Discovery acknowledgement.
  await page.evaluate(() => {
    const probe = window.navigationProbe
    probe.emit(probe.pendingEvents.filter(event => event.payload.route.surface === 'map').at(-1))
    probe.emit(probe.pendingEvents.find(event => event.payload.route.surface === 'discovery'))
  })
  await settle()
  assert.equal(await route(), 'map', 'A delayed Discovery bridge echo must never replace the newer visible Map')
  assert.equal(await host.getByRole('button', { name: '添加餐厅', exact: true }).isVisible(), true)

  // Native-owned dismissals and old bridge payloads without correlation remain authoritative.
  await page.evaluate(() => window.navigationProbe.emit({ payload: { route: { surface: 'profile' }, owner: 'hybrid', canGoBack: true } }))
  await host.locator('.tm-hybrid-shell[data-route="profile"]').waitFor()
  await page.evaluate(() => window.navigationProbe.emit({ name: 'deepLink.received', payload: { route: { surface: 'discovery' }, owner: 'hybrid', canGoBack: true } }))
  await host.locator('.tm-hybrid-shell[data-route="discovery"]').waitFor()

  // The asynchronous Back response must not undo a newer bottom-tab intent.
  await host.getByRole('button', { name: '地图', exact: true }).click()
  await host.getByRole('button', { name: '添加餐厅', exact: true }).click()
  await host.locator('.tm-hybrid-shell[data-route="add"]').waitFor()
  await page.evaluate(() => { window.navigationProbe.deferBack = true })
  await host.getByRole('button', { name: '返回上一页', exact: true }).click()
  await page.waitForFunction(() => window.navigationProbe.pendingBacks.length === 1)
  await host.getByRole('button', { name: '发现', exact: true }).click()
  await host.locator('.tm-hybrid-shell[data-route="discovery"]').waitFor()
  await page.evaluate(() => {
    const probe = window.navigationProbe
    probe.pendingBacks.shift()()
    probe.pendingEvents.forEach(probe.emit)
  })
  await settle()
  assert.equal(await route(), 'discovery', 'A delayed Back result and its echo must not undo a newer tab selection')
  const pendingBeforeVisit = await page.evaluate(() => window.navigationProbe.pendingEvents.length)
  await host.getByRole('button', { name: /^(再次添加|记录到访|加入餐厅) / }).first().click()
  await host.locator('.tm-hybrid-shell[data-route="visit"]').waitFor()
  await settle()
  const visitRequests = await page.evaluate(start => window.navigationProbe.pendingEvents.slice(start).filter(event => event.payload.route.surface === 'visit'), pendingBeforeVisit)
  assert.equal(visitRequests.length, 1, 'The shared Discovery callback must not also invoke its Native fallback')

  // Exercise both card branches with and without the Shell callback. A void
  // callback is a handled action, not a missing return value to fall through.
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('navigation-order-probe').style.display = 'none'
    const panel = document.body.appendChild(document.createElement('div'))
    panel.id = 'discovery-navigation-probe'
    const root = createRoot(panel)
    const probe = window.discoveryNavigationProbe = { callbackCalls: [], fallbackCalls: [] }
    window.renderDiscoveryNavigationProbe = withCallback => {
      probe.callbackCalls = []; probe.fallbackCalls = []
      root.render(React.createElement(HybridDiscoveryPage, {
        key: String(withCallback), content: fixture.content,
        onOpenRestaurant: () => {},
        onRecordVisit: withCallback ? id => { probe.callbackCalls.push(id) } : undefined,
        platform: { kind: 'native', haptics: { selection: async () => {} }, navigation: { openHybrid: async route => { probe.fallbackCalls.push(route) } } },
      }))
    }
  })
  const discovery = page.locator('#discovery-navigation-probe')
  for (const withCallback of [true, false]) {
    await page.evaluate(value => window.renderDiscoveryNavigationProbe(value), withCallback)
    for (const tab of ['为你推荐', '最新']) {
      await discovery.getByRole('tab', { name: tab, exact: true }).click()
      await discovery.getByRole('button', { name: /^(再次添加|记录到访|加入餐厅) / }).first().click()
    }
    const calls = await page.evaluate(() => window.discoveryNavigationProbe)
    assert.equal(calls.callbackCalls.length, withCallback ? 2 : 0)
    assert.equal(calls.fallbackCalls.length, withCallback ? 0 : 2)
  }
  assert.deepEqual(errors, [])
  console.log('PASS actual HybridAppShell + NativeAdapter: reversed local navigation echoes, Map CTA preservation, legacy Native route/deep-link compatibility, delayed Back response after a newer tab intent; both Discovery card branches call exactly one Shell callback or one Native fallback')
} finally { await browser.close() }
