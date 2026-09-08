import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 430, height: 932 } })
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridVisitEditorPage } = await import('/src/hybrid/app/HybridVisitEditorPage.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/hybrid/app/hybridShell.css')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const restaurant = fixture.restaurants[0]
    const visit = { ...restaurant.visits[0], restaurantId: restaurant.id, note: '要编辑的原始笔记' }
    restaurant.visits = [visit]
    const detail = { restaurant, editableVisitIDs: [visit.id], capabilities: { canRecordVisit: true } }
    window.probe = { mode: 'deferred', calls: 0, closes: 0, saved: null, detail, visit, restaurant }
    const platform = {
      profile: { getCurrent: async () => {
        window.probe.calls++
        if (window.probe.mode === 'deferred') await new Promise(resolve => { window.probe.finish = resolve })
        return { restaurants: [restaurant], visits: window.probe.mode === 'missing' ? [] : [visit] }
      } },
      restaurant: { get: async () => detail },
      visit: { save: async request => { window.probe.saved = request; return { restaurantID: restaurant.id } } },
    }
    window.showVisitProbe = (key = 'current', visits = []) => root.render(React.createElement('div', { className: 'tm-hybrid-shell', 'data-route': 'visitEdit' }, React.createElement(HybridVisitEditorPage, { key, platform, visitID: visit.id, restaurants: [], visits, onClose: () => window.probe.closes++, onSaved: () => {} })))
    window.showVisitProbe()
  })
  await page.getByRole('heading', { name: '正在读取到访记录', exact: true }).waitFor()
  assert.equal(await page.getByText('无法打开到访记录', { exact: true }).count(), 0)
  const back = page.getByRole('button', { name: '返回上一页', exact: true })
  assert.equal(await back.count(), 1)
  await back.click()
  assert.equal(await page.evaluate(() => window.probe.closes), 1)
  await page.evaluate(() => { window.probe.mode = 'ready'; window.probe.finish() })
  await page.getByRole('heading', { name: '编辑到访记录', exact: true }).waitFor()
  const note = page.getByRole('textbox', { name: '到访笔记', exact: true })
  assert.equal(await note.inputValue(), '要编辑的原始笔记')
  await note.fill('尚未保存的本地草稿')
  await page.evaluate(() => window.showVisitProbe('current', [{ ...window.probe.visit, note: '后台新快照' }]))
  assert.equal(await note.inputValue(), '尚未保存的本地草稿')
  await page.screenshot({ path: '/tmp/tastemap-visit-edit-recovered.png', fullPage: false })
  await page.evaluate(() => { window.probe.mode = 'missing'; window.showVisitProbe('missing') })
  await page.getByRole('heading', { name: '无法打开到访记录', exact: true }).waitFor()
  assert.equal(await page.getByRole('button', { name: '保存修改', exact: true }).count(), 0)
  assert.equal(await page.getByText('正在读取餐厅…', { exact: true }).count(), 0)
  await page.screenshot({ path: '/tmp/tastemap-visit-edit-retry.png', fullPage: false })
  await page.evaluate(() => { window.probe.mode = 'ready' })
  await page.getByRole('button', { name: '重试', exact: true }).click()
  await page.getByRole('heading', { name: '编辑到访记录', exact: true }).waitFor()
  assert.equal(await note.inputValue(), '要编辑的原始笔记')
  await page.getByRole('button', { name: '保存修改', exact: true }).click()
  await page.waitForFunction(() => window.probe.saved !== null)
  assert.equal(await page.evaluate(() => window.probe.saved.visitID), await page.evaluate(() => window.probe.visit.id))
  console.log('PASS Visit editor runtime: stale profile recovery, original draft, retained draft, honest loading/error, back, retry, exact edit write identity')
} finally { await browser.close() }
