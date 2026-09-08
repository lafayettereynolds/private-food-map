import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, timezoneId: 'Asia/Shanghai' })
  const errors = []; page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { TasteMapAnalyticsPage } = await import('/src/components/TasteMapAnalyticsPage.tsx')
    const { OnThisDayExplorer } = await import('/src/components/OnThisDayExplorer.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/styles/global.css'); await import('/src/hybrid/app/hybridShell.css')
    const owner = fixture.profile.user.id
    const restaurants = Array.from({ length: 36 }, (_, index) => ({ ...fixture.restaurants[0], id: 'r' + index, userId: owner, name: '真实记录餐厅' + index, tags: [index % 2 ? '日料' : '火锅'], city: index % 2 ? '杭州' : '上海', deletedAt: null, visits: [] }))
    const visits = Array.from({ length: 108 }, (_, index) => ({ ...fixture.restaurants[0].visits[0], id: 'v' + index, userId: owner, restaurantId: 'r' + (index % 36), visibility: index % 7 ? 'public' : 'private',
      visitedAt: index < 36 ? '2024-09-07T12:00:00+08:00' : index < 72 ? '2025-09-07T19:00:00+08:00' : `2026-08-${String(index % 28 + 1).padStart(2, '0')}T12:00:00+08:00`,
      rating: index % 36 < 18 ? 4.5 : 2.5, updatedAt: '2026-09-01', deletedAt: null, diningOccasions: ['friends'], companionIds: ['a'], companions: ['私密饭搭子'], totalPrice: 200, partySize: 2, paymentMode: 'aa', myActualSpend: 100, photos: [], photoIds: [], dishes: [], note: '私人笔记不可外发' }))
    const entry = id => ({ id, ownerUserID: owner, displayName: id === 'a' ? '私密饭搭子' : id === 's1' ? '可靠来源' : '原型博主A', identifiers: [id], deletedAt: null, updatedAt: '2026-09-01' })
    const profile = { ...fixture.profile, restaurants, visits, restaurantImages: {}, analyticsIdentity: { ownerUserID: owner, recordOwnerID: owner, companions: [entry('a')], sources: ['s1', 's2'].map(id => ({ ...entry(id), sourceType: 'friend' })), visitSourceLinks: visits.map(visit => ({ visitID: visit.id, sourceID: Number(visit.restaurantId.slice(1)) < 18 ? 's1' : 's2' })) } }
    const platform = { kind: 'native', navigation: { openHybrid: async route => window.opens.push(route) }, share: { open: async data => window.shares.push(data) } }
    document.body.innerHTML = '<div id="test-root"></div>'; window.opens = []; window.shares = []
    const root = createRoot(document.getElementById('test-root'))
    window.mountMode = mode => root.render(mode === 'day' ? React.createElement(OnThisDayExplorer, { key: mode, user: profile.user, restaurants, visits, profile, platform, onOpenRestaurant: id => window.opens.push({ restaurant: id }), onClose: () => {} }) : React.createElement(TasteMapAnalyticsPage, { key: mode, initialMode: mode, singleReport: true, profile, platform, onOpenRestaurant: id => window.opens.push({ restaurant: id }), onBack: () => {} }))
    window.mountMode('source')
  })
  const current = id => page.locator(`[data-explore-page="${id}"]:visible`).first()
  const click = async (id, title) => current(id).getByRole('button').filter({ hasText: title }).first().click()
  const back = async () => page.getByRole('button', { name: '返回上一页', exact: true }).click()
  await current('S01').waitFor(); await click('S01', '最坑推荐来源'); await current('S03').waitFor()
  assert.match(await current('S03').innerText(), /原型博主A/)
  await page.screenshot({ path: '/tmp/tastemap-v2-S03.png', fullPage: true })
  await click('S03', '原型博主A'); await current('S04').waitFor()
  assert.equal(await current('S04').getByRole('button', { name: '踩坑', exact: true }).getAttribute('aria-pressed'), 'true')
  await click('S04', '查看全部餐厅记录'); await current('S06').waitFor(); await current('S06').locator('.tm-explore-topic').first().click(); await current('X01').waitFor()
  assert.equal(await current('X01').locator('.tm-memory-record').count(), 1)
  assert.match(await current('X01').innerText(), /5.0 \/ 10/)
  await current('X01').locator('.tm-memory-record>button').first().click(); assert.equal(await page.evaluate(() => window.opens.at(-1).surface), 'visit')
  await back(); await current('S06').waitFor(); await back(); await current('S04').waitFor()
  await click('S04', '来源擅长什么'); await current('S07').waitFor(); await back()
  await click('S04', '踩坑怎么算'); await current('S05').waitFor(); assert.match(await current('S05').innerText(), /坑率 =/); await back(); await back(); await back(); await current('S01').waitFor()
  await click('S01', '最会种草'); await current('S02').waitFor(); await back()
  await click('S01', '还没去验证'); await current('S08').waitFor(); assert.match(await current('S08').innerText(), /尚不能核验/); await back()
  await click('S01', '全部来源与样本'); await current('S09').waitFor(); await back()
  await click('S01', '生成来源回顾海报'); await current('S10').waitFor(); await current('S10').locator('.tm-hybrid-poster-preview img').waitFor({ timeout: 60000 })
  await click('S10', '查看分享版'); await current('S10').locator('.tm-hybrid-poster-preview img').waitFor({ timeout: 60000 })
  const oldPreview = await current('S10').locator('.tm-hybrid-poster-preview img').getAttribute('src')
  await click('S10', '分享内容与隐私'); await current('X03').waitFor()
  await current('X03').getByRole('button', { name: '显示餐厅名称', exact: true }).click()
  await current('X03').getByRole('button', { name: '使用本人可导出照片', exact: true }).click()
  assert.equal(await current('X03').getByRole('button', { name: '隐藏餐厅名称', exact: true }).getAttribute('aria-pressed'), 'false')
  await page.getByRole('button', { name: '关闭', exact: true }).click()
  await current('S10').locator('.tm-hybrid-poster-preview img').waitFor({ timeout: 60000 })
  assert.notEqual(await current('S10').locator('.tm-hybrid-poster-preview img').getAttribute('src'), oldPreview)
  await click('S10', '选择海报封面'); await current('X02').waitFor(); await page.getByRole('button', { name: '关闭', exact: true }).click()
  await click('S10', '系统分享'); await page.waitForFunction(() => window.shares.length > 0); assert.ok(!(await page.evaluate(() => JSON.stringify(window.shares))).includes('原型博主A'))
  for (const mode of ['monthly', 'annual']) {
    await page.evaluate(mode => window.mountMode(mode), mode)
    const prefix = mode === 'monthly' ? 'M' : 'Y'; await current(prefix + '01').waitFor()
    await click(prefix + '01', '切换历史周期'); await current(prefix + '02').waitFor()
    if (mode === 'monthly') await current('M02').getByRole('button', { name: '8 月', exact: true }).first().click()
    else await current('Y02').getByRole('button', { name: '2025 年', exact: true }).click()
    await current(prefix + '01').waitFor(); await page.waitForLoadState('networkidle')
    await page.screenshot({ path: `/tmp/tastemap-v2-${prefix}01.png`, fullPage: true })
    if (mode === 'monthly') {
      await click('M01', '翻一翻'); await current('M03').waitFor(); assert.equal(await current('M03').locator('.tm-memory-calendar button').count(), 31)
      await current('M03').locator('.has-records').first().click(); await current('M04').waitFor(); assert.ok(await current('M04').locator('.tm-memory-record').count() > 0); await back(); await back()
      await click('M01', '新发现与再回去'); await current('M05').waitFor(); await current('M05').getByRole('button', { name: '再回去', exact: true }).click(); assert.ok(await current('M05').locator('.tm-memory-record').count() > 0); await back()
      await click('M01', '和上个月'); await current('M06').waitFor(); await click('M06', '上一期参与比较'); await current('X01').waitFor(); await back(); await back()
      await click('M01', '支出与同行'); await current('M07').waitFor(); assert.match(await current('M07').innerText(), /个人实际支出/); await back()
    } else {
      await click('Y01', '四季食味'); await current('Y03').waitFor(); await current('Y03').getByRole('button').filter({ hasText: '第 3 季度' }).click(); await click('Y03', '查看本季度记录'); await current('X01').waitFor(); assert.ok(await current('X01').locator('.tm-memory-record').count() > 0); await back(); await back()
      for (const [title, id] of [['年度餐厅','Y04'], ['年度足迹','Y05'], ['这一年的人与来源','Y06'], ['和上一年','Y07']]) { await click('Y01', title); await current(id).waitFor(); await back() }
    }
    await click(prefix + '01', '回忆海报'); await current(prefix + '08').waitFor(); const img = current(prefix + '08').locator('.tm-hybrid-poster-preview img'); await img.waitFor({ timeout: 60000 }); assert.deepEqual(await img.evaluate(item => [item.naturalWidth, item.naturalHeight]), [1080, 1530])
  }
  await page.evaluate(() => window.mountMode('day')); await current('D01').waitFor(); await click('D01', '真实记录餐厅'); await current('D02').waitFor(); await page.screenshot({ path: '/tmp/tastemap-v2-D02.png', fullPage: true }); await click('D02', '生成回忆海报'); await current('D07').waitFor(); await current('D07').locator('.tm-hybrid-poster-preview img').waitFor({ timeout: 60000 }); await back(); await back()
  await click('D01', '不同年份'); await current('D03').waitFor(); await click('D03', '同日记录清单'); await current('D08').waitFor(); await back(); await back()
  await click('D01', '选择回忆日期'); await current('D04').waitFor(); await page.getByLabel('回忆日期', { exact: true }).fill('2026-09-06'); await page.getByRole('button', { name: '查看这一天', exact: true }).click(); await current('D05').waitFor(); await click('D05', '看看附近日期'); await current('D06').waitFor(); assert.match(await current('D06').innerText(), /不是往年同日/)
  assert.deepEqual(errors, []); console.log('PASS V2: S01–S10, M01–M08, Y01–Y08, D01–D08, X01–X03, first-Visit identity, period/day scope, public-safe PNG and canonical Visit handoff')
} finally { await browser.close() }
