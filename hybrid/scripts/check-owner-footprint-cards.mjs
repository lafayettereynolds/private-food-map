import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width, height: 874 }, colorScheme })
    await page.goto('http://127.0.0.1:4179')
    await page.evaluate(async () => {
      const React = (await import('/node_modules/.vite/deps/react.js')).default
      const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
      const { TasteFootprintPreview } = await import('/src/components/TasteFootprints.tsx')
      const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
      const { profile } = await loadTasteMapBrowserDebugFixture()
      const restaurant = { ...profile.restaurants[0], visits: [], status: 'visited' }
      const visits = [1, 2, 4, 5, 6, 7].map((count, index) => ({ ...profile.visits[0], id: `album-${count}`,
        restaurantId: restaurant.id, visitedAt: new Date(Date.UTC(2026, 8, 6 - index)).toISOString(),
        rating: index === 0 ? 0 : index === 1 ? null : 4.3, visibility: 'private', dishes: [],
        note: '完整的私人到访笔记，保留原文而不是只显示餐厅名称。'.repeat(5),
        photos: Array.from({ length: count }, (_, n) => `/food-heroes/western.png?sample=${n}`), photoIds: [] }))
      document.getElementById('root').remove()
      window.footprintOpened = []
      const root = document.body.appendChild(document.createElement('div'))
      root.style.padding = '16px'
      createRoot(root).render(React.createElement(TasteFootprintPreview, { restaurants: [restaurant], visits, user: profile.user, onSelectRestaurant: r => window.footprintOpened.push(r.id) }))
    })
    await page.locator('[data-footprint-id]').first().waitFor()
    assert.equal(await page.locator('[data-product-contract="activity-card"]').count(), 6)
    assert.equal(await page.locator('[class*="timeline"]').count(), 0)
    for (const count of [1, 2, 4, 5, 6, 7]) {
      const card = page.locator(`[data-footprint-id="visit:album-${count}"]`)
      await card.scrollIntoViewIfNeeded()
      const tiles = card.locator('.tm-activity-media__tile')
      assert.equal(await tiles.count(), count)
      const boxes = await tiles.evaluateAll(nodes => nodes.map(n => { const b = n.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height } }))
      assert.ok(boxes.every(b => b.w <= 180 && Math.abs(b.w - b.h) < 1))
      if (count === 2) assert.ok(Math.abs(boxes[0].y - boxes[1].y) < 1)
      if (count === 4) assert.ok(boxes[2].y > boxes[0].y && Math.abs(boxes[0].x - boxes[2].x) < 1)
      assert.ok(await card.getByText('仅自己', { exact: true }).count())
      assert.equal(await card.getByText('查看餐厅', { exact: true }).count(), 0)
      assert.equal(await card.locator('footer').count(), 0)
      assert.equal(await card.locator('.tm-activity-card__restaurant-copy small .tm-activity-card__restaurant-detail-icon svg').count(), 1)
      const noOverflow = await card.evaluate(n => n.scrollWidth <= n.clientWidth)
      assert.ok(noOverflow)
      if (count === 2) await page.screenshot({ path: `/tmp/tastemap-owner-footprints-${width}-${colorScheme}.png` })
      await card.getByRole('button', { name: '查看餐厅', exact: true }).click()
    }
    assert.equal(await page.evaluate(() => window.footprintOpened.length), 6)
    assert.equal(await page.locator('[aria-label="本次到访评分 0.0"]').count(), 1)
    assert.equal(await page.locator('[aria-label="本次到访未评分"]').count(), 1)
    await page.close()
  }
  console.log('PASS owner cards: 375/402 light/dark; 1/2/4/5/6/7 square albums; full private notes, zero vs unrated and Restaurant navigation.')
} finally { await browser.close() }
