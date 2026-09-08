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
    const owner = 'isolated-recommendation-intent-probe'
    for (const version of ['v1', 'v2']) localStorage.removeItem(`tastemap:recommendation-exclusions:${version}:${owner}`)
    const names = ['KFC (西湖店)', '肯德基（城西店）', '麦当劳', '日常午餐厨房', '地方特色小吃', '特色火锅']
    const forYou = names.map((name, index) => ({ ...fixture.content.discovery.forYou[0], id: `intent-card-${index}`, rank: index + 1,
      restaurant: { ...fixture.content.discovery.forYou[0].restaurant, id: `intent-${index}`, name, tags: index === 3 ? ['日常快餐'] : index === 4 ? ['小吃'] : [], latitude: 30.25 + index * .01 } }))
    const profile = { ...fixture.profile, user: { ...fixture.profile.user, id: owner }, restaurants: forYou.map(item => ({ ...fixture.profile.restaurants[0], ...item.restaurant, userId: owner, placeIdentities: [], deletedAt: null })) }
    const content = { ...fixture.content, discovery: { ...fixture.content.discovery, forYou } }
    document.getElementById('root').remove()
    const host = document.body.appendChild(document.createElement('div'))
    window.intentProbe = { original: JSON.stringify(forYou), forYou, profile }
    window.mountIntent = () => {
      window.intentProbe.root?.unmount()
      const root = createRoot(host); const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
      adapter.acceptProfileSnapshot(profile)
      const MapSurface = props => { window.intentProbe.map = props; return React.createElement('div', { 'data-map-probe': true }) }
      root.render(React.createElement(React.Fragment, {},
        React.createElement(HybridDiscoveryPage, { content, platform: adapter, onOpenRestaurant: () => {} }),
        React.createElement(MyMapBrowsePage, { platform: adapter, profile, active: true, MapSurface, forYouRecommendations: forYou,
          recommendationSnapshotGeneratedAt: content.generatedAt, onOpenRestaurant: () => {}, onAddRestaurant: () => {} })))
      window.intentProbe.root = root
    }
    window.mountIntent()
  })
  const dismissal = page.getByRole('button', { name: '不感兴趣', exact: true })
  await dismissal.first().waitFor()
  await page.getByRole('tab', { name: /^推荐/ }).click()
  await page.waitForFunction(() => window.intentProbe.map?.restaurants?.length === 6)
  await page.locator('.tm-my-map').evaluate(el => { el.style.visibility = 'hidden' })
  await dismissal.first().click()
  await page.getByRole('dialog', { name: '不再推荐这家餐厅？' }).waitFor()
  assert.equal(await dismissal.count(), 6, 'opening confirmation does not remove a card')
  assert.equal(await page.evaluate(() => window.intentProbe.map.restaurants.length), 6)
  await page.getByRole('button', { name: '取消', exact: true }).click()
  assert.equal(await dismissal.count(), 6, 'cancel does not alter recommendation intent')
  await dismissal.first().click()
  await page.getByRole('button', { name: '确认不感兴趣', exact: true }).click()
  await page.waitForFunction(() => window.intentProbe.map?.restaurants?.length === 4)
  assert.equal(await dismissal.count(), 4, 'both KFC branches disappear, not other cuisines')
  await dismissal.first().click()
  await page.getByRole('button', { name: '确认不感兴趣', exact: true }).click()
  await page.waitForFunction(() => window.intentProbe.map?.restaurants?.length === 3)
  assert.deepEqual(await page.evaluate(() => [...window.intentProbe.map.restaurants].sort((a, b) => a.recommendationRank - b.recommendationRank).map(item => item.name)), ['地方特色小吃', '特色火锅', '日常午餐厨房'])
  const feed = await page.locator('.tm-hybrid-discovery').count() ? page.locator('.tm-hybrid-discovery') : page.locator('body')
  const text = await feed.innerText()
  assert(text.indexOf('地方特色小吃') < text.indexOf('日常午餐厨房'), 'the actual For You feed shares the reordered snapshot')
  await page.screenshot({ path: '/tmp/tastemap-recommendation-intent-browser.png', fullPage: true })
  await page.evaluate(() => window.mountIntent())
  await dismissal.first().waitFor()
  assert.equal(await dismissal.count(), 3, 'intent and exact exclusions survive adapter recreation')
  assert.equal(await page.evaluate(() => JSON.stringify(window.intentProbe.forYou)), await page.evaluate(() => window.intentProbe.original), 'original ratings, reasons and cuisine records are immutable')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { RestaurantPreviewCard } = await import('/src/components/RestaurantPreviewCard.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    window.intentProbe.root.unmount()
    const host = document.body.appendChild(document.createElement('div'))
    const safety = window.intentSafety = { owner: 'owner-a', writes: [], exclusions: {}, notify: () => {} }
    const platform = {
      events: { subscribe: async callback => { safety.notify = callback; return { remove() {} } } },
      recommendations: { preference: async id => {
        if (id) { safety.writes.push({ owner: safety.owner, id }); safety.exclusions[safety.owner] = [id] }
        return { ownerID: safety.owner, excludedIDs: safety.exclusions[safety.owner] ?? [] }
      } },
    }
    const restaurant = { ...window.intentProbe.profile.restaurants[0], id: 'safety-restaurant', visits: [] }
    createRoot(host).render(React.createElement('main', { className: 'tm-hybrid-detail' }, React.createElement(RestaurantPreviewCard, { restaurant, recommendationPlatform: platform, remoteStatsEnabled: false, showCloseButton: false, onClose() {} })))
  })
  const hero = page.locator('.restaurant-detail-gallery__merchant')
  const heroDismiss = hero.getByRole('button', { name: '不感兴趣', exact: true })
  await heroDismiss.waitFor()
  await hero.scrollIntoViewIfNeeded()
  const heroBox = await hero.boundingBox(); const buttonBox = await heroDismiss.boundingBox()
  assert(buttonBox.x + buttonBox.width <= heroBox.x + heroBox.width + 1 && buttonBox.x > heroBox.x + heroBox.width / 2, 'detail X is at the hero right edge')
  assert(buttonBox.y + buttonBox.height <= heroBox.y + heroBox.height + 1 && buttonBox.y > heroBox.y + heroBox.height / 2, 'detail X is at the hero bottom edge')
  await heroDismiss.click()
  await page.getByRole('dialog', { name: '不再推荐这家餐厅？' }).waitFor()
  await page.screenshot({ path: '/tmp/tastemap-not-interested-confirmation-browser.png', fullPage: true, animations: 'disabled' })
  await page.getByRole('button', { name: '取消', exact: true }).click()
  assert.deepEqual(await page.evaluate(() => window.intentSafety.writes), [], 'detail cancellation does not write')
  await heroDismiss.click()
  await page.evaluate(() => { window.intentSafety.owner = 'owner-b'; window.intentSafety.notify({ name: 'auth.changed' }) })
  await page.getByRole('dialog', { name: '不再推荐这家餐厅？' }).waitFor({ state: 'detached' })
  assert.deepEqual(await page.evaluate(() => window.intentSafety.writes), [], 'switching owner invalidates an open confirmation without writing')
  await heroDismiss.click()
  await page.getByRole('button', { name: '确认不感兴趣', exact: true }).click()
  await page.getByRole('button', { name: '已标记不感兴趣', exact: true }).waitFor()
  assert.deepEqual(await page.evaluate(() => window.intentSafety.writes), [{ owner: 'owner-b', id: 'safety-restaurant' }])
  await page.screenshot({ path: '/tmp/tastemap-not-interested-detail-browser.png', fullPage: true, animations: 'disabled' })
  await page.evaluate(async () => {
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const original = window.intentProbe.profile
    const next = { ...original, user: { ...original.user, id: 'isolated-owner-switch-probe' }, restaurants: original.restaurants.map(item => ({ ...item, userId: 'isolated-owner-switch-probe' })) }
    for (const version of ['v1', 'v2']) localStorage.removeItem(`tastemap:recommendation-exclusions:${version}:${next.user.id}`)
    const adapter = new TasteMapBrowserAdapter({ profile: async () => original })
    adapter.acceptProfileSnapshot(original)
    const pending = adapter.recommendations.preference(original.restaurants[0].id)
    adapter.acceptProfileSnapshot(next)
    try { await pending; throw new Error('write should reject account switch') } catch (error) { if (error.code !== 'account_changed') throw error }
    const current = await adapter.recommendations.preference()
    if (current.ownerID !== next.user.id || current.excludedIDs.length) throw new Error('previous account confirmation wrote the next account')
  })
  assert.deepEqual(errors, [])
  console.log('PASS: For You / Map confirmation, cancellation, persistence, detail hero X, owner-switch invalidation and adapter write isolation; ratings and history survive.')
} finally { await browser.close() }
