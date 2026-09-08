import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  const errors = []; page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    const { MyMapBrowsePage } = await import('/src/components/MyMapBrowsePage.tsx')
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    const owner = 'isolated-dismissal-browser-probe'
    const profile = { ...fixture.profile, user: { ...fixture.profile.user, id: owner } }
    localStorage.removeItem(`tastemap:recommendation-exclusions:v1:${owner}`)
    document.getElementById('root').remove()
    const host = document.body.appendChild(document.createElement('div'))
    window.probe = { fixture, target: fixture.content.discovery.forYou[0].restaurant.id }
    window.mountDismissal = () => {
      window.probe.root?.unmount()
      const root = createRoot(host); const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
      adapter.acceptProfileSnapshot(profile)
      const MapSurface = props => { window.probe.map = props; return React.createElement('div', { 'data-map-probe': true }) }
      root.render(React.createElement(React.Fragment, {},
        React.createElement(HybridDiscoveryPage, { content: fixture.content, platform: adapter, onOpenRestaurant: () => {} }),
        React.createElement(MyMapBrowsePage, { platform: adapter, profile, active: true, MapSurface, forYouRecommendations: fixture.content.discovery.forYou, recommendationSnapshotGeneratedAt: fixture.content.generatedAt, onOpenRestaurant: () => {}, onAddRestaurant: () => {} })))
      window.probe.root = root
    }
    window.mountDismissal()
  })
  await page.getByRole('button', { name: '不感兴趣', exact: true }).first().waitFor()
  await page.getByRole('tab', { name: /^推荐/ }).click()
  await page.waitForFunction(() => window.probe.map?.restaurants?.some(item => item.id === window.probe.target))
  // Keep Map mounted as a state consumer, but show Discovery as the active
  // test surface. The production shell owns this visibility boundary.
  await page.locator('.tm-my-map').evaluate(element => { element.style.visibility = 'hidden' })
  const before = await page.getByRole('button', { name: '不感兴趣', exact: true }).count()
  const dismissButton = page.getByRole('button', { name: '不感兴趣', exact: true }).first()
  assert.equal(await dismissButton.innerText(), '')
  assert.equal(await dismissButton.locator('svg.lucide-x').count(), 1)
  const hitBox = await dismissButton.boundingBox()
  assert(hitBox.width >= 44 && hitBox.height >= 44)
  await page.screenshot({ path: '/tmp/tastemap-recommendation-dismissal-before.png', fullPage: true })
  await page.getByRole('button', { name: '不感兴趣', exact: true }).first().click()
  await page.waitForFunction(() => !window.probe.map?.restaurants?.some(item => item.id === window.probe.target))
  const after = await page.getByRole('button', { name: '不感兴趣', exact: true }).count()
  assert.ok(after < before, 'all matching identity aliases disappear together')
  await page.evaluate(() => window.probe.map.onViewportChange({ center: { latitude: 30, longitude: 120 }, latitudeDelta: 1, longitudeDelta: 1 }))
  await page.evaluate(() => window.mountDismissal())
  await page.getByRole('button', { name: '不感兴趣', exact: true }).first().waitFor()
  assert.equal(await page.getByRole('button', { name: '不感兴趣', exact: true }).count(), after)
  await page.getByRole('tab', { name: /^推荐/ }).click()
  await page.waitForFunction(() => window.probe.map?.scope === 'recommended' && !window.probe.map.restaurants.some(item => item.id === window.probe.target))
  assert.deepEqual(errors, [])
  console.log('PASS: real shared ForYou + mounted Map Recommended remove together, preserve exclusion after pan and adapter/component recreation.')
} finally { await browser.close() }
