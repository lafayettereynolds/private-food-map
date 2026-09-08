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
    const { flushSync } = (await import('/node_modules/.vite/deps/react-dom.js')).default
    const { HybridAddRestaurantPage } = await import('/src/hybrid/app/HybridAddRestaurantPage.tsx')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const probe = window.nearbyProbe = { requests: [], selected: [], opened: [], removed: 0 }
    probe.location = { latitude: 0, longitude: 0, timestamp: new Date().toISOString(), horizontalAccuracy: 8, accuracyMode: 'full', authorizationStatus: 'allowed' }
    const platform = {
      acquisition: {
        nearby: () => new Promise(resolve => probe.requests.push(resolve)),
        shared: async () => ({ candidates: [] }),
        select: async id => { probe.selected.push(id); return { restaurantID: id } },
      },
      events: { subscribe: async handler => { probe.emit = handler; return { remove: async () => { probe.removed++ } } } },
    }
    probe.reply = (index, prefix, count) => probe.requests[index]({
      candidates: Array.from({ length: count }, (_, order) => ({ id: `${prefix}-${order}`, name: `${prefix} ${order}`, city: '测试城市', address: '仅测试用候选', distanceMeters: order + 1,
        duplicateKind: 'none', image: { kind: 'foodDiningFallback', stableSeed: `${prefix}-${order}`, accessibilityLabel: '测试视觉' } })),
      detectedCity: '测试城市', location: probe.location, message: null, sharedImportFingerprint: null,
    })
    probe.unmount = () => flushSync(() => root.unmount())
    flushSync(() => root.render(React.createElement(HybridAddRestaurantPage, { platform, onOpenRestaurant: id => probe.opened.push(id), onBack: () => {} })))
  })
  const nearby = page.locator('[data-acquisition-capability="nearby"]')
  const rows = nearby.locator('.tm-acquisition-results > button')
  const more = nearby.getByRole('button', { name: /继续加载附近餐厅/ })
  await page.waitForFunction(() => window.nearbyProbe.requests.length === 1)
  await page.evaluate(() => window.nearbyProbe.reply(0, '完整批次', 29))
  await rows.last().waitFor()
  assert.equal(await rows.count(), 12)
  await page.evaluate(() => { window.firstNearbyRow = document.querySelector('[data-nearby-total] > button') })
  assert.equal((await more.boundingBox()).height >= 44, true)
  await more.click()
  assert.equal(await rows.count(), 24)
  await more.click()
  assert.equal(await rows.count(), 29)
  assert.equal(await more.count(), 0)
  assert.deepEqual(await rows.locator('strong').allTextContents(), Array.from({ length: 29 }, (_, index) => `完整批次 ${index}`))
  assert.equal(await page.evaluate(() => window.firstNearbyRow === document.querySelector('[data-nearby-total] > button')), true)
  assert.equal(await page.evaluate(() => window.nearbyProbe.requests.length), 1)
  await rows.last().click()
  assert.deepEqual(await page.evaluate(() => window.nearbyProbe.opened), ['完整批次-28'])

  await page.evaluate(() => window.nearbyProbe.emit({ name: 'location.changed', payload: { ...window.nearbyProbe.location, latitude: 0.01 } }))
  await page.waitForFunction(() => !document.querySelector('[data-nearby-total]'))
  assert.equal(await rows.count(), 0)
  assert.equal(await more.count(), 0)
  assert.equal(await page.evaluate(() => window.nearbyProbe.requests.length), 1)
  await nearby.getByRole('button', { name: '重试', exact: true }).click()
  await page.waitForFunction(() => window.nearbyProbe.requests.length === 2)
  await page.evaluate(() => window.nearbyProbe.reply(1, '新位置', 13))
  await rows.last().waitFor()
  assert.equal(await rows.count(), 12)
  await more.click()
  assert.equal(await rows.count(), 13)
  await page.evaluate(() => window.nearbyProbe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } }))
  await page.waitForFunction(() => window.nearbyProbe.requests.length === 3)
  await page.waitForFunction(() => !document.querySelector('[data-nearby-total]'))
  assert.equal(await rows.count(), 0)
  await page.evaluate(() => window.nearbyProbe.emit({ name: 'auth.changed', payload: { state: 'authenticated', userID: 'new-test-owner' } }))
  await page.evaluate(() => window.nearbyProbe.reply(2, '旧账号晚到', 29))
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(resolve)))
  assert.equal(await rows.count(), 0)
  await page.evaluate(() => window.nearbyProbe.unmount())

  // Exercise the legacy Browser Add entrance with the same formal shared renderer.
  // Provider and coordinates are isolated in this test page only; no real GPS.
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { flushSync } = (await import('/node_modules/.vite/deps/react-dom.js')).default
    const { mapService } = await import('/src/services/mapService.ts')
    const { AddRestaurantModal } = await import('/src/components/AddRestaurantModal.tsx')
    const probe = window.browserNearbyProbe = { gps: 0, searches: 0 }
    Object.defineProperty(mapService, 'isConfigured', { get: () => true })
    mapService.detectCurrentCoordinates = async () => { probe.gps++; return { latitude: 0, longitude: 0 } }
    mapService.resolveCoordinatesLocation = async () => ({ city: '测试城市', district: '', address: '测试地址' })
    mapService.searchNearbyRestaurantPois = async () => {
      probe.searches++
      return Array.from({ length: 29 }, (_, index) => ({ amapPoiId: `browser-${index}`, name: `Browser测试 ${index}`, city: '测试城市', district: '', address: '测试地址', latitude: index / 100_000, longitude: 0, categoryHints: [], merchantImageUrl: null, phone: null, openingHours: null }))
    }
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const render = owner => flushSync(() => root.render(React.createElement(AddRestaurantModal, {
      key: owner, companionOptions: [], existingRestaurantsByPoiId: new Map(), historyRestaurants: [], isRouletteCandidate: () => false,
      onAdd: async () => {}, onToggleRoulette: () => {}, onRecordExisting: () => {}, onClose: () => {},
    })))
    probe.changeOwner = () => render('new-owner')
    probe.unmount = () => flushSync(() => root.unmount())
    render('first-owner')
  })
  await nearby.locator('[data-nearby-total="29"]').waitFor()
  assert.equal(await rows.count(), 12)
  await more.click()
  await more.click()
  assert.equal(await rows.count(), 29)
  assert.deepEqual(await page.evaluate(() => ({ gps: window.browserNearbyProbe.gps, searches: window.browserNearbyProbe.searches })), { gps: 1, searches: 1 })
  await page.evaluate(() => window.browserNearbyProbe.changeOwner())
  await nearby.locator('[data-nearby-visible="12"]').waitFor()
  assert.equal(await rows.count(), 12)
  assert.deepEqual(await page.evaluate(() => ({ gps: window.browserNearbyProbe.gps, searches: window.browserNearbyProbe.searches })), { gps: 2, searches: 2 })
  await page.evaluate(() => window.browserNearbyProbe.unmount())
  assert.deepEqual(errors, [])
  console.log('PASS real React Hybrid + Browser Add: 12→24→29 complete ordered snapshot; no GPS/search on expand; stable rows, 44px control, final candidate opens; location/refresh/owner invalidate and reset; late response dropped')
} finally { await browser.close() }
