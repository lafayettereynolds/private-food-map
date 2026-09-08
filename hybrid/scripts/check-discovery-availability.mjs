import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('root').remove()
    const host = document.body.appendChild(document.createElement('div'))
    window.availabilityActions = []
    window.mountAvailability = (kind) => {
      window.availabilityRoot?.unmount()
      const profile = { ...fixture.profile, user: { ...fixture.profile.user, membershipTier: kind === 'free' || kind === 'free-error' ? 'free' : 'member' } }
      const evidence = { personalRatedRestaurantCount: kind === 'records' ? 2 : 10, personalScoreStandardDeviationOutOfTen: kind === 'flat' ? 0 : 1,
        personalEvidence: kind === 'records' || kind === 'flat' ? 'insufficient' : 'eligible', localDirectRestaurantCount: 0 }
      const content = { ...fixture.content, discovery: { ...fixture.content.discovery, similarTaste: [],
        evidenceAvailability: kind === 'unknown' ? undefined : { similar_taste: evidence },
        refreshStatus: { ...fixture.content.discovery.refreshStatus, similar_taste: kind.endsWith('error') ? { state: 'unavailable', issue: { message: '网络读取失败', recoverable: true } } : undefined } } }
      const root = createRoot(host)
      const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
      adapter.acceptProfileSnapshot(profile)
      window.availabilityAdapter = adapter
      const listeners = new Set()
      adapter.events.subscribe = async listener => { listeners.add(listener); return { remove: async () => { listeners.delete(listener) } } }
      window.availabilityChangeAccount = () => { for (const listener of listeners) listener({ name: 'auth.changed', payload: { state: 'authenticated', userID: 'different-owner' } }) }
      window.availabilityCityQueries = []
      adapter.discovery.cityPage = async query => {
        window.availabilityCityQueries.push(query)
        return { discoveryItems: [], activityItems: [], pagination: 'complete', resolvedCity: query.city, engagementState: 'known', interactionsAvailable: false }
      }
      if (kind === 'unavailable') adapter.premium.status = async () => ({ state: 'unavailable', expiresAt: null })
      root.render(React.createElement(HybridDiscoveryPage, { content, platform: adapter, profile,
        onOpenRestaurant: () => {}, onOpenPremium: () => window.availabilityActions.push('premium'),
        onAddRestaurant: () => window.availabilityActions.push('record'), onRetry: () => window.availabilityActions.push('retry') }))
      window.availabilityRoot = root
    }
  })
  for (const [kind, state] of [['free', 'membership_required'], ['records', 'personal_records_needed'], ['flat', 'personal_variation_needed'], ['city', 'city_coverage_needed'], ['unknown', 'unknown'], ['error', null], ['free-error', null]]) {
    await page.evaluate(kind => window.mountAvailability(kind), kind)
    await page.getByRole('tab', { name: '同味之选', exact: true }).click()
    if (state) {
      await page.locator(`[data-discovery-availability="${state}"]`).waitFor()
      assert.equal(await page.getByRole('button', { name: '查看会员权益', exact: true }).count(), kind === 'free' ? 1 : 0)
      if (kind === 'free') await page.getByRole('button', { name: '查看会员权益', exact: true }).click()
      if (kind === 'records') await page.getByRole('button', { name: '补充到访与评分', exact: true }).click()
      if (kind === 'city') {
        await page.screenshot({ path: '/tmp/tastemap-discovery-city-empty.png', fullPage: true })
        await page.getByRole('button', { name: '切换城市', exact: true }).click()
        await page.getByRole('textbox', { name: '筛选城市', exact: true }).waitFor()
      } else {
        await page.getByRole('button', { name: '查看为你推荐', exact: true }).click()
        await page.locator('[data-discovery-tab="forYou"]').waitFor()
      }
    } else {
      await page.getByText('网络读取失败', { exact: true }).waitFor()
      assert.equal(await page.locator('[data-discovery-availability]').count(), 0, 'network failures must not be called insufficient evidence')
    }
  }
  await page.evaluate(() => window.mountAvailability('unavailable'))
  await page.getByRole('tab', { name: '同味之选', exact: true }).click()
  await page.getByRole('heading', { name: '暂时无法确认会员状态' }).waitFor()
  assert.equal(await page.getByRole('button', { name: '查看会员权益', exact: true }).count(), 0, 'unknown entitlement never becomes a purchase prompt')
  assert.equal(await page.getByRole('button', { name: '重新确认权益', exact: true }).count(), 1)
  assert.deepEqual(await page.evaluate(() => window.availabilityActions), ['premium', 'record'])
  await page.evaluate(() => window.mountAvailability('city'))
  await page.getByRole('tab', { name: '同味之选', exact: true }).click()
  await page.getByRole('button', { name: '切换城市', exact: true }).click()
  await page.getByRole('textbox', { name: '筛选城市', exact: true }).fill('上海')
  await page.getByRole('combobox', { name: '筛选最低评分', exact: true }).selectOption('8')
  assert.equal(await page.evaluate(() => window.availabilityCityQueries.length), 0, 'draft must not query')
  await page.getByRole('button', { name: '取消', exact: true }).click()
  await page.getByRole('button', { name: '切换城市', exact: true }).click()
  assert.equal(await page.getByRole('textbox', { name: '筛选城市', exact: true }).inputValue(), '')
  assert.equal(await page.getByRole('combobox', { name: '筛选最低评分', exact: true }).inputValue(), '0')
  await page.getByRole('textbox', { name: '筛选城市', exact: true }).fill('上海')
  await page.getByRole('button', { name: '应用', exact: true }).click()
  await page.waitForFunction(() => window.availabilityCityQueries.length === 1)
  assert.equal(await page.evaluate(() => window.availabilityCityQueries[0].city), '上海')
  await page.evaluate(() => window.availabilityChangeAccount())
  await page.locator('[data-discovery-tab="forYou"]').waitFor()
  await page.getByRole('button', { name: /^筛选/ }).click()
  assert.equal(await page.getByRole('textbox', { name: '筛选城市', exact: true }).inputValue(), '', 'account change clears prior city context')
  assert.equal(await page.getByRole('combobox', { name: '筛选最低评分', exact: true }).inputValue(), '0')
  assert.deepEqual(errors, [])
  console.log('PASS: actual Hybrid page separates entitlement, missing ratings, flat ratings, city coverage, unknown evidence and transport errors; recovery actions work.')
} finally { await browser.close() }
