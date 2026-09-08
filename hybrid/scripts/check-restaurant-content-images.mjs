import assert from 'node:assert/strict'

// Isolated actual React renderer. No account writes, upload, publication or Native storage.
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  for (const width of [375, 430]) for (const colorScheme of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width, height: 932 }, colorScheme })
    const errors = []
    page.on('pageerror', error => errors.push(error.message))
    await page.goto(process.env.TASTEMAP_UI_TEST_URL ?? 'http://127.0.0.1:4179')
    await page.evaluate(async () => {
      const React = (await import('/node_modules/.vite/deps/react.js')).default
      const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
      const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
      const { RestaurantPreviewCard } = await import('/src/components/RestaurantPreviewCard.tsx')
      const { RestaurantAvatar } = await import('/src/components/RestaurantAvatar.tsx')
      const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
      await import('/src/styles/global.css')
      await import('/src/hybrid/app/hybridShell.css')
      const fixture = await loadTasteMapBrowserDebugFixture()
      const imageURL = `${location.origin}/food-library/western.png`
      const avatarURL = `${location.origin}/food-library/drinks-desserts.png`
      const photo = { kind: 'ownerPhoto', photoID: 'content-test-photo', restaurantID: 'content-test', visitID: 'content-test-visit',
        sourceOwnerID: fixture.profile.user.id, visibility: 'private', exportAllowed: true, attributionRequired: false,
        resourceURL: imageURL, accessibilityLabel: '隔离测试实拍描述符' }
      const fallback = { kind: 'foodCategoryVisual', categoryVisualID: 'cafeBakery', stableSeed: 'content-test', exportAllowed: false, accessibilityLabel: '咖啡素材插画' }
      const avatar = { ...photo, visitID: null, photoID: 'custom-avatar', resourceURL: avatarURL, accessibilityLabel: '自定义头像' }
      const restaurant = { ...fixture.profile.restaurants[0], name: '桂雨咖啡', tags: ['咖啡'], markerType: 'image', markerImageData: avatarURL, markerPhotoId: null, visits: [], visitCount: 0 }
      const platform = { kind: 'browser', events: { subscribe: async () => ({ remove: async () => {} }) },
        auth: { sessionStatus: async () => ({ state: 'authenticated', userID: fixture.profile.user.id }) },
        share: { open: async () => {} }, haptics: { selection: async () => {} } }
      document.getElementById('root').remove()
      const host = document.body.appendChild(document.createElement('div'))
      host.className = 'tm-hybrid-shell'
      const root = createRoot(host)
      window.setContentImagePhase = phase => {
        const content = structuredClone(fixture.content)
        const selected = phase === 'photo' ? photo : phase === 'broken' ? { ...photo, resourceURL: `${location.origin}/__deliberately_missing_content_photo__.jpg` } : fallback
        const resolution = { sources: selected === fallback ? [] : [selected], fallback }
        for (const items of [...Object.values(content.discovery), ...Object.values(content.community)]) for (const item of items) {
          item.restaurant = { ...item.restaurant, name: '桂雨咖啡', tags: ['咖啡'], image: avatar, contentImage: selected, contentImageResolution: resolution }
          item.activityImages = []
        }
        root.render(React.createElement(React.Fragment, null,
          React.createElement('div', { 'data-test-discovery': true }, React.createElement(HybridDiscoveryPage, { content, platform, onOpenRestaurant: () => {} })),
          React.createElement('div', { 'data-test-detail': true, className: 'tm-hybrid-detail' }, React.createElement(RestaurantPreviewCard, {
            restaurant, contentImage: selected, contentImageResolution: resolution, onClose: () => {}, onEditAvatar: () => {}, remoteStatsEnabled: false,
          })),
          React.createElement('div', { 'data-test-avatar': true }, React.createElement(RestaurantAvatar, { restaurant }))))
      }
      window.setContentImagePhase('empty')
    })
    for (const phase of ['empty', 'photo', 'removed', 'broken']) {
      await page.evaluate(phase => window.setContentImagePhase(phase), phase)
      for (const tab of ['为你推荐', '同味之选', '最新', '趋势', '关注']) {
        await page.getByRole('tab', { name: tab, exact: true }).click()
        const media = page.locator('[data-test-discovery] .tm-activity-card__media').first()
        await media.waitFor()
        if (phase === 'photo') await media.locator('img').first().waitFor()
        else await media.locator('[data-food-library-artwork="coffee"]').first().waitFor()
        assert.equal(await media.locator('img[src$="drinks-desserts.png"]').count(), 0)
        assert.equal(await media.locator('.restaurant-avatar').count(), 0)
        const rect = await media.boundingBox()
        assert(rect.width < 200 && Math.abs(rect.width - rect.height) < 1)
      }
      const cover = page.locator('[data-test-detail] .restaurant-detail-gallery')
      await cover.scrollIntoViewIfNeeded()
      if (phase === 'photo') await cover.locator('img[src$="western.png"]').waitFor()
      else await cover.locator('[data-food-library-artwork="coffee"]').waitFor()
      assert.equal(await cover.locator('img[src$="drinks-desserts.png"]').count(), 0)
      assert.equal(await page.locator('[data-test-avatar] img[src$="drinks-desserts.png"]').count(), 1)
      assert.equal(await page.getByRole('button', { name: '修改餐厅头像', exact: true }).count(), 1)
      assert.equal(await page.locator('[data-test-detail] [data-summary-module="user-photos"]').count(), 1)
    }
    assert.deepEqual(errors, [])
    console.log(`PASS content/avatar isolation ${width}px ${colorScheme}: all 5 Discovery tabs + Detail, photo arrival/removal/failure, custom avatar preserved`)
    await page.close()
  }
} finally { await browser.close() }
