const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
import assert from 'node:assert/strict'

const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
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
    const platform = { kind: 'browser', community: {}, navigation: {}, share: {} }
    window.showFilterTest = host => {
      function BrowserPage() {
        const [mode, setMode] = React.useState('for_you')
        return React.createElement(CommunityPage, { mode, onModeChange: setMode, users: [], restaurants: [], candidateRestaurantIds: [], onToggleWant() {}, onMarkVisited() {}, onToggleCandidate() {}, onViewProfile() {} })
      }
      root.render(React.createElement('div', { className: 'tm-hybrid-shell', key: host }, host === 'hybrid'
        ? React.createElement(HybridDiscoveryPage, { content, platform, onOpenRestaurant() {} })
        : React.createElement(BrowserPage)))
    }
    window.showFilterTest('hybrid')
  })
  for (const host of ['hybrid', 'browser']) {
    if (host === 'browser') await page.evaluate(() => window.showFilterTest('browser'))
    await page.getByRole('tab', { name: '为你推荐', exact: true }).waitFor()
    for (const tab of ['为你推荐', '同味之选', '关注', '最新', '趋势']) {
      await page.getByRole('tab', { name: tab, exact: true }).click()
      await page.getByRole('button', { name: /^筛选(?: \d+)?$/ }).click()
      const dialog = page.getByRole('dialog', { name: '筛选餐厅', exact: true })
      await dialog.waitFor()
      const reset = dialog.getByRole('button', { name: '重置', exact: true })
      if (await reset.isEnabled()) await reset.click()
      const city = dialog.getByLabel('筛选城市', { exact: true })
      if (host === 'hybrid') await city.selectOption('杭州')
      else await city.fill('杭州')
      await dialog.getByLabel('筛选最低评分', { exact: true }).selectOption('9')
      await dialog.getByLabel('筛选排序', { exact: true }).selectOption('rating')
      assert.equal(await dialog.getByLabel('筛选最低评分').locator('option').count(), 12)
      if (host === 'hybrid' && tab === '为你推荐') await page.screenshot({ path: '/tmp/tastemap-filter-browser-panel.png', animations: 'disabled' })
      await dialog.getByRole('button', { name: '查看结果', exact: true }).click()
      const cards = page.locator('[data-product-contract="activity-card"]')
      if (host === 'hybrid') {
        assert.equal(await cards.count(), 1, `${host}/${tab} combines city and score`)
        assert.ok((await cards.innerText()).includes('乙店'))
      } else {
        // Stub only replaces the network loader; exercise actual per-tab local filtering.
        assert.equal(await cards.count(), 1, `${host}/${tab} applies city and score to the received snapshot`)
        assert.ok((await cards.first().innerText()).includes('乙店'))
      }
      await page.getByRole('button', { name: /^筛选(?: \d+)?$/ }).click()
      assert.equal(await dialog.getByLabel('筛选最低评分').inputValue(), '9')
      await dialog.getByRole('button', { name: '重置', exact: true }).click()
      await dialog.getByRole('button', { name: '关闭', exact: true }).click()
      assert.equal(await cards.count(), 3, `${host}/${tab} reset restores results`)
      console.log(`PASS ${host}/${tab}: open, controls, actual result filtering, sorting, reopen, reset, close`)
    }
    if (host === 'browser') {
      await page.getByRole('tab', { name: '为你推荐', exact: true }).click()
      await page.getByRole('button', { name: /^筛选(?: \d+)?$/ }).click()
      await page.getByLabel('筛选饭搭子').selectOption('小王')
      await page.getByLabel('筛选推荐来源').selectOption('friend')
      await page.getByLabel('筛选适合场景').selectOption('date')
      await page.getByRole('button', { name: '查看结果', exact: true }).click()
      assert.equal(await page.locator('[data-product-contract="activity-card"]').count(), 1)
      assert.ok((await page.locator('[data-product-contract="activity-card"]').innerText()).includes('乙店'))
      console.log('PASS Browser advanced source, occasion and companion filters use the same received Visit, not no-op buttons')
    }
  }
} finally { await browser.close() }
