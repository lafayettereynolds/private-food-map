import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 }, timezoneId: 'Asia/Shanghai' })
  const errors = []; page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { TasteMapAnalyticsPage } = await import('/src/components/TasteMapAnalyticsPage.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/styles/global.css'); await import('/src/hybrid/app/hybridShell.css')
    const owner = fixture.profile.user.id
    const cuisines = ['日料', '中餐', '西餐', '咖啡', '火锅', '面条']
    const restaurants = Array.from({ length: 36 }, (_, index) => ({ ...fixture.restaurants[0], id: 'r' + index, userId: owner, name: cuisines[index % 6] + '真实测试餐厅' + index, tags: [cuisines[index % 6]], city: index % 3 ? '杭州' : '上海', deletedAt: null, visits: [] }))
    const visits = Array.from({ length: 108 }, (_, index) => ({ ...fixture.restaurants[0].visits[0], id: 'v' + index, userId: owner, restaurantId: 'r' + (index % 36), visibility: index < 36 ? 'private' : 'public',
      visitedAt: (index < 54 ? '2026-08-' : '2026-02-') + String(index % 27 + 1).padStart(2, '0') + 'T' + ['08', '12', '15', '19', '23'][index % 5] + ':00:00+08:00',
      rating: index % 36 < 18 ? 4.5 : 2.5, updatedAt: '2026-09-01', deletedAt: null, diningOccasions: index % 5 ? ['friends'] : ['solo'],
      companionIds: index % 5 ? ['a'] : [], companions: index % 5 ? ['小林'] : [], totalPrice: 200, partySize: 2, paymentMode: 'aa', myActualSpend: 100, photos: [], photoIds: [], dishes: [], note: '测试私人笔记' }))
    const entry = id => ({ id, ownerUserID: owner, displayName: id === 'a' ? '小林' : id === 's1' ? '可靠来源' : '需谨慎的来源', identifiers: [id], deletedAt: null, updatedAt: '2026-09-01' })
    const profile = { ...fixture.profile, restaurants, visits, restaurantImages: {}, analyticsIdentity: { ownerUserID: owner, recordOwnerID: owner, companions: [entry('a')], sources: ['s1', 's2'].map(id => ({ ...entry(id), sourceType: 'friend' })), visitSourceLinks: visits.map(visit => ({ visitID: visit.id, sourceID: Number(visit.restaurantId.slice(1)) < 18 ? 's1' : 's2' })) } }
    document.body.innerHTML = '<div id="test-root"></div>'; window.opens = []; window.shares = []
    createRoot(document.getElementById('test-root')).render(React.createElement(TasteMapAnalyticsPage, { initialMode: 'taste', singleReport: true, profile,
      platform: { kind: 'native', navigation: { openHybrid: async route => window.opens.push(route) }, share: { open: async data => window.shares.push(data) } }, onOpenRestaurant: id => window.opens.push({ restaurant: id }), onBack: () => {} }))
  })
  const current = id => page.locator('[data-explore-page="' + id + '"]:visible')
  const back = async () => { await page.getByRole('button', { name: '返回上一页', exact: true }).click() }
  await current('F01').waitFor()
  await page.waitForLoadState('networkidle')
  for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
    await page.setViewportSize({ width, height: 874 }); await page.emulateMedia({ colorScheme })
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1))
    await page.screenshot({ path: `/tmp/tastemap-explorer-F01-${width}-${colorScheme}.png`, fullPage: true })
  }
  await page.emulateMedia({ colorScheme: 'light' })
  await page.getByRole('button', { name: '查看完整分析', exact: true }).click(); await current('F02').waitFor()
  assert.equal(await page.getByRole('navigation', { name: '分析主题' }).getByRole('button').count(), 5)
  assert.equal(await page.getByText('查看章节', { exact: true }).count(), 0)
  await page.screenshot({ path: '/tmp/tastemap-explorer-F02.png', fullPage: true })
  for (const [label, id] of [['偏好与发现', 'F04'], ['消费与价位', 'F07'], ['时间与变化', 'F10'], ['餐厅与足迹', 'F13'], ['评分与记录', 'F19']]) {
    await current('F02').getByRole('button').filter({ hasText: label }).click(); await current(id).waitFor()
    await page.screenshot({ path: `/tmp/tastemap-explorer-${id}.png`, fullPage: true })
    if (id === 'F04') {
      await page.locator('.tm-explore-ranks button').first().click(); await current('F05').waitFor()
      await page.locator('.tm-explore-bars button').last().click(); await current('F21').waitFor()
      assert.ok((await page.locator('.tm-explore-condition').innerText()).includes('餐厅均分'))
      await back(); await current('F05').waitFor(); await back(); await current('F04').waitFor()
      await page.getByRole('button').filter({ hasText: '常吃按到访；高分按不同餐厅' }).click()
      assert.ok((await page.getByRole('dialog').innerText()).includes('等权汇总'))
      await page.getByRole('button', { name: '关闭', exact: true }).click()
      await current('F04').getByRole('button').filter({ hasText: '菜品与口味' }).click(); await current('F06').waitFor()
      await back(); await current('F04').waitFor()
    }
    if (id === 'F07') {
      await page.getByRole('button').filter({ hasText: '常吃什么价位？' }).click(); await current('F08').waitFor()
      await page.locator('.tm-explore-bars button').nth(2).click(); await current('F09').waitFor()
      assert.ok((await page.locator('.tm-explore-condition').innerText()).includes('100'))
      await back(); await current('F08').waitFor(); await back(); await current('F07').waitFor()
    }
    if (id === 'F10') {
      await page.locator('.tm-explore-bars').first().getByRole('button').nth(1).click(); await current('F21').waitFor()
      const rows = await page.locator('.tm-explore-record').allTextContents(); assert.ok(rows.length > 0); assert.ok(rows.every(row => row.includes('午餐')))
      await page.locator('.tm-explore-record').first().click(); assert.equal(await page.evaluate(() => window.opens.at(-1).surface), 'visit')
      await back(); await current('F10').waitFor()
      await current('F10').getByRole('button').filter({ hasText: '最近，哪里变了' }).click(); await current('F11').waitFor()
      await page.getByRole('button').filter({ hasText: '看更长的轨迹' }).click(); await current('F12').waitFor()
      assert.equal(await current('F12').locator('.tm-explore-timeline>svg').count(), 1)
      await back(); await current('F11').waitFor(); await back(); await current('F10').waitFor()
    }
    if (id === 'F13') {
      await page.getByRole('button').filter({ hasText: '新发现与再回去' }).click(); await current('F14').waitFor()
      await page.getByRole('button').filter({ hasText: '你的代表餐厅' }).click(); await current('F15').waitFor()
      await back(); await current('F14').waitFor(); await back(); await current('F13').waitFor()
    }
    if (id === 'F19') {
      await page.getByRole('button').filter({ hasText: '哪些数据参与了分析' }).click(); await current('F20').waitFor()
      await page.getByRole('button').filter({ hasText: '样本不足时' }).click(); await current('F23').waitFor()
      await back(); await current('F20').waitFor(); await back(); await current('F19').waitFor()
    }
    if (id === 'F16') {
      await page.getByRole('button').filter({ hasText: '哪些来源更合口味' }).click(); await current('S01').waitFor()
      await current('S01').getByRole('button').filter({ hasText: '最坑推荐来源' }).click()
      await current('S03').waitFor()
      await page.screenshot({ path: '/tmp/tastemap-explorer-source-pitfalls.png', fullPage: true })
      await current('S03').locator(':scope > .tm-explore-topic').first().click(); await current('S04').waitFor()
      assert.equal(await page.getByRole('button', { name: '踩坑', exact: true }).getAttribute('aria-pressed'), 'true')
      await back(); await current('S03').waitFor(); await back(); await current('S01').waitFor(); await back(); await current('F16').waitFor()
    }
    await back(); await current('F02').waitFor()
  }
  await page.getByRole('button', { name: '筛选这份档案', exact: true }).click()
  await page.getByRole('button', { name: '最近90天', exact: true }).click()
  await page.getByRole('button', { name: '关闭', exact: true }).click()
  assert.ok((await current('F02').innerText()).includes('全部历史'))
  await page.getByRole('button', { name: '筛选这份档案', exact: true }).click()
  await page.getByRole('button', { name: '最近90天', exact: true }).click()
  await page.getByRole('button', { name: '应用条件', exact: true }).click(); await current('F02').waitFor()
  assert.ok((await current('F02').innerText()).includes('最近 90 天'))
  await page.getByRole('button', { name: '分享口味名片', exact: true }).click(); await current('F24').waitFor()
  await page.locator('.tm-hybrid-poster-preview img').waitFor({ timeout: 60000 })
  const size = await page.locator('.tm-hybrid-poster-preview img').evaluate(img => [img.naturalWidth, img.naturalHeight])
  assert.deepEqual(size, [1080, 1620]); assert.ok((await current('F24').innerText()).includes('仅用公开记录重新分析'))
  await page.screenshot({ path: '/tmp/tastemap-explorer-F24.png', fullPage: true })
  await back(); await current('F02').waitFor()
  assert.deepEqual(errors, []); console.log('PASS: five direct topics, real chart filters, canonical Visit, back state, cancel/apply, public-only 2:3 editorial poster')
} finally { await browser.close() }
