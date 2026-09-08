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
    const { TasteMapListsPage } = await import('/src/components/TasteMapListsPage.tsx')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const probe = window.listProbe = { gets: [], shares: [], opened: [], back: 0, pending: null, public: true }
    const rows = offset => Array.from({ length: 2 }, (_, index) => ({ id: `row-${offset + index}`, name: `真实投影测试 ${offset + index}`,
      address: '隔离测试地址', city: '测试城市', position: offset + index, note: '保留备注', coordinate: { latitude: 0, longitude: offset + index },
      rating: offset + index === 0 ? { valueOutOfTen: 9, source: 'viewer', sampleCount: 2 }
        : offset + index === 1 ? { valueOutOfTen: 8.5, source: 'public', sampleCount: 10 } : null,
      image: { kind: 'foodDiningFallback', stableSeed: `row-${offset + index}`, accessibilityLabel: '测试图示' } }))
    const list = { id: 'list-only', title: '食单读取测试', description: '保留食单说明', visibility: 'public', isRanked: true, isOwnedByViewer: true,
      ownerName: '测试用户', restaurantCount: 4, restaurants: rows(0), updatedAt: 'v1' }
    const platform = {
      events: { subscribe: async handler => { probe.emit = handler; return { remove: async () => {} } } },
      navigation: { openNative: async () => {} },
      lists: {
        get: async request => {
          probe.gets.push(request)
          if (!probe.public) throw Object.assign(new Error('这份食单已不可访问'), { code: 'list_unavailable' })
          return { list: { ...list, restaurants: rows(request.cursor ? 2 : 0) }, nextCursor: request.cursor ? null : 'opaque-page-two', generatedAt: 'now' }
        },
        createShareLink: async id => { probe.createdFor = id; return { url: `https://example.test/share/${'a'.repeat(32)}` } },
      },
      share: { open: async value => { probe.shares.push(value) } },
    }
    root.render(React.createElement(TasteMapListsPage, { lists: [], initialSelectedID: 'list-only', platform,
      onOpenRestaurant: id => probe.opened.push(id), onInitialDetailBack: () => probe.back++ }))
  })
  await page.getByRole('heading', { name: '食单读取测试' }).waitFor()
  assert.equal(await page.locator('.tm-hybrid-ranked-list > li').count(), 2)
  assert.equal(await page.getByText('我的评分 9.0 / 10 · 2 个评分', { exact: true }).count(), 1)
  assert.equal(await page.getByText('公开评分 8.5 / 10 · 10 个评分', { exact: true }).count(), 1)
  await page.getByRole('button', { name: /继续加载餐厅/ }).click()
  await page.waitForFunction(() => document.querySelectorAll('.tm-hybrid-ranked-list > li').length === 4)
  assert.equal(await page.getByText('暂无评分', { exact: true }).count(), 2)
  await page.locator('.tm-hybrid-ranked-list > li').last().getByRole('button').click()
  assert.deepEqual(await page.evaluate(() => window.listProbe.opened), ['row-3'])
  await page.getByRole('button', { name: '分享', exact: true }).click()
  await page.getByRole('button', { name: '分享链接', exact: true }).waitFor()
  assert.equal(await page.evaluate(() => window.listProbe.shares.length), 0)
  await page.getByRole('button', { name: '分享链接', exact: true }).click()
  assert.deepEqual(await page.evaluate(() => window.listProbe.shares), [{ title: '食单读取测试', url: `https://example.test/share/${'a'.repeat(32)}` }])
  await page.evaluate(() => { window.listProbe.public = false; window.listProbe.emit({ name: 'data.changed' }) })
  await page.getByRole('heading', { name: '食单暂时不可用' }).waitFor()
  assert.equal(await page.locator('.tm-hybrid-ranked-list > li').count(), 0)
  assert.equal(await page.getByRole('button', { name: '分享链接', exact: true }).count(), 0)
  await page.getByRole('button', { name: '返回上一页', exact: true }).click()
  assert.equal(await page.evaluate(() => window.listProbe.back), 1)
  assert.deepEqual(errors, [])
  console.log('PASS shared List uncached read, exact rating origins/nil, full pagination, actual URL share, permission revocation and reachable back. Isolated adapter data only; not installed/native UI acceptance.')
} finally { await browser.close() }
