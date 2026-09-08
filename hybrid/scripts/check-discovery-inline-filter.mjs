const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
import assert from 'node:assert/strict'

const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  page.on('pageerror', error => console.error(error.message))
  await page.route('**/src/services/socialApi.ts', async route => {
    const response = await route.fetch()
    const source = await response.text()
    const patched = source.replace(/(async function fetchCommunityFeed\([^)]*\)\s*\{)/, '$1 if (window.filterTestFeed) return window.filterTestFeed;')
    assert.notEqual(patched, source)
    await route.fulfill({ response, body: patched })
  })
  await page.goto(process.env.TASTEMAP_FILTER_TEST_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    const { CommunityPage } = await import('/src/components/CommunityPage.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    const fixture = await (await fetch('/hybrid/fixtures/profile-restaurant-rich.json')).json()
    document.getElementById('root').style.display = 'none'
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const user = { id: 'filter-user', name: '筛选测试用户', isFollowing: true }
    const examples = [['甲店', '杭州', 4], ['乙店', '杭州', 4.75], ['丙店', '上海', 4.5]]
    const restaurants = examples.map(([name, city], index) => ({ ...fixture.restaurants[0], id: `filter-${index}`, name, city, image: { kind: 'foodCategoryVisual', categoryVisualID: 'noodles', stableSeed: `filter-${index}`, exportAllowed: false }, visits: [] }))
    const placements = examples.map((item, index) => ({ id: `card-${index}`, restaurant: restaurants[index], viewerState: 'none', sourceUser: null, activityRating: item[2], activityVisitedAt: null, interaction: null, likedByViewer: false, likeCount: 0, commentCount: 0, communityRating: { valueOutOfFive: item[2], sampleCount: 5 }, reasons: [], reason: '', personalTastePercent: 85, similarityPercent: 80, sharedRestaurantCount: 6, trendWindowDays: 7, uniqueVisitorCount: 8, rank: index + 1 }))
    const activities = examples.map((item, index) => ({ id: `activity-${index}`, kind: 'visit', eventAt: `2026-09-0${index + 1}T12:00:00Z`, user, restaurant: restaurants[index], visitID: `visit-${index}`, interaction: null, visitRating: item[2], note: null, viewerState: 'none', likedByViewer: false, likeCount: 0, commentCount: 0 }))
    const content = { generatedAt: '2026-09-06T00:00:00Z', discovery: { forYou: placements.map(item => ({ ...item, mode: 'for_you' })), similarTaste: placements.map(item => ({ ...item, mode: 'similar_taste' })), trending: placements.map(item => ({ ...item, mode: 'trending' })) }, community: { following: activities, latest: activities }, lists: [] }
    window.filterTestFeed = { access: { entitlementTier: 'premium', advancedFiltersEnabled: true, similarTasteEnabled: true }, items: examples.map((item, index) => ({ user: { ...fixture.profile.user, id: 'filter-user' }, restaurant: restaurants[index], visit: { ...fixture.restaurants[0].visits[0], id: `visit-${index}`, restaurantId: restaurants[index].id, rating: item[2], companions: index === 1 ? ['小王'] : ['小李'], recommendationSourceType: index === 1 ? 'friend' : 'self', diningOccasions: index === 1 ? ['date'] : ['friends'] }, publicRating: { value: item[2] * 2, sampleCount: 5 } })) }
    const platform = { kind: 'browser', events: { subscribe: async () => ({ remove() {} }) }, auth: { sessionStatus: async () => ({ state: 'anonymous' }) }, premium: { status: async () => ({ state: 'premium' }) }, community: {}, navigation: {}, share: {} }
    window.showFilterTest = host => {
      function BrowserPage() {
        const [mode, setMode] = React.useState('for_you')
        return React.createElement(CommunityPage, { mode, onModeChange: setMode, users: [], restaurants: [], candidateRestaurantIds: [], onToggleWant() {}, onMarkVisited() {}, onToggleCandidate() {}, onViewProfile() {} })
      }
      root.render(React.createElement('div', { className: 'tm-hybrid-shell', key: host + Date.now() }, host === 'hybrid'
        ? React.createElement(HybridDiscoveryPage, { content, platform, onOpenRestaurant() {} })
        : React.createElement(BrowserPage)))
    }
    window.showFilterTest('hybrid')
  })
  for (const width of [375, 402]) {
    await page.setViewportSize({ width, height: 874 })
    for (const theme of ['light', 'dark']) {
      await page.emulateMedia({ colorScheme: theme })
      await page.evaluate(() => window.showFilterTest('hybrid'))
      await page.getByRole('tab', { name: '为你推荐', exact: true }).click()
      const chip = page.getByRole('button', { name: '去过状态', exact: true })
      await chip.waitFor()
      assert.equal(await page.locator('.tm-discovery-query-tags').count(), 0)
      assert.equal(await chip.evaluate(el => el.parentElement.classList.contains('tm-browse-filter-bar')), true)
      await chip.scrollIntoViewIfNeeded()
      const geometry = await chip.evaluate(el => { const bar=el.parentElement, a=el.getBoundingClientRect(), b=bar.getBoundingClientRect();return { top:a.top, row:b.top, height:a.height, overflow:bar.scrollWidth>bar.clientWidth } })
      assert.ok(Math.abs(geometry.top-geometry.row)<2)
      assert.ok(geometry.height>=44)
      assert.equal(geometry.overflow,true)
      await page.screenshot({ path: '/tmp/tastemap-inline-filter-'+width+'-'+theme+'.png' })
      await chip.click()
      await page.getByRole('dialog', { name: '去过状态', exact: true }).getByRole('button', { name: '全部状态', exact: true }).click()
      assert.equal(await chip.count(), 1)
      assert.match(await chip.innerText(), /全部状态/)
      await chip.click()
      await page.getByRole('dialog', { name: '去过状态', exact: true }).getByRole('button', { name: '未去过', exact: true }).click()
      assert.match(await chip.innerText(), /未去过/)
    }
  }
  console.log('PASS: inline selected filter, single scrolling row, 375/402 light/dark, 44px targets and clear action')
} finally { await browser.close() }
