import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { TasteMapAnalyticsPage } = await import('/src/components/TasteMapAnalyticsPage.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/hybrid/app/hybridShell.css')
    const owner = fixture.profile.user.id
    const restaurants = fixture.restaurants.map(item => ({ ...item, userId: owner, deletedAt: null }))
    const base = restaurants[0].visits[0]
    const visits = [
      ['2025-09-14T12:00:00', 4, 'a'], ['2025-09-19T12:00:00', 3, 'b'],
      ['2026-08-14T12:00:00', 4.5, 'a'], ['2026-08-19T12:00:00', 3.5, 'b'],
      ['2026-09-01T12:00:00', 4, 'a'], ['2026-09-02T12:00:00', 4.5, 'a'],
    ].map(([visitedAt, rating, companion], index) => ({ ...base, id: 'analytics-qa-' + index, userId: owner, restaurantId: restaurants[0].id, visitedAt, updatedAt: visitedAt, deletedAt: null, rating, companionIds: [companion], companions: [companion === 'a' ? '私密饭搭子甲' : '私密饭搭子乙'], note: '绝不进入分享的私人笔记', myActualSpend: 137, paymentMethod: 'self', amountInputMode: 'manual' }))
    const profile = { ...fixture.profile, restaurants, visits, restaurantImages: {}, analyticsIdentity: { ownerUserID: owner, recordOwnerID: owner, companions: ['a', 'b'].map((id, index) => ({ id, ownerUserID: owner, displayName: index ? '私密饭搭子乙' : '私密饭搭子甲', identifiers: [id], deletedAt: null, updatedAt: '2026-09-01' })), sources: [], visitSourceLinks: visits.map(item => ({ visitID: item.id, sourceID: null })) } }
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    window.analyticsShares = []; window.analyticsRestaurantOpens = []
    const platform = { kind: 'native', share: { open: async value => { window.analyticsShares.push(value) } } }
    window.renderAnalytics = (mode, empty = false) => root.render(React.createElement(TasteMapAnalyticsPage, { key: mode + empty, initialMode: mode, singleReport: true, platform, profile: empty ? { ...profile, visits: [], restaurants: [] } : profile, onOpenRestaurant: id => window.analyticsRestaurantOpens.push(id), onBack: () => {} }))
    window.renderAnalytics('taste')
  })
  for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
    await page.setViewportSize({ width, height: 874 }); await page.emulateMedia({ colorScheme })
    await page.locator('.tm-analysis-data').waitFor()
    assert.equal(await page.locator('.tm-analysis-data details, .tm-analysis-data summary').count(), 0)
    assert.equal(await page.locator('.tm-analysis-story__cta').isVisible(), true)
    assert.ok(await page.locator('.tm-analysis-story__feature').count() <= 3)
    assert.equal(await page.locator('[data-analysis-section]').count(), 0)
    const geometry = await page.evaluate(() => ({ overflow: document.documentElement.scrollWidth - innerWidth, font: parseFloat(getComputedStyle(document.querySelector('.tm-analysis-story__lead h2')).fontSize) }))
    assert.ok(geometry.overflow <= 1, JSON.stringify(geometry)); assert.ok(geometry.font >= 14)
    await page.screenshot({ path: `/tmp/tastemap-analytics-data-${width}-${colorScheme}.png` })
  }
  for (const mode of ['taste', 'companion', 'source', 'monthly', 'annual']) {
    await page.evaluate(mode => window.renderAnalytics(mode), mode)
    await page.locator(`[data-analysis-mode="${mode}"] .tm-analysis-data`).waitFor()
    assert.ok(await page.locator('.tm-analysis-story__feature').count() <= 3)
    assert.equal(await page.locator('.tm-analysis-data details, .tm-analysis-data summary').count(), 0)
    assert.equal(await page.locator('[data-analysis-section="source-pitfall-method"]').count(), 0)
    assert.ok(!/计算依据|为什么得出这个结果|历史 Web|稳定 ID|分母/.test(await page.locator('.tm-analysis-data').innerText()))
    await page.screenshot({ path: `/tmp/tastemap-results-${mode}.png`, fullPage: true })
    await page.evaluate(mode => window.renderAnalytics(mode, true), mode)
    await page.waitForFunction(() => document.querySelector('.tm-analysis-data__empty') != null)
    assert.equal(await page.locator('.tm-analysis-story__feature').count(), 0)
    await page.screenshot({ path: `/tmp/tastemap-results-${mode}-empty.png` })
  }
  await page.evaluate(() => window.renderAnalytics('taste'))
  await page.locator('[data-analysis-mode="taste"] .tm-analysis-story__cta').waitFor()
  await page.getByRole('button', { name: '分享数据', exact: true }).click()
  const text = await page.evaluate(() => window.analyticsShares.at(-1).text)
  assert.ok(text.includes('评分习惯') && text.includes('近期与长期口味'))
  assert.ok(!text.includes('私密饭搭子') && !text.includes('绝不进入分享') && !text.includes('¥137'))
  await page.getByRole('tab', { name: '画报', exact: true }).click()
  await page.locator('.poster-zoom-surface img').waitFor()
  const shareCount = await page.evaluate(() => window.analyticsShares.length)
  assert.ok((await page.getByLabel('画报隐私预览').innerText()).includes('本人完整预览'))
  await page.getByRole('button', { name: '预览分享版', exact: true }).click()
  assert.equal(await page.evaluate(() => window.analyticsShares.length), shareCount, 'private preview must never export')
  await page.getByRole('button', { name: '分享画报', exact: true }).click()
  await page.waitForFunction(() => window.analyticsShares.at(-1)?.imageDataURL?.startsWith('data:image/png'))
  assert.ok((await page.evaluate(() => window.analyticsShares.at(-1).imageDataURL)).startsWith('data:image/png'))
  const visibleImage = await page.evaluate(async () => {
    const blob = await (await fetch(document.querySelector('.poster-zoom-surface img').src)).blob()
    return new Promise(resolve => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.readAsDataURL(blob) })
  })
  assert.equal(visibleImage, await page.evaluate(() => window.analyticsShares.at(-1).imageDataURL), 'export must equal the reviewed safe preview byte-for-byte')
  await page.screenshot({ path: '/tmp/tastemap-analytics-poster.png' })
  await page.evaluate(() => window.renderAnalytics('monthly'))
  await page.getByLabel('分析年份').selectOption('2025')
  await page.getByLabel('分析月份').selectOption('9')
  assert.ok((await page.locator('.tm-analysis-data__intro').innerText()).includes('2025 年 9 月'))
  await page.getByRole('tab', { name: '画报', exact: true }).click()
  await page.locator('.poster-zoom-surface img').waitFor()
  await page.getByRole('button', { name: '预览分享版', exact: true }).click()
  await page.getByRole('button', { name: '分享画报', exact: true }).click()
  await page.waitForFunction(() => window.analyticsShares.at(-1)?.text?.includes('2025 年 9 月'))
  assert.ok((await page.evaluate(() => window.analyticsShares.at(-1).text)).includes('2025 年 9 月'))
  await page.getByRole('tab', { name: '数据', exact: true }).click()
  assert.equal(await page.getByLabel('分析年份').inputValue(), '2025')
  await page.evaluate(() => window.renderAnalytics('companion'))
  await page.getByLabel('选择饭搭子').selectOption('b')
  assert.ok((await page.locator('.tm-analysis-story__lead').innerText()).includes('2 顿饭'))
  await page.getByRole('button', { name: '分享数据', exact: true }).click()
  assert.ok(!(await page.evaluate(() => window.analyticsShares.at(-1).text)).includes('私密饭搭子'))
  assert.deepEqual(errors, [])
  console.log('PASS: analytics readable data, 4 viewport/theme cases, period retention, real PNG preview/share, companion switching and private text exclusion')
} finally { await browser.close() }
