import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 430, height: 932 } })
  const errors = []
  page.on('pageerror', e => errors.push(e.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridAppShell } = await import('/src/hybrid/app/HybridAppShell.tsx')
    const { MyMapBrowsePage } = await import('/src/components/MyMapBrowsePage.tsx')
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    const restaurant = { ...fixture.profile.restaurants[0], id: 'owned-uuid', name: '身份转换验证餐厅', status: 'visited' }
    let profile = { ...fixture.profile, restaurants: [restaurant] }
    const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
    adapter.acceptProfileSnapshot(profile)
    adapter.content.snapshot = async () => ({ ...fixture.content, lists: [] })
    adapter.restaurant.get = async () => ({ restaurant, image: fixture.profile.restaurantImages[fixture.profile.restaurants[0].id], editableVisitIDs: [], viewerState: 'visited', capabilities: {} })
    document.getElementById('root').remove()
    window.history.replaceState(null, '', '#/restaurant/provider%3Aplace')
    const host = document.body.appendChild(document.createElement('div'))
    const root = createRoot(host)
    root.render(React.createElement(HybridAppShell, { platform: adapter }))
    window.mutationProbe = { root, adapter, profile, calls: 0 }
    window.startMapProbe = () => {
      root.unmount()
      const nextRoot = createRoot(document.body.appendChild(document.createElement('div')))
      const listeners = new Set()
      adapter.events.subscribe = async handler => { listeners.add(handler); return { remove: async () => listeners.delete(handler) } }
      const viewport = adapter.map.viewport
      adapter.map.viewport = async request => { window.mutationProbe.calls++; return viewport(request) }
      const MapSurface = props => { window.mutationProbe.map = props; return React.createElement('div', { 'data-map-probe': true }, props.restaurants?.map(r => r.name).join(',')) }
      nextRoot.render(React.createElement(MyMapBrowsePage, { platform: adapter, profile, active: true, MapSurface, onOpenRestaurant: () => {}, onAddRestaurant: () => {} }))
      window.deleteProbe = () => {
        profile = { ...profile, restaurants: [], visits: [] }
        adapter.acceptProfileSnapshot(profile)
        for (const listener of listeners) listener({ version: 1, sequence: 1, name: 'data.changed', payload: { reason: 'restaurantDeleted' } })
      }
    }
  })
  await page.locator('.tm-hybrid-detail').waitFor()
  assert.equal(await page.getByText('正在读取餐厅详情', { exact: true }).count(), 0)
  await page.getByRole('heading', { name: '身份转换验证餐厅', exact: true }).waitFor()
  await page.screenshot({ path: '/tmp/tastemap-90627-resolved-restaurant.png' })
  await page.evaluate(() => window.startMapProbe())
  await page.waitForFunction(() => window.mutationProbe.map?.restaurants?.length === 1)
  const before = await page.evaluate(() => window.mutationProbe.calls)
  await page.evaluate(() => window.deleteProbe())
  await page.waitForFunction(n => window.mutationProbe.calls > n && window.mutationProbe.map?.restaurants?.length === 0, before)
  assert.deepEqual(errors, [])
  console.log('PASS actual HybridAppShell provider-to-owner detail resolution; mounted MyMapBrowsePage refreshes and removes deleted marker without parent snapshot rerender.')
} finally { await browser.close() }
