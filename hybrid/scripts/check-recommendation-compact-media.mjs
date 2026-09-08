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
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    await import('/src/hybrid/app/hybridShell.css')
    const { content: original, profile } = await loadTasteMapBrowserDebugFixture()
    const platform = new TasteMapBrowserAdapter({ profile: async () => profile })
    platform.acceptProfileSnapshot(profile)
    const content = structuredClone(original)
    content.discovery.forYou = [content.discovery.forYou[0]]
    // Local layout material only; no remote merchant photo availability dependency.
    const image = { ...content.discovery.forYou[0].restaurant.image, resourceURL: '/food-heroes/western.png' }
    content.discovery.forYou[0].restaurant.image = image
    content.discovery.trending = [{ ...content.discovery.trending[0], restaurant: { ...content.discovery.trending[0].restaurant, image } }]
    content.discovery.similarTaste = [{ ...content.discovery.similarTaste[0], activityImages: [image] }]
    content.community.latest = [{ ...content.community.latest[0], activityImages: [image] }]
    document.getElementById('root').remove()
    window.compactMediaOpened = []
    createRoot(document.body.appendChild(document.createElement('div'))).render(React.createElement(HybridDiscoveryPage, {
      content, platform, onOpenRestaurant: id => window.compactMediaOpened.push(id),
    }))
  })
  for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
    await page.setViewportSize({ width, height: 874 }); await page.emulateMedia({ colorScheme })
    const cases = []
    for (const name of ['为你推荐', '同味之选', '最新', '趋势']) {
      await page.getByRole('tab', { name, exact: true }).click()
      await page.locator('.tm-activity-card__media').first().waitFor()
      await page.waitForFunction(() => {
        const img = document.querySelector('.tm-activity-card__media img')
        return img?.complete && img.naturalWidth > 0
      })
      const box = await page.locator('.tm-activity-card__media').first().boundingBox()
      assert.ok(box)
      assert.ok(Math.abs(box.width - box.height) < 1, JSON.stringify(box))
      assert.ok(box.width <= 180 && box.width < width * .55)
      cases.push(box)
      assert.equal(await page.locator('[data-media-layout="wide"]').count(), 0)
      if (name === '趋势') {
        assert.equal(await page.locator('[data-activity-region="restaurant-actions"] button').count(), 3)
        assert.ok(await page.locator('.tm-activity-card__recommendation-reasons li').count() > 0)
        assert.equal(await page.locator('.tm-activity-card__rating-summary').count(), 0)
        await page.screenshot({ path: `/tmp/tastemap-trending-compact-${width}-${colorScheme}.png` })
        const before = await page.evaluate(() => window.compactMediaOpened.length)
        await page.locator('.tm-activity-card__media button').first().click()
        assert.equal(await page.evaluate(() => window.compactMediaOpened.length), before + 1)
      }
      if (name === '为你推荐') {
        assert.equal(await page.locator('[data-signal-artwork="ribbon-medal"]').count(), 1)
        assert.equal(await page.locator('[data-signal-explanation]').count(), 0)
        assert.ok(await page.locator('.tm-activity-card__recommendation-reasons li').count() > 0)
        assert.equal(await page.locator('[data-activity-region="restaurant-actions"] button').count(), 3)
        await page.screenshot({ path: `/tmp/tastemap-for-you-compact-${width}-${colorScheme}.png` })
        await page.locator('.tm-activity-card__media button').first().click()
        assert.ok(await page.evaluate(() => window.compactMediaOpened.length > 0))
      }
    }
    cases.forEach(box => {
      assert.ok(Math.abs(box.width - cases[0].width) < 1)
      assert.ok(Math.abs(box.x - cases[0].x) < 1)
    })
  }
  assert.deepEqual(errors, [])
  console.log('PASS: For You/Similar Taste/Latest/Trending single-image sizes and left edges match at 375/402 light/dark; no wide-media variant, retained badge/reasons/actions, working image navigation.')
} finally { await browser.close() }
