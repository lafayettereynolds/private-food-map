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
    const { MyMapBrowsePage } = await import('/src/components/MyMapBrowsePage.tsx')
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('root').remove()
    const host = document.body.appendChild(document.createElement('div'))
    host.id = 'city-source-probe'
    const make = (id, city, status = 'visited') => ({ ...fixture.profile.restaurants[0], id, city, status,
      userId: fixture.profile.user.id, visits: [], visitCount: 0, name: `${city}城市来源验证`, deletedAt: null })
    window.cityProbe = { reads: 0, make, profile: { ...fixture.profile, visits: [], restaurants: [
      make('shanghai', '上海市'), make('alias', '上海'), make('hangzhou', '杭州'), make('wanted', '东京', 'wantToGo'),
    ] } }
    const adapter = new TasteMapBrowserAdapter({ profile: async () => { window.cityProbe.reads++; return window.cityProbe.profile } })
    const recommendation = fixture.content.discovery.forYou[0]
    const recommendations = ['温州市', '广州'].map((city, index) => ({ ...recommendation, id: `rec-${index}`, rank: index,
      restaurant: { ...recommendation.restaurant, id: `rec-restaurant-${index}`, city } }))
    const MapSurface = props => { window.cityProbe.map = props; return React.createElement('div', { 'data-city-probe-map': true }) }
    const root = createRoot(host)
    window.cityProbe.dispose = () => root.unmount()
    window.cityProbe.render = () => {
      adapter.acceptProfileSnapshot(window.cityProbe.profile)
      root.render(React.createElement(MyMapBrowsePage, { platform: adapter, profile: window.cityProbe.profile,
        active: true, MapSurface, onOpenRestaurant: () => {}, onAddRestaurant: () => {},
        forYouRecommendations: recommendations, recommendationSnapshotGeneratedAt: 'unchanged-recommendation-time' }))
    }
    window.cityProbe.render()
  })
  const host = page.locator('#city-source-probe')
  const city = host.getByRole('combobox', { name: '城市', exact: true })
  const options = () => city.locator('option').evaluateAll(values => values.map(value => value.value).filter(Boolean).sort())
  await page.waitForFunction(() => document.querySelectorAll('#city-source-probe select[aria-label="城市"] option').length === 3)
  assert.deepEqual(await options(), ['上海', '杭州'].sort())
  await city.selectOption('上海')
  await page.waitForFunction(() => window.cityProbe.map.restaurants.length === 2)
  assert.deepEqual(await options(), ['上海', '杭州'].sort())
  assert.deepEqual(await page.evaluate(() => window.cityProbe.map.restaurants.map(item => item.city).sort()), ['上海', '上海市'])
  await host.getByRole('tab', { name: /想吃/ }).click()
  await page.waitForFunction(() => window.cityProbe.map.scope === 'wantToGo' && window.cityProbe.map.restaurants.length === 1)
  assert.deepEqual(await options(), ['东京'])
  await host.getByRole('tab', { name: /推荐/ }).click()
  await page.waitForFunction(() => window.cityProbe.map.scope === 'recommended' && window.cityProbe.map.restaurants.length === 2)
  assert.deepEqual(await options(), ['温州', '广州'].sort())
  await host.getByRole('tab', { name: /去过/ }).click()
  await page.waitForFunction(() => window.cityProbe.map.scope === 'visited')
  await city.selectOption('')
  await page.waitForFunction(() => window.cityProbe.map.restaurants.length === 3)
  await page.evaluate(() => {
    window.cityProbe.originalNode = document.querySelector('#city-source-probe .tm-my-map')
    window.cityProbe.cameraFitKey = window.cityProbe.map.cameraFitKey
    window.cityProbe.map.onViewportChange({ center: { latitude: 30, longitude: 120 }, latitudeSpan: 0.5, longitudeSpan: 0.5,
      bounds: { north: 30.25, south: 29.75, east: 120.25, west: 119.75 } })
    window.cityProbe.profile = { ...window.cityProbe.profile, restaurants: [
      window.cityProbe.make('shanghai', '温州市'), window.cityProbe.make('wanted', '东京', 'wantToGo'),
      window.cityProbe.make('hangzhou', '杭州', 'wantToGo'), window.cityProbe.make('added', 'New York'),
    ] }
    window.cityProbe.render()
  })
  await page.waitForFunction(() => [...document.querySelectorAll('#city-source-probe select[aria-label="城市"] option')].some(item => item.value === 'New York'))
  assert.deepEqual(await options(), ['温州', 'New York'].sort())
  assert.equal(await page.evaluate(() => window.cityProbe.originalNode === document.querySelector('#city-source-probe .tm-my-map')), true)
  assert.equal(await page.evaluate(() => window.cityProbe.map.cameraFitKey === window.cityProbe.cameraFitKey), true)
  assert.equal(await page.evaluate(() => window.cityProbe.reads), 0, 'Accepted snapshots avoid every DB reread, including viewport callbacks')
  await host.getByRole('tab', { name: /想吃/ }).click()
  await page.waitForFunction(() => window.cityProbe.map.scope === 'wantToGo' && window.cityProbe.map.restaurants.length === 2)
  assert.deepEqual(await options(), ['东京', '杭州'].sort())
  await page.screenshot({ path: '/tmp/tastemap-city-source-runtime.png', fullPage: false })
  await page.evaluate(async () => {
    window.cityProbe.dispose()
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { TasteMapCitySearch } = await import('/src/components/TasteMapCitySearch.tsx')
    const host = document.getElementById('city-source-probe')
    host.style.cssText = 'position:fixed;top:60px;left:12px;z-index:5'
    const space = document.body.appendChild(document.createElement('div'))
    space.style.height = '3200px'
    window.cityFocusProbe = { changes: [], returnToTop: false }
    function Probe() {
      const [city, setCity] = React.useState('')
      return React.createElement(TasteMapCitySearch, { city, suggestions: ['上海', '杭州'], onChange: value => {
        window.cityFocusProbe.changes.push({ city: value, scrollY })
        setCity(value)
        if (window.cityFocusProbe.returnToTop) window.scrollTo({ top: 0, behavior: 'instant' })
      } })
    }
    createRoot(host).render(React.createElement(Probe))
  })
  for (const position of [0, 480]) for (const action of ['submit', 'cancel', 'escape', 'reset', 'suggestion']) {
    await page.evaluate(top => window.scrollTo({ top, behavior: 'instant' }), position)
    await host.getByRole('button', { name: /^搜索城市/ }).click()
    const dialog = page.getByRole('dialog', { name: '搜索城市', exact: true })
    const input = dialog.getByRole('textbox', { name: '城市名称', exact: true })
    await input.click()
    await input.fill('上海')
    // Deterministic reproduction of the document displacement caused by iOS
    // keyboard focus. Actual software-keyboard acceptance remains on Simulator.
    await page.evaluate(top => window.scrollTo({ top: top + 160, behavior: 'instant' }), position)
    const before = await page.evaluate(() => window.cityFocusProbe.changes.length)
    if (action === 'submit') await input.press('Enter')
    else if (action === 'cancel') await dialog.getByRole('button', { name: '关闭', exact: true }).click()
    else if (action === 'escape') await input.press('Escape')
    else if (action === 'reset') await dialog.getByRole('button', { name: '重置城市', exact: true }).click()
    else await dialog.getByRole('button', { name: '上海', exact: true }).click()
    await dialog.waitFor({ state: 'detached' })
    await page.waitForFunction(top => Math.abs(scrollY - top) <= 1 && document.activeElement.tagName !== 'INPUT', position)
    const changes = await page.evaluate(() => window.cityFocusProbe.changes)
    const commits = !['cancel', 'escape'].includes(action)
    assert.equal(changes.length, before + Number(commits))
    if (commits) assert.deepEqual(changes.at(-1), { city: action === 'reset' ? '' : '上海', scrollY: position })
    await page.evaluate(top => window.scrollTo({ top: top + 60, behavior: 'instant' }), position)
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
    assert.equal(await page.evaluate(() => scrollY), position + 60, 'Restoration must not fight subsequent user scrolling')
  }
  await page.evaluate(() => { window.cityFocusProbe.returnToTop = true; window.scrollTo({ top: 480, behavior: 'instant' }) })
  await host.getByRole('button', { name: /^搜索城市/ }).click()
  await page.getByRole('textbox', { name: '城市名称', exact: true }).fill('成都')
  await page.getByRole('textbox', { name: '城市名称', exact: true }).press('Enter')
  await page.waitForFunction(() => window.cityFocusProbe.changes.at(-1)?.city === '成都' && scrollY === 0)
  assert.equal(await page.evaluate(() => window.cityFocusProbe.changes.at(-1).scrollY), 480, 'Caller query scroll policy runs after focus restoration')
  assert.deepEqual(errors, [])
  console.log('PASS MyMap city scopes and camera; city dialog submit/cancel/Escape/reset/suggestion restore pre-focus scroll at 0/480px, blur input, preserve subsequent scroll and caller query-to-top policy; no pageerrors')
} finally {
  await browser.close()
}
