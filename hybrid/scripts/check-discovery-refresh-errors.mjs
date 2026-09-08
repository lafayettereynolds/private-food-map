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
    const { HybridAppShell } = await import('/src/hybrid/app/HybridAppShell.tsx')
    const { TasteMapNativeAdapter } = await import('/src/platform/TasteMapNativeAdapter.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    const profile = { ...fixture.profile, restaurants: fixture.profile.restaurants.map(item => ({
      ...item, referencePrice: item.averagePricePerPerson, image: fixture.profile.restaurantImages[item.id],
      visits: item.visits.map(visit => ({ ...visit, photos: [], dishes: [] })),
    })) }
    const content = structuredClone(fixture.content)
    content.discovery.forYou = [content.discovery.forYou[0]]
    content.discovery.forYou[0].restaurant.name = '容量失败保留的真实缓存样例'
    const issue = { code: 'DISCOVERY_AGGREGATE_CAPACITY', message: '当前城市的发现数据超出完整统计容量，请稍后重试。未返回不完整榜单。', recoverable: true, details: { status: 503 } }
    const cached = { state: 'cached', city: '杭州', windowDays: 7, sourceGeneratedAt: '2026-09-01T00:00:00Z', attemptedAt: '2026-09-06T00:00:00Z', issue }
    content.discovery.refreshStatus = { for_you: cached }
    window.probe = { content, profile, requests: [], issue, cached, likes: [], sequence: 0, listeners: new Set() }
    window.emitProbe = () => window.probe.listeners.forEach(listener => listener({ version: 1, sequence: ++window.probe.sequence, name: 'data.changed', payload: { reason: 'error-regression' } }))
    const plugin = {
      addListener: async (_name, listener) => { window.probe.listeners.add(listener); return { remove: async () => window.probe.listeners.delete(listener) } },
      invoke: async ({ request }) => {
        window.probe.requests.push(structuredClone(request))
        let result
        switch (request.method) {
          case 'runtime.info': result = { bridgeVersion: 1, dataSource: 'isolated-bridge-error-probe', supportedCapabilities: {} }; break
          case 'auth.sessionStatus': result = { state: 'authenticated', userID: profile.user.id }; break
          case 'profile.getCurrent': result = structuredClone(window.probe.profile); break
          case 'content.snapshot': result = structuredClone(window.probe.content); break
          case 'navigation.openHybrid': result = { route: request.payload, canGoBack: true }; break
          case 'navigation.back': result = { route: { surface: 'discovery' }, canGoBack: false }; break
          case 'community.setLike': window.probe.likes.push(request.payload); result = { likedByViewer: request.payload.liked, likeCount: 24, commentCount: 2 }; break
          case 'restaurant.get': {
            const restaurant = profile.restaurants.find(item => item.id === request.payload.id)
            result = { restaurant, editableVisitIDs: restaurant.visits.map(visit => visit.id), viewerState: 'visited', capabilities: { canRecordVisit: true, canEditRestaurant: true } }
            break
          }
          default: result = {}
        }
        return { version: 1, requestId: request.requestId, result }
      },
    }
    document.getElementById('root').remove()
    window.history.replaceState(null, '', '#/discovery')
    const host = document.body.appendChild(document.createElement('div'))
    host.id = 'discovery-error-probe'
    createRoot(host).render(React.createElement(HybridAppShell, { platform: new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: plugin } } }) }))
  })
  const host = page.locator('#discovery-error-probe')
  const cards = host.locator('.tm-activity-card')
  await host.getByRole('button', { name: '重试刷新', exact: true }).waitFor({ timeout: 10_000 }).catch(async error => {
    console.error({ errors, text: await page.locator('body').innerText(), requests: await page.evaluate(() => window.probe?.requests.map(item => item.method)) })
    throw error
  })
  assert.equal(await cards.count(), 1, 'Cached cards remain visible when remote refresh fails')
  assert.match(await host.innerText(), /正在显示上次缓存/)
  assert.equal(await host.getByText('推荐证据还不够', { exact: true }).count(), 0)
  await page.screenshot({ path: '/tmp/tastemap-discovery-capacity-cached-402.png' })
  await host.getByRole('button', { name: '重试刷新', exact: true }).click()
  await page.waitForFunction(() => window.probe.requests.filter(item => item.method === 'content.snapshot').length === 2)
  assert.equal(await page.evaluate(() => window.probe.requests.filter(item => item.method === 'content.snapshot').at(-1).payload.forceRefresh), true)
  assert.equal(await cards.count(), 1)
  await page.evaluate(() => {
    window.originalDiscovery = document.querySelector('#discovery-error-probe .tm-hybrid-discovery')
    window.probe.content.discovery.refreshStatus.for_you = { ...window.probe.cached, state: 'fresh', sourceGeneratedAt: 'new', issue: null }
  })
  await host.getByRole('button', { name: '重试刷新', exact: true }).click()
  await host.getByRole('button', { name: '重试刷新', exact: true }).waitFor({ state: 'detached' })
  assert.equal(await page.evaluate(() => window.originalDiscovery === document.querySelector('#discovery-error-probe .tm-hybrid-discovery')), true)

  // A refresh issue cannot unmount an active Visit editor or lose its text.
  await host.getByRole('button', { name: /^(再次添加|记录到访|加入餐厅) 容量失败保留的真实缓存样例$/ }).click()
  const note = page.getByRole('textbox', { name: '到访笔记', exact: true })
  await note.fill('容量失败时保留未保存的到访草稿')
  await page.evaluate(() => {
    window.originalNote = document.querySelector('[aria-label="到访笔记"]')
    window.probe.content.discovery.refreshStatus.for_you = window.probe.cached
    window.emitProbe()
  })
  await host.getByRole('button', { name: '重试刷新', exact: true }).waitFor()
  assert.equal(await note.inputValue(), '容量失败时保留未保存的到访草稿')
  assert.equal(await page.evaluate(() => window.originalNote === document.querySelector('[aria-label="到访笔记"]')), true)
  page.once('dialog', dialog => dialog.accept())
  await page.getByRole('dialog').getByRole('button', { name: '关闭', exact: true }).click()

  // Structured unavailable is an error, whereas successful empty is ordinary evidence insufficiency.
  await page.evaluate(() => {
    window.probe.content.discovery.forYou = []
    window.probe.content.discovery.refreshStatus.for_you = { ...window.probe.cached, state: 'unavailable', sourceGeneratedAt: null }
    window.emitProbe()
  })
  await host.getByRole('heading', { name: '发现内容暂未更新', exact: true }).waitFor()
  assert.equal(await host.getByText('推荐证据还不够', { exact: true }).count(), 0)
  await page.screenshot({ path: '/tmp/tastemap-discovery-capacity-empty-402.png' })
  await page.evaluate(() => { window.probe.content.discovery.refreshStatus.for_you = { ...window.probe.cached, state: 'fresh', issue: null }; window.emitProbe() })
  await host.getByRole('heading', { name: '推荐证据还不够', exact: true }).waitFor()
  assert.equal(await host.getByRole('button', { name: '重试刷新', exact: true }).count(), 0)

  // A forbidden mode must not expose stale protected cards or pretend retry fixes membership.
  await page.evaluate(() => {
    window.probe.content.discovery.refreshStatus.similar_taste = { ...window.probe.cached, state: 'restricted', sourceGeneratedAt: null,
      issue: { code: 'discovery_access_required', message: '这部分发现内容需要相应的访问权限。', recoverable: false, details: { status: 403 } } }
    window.emitProbe()
  })
  await host.getByRole('tab', { name: '同味之选', exact: true }).click()
  await host.getByRole('heading', { name: '暂时无法访问这部分发现内容', exact: true }).waitFor()
  assert.equal(await cards.count(), 0)
  assert.equal(await host.getByRole('button', { name: '重试', exact: true }).count(), 0)
  assert.equal(await host.getByRole('button', { name: '重试刷新', exact: true }).count(), 0)
  await page.screenshot({ path: '/tmp/tastemap-discovery-restricted-402.png' })
  // Recovering the permitted mode preserves authoritative interaction calls.
  await page.evaluate(() => { window.probe.content.discovery.refreshStatus.similar_taste = window.probe.cached; window.emitProbe() })
  await cards.first().waitFor()
  await cards.first().getByRole('button', { name: /^(取消点赞|点赞) / }).click()
  await page.waitForFunction(() => window.probe.likes.length === 1)
  assert.equal(await cards.first().getByRole('button', { name: /^(取消点赞|点赞) / }).innerText(), '24')
  assert.deepEqual(errors, [])
  console.log('PASS actual Native adapter envelopes → full Hybrid shell: capacity issue keeps cached card and Visit draft; explicit repeated retry is forced; success clears issue without remount; unavailable differs from genuine empty; 403 hides protected cards and misleading retries; recovered mode retains authoritative Like actions.')
} finally { await browser.close() }
