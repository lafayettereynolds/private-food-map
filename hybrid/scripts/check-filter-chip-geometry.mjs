// Isolated visual/interaction probe. No network or production data is changed.
import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  await page.goto(process.env.TASTEMAP_FILTER_TEST_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { MapFilterBar } = await import('/src/components/MyMapBrowsePage.tsx')
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    const fixture = await (await fetch('/hybrid/fixtures/profile-restaurant-rich.json')).json()
    document.getElementById('root').style.display = 'none'
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const cities = ['杭州', '上海', '很长的城市名称用于检查选中后的省略显示']
    const placements = cities.map((city, i) => ({ id: `geometry-${i}`, restaurant: { ...fixture.restaurants[0], id: `geometry-${i}`, city, visits: [] }, mode: 'for_you', viewerState: 'none', sourceUser: null, interaction: null, communityRating: { valueOutOfFive: 4.5, sampleCount: 5 }, reasons: [], reason: '', rank: i + 1 }))
    const content = { generatedAt: '2026-09-06T00:00:00Z', discovery: { forYou: placements, similarTaste: [], trending: [] }, community: { following: [], latest: [] }, lists: [] }
    function Probe() {
      const [filters, setFilters] = React.useState({})
      return React.createElement('div', { className: 'tm-hybrid-shell' },
        React.createElement('h2', null, '我的地图 · 共用筛选'),
        React.createElement(MapFilterBar, { activeCount: Object.values(filters).filter(Boolean).length, filters, onChange: setFilters, onOpenAll() {}, options: { cities, companions: [], cuisines: [], recommendationSources: [] }, search: '', setSearch() {}, sort: 'recent', setSort() {} }),
        React.createElement(HybridDiscoveryPage, { content, platform: { kind: 'browser', community: {}, navigation: {}, share: {} }, onOpenRestaurant() {} }))
    }
    root.render(React.createElement(Probe))
  })
  const map = page.locator('.tm-map-filter-bar:visible')
  const discovery = page.locator('.tm-discovery-page__filters .tm-browse-filter-bar')
  const mapCity = map.getByLabel('城市', { exact: true })
  const discoveryCity = discovery.getByLabel('城市', { exact: true })
  await mapCity.waitFor()
  const buttonGeometry = el => {
    const style = getComputedStyle(el), rect = el.getBoundingClientRect()
    return { width: rect.width, height: rect.height, font: style.font, padding: style.padding, gap: style.gap }
  }
  assert.deepEqual(await map.locator('button').first().evaluate(buttonGeometry), await discovery.locator('button').first().evaluate(buttonGeometry))
  console.log('PASS leading Filters button also shares width, font, padding and gap; host font resets do not override it')
  async function geometry(select) {
    return select.evaluate(el => {
      const label = el.closest('label')
      const rect = label.getBoundingClientRect()
      const [icon, text, chevron] = [...label.children].slice(0, 3).map(child => child.getBoundingClientRect())
      const target = el.getBoundingClientRect()
      const style = getComputedStyle(label)
      return {
        width: rect.width, height: rect.height,
        paddingLeft: icon.left - rect.left, paddingRight: rect.right - chevron.right,
        iconTextGap: text.left - icon.right, textChevronGap: chevron.left - text.right,
        iconWidth: icon.width, chevronWidth: chevron.width,
        targetWidth: target.width, targetHeight: target.height,
        font: style.font, color: style.color,
      }
    })
  }
  async function compare(label, first, second) {
    const a = await geometry(first), b = await geometry(second)
    assert.deepEqual(a, b, label)
    assert.equal(a.height, 44)
    assert.equal(a.targetHeight, 44)
    assert.equal(a.targetWidth, a.width)
    assert.equal(a.paddingLeft, 9)
    assert.equal(a.paddingRight, 9)
    assert.equal(a.iconTextGap, 5)
    assert.equal(a.textChevronGap, 5)
    console.log(`PASS ${label}: ${JSON.stringify(a)}`)
  }
  for (const width of [375, 402, 430]) {
    await page.setViewportSize({ width, height: 874 })
    for (const colorScheme of ['light', 'dark']) {
      await page.emulateMedia({ colorScheme })
      for (const city of ['', '杭州', '很长的城市名称用于检查选中后的省略显示']) {
        await mapCity.selectOption(city)
        await discoveryCity.selectOption(city || 'all')
        await compare(`${width}/${colorScheme}/city=${city || 'default'}`, mapCity, discoveryCity)
      }
    }
  }
  await page.emulateMedia({ colorScheme: 'light' })
  await page.setViewportSize({ width: 402, height: 874 })
  await mapCity.selectOption('')
  await discoveryCity.selectOption('all')
  await map.getByLabel('评分', { exact: true }).selectOption('')
  await discovery.getByLabel('公开评分', { exact: true }).selectOption('0')
  await discoveryCity.blur()
  // The longest hidden option differs; neither must contribute to chip width.
  await mapCity.evaluate(el => el.add(new Option('比任何现有选项都长的城市名称但并没有选择因此必须不影响宽度', 'extra')))
  await compare('different hidden menu options', mapCity, discoveryCity)
  await compare('default rating', map.getByLabel('评分', { exact: true }), discovery.getByLabel('公开评分', { exact: true }))
  await map.getByLabel('评分', { exact: true }).selectOption('9')
  await discovery.getByLabel('公开评分', { exact: true }).selectOption('9')
  await compare('selected rating', map.getByLabel('评分', { exact: true }), discovery.getByLabel('公开评分', { exact: true }))
  await discoveryCity.focus()
  assert.equal(await discoveryCity.evaluate(el => document.activeElement === el), true)
  await discoveryCity.selectOption('杭州')
  assert.equal(await discoveryCity.inputValue(), '杭州')
  assert.equal(await discoveryCity.locator('..').locator('.tm-filter-select__value').innerText(), '杭州')
  console.log('PASS native select retains focusability and keeps selected value/visible label synchronized; system menu tapping is covered by the iOS UI test')
  await discoveryCity.selectOption('all')
  await page.screenshot({ path: '/tmp/tastemap-filter-chip-comparison.png', animations: 'disabled' })
} finally { await browser.close() }
