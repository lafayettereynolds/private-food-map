import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 430, height: 932 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { flushSync } = (await import('/node_modules/.vite/deps/react-dom.js')).default
    const { MyMapBrowsePage } = await import('/src/components/MyMapBrowsePage.tsx')
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('root').remove()
    const host = document.body.appendChild(document.createElement('div'))
    host.id = 'map-location-probe'
    const root = createRoot(host)
    const profile = { ...fixture.profile, restaurants: [fixture.profile.restaurants[0]] }
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
    adapter.acceptProfileSnapshot(profile)
    const info = await adapter.runtime.info()
    adapter.runtime.info = async () => ({ ...info, supportedCapabilities: { ...info.supportedCapabilities, location: true } })
    const listeners = new Set()
    const probe = window.mapLocationProbe = { requests: [], active: true, listeners, removed: 0 }
    adapter.location.current = () => new Promise((resolve, reject) => probe.requests.push({ resolve, reject }))
    adapter.events.subscribe = async handler => { listeners.add(handler); return { remove: async () => { listeners.delete(handler); probe.removed++ } } }
    probe.emit = event => [...listeners].forEach(listener => listener(event))
    probe.fix = (value, overrides = {}) => ({ latitude: value, longitude: value, timestamp: new Date().toISOString(),
      horizontalAccuracy: 10, accuracyMode: 'full', authorizationStatus: 'allowed', ...overrides })
    const MapSurface = props => { probe.map = props; return React.createElement('div', { 'data-location-test-surface': true }) }
    probe.render = () => flushSync(() => root.render(React.createElement(MyMapBrowsePage, {
      active: probe.active, profile, platform: adapter, MapSurface, onOpenRestaurant: () => {}, onAddRestaurant: () => {},
    })))
    probe.unmount = () => flushSync(() => root.unmount())
    probe.render()
  })
  await page.waitForFunction(() => window.mapLocationProbe.requests.length === 1)
  await page.evaluate(() => {
    const probe = window.mapLocationProbe
    probe.emit({ name: 'app.lifecycle', payload: { state: 'background' } })
    probe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } })
  })
  await page.waitForFunction(() => window.mapLocationProbe.requests.length === 2)
  await page.evaluate(() => { const probe = window.mapLocationProbe; probe.requests[1].resolve(probe.fix(2)) })
  await page.waitForFunction(() => window.mapLocationProbe.map.currentCoordinates?.latitude === 2)
  await page.evaluate(() => {
    const probe = window.mapLocationProbe
    probe.requests[0].resolve(probe.fix(1))
    probe.emit({ name: 'location.changed', payload: probe.fix(1, { timestamp: new Date(Date.now() - 60_000).toISOString() }) })
  })
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await page.evaluate(() => window.mapLocationProbe.map.currentCoordinates.latitude), 2)
  await page.evaluate(() => {
    const probe = window.mapLocationProbe
    probe.originalNode = document.querySelector('#map-location-probe .tm-my-map')
    probe.cameraFitKey = probe.map.cameraFitKey
    probe.map.onViewportChange({ center: { latitude: 3, longitude: 3 }, zoom: 14,
      bounds: { north: 3.1, south: 2.9, east: 3.1, west: 2.9 } })
  })
  await page.waitForFunction(() => window.mapLocationProbe.map.initialViewport?.center.latitude === 3)
  await page.evaluate(() => {
    const probe = window.mapLocationProbe
    probe.emit({ name: 'app.lifecycle', payload: { state: 'background' } })
    probe.emit({ name: 'location.changed', payload: probe.fix(4) })
  })
  assert.equal(await page.evaluate(() => window.mapLocationProbe.map.currentCoordinates.latitude), 2)
  await page.evaluate(() => window.mapLocationProbe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } }))
  await page.waitForFunction(() => window.mapLocationProbe.requests.length === 3)
  await page.evaluate(() => { const probe = window.mapLocationProbe; probe.requests[2].resolve(probe.fix(4, { accuracyMode: 'reduced', horizontalAccuracy: 5_000 })) })
  await page.waitForFunction(() => window.mapLocationProbe.map.currentCoordinates?.latitude === 4)
  await page.getByText('当前为大致位置，地图不会冒充精确定位。', { exact: true }).waitFor()
  assert.equal(await page.evaluate(() => window.mapLocationProbe.map.cameraFitKey === window.mapLocationProbe.cameraFitKey), true)
  assert.equal(await page.evaluate(() => window.mapLocationProbe.map.initialViewport.center.latitude), 3)
  assert.equal(await page.evaluate(() => window.mapLocationProbe.originalNode === document.querySelector('#map-location-probe .tm-my-map')), true)
  // Hide while a fresh request is pending: neither its response nor an event
  // may update the hidden page, and a hidden resume must not start another GPS call.
  await page.evaluate(() => window.mapLocationProbe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } }))
  await page.waitForFunction(() => window.mapLocationProbe.requests.length === 4)
  await page.evaluate(() => {
    const probe = window.mapLocationProbe
    probe.active = false; probe.render()
    probe.requests[3].resolve(probe.fix(5))
    probe.emit({ name: 'location.changed', payload: probe.fix(5) })
    probe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } })
  })
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await page.evaluate(() => window.mapLocationProbe.requests.length), 4)
  assert.notEqual(await page.evaluate(() => window.mapLocationProbe.map.currentCoordinates?.latitude), 5)
  await page.evaluate(() => window.mapLocationProbe.unmount())
  await page.waitForFunction(() => window.mapLocationProbe.listeners.size === 0)
  assert.deepEqual(errors, [])
  console.log('PASS actual MyMap fresh resume requests, stale response/event rejection, hidden-page suppression, reduced-accuracy label and preserved user camera; synthetic fixtures only, no GPS requested')
} finally { await browser.close() }
