import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  await page.goto(process.env.TASTEMAP_FILTER_TEST_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { DiscoveryQueryPanel } = await import('/src/components/DiscoveryQueryPanel.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    const { normalizeDiscoveryFilters } = await import('/src/contracts/discoveryFilters.ts')
    const { normalizeDiscoverySessionPreferences } = await import('/src/contracts/discoverySessionPreferences.ts')
    document.getElementById('root').style.display = 'none'
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    window.appliedQueries = []
    window.cancelledQueries = 0
    window.renderQueryPanel = (mode = 'for_you') => root.render(React.createElement(DiscoveryQueryPanel, {
      key: `${mode}:${Date.now()}`, mode,
      initial: { city: '杭州', sort: mode === 'trending' ? 'trend' : mode === 'latest' ? 'latest' : 'recommended', windowDays: 7,
        filters: normalizeDiscoveryFilters(), preferences: normalizeDiscoverySessionPreferences() },
      platform: { location: { current: async () => ({ authorization: 'denied' }) } },
      onApply: query => window.appliedQueries.push(query), onCancel: () => { window.cancelledQueries += 1 },
    }))
    window.renderQueryPanel()
  })
  const dialog = page.getByRole('dialog', { name: '发现筛选', exact: true })
  await dialog.waitFor()
  for (const height of [874, 480]) {
    await page.setViewportSize({ width: 375, height })
    await page.waitForFunction(height => document.querySelector('.modal-backdrop')?.style.getPropertyValue('--modal-viewport-height') === height + 'px', height)
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
    for (const bottom of [false, true]) {
      await dialog.locator('.sticky-action-form__content').evaluate((el, bottom) => { el.scrollTop = bottom ? el.scrollHeight : 0 }, bottom)
      for (const name of ['重置', '取消', '应用']) {
        const bounds = await dialog.getByRole('button', { name, exact: true }).boundingBox()
        assert.ok(bounds && bounds.y >= 0 && bounds.y + bounds.height <= height, name + ' always visible ' + JSON.stringify({bounds,height}))
      }
    }
  }
  await page.setViewportSize({ width: 402, height: 874 })
  await dialog.getByLabel('大家评分', { exact: true }).selectOption('9')
  await dialog.getByLabel('我的记录状态', { exact: true }).selectOption('none')
  await dialog.getByLabel('仅有实拍', { exact: true }).check()
  await dialog.getByRole('button', { name: '重置', exact: true }).click()
  assert.equal(await dialog.getByLabel('大家评分', { exact: true }).inputValue(), '')
  assert.equal(await dialog.getByLabel('我的记录状态', { exact: true }).inputValue(), '')
  assert.equal(await dialog.getByLabel('仅有实拍', { exact: true }).isChecked(), false)
  assert.equal(await dialog.getByLabel('筛选城市', { exact: true }).inputValue(), '杭州')
  assert.equal(await page.evaluate(() => window.appliedQueries.length), 0, 'reset edits draft without applying')
  await dialog.getByLabel('大家评分', { exact: true }).selectOption('9')
  await dialog.getByLabel('评价人数', { exact: true }).selectOption('10')
  await dialog.getByLabel('仅有实拍', { exact: true }).check()
  assert.equal(await page.evaluate(() => window.appliedQueries.length), 0)
  await dialog.getByRole('button', { name: '取消', exact: true }).click()
  assert.equal(await page.evaluate(() => window.appliedQueries.length), 0)
  await page.evaluate(() => window.renderQueryPanel())
  await page.waitForFunction(() => document.querySelector('select[aria-label="大家评分"]')?.value === '')
  assert.equal(await dialog.getByLabel('大家评分', { exact: true }).inputValue(), '')
  await dialog.getByLabel('大家评分', { exact: true }).selectOption('9')
  await dialog.getByLabel('评价人数', { exact: true }).selectOption('10')
  await dialog.getByLabel('仅有实拍', { exact: true }).check()
  await dialog.getByLabel('筛选城市', { exact: true }).fill('上海')
  await dialog.getByRole('button', { name: '应用', exact: true }).click()
  const [query] = await page.evaluate(() => window.appliedQueries)
  assert.equal(query.city, '上海')
  assert.equal(query.filters.minimumPublicScoreOutOfTen, 9)
  assert.equal(query.filters.minimumPublicRatingUsers, 10)
  assert.equal(query.filters.requireActualPhoto, true)
  await page.evaluate(() => window.renderQueryPanel('trending'))
  await page.waitForFunction(() => document.querySelector('select[aria-label="筛选排序"]')?.value === 'trend')
  assert.equal(await dialog.getByText('本次偏好', { exact: true }).count(), 0)
  assert.equal(await dialog.getByLabel('筛选排序', { exact: true }).inputValue(), 'trend')
  await page.evaluate(async () => { await Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))) })
  await page.screenshot({ path: '/tmp/tastemap-discovery-query-panel.png', fullPage: true })
  console.log('PASS: draft cancel/apply, independent public score/count/photo, arbitrary city, mode-specific sort/preferences')
} finally { await browser.close() }
