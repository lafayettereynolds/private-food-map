import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 }, timezoneId: 'Asia/Shanghai' })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { TasteMapAnalyticsPage } = await import('/src/components/TasteMapAnalyticsPage.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/styles/global.css')
    await import('/src/hybrid/app/hybridShell.css')
    const owner = fixture.profile.user.id
    const names = ['山葵小料理', '小满食堂', '河岸牛排馆', '树影咖啡', '红炉火锅', '兰州牛肉面']
    const cuisines = ['日料', '中餐', '西餐', '咖啡', '火锅', '面条']
    const restaurants = Array.from({ length: 18 }, (_, index) => ({ ...fixture.restaurants[0], id: 'r' + index, userId: owner, name: names[index % 6] + (index >= 6 ? ' · 湖滨店 ' + index : ''), tags: [cuisines[index % 6]], city: index % 3 ? '杭州' : '上海', deletedAt: null, visits: [] }))
    const visits = Array.from({ length: 72 }, (_, index) => ({ ...fixture.restaurants[0].visits[0], id: 'v' + index, userId: owner, restaurantId: 'r' + (index % 18),
      visitedAt: (index < 36 ? '2026-08-' : '2026-02-') + String(index % 27 + 1).padStart(2, '0') + 'T' + [8, 12, 15, 19, 23][index % 5] + ':00:00+08:00',
      rating: index % 6 === 0 ? 4.5 : 4, updatedAt: '2026-09-01', deletedAt: null, diningOccasions: index % 5 ? ['friends'] : ['solo'],
      companionIds: index % 5 ? ['a'] : [], companions: index % 5 ? ['小林'] : [], myActualSpend: 137, photos: [], photoIds: [], dishes: [], note: '绝不进入默认分享的笔记' }))
    // Keep all times valid ISO, including single-digit breakfast hours.
    visits.forEach(visit => { visit.visitedAt = visit.visitedAt.replace('T8:', 'T08:') })
    const directory = id => ({ id, ownerUserID: owner, displayName: id === 'a' ? '小林' : id === 's1' ? '阿哲' : '朋友的食单', identifiers: [id], deletedAt: null, updatedAt: '2026-09-01' })
    const profile = { ...fixture.profile, restaurants, visits, restaurantImages: {}, analyticsIdentity: { ownerUserID: owner, recordOwnerID: owner, companions: [directory('a')], sources: ['s1', 's2'].map(id => ({ ...directory(id), sourceType: 'friend' })), visitSourceLinks: visits.map(visit => ({ visitID: visit.id, sourceID: Number(visit.restaurantId.slice(1)) < 9 ? 's1' : 's2' })) } }
    document.body.innerHTML = '<div id="test-root"></div>'
    const root = createRoot(document.getElementById('test-root'))
    window.opens = []; window.shares = []
    window.renderStory = (mode, empty = false) => root.render(React.createElement(TasteMapAnalyticsPage, { key: mode + empty, initialMode: mode, singleReport: true,
      platform: { kind: 'native', share: { open: async value => window.shares.push(value) } },
      profile: empty ? { ...profile, visits: [], restaurants: [] } : profile, onOpenRestaurant: id => window.opens.push(id), onBack: () => {} }))
  })
  const results = []
  for (const mode of ['taste', 'monthly', 'annual', 'companion', 'source']) {
    await page.evaluate(mode => window.renderStory(mode), mode)
    await page.locator('[data-analysis-mode="' + mode + '"]').waitFor()
    if (mode === 'monthly') await page.getByLabel('分析月份').selectOption('8')
    await page.locator('.tm-analysis-story__cta').waitFor()
    assert.equal(await page.locator('[data-analysis-section]').count(), 0)
    assert.ok(await page.locator('.tm-analysis-story__feature').count() <= 1)
    assert.ok(await page.locator('.tm-analysis-story__categories button').count() <= 4)
    assert.ok(await page.locator('.tm-analysis-story__sources>button').count() <= 3)
    if (['monthly', 'annual', 'companion'].includes(mode)) assert.equal(await page.locator('.tm-analysis-story__facts>div').count(), 4)
    for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
      await page.setViewportSize({ width, height: 874 }); await page.emulateMedia({ colorScheme })
      const geometry = await page.evaluate(() => ({ overflow: document.documentElement.scrollWidth - innerWidth, height: document.querySelector('.tm-analysis-data').getBoundingClientRect().height, headlineSize: parseFloat(getComputedStyle(document.querySelector('.tm-analysis-story__lead h2')).fontSize) }))
      assert.ok(geometry.overflow <= 1, JSON.stringify(geometry))
      assert.ok(geometry.height < 1748, JSON.stringify(geometry))
      assert.ok(geometry.headlineSize >= 24)
      await page.screenshot({ path: '/tmp/tastemap-story-' + mode + '-' + width + '-' + colorScheme + '.png', fullPage: true })
      results.push({ mode, width, colorScheme, ...geometry })
    }
    if (mode === 'taste') {
      await page.getByRole('button', { name: '高分', exact: true }).click()
      await page.waitForFunction(() => document.querySelector('.tm-analysis-story__categories')?.textContent?.includes('/ 10')).catch(async error => { console.error(await page.locator('.tm-analysis-data').innerText(), errors); throw error })
      assert.ok((await page.locator('.tm-analysis-story__categories').innerText()).includes('/ 10'))
      await page.locator('.tm-analysis-story__categories button').first().click()
      assert.equal(await page.locator('[data-analysis-section]').count(), 1)
      assert.ok((await page.locator('[data-analysis-section]').innerText()).includes('有效评分'))
      await page.getByRole('button', { name: '返回报告首页' }).click()
    }
    if (mode === 'source') {
      assert.equal(await page.locator('.tm-analysis-story__hero,.tm-analysis-story__collage').count(), 0)
      await page.locator('.tm-analysis-story__sources>button').first().click()
      assert.ok((await page.locator('[data-analysis-section]').innerText()).includes('已验证且评分餐厅'))
      await page.getByRole('button', { name: '返回报告首页' }).click()
      const second = page.locator('.tm-analysis-story__sources>button').nth(1)
      const sourceName = await second.locator('strong').innerText()
      await second.click()
      await page.waitForFunction(name => document.querySelector('[data-analysis-section] h2')?.textContent === name, sourceName)
      assert.ok((await page.getByLabel('选择推荐来源').locator('option:checked').innerText()).includes(sourceName), 'source drill-in must update the report and poster selection')
      await page.getByRole('button', { name: '返回报告首页' }).click()
    }
    await page.locator('.tm-analysis-story__cta').click()
    assert.equal(await page.locator('[data-analysis-section]').count(), 1)
    const themes = await page.locator('.tm-analysis-detail__topics button').count()
    for (let index = 0; index < themes; index++) {
      await page.locator('.tm-analysis-detail__topics button').nth(index).click()
      assert.equal(await page.locator('[data-analysis-section]').count(), 1)
    }
    assert.ok((await page.locator('[data-analysis-section]').innerText()).includes('原始记录'))
    await page.locator('.tm-analysis-data__row').first().click()
    assert.ok(await page.evaluate(() => window.opens.length > 0))
    await page.getByRole('button', { name: '返回报告首页' }).click()
    assert.equal(await page.locator('[data-analysis-section]').count(), 0)
    await page.evaluate(mode => window.renderStory(mode, true), mode)
    await page.waitForFunction(() => document.querySelector('[data-report-state="empty"]') != null)
    assert.equal(await page.locator('.tm-analysis-story__categories button').count(), 0)
  }
  assert.deepEqual(errors, [])
  console.log(JSON.stringify({ status: 'PASS', cases: results, checks: 'short homes, sample gates, lens, source drill-in, one detail at a time, all original records, restaurant action, empty states' }, null, 2))
} finally { await browser.close() }
