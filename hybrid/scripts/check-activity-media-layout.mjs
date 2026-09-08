import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
const evidence = []
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    await import('/src/hybrid/app/hybridShell.css')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const assets = ['Japanese', 'Mixed', 'Chinese', 'Cafe', 'Western', 'HotpotGrill']
    const filenames = ['japanese', 'mixed', 'chinese', 'cafe', 'western', 'hotpot-grill']
    window.renderMediaCount = count => {
      const content = structuredClone(fixture.content)
      const template = content.discovery.similarTaste[0].restaurant.image
      // Isolated layout fixtures, never uploaded or represented as real records.
      const images = Array.from({ length: count }, (_, index) => ({ ...template,
        photoID: `isolated-layout-photo-${index}`,
        resourceURL: index < 6 ? `/ios/TasteMap/TasteMap/Assets.xcassets/FoodHero${assets[index]}.imageset/taste-hero-${filenames[index]}.png` : template.resourceURL,
      }))
      content.discovery.similarTaste = [{ ...content.discovery.similarTaste[0], activityImages: images }]
      content.community.latest = [{ ...content.community.latest[0], activityImages: images }]
      content.community.following = [...content.community.latest]
      window.mediaOpened = []
      root.render(React.createElement(HybridDiscoveryPage, {
        key: count, content, platform: { kind: 'native' },
        onOpenRestaurant: id => window.mediaOpened.push(id),
      }))
    }
    window.renderMediaCount(1)
  })
  for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
    await page.setViewportSize({ width, height: 874 })
    await page.emulateMedia({ colorScheme })
    for (const count of [1, 2, 4, 5, 6, 7]) {
      await page.evaluate(count => window.renderMediaCount(count), count)
      const geometry = []
      for (const tab of ['同味之选', '最新']) {
        await page.getByRole('tab', { name: tab, exact: true }).click()
        await page.locator(`.tm-activity-media[data-photo-count="${count}"]`).waitFor()
        await page.waitForFunction(() => [...document.querySelectorAll('.tm-activity-media img')].every(img => img.complete && img.naturalWidth > 0))
        const row = await page.evaluate(() => {
          const card = document.querySelector('.tm-activity-card')
          const media = card.querySelector('.tm-activity-card__media').getBoundingClientRect()
          const tiles = [...card.querySelectorAll('.tm-activity-media__tile')].map(tile => {
            const { x, y, width, height } = tile.getBoundingClientRect()
            return { x, y, width, height }
          })
          return { cardClass: card.className, width: media.width, height: media.height, tiles, overflow: document.documentElement.scrollWidth - innerWidth }
        })
        assert.equal(row.tiles.length, count)
        assert.ok(row.cardClass.includes('is-activity'))
        assert.ok(row.overflow <= 1)
        row.tiles.forEach(tile => {
          assert.ok(Math.abs(tile.width - tile.height) <= 1, JSON.stringify(tile))
          assert.ok(tile.width >= 44)
        })
        if (count === 2) assert.ok(Math.abs(row.tiles[0].y - row.tiles[1].y) < 1)
        geometry.push(row)
        evidence.push({ viewportWidth: width, colorScheme, count, tab, ...row })
        await page.screenshot({ path: `/tmp/tastemap-media-${width}-${colorScheme}-${count}-${tab === '最新' ? 'latest' : 'similar'}.png`, fullPage: true })
        await page.locator('.tm-activity-media__tile').first().click()
        assert.ok((await page.evaluate(() => window.mediaOpened)).length > 0)
      }
      assert.equal(geometry[0].width, geometry[1].width)
      assert.equal(geometry[0].height, geometry[1].height)
      assert.deepEqual(geometry[0].tiles.map(({ width, height }) => ({ width, height })), geometry[1].tiles.map(({ width, height }) => ({ width, height })))
    }
  }
  await page.evaluate(() => window.renderMediaCount(20))
  await page.getByRole('tab', { name: '最新', exact: true }).click()
  await page.getByRole('button', { name: '展开全部 20 张照片', exact: true }).click()
  assert.equal(await page.locator('.tm-activity-media__tile').count(), 20)
  await page.getByRole('button', { name: '收起照片', exact: true }).click()
  assert.equal(await page.locator('.tm-activity-media__tile').count(), 9)
  assert.deepEqual(errors, [])
  console.log(JSON.stringify({ status: 'PASS', cases: evidence.length, evidence }))
} finally { await browser.close() }
