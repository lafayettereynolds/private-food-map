import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 430, height: 932 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridAppShell } = await import('/src/hybrid/app/HybridAppShell.tsx')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    document.getElementById('root').remove()
    window.history.replaceState(null, '', '#/profile')
    const host = document.body.appendChild(document.createElement('div'))
    host.id = 'snapshot-refresh-probe'
    const restaurant = { ...fixture.profile.restaurants[0], name: '刷新验证餐厅', visits: [fixture.profile.visits[0]] }
    const wanted = { ...fixture.profile.restaurants.find(item => item.status === 'wantToGo'), name: '仍然想吃餐厅' }
    const profile = { ...fixture.profile, restaurants: [restaurant, wanted], visits: restaurant.visits }
    const content = { ...fixture.content, lists: [], discovery: { ...fixture.content.discovery, forYou: [{ ...fixture.content.discovery.forYou[0], restaurant: { ...fixture.content.discovery.forYou[0].restaurant, name: restaurant.name } }] } }
    const listeners = new Set()
    window.probe = { profile, content, mode: 'ready', pendingProfiles: [], pendingContent: [], bootCalls: 0, saves: [], sequence: 0 }
    const emit = (name, payload) => listeners.forEach(listener => listener({ version: 1, sequence: ++window.probe.sequence, name, payload }))
    window.emitProbe = emit
    const platform = {
      kind: 'browser',
      runtime: { info: async () => { window.probe.bootCalls++; return { bridgeVersion: 1, dataSource: 'isolated-runtime-probe' } } },
      auth: { sessionStatus: async () => ({ state: 'authenticated', userID: window.probe.profile.user.id }) },
      events: { subscribe: async listener => { listeners.add(listener); return { remove: async () => listeners.delete(listener) } } },
      profile: { getCurrent: async () => {
        if (window.probe.mode === 'deferred') return new Promise(resolve => window.probe.pendingProfiles.push(resolve))
        return structuredClone(window.probe.profile)
      } },
      content: { snapshot: async () => {
        if (window.probe.mode !== 'ready') return new Promise((resolve, reject) => window.probe.pendingContent.push({ resolve, reject }))
        return structuredClone(window.probe.content)
      } },
      restaurant: { get: async id => {
        const value = window.probe.profile.restaurants.find(item => item.id === id)
        return { restaurant: structuredClone(value), image: fixture.profile.restaurantImages[id], editableVisitIDs: value.visits.map(visit => visit.id), viewerState: value.status === 'visited' ? 'visited' : 'want_to_go', capabilities: { canRecordVisit: true, canEditRestaurant: true, canDeleteRestaurant: true, canShare: true, canAddToWantToGo: true, canAddToRoulette: true, canAddToList: true } }
      } },
      visit: { save: async request => {
        window.probe.saves.push(request)
        const value = window.probe.profile.restaurants.find(item => item.id === request.restaurantID)
        const original = value.visits.find(visit => visit.id === request.visitID) ?? value.visits[0]
        const visit = { ...original, ...request.draft, id: request.visitID ?? 'runtime-new-visit', restaurantId: value.id }
        value.visits = request.visitID ? value.visits.map(item => item.id === visit.id ? visit : item) : [visit, ...value.visits]
        window.probe.profile.visits = window.probe.profile.restaurants.flatMap(item => item.visits)
        emit('data.changed', { reason: 'visitSaved' })
        return { restaurantID: value.id }
      } },
      haptics: { selection: async () => {} },
      navigation: { openNative: async () => {}, openHybrid: async () => {} },
    }
    createRoot(host).render(React.createElement(HybridAppShell, { platform }))
  })
  const host = page.locator('#snapshot-refresh-probe')
  const footprints = host.locator('.profile-taste-footprints-preview__row')
  await host.getByRole('heading', { name: '味觉足迹', exact: true }).waitFor()
  assert.equal(await footprints.count(), 2, 'Initial private footprint contains Visit and WantToGo')
  await page.evaluate(() => {
    window.originalShell = document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')
    window.originalProfile = document.querySelector('#snapshot-refresh-probe .profile-dashboard')
    const source = window.probe.profile.visits[0]
    const added = { ...source, id: 'fresh-unrated-visit', rating: null, visitedAt: '2026-09-06T10:00:00Z' }
    window.probe.profile = { ...window.probe.profile, visits: [added, source] }
    window.probe.mode = 'content-pending'
    window.emitProbe('data.changed', { reason: 'visitSaved' })
  })
  await page.waitForFunction(() => document.querySelectorAll('#snapshot-refresh-probe .profile-taste-footprints-preview__row').length === 3)
  assert.equal(await page.evaluate(() => window.probe.pendingContent.length), 1)
  assert.equal(await page.evaluate(() => window.originalShell === document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')), true)
  assert.equal(await page.evaluate(() => window.originalProfile === document.querySelector('#snapshot-refresh-probe .profile-dashboard')), true)
  assert.equal(await page.evaluate(() => window.probe.bootCalls), 1)
  await page.evaluate(() => window.probe.pendingContent.shift().reject(new Error('independent feed offline')))
  await host.getByRole('button', { name: '重试刷新', exact: true }).waitFor()
  assert.equal(await footprints.count(), 3)
  await page.evaluate(() => { window.probe.mode = 'ready' })
  await host.getByRole('button', { name: '重试刷新', exact: true }).click()
  await host.getByRole('button', { name: '重试刷新', exact: true }).waitFor({ state: 'detached' })

  // Two real shell events: the older request must not overwrite the later one.
  await page.evaluate(() => { window.probe.mode = 'deferred'; window.emitProbe('data.changed', { reason: 'first' }); window.emitProbe('data.changed', { reason: 'second' }) })
  await page.waitForFunction(() => window.probe.pendingProfiles.length === 2)
  await page.evaluate(() => {
    const fresh = structuredClone(window.probe.profile)
    fresh.user.nickname = '最新刷新结果'
    window.probe.pendingProfiles[1](fresh)
    window.probe.pendingContent[1].resolve(window.probe.content)
  })
  await host.getByText('最新刷新结果', { exact: true }).waitFor()
  await page.evaluate(() => {
    const stale = structuredClone(window.probe.profile)
    stale.user.nickname = '不应返回的旧快照'
    window.probe.pendingProfiles[0](stale)
    window.probe.pendingContent[0].resolve(window.probe.content)
    window.probe.pendingProfiles = []; window.probe.pendingContent = []; window.probe.mode = 'ready'
  })
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await host.getByText('不应返回的旧快照', { exact: true }).count(), 0)

  // Use the actual Discovery action, preserve its mounted DOM, and save while its refresh is stalled.
  await host.getByRole('button', { name: '发现', exact: true }).click()
  await host.locator('.tm-activity-card').first().waitFor()
  await page.evaluate(() => { window.originalDiscovery = document.querySelector('#snapshot-refresh-probe .tm-hybrid-discovery') })
  await host.getByRole('button', { name: /^(再次添加|记录到访|加入餐厅) 刷新验证餐厅$/ }).click()
  await page.getByRole('heading', { name: '记录一次到访', exact: true }).waitFor()
  await page.getByRole('textbox', { name: '到访笔记', exact: true }).fill('保存后无需等待发现请求')
  await page.evaluate(() => { window.probe.mode = 'content-pending' })
  await page.getByRole('button', { name: '保存到我的地图', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')?.dataset.route === 'discovery')
  assert.equal(await page.evaluate(() => window.probe.saves.length), 1)
  assert.equal(await page.evaluate(() => window.probe.pendingContent.length > 0), true)
  assert.equal(await page.evaluate(() => window.originalDiscovery === document.querySelector('#snapshot-refresh-probe .tm-hybrid-discovery')), true)
  assert.equal(await page.evaluate(() => window.probe.bootCalls), 1)
  await host.getByRole('button', { name: '我的', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')?.dataset.route === 'profile')
  assert.equal(await footprints.count(), 3)
  await host.getByRole('heading', { name: '味觉足迹', exact: true }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: '/tmp/tastemap-snapshot-refresh-profile.png', fullPage: false })

  // Profile → Detail → Edit → Save completes one editor history entry.
  await footprints.first().click()
  await host.locator('[data-product-contract="visit-edit-entry"]').first().waitFor()
  await host.locator('[data-product-contract="visit-edit-entry"]').first().click()
  await page.getByRole('heading', { name: '编辑到访记录', exact: true }).waitFor()
  await page.getByRole('textbox', { name: '到访笔记', exact: true }).fill('修改后返回原餐厅，随后返回我的')
  await page.getByRole('button', { name: '保存修改', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')?.dataset.route === 'restaurant')
  await host.getByRole('button', { name: '返回上一页', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')?.dataset.route === 'profile')
  assert.equal(await page.getByRole('heading', { name: '编辑到访记录', exact: true }).count(), 0)
  assert.equal(await page.evaluate(() => window.probe.saves[1].visitID), 'runtime-new-visit')
  assert.equal(await page.evaluate(() => window.probe.bootCalls), 1)

  // An externally restored editor has no remembered parent: replace it on save.
  await page.evaluate(() => {
    window.history.replaceState(null, '', '#/visitEdit/runtime-new-visit')
    window.dispatchEvent(new PopStateEvent('popstate'))
  })
  await page.getByRole('heading', { name: '编辑到访记录', exact: true }).waitFor()
  const historyLength = await page.evaluate(() => window.history.length)
  await page.getByRole('button', { name: '保存修改', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('#snapshot-refresh-probe .tm-hybrid-shell')?.dataset.route === 'restaurant')
  assert.equal(await page.evaluate(() => window.history.length), historyLength)
  assert.equal(await page.getByRole('heading', { name: '编辑到访记录', exact: true }).count(), 0)
  await host.getByRole('button', { name: '我的', exact: true }).click()

  // Account bootstrap invalidates still-pending prior-owner snapshots.
  await page.evaluate(() => {
    window.probe.mode = 'deferred'
    window.emitProbe('data.changed', { reason: 'beforeAccountChange' })
  })
  await page.waitForFunction(() => window.probe.pendingProfiles.length === 1)
  await page.evaluate(() => {
    window.probe.profile = { ...window.probe.profile, user: { ...window.probe.profile.user, id: 'tm_runtime_other_owner', nickname: '切换后的账户' }, restaurants: [], visits: [] }
    window.probe.mode = 'ready'
    window.emitProbe('auth.changed', { state: 'authenticated' })
  })
  await host.getByText('切换后的账户', { exact: true }).waitFor()
  await page.evaluate(() => {
    window.probe.pendingProfiles[0]({ ...window.probe.profile, user: { ...window.probe.profile.user, nickname: '旧账户泄漏' } })
    window.probe.pendingContent.forEach(request => request.resolve(window.probe.content))
  })
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  assert.equal(await host.getByText('旧账户泄漏', { exact: true }).count(), 0)
  assert.equal(await footprints.count(), 0)
  assert.equal(await page.evaluate(() => window.probe.bootCalls), 2)
  assert.deepEqual(errors, [])
  console.log('PASS full Hybrid shell: immediate owner footprint refresh while feed pending; retained DOM; recoverable partial failure; retry; stale-response rejection; saved Discovery return without feed wait; Detail edit/save/back returns Profile; cold editor replaces its history entry; auth invalidates old owner')
} finally { await browser.close() }
